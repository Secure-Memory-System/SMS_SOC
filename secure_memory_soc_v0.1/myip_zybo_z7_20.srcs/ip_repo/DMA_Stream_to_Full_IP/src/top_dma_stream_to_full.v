`timescale 1ns / 1ps

/**
 * top_dma_stream_to_full
 * 기능: AXI4-Stream으로 데이터를 수신하여 AXI4-Full로 메모리에 저장함.
 * 용도:
 *   - 버전 B: 암호화 IP 출력 → DRAM_1 저장 (C_S_AXIS_DATA_WIDTH = 128)
 *
 * 내부 구성:
 *   AXI4-Lite Slave (CPU 제어)
 *   → stream_read_master (AXI4-Stream Slave 수신)
 *   → FIFO (Xilinx FIFO Generator, FWFT, 32bit x 1024)
 *   → write_master (AXI4-Full Write)
 *
 * 레지스터 맵 (AXI4-Lite, Base Addr 기준):
 *   0x00 : CTRL    [0] start (write 1 → 1클럭 후 자동 clear)
 *   0x04 : STAT    [0] done  (read-only, 1클럭 펄스)
 *   0x08 : DST_ADDR 쓰기 목적지 메모리 주소
 *   0x0C : TRF_LEN  전송할 총 바이트 수
 */
module top_dma_stream_to_full #(
    parameter integer C_S_AXI_DATA_WIDTH    = 32,
    parameter integer C_S_AXI_ADDR_WIDTH    = 5,
    parameter integer C_M_AXI_ADDR_WIDTH    = 32,
    parameter integer C_M_AXI_DATA_WIDTH    = 32,
    parameter integer C_S_AXIS_DATA_WIDTH   = 128  // 암호화 IP 출력이 128bit
)(
    input  wire aclk,
    input  wire aresetn,

    // =========================================================
    // 1. AXI4-Lite Slave (CPU 제어 버스)
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
    // 2. AXI4-Stream Slave (암호화 IP → DMA)
    // =========================================================
    input  wire [C_S_AXIS_DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                             s_axis_tvalid,
    output wire                             s_axis_tready,
    input  wire                             s_axis_tlast,

    // =========================================================
    // 3. AXI4-Full Master Write (DMA → 메모리)
    // =========================================================
    // AW Channel
    output wire [C_M_AXI_ADDR_WIDTH-1:0]  m_axi_awaddr,
    output wire [7:0]                      m_axi_awlen,
    output wire [2:0]                      m_axi_awsize,
    output wire [1:0]                      m_axi_awburst,
    output wire                            m_axi_awvalid,
    input  wire                            m_axi_awready,
    // W Channel
    output wire [C_M_AXI_DATA_WIDTH-1:0]  m_axi_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output wire                            m_axi_wlast,
    output wire                            m_axi_wvalid,
    input  wire                            m_axi_wready,
    // B Channel
    input  wire [1:0]                      m_axi_bresp,
    input  wire                            m_axi_bvalid,
    output wire                            m_axi_bready,

    // =========================================================
    // 4. 인터럽트 출력
    // =========================================================
    output wire                            o_done_irq
);

    // =========================================================
    // [Part 1] AXI4-Lite 슬레이브 레지스터
    // =========================================================
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg0; // 0x00 CTRL    [0]: start
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg1; // 0x04 STAT    [0]: done (read-only)
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg2; // 0x08 DST_ADDR
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
    wire        dma_start = slv_reg0[0];
    wire [31:0] dst_addr  = slv_reg2;
    wire [31:0] trf_len   = slv_reg3;

    // FIFO 내부 배선
    wire        fifo_full;
    wire        fifo_empty;
    wire        fifo_wr_en;
    wire        fifo_rd_en;
    wire [31:0] fifo_din;
    wire [31:0] fifo_dout;

    // 완료 신호
    wire        stream_recv_done;   // stream_read_master 수신 완료
    wire        write_done;         // write_master 쓰기 완료

    // 전체 완료: FIFO를 다 비워 메모리에 써야 진짜 완료이므로 write_done 기준
    assign dma_done   = write_done;
    assign o_done_irq = dma_done;

    // =========================================================
    // [Part 3] stream_read_master 인스턴스
    // =========================================================
    // ※ 암호화 IP 출력이 128bit이므로 FIFO din에 넣기 전에
    //   128bit → 32bit 분할이 필요함.
    //   여기서는 단순화를 위해 C_S_AXIS_DATA_WIDTH = 32 기준으로 직결.
    //   128bit 대응이 필요할 경우 width converter를 별도 삽입할 것.
    stream_read_master #(
        .C_S_AXIS_DATA_WIDTH (C_S_AXIS_DATA_WIDTH)
    ) u_stream_read_master (
        .clk            (aclk),
        .reset_n        (aresetn),
        // 제어
        .i_start        (dma_start),
        .i_total_len    (trf_len),
        .o_done         (stream_recv_done),
        // FIFO
        .i_fifo_full    (fifo_full),
        .o_fifo_push    (fifo_wr_en),
        .o_r_data       (fifo_din),
        // AXI4-Stream
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast)
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
    // [Part 5] write_master 인스턴스
    // =========================================================
    write_master #(
        .C_M_AXI_ADDR_WIDTH (C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH (C_M_AXI_DATA_WIDTH)
    ) u_write_master (
        .clk            (aclk),
        .reset_n        (aresetn),
        // 제어
        .i_start        (dma_start),
        .i_dst_addr     (dst_addr),
        .i_total_len    (trf_len),
        .o_write_done   (write_done),
        // FIFO
        .i_fifo_empty   (fifo_empty),
        .o_fifo_rd_en   (fifo_rd_en),
        .i_w_data       (fifo_dout),
        // AW Channel
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        // W Channel
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        // B Channel
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready)
    );

endmodule