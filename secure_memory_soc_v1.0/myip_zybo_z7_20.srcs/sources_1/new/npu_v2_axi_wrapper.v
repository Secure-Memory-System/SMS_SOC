`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : npu_v2_axi_wrapper
// Description : AXI4-Lite Slave(CPU제어) + AXI4-Lite Master(BRAM읽기) +
//               AXI4-Stream Master(결과출력) wrapper for npu_v2_top
//
// ── 클럭 게이팅 전략 (sub_module 무수정) ──────────────────────────────────
//
//  npu_conv2d_buf는 posedge clk마다 무조건 pixel 소비 + buf_idx++ 를 하므로
//  BRAM 1-cycle latency와 맞추려면 NPU에 공급하는 클럭을
//  "BRAM rvalid가 온 클럭에만" 엣지가 발생하도록 게이팅해야 한다.
//
//  구현:
//    npu_clk = aclk  AND  npu_clk_en
//    npu_clk_en : BRAM rvalid 수신 클럭에 1, 나머지 0
//
//  타이밍:
//    aclk N   : pf_state=STREAM → arvalid=1, araddr=BASE+buf_idx*4
//    aclk N+1 : BRAM rdata 도착(rvalid=1) → npu_clk_en=1 → npu_clk 엣지 발생
//               → NPU: pixel_r 소비, buf_idx++, 다음 araddr 발행
//    aclk N+2 : rvalid=0 → npu_clk_en=0 (NPU 정지, BRAM 응답 대기)
//    aclk N+2 : 새 rvalid=1 → npu_clk_en=1 → NPU 재진행
//    ...반복 (BRAM throughput에 맞춰 NPU가 자동으로 throttle)
//
// ── AXI-Lite Register Map ─────────────────────────────────────────────────
//   0x00 Write: [0]=start (self-clear 1-pulse)
//        Read : [1]=done_latch, [0]=busy
//   0x04 Write: BRAM 픽셀 데이터 오프셋 주소 (기본 0)
//   0x08 Read : [3:0]=final_digit
//////////////////////////////////////////////////////////////////////////////////

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

    // ── AXI4-Lite Master (BRAM 픽셀 읽기) ────────────────
    output wire [31:0] m_axi_bram_araddr,
    output wire        m_axi_bram_arvalid,
    input  wire        m_axi_bram_arready,
    input  wire [31:0] m_axi_bram_rdata,
    input  wire [1:0]  m_axi_bram_rresp,
    input  wire        m_axi_bram_rvalid,
    output wire        m_axi_bram_rready,

    // ── AXI4-Stream Master (결과 출력) ───────────────────
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);

    // =========================================================
    // [Part 1] AXI4-Lite Slave 레지스터
    // =========================================================
    reg [31:0] slv_reg0;   // [0]=start(self-clear)
    reg [31:0] slv_reg1;   // BRAM 오프셋 주소

    reg awready_reg, wready_reg, bvalid_reg;
    assign s_axi_awready = awready_reg;
    assign s_axi_wready  = wready_reg;
    assign s_axi_bvalid  = bvalid_reg;
    assign s_axi_bresp   = 2'b00;

    always @(posedge aclk) begin
        if (!aresetn) begin
            awready_reg <= 0; wready_reg <= 0; bvalid_reg <= 0;
        end else begin
            awready_reg <= (s_axi_awvalid && !awready_reg) ? 1'b1 : 1'b0;
            wready_reg  <= (s_axi_wvalid  && !wready_reg)  ? 1'b1 : 1'b0;
            if      (awready_reg && wready_reg)      bvalid_reg <= 1'b1;
            else if (s_axi_bready && bvalid_reg)     bvalid_reg <= 1'b0;
        end
    end

    wire [2:0] wr_reg_addr = s_axi_awaddr[4:2];
    wire        result_valid_w;
    wire [3:0]  final_digit_w;
    wire        npu_busy;
    reg         done_latch;
    reg  [3:0]  final_digit_reg;

    always @(posedge aclk) begin
        if (!aresetn) begin
            slv_reg0 <= 0; slv_reg1 <= 0;
            done_latch <= 0; final_digit_reg <= 0;
        end else begin
            if (awready_reg && wready_reg) begin
                case (wr_reg_addr)
                    3'h0: slv_reg0 <= s_axi_wdata;
                    3'h1: slv_reg1 <= s_axi_wdata;
                    default: ;
                endcase
            end else if (slv_reg0[0]) begin
                slv_reg0[0] <= 1'b0;   // start self-clear
            end

            if (result_valid_w) begin
                done_latch      <= 1'b1;
                final_digit_reg <= final_digit_w;
            end
            if (awready_reg && wready_reg && wr_reg_addr == 3'h0)
                done_latch <= 1'b0;
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
    // [Part 2] 클럭 게이팅 기반 BRAM 픽셀 피더
    //
    //  핵심 아이디어:
    //    NPU(npu_v2_top)에 공급하는 클럭(npu_clk)을
    //    BRAM rvalid가 오는 클럭에만 HIGH 엣지가 발생하도록 게이팅.
    //
    //    → npu_conv2d_buf 내부의 buf_idx 증가와 pixel 소비가
    //      항상 BRAM 응답 도착 시점과 1:1로 동기화됨.
    //
    //  npu_clk 생성:
    //    npu_clk_en : posedge aclk에서 rvalid 감지 → 다음 반클럭에 HIGH
    //    npu_clk    : aclk AND npu_clk_en (글리치 방지: negedge에서 en 래치)
    // =========================================================

    localparam PF_IDLE   = 2'd0;
    localparam PF_STREAM = 2'd1;
    localparam PF_DONE   = 2'd2;

    reg [1:0]  pf_state;
    reg        busy_r;
    reg [7:0]  pixel_r;
    assign npu_busy = busy_r;

    wire [9:0] buf_idx_w;   // NPU → BRAM 주소

    // ── BRAM AR 채널 ─────────────────────────────────────
    assign m_axi_bram_araddr  = BRAM_ADDR_BASE + slv_reg1
                                + {20'd0, buf_idx_w, 2'b00};
    assign m_axi_bram_arvalid = (pf_state == PF_STREAM);
    assign m_axi_bram_rready  = 1'b1;

    // ── pixel 래치 ───────────────────────────────────────
    // rvalid 클럭에 pixel_r 업데이트 (npu_clk 엣지와 동일 시점)
    always @(posedge aclk) begin
        if (!aresetn)
            pixel_r <= 8'd0;
        else if (m_axi_bram_rvalid && pf_state == PF_STREAM)
            pixel_r <= m_axi_bram_rdata[7:0];
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
    //   clk  → npu_clk  (게이팅된 클럭: BRAM rvalid 클럭에만 엣지)
    //   pixel → pixel_r (BRAM rdata 래치값)
    //   start → slv_reg0[0] (CPU 펄스)
    //   reset_p → ~aresetn (active-high)
    // =========================================================
    npu_v2_top u_npu_v2 (
        .clk         (aclk),
        .reset_p     (~aresetn),
        .start       (slv_reg0[0]),
        .pixel       (pixel_r),
        .pixel_en    (m_axi_bram_rvalid),
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