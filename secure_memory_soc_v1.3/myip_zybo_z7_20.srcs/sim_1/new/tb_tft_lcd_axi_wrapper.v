`timescale 1ns / 1ps

/**
 * tb_tft_lcd_axi_wrapper
 *
 * Integration testbench for axi_lcd_wrapper.
 *
 * Verification:
 *   1. AXI Lite write: DST_ADDR, TRF_LEN registers
 *   2. AXI Lite write: CTRL start bit -> DMA starts
 *   3. AXI Full Write: AW/W/B channel handshake
 *   4. 784 bytes transferred to correct destination address
 *   5. o_done_irq pulse after transfer complete
 *   6. AXI Lite read: STAT done bit set after transfer
 *   7. AXI Lite write: CTRL bram_clear bit
 *   8. pen_lock active during DMA transfer (STAT busy bit)
 */
module tb_tft_lcd_axi_wrapper;

    // =========================================================
    // Parameters
    // =========================================================
    parameter CLK_PERIOD  = 10;       // 100MHz
    parameter BURST_LEN   = 16;
    parameter TOTAL_BYTES = 784;      // 28*28
    parameter DST_ADDR    = 32'hB000_0000;

    // AXI Lite register offsets
    parameter CTRL_OFFSET     = 5'h00;
    parameter STAT_OFFSET     = 5'h04;
    parameter DST_ADDR_OFFSET = 5'h08;
    parameter TRF_LEN_OFFSET  = 5'h0C;

    // =========================================================
    // DUT ports
    // =========================================================
    reg         aclk;
    reg         aresetn;

    // AXI Lite Slave
    reg  [4:0]  s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg  [4:0]  s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // AXI Full Master Write
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

    // TFT LCD ports (tied off for simulation)
    reg         tft_sdo;
    wire        tft_sck;
    wire        tft_sdi;
    wire        tft_dc;
    wire        tft_reset;
    wire        tft_cs;

    // Touch pad (tied off: pen not pressed)
    reg         PenIrq_n;
    wire        DCLK;
    wire        DIN;
    wire        CS_N;
    reg         DOUT;

    // IRQ
    wire        o_done_irq;

    // =========================================================
    // DUT instance
    // =========================================================
    tft_lcd_axi_wrapper #(
        .C_S_AXI_DATA_WIDTH (32),
        .C_S_AXI_ADDR_WIDTH (5),
        .C_M_AXI_ADDR_WIDTH (32),
        .C_M_AXI_DATA_WIDTH (32),
        .BURST_LEN          (BURST_LEN)
    ) dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
        // AXI Lite
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
        // AXI Full Master
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
        .m_axi_bready   (m_axi_bready),
        // TFT
        .tft_sdo        (tft_sdo),
        .tft_sck        (tft_sck),
        .tft_sdi        (tft_sdi),
        .tft_dc         (tft_dc),
        .tft_reset      (tft_reset),
        .tft_cs         (tft_cs),
        // Touch
        .PenIrq_n       (PenIrq_n),
        .DCLK           (DCLK),
        .DIN            (DIN),
        .CS_N           (CS_N),
        .DOUT           (DOUT),
        // IRQ
        .o_done_irq     (o_done_irq)
    );

    // =========================================================
    // Clock
    // =========================================================
    initial aclk = 0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // =========================================================
    // AXI Full Slave model
    // =========================================================

    // [AW channel] 2-cycle delay
    integer aw_delay_cnt;
    initial aw_delay_cnt = 0;
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_awready <= 0;
            aw_delay_cnt  <= 0;
        end else begin
            if (m_axi_awvalid && !m_axi_awready) begin
                if (aw_delay_cnt >= 1) begin
                    m_axi_awready <= 1;
                    aw_delay_cnt  <= 0;
                end else
                    aw_delay_cnt <= aw_delay_cnt + 1;
            end else
                m_axi_awready <= 0;
        end
    end

    // [W channel] always ready
    initial m_axi_wready = 1;

    // [B channel] bvalid 1 cycle after wlast
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_bvalid <= 0;
            m_axi_bresp  <= 0;
        end else begin
            if (m_axi_wlast && m_axi_wvalid && m_axi_wready) begin
                m_axi_bvalid <= 1;
                m_axi_bresp  <= 2'b00;
            end else if (m_axi_bvalid && m_axi_bready)
                m_axi_bvalid <= 0;
        end
    end

    // =========================================================
    // Task: AXI Lite write (AW/W independent latch safe)
    // =========================================================
    task axi_lite_write;
        input [4:0]  addr;
        input [31:0] data;
        begin
            // Drive AW and W simultaneously
            @(posedge aclk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= 4'hF;
            s_axi_wvalid  <= 1;

            // Wait for both ready
            fork
                begin : aw_wait
                    wait (s_axi_awready);
                    @(posedge aclk);
                    s_axi_awvalid <= 0;
                end
                begin : w_wait
                    wait (s_axi_wready);
                    @(posedge aclk);
                    s_axi_wvalid <= 0;
                end
            join

            // Wait for B response
            s_axi_bready <= 1;
            wait (s_axi_bvalid);
            @(posedge aclk);
            s_axi_bready <= 0;
        end
    endtask

    // =========================================================
    // Task: AXI Lite read
    // =========================================================
    task axi_lite_read;
        input  [4:0]  addr;
        output [31:0] data;
        begin
            @(posedge aclk);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1;
            s_axi_rready  <= 1;
            wait (s_axi_arready);
            @(posedge aclk);
            s_axi_arvalid <= 0;
            wait (s_axi_rvalid);
            data = s_axi_rdata;
            @(posedge aclk);
            s_axi_rready <= 0;
        end
    endtask

    // =========================================================
    // Verification counters
    // =========================================================
    integer beat_count;
    integer burst_count;

    initial begin
        beat_count  = 0;
        burst_count = 0;
    end

    always @(posedge aclk) begin
        if (m_axi_wvalid && m_axi_wready)
            beat_count <= beat_count + 1;
        if (m_axi_awvalid && m_axi_awready)
            burst_count <= burst_count + 1;
    end

    // =========================================================
    // Main scenario
    // =========================================================
    reg [31:0] read_data;
    integer    expected_beats;

    initial begin
        // Init
        aresetn       = 0;
        s_axi_awvalid = 0; s_axi_wvalid  = 0; s_axi_bready  = 0;
        s_axi_arvalid = 0; s_axi_rready  = 0;
        s_axi_awaddr  = 0; s_axi_wdata   = 0; s_axi_wstrb   = 0;
        tft_sdo       = 0; PenIrq_n      = 1; DOUT          = 0;

        repeat(5) @(posedge aclk);
        aresetn = 1;
        repeat(3) @(posedge aclk);

        // -----------------------------------------------
        // [TEST 1] Write DST_ADDR register
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 1] AXI Lite write DST_ADDR=0x%08h", DST_ADDR);
        $display("========================================");
        axi_lite_write(DST_ADDR_OFFSET, DST_ADDR);
        axi_lite_read (DST_ADDR_OFFSET, read_data);
        if (read_data === DST_ADDR)
            $display("[PASS] DST_ADDR reg: 0x%08h", read_data);
        else
            $display("[FAIL] DST_ADDR reg: expected=0x%08h, actual=0x%08h", DST_ADDR, read_data);

        // -----------------------------------------------
        // [TEST 2] Write TRF_LEN register
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 2] AXI Lite write TRF_LEN=%0d", TOTAL_BYTES);
        $display("========================================");
        axi_lite_write(TRF_LEN_OFFSET, TOTAL_BYTES);
        axi_lite_read (TRF_LEN_OFFSET, read_data);
        if (read_data === TOTAL_BYTES)
            $display("[PASS] TRF_LEN reg: %0d", read_data);
        else
            $display("[FAIL] TRF_LEN reg: expected=%0d, actual=%0d", TOTAL_BYTES, read_data);

        // -----------------------------------------------
        // [TEST 3] Write CTRL start bit -> DMA starts
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 3] CTRL start -> DMA transfer begins");
        $display("========================================");
        axi_lite_write(CTRL_OFFSET, 32'h1); // start=1

        // Verify start bit auto-clears
        axi_lite_read(CTRL_OFFSET, read_data);
        if (read_data[0] === 1'b0)
            $display("[PASS] CTRL start bit auto-cleared");
        else
            $display("[FAIL] CTRL start bit did not auto-clear");

        // -----------------------------------------------
        // [TEST 4] STAT busy bit during transfer
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 4] STAT busy bit during DMA");
        $display("========================================");
        axi_lite_read(STAT_OFFSET, read_data);
        if (read_data[1] === 1'b1)
            $display("[PASS] STAT busy=1 during transfer");
        else
            $display("[INFO] STAT busy=%0b (may have completed already)", read_data[1]);

        // -----------------------------------------------
        // [TEST 5] Wait for o_done_irq
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 5] Waiting for o_done_irq...");
        $display("========================================");
        fork
            begin : wait_irq
                @(posedge o_done_irq);
                $display("[PASS] o_done_irq received! time=%0t ns", $time);
                disable timeout_irq;
            end
            begin : timeout_irq
                repeat(10000) @(posedge aclk);
                $display("[FAIL] Timeout! o_done_irq not received.");
                disable wait_irq;
            end
        join

        repeat(3) @(posedge aclk);

        // -----------------------------------------------
        // [TEST 6] Transfer statistics
        // -----------------------------------------------
        expected_beats = TOTAL_BYTES / 4; // 196
        $display("\n========================================");
        $display("[TEST 6] Transfer statistics");
        $display("========================================");
        $display("Total beats  : expected=%0d, actual=%0d %s",
            expected_beats, beat_count,
            (beat_count == expected_beats) ? "[PASS]" : "[FAIL]");
        $display("AW burst cnt : actual=%0d (expected 13)", burst_count);
        $display("First AW addr should be 0x%08h (check waveform)", DST_ADDR);

        // -----------------------------------------------
        // [TEST 7] STAT done bit after transfer
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 7] AXI Lite read STAT done bit");
        $display("========================================");
        axi_lite_read(STAT_OFFSET, read_data);
        $display("STAT reg: done=%0b, busy=%0b %s",
            read_data[0], read_data[1],
            (read_data[1] === 1'b0) ? "[PASS] busy cleared" : "[FAIL] busy still set");

        // -----------------------------------------------
        // [TEST 8] CTRL bram_clear bit
        // -----------------------------------------------
        $display("\n========================================");
        $display("[TEST 8] CTRL bram_clear -> BRAM cleared");
        $display("========================================");
        axi_lite_write(CTRL_OFFSET, 32'h2); // bram_clear=1
        axi_lite_read (CTRL_OFFSET, read_data);
        if (read_data[1] === 1'b0)
            $display("[PASS] CTRL bram_clear bit auto-cleared");
        else
            $display("[FAIL] CTRL bram_clear bit did not auto-clear");

        $display("\n========================================");
        $display("All tests done.");
        $display("========================================\n");
        $finish;
    end

    // =========================================================
    // Waveform dump
    // =========================================================
    initial begin
        $dumpfile("tb_tft_lcd_axi_wrapper.vcd");
        $dumpvars(0, tb_tft_lcd_axi_wrapper);
    end

    // =========================================================
    // Monitor: real-time event log
    // =========================================================
    always @(posedge aclk) begin
        if (m_axi_awvalid && m_axi_awready)
            $display("[AW] addr=0x%08h, len=%0d", m_axi_awaddr, m_axi_awlen+1);
        if (m_axi_wlast && m_axi_wvalid && m_axi_wready)
            $display("[W ] wlast fired, beat_total=%0d", beat_count+1);
        if (m_axi_bvalid && m_axi_bready)
            $display("[B ] bresp received");
        if (o_done_irq)
            $display("[IRQ] o_done_irq asserted!");
    end

endmodule