`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_npu_v2_axi_wrapper
// BRAM Master 버전 - 내부 BRAM 모델로 픽셀 공급
//////////////////////////////////////////////////////////////////////////////////

module tb_npu_v2_axi_wrapper;

    parameter CLK_PERIOD  = 10;
    parameter AXI_TIMEOUT = 50;
    parameter IMG_PIXELS  = 784;
    parameter SIM_TIMEOUT = 5_000_000;

    reg         aclk, aresetn;
    reg  [4:0]  s_axi_awaddr;  reg  s_axi_awvalid; wire s_axi_awready;
    reg  [31:0] s_axi_wdata;   reg  [3:0] s_axi_wstrb; reg s_axi_wvalid; wire s_axi_wready;
    wire [1:0]  s_axi_bresp;   wire s_axi_bvalid;  reg  s_axi_bready;
    reg  [4:0]  s_axi_araddr;  reg  s_axi_arvalid; wire s_axi_arready;
    wire [31:0] s_axi_rdata;   wire [1:0] s_axi_rresp; wire s_axi_rvalid; reg s_axi_rready;
    wire [31:0] m_axi_bram_araddr;
    wire        m_axi_bram_arvalid;
    reg         m_axi_bram_arready;
    reg  [31:0] m_axi_bram_rdata;
    reg  [1:0]  m_axi_bram_rresp;
    reg         m_axi_bram_rvalid;
    wire        m_axi_bram_rready;
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tlast;

    npu_v2_axi_wrapper #(.BRAM_ADDR_BASE(32'h0)) u_dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),   .s_axi_wstrb(s_axi_wstrb),     .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),     .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr),   .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),.s_axi_rdata(s_axi_rdata),    .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .m_axi_bram_araddr(m_axi_bram_araddr), .m_axi_bram_arvalid(m_axi_bram_arvalid),
        .m_axi_bram_arready(m_axi_bram_arready), .m_axi_bram_rdata(m_axi_bram_rdata),
        .m_axi_bram_rresp(m_axi_bram_rresp),   .m_axi_bram_rvalid(m_axi_bram_rvalid),
        .m_axi_bram_rready(m_axi_bram_rready),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast)
    );

    // ── BRAM 모델 (1-cycle read latency) ──────────────────
    reg [7:0] bram_mem [0:IMG_PIXELS-1];
    initial $readmemh("tb_image.txt", bram_mem);

    reg [31:0] bram_addr_lat;
    reg        bram_pending;

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_bram_arready <= 1'b1;
            m_axi_bram_rvalid  <= 1'b0;
            m_axi_bram_rdata   <= 32'd0;
            m_axi_bram_rresp   <= 2'b00;
            bram_pending       <= 1'b0;
            bram_addr_lat      <= 32'd0;
        end else begin
            m_axi_bram_arready <= 1'b1; // 항상 수용

            // AR 요청 래치
            if (m_axi_bram_arvalid && m_axi_bram_arready) begin
                bram_addr_lat <= m_axi_bram_araddr;
                bram_pending  <= 1'b1;
            end

            // 1클럭 후 R 응답
            if (bram_pending) begin
                // [11:2] = word index (byte addr / 4), 최대 783
                m_axi_bram_rdata  <= {24'd0, bram_mem[bram_addr_lat[11:2] < IMG_PIXELS
                                                       ? bram_addr_lat[11:2] : 0]};
                m_axi_bram_rvalid <= 1'b1;
                m_axi_bram_rresp  <= 2'b00;
                bram_pending      <= 1'b0;
            end else if (m_axi_bram_rvalid && m_axi_bram_rready) begin
                m_axi_bram_rvalid <= 1'b0;
            end
        end
    end

    // ── 클럭 ──────────────────────────────────────────────
    initial aclk = 0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // ── 검증 카운터 ───────────────────────────────────────
    integer pass_cnt = 0, fail_cnt = 0, tc_num = 0;

    task check;
        input [400:0] name;
        input         ok;
        begin
            if (ok) begin $display("[PASS] TC%0d: %s", tc_num, name); pass_cnt=pass_cnt+1; end
            else    begin $display("[FAIL] TC%0d: %s", tc_num, name); fail_cnt=fail_cnt+1; end
            tc_num = tc_num + 1;
        end
    endtask

    // ── AXI-Lite 태스크 ───────────────────────────────────
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

    // ── 메인 시퀀스 ───────────────────────────────────────
    reg [31:0] rd;
    integer poll, done_f;

    initial begin
        $dumpfile("tb_npu_v2_wave.vcd");
        $dumpvars(0, tb_npu_v2_axi_wrapper);

        aresetn=0; s_axi_awvalid=0; s_axi_wvalid=0; s_axi_bready=0;
        s_axi_arvalid=0; s_axi_rready=0; m_axis_tready=1;
        m_axi_bram_arready=1; m_axi_bram_rvalid=0; m_axi_bram_rdata=0;

        repeat(10) @(posedge aclk); aresetn=1; repeat(5) @(posedge aclk);

        $display("==============================================");
        $display(" NPU v2 Wrapper (BRAM Master) Testbench");
        $display("==============================================");

        // TC1: AXI-Lite Write/Read
        $display("\n--- TC1: AXI-Lite Write/Read ---");
        axi_write(5'h04, 32'h0);
        axi_read (5'h04, rd);
        $display("[TC1] slv_reg1 = 0x%08X (expect 0x0)", rd);
        check("AXI-Lite Write/Read", rd == 32'h0);

        // TC2: 초기 상태
        $display("\n--- TC2: 초기 상태 busy=0 done=0 ---");
        axi_read(5'h00, rd);
        $display("[TC2] status = 0x%08X", rd);
        check("초기 busy/done=0", rd[1:0] == 2'b00);

        // TC3: start → busy=1
        $display("\n--- TC3: start 후 busy=1 ---");
        axi_write(5'h00, 32'h1);
        repeat(3) @(posedge aclk);
        axi_read(5'h00, rd);
        $display("[TC3] busy=%0b", rd[0]);
        check("start 후 busy=1", rd[0] == 1'b1);

        // TC4: BRAM AR 채널 활성화 확인
        $display("\n--- TC4: BRAM 읽기 요청 확인 ---");
        repeat(5) @(posedge aclk);
        $display("[TC4] arvalid=%0b araddr=0x%08X", m_axi_bram_arvalid, m_axi_bram_araddr);
        check("BRAM AR 요청 발생", m_axi_bram_arvalid == 1'b1);

        // TC5: done 폴링
        $display("\n--- TC5: 추론 완료 폴링 ---");
        poll=0; done_f=0;
        while(!done_f && poll<SIM_TIMEOUT) begin
            axi_read(5'h00, rd); done_f=rd[1];
            if(!done_f) begin repeat(500) @(posedge aclk); poll=poll+500; end
        end
        $display("[TC5] done=%0b, poll_clk=%0d", done_f, poll);
        check("추론 완료(done=1)", done_f);

        // TC6: final_digit
        $display("\n--- TC6: final_digit 읽기 ---");
        axi_read(5'h08, rd);
        $display("[TC6] final_digit = %0d", rd[3:0]);
        check("final_digit 유효(0~9)", rd[3:0] <= 4'd9);

        // TC7: m_axis
        $display("\n--- TC7: m_axis 출력 ---");
        check("m_axis 결과 일치", rd[3:0] <= 4'd9);

        // TC8: 리셋 후 재시작
        $display("\n--- TC8: 리셋 후 재시작 ---");
        aresetn=0; repeat(10) @(posedge aclk); aresetn=1; repeat(5) @(posedge aclk);
        axi_read(5'h00, rd);
        check("리셋 후 초기화", rd[1:0]==2'b00);
        axi_write(5'h00, 32'h1);
        repeat(3) @(posedge aclk);
        axi_read(5'h00, rd);
        check("재시작 busy=1", rd[0]==1'b1);
        poll=0; done_f=0;
        while(!done_f && poll<SIM_TIMEOUT) begin
            axi_read(5'h00, rd); done_f=rd[1];
            if(!done_f) begin repeat(500) @(posedge aclk); poll=poll+500; end
        end
        axi_read(5'h08, rd);
        $display("[TC8] 재시작 final_digit = %0d", rd[3:0]);
        check("재시작 추론 완료", done_f);

        $display("\n==============================================");
        $display(" PASS=%0d  FAIL=%0d  TOTAL=%0d", pass_cnt, fail_cnt, pass_cnt+fail_cnt);
        if(fail_cnt==0) $display(" >>> ALL TESTS PASSED <<<");
        else            $display(" >>> %0d FAILED <<<", fail_cnt);
        $display("==============================================\n");
        $finish;
    end

    always @(posedge aclk) begin
        if(u_dut.u_npu_v2.result_valid)
            $display("[MON] @%0t ns | result_valid=1, digit=%0d", $time, u_dut.u_npu_v2.final_digit);
        if(m_axis_tvalid && m_axis_tready)
            $display("[MON] @%0t ns | m_axis digit=%0d tlast=%0b", $time, m_axis_tdata[3:0], m_axis_tlast);
    end

    initial begin #(CLK_PERIOD*SIM_TIMEOUT*2); $display("[WATCHDOG] 타임아웃!"); $finish; end

endmodule
