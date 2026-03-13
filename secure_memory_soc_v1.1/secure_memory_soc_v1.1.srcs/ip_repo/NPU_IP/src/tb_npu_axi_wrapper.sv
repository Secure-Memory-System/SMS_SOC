`timescale 1ns / 1ps
/**
 * tb_npu_axi_wrapper.sv
 *
 * NPU AXI Wrapper 테스트벤치
 *
 * 동작 흐름:
 *   1. Reset
 *   2. AXI-Lite: slv_reg1(0x04) ← (28<<16)|28  (img_h:img_w)
 *   3. AXI-Lite: slv_reg0(0x00) ← 0x3           (pad_en=1, start=1)
 *   4. AXI-Stream: 784 픽셀 전송 (1픽셀/클럭)
 *   5. m_axis_tvalid 감지 → final_digit 출력
 *
 * 주의:
 *   - $readmemh 경로는 시뮬레이터 working directory 기준
 *   - Vivado XSim: Simulation 설정에서 "Simulation working directory" 확인
 *   - Dense MAC 연산(IN_FEATURES=845, 5뉴런) → 약 5000+ 클럭 필요
 *   - 타임아웃: 2,000,000 클럭 (100MHz 기준 20ms)
 *
 * 테스트 픽셀:
 *   - 기본: 외곽 테두리 숫자 '0' 모양 패턴
 *   - 파일 모드: IMG_FILE 파라미터 경로에 hex 파일 존재 시 자동 로드
 */

module tb_npu_axi_wrapper;

    // ─── 파라미터 ─────────────────────────────────────────────────────
    localparam CLK_PERIOD   = 10;       // 100 MHz
    localparam IMG_W        = 28;
    localparam IMG_H        = 28;
    localparam N_PIXELS     = IMG_W * IMG_H;  // 784
    localparam TIMEOUT_CLKS = 2_000_000;

    // ─── 클럭 / 리셋 ──────────────────────────────────────────────────
    reg aclk    = 0;
    reg aresetn = 0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // ─── AXI4-Lite Slave 포트 ────────────────────────────────────────
    reg  [4:0]  s_axi_awaddr  = 0;
    reg         s_axi_awvalid = 0;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata   = 0;
    reg  [3:0]  s_axi_wstrb   = 4'hF;
    reg         s_axi_wvalid  = 0;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready  = 1;
    reg  [4:0]  s_axi_araddr  = 0;
    reg         s_axi_arvalid = 0;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready  = 1;

    // ─── AXI4-Stream Slave 포트 (픽셀 입력) ──────────────────────────
    reg  [31:0] s_axis_tdata  = 0;
    reg         s_axis_tvalid = 0;
    wire        s_axis_tready;
    reg         s_axis_tlast  = 0;

    // ─── AXI4-Stream Master 포트 (결과 출력) ─────────────────────────
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready = 1;
    wire        m_axis_tlast;

    // ─── DUT ─────────────────────────────────────────────────────────
    npu_axi_wrapper u_dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
        // AXI-Lite
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        // AXI-Stream in
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        // AXI-Stream out
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast)
    );

    // ─── 테스트 픽셀 배열 ─────────────────────────────────────────────
    reg [7:0] pixels [0:N_PIXELS-1];

    // ─── 픽셀 초기화: '0' 숫자 테두리 패턴 ───────────────────────────
    integer idx, r, c;
    initial begin
        // 전체 0으로 초기화
        for (idx = 0; idx < N_PIXELS; idx = idx + 1)
            pixels[idx] = 8'd0;

        // 숫자 '0' 모양: 행 4~23, 열 6~21 영역의 테두리
        for (c = 6; c <= 21; c = c + 1) begin
            pixels[ 4*IMG_W + c] = 8'd200;   // 상단 가로선
            pixels[23*IMG_W + c] = 8'd200;   // 하단 가로선
        end
        for (r = 4; r <= 23; r = r + 1) begin
            pixels[r*IMG_W +  6] = 8'd200;   // 좌측 세로선
            pixels[r*IMG_W + 21] = 8'd200;   // 우측 세로선
        end
    end

    // ─── AXI-Lite 쓰기 태스크 ────────────────────────────────────────
    // npu_axi_wrapper의 AW/W ready 방식:
    //   awready = 1 (awvalid 왔을 때 다음 클럭 1클럭)
    //   wready  = 1 (wvalid  왔을 때 다음 클럭 1클럭)
    //   awready && wready가 동시에 → 레지스터 쓰기 + bvalid
    task automatic axi_lite_write;
        input [4:0]  addr;
        input [31:0] data;
        begin
            @(posedge aclk); #1;
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1;
            s_axi_wdata   = data;
            s_axi_wvalid  = 1;

            // awready & wready 모두 1이 될 때까지 대기
            @(posedge aclk);
            while (!(s_axi_awready && s_axi_wready)) @(posedge aclk);

            @(posedge aclk); #1;
            s_axi_awvalid = 0;
            s_axi_wvalid  = 0;

            // B channel 완료 대기
            while (!s_axi_bvalid) @(posedge aclk);
            @(posedge aclk);
        end
    endtask

    // ─── 시뮬레이션 메인 ─────────────────────────────────────────────
    integer      pix_i;
    integer      clk_cnt;
    reg          done_flag;
    reg [3:0]    result_digit;
    time         start_time, end_time;

    initial begin
        $display("================================================");
        $display("  NPU AXI Wrapper Testbench");
        $display("  Image: %0d x %0d = %0d pixels", IMG_W, IMG_H, N_PIXELS);
        $display("  Timeout: %0d clocks", TIMEOUT_CLKS);
        $display("================================================");

        // ── 리셋 ─────────────────────────────────────────────────────
        aresetn = 0;
        repeat(20) @(posedge aclk);
        aresetn = 1;
        repeat(5)  @(posedge aclk);
        $display("[%0t] Reset released.", $time);

        // ── Step 1: 해상도 설정 (reg1 = 0x04) ─────────────────────────
        $display("[%0t] Step1: AXI-Lite write reg1 = (28<<16)|28", $time);
        axi_lite_write(5'h04, (IMG_H << 16) | IMG_W);

        // ── Step 2: start + pad_en (reg0 = 0x00) ──────────────────────
        $display("[%0t] Step2: AXI-Lite write reg0 = 0x3 (start|pad_en)", $time);
        axi_lite_write(5'h00, 32'h0000_0003);

        // start 펄스가 npu_controller에 도달할 시간 확보
        repeat(3) @(posedge aclk);

        // ── Step 3: 784 픽셀 스트리밍 ─────────────────────────────────
        $display("[%0t] Step3: Streaming %0d pixels...", $time, N_PIXELS);
        start_time = $time;

        for (pix_i = 0; pix_i < N_PIXELS; pix_i = pix_i + 1) begin
            @(posedge aclk); #1;
            s_axis_tdata  = {24'b0, pixels[pix_i]};
            s_axis_tvalid = 1;
            s_axis_tlast  = (pix_i == N_PIXELS - 1) ? 1 : 0;
            // s_axis_tready = 1'b1 (always) → 매 클럭 수신
        end
        @(posedge aclk); #1;
        s_axis_tvalid = 0;
        s_axis_tlast  = 0;
        $display("[%0t] Step3: Pixel stream done.", $time);

        // ── Step 4: NPU 결과 대기 ─────────────────────────────────────
        $display("[%0t] Step4: Waiting for NPU result (Dense MAC 연산 중)...", $time);
        done_flag    = 0;
        result_digit = 0;

        for (clk_cnt = 0; clk_cnt < TIMEOUT_CLKS; clk_cnt = clk_cnt + 1) begin
            @(posedge aclk);
            if (m_axis_tvalid) begin
                end_time     = $time;
                result_digit = m_axis_tdata[3:0];
                done_flag    = 1;
                clk_cnt      = TIMEOUT_CLKS; // loop 탈출
            end
        end

        // ── 결과 출력 ─────────────────────────────────────────────────
        $display("================================================");
        if (done_flag) begin
            $display("  [PASS] NPU Result : digit = %0d", result_digit);
            $display("  Processing time   : %0d ns (%0d clocks)",
                     end_time - start_time,
                     (end_time - start_time) / CLK_PERIOD);
        end else begin
            $display("  [FAIL] TIMEOUT: NPU did not produce output!");
            $display("  Possible causes:");
            $display("    1. NPU controller never reached (27,27)");
            $display("       → pixel_valid count mismatch");
            $display("    2. flatten_dense FSM stuck");
            $display("       → check weight file loading");
            $display("    3. final_valid never fired");
        end
        $display("================================================");

        repeat(10) @(posedge aclk);
        $finish;
    end

    // ─── NPU 내부 상태 모니터링 ──────────────────────────────────────
    // npu_controller의 x_cnt, y_cnt를 직접 참조 (계층 경로)
    wire [15:0] mon_x = u_dut.u_npu.u_ctrl.x_cnt;
    wire [15:0] mon_y = u_dut.u_npu.u_ctrl.y_cnt;
    wire [1:0]  mon_state = u_dut.u_npu.u_ctrl.state;
    wire        mon_done  = u_dut.u_npu.u_ctrl.done_tick;
    wire [3:0]  mon_fc_state = u_dut.u_npu.u_fc.state;

    // 100 픽셀마다 진행상황 출력
    always @(posedge aclk) begin
        if (s_axis_tvalid && (mon_x == 0) && (mon_y % 7 == 0) && (mon_y != 0))
            $display("[%0t] [NPU] pixel progress: row y=%0d/27", $time, mon_y);
        if (mon_done)
            $display("[%0t] [NPU] done_tick! Conv→Pool 완료, Dense MAC 시작", $time);
        if (mon_fc_state == 4'd8)  // S_EVAL
            $display("[%0t] [NPU] flatten_dense S_EVAL → best class 계산 중", $time);
    end

    // ─── 글로벌 타임아웃 ─────────────────────────────────────────────
    initial begin
        #(TIMEOUT_CLKS * CLK_PERIOD * 2);
        $display("[FATAL] Global timeout exceeded!");
        $finish;
    end

endmodule
