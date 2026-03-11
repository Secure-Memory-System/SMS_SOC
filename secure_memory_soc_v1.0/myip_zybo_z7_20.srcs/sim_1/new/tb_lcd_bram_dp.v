`timescale 1ns / 1ps

/**
 * tb_lcd_bram_dp
 *
 * Verification:
 *   1. Port A write -> Port A read (basic)
 *   2. Port A write & Port B read simultaneously (dual-port access)
 *   3. Sequential write all 784 addresses -> Port B full read check
 *   4. Write-First behavior (douta updates same cycle as write)
 */
module tb_lcd_bram_dp;

    parameter CLK_PERIOD = 10;
    parameter DEPTH = 784; // 28*28

    // =========================================================
    // DUT ports
    // =========================================================
    reg        clka;
    reg        ena,  enb;
    reg        wea;
    reg  [9:0] addra, addrb;
    reg  [7:0] dina;
    wire [7:0] douta, doutb;

    // =========================================================
    // DUT instance
    // =========================================================
    lcd_bram_dp #(
        .WIDTH (8),
        .DEPTH (DEPTH)
    ) dut (
        .clka  (clka),
        .ena   (ena),
        .wea   (wea),
        .addra (addra),
        .dina  (dina),
        .douta (douta),
        .clkb  (clka),
        .enb   (enb),
        .addrb (addrb),
        .doutb (doutb)
    );

    // =========================================================
    // Clock (same clock, same phase for both ports)
    // =========================================================
    initial clka = 0;
    always #(CLK_PERIOD/2) clka = ~clka;

    // =========================================================
    // Task: Port A write
    // =========================================================
    task porta_write;
        input [9:0] addr;
        input [7:0] data;
        begin
            @(posedge clka);
            ena   <= 1; wea <= 1;
            addra <= addr;
            dina  <= data;
            @(posedge clka);
            wea <= 0;
        end
    endtask

    // =========================================================
    // Task: Port A read (douta valid 1 cycle later)
    // =========================================================
    task porta_read;
        input [9:0] addr;
        begin
            @(posedge clka);
            ena   <= 1; wea <= 0;
            addra <= addr;
            @(posedge clka);
        end
    endtask

    // =========================================================
    // Task: Port B read
    // =========================================================
    task portb_read;
        input [9:0] addr;
        begin
            @(posedge clka);
            enb   <= 1;
            addrb <= addr;
            @(posedge clka);
        end
    endtask

    // =========================================================
    // Main scenario
    // =========================================================
    integer i;
    integer fail_cnt;

    initial begin
        ena = 0; enb = 0;
        wea = 0;
        addra = 0; addrb = 0;
        dina  = 0;
        fail_cnt = 0;

        repeat(5) @(posedge clka);

        // -----------------------------------------------
        // [TEST 1] Port A write -> Port A read
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 1] Port A write -> Port A read");
        $display("========================================");

        porta_write(10'd0,   8'hAA);
        porta_write(10'd1,   8'hBB);
        porta_write(10'd100, 8'h55);
        porta_write(10'd783, 8'hFF);

        porta_read(10'd0);
        #1;
        if (douta === 8'hAA)
            $display("[PASS] addr=0: 0x%02h", douta);
        else begin
            $display("[FAIL] addr=0: expected=0xAA, actual=0x%02h", douta);
            fail_cnt = fail_cnt + 1;
        end

        porta_read(10'd1);
        #1;
        if (douta === 8'hBB)
            $display("[PASS] addr=1: 0x%02h", douta);
        else begin
            $display("[FAIL] addr=1: expected=0xBB, actual=0x%02h", douta);
            fail_cnt = fail_cnt + 1;
        end

        porta_read(10'd783);
        #1;
        if (douta === 8'hFF)
            $display("[PASS] addr=783: 0x%02h", douta);
        else begin
            $display("[FAIL] addr=783: expected=0xFF, actual=0x%02h", douta);
            fail_cnt = fail_cnt + 1;
        end

        // -----------------------------------------------
        // [TEST 2] Port A write & Port B read simultaneously
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 2] Simultaneous Port A write & Port B read");
        $display("========================================");

        @(posedge clka);
        ena   <= 1; wea <= 1; addra <= 10'd50; dina <= 8'h12;
        enb   <= 1;           addrb <= 10'd100;
        @(posedge clka);
        wea <= 0;
        #1;
        if (doutb === 8'h55)
            $display("[PASS] Port B addr=100: 0x%02h (simultaneous access OK)", doutb);
        else begin
            $display("[FAIL] Port B addr=100: expected=0x55, actual=0x%02h", doutb);
            fail_cnt = fail_cnt + 1;
        end

        porta_read(10'd50);
        #1;
        if (douta === 8'h12)
            $display("[PASS] Port A addr=50: 0x%02h", douta);
        else begin
            $display("[FAIL] Port A addr=50: expected=0x12, actual=0x%02h", douta);
            fail_cnt = fail_cnt + 1;
        end

        // -----------------------------------------------
        // [TEST 3] Sequential write all 784 -> Port B full read
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 3] Full 784-byte sequential write -> Port B read");
        $display("========================================");

        for (i = 0; i < DEPTH; i = i + 1) begin
            @(posedge clka);
            ena <= 1; wea <= 1;
            addra <= i[9:0];
            dina  <= i[7:0];
        end
        @(posedge clka); wea <= 0;

        begin : check_all
            integer err_cnt;
            err_cnt = 0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                @(posedge clka);
                enb   <= 1;
                addrb <= i[9:0];
                @(posedge clka);
                #1;
                if (doutb !== i[7:0]) begin
                    $display("[FAIL] Port B addr=%0d: expected=0x%02h, actual=0x%02h",
                             i, i[7:0], doutb);
                    err_cnt = err_cnt + 1;
                    if (err_cnt > 5) begin
                        $display("Too many errors, stopping output.");
                        fail_cnt = fail_cnt + err_cnt;
                        disable check_all;
                    end
                end
            end
            if (err_cnt == 0)
                $display("[PASS] All 784 bytes verified via Port B!");
            else begin
                $display("[FAIL] Error count: %0d", err_cnt);
                fail_cnt = fail_cnt + err_cnt;
            end
        end

        // -----------------------------------------------
        // [TEST 4] Write-First check
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 4] Write-First (douta = dina same cycle)");
        $display("========================================");

        @(posedge clka);
        ena <= 1; wea <= 1; addra <= 10'd200; dina <= 8'hDE;
        @(posedge clka);
        #1;
        if (douta === 8'hDE)
            $display("[PASS] Write-First: douta=0x%02h (write value reflected immediately)", douta);
        else
            $display("[INFO] Read-First mode: douta=0x%02h (not a failure, just mode info)", douta);
        wea <= 0;

        // -----------------------------------------------
        // Final result
        // -----------------------------------------------
        $display("\n========================================");
        if (fail_cnt == 0)
            $display("All tests PASSED!");
        else
            $display("FAILED: %0d error(s)", fail_cnt);
        $display("========================================\n");

        $finish;
    end

    // =========================================================
    // Waveform dump
    // =========================================================
    initial begin
        $dumpfile("tb_lcd_bram_dp.vcd");
        $dumpvars(0, tb_lcd_bram_dp);
    end

endmodule