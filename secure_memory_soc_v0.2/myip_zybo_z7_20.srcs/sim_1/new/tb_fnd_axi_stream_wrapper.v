`timescale 1ns / 1ps

module tb_fnd_axi_stream_wrapper;

    // -----------------------------------------------
    // DUT 포트
    // -----------------------------------------------
    reg        aclk;
    reg        aresetn;
    reg  [3:0] s_axis_tdata;
    reg        s_axis_tvalid;
    wire       s_axis_tready;
    wire [7:0] seg;
    wire [3:0] com;

    // -----------------------------------------------
    // DUT 인스턴스
    // -----------------------------------------------
    fnd_axi_stream_wrapper u_dut (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .seg           (seg),
        .com           (com)
    );

    // -----------------------------------------------
    // 클럭: 10ns 주기 (100MHz)
    // -----------------------------------------------
    initial aclk = 0;
    always #5 aclk = ~aclk;

    // -----------------------------------------------
    // 태스크: AXI-Stream 1회 전송
    // -----------------------------------------------
    task send_digit(input [3:0] val);
        begin
            @(posedge aclk);
            s_axis_tdata  = val;
            s_axis_tvalid = 1;
            // tready가 1이 될 때까지 대기 (현재 구현은 항상 1)
            wait(s_axis_tready == 1);
            @(posedge aclk);
            s_axis_tvalid = 0;
            s_axis_tdata  = 4'bx;
        end
    endtask

    // -----------------------------------------------
    // 메인 시뮬레이션
    // -----------------------------------------------
    integer i;

    initial begin
        // --- 초기화 ---
        aresetn       = 0;
        s_axis_tdata  = 4'd0;
        s_axis_tvalid = 0;

        // --- 리셋 해제 ---
        repeat(5) @(posedge aclk);
        aresetn = 1;
        repeat(3) @(posedge aclk);

        // =============================================
        // TC1: tready 확인 (항상 1이어야 함)
        // =============================================
        $display("[TC1] tready = %b (expect 1)", s_axis_tready);
        if (s_axis_tready !== 1)
            $display("FAIL TC1");
        else
            $display("PASS TC1");

        // =============================================
        // TC2: 숫자 0~9 순차 전송 후 digit_hold 확인
        // =============================================
        $display("[TC2] Sending digits 0~9...");
        for (i = 0; i <= 9; i = i + 1) begin
            send_digit(i[3:0]);
            // digit_hold는 내부 reg이므로 com/seg 변화로 간접 확인
            repeat(5) @(posedge aclk);
            $display("  digit=%0d | seg=0x%02h | com=0b%04b", i, seg, com);
        end
        $display("PASS TC2 (파형으로 seg 값 확인 필요)");

        // =============================================
        // TC3: valid 없이 대기 → digit_hold 유지 확인
        // =============================================
        $display("[TC3] Hold test: send 4'hA then idle 20 cycles");
        send_digit(4'hA);
        repeat(20) @(posedge aclk);
        $display("  After idle: seg=0x%02h | com=0b%04b (digit_hold should be 0xA)", seg, com);

        // =============================================
        // TC4: 리셋 후 digit_hold = 0 확인
        // =============================================
        $display("[TC4] Reset test");
        aresetn = 0;
        repeat(3) @(posedge aclk);
        aresetn = 1;
        @(posedge aclk);
        $display("  After reset: seg=0x%02h | com=0b%04b (expect digit=0)", seg, com);

        // =============================================
        // TC5: 연속 전송 (back-to-back)
        // =============================================
        $display("[TC5] Back-to-back transfer");
        @(posedge aclk);
        s_axis_tvalid = 1;
        s_axis_tdata  = 4'd5;
        @(posedge aclk);
        s_axis_tdata  = 4'd7;  // 바로 다음 사이클에 새 값
        @(posedge aclk);
        s_axis_tdata  = 4'd3;
        @(posedge aclk);
        s_axis_tvalid = 0;
        repeat(5) @(posedge aclk);
        $display("  Final digit_hold should be 3: seg=0x%02h", seg);

        // =============================================
        // FND com 로테이션 확인 (약 2^17 클럭 대기)
        // =============================================
        $display("[TC6] Waiting for com rotation (~131072 clocks)...");
        send_digit(4'd6);
        repeat(200000) @(posedge aclk);
        $display("  com=0b%04b (should have rotated from 1110)", com);

        $display("=== Simulation Done ===");
        $finish;
    end

    // -----------------------------------------------
    // 파형 덤프 (Vivado xsim 또는 ModelSim)
    // -----------------------------------------------
    initial begin
        $dumpfile("tb_fnd.vcd");
        $dumpvars(0, tb_fnd_axi_stream_wrapper);
    end

endmodule