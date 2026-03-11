`timescale 1ns / 1ps

module tft_lcd_top(
    input clk, reset_p,
    input tft_sdo, 
    output tft_sck, 
    output tft_sdi, 
    output tft_dc, 
    output tft_reset, 
    output tft_cs,
    
    input PenIrq_n,
    output DCLK,
    output DIN,
    output CS_N,
    input  DOUT,

    // =========================================================
    // [추가] 외부 제어 포트
    // =========================================================
    input  wire        pen_lock,      // 1이면 터치 입력 차단 (DMA 전송 중)
    input  wire        bram_clear,    // 1이면 내부 BRAM 전체 클리어

    // [추가] 외부 BRAM 읽기 포트 (write_master가 직접 읽음)
    input  wire [9:0]  ext_rd_addr,   // write_master가 지정하는 읽기 주소 (0~783)
    output wire [7:0]  ext_rd_data    // write_master로 나가는 데이터
);

    // =========================================================
    // 1. LCD 컨트롤러 스캔 동기화 (Y좌표 자체 카운트)
    // =========================================================
    wire [9:0] lcd_x;
    reg [8:0] internal_y; 
    reg [9:0] prev_x;     

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            internal_y <= 0;
            prev_x <= 0;
        end else begin
            prev_x <= lcd_x; 
            if (prev_x == 479 && lcd_x == 0) begin
                if (internal_y >= 319) internal_y <= 0;
                else internal_y <= internal_y + 1;
            end
        end
    end

    // =========================================================
    // 2. 물리 해상도(240x320) -> 논리 해상도(28x28) 맵핑 (출력용)
    // =========================================================
    wire [7:0] px_x = lcd_x[9:1];
    wire [8:0] px_y = internal_y;

    wire [15:0] calc_lcd_x = (px_x * 16'd120) >> 10;
    wire [15:0] calc_lcd_y = (px_y * 16'd90)  >> 10;

    wire [4:0] grid_lcd_x = (calc_lcd_x > 27) ? 5'd27 : calc_lcd_x[4:0];
    wire [4:0] grid_lcd_y = (calc_lcd_y > 27) ? 5'd27 : calc_lcd_y[4:0];

    reg [9:0] rd_addr;
    always @(*) begin
        rd_addr = (grid_lcd_y * 10'd28) + grid_lcd_x;
    end

    // =========================================================
    // 3. 내부 BRAM (DEPTH = 28 * 28 = 784)
    //    포트 A: LCD 표시용 읽기 / 터치 쓰기
    //    포트 B: write_master 읽기 (ext_rd_addr / ext_rd_data)
    // =========================================================
    reg [9:0]  wr_addr;
    reg [7:0]  data_to_ram;
    wire [7:0] data_from_ram;   // LCD 표시용

    // [추가] BRAM 클리어 FSM
    reg        clearing;
    reg [9:0]  clr_addr;

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            clearing <= 0;
            clr_addr <= 0;
        end else begin
            if (bram_clear && !clearing) begin
                clearing <= 1;
                clr_addr <= 0;
            end else if (clearing) begin
                if (clr_addr >= 10'd783)
                    clearing <= 0;
                else
                    clr_addr <= clr_addr + 1;
            end
        end
    end

    // BRAM 쓰기 주소/데이터 MUX
    //  우선순위: clear > 터치 (pen_lock 중에는 터치 차단)
    wire        bram_wr_en;
    wire [9:0]  bram_wr_addr;
    wire [7:0]  bram_wr_data;

    assign bram_wr_en   = clearing ? 1'b1 :
                          (~pen_lock && ~PenIrq_n) ? 1'b1 : 1'b0;
    assign bram_wr_addr = clearing ? clr_addr : wr_addr;
    assign bram_wr_data = clearing ? 8'h00    : 8'hff;

    // 듀얼 포트 BRAM 인스턴스
    //   포트 A: LCD 읽기 + 터치/클리어 쓰기
    //   포트 B: write_master 읽기 전용
    lcd_bram_dp #(.DEPTH(28*28)) lcd_mem(
        // Port A
        .clka    (clk),
        .ena     (1'b1),
        .wea     (bram_wr_en),
        .addra   (bram_wr_en ? bram_wr_addr : rd_addr),
        .dina    (bram_wr_data),
        .douta   (data_from_ram),

        // Port B (write_master 전용)
        .clkb    (clk),
        .enb     (1'b1),
        .addrb   (ext_rd_addr),
        .doutb   (ext_rd_data)
    );

    // =========================================================
    // 4. 터치패드 컨트롤러
    // =========================================================
    reg Clk50M = 0;
    always @(posedge clk) Clk50M <= ~Clk50M;
    wire Rst_n = ~reset_p;
    
    wire [11:0] X_Value, Y_Value;
    wire Get_Flag;
    
    xpt2046 touch_pad(Clk50M, Rst_n, 1'b1, X_Value, Y_Value, Get_Flag, PenIrq_n, DCLK, DIN, DOUT, CS_N);

    // =========================================================
    // 5. 터치 좌표 -> 28x28 해상도 맵핑 (입력용)
    // =========================================================
    wire [11:0] x_tmp = (X_Value > 12'd300) ? (X_Value - 12'd300) : 12'd0;
    wire [11:0] y_tmp = (Y_Value > 12'd300) ? (Y_Value - 12'd300) : 12'd0;

    wire [15:0] penx_240 = (x_tmp * 32'd70) >> 10; 
    wire [15:0] peny_320 = (y_tmp * 32'd94) >> 10; 

    wire [15:0] peny_inv  = (16'd319 > peny_320) ? (16'd319 - peny_320) : 16'd0;
    wire [15:0] penx_calib = penx_240 + 16'd15; 
    wire [15:0] peny_calib = peny_inv + 16'd0;  

    wire [15:0] t_x = (penx_calib > 16'd239) ? 16'd239 : penx_calib;
    wire [15:0] t_y = (peny_calib > 16'd319) ? 16'd319 : peny_calib;

    wire [15:0] calc_touch_x = (t_x * 32'd120) >> 10;
    wire [15:0] calc_touch_y = (t_y * 32'd90)  >> 10;
    
    wire [4:0] grid_touch_x = (calc_touch_x > 27) ? 5'd27 : calc_touch_x[4:0];
    wire [4:0] grid_touch_y = (calc_touch_y > 27) ? 5'd27 : calc_touch_y[4:0];

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            wr_addr      <= 0;
            data_to_ram  <= 0;
        end else begin
            wr_addr     <= (grid_touch_y * 10'd28) + grid_touch_x; 
            data_to_ram <= 8'hff; 
        end
    end

    // =========================================================
    // 6. TFT LCD 출력
    // =========================================================
    wire framebufferClk;
    wire [17:0] framebufferIndex;
    
    tft_sv lcd(
        .clk(clk), 
        .reset_p(reset_p), 
        .tft_sdo(tft_sdo), 
        .tft_sck(tft_sck), 
        .tft_sdi(tft_sdi), 
        .tft_dc(tft_dc), 
        .tft_reset(tft_reset), 
        .tft_cs(tft_cs),
        .framebufferData({8'b0, data_from_ram}), 
        .framebufferClk(framebufferClk), 
        .framebufferIndex(framebufferIndex), 
        .x(lcd_x)  
    );

endmodule