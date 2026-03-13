`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: npu_test
// Description: NPU AXI Wrapper 멀티 숫자 테스트벤치 (0~9 순서 테스트)
//////////////////////////////////////////////////////////////////////////////////

module npu_test;

    // =========================================================
    // 파라미터
    // =========================================================
    localparam CLK_PERIOD   = 10;
    localparam IMG_W        = 28;
    localparam IMG_H        = 28;
    localparam N_PIXELS     = IMG_W * IMG_H; // 784
    localparam TIMEOUT_CLKS = 2_000_000;

    // =========================================================
    // 클럭 / 리셋
    // =========================================================
    reg aclk    = 0;
    reg aresetn = 0;
    always #(CLK_PERIOD / 2) aclk = ~aclk;

    // =========================================================
    // AXI4-Lite 포트
    // =========================================================
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

    // =========================================================
    // AXI4-Stream 포트
    // =========================================================
    reg  [31:0] s_axis_tdata  = 0;
    reg         s_axis_tvalid = 0;
    wire        s_axis_tready;
    reg         s_axis_tlast  = 0;

    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready = 1;
    wire        m_axis_tlast;

    // =========================================================
    // DUT
    // =========================================================
    npu_axi_wrapper u_dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
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
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast)
    );

    // =========================================================
    // 픽셀 배열
    // =========================================================
    reg [7:0] pixels [0:N_PIXELS-1];

    // =========================================================
    // 내부 신호 모니터링
    // =========================================================
    wire [15:0] mon_x    = u_dut.u_npu.u_ctrl.x_cnt;
    wire [15:0] mon_y    = u_dut.u_npu.u_ctrl.y_cnt;
    wire        mon_done = u_dut.u_npu.u_ctrl.done_tick;
    wire [3:0]  mon_fc   = u_dut.u_npu.u_fc.state;

    // =========================================================
    // 숫자별 픽셀 패턴 생성 태스크
    // (28x28, 유효 영역: row 4~23, col 6~21)
    //
    //  0 : 사각형 테두리
    //  1 : 중앙 세로선
    //  2 : 상단 + 우상 세로 + 중간 + 좌하 세로 + 하단
    //  3 : 상단 + 우측 세로 + 중간 + 하단
    //  4 : 좌상 세로 + 중간 + 우측 세로
    //  5 : 상단 + 좌상 세로 + 중간 + 우하 세로 + 하단
    //  6 : 상단 + 좌측 세로 + 중간 + 우하 세로 + 하단
    //  7 : 상단 + 우측 세로
    //  8 : 사각형 테두리 + 중간 가로선
    //  9 : 상단 + 좌상 세로 + 중간 + 우측 세로 + 하단
    // =========================================================
    integer _i, _r, _c;

    task automatic gen_digit;
        input [3:0] digit;
        begin
            for (_i = 0; _i < N_PIXELS; _i = _i + 1)
                pixels[_i] = 8'd0;

            case (digit)
                4'd0: begin
                    for (_c = 6; _c <= 21; _c = _c + 1) begin
                        pixels[ 4*IMG_W + _c] = 8'd200;
                        pixels[23*IMG_W + _c] = 8'd200;
                    end
                    for (_r = 4; _r <= 23; _r = _r + 1) begin
                        pixels[_r*IMG_W +  6] = 8'd200;
                        pixels[_r*IMG_W + 21] = 8'd200;
                    end
                end
                4'd1: begin
                    // 중앙 세로선 + 상단 왼쪽 사선(serif)
                    pixels[4*IMG_W + 10] = 8'd200;
                    pixels[4*IMG_W + 11] = 8'd200;
                    pixels[4*IMG_W + 12] = 8'd200;
                    for (_r = 4; _r <= 23; _r = _r + 1)
                        pixels[_r*IMG_W + 13] = 8'd200;
                end
                4'd2: begin
                    for (_c = 6; _c <= 21; _c = _c + 1) begin
                        pixels[ 4*IMG_W + _c] = 8'd200;
                        pixels[13*IMG_W + _c] = 8'd200;
                        pixels[23*IMG_W + _c] = 8'd200;
                    end
                    for (_r = 4;  _r <= 13; _r = _r + 1)
                        pixels[_r*IMG_W + 21] = 8'd200;
                    for (_r = 13; _r <= 23; _r = _r + 1)
                        pixels[_r*IMG_W +  6] = 8'd200;
                end
                4'd3: begin
                    for (_c = 6; _c <= 21; _c = _c + 1) begin
                        pixels[ 4*IMG_W + _c] = 8'd200;
                        pixels[13*IMG_W + _c] = 8'd200;
                        pixels[23*IMG_W + _c] = 8'd200;
                    end
                    for (_r = 4; _r <= 23; _r = _r + 1)
                        pixels[_r*IMG_W + 21] = 8'd200;
                end
                4'd4: begin
                    for (_r = 4; _r <= 13; _r = _r + 1)
                        pixels[_r*IMG_W +  6] = 8'd200;
                    for (_c = 6; _c <= 21; _c = _c + 1)
                        pixels[13*IMG_W + _c] = 8'd200;
                    for (_r = 4; _r <= 23; _r = _r + 1)
                        pixels[_r*IMG_W + 21] = 8'd200;
                end
                4'd5: begin
                    for (_c = 6; _c <= 21; _c = _c + 1) begin
                        pixels[ 4*IMG_W + _c] = 8'd200;
                        pixels[13*IMG_W + _c] = 8'd200;
                        pixels[23*IMG_W + _c] = 8'd200;
                    end
                    for (_r = 4;  _r <= 13; _r = _r + 1)
                        pixels[_r*IMG_W +  6] = 8'd200;
                    for (_r = 13; _r <= 23; _r = _r + 1)
                        pixels[_r*IMG_W + 21] = 8'd200;
                end
                4'd6: begin
                    for (_c = 6; _c <= 21; _c = _c + 1) begin
                        pixels[ 4*IMG_W + _c] = 8'd200;
                        pixels[13*IMG_W + _c] = 8'd200;
                        pixels[23*IMG_W + _c] = 8'd200;
                    end
                    for (_r = 4;  _r <= 23; _r = _r + 1)
                        pixels[_r*IMG_W +  6] = 8'd200;
                    for (_r = 13; _r <= 23; _r = _r + 1)
                        pixels[_r*IMG_W + 21] = 8'd200;
                end
                4'd7: begin
                    for (_c = 6; _c <= 21; _c = _c + 1)
                        pixels[4*IMG_W + _c] = 8'd200;
                    for (_r = 4; _r <= 23; _r = _r + 1)
                        pixels[_r*IMG_W + 21] = 8'd200;
                end
                4'd8: begin
                    for (_c = 6; _c <= 21; _c = _c + 1) begin
                        pixels[ 4*IMG_W + _c] = 8'd200;
                        pixels[13*IMG_W + _c] = 8'd200;
                        pixels[23*IMG_W + _c] = 8'd200;
                    end
                    for (_r = 4; _r <= 23; _r = _r + 1) begin
                        pixels[_r*IMG_W +  6] = 8'd200;
                        pixels[_r*IMG_W + 21] = 8'd200;
                    end
                end
                4'd9: begin
                    for (_c = 6; _c <= 21; _c = _c + 1) begin
                        pixels[ 4*IMG_W + _c] = 8'd200;
                        pixels[13*IMG_W + _c] = 8'd200;
                        pixels[23*IMG_W + _c] = 8'd200;
                    end
                    for (_r = 4;  _r <= 13; _r = _r + 1)
                        pixels[_r*IMG_W +  6] = 8'd200;
                    for (_r = 4;  _r <= 23; _r = _r + 1)
                        pixels[_r*IMG_W + 21] = 8'd200;
                end
                default: begin end
            endcase
        end
    endtask

    // =========================================================
    // AXI-Lite 쓰기 태스크
    // =========================================================
    task automatic axi_lite_write;
        input [4:0]  addr;
        input [31:0] data;
        begin
            @(posedge aclk); #1;
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1;
            s_axi_wdata   = data;
            s_axi_wvalid  = 1;
            @(posedge aclk);
            while (!(s_axi_awready && s_axi_wready)) @(posedge aclk);
            @(posedge aclk); #1;
            s_axi_awvalid = 0;
            s_axi_wvalid  = 0;
            while (!s_axi_bvalid) @(posedge aclk);
            @(posedge aclk);
        end
    endtask

    // =========================================================
    // 추론 실행 태스크 (리셋 → 설정 → 스트리밍 → 결과 대기)
    // =========================================================
    integer pix_i, clk_cnt;
    reg     done_flag;
    reg [3:0] result_digit;
    time      t0, t1;

    task automatic run_inference;
        input [3:0] test_digit;
        begin
            // 리셋
            aresetn = 0;
            repeat(20) @(posedge aclk);
            aresetn = 1;
            repeat(5)  @(posedge aclk);

            // Step1: 해상도 설정
            axi_lite_write(5'h04, (IMG_H << 16) | IMG_W);
            // Step2: start + pad_en
            axi_lite_write(5'h00, 32'h0000_0003);
            repeat(3) @(posedge aclk);

            // Step3: 픽셀 스트리밍
            t0 = $time;
            for (pix_i = 0; pix_i < N_PIXELS; pix_i = pix_i + 1) begin
                @(posedge aclk); #1;
                s_axis_tdata  = {24'b0, pixels[pix_i]};
                s_axis_tvalid = 1;
                s_axis_tlast  = (pix_i == N_PIXELS - 1) ? 1'b1 : 1'b0;
            end
            @(posedge aclk); #1;
            s_axis_tvalid = 0;
            s_axis_tlast  = 0;

            // Step4: 결과 대기
            done_flag    = 0;
            result_digit = 0;
            for (clk_cnt = 0; clk_cnt < TIMEOUT_CLKS; clk_cnt = clk_cnt + 1) begin
                @(posedge aclk);
                if (m_axis_tvalid) begin
                    t1           = $time;
                    result_digit = m_axis_tdata[3:0];
                    done_flag    = 1;
                    clk_cnt      = TIMEOUT_CLKS;
                end
            end

            // 결과 출력
            if (done_flag) begin
                if (result_digit == test_digit)
                    $display("  [PASS] 입력: %0d  →  인식: %0d   (%0d clocks)",
                             test_digit, result_digit, (t1 - t0) / CLK_PERIOD);
                else
                    $display("  [FAIL] 입력: %0d  →  인식: %0d   (%0d clocks)  ← 오분류",
                             test_digit, result_digit, (t1 - t0) / CLK_PERIOD);
            end else begin
                $display("  [FAIL] 입력: %0d  →  타임아웃 (mon_ctrl=%0d x=%0d y=%0d fc=%0d)",
                         test_digit, u_dut.u_npu.u_ctrl.state,
                         mon_x, mon_y, mon_fc);
            end
        end
    endtask

    // =========================================================
    // 메인: 0~9 순서 테스트
    // =========================================================
    integer d;

    initial begin
        $display("================================================");
        $display("  NPU Multi-Digit Test   (기하학적 패턴 0~9)");
        $display("  Image : %0d x %0d  |  Timeout : %0d clocks",
                 IMG_W, IMG_H, TIMEOUT_CLKS);
        $display("================================================");

        for (d = 0; d <= 9; d = d + 1) begin
            $display("------------------------------------------------");
            $display("  [Digit %0d]", d);
            gen_digit(d[3:0]);
            run_inference(d[3:0]);
        end

        $display("================================================");
        $display("  All Tests Done");
        $display("================================================");
        $finish;
    end

    // =========================================================
    // 글로벌 타임아웃 (10개 숫자 × 3배 여유)
    // =========================================================
    initial begin
        #(TIMEOUT_CLKS * CLK_PERIOD * 3 * 10);
        $display("[FATAL] 글로벌 타임아웃 초과!");
        $finish;
    end

endmodule
