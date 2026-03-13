`timescale 1ns / 1ps

module npu_v2_axi_wrapper #(
    parameter BRAM_ADDR_BASE = 32'h0000_0000
)(
    input  wire        aclk,
    input  wire        aresetn,

    // ── AXI4-Lite Slave (CPU 제어) ────────────────────────
    input  wire [4:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [4:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // ── AXI4 Master (BRAM 픽셀 읽기) ─────────────────────
    // [Read 채널] 실제 사용
    output wire [31:0] m_axi_img_araddr,
    output wire [7:0]  m_axi_img_arlen,
    output wire [2:0]  m_axi_img_arsize,
    output wire [1:0]  m_axi_img_arburst,
    output wire        m_axi_img_arvalid,
    input  wire        m_axi_img_arready,
    input  wire [31:0] m_axi_img_rdata,
    input  wire [1:0]  m_axi_img_rresp,
    input  wire        m_axi_img_rvalid,
    output wire        m_axi_img_rready,
    // [Write 채널] 더미 tie-off - Block Design 연결을 위해 추가
    output wire [31:0] m_axi_img_awaddr,
    output wire [7:0]  m_axi_img_awlen,
    output wire [2:0]  m_axi_img_awsize,
    output wire [1:0]  m_axi_img_awburst,
    output wire        m_axi_img_awvalid,
    input  wire        m_axi_img_awready,
    output wire [31:0] m_axi_img_wdata,
    output wire [3:0]  m_axi_img_wstrb,
    output wire        m_axi_img_wvalid,
    input  wire        m_axi_img_wready,
    input  wire [1:0]  m_axi_img_bresp,
    input  wire        m_axi_img_bvalid,
    output wire        m_axi_img_bready,

    // ── AXI4-Stream Master (결과 출력) ───────────────────
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);

    // ── Read 채널 고정 신호 (단일 beat 읽기) ─────────────
    assign m_axi_img_arlen   = 8'd0;    // burst length = 1 beat
    assign m_axi_img_arsize  = 3'b010;  // 4 bytes (32-bit)
    assign m_axi_img_arburst = 2'b01;   // INCR

    // ── Write 채널 더미 tie-off (쓰기 요청 발생 안 함) ───
    assign m_axi_img_awaddr  = 32'd0;
    assign m_axi_img_awlen   = 8'd0;
    assign m_axi_img_awsize  = 3'b010;
    assign m_axi_img_awburst = 2'b01;
    assign m_axi_img_awvalid = 1'b0;
    assign m_axi_img_wdata   = 32'd0;
    assign m_axi_img_wstrb   = 4'b0000;
    assign m_axi_img_wvalid  = 1'b0;
    assign m_axi_img_bready  = 1'b0;

    // =========================================================
    // [Part 1] AXI4-Lite Slave 레지스터
    // =========================================================
    reg [31:0] slv_reg0;   // [0]=start(self-clear)
    reg [31:0] slv_reg1;   // BRAM 오프셋 주소
    
    reg bvalid_reg;
    // 기존 코드 제거하고 아래로 교체
    reg aw_latched, w_latched;
    reg [4:0] aw_addr_lat;
    reg [31:0] w_data_lat;

    assign s_axi_awready = !aw_latched && !bvalid_reg;
    assign s_axi_wready  = !w_latched  && !bvalid_reg;
    assign s_axi_bvalid  = bvalid_reg;
    assign s_axi_bresp   = 2'b00;
    
    wire write_en = aw_latched && w_latched;
    wire        result_valid_w;
    wire [3:0]  final_digit_w;
    wire        npu_busy;

    always @(posedge aclk) begin
        if (!aresetn) begin
            aw_latched <= 0; w_latched  <= 0;
            aw_addr_lat <= 0; w_data_lat <= 0;
            bvalid_reg <= 0;
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

    wire [2:0] wr_reg_addr = aw_addr_lat[4:2];  // s_axi_awaddr → aw_addr_lat
    reg done_latch; 
    reg [3:0] final_digit_reg;
    
    // [수정] done_latch 및 제어 레지스터 Race Condition 해결
    always @(posedge aclk) begin
        if (!aresetn) begin
            slv_reg0 <= 0;
            slv_reg1 <= 0;
            done_latch <= 0; final_digit_reg <= 0;
        end else begin
            // 1순위: 연산이 완료되면 플래그와 결과값을 래치
            if (result_valid_w) begin
                done_latch      <= 1'b1;
                final_digit_reg <= final_digit_w;
            end 
            // 2순위: CPU가 제어 레지스터에 쓰기를 시도할 때
            else if (write_en) begin  
                case (wr_reg_addr)
                    3'h0: slv_reg0 <= w_data_lat;
                    3'h1: slv_reg1 <= w_data_lat;
                    default: ;
                endcase
                // CPU가 레지스터 0번(제어)에 Write 할 때만 완료 플래그를 명시적으로 해제
                if (wr_reg_addr == 3'h0) done_latch <= 1'b0;
            end 
            // 3순위: start(slv_reg0[0]) 비트는 1클럭 유지 후 자동 Clear
            else if (slv_reg0[0]) begin
                slv_reg0[0] <= 1'b0;
            end
        end
    end

    // AXI-Lite Read
    reg arready_reg, rvalid_reg;
    reg [31:0] rdata_reg;
    assign s_axi_arready = arready_reg;
    assign s_axi_rvalid  = rvalid_reg;
    assign s_axi_rdata   = rdata_reg;
    assign s_axi_rresp   = 2'b00;
    wire [2:0] rd_reg_addr = s_axi_araddr[4:2];

    always @(posedge aclk) begin
        if (!aresetn) begin
            arready_reg <= 0; rvalid_reg <= 0; rdata_reg <= 0;
        end else begin
            if (s_axi_arvalid && !arready_reg) begin
                arready_reg <= 1'b1; rvalid_reg <= 1'b1;
                case (rd_reg_addr)
                    3'h0: rdata_reg <= {30'd0, done_latch, npu_busy};
                    3'h1: rdata_reg <= slv_reg1;
                    3'h2: rdata_reg <= {28'd0, final_digit_reg};
                    default: rdata_reg <= 32'd0;
                endcase
            end else begin
                arready_reg <= 1'b0;
                if (s_axi_rready && rvalid_reg) rvalid_reg <= 1'b0;
            end
        end
    end

    // =========================================================
    // [Part 2] BRAM 픽셀 피더
    // =========================================================
    localparam PF_IDLE   = 2'd0;
    localparam PF_STREAM = 2'd1;
    localparam PF_DONE   = 2'd2;

    reg [1:0]  pf_state;
    reg        busy_r;
    reg [7:0]  pixel_r;
    reg [31:0] word_buf;    // 수신한 32bit 워드 저장
    reg [1:0]  byte_sel;    // 언팩 중인 바이트 위치 (0~3)
    reg        word_valid;  // 언팩 진행 중 플래그
    reg        pixel_en_r;  // NPU에 전달할 pixel_en
    assign npu_busy = busy_r;

    wire [9:0] buf_idx_w;

    // ── BRAM AR 채널 ─────────────────────────────────────
    reg ar_pending;  // AR 발행 후 rvalid 대기 중 플래그
    
    always @(posedge aclk) begin
        if (!aresetn)
            ar_pending <= 1'b0;
        else if (m_axi_img_arvalid && m_axi_img_arready)
            ar_pending <= 1'b1;   // 주소 수락됨 → 대기
        else if (m_axi_img_rvalid)
            ar_pending <= 1'b0;   // 데이터 수신 → 다음 요청 가능
    end
    
    // arvalid: PF_STREAM 중이고 pending 아닐 때만 assert
    assign m_axi_img_arvalid = (pf_state == PF_STREAM) && !ar_pending && !word_valid;
    assign m_axi_img_araddr = BRAM_ADDR_BASE + slv_reg1
                         + {22'd0, buf_idx_w[9:2], 2'b00};  // 4픽셀당 1 워드
    assign m_axi_img_rready  = 1'b1;

    // ── pixel 래치 ───────────────────────────────────────
    always @(posedge aclk) begin
        if (!aresetn) begin
            word_buf   <= 0;
            byte_sel   <= 0;
            word_valid <= 0;
            pixel_en_r <= 0;
            pixel_r    <= 0;
        end else begin
            pixel_en_r <= 0; // 매 클럭 기본값 0
    
            if (m_axi_img_rvalid && pf_state == PF_STREAM && !word_valid) begin
                // 새 워드 수신 → byte[0] 즉시 출력
                word_buf   <= m_axi_img_rdata;
                pixel_r    <= m_axi_img_rdata[7:0];
                pixel_en_r <= 1;
                byte_sel   <= 2'd1;
                word_valid <= 1;
            end else if (word_valid) begin
                // byte[1], [2], [3] 순차 출력
                pixel_en_r <= 1;
                case (byte_sel)
                    2'd1: pixel_r <= word_buf[15:8];
                    2'd2: pixel_r <= word_buf[23:16];
                    2'd3: pixel_r <= word_buf[31:24];
                    default: ;
                endcase
    
                if (byte_sel == 2'd3) begin
                    word_valid <= 0;
                    byte_sel   <= 0;
                end else begin
                    byte_sel <= byte_sel + 1;
                end
            end
        end
    end

    // ── Pixel Feeder FSM ─────────────────────────────────
    always @(posedge aclk) begin
        if (!aresetn) begin
            pf_state <= PF_IDLE;
            busy_r   <= 1'b0;
        end else begin
            case (pf_state)
                PF_IDLE: begin
                    if (slv_reg0[0]) begin
                        pf_state <= PF_STREAM;
                        busy_r   <= 1'b1;
                    end
                end
                PF_STREAM: begin
                    if (result_valid_w)
                        pf_state <= PF_DONE;
                end
                PF_DONE: begin
                    busy_r   <= 1'b0;
                    pf_state <= PF_IDLE;
                end
                default: pf_state <= PF_IDLE;
            endcase
        end
    end

    // =========================================================
    // [Part 3] npu_v2_top 인스턴스
    // =========================================================
    npu_v2_top u_npu_v2 (
        .clk         (aclk),
        .reset_p     (~aresetn),
        .start       (slv_reg0[0]),
        .pixel       (pixel_r),
        .pixel_en    (pixel_en_r),     // ← m_axi_img_rvalid 에서 pixel_en_r 로 변경
        .buf_idx     (buf_idx_w),
        .final_digit (final_digit_w),
        .result_valid(result_valid_w)
    );

    // =========================================================
    // [Part 4] AXI4-Stream Master 결과 출력
    // =========================================================
    reg        m_tvalid_r;
    reg [31:0] m_tdata_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_tvalid_r <= 1'b0; m_tdata_r <= 32'd0;
        end else begin
            if (result_valid_w) begin
                m_tvalid_r <= 1'b1;
                m_tdata_r  <= {28'd0, final_digit_w};
            end else if (m_axis_tready && m_tvalid_r) begin
                m_tvalid_r <= 1'b0;
            end
        end
    end

    assign m_axis_tdata  = m_tdata_r;
    assign m_axis_tvalid = m_tvalid_r;
    assign m_axis_tlast  = m_tvalid_r;

endmodule