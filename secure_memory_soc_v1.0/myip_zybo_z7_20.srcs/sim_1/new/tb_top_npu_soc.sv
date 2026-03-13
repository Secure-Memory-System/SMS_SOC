`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : tb_top_npu_soc
// Description : SMS SoC 전체 통합 테스트벤치 (PS7 BFM 방식)
//               구간별 handshake 진단 목적
//////////////////////////////////////////////////////////////////////////////////

module tb_top_npu_soc;

    // =========================================================
    // 1. 클록 / 리셋
    // =========================================================
    logic ps_clk;
    initial  ps_clk = 1'b0;
    always #15 ps_clk = ~ps_clk;  // 33.33 MHz (PS7 입력 클럭)

    // =========================================================
    // 2. DUT 포트 신호 선언
    // =========================================================

    // ── TFT LCD (SPI) ─────────────────────────────────────
    logic       tft_sdo_0  = 1'b0;   // input  : MISO (TB → DUT)
    wire        tft_sck_0;            // output : SPI 클럭
    wire        tft_sdi_0;            // output : MOSI
    wire        tft_dc_0;             // output : Data/Command
    wire        tft_reset_0;          // output : LCD 리셋
    wire        tft_cs_0;             // output : Chip Select

    // ── 터치패드 XPT2046 ───────────────────────────────────
    logic       PenIrq_n_0 = 1'b1;   // input  : 터치 감지 (active-low)
    wire        DCLK_0;               // output : SPI 클럭
    wire        DIN_0;                // output : MOSI
    wire        CS_N_0;               // output : Chip Select
    logic       DOUT_0     = 1'b0;   // input  : MISO (TB → DUT)

    // ── FND 출력 (관찰 포인트) ────────────────────────────
    wire [3:0]  com_0;                // output : 자릿수 선택
    wire [7:0]  seg_0;                // output : 7-Segment 패턴

    // ── PS7 DDR ───────────────────────────────────────────
    wire [14:0] DDR_addr;
    wire [2:0]  DDR_ba;
    wire        DDR_cas_n;
    wire        DDR_ck_n;
    wire        DDR_ck_p;
    wire        DDR_cke;
    wire        DDR_cs_n;
    wire [3:0]  DDR_dm;
    wire [31:0] DDR_dq;
    wire [3:0]  DDR_dqs_n;
    wire [3:0]  DDR_dqs_p;
    wire        DDR_odt;
    wire        DDR_ras_n;
    wire        DDR_reset_n;
    wire        DDR_we_n;

    // ── PS7 FIXED_IO ──────────────────────────────────────
    wire        FIXED_IO_ddr_vrn;
    wire        FIXED_IO_ddr_vrp;
    wire [53:0] FIXED_IO_mio;
    wire        FIXED_IO_ps_clk;
    wire        FIXED_IO_ps_porb;
    wire        FIXED_IO_ps_srstb;

    assign FIXED_IO_ps_clk  = ps_clk;
    assign FIXED_IO_ps_porb = 1'b1;
    assign FIXED_IO_ps_srstb = 1'b1;

    // =========================================================
    // 3. DUT 인스턴스
    // =========================================================
    soc_design_wrapper DUT (
        // TFT LCD
        .tft_sdo_0      (tft_sdo_0),
        .tft_sck_0      (tft_sck_0),
        .tft_sdi_0      (tft_sdi_0),
        .tft_dc_0       (tft_dc_0),
        .tft_reset_0    (tft_reset_0),
        .tft_cs_0       (tft_cs_0),
        // 터치패드
        .PenIrq_n_0     (PenIrq_n_0),
        .DCLK_0         (DCLK_0),
        .DIN_0          (DIN_0),
        .CS_N_0         (CS_N_0),
        .DOUT_0         (DOUT_0),
        // FND
        .com_0          (com_0),
        .seg_0          (seg_0),
        // DDR
        .DDR_addr       (DDR_addr),
        .DDR_ba         (DDR_ba),
        .DDR_cas_n      (DDR_cas_n),
        .DDR_ck_n       (DDR_ck_n),
        .DDR_ck_p       (DDR_ck_p),
        .DDR_cke        (DDR_cke),
        .DDR_cs_n       (DDR_cs_n),
        .DDR_dm         (DDR_dm),
        .DDR_dq         (DDR_dq),
        .DDR_dqs_n      (DDR_dqs_n),
        .DDR_dqs_p      (DDR_dqs_p),
        .DDR_odt        (DDR_odt),
        .DDR_ras_n      (DDR_ras_n),
        .DDR_reset_n    (DDR_reset_n),
        .DDR_we_n       (DDR_we_n),
        // FIXED_IO
        .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio      (FIXED_IO_mio),
        .FIXED_IO_ps_clk   (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb  (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb)
    );

    // =========================================================
    // 4. 내부 신호 계층적 참조 (진단용)
    // =========================================================
    `define LCD  DUT.soc_design_i.tft_lcd_axi_wrapper_0
    `define NPU  DUT.soc_design_i.npu_v2_axi_wrapper_0
    `define ENC  DUT.soc_design_i.aes_enc_axi_wrapper_0
    `define DEC  DUT.soc_design_i.aes_dec_axi_wrapper_0
    `define S2F  DUT.soc_design_i.top_dma_stream_to_fu_0
    `define F2S  DUT.soc_design_i.top_dma_full_to_stre_0
    `define FND  DUT.soc_design_i.fnd_axi_stream_wrapp_0

    // =========================================================
    // 5. 워치독 태스크 (구간별 타임아웃 진단)
    // =========================================================
    task automatic wait_signal(
        input string stage_name,
        ref   logic  sig,        // logic 변수만 받음 (wire 불가)
        input int    timeout_ns  // 단위: ns (timescale 1ns 기준)
    );
        // wait()는 level-sensitive: 이미 1이면 즉시 통과 (펄스 놓침 없음)
        fork
            begin : wait_block
                wait(sig === 1'b1);
                $display("[PASS] %-30s @ %0t ns", stage_name, $time/1000);
                disable timeout_block;
            end
            begin : timeout_block
                #(timeout_ns);
                $display("[FAIL] %-30s TIMEOUT @ %0t ns", stage_name, $time/1000);
                disable wait_block;
            end
        join
    endtask
    
    // PS7 VIP의 FCLK_CLK0이 실제로 출력되는 경우 사용
    // 만약 FCLK_CLK0이 X/0으로 고정된다면 ps_clk를 직접 사용할 것
    wire fclk     = DUT.soc_design_i.processing_system7_0.inst.FCLK_CLK0;
    wire resetn   = DUT.soc_design_i.processing_system7_0.inst.FCLK_RESET0_N;

    // fclk 동작 확인용: 시뮬레이션 초기 100us 내에 클럭이 없으면 경고
    initial begin
        #100_000;  // 100us 대기
        if (fclk === 1'bx || fclk === 1'b0) begin
            $display("[WARN] FCLK_CLK0 not toggling after 100us — check PS7 VIP clock config");
            $display("[HINT] ps_clk is running at 33MHz; consider using ps_clk as fclk");
        end
    end

    // ── 구간별 진단 신호 (래치 방식 logic) ───────────────────
    // wire를 ref에 넘길 수 없고, @(posedge)는 1-cycle 펄스를 놓치므로
    // logic 변수에 래치하여 wait() 방식으로 감지
    logic lcd_dma_done_lat     = 1'b0;
    logic npu_result_valid_lat = 1'b0;
    logic enc_output_valid_lat = 1'b0;
    logic s2f_dma_done_lat     = 1'b0;
    logic f2s_stream_done_lat  = 1'b0;
    logic dec_output_valid_lat = 1'b0;

    always @(posedge fclk) begin
        if (`LCD.inst.dma_done)        lcd_dma_done_lat     <= 1'b1;
        if (`NPU.inst.result_valid_w)  npu_result_valid_lat <= 1'b1;
        if (`ENC.inst.output_valid)    enc_output_valid_lat <= 1'b1;
        if (`S2F.inst.dma_done)        s2f_dma_done_lat     <= 1'b1;
        if (`F2S.inst.dma_done)        f2s_stream_done_lat  <= 1'b1;
        if (`DEC.inst.output_valid)    dec_output_valid_lat <= 1'b1;
    end

    // =========================================================
    // 6. 터치 시뮬레이션 태스크 (BRAM Port A 포트 force 방식)
    // =========================================================
    // xsim 제약:
    //   - force 대상에 automatic 변수 인덱스 불가 (VRFC 10-3142)
    //   - force로 reg 배열 bit-select 불가 (VRFC 10-3149)
    // 해결: BRAM Port A 입력 포트(wea/addra/dina)를 module-level 신호로
    //       continuous force → ts_* 변수 갱신만으로 픽셀 주입
    logic       ts_wea   = 1'b0;
    logic [9:0] ts_addra = 10'd0;
    logic [7:0] ts_dina  = 8'h00;

    task touch_sim();   // static task — automatic 변수 제한 없음
        integer i;

        // force 한 번만 설정: ts_* 가 바뀌면 자동 추적 (continuous force)
        force `LCD.inst.u_lcd.lcd_mem.wea   = ts_wea;
        force `LCD.inst.u_lcd.lcd_mem.addra = ts_addra;
        force `LCD.inst.u_lcd.lcd_mem.dina  = ts_dina;

        // (1) BRAM 전체 클리어
        ts_wea = 1'b1; ts_dina = 8'h00;
        for (i = 0; i < 784; i = i + 1) begin
            ts_addra = 10'(i);
            @(posedge fclk);
        end

        // (2) 패턴 주입: 숫자 '1' — x=13~14, y=4~24 세로줄
        ts_dina = 8'hFF;
        for (i = 4; i <= 24; i = i + 1) begin
            ts_addra = 10'(i * 28 + 13);
            @(posedge fclk);
            ts_addra = 10'(i * 28 + 14);
            @(posedge fclk);
        end

        // (3) release — 이후 DMA 전송 때 실제 값이 읽힘
        ts_wea = 1'b0;
        @(posedge fclk);
        release `LCD.inst.u_lcd.lcd_mem.wea;
        release `LCD.inst.u_lcd.lcd_mem.addra;
        release `LCD.inst.u_lcd.lcd_mem.dina;

        $display("[INFO] touch_sim: pattern injected @ %0t ns", $time/1000);
    endtask

    // =========================================================
    // 7. CPU 쓰기 태스크 (PS7 BFM → SmartConnect → AXI-Lite Slave)
    // =========================================================
    task automatic cpu_write(
        input [31:0] addr,
        input [31:0] wdata
    );
        reg [1:0] resp;
        DUT.soc_design_i.processing_system7_0.inst.write_data(addr, 4'hF, wdata, resp);
        @(posedge fclk);
        if (resp !== 2'b00)
            $display("[WARN] cpu_write SLVERR: addr=0x%08X data=0x%08X", addr, wdata);
        else
            $display("[INFO] cpu_write OK    : addr=0x%08X data=0x%08X", addr, wdata);
    endtask

    // =========================================================
    // 7. 메인 시나리오
    // =========================================================
    initial begin
        $display("=== SMS SoC TB Start ===");

        // ─── 1. PS7 BFM 초기화 대기 ──────────────────────────
        @(posedge resetn);
        repeat(10) @(posedge fclk);
        $display("[INFO] PS7 BFM initialized @ %0t ns", $time/1000);

        // ─── 2. AES 키 설정 ──────────────────────────────────
        // 128-bit test key : 0x000102030405060708090a0b0c0d0e0f
        // aes_key = {key_reg3, key_reg2, key_reg1, key_reg0}
        //   key_reg0 = key[31:0]   = 32'h0c0d_0e0f  → offset 0x00
        //   key_reg1 = key[63:32]  = 32'h0809_0a0b  → offset 0x04
        //   key_reg2 = key[95:64]  = 32'h0405_0607  → offset 0x08
        //   key_reg3 = key[127:96] = 32'h0001_0203  → offset 0x0C
        $display("[INFO] AES key setup start");

        // ENC IP (base: 0x4000_1000)
        cpu_write(32'h4000_1000, 32'h0c0d_0e0f);
        cpu_write(32'h4000_1004, 32'h0809_0a0b);
        cpu_write(32'h4000_1008, 32'h0405_0607);
        cpu_write(32'h4000_100C, 32'h0001_0203);

        // DEC IP (base: 0x4000_0000) — 동일 키
        cpu_write(32'h4000_0000, 32'h0c0d_0e0f);
        cpu_write(32'h4000_0004, 32'h0809_0a0b);
        cpu_write(32'h4000_0008, 32'h0405_0607);
        cpu_write(32'h4000_000C, 32'h0001_0203);

        $display("[INFO] AES key setup done @ %0t ns", $time/1000);

        // ─── 3. 터치 입력 시뮬레이션 ─────────────────────────
        $display("[INFO] Touch input simulation start");
        touch_sim();

        // ─── 4. LCD DMA 시작 (내부 BRAM → BRAM_0) ──────────────
        // tft_lcd_axi_wrapper base : 0x4000_3000
        //   0x3000 : CTRL     [0]=start (auto-clear), [1]=bram_clear
        //   0x3008 : DST_ADDR → axi_bram_ctrl_0 (LCD m_axi 관점: 0xC000_0000)
        //   0x300C : TRF_LEN  → 784 bytes (28×28)
        $display("[INFO] LCD DMA start");
        cpu_write(32'h4000_3008, 32'hC000_0000);  // DST_ADDR
        cpu_write(32'h4000_300C, 32'd784);         // TRF_LEN
        cpu_write(32'h4000_3000, 32'h0000_0001);   // CTRL[0] = start

        // DMA 완료 대기 (타임아웃 100us)
        wait_signal("LCD DMA done     ", lcd_dma_done_lat, 100_000);

        // ─── 5. 구간별 handshake 체크 ────────────────────────
        // S2F (AES ENC → DRAM_1) : NPU 시작 전에 미리 설정해야
        // ENC 출력이 도달했을 때 바로 수신할 수 있음
        $display("[INFO] S2F pre-configure (DST=0x1000_0000, LEN=16)");
        cpu_write(32'h4000_5008, 32'h1000_0000); // S2F DST_ADDR (DRAM_1)
        cpu_write(32'h4000_500C, 32'd16);         // S2F TRF_LEN = 16 bytes (128-bit)
        cpu_write(32'h4000_5000, 32'h0000_0001);  // S2F start

        // NPU 추론 시작 (BRAM_0 → NPU → AXI-Stream → AES ENC)
        $display("[INFO] NPU start");
        cpu_write(32'h4000_2004, 32'h0000_0000);  // BRAM 오프셋 = 0
        cpu_write(32'h4000_2000, 32'h0000_0001);  // NPU start

        // 구간별 완료 모니터링 (각 1ms 타임아웃)
        wait_signal("NPU result_valid ", npu_result_valid_lat, 1_000_000);
        wait_signal("ENC output_valid ", enc_output_valid_lat, 1_000_000);
        wait_signal("S2F DMA done     ", s2f_dma_done_lat,     2_000_000);

        // F2S (DRAM_1 → AES DEC) 시작
        $display("[INFO] F2S start (SRC=0x1000_0000, LEN=16)");
        cpu_write(32'h4000_4008, 32'h1000_0000); // F2S SRC_ADDR (DRAM_1)
        cpu_write(32'h4000_400C, 32'd16);         // F2S TRF_LEN = 16 bytes
        cpu_write(32'h4000_4000, 32'h0000_0001);  // F2S start

        wait_signal("F2S stream done  ", f2s_stream_done_lat,  2_000_000);
        wait_signal("DEC output_valid ", dec_output_valid_lat, 1_000_000);

        // ─── 6. FND 출력 확인 ────────────────────────────────
        // DEC 출력 → xlslice[3:0] → FND 자동 전달 (CPU 개입 불필요)
        repeat(10) @(posedge fclk);
        $display("[INFO] FND digit_hold = %0d  @ %0t ns",
                 `FND.inst.digit_hold, $time/1000);
        $display("[INFO] seg=0x%02X  com=0x%01X",
                 seg_0, com_0);

        #1_000_000;
        $display("=== TB End ===");
        $finish;
    end

endmodule
