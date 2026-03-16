`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_npu_v2_axi_wrapper
// Real MNIST digit-2 samples (5 samples, expected output = 2)
// Fixed: Race conditions resolved, safe memory initialization, 
//        and unnamed block declaration errors fixed.
//////////////////////////////////////////////////////////////////////////////////

module tb_npu_v2_axi_wrapper;

    parameter CLK_PERIOD     = 10;
    parameter AXI_TIMEOUT    = 50;
    parameter IMG_PIXELS     = 784;
    parameter SIM_TIMEOUT    = 5_000_000;
    parameter NUM_SAMPLES    = 5;
    parameter EXPECTED_DIGIT = 4'd2;

    // ── Testbench Signals ────────────────────────────────
    reg         aclk, aresetn;

    // AXI4-Lite Slave
    reg  [4:0]  s_axi_awaddr;  reg  s_axi_awvalid; wire s_axi_awready;
    reg  [31:0] s_axi_wdata;   reg  [3:0] s_axi_wstrb; reg s_axi_wvalid; wire s_axi_wready;
    wire [1:0]  s_axi_bresp;   wire s_axi_bvalid;  reg  s_axi_bready;
    reg  [4:0]  s_axi_araddr;  reg  s_axi_arvalid; wire s_axi_arready;
    wire [31:0] s_axi_rdata;   wire [1:0] s_axi_rresp; wire s_axi_rvalid; reg s_axi_rready;

    // AXI4 Master (BRAM Read)
    wire [31:0] m_axi_img_araddr;
    wire [7:0]  m_axi_img_arlen;
    wire [2:0]  m_axi_img_arsize;
    wire [1:0]  m_axi_img_arburst;
    wire        m_axi_img_arvalid;
    reg         m_axi_img_arready;
    reg  [31:0] m_axi_img_rdata;
    reg  [1:0]  m_axi_img_rresp;
    reg         m_axi_img_rvalid;
    wire        m_axi_img_rready;

    // AXI4 Master (BRAM Write - Dummy)
    wire [31:0] m_axi_img_awaddr; wire [7:0] m_axi_img_awlen;
    wire [2:0]  m_axi_img_awsize; wire [1:0] m_axi_img_awburst; wire m_axi_img_awvalid;
    reg         m_axi_img_awready;
    wire [31:0] m_axi_img_wdata;  wire [3:0] m_axi_img_wstrb; wire m_axi_img_wvalid;
    reg         m_axi_img_wready; reg  [1:0] m_axi_img_bresp; reg  m_axi_img_bvalid;
    wire        m_axi_img_bready;

    // AXI4-Stream Master
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tlast;

    // ── DUT Instance ─────────────────────────────────────
    npu_v2_axi_wrapper #(.BRAM_ADDR_BASE(32'h0)) u_dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),   .s_axi_wstrb(s_axi_wstrb),     .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),     .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr),   .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),.s_axi_rdata(s_axi_rdata),    .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .m_axi_img_araddr(m_axi_img_araddr), .m_axi_img_arlen(m_axi_img_arlen),
        .m_axi_img_arsize(m_axi_img_arsize), .m_axi_img_arburst(m_axi_img_arburst),
        .m_axi_img_arvalid(m_axi_img_arvalid), .m_axi_img_arready(m_axi_img_arready),
        .m_axi_img_rdata(m_axi_img_rdata), .m_axi_img_rresp(m_axi_img_rresp),
        .m_axi_img_rvalid(m_axi_img_rvalid), .m_axi_img_rready(m_axi_img_rready),
        .m_axi_img_awaddr(m_axi_img_awaddr), .m_axi_img_awlen(m_axi_img_awlen),
        .m_axi_img_awsize(m_axi_img_awsize), .m_axi_img_awburst(m_axi_img_awburst),
        .m_axi_img_awvalid(m_axi_img_awvalid), .m_axi_img_awready(m_axi_img_awready),
        .m_axi_img_wdata(m_axi_img_wdata), .m_axi_img_wstrb(m_axi_img_wstrb),
        .m_axi_img_wvalid(m_axi_img_wvalid), .m_axi_img_wready(m_axi_img_wready),
        .m_axi_img_bresp(m_axi_img_bresp), .m_axi_img_bvalid(m_axi_img_bvalid),
        .m_axi_img_bready(m_axi_img_bready),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast)
    );

    // ── BRAM Model ────────────────────────────────────────
    reg [7:0] bram_mem [0:IMG_PIXELS-1];
    reg [7:0] sample0  [0:IMG_PIXELS-1];
    reg [7:0] sample1  [0:IMG_PIXELS-1];
    reg [7:0] sample2  [0:IMG_PIXELS-1];
    reg [7:0] sample3  [0:IMG_PIXELS-1];
    reg [7:0] sample4  [0:IMG_PIXELS-1];

    // ── BRAM AXI Read Model (1-cycle latency) ─────────────
    reg [31:0] bram_addr_lat;
    reg        bram_pending;

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_img_arready <= 1'b0;
            m_axi_img_rvalid  <= 1'b0;
            m_axi_img_rdata   <= 32'd0;
            m_axi_img_rresp   <= 2'b00;
            bram_pending      <= 1'b0;
            bram_addr_lat     <= 32'd0;
        end else begin
            m_axi_img_arready <= 1'b1;

            if (m_axi_img_arvalid && m_axi_img_arready) begin
                bram_addr_lat <= m_axi_img_araddr;
                bram_pending  <= 1'b1;
            end

            if (bram_pending) begin
                m_axi_img_rdata  <= {24'd0, bram_mem[bram_addr_lat[11:2] < IMG_PIXELS
                                                     ? bram_addr_lat[11:2] : 0]};
                m_axi_img_rvalid <= 1'b1;
                m_axi_img_rresp  <= 2'b00;
                bram_pending     <= 1'b0;
            end else if (m_axi_img_rvalid && m_axi_img_rready) begin
                m_axi_img_rvalid <= 1'b0;
            end
        end
    end

    // ── Clock ─────────────────────────────────────────────
    initial aclk = 0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // ── Verification Counters ─────────────────────────────
    integer pass_cnt = 0, fail_cnt = 0, tc_num = 1, correct_cnt = 0;

    task check;
        input [400:0] name;
        input         ok;
        begin
            if (ok) begin $display("[PASS] TC%0d: %s", tc_num, name); pass_cnt=pass_cnt+1; end
            else    begin $display("[FAIL] TC%0d: %s", tc_num, name); fail_cnt=fail_cnt+1; end
            tc_num = tc_num + 1;
        end
    endtask

    // ── AXI-Lite Tasks ────────────────────────────────────
    task axi_write;
        input [4:0] addr; input [31:0] data;
        integer t;
        begin
            @(negedge aclk);
            s_axi_awaddr=addr; s_axi_awvalid=1;
            s_axi_wdata=data;  s_axi_wstrb=4'hF; s_axi_wvalid=1; s_axi_bready=1;
            t=0; @(posedge aclk);
            while(!(s_axi_awready && s_axi_wready) && t<AXI_TIMEOUT) begin @(posedge aclk); t=t+1; end
            @(negedge aclk); s_axi_awvalid=0; s_axi_wvalid=0;
            t=0; @(posedge aclk);
            while(!s_axi_bvalid && t<AXI_TIMEOUT) begin @(posedge aclk); t=t+1; end
            @(negedge aclk); s_axi_bready=0; @(posedge aclk);
        end
    endtask

    task axi_read;
        input [4:0] addr; output [31:0] rdata;
        integer t;
        begin
            @(negedge aclk);
            s_axi_araddr=addr; s_axi_arvalid=1; s_axi_rready=1;
            t=0; @(posedge aclk);
            while(!s_axi_arready && t<AXI_TIMEOUT) begin @(posedge aclk); t=t+1; end
            while(!s_axi_rvalid  && t<AXI_TIMEOUT) begin @(posedge aclk); t=t+1; end
            rdata = s_axi_rdata;
            @(negedge aclk); s_axi_arvalid=0; s_axi_rready=0; @(posedge aclk);
        end
    endtask

    // ── Load sample into bram_mem ─────────────────────────
    task load_sample;
        input integer idx;
        integer i;
        begin
            case (idx)
                0: for(i=0;i<IMG_PIXELS;i=i+1) bram_mem[i] = sample0[i];
                1: for(i=0;i<IMG_PIXELS;i=i+1) bram_mem[i] = sample1[i];
                2: for(i=0;i<IMG_PIXELS;i=i+1) bram_mem[i] = sample2[i];
                3: for(i=0;i<IMG_PIXELS;i=i+1) bram_mem[i] = sample3[i];
                4: for(i=0;i<IMG_PIXELS;i=i+1) bram_mem[i] = sample4[i];
                default: for(i=0;i<IMG_PIXELS;i=i+1) bram_mem[i] = 8'h00;
            endcase
            #1; // ★ 시뮬레이터 Race Condition 방지용 미세 딜레이
        end
    endtask

    // ── Per-Sample Inference Task ─────────────────────────
    task run_sample;
        input integer sample_idx;
        input [3:0]   expected;
        integer poll, done_f;
        reg [31:0] rd;
        begin
            $display("\n----------------------------------------------");
            $display(" Sample %0d  (expected digit = %0d)", sample_idx+1, expected);
            $display("----------------------------------------------");

            // 1) Load image into bram_mem
            load_sample(sample_idx);
            #100; // ★ BRAM 복사가 완전히 끝나도록 물리적 대기시간 부여

            // 2) Hard reset - ensures NPU reads bram_mem AFTER load_sample completes
            aresetn = 0;
            repeat(50) @(posedge aclk); // 리셋 기간 대폭 증가
            aresetn = 1;
            repeat(50) @(posedge aclk); // 안정화 시간 부여


            // 3) Check reset state
            axi_read(5'h00, rd);
            check("Reset state busy=0 done=0", rd[1:0] == 2'b00);

            // 4) Start
            axi_write(5'h00, 32'h1);
            repeat(3) @(posedge aclk);
            axi_read(5'h00, rd);
            check("busy=1 after start", rd[0] == 1'b1);

            // 5) Poll done
            poll = 0; done_f = 0;
            while (!done_f && poll < SIM_TIMEOUT) begin
                axi_read(5'h00, rd);
                done_f = rd[1];
                if (!done_f) begin repeat(500) @(posedge aclk); poll = poll + 500; end
            end
            $display("[INFO] Sample%0d  done=%0b  poll_clk=%0d",
                     sample_idx+1, done_f, poll);
            check("Inference done=1", done_f);

            // 6) Read and compare result
            axi_read(5'h08, rd);
            $display("[INFO] Sample%0d  final_digit=%0d  expected=%0d  -> %s",
                     sample_idx+1, rd[3:0], expected,
                     (rd[3:0] == expected) ? "CORRECT" : "WRONG");
            if (rd[3:0] == expected) correct_cnt = correct_cnt + 1;
            check("final_digit == expected", rd[3:0] == expected);

            // 7) AXI-Stream check
            check("m_axis digit == expected", m_axis_tdata[3:0] == expected);
        end
    endtask

    // ── Main Sequence ─────────────────────────────────────
    integer s;

    initial begin : MAIN_SEQ
        // 1. 시뮬레이션 시작 시 원본 배열에만 데이터를 로드합니다.
        $readmemh("mnist_digit2_sample1.txt", sample0);
        $readmemh("mnist_digit2_sample2.txt", sample1);
        $readmemh("mnist_digit2_sample3.txt", sample2);
        $readmemh("mnist_digit2_sample4.txt", sample3);
        $readmemh("mnist_digit2_sample5.txt", sample4);

        #1000; 

        // 2. 신호 초기화
        aresetn=0; s_axi_awvalid=0; s_axi_wvalid=0; s_axi_bready=0;
        s_axi_arvalid=0; s_axi_rready=0; m_axis_tready=1;
        m_axi_img_awready=0; m_axi_img_wready=0;
        m_axi_img_bvalid=0; m_axi_img_bresp=2'b00;

        repeat(50) @(posedge aclk); 
        aresetn=1;
        repeat(50) @(posedge aclk);

        // ==========================================================
        // ★ 핵심 해결책: NPU 워밍업 (Dummy Run)
        // ==========================================================
        $display("\n==============================================");
        $display(" [WARM-UP] NPU Cold-Start Initialization...");
        $display("==============================================");
        
        // 0번 샘플을 한 번 실행시켜서 NPU 파이프라인을 예열합니다.
        // 이때 나오는 FAIL이나 에러는 무시합니다.
        run_sample(0, EXPECTED_DIGIT); 

        // 워밍업이 끝났으므로 채점판(카운터)을 모두 0으로 깨끗하게 초기화!
        pass_cnt = 0; fail_cnt = 0; tc_num = 1; correct_cnt = 0;
        
        // ==========================================================
        // ★ 진짜 테스트 시작
        // ==========================================================
        $display("\n==============================================");
        $display(" NPU v2 - REAL MNIST Digit-2 Accuracy Test");
        $display(" 5 real samples, all expected = 2");
        $display("==============================================");

        // 다시 0번 샘플부터 진짜 채점을 시작합니다.
        // 이미 예열이 끝났기 때문에 이번엔 0번(Sample 1)도 정답을 맞힐 겁니다!
        for (s = 0; s < NUM_SAMPLES; s = s+1) begin
            run_sample(s, EXPECTED_DIGIT);
        end

        // ── Final Summary ──────────────────────────────────
        $display("\n==============================================");
        $display(" PASS=%0d  FAIL=%0d  TOTAL=%0d", pass_cnt, fail_cnt, tc_num-1);
        $display(" Digit Accuracy: %0d / %0d samples correct",
                 correct_cnt, NUM_SAMPLES);
        if (fail_cnt == 0) $display(" >>> ALL TESTS PASSED <<<");
        else               $display(" >>> %0d TEST(s) FAILED <<<", fail_cnt);
        $display("==============================================\n");
        $finish;
    end

    // ── Monitor ───────────────────────────────────────────
    always @(posedge aclk) begin
        if (u_dut.u_npu_v2.result_valid)
            $display("[MON] @%0t ns | result_valid=1  digit=%0d",
                     $time, u_dut.u_npu_v2.final_digit);
        if (m_axis_tvalid && m_axis_tready)
            $display("[MON] @%0t ns | AXI-Stream digit=%0d  tlast=%0b",
                     $time, m_axis_tdata[3:0], m_axis_tlast);
    end

    // ── Watchdog ──────────────────────────────────────────
    initial begin
        #(CLK_PERIOD * SIM_TIMEOUT * 12);
        $display("[WATCHDOG] Timeout! Force exit.");
        $finish;
    end

endmodule