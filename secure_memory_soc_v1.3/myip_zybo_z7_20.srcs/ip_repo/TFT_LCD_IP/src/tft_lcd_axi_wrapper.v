`timescale 1ns / 1ps

/**
 * 동작 흐름:
 *   1. 사용자가 LCD에 숫자 그리기
 *   2. Zynq 버튼 인터럽트 → CPU가 DST_ADDR, TRF_LEN 설정 후 CTRL[0]=1
 *   3. pen_lock 활성화 → 터치 입력 차단
 *   4. write_master가 내부 BRAM → BRAM_0으로 784바이트 전송
 *   5. done_irq → CPU → NPU 추론 시작
 *   6. CPU가 CTRL[1]=1 → 내부 BRAM 클리어 → 다음 입력 준비
 */
module tft_lcd_axi_wrapper #(
    parameter integer C_S_AXI_DATA_WIDTH  = 32,
    parameter integer C_S_AXI_ADDR_WIDTH  = 5,
    parameter integer C_M_AXI_ADDR_WIDTH  = 32,
    parameter integer C_M_AXI_DATA_WIDTH  = 32,
    parameter integer BURST_LEN           = 16
)(
    input  wire aclk,
    input  wire aresetn,

    // =========================================================
    // 1. AXI4-Lite Slave (CPU 제어)
    // =========================================================
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire                             s_axi_awvalid,
    output wire                             s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                             s_axi_wvalid,
    output wire                             s_axi_wready,
    output wire [1:0]                       s_axi_bresp,
    output wire                             s_axi_bvalid,
    input  wire                             s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire                             s_axi_arvalid,
    output wire                             s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0]   s_axi_rdata,
    output wire [1:0]                       s_axi_rresp,
    output wire                             s_axi_rvalid,
    input  wire                             s_axi_rready,

    // =========================================================
    // 2. AXI4-Full Master Write (내부 BRAM → BRAM_0)
    // =========================================================
    output wire [C_M_AXI_ADDR_WIDTH-1:0]   m_axi_awaddr,
    output wire [7:0]                       m_axi_awlen,
    output wire [2:0]                       m_axi_awsize,
    output wire [1:0]                       m_axi_awburst,
    output wire                             m_axi_awvalid,
    input  wire                             m_axi_awready,
    output wire [C_M_AXI_DATA_WIDTH-1:0]   m_axi_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output wire                             m_axi_wlast,
    output wire                             m_axi_wvalid,
    input  wire                             m_axi_wready,
    input  wire [1:0]                       m_axi_bresp,
    input  wire                             m_axi_bvalid,
    output wire                             m_axi_bready,

    // =========================================================
    // 3. TFT LCD 포트
    // =========================================================
    input  wire tft_sdo,
    output wire tft_sck,
    output wire tft_sdi,
    output wire tft_dc,
    output wire tft_reset,
    output wire tft_cs,

    // 터치패드
    input  wire PenIrq_n,
    output wire DCLK,
    output wire DIN,
    output wire CS_N,
    input  wire DOUT,

    // =========================================================
    // 4. 인터럽트
    // =========================================================
    output wire o_done_irq
);

    // =========================================================
    // [Part 1] AXI4-Lite 슬레이브 레지스터
    // (top_dma_full_to_stream의 버그픽스 버전 채용)
    // =========================================================
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg0; // 0x00 CTRL
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg1; // 0x04 STAT (read-only)
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg2; // 0x08 DST_ADDR
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg3; // 0x0C TRF_LEN

    // AW/W 독립 래치 방식 (버그픽스)
    reg bvalid_reg;
    reg aw_latched;
    reg w_latched;
    reg [C_S_AXI_ADDR_WIDTH-1:0] aw_addr_lat;
    reg [C_S_AXI_DATA_WIDTH-1:0] w_data_lat;

    assign s_axi_awready = !aw_latched;
    assign s_axi_wready  = !w_latched;
    assign s_axi_bvalid  = bvalid_reg;
    assign s_axi_bresp   = 2'b00;


    wire write_en = aw_latched && w_latched && !bvalid_reg;

    always @(posedge aclk) begin
        if (!aresetn) begin
            aw_latched  <= 0; w_latched   <= 0;
            aw_addr_lat <= 0; w_data_lat  <= 0;
            bvalid_reg  <= 0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_latched  <= 1;
                aw_addr_lat <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_latched  <= 1;
                w_data_lat <= s_axi_wdata;
            end
            if (write_en) begin
                bvalid_reg <= 1;
                aw_latched <= 0;
                w_latched  <= 0;
            end else if (s_axi_bready && bvalid_reg) begin
                bvalid_reg <= 0;
            end
        end
    end

    // 레지스터 쓰기
    wire [2:0] wr_addr_idx = aw_addr_lat[4:2];
    always @(posedge aclk) begin
        if (!aresetn) begin
            slv_reg0 <= 0;
            slv_reg2 <= 0;
            slv_reg3 <= 0;
        end else begin
            // CTRL 비트 자동 clear (start, bram_clear 모두)
            if (slv_reg0[0]) slv_reg0[0] <= 1'b0;
            if (slv_reg0[1]) slv_reg0[1] <= 1'b0;

            if (write_en) begin
                case (wr_addr_idx)
                    3'h0: slv_reg0 <= w_data_lat;
                    3'h2: slv_reg2 <= w_data_lat;
                    3'h3: slv_reg3 <= w_data_lat;
                endcase
            end
        end
    end

    // ★ 추가: dma_done 펄스를 래치하여 유지
    reg done_latch;
    always @(posedge aclk) begin
        if (!aresetn)
            done_latch <= 1'b0;
        else if (dma_done)
            done_latch <= 1'b1;     // 전송이 끝나면 1로 유지
        else if (dma_start)
            done_latch <= 1'b0;     // 다음 전송 시작 시 0으로 초기화
    end

    // 원래 있던 slv_reg1 할당 부분을 아래처럼 수정!
    always @(posedge aclk) begin
        if (!aresetn)
            slv_reg1 <= 0;
        else begin
            slv_reg1[0] <= done_latch; // 펄스 대신 래치된 값 사용!
            slv_reg1[1] <= dma_busy;
        end
    end

    // Read 핸드셰이크
    reg  rvalid_reg;
    reg  [C_S_AXI_DATA_WIDTH-1:0] rdata_reg;
    reg arready_reg;
    assign s_axi_arready = arready_reg;
    
    always @(posedge aclk) begin
        if (!aresetn)
            arready_reg <= 1;
        else if (s_axi_arvalid && arready_reg)
            arready_reg <= 0;  // 요청 수락 후 내림
        else if (s_axi_rvalid && s_axi_rready)
            arready_reg <= 1;  // 읽기 응답 완료 후 다시 올림
    end
    assign s_axi_rvalid  = rvalid_reg;
    assign s_axi_rdata   = rdata_reg;
    assign s_axi_rresp   = 2'b00;

    always @(posedge aclk) begin
        if (!aresetn) begin
            rvalid_reg <= 0;
            rdata_reg  <= 0;
        end else begin
            // ARVALID와 ARREADY가 만나면 읽기 응답(RVALID) 시작
            if (s_axi_arvalid && arready_reg) begin
                rvalid_reg <= 1;
                case (s_axi_araddr[4:2])
                    3'h0: rdata_reg <= slv_reg0;
                    3'h1: rdata_reg <= slv_reg1;
                    3'h2: rdata_reg <= slv_reg2;
                    3'h3: rdata_reg <= slv_reg3;
                    default: rdata_reg <= 0;
                endcase
            end 
            // 마스터가 데이터를 받아가면(RREADY) RVALID 내림
            else if (s_axi_rvalid && s_axi_rready) begin
                rvalid_reg <= 0;
            end
        end
    end

    // =========================================================
    // [Part 2] 내부 신호 배선
    // =========================================================
    wire        bram_clear = slv_reg0[1];
    wire [31:0] dst_addr   = slv_reg2;
    wire [31:0] trf_len    = slv_reg3;
    wire [7:0]  ext_rd_addr;
    wire [31:0] ext_rd_data;
    
    (* mark_debug = "true" *) wire pen_lock;
    (* mark_debug = "true" *) reg  busy_reg;
    
    // ★ 수정: start_pulse를 slv_reg0[0]에서 분리
    // write_en이 CTRL 레지스터에 1을 쓰는 순간 1클럭 펄스 생성
    // → auto-clear 경쟁 조건 완전히 제거
    (* mark_debug = "true" *) reg  start_pulse;
    wire dma_start = start_pulse;
    
    always @(posedge aclk) begin
        if (!aresetn)
            start_pulse <= 1'b0;
        else if (write_en && (wr_addr_idx == 3'h0) && w_data_lat[0])
            start_pulse <= 1'b1;  // write_en 발생 클럭 자체에서 펄스 생성
        else
            start_pulse <= 1'b0;  // 1클럭 후 자동 소멸
    end
    
    assign dma_busy = busy_reg;
    assign pen_lock = busy_reg;
    
    always @(posedge aclk) begin
        if (!aresetn)       busy_reg <= 0;
        else if (dma_start) busy_reg <= 1;
        else if (dma_done)  busy_reg <= 0;
    end

    // =========================================================
    // [Part 3] tft_lcd_top 인스턴스
    // =========================================================
    tft_lcd_top u_lcd (
        .clk        (aclk),
        .reset_p    (~aresetn),
        // TFT
        .tft_sdo    (tft_sdo),
        .tft_sck    (tft_sck),
        .tft_sdi    (tft_sdi),
        .tft_dc     (tft_dc),
        .tft_reset  (tft_reset),
        .tft_cs     (tft_cs),
        // 터치패드
        .PenIrq_n   (PenIrq_n),
        .DCLK       (DCLK),
        .DIN        (DIN),
        .CS_N       (CS_N),
        .DOUT       (DOUT),
        // 제어
        .pen_lock   (pen_lock),
        .bram_clear (bram_clear),
        // BRAM 외부 읽기 포트
        .ext_rd_addr(ext_rd_addr),
        .ext_rd_data(ext_rd_data)
    );

    // =========================================================
    // [Part 4] write_master 인스턴스
    // =========================================================
    tft_lcd_write_master #(
        .C_M_AXI_ADDR_WIDTH (C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH (C_M_AXI_DATA_WIDTH),
        .BURST_LEN          (BURST_LEN)
    ) u_write_master (
        .clk            (aclk),
        .reset_n        (aresetn),
        // 제어
        .i_start        (dma_start),
        .i_dst_addr     (dst_addr),
        .i_total_len    (trf_len),
        .o_write_done   (dma_done),
        // BRAM 읽기
        .o_bram_rd_addr (ext_rd_addr),
        .i_bram_rd_data (ext_rd_data),
        // AXI4-Full Write
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready)
    );

    assign o_done_irq = dma_done;

endmodule