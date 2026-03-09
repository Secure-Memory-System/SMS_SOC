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

    // Write 핸드셰이크
    reg awready_reg, wready_reg, bvalid_reg;
    assign s_axi_awready = awready_reg;
    assign s_axi_wready  = wready_reg;
    assign s_axi_bvalid  = bvalid_reg;
    assign s_axi_bresp   = 2'b00;

    always @(posedge aclk) begin
        if (!aresetn) begin
            awready_reg <= 0;
            wready_reg  <= 0;
            bvalid_reg  <= 0;
        end else begin
            awready_reg <= (s_axi_awvalid && !awready_reg) ? 1'b1 : 1'b0;
            wready_reg  <= (s_axi_wvalid  && !wready_reg)  ? 1'b1 : 1'b0;
            if (awready_reg && wready_reg)
                bvalid_reg <= 1;
            else if (s_axi_bready && bvalid_reg)
                bvalid_reg <= 0;
        end
    end

    // 레지스터 쓰기
    wire [2:0] wr_addr = s_axi_awaddr[4:2];
    always @(posedge aclk) begin
        if (!aresetn) begin
            slv_reg0 <= 0;
            slv_reg2 <= 0;
            slv_reg3 <= 0;
        end else begin
            // start 비트 자동 clear
            if (slv_reg0[0]) slv_reg0[0] <= 1'b0;

            if (awready_reg && wready_reg) begin
                case (wr_addr)
                    3'h0: slv_reg0 <= s_axi_wdata;
                    3'h2: slv_reg2 <= s_axi_wdata;
                    3'h3: slv_reg3 <= s_axi_wdata;
                    // 0x04 STAT은 read-only, 쓰기 무시
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