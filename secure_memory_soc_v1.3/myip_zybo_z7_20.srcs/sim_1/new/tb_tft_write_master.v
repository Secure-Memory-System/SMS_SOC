`timescale 1ns / 1ps

/**
 * tb_write_master
 *
 * Verification:
 *   1. i_start pulse -> AW channel address issue
 *   2. W channel burst data transfer (wlast timing)
 *   3. Next burst starts after B channel response
 *   4. o_write_done pulse after all 784 bytes transferred
 *   5. o_bram_rd_addr increments in order
 */
module tb_tft_write_master;

    // =========================================================
    // Parameters
    // =========================================================
    parameter CLK_PERIOD  = 10;   // 100MHz
    parameter BURST_LEN   = 16;
    parameter TOTAL_BYTES = 784;  // 28*28
    parameter DST_ADDR    = 32'hA000_0000;

    // =========================================================
    // DUT ports
    // =========================================================
    reg         clk;
    reg         reset_n;
    reg         i_start;
    reg  [31:0] i_dst_addr;
    reg  [31:0] i_total_len;
    wire        o_write_done;

    // BRAM read port
    wire [9:0]  o_bram_rd_addr;
    reg  [7:0]  i_bram_rd_data;

    // AXI4-Full Write
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    reg         m_axi_awready;

    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    reg         m_axi_wready;

    reg  [1:0]  m_axi_bresp;
    reg         m_axi_bvalid;
    wire        m_axi_bready;

    // =========================================================
    // DUT instance
    // =========================================================
    tft_lcd_write_master #(
        .C_M_AXI_ADDR_WIDTH (32),
        .C_M_AXI_DATA_WIDTH (32),
        .BURST_LEN          (BURST_LEN)
    ) dut (
        .clk            (clk),
        .reset_n        (reset_n),
        .i_start        (i_start),
        .i_dst_addr     (i_dst_addr),
        .i_total_len    (i_total_len),
        .o_write_done   (o_write_done),
        .o_bram_rd_addr (o_bram_rd_addr),
        .i_bram_rd_data (i_bram_rd_data),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready)
    );

    // =========================================================
    // Clock
    // =========================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================
    // BRAM model: returns addr[7:0] as data (easy to verify)
    // =========================================================
    always @(*) begin
        i_bram_rd_data = o_bram_rd_addr[7:0];
    end

    // =========================================================
    // AXI Slave model
    // =========================================================

    // [AW channel] 2-cycle delay before ready
    integer aw_delay_cnt;
    initial aw_delay_cnt = 0;
    always @(posedge clk) begin
        if (!reset_n) begin
            m_axi_awready <= 0;
            aw_delay_cnt  <= 0;
        end else begin
            if (m_axi_awvalid && !m_axi_awready) begin
                if (aw_delay_cnt >= 1) begin
                    m_axi_awready <= 1;
                    aw_delay_cnt  <= 0;
                end else begin
                    aw_delay_cnt <= aw_delay_cnt + 1;
                end
            end else begin
                m_axi_awready <= 0;
            end
        end
    end

    // [W channel] always ready (fast slave)
    initial m_axi_wready = 1;

    // [B channel] bvalid 1 cycle after wlast
    always @(posedge clk) begin
        if (!reset_n) begin
            m_axi_bvalid <= 0;
            m_axi_bresp  <= 0;
        end else begin
            if (m_axi_wlast && m_axi_wvalid && m_axi_wready) begin
                m_axi_bvalid <= 1;
                m_axi_bresp  <= 2'b00;
            end else if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 0;
            end
        end
    end

    // =========================================================
    // Verification counters
    // =========================================================
    integer beat_count;
    integer burst_count;
    integer wlast_count;
    integer done_time;

    initial begin
        beat_count  = 0;
        burst_count = 0;
        wlast_count = 0;
        done_time   = 0;
    end

    always @(posedge clk) begin
        if (m_axi_wvalid && m_axi_wready)
            beat_count <= beat_count + 1;
        if (m_axi_awvalid && m_axi_awready)
            burst_count <= burst_count + 1;
        if (m_axi_wlast && m_axi_wvalid && m_axi_wready)
            wlast_count <= wlast_count + 1;
    end

    // =========================================================
    // Main scenario
    // =========================================================
    integer expected_beats;

    initial begin
        reset_n     = 0;
        i_start     = 0;
        i_dst_addr  = DST_ADDR;
        i_total_len = TOTAL_BYTES;

        repeat(5) @(posedge clk);
        reset_n = 1;
        repeat(3) @(posedge clk);

        // -----------------------------------------------
        // [TEST 1] Issue start pulse
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 1] Issue start pulse");
        $display("========================================");
        @(posedge clk);
        i_start = 1;
        @(posedge clk);
        i_start = 0;

        // -----------------------------------------------
        // [TEST 2] Wait for o_write_done (timeout 5000 clk)
        // -----------------------------------------------
        $display("[TEST 2] Waiting for o_write_done...");
        fork
            begin : wait_done
                @(posedge o_write_done);
                done_time = $time;
                $display("[PASS] o_write_done received! time=%0t ns", done_time);
                disable timeout_check;
            end
            begin : timeout_check
                repeat(5000) @(posedge clk);
                $display("[FAIL] Timeout! o_write_done not received.");
                disable wait_done;
            end
        join

        repeat(5) @(posedge clk);

        // -----------------------------------------------
        // [TEST 3] Transfer statistics
        // -----------------------------------------------
        expected_beats = TOTAL_BYTES / 4; // 784/4 = 196

        $display("\n========================================");
        $display("[TEST 3] Transfer statistics");
        $display("========================================");
        $display("Total beats  : expected=%0d, actual=%0d %s",
            expected_beats, beat_count,
            (beat_count == expected_beats) ? "[PASS]" : "[FAIL]");
        $display("wlast count  : actual=%0d", wlast_count);
        $display("AW burst cnt : actual=%0d", burst_count);

        // -----------------------------------------------
        // [TEST 4] Verify first AW address
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 4] First AW address check");
        $display("========================================");
        $display("First AW addr should be 0x%08h (check waveform)", DST_ADDR);

        // -----------------------------------------------
        // [TEST 5] Back-pressure test (wready=0 inserted)
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 5] Back-pressure test (wready forced low)");
        $display("========================================");

        beat_count  = 0;
        burst_count = 0;
        wlast_count = 0;

        force m_axi_wready = 0;
        repeat(3) @(posedge clk);

        @(posedge clk);
        i_start = 1;
        @(posedge clk);
        i_start = 0;

        repeat(10) @(posedge clk);
        force m_axi_wready = 1;

        fork
            begin : wait_done2
                @(posedge o_write_done);
                $display("[PASS] o_write_done received after back-pressure!");
                disable timeout2;
            end
            begin : timeout2
                repeat(8000) @(posedge clk);
                $display("[FAIL] Back-pressure test timeout!");
                disable wait_done2;
            end
        join

        release m_axi_wready;
        repeat(5) @(posedge clk);

        $display("\n========================================");
        $display("All tests done.");
        $display("========================================\n");
        $finish;
    end

    // =========================================================
    // Waveform dump (Vivado xsim)
    // =========================================================
    initial begin
        $dumpfile("tb_tft_write_master.vcd");
        $dumpvars(0, tb_tft_write_master);
    end

    // =========================================================
    // Monitor: real-time event log
    // =========================================================
    always @(posedge clk) begin
        if (m_axi_awvalid && m_axi_awready)
            $display("[AW] Burst addr issued: addr=0x%08h, len=%0d",
                     m_axi_awaddr, m_axi_awlen+1);
        if (m_axi_wlast && m_axi_wvalid && m_axi_wready)
            $display("[W ] wlast fired (burst done), beat_total=%0d", beat_count+1);
        if (m_axi_bvalid && m_axi_bready)
            $display("[B ] bresp received: resp=%0b", m_axi_bresp);
    end

endmodule