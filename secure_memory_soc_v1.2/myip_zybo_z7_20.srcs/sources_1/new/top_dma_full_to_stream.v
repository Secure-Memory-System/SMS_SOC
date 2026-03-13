`timescale 1ns / 1ps

/**
 * top_dma_full_to_stream
 * 기능: AXI4-Full로 메모리에서 데이터를 읽어 AXI4-Stream으로 출력함.
 * 용도:
 *   - 버전 A: DRAM_0 → NPU        (C_M_AXIS_DATA_WIDTH = 32)
 *   - 버전 C: DRAM_1 → 복호화 IP  (C_M_AXIS_DATA_WIDTH = 32)
 *
 * 내부 구성:
 *   AXI4-Lite Slave (CPU 제어)
 *   → read_master (AXI4-Full Read)
 *   → FIFO (Xilinx FIFO Generator, FWFT, 32bit x 1024)
 *   → stream_write_master (AXI4-Stream Master 출력)
 *
 * 레지스터 맵 (AXI4-Lite, Base Addr 기준):
 *   0x00 : CTRL    [0] start (write 1 → 1클럭 후 자동 clear)
 *   0x04 : STAT    [0] done  (read-only, 1클럭 펄스)
 *   0x08 : SRC_ADDR 읽기 소스 메모리 주소
 *   0x0C : TRF_LEN  전송할 총 바이트 수
 */
module top_dma_full_to_stream #(
    parameter integer C_S_AXI_DATA_WIDTH    = 32,
    parameter integer C_S_AXI_ADDR_WIDTH    = 5,
    parameter integer C_M_AXI_ADDR_WIDTH    = 32,
    parameter integer C_M_AXI_DATA_WIDTH    = 32,
    parameter integer C_M_AXIS_DATA_WIDTH   = 32
)(
    input  wire aclk,
    input  wire aresetn,

    // =========================================================
    // 1. AXI4-Lite Slave (CPU 제어 버스)
    // =========================================================
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire                            s_axi_awvalid,
    output wire                            s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                            s_axi_wvalid,
    output wire                            s_axi_wready,
    output wire [1:0]                      s_axi_bresp,
    output wire                            s_axi_bvalid,
    input  wire                            s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire                            s_axi_arvalid,
    output wire                            s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]                      s_axi_rresp,
    output wire                            s_axi_rvalid,
    input  wire                            s_axi_rready,

    // =========================================================
    // 2. AXI4-Full Master Read (메모리 → DMA)
    // =========================================================
    // AR Channel
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_araddr,
    output wire [7:0]                      m_axi_arlen,
    output wire [2:0]                      m_axi_arsize,
    output wire [1:0]                      m_axi_arburst,
    output wire                            m_axi_arvalid,
    input  wire                            m_axi_arready,
    // R Channel
    input  wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_rdata,
    input  wire                            m_axi_rlast,
    input  wire                            m_axi_rvalid,
    output wire                            m_axi_rready,

    // =========================================================
    // 3. AXI4-Stream Master (DMA → NPU 또는 복호화 IP)
    // =========================================================
    output wire [C_M_AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output wire                            m_axis_tvalid,
    input  wire                            m_axis_tready,
    output wire                            m_axis_tlast,

    // =========================================================
    // 4. 인터럽트 출력
    // =========================================================
    output wire                            o_done_irq
);

    // =========================================================
    // [Part 1] AXI4-Lite 슬레이브 레지스터
    // =========================================================
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg0; // 0x00 CTRL  [0]: start
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg1; // 0x04 STAT  [0]: done (read-only)
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg2; // 0x08 SRC_ADDR
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg3; // 0x0C TRF_LEN

    // =========================================================
    // Write 핸드셰이크 (Bug Fix: AW/W 채널 독립 접수)
    //
    // [수정 이유]
    //   AXI4-Lite 스펙상 AW(주소)와 W(데이터) 채널은 어떤 순서로든
    //   도착할 수 있음. 기존 코드는 awready와 wready가 "동일 클럭"에
    //   동시에 1이 될 때만 bvalid를 올렸으나, 두 채널이 서로 다른
    //   클럭에 도착하면 bvalid가 영원히 올라가지 않는 버스 Hang 버그가
    //   존재했음.
    //
    // [수정 방법]
    //   aw_latched / w_latched 플래그를 두어 두 채널을 독립적으로 접수.
    //   두 플래그가 모두 1이 된 순간 레지스터 쓰기 + bvalid 발행.
    //   어느 채널이 먼저 와도 정상 동작 보장.
    // =========================================================
    reg bvalid_reg;
    reg aw_latched;          // AW 채널 접수 완료 플래그
    reg w_latched;           // W  채널 접수 완료 플래그
    reg [C_S_AXI_ADDR_WIDTH-1:0] aw_addr_lat; // 래치된 쓰기 주소
    reg [C_S_AXI_DATA_WIDTH-1:0] w_data_lat;  // 래치된 쓰기 데이터

    // awready / wready: 상대방이 아직 latched 되지 않았고
    //                   bvalid가 처리 중이 아닐 때만 새 트랜잭션 수락
    assign s_axi_awready = !aw_latched && !bvalid_reg;
    assign s_axi_wready  = !w_latched  && !bvalid_reg;
    assign s_axi_bvalid  = bvalid_reg;
    assign s_axi_bresp   = 2'b00;

    // write_en: 두 채널이 모두 접수된 순간 1클럭 활성화 → 레지스터 쓰기 트리거
    wire write_en = aw_latched && w_latched;

    always @(posedge aclk) begin
        if (!aresetn) begin
            aw_latched   <= 0;
            w_latched    <= 0;
            aw_addr_lat  <= 0;
            w_data_lat   <= 0;
            bvalid_reg   <= 0;
        end else begin
            // --- AW 채널 접수 ---
            if (s_axi_awvalid && s_axi_awready) begin
                aw_latched  <= 1;
                aw_addr_lat <= s_axi_awaddr;
            end

            // --- W 채널 접수 ---
            if (s_axi_wvalid && s_axi_wready) begin
                w_latched  <= 1;
                w_data_lat <= s_axi_wdata;
            end

            // --- 두 채널 모두 접수 완료 → B 채널 응답 발행 ---
            if (write_en) begin
                bvalid_reg <= 1;
                aw_latched <= 0;
                w_latched  <= 0;
            end else if (s_axi_bready && bvalid_reg) begin
                bvalid_reg <= 0;
            end
        end
    end

    // 레지스터 쓰기 (write_en 기준으로 래치된 주소/데이터 사용)
    wire [2:0] wr_addr = aw_addr_lat[4:2];
    always @(posedge aclk) begin
        if (!aresetn) begin
            slv_reg0 <= 0;
            slv_reg2 <= 0;
            slv_reg3 <= 0;
        end else begin
            // start 비트 자동 clear (Self-Clearing)
            if (slv_reg0[0]) slv_reg0[0] <= 1'b0;

            // write_en이 1인 클럭에 래치된 주소/데이터로 레지스터 쓰기
            if (write_en) begin
                case (wr_addr)
                    3'h0: slv_reg0 <= w_data_lat;
                    3'h2: slv_reg2 <= w_data_lat;
                    3'h3: slv_reg3 <= w_data_lat;
                    // 3'h1: STAT은 read-only, 쓰기 무시
                endcase
            end
        end
    end

    // done 신호를 STAT 레지스터에 반영
    wire dma_done;
    always @(posedge aclk) begin
        if (!aresetn)
            slv_reg1 <= 0;
        else
            slv_reg1[0] <= dma_done;
    end

    // Read 핸드셰이크
    reg  rvalid_reg;
    reg  [C_S_AXI_DATA_WIDTH-1:0] rdata_reg;
    assign s_axi_arready = 1'b1;
    assign s_axi_rvalid  = rvalid_reg;
    assign s_axi_rdata   = rdata_reg;
    assign s_axi_rresp   = 2'b00;

    always @(posedge aclk) begin
        if (!aresetn) begin
            rvalid_reg <= 0;
            rdata_reg  <= 0;
        end else begin
            rvalid_reg <= s_axi_arvalid;
            case (s_axi_araddr[4:2])
                3'h0: rdata_reg <= slv_reg0;
                3'h1: rdata_reg <= slv_reg1;
                3'h2: rdata_reg <= slv_reg2;
                3'h3: rdata_reg <= slv_reg3;
                default: rdata_reg <= 0;
            endcase
        end
    end

    // =========================================================
    // [Part 2] 내부 배선
    // =========================================================
    wire        dma_start   = slv_reg0[0];
    wire [31:0] src_addr    = slv_reg2;
    wire [31:0] trf_len     = slv_reg3;

    // FIFO 내부 배선
    wire        fifo_full;
    wire        fifo_empty;
    wire        fifo_wr_en;
    wire        fifo_rd_en;
    wire [31:0] fifo_din;
    wire [31:0] fifo_dout;

    // read_master → FIFO
    wire        read_done;

    // stream_write_master done
    wire        stream_done;

    // 전체 완료: read_done과 stream_done 중 stream_done 기준
    // (FIFO를 다 비워야 진짜 완료이므로 stream_done 사용)
    assign dma_done  = stream_done;
    assign o_done_irq = dma_done;

    // =========================================================
    // [Part 3] read_master 인스턴스
    // =========================================================
    read_master #(
        .C_M_AXI_ADDR_WIDTH (C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH (C_M_AXI_DATA_WIDTH)
    ) u_read_master (
        .clk            (aclk),
        .reset_n        (aresetn),
        // 제어
        .i_start        (dma_start),
        .i_src_addr     (src_addr),
        .i_total_len    (trf_len),
        .o_read_done    (read_done),
        // FIFO
        .i_fifo_full    (fifo_full),
        .o_fifo_push    (fifo_wr_en),
        .o_r_data       (fifo_din),
        // AR Channel
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        // R Channel
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready)
    );

    // =========================================================
    // [Part 4] FIFO 인스턴스
    // Synchronous FIFO / FWFT / 32bit / Depth 1024
    // =========================================================
    fifo_sync_fwft u_fifo (
        .clk    (aclk),
        .srst   (~aresetn),
        .din    (fifo_din),
        .wr_en  (fifo_wr_en),
        .rd_en  (fifo_rd_en),
        .dout   (fifo_dout),
        .full   (fifo_full),
        .empty  (fifo_empty)
    );

    // =========================================================
    // [Part 5] stream_write_master 인스턴스
    // =========================================================
    stream_write_master #(
        .C_M_AXIS_DATA_WIDTH (C_M_AXIS_DATA_WIDTH)
    ) u_stream_write_master (
        .clk            (aclk),
        .reset_n        (aresetn),
        // 제어
        .i_start        (dma_start),
        .i_total_len    (trf_len),
        .o_done         (stream_done),
        // FIFO
        .i_fifo_empty   (fifo_empty),
        .o_fifo_rd_en   (fifo_rd_en),
        .i_w_data       (fifo_dout),
        // AXI4-Stream
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast)
    );

endmodule