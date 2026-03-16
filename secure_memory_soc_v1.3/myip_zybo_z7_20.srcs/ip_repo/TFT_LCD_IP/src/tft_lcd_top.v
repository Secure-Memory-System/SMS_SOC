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
    // 외부 제어 포트
    // =========================================================
    input  wire        pen_lock,      // 1이면 터치 입력 차단 (DMA 전송 중)
    input  wire        bram_clear,    // 1이면 내부 BRAM 전체 클리어

    // 외부 BRAM 읽기 포트 폭
    input  wire [7:0]  ext_rd_addr,   // 10-bit -> 8-bit
    output wire [31:0] ext_rd_data    // 8-bit -> 32-bit
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
    // 3. 터치패드 컨트롤러 
    // =========================================================
    reg Clk50M = 0;
    always @(posedge clk) Clk50M <= ~Clk50M;
    wire Rst_n = ~reset_p;
    
    wire [11:0] X_Value, Y_Value;
    (* mark_debug = "true" *) wire Get_Flag;
    
    xpt2046 touch_pad(Clk50M, Rst_n, 1'b1, X_Value, Y_Value, Get_Flag, PenIrq_n, DCLK, DIN, DOUT, CS_N);

    // =========================================================
    // 4. 터치 좌표 -> 28x28 해상도 맵핑 (입력용)
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

    // =========================================================
    // 5. BRAM 클리어 로직 (복구됨!)
    // =========================================================
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

    // =========================================================
    // 6. 3x3 붓(Brush) 효과 연속 그리기 로직
    // =========================================================
    // 화면 바깥으로 넘어가지 않도록 경계(0~27) 안전장치 추가
    wire [4:0] gx = grid_touch_x;
    wire [4:0] gy = grid_touch_y;
    wire [4:0] gx_m = (gx > 0)  ? gx - 1 : 0;
    wire [4:0] gx_p = (gx < 27) ? gx + 1 : 27;
    wire [4:0] gy_m = (gy > 0)  ? gy - 1 : 0;
    wire [4:0] gy_p = (gy < 27) ? gy + 1 : 27;

    reg [3:0] brush_state;
    reg [9:0] brush_addr;
    (* mark_debug = "true" *) reg  brush_wr_en;

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            brush_state <= 0;
            brush_wr_en <= 0;
        end else begin
            // 좌표 획득(Get_Flag) 시 4클럭 동안 2x2 픽셀 도장 찍기
            // MNIST 획 두께(1~2px)에 가깝게 맞춤
            if (Get_Flag && ~pen_lock) begin
                brush_state <= 1;
            end else if (brush_state > 0) begin
                case (brush_state)
                    1: begin brush_addr <= (gy   * 10'd28) + gx;   brush_wr_en <= 1; brush_state <= 2; end
                    2: begin brush_addr <= (gy   * 10'd28) + gx_p; brush_wr_en <= 1; brush_state <= 3; end
                    3: begin brush_addr <= (gy_p * 10'd28) + gx;   brush_wr_en <= 1; brush_state <= 4; end
                    4: begin brush_addr <= (gy_p * 10'd28) + gx_p; brush_wr_en <= 1; brush_state <= 0; end
                    default: begin brush_wr_en <= 0; brush_state <= 0; end
                endcase
            end else begin
                brush_wr_en <= 0;
            end
        end
    end

    // =========================================================
    // 7. 쓰기 주소 및 데이터 MUX (우선순위: Clear > Brush)
    // =========================================================
    (* mark_debug = "true" *) wire bram_wr_en;
    wire [9:0]  bram_wr_addr;
    wire [7:0]  bram_wr_data;
    wire [7:0]  data_from_ram;

    assign bram_wr_en   = clearing ? 1'b1 : brush_wr_en;
    assign bram_wr_addr = clearing ? clr_addr : brush_addr;
    assign bram_wr_data = clearing ? 8'h00    : 8'hff;

    // 듀얼 포트 BRAM 인스턴스
    lcd_bram_dp #(.DEPTH(28*28)) lcd_mem(
        // Port A (LCD 표시 및 터치 쓰기)
        .clka    (clk),
        .ena     (1'b1),
        .wea     (bram_wr_en),
        .addra   (bram_wr_en ? bram_wr_addr : rd_addr),
        .dina    (bram_wr_data),
        .douta   (data_from_ram),

        // Port B (write_master AXI 전송용)
        .clkb    (clk),
        .enb     (1'b1),
        .addrb   (ext_rd_addr),
        .doutb   (ext_rd_data)
    );

    // =========================================================
    // 8. TFT LCD 출력
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