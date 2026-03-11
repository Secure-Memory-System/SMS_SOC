`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : npu_v2_axi_wrapper
// Description : AXI4-Lite Slave(CPU제어) + AXI4 Master(BRAM읽기) +
//               AXI4-Stream Master(결과출력) wrapper for npu_v2_top
//
// ── m_axi_img Write 채널 더미 포트 추가 이력 ─────────────────────────────
//   Vivado Block Design에서 BRAM Controller Port B 연결 시
//   "no matching connection" 오류 발생 원인:
//     m_axi_img에 AR+R 채널만 존재 → AXI Master 인터페이스 불완전
//     BRAM Controller는 AW+W+B+AR+R 5채널 전부 요구
//
//   해결: Write 채널(AW+W+B) 더미 포트 추가
//     - output 포트: 0으로 tie-off (쓰기 요청 절대 발생 안 함)
//     - input  포트: 연결만 하고 내부에서 사용 안 함
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
            if      (awready_reg && wready_reg)  bvalid_reg <= 1'b1;
            else if (s_axi_bready && bvalid_reg) bvalid_reg <= 1'b0;
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
    // [Part 2] BRAM 픽셀 피더
    // =========================================================
    localparam PF_IDLE   = 2'd0;
    localparam PF_STREAM = 2'd1;
    localparam PF_DONE   = 2'd2;

    reg [1:0]  pf_state;
    reg        busy_r;
    reg [7:0]  pixel_r;
    assign npu_busy = busy_r;

    wire [9:0] buf_idx_w;

    // ── BRAM AR 채널 ─────────────────────────────────────
    assign m_axi_img_araddr  = BRAM_ADDR_BASE + slv_reg1
                               + {20'd0, buf_idx_w, 2'b00};
    assign m_axi_img_arvalid = (pf_state == PF_STREAM);
    assign m_axi_img_rready  = 1'b1;

    // ── pixel 래치 ───────────────────────────────────────
    always @(posedge aclk) begin
        if (!aresetn)
            pixel_r <= 8'd0;
        else if (m_axi_img_rvalid && pf_state == PF_STREAM)
            pixel_r <= m_axi_img_rdata[7:0];
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
        .pixel_en    (m_axi_img_rvalid),
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