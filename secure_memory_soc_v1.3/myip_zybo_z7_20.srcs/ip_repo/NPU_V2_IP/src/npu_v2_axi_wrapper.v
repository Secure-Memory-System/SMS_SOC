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
    // [Part 2] BRAM 픽셀 피더 (기상 지연 + 데이터 유실 완벽 방지)
    // =========================================================
    localparam PF_IDLE   = 3'd0;
    localparam PF_WAIT   = 3'd1; // ★ NPU가 깨어날 시간을 주는 대기 상태
    localparam PF_STREAM = 3'd2;
    localparam PF_DONE   = 3'd3;

    reg [2:0]  pf_state;
    reg [4:0]  wait_cnt; // 대기 카운터
    reg        busy_r;
    reg [7:0]  pixel_r;
    reg [31:0] word_buf;
    reg [1:0]  byte_sel;
    reg        word_valid;
    reg        pixel_en_r;
    assign npu_busy = busy_r;

    wire [9:0] buf_idx_w;

    // ── BRAM AR / R 채널 ─────────────────────────────────────
    reg ar_pending;
    reg [7:0] word_count;
    
    // 언팩(Unpack) 중일 때는 rready를 0으로 내려서 새 데이터를 거부
    assign m_axi_img_rready = (pf_state == PF_STREAM) && !word_valid;

    always @(posedge aclk) begin
        if (!aresetn) begin
            ar_pending <= 1'b0;
            word_count <= 8'd0;
        end else begin
            // AR 채널 핸드셰이크
            if (m_axi_img_arvalid && m_axi_img_arready)
                ar_pending <= 1'b1; 
            else if (m_axi_img_rvalid && m_axi_img_rready) 
                ar_pending <= 1'b0; 

            // 워드 카운터
            if (pf_state == PF_IDLE)
                word_count <= 8'd0;
            else if (m_axi_img_rvalid && m_axi_img_rready) 
                word_count <= word_count + 1'b1;
        end
    end
    
    // 196워드(784픽셀)까지만 정확히 요청
    assign m_axi_img_arvalid = (pf_state == PF_STREAM) && !ar_pending && !word_valid && (word_count < 8'd196);
    assign m_axi_img_araddr = BRAM_ADDR_BASE + slv_reg1 + {22'd0, word_count, 2'b00};

    wire npu_pixel_ready_w; // [추가됨] NPU로부터 받을 Ready 신호

    // ── pixel 래치 및 핸드셰이킹 로직 ───────────────────────────────────────
    always @(posedge aclk) begin
        if (!aresetn) begin
            word_buf   <= 0;
            byte_sel   <= 0;
            word_valid <= 0;
            pixel_en_r <= 0;
            pixel_r    <= 0;
        end else begin
            // m_axi_img_rready 조건은 기존대로 유지됨 ((pf_state == PF_STREAM) && !word_valid)
            if (m_axi_img_rvalid && m_axi_img_rready) begin
                // 버스가 새 32bit 데이터를 줬을 때 (Byte 0 세팅)
                word_buf   <= m_axi_img_rdata;
                pixel_r    <= m_axi_img_rdata[7:0]; // Byte 0 추출
                pixel_en_r <= 1'b1;
                byte_sel   <= 2'd1;                 // 다음은 Byte 1
                word_valid <= 1'b1;
            end 
            // [수정됨] 무조건 넘기지 않고, NPU가 픽셀을 먹었을 때(Ready)만 다음으로 넘어감
            else if (word_valid && pixel_en_r && npu_pixel_ready_w) begin
                if (byte_sel == 2'd0) begin
                    // Byte 3까지 NPU에 모두 밀어넣음 -> 새 AXI Read를 위해 비움
                    word_valid <= 1'b0;
                    pixel_en_r <= 1'b0; // 다음 AXI 응답이 올 때까지 pixel_en 중단
                end else begin
                    // 다음 Byte를 pixel_r에 준비
                    case (byte_sel)
                        2'd1: pixel_r <= word_buf[15:8];
                        2'd2: pixel_r <= word_buf[23:16];
                        2'd3: pixel_r <= word_buf[31:24];
                        default: ;
                    endcase
                    byte_sel <= byte_sel + 1'b1; // 1->2, 2->3, 3->0 순환
                end
            end
            // Ready가 아니면 pixel_en_r과 pixel_r 값을 그대로 유지 (Hold)
        end
    end

    // ── Pixel Feeder FSM ─────────────────────────────────
    always @(posedge aclk) begin
        if (!aresetn) begin
            pf_state <= PF_IDLE;
            busy_r   <= 1'b0;
            wait_cnt <= 0;
        end else begin
            case (pf_state)
                PF_IDLE: begin
                    if (slv_reg0[0]) begin
                        pf_state <= PF_WAIT; // ★ 바로 쏘지 않고 WAIT 상태로 진입
                        busy_r   <= 1'b1;
                        wait_cnt <= 0;
                    end
                end
                PF_WAIT: begin // ★ NPU 내부 초기화 시간을 넉넉히 20클럭 보장
                    if (wait_cnt == 5'd20)
                        pf_state <= PF_STREAM;
                    else
                        wait_cnt <= wait_cnt + 1'b1;
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
        .pixel_en    (pixel_en_r),
        .buf_idx     (buf_idx_w),
        .final_digit (final_digit_w),
        .result_valid(result_valid_w),
        .pixel_ready (npu_pixel_ready_w)  // [추가됨] 신호 연결
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