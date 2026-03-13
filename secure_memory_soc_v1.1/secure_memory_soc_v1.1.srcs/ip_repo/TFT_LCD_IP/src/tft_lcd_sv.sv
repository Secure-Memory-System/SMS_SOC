`timescale 1ns / 1ps

// ============================================================
// TFT LCD IP - 통합 서브모듈 파일
// tft_lcd_sv.sv (master) 기반으로 AXI wrapper에 맞게 구성
//
// 포함 모듈:
//   1. spi          - TFT SPI 컨트롤러 (counter==7 glitch 수정본)
//   2. tft_sv       - TFT LCD 드라이버 (SYNC_FRAME 자가치유 포함)
//   3. xpt2046      - 터치패드 컨트롤러
//   4. lcd_bram_dp  - 28x28 듀얼포트 BRAM (write_master ext_rd 지원)
//   5. tft_lcd_top  - AXI wrapper 연동용 최상위 모듈
// ============================================================

// ------------------------------------------------------------
// 1. SPI 컨트롤러
// ------------------------------------------------------------
module spi(
    input clk, reset_p,
    input[8:0] data,        // 최상위 비트는 명령어 or 데이터인지 결정
    input dataAvailable,    // flag
    output tft_sck,
    output reg tft_sdi, tft_dc,
    output tft_cs,
    output reg idle
    );

    reg internalSck, cs;
    reg[0:2] counter = 3'b0;
    reg[8:0] internalData;
    wire dataDc = internalData[8]; // 명령 or 데이터
    wire[0:7] dataShift = internalData[7:0]; // 최상위 비트부터 보냄

    assign tft_sck = internalSck & cs;
    assign tft_cs = !cs;

    always @ (posedge clk, posedge reset_p) begin
        if(reset_p)begin
            internalSck <= 1'b1;
            idle <= 1'b1;
            cs <= 1'b0;
        end
        else begin
            if (dataAvailable) begin
                internalData <= data;
                idle <= 1'b0;
            end
            if (!idle)begin
                internalSck <= !internalSck;
                if (internalSck) begin
                    tft_dc <= dataDc;
                    tft_sdi <= dataShift[counter];
                    cs <= 1'b1;
                    counter <= counter + 1'b1;
                    //idle <= &counter; // 각 비트 전체 & masking → glitch 발생 가능, 사용 안함
                    if(counter == 7) idle <= 1;
                end
            end
            else begin
                internalSck <= 1'b1;
                if (internalSck) cs <= 1'b0;
            end
        end
    end

endmodule

// ------------------------------------------------------------
// 2. TFT LCD 드라이버 (SYNC_FRAME 자가치유 포함)
// ------------------------------------------------------------
module tft_sv(
        input clk, reset_p,
        input tft_sdo,
        output wire tft_sck,
        output wire tft_sdi,
        output wire tft_dc,
        output reg tft_reset,
        output wire tft_cs,
        input[15:0] framebufferData,
        output wire framebufferClk,
        output reg [17:0] framebufferIndex,
        output reg [9:0] x);

        parameter INPUT_CLK_MHZ = 100;

        reg[8:0] spiData;
        reg spiDataSet = 1'b0;
        wire spiIdle;

        reg frameBufferLowByte;
        assign framebufferClk = !frameBufferLowByte;

        initial tft_reset = 1'b1;

        spi spi_inst (clk, 1'b0, spiData, spiDataSet, tft_sck, tft_sdi, tft_dc, tft_cs, spiIdle);

        parameter INIT_SEQ_LEN = 52;
        reg[5:0] initSeqCounter = 6'b0;

        reg[8:0] INIT_SEQ [0:INIT_SEQ_LEN-1] = '{
        {1'b0, 8'h28},
        {1'b0, 8'hCF}, {1'b1, 8'h00}, {1'b1, 8'h83}, {1'b1, 8'h30},
        {1'b0, 8'hED}, {1'b1, 8'h64}, {1'b1, 8'h03}, {1'b1, 8'h12}, {1'b1, 8'h81},
        {1'b0, 8'hE8}, {1'b1, 8'h85}, {1'b1, 8'h01}, {1'b1, 8'h79},
        {1'b0, 8'hCB}, {1'b1, 8'h39}, {1'b1, 8'h2C}, {1'b1, 8'h00}, {1'b1, 8'h34}, {1'b1, 8'h02},
        {1'b0, 8'hF7}, {1'b1, 8'h20},
        {1'b0, 8'hEA}, {1'b1, 8'h00}, {1'b1, 8'h00},
        {1'b0, 8'hC0}, {1'b1, 8'h26},
        {1'b0, 8'hC1}, {1'b1, 8'h11},
        {1'b0, 8'hC5}, {1'b1, 8'h35}, {1'b1, 8'h3E},
        {1'b0, 8'hC7}, {1'b1, 8'hBE},
        {1'b0, 8'h3A}, {1'b1, 8'h55},
        {1'b0, 8'hB1}, {1'b1, 8'h00}, {1'b1, 8'h1B},
        {1'b0, 8'h26}, {1'b1, 8'h01},
        {1'b0, 8'h51}, {1'b1, 8'hFF},
        {1'b0, 8'hB7}, {1'b1, 8'h07},
        {1'b0, 8'hB6}, {1'b1, 8'h0A}, {1'b1, 8'h82}, {1'b1, 8'h27}, {1'b1, 8'h00},
        {1'b0, 8'h29},
        {1'b0, 8'h2C}
        };

        // 매 프레임마다 강제로 좌표를 (0,0)으로 맞추는 자가 치유 시퀀스
        parameter SYNC_SEQ_LEN = 11;
        reg [3:0] syncCounter = 0;
        reg [8:0] SYNC_SEQ [0:SYNC_SEQ_LEN-1] = '{
            {1'b0, 8'h2A}, {1'b1, 8'h00}, {1'b1, 8'h00}, {1'b1, 8'h00}, {1'b1, 8'hEF}, // X좌표 리셋
            {1'b0, 8'h2B}, {1'b1, 8'h00}, {1'b1, 8'h00}, {1'b1, 8'h01}, {1'b1, 8'h3F}, // Y좌표 리셋
            {1'b0, 8'h2C} // 메모리 쓰기 재시작 명령
        };

        reg[23:0] remainingDelayTicks = 24'b0;

        enum logic[3:0] { START, HOLD_RESET, WAIT_FOR_POWERUP, SEND_INIT_SEQ, SYNC_FRAME, LOOP} state = START;

        reg [9:0] y;

        always @ (posedge clk, posedge reset_p)begin
          if(reset_p)begin
              frameBufferLowByte = 1;
              x = 0;
              y = 0;
              framebufferIndex = 0;
              state = START;
              remainingDelayTicks = 0;
              initSeqCounter = 6'b0;
              syncCounter = 0;
          end
          else begin
            spiDataSet <= 1'b0;
            if (remainingDelayTicks > 0)
            begin
                remainingDelayTicks <= remainingDelayTicks - 1'b1;
            end
            else if (spiIdle && !spiDataSet)
            begin
                case (state)
                    START: begin
                        tft_reset <= 1'b0;
                        remainingDelayTicks <= 24'(INPUT_CLK_MHZ * 10);
                        state <= HOLD_RESET;
                    end

                    HOLD_RESET: begin
                        tft_reset <= 1'b1;
                        remainingDelayTicks <= 24'(INPUT_CLK_MHZ * 120000);
                        state <= WAIT_FOR_POWERUP;
                        frameBufferLowByte <= 1'b0;
                    end

                    WAIT_FOR_POWERUP: begin
                        spiData <= {1'b0, 8'h11};
                        spiDataSet <= 1'b1;
                        remainingDelayTicks <= 24'(INPUT_CLK_MHZ * 5000);
                        state <= SEND_INIT_SEQ;
                        frameBufferLowByte <= 1'b1;
                    end

                    SEND_INIT_SEQ: begin
                        if (initSeqCounter < INIT_SEQ_LEN) begin
                            spiData <= INIT_SEQ[initSeqCounter];
                            spiDataSet <= 1'b1;
                            initSeqCounter <= initSeqCounter + 1'b1;
                        end
                        else begin
                            state <= LOOP;
                            remainingDelayTicks <= 24'(INPUT_CLK_MHZ * 10000);
                        end
                    end

                    SYNC_FRAME: begin
                        if (syncCounter < SYNC_SEQ_LEN) begin
                            spiData <= SYNC_SEQ[syncCounter];
                            spiDataSet <= 1'b1;
                            syncCounter <= syncCounter + 1'b1;
                        end else begin
                            state <= LOOP;
                        end
                    end

                    default: begin // LOOP 상태
                        framebufferIndex <= x[9:1] * 320 + y;

                        spiData <= !frameBufferLowByte ? {1'b1, ~framebufferData[15:8]} : {1'b1, ~framebufferData[7:0]};
                        spiDataSet <= 1'b1;
                        frameBufferLowByte <= ~frameBufferLowByte;

                        if(x >= 479)begin
                            x <= 0;
                            if(y >= 319) begin
                                y <= 0;
                                state <= SYNC_FRAME;
                                syncCounter <= 0;
                            end
                            else y <= y + 1;
                        end
                        else x <= x + 1;
                    end
                endcase
             end
            end
        end

endmodule

// ------------------------------------------------------------
// 3. XPT2046 터치패드 컨트롤러
// ------------------------------------------------------------
module xpt2046(
    Clk50m,
    Rst_n,
    EN,
    X_Value,
    Y_Value,
    Get_Flag,

    PenIrq_n,
    DCLK,
    DIN,
    DOUT,
    CS_N
);

    input Clk50m;
    input Rst_n;
    input EN;
    output reg [11:0]X_Value;
    output reg [11:0]Y_Value;

    output reg Get_Flag;

    input PenIrq_n;

    output reg DCLK;
    output reg DIN;
    output reg CS_N;
    input  DOUT;

    wire pen_flag;
    wire pen_state;

    reg [4:0]DIV_CNT;
    reg [5:0]CLK_GEN_CNT;
    reg [5:0]CONV_CNT;

    reg [19:0]PEN_CNT;

    reg DCLK2X;
    reg CONV_DONE;
    reg [11:0]Dtmp;
    reg EN_CONV;

    reg [16:0]tmp_X_Value,tmp_Y_Value;
    reg [11:0]X_MAX,X_MIN,Y_MAX,Y_MIN;
    reg r_Get_Flag;

    localparam S = 1'b1;
    localparam MODE = 1'b0;
    localparam SER_DFR = 1'b0;
    localparam PD = 2'b00;
    parameter CONV_TIMES = 36;
    parameter FILTER_PARAM = 4;

    parameter CNT_TOP = 20'd499999;

    wire [2:0]ADDR;
    assign ADDR = (CONV_CNT[0])?3'b101:3'b001;

    wire cnt_full;

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        PEN_CNT <= 20'd0;
    else if(!PenIrq_n)begin
        if(cnt_full)
            PEN_CNT <= 20'd0;
        else
            PEN_CNT <= PEN_CNT + 1'b1;
    end else
        PEN_CNT <= 20'd0;

    assign cnt_full = (PEN_CNT == CNT_TOP);
    assign pen_state = cnt_full;

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        DIV_CNT <= 5'd0;
    else if(EN_CONV)begin
        if(DIV_CNT == 5'd24)
            DIV_CNT <= 5'd0;
        else
            DIV_CNT <= DIV_CNT + 1'b1;
    end
    else
        DIV_CNT <= 5'd0;

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        DCLK2X <= 1'b0;
    else if(DIV_CNT == 5'd24)
        DCLK2X <= 1'b1;
    else
        DCLK2X <= 1'b0;

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        CLK_GEN_CNT <= 6'b0;
    else if(EN_CONV)begin
        if(DCLK2X)begin
            if(CLK_GEN_CNT == 6'd45)
                CLK_GEN_CNT <= 6'd16;
            else
                CLK_GEN_CNT <= CLK_GEN_CNT + 1'b1;
        end
    end
    else
        CLK_GEN_CNT <= 6'b0;

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)begin
        DIN <= 1'b1;
        Dtmp <= 12'd0;
        DCLK <= 1'd0;
        CONV_CNT <= 6'd0;
    end
    else if(EN_CONV)begin
        if(DCLK2X)begin
            case(CLK_GEN_CNT)
                0:begin DIN <= S; DCLK <= 1'b0; end
                1:begin DCLK <= 1'b1; end
                2:begin DIN <= ADDR[2]; DCLK <= 1'b0; end
                3:begin DCLK <= 1'b1; end
                4:begin DIN <= ADDR[1]; DCLK <= 1'b0; end
                5:begin DCLK <= 1'b1; end
                6:begin DIN <= ADDR[0]; DCLK <= 1'b0; end
                7:begin DCLK <= 1'b1; end
                8:begin DIN <= MODE; DCLK <= 1'b0; end
                9:begin DCLK <= 1'b1; end
                10:begin DIN <= SER_DFR; DCLK <= 1'b0; end
                11:begin DCLK <= 1'b1;end
                12:begin DIN <= PD[1]; DCLK <= 1'b0; end
                13:begin DCLK <= 1'b1; end
                14:begin DIN <= PD[0]; DCLK <= 1'b0; end
                15:begin DCLK <= 1'b1; end
                16:begin DIN <= 0; DCLK <= 1'b0; end
                17:begin DCLK <= 1'b1; end
                18:begin DIN <= 0; DCLK <= 1'b0; end
                19:begin Dtmp[11] <= DOUT; DCLK <= 1'b1; end
                20:begin DIN <= 0; DCLK <= 1'b0; end
                21:begin Dtmp[10] <= DOUT; DCLK <= 1'b1; end
                22:begin DIN <= 0; DCLK <= 1'b0; end
                23:begin Dtmp[9] <= DOUT; DCLK <= 1'b1; end
                24:begin DIN <= 0; DCLK <= 1'b0; end
                25:begin Dtmp[8] <= DOUT;DCLK <= 1'b1; end
                26:begin DIN <= 0; DCLK <= 1'b0; end
                27:begin Dtmp[7] <= DOUT; DCLK <= 1'b1; end
                28:begin DIN <= 0; DCLK <= 1'b0; end
                29:begin Dtmp[6] <= DOUT; DCLK <= 1'b1; end
                30:begin DIN <= S; DCLK <= 1'b0; end
                31:begin Dtmp[5] <= DOUT; DCLK <= 1'b1; end
                32:begin DIN <= ADDR[2]; DCLK <= 1'b0; end
                33:begin Dtmp[4] <= DOUT; DCLK <= 1'b1; end
                34:begin DIN <= ADDR[1]; DCLK <= 1'b0; end
                35:begin Dtmp[3] <= DOUT; DCLK <= 1'b1; end
                36:begin DIN <= ADDR[0]; DCLK <= 1'b0; end
                37:begin Dtmp[2] <= DOUT; DCLK <= 1'b1; end
                38:begin DIN <= MODE; DCLK <= 1'b0; end
                39:begin Dtmp[1] <= DOUT; DCLK <= 1'b1; end
                40:begin DIN <= SER_DFR; DCLK <= 1'b0; end
                41:begin Dtmp[0] <= DOUT; DCLK <= 1'b1; CONV_CNT <= CONV_CNT + 1'b1; end
                42:begin DIN <= PD[1]; DCLK <= 1'b0; end
                43:begin DCLK <= 1'b1; end
                44:begin DIN <= PD[0]; DCLK <= 1'b0; end
                45:begin DCLK <= 1'b1; CONV_DONE <= 1'b1; end
            endcase
        end else
            CONV_DONE <= 1'b0;
    end else if(!EN_CONV)begin
        CONV_CNT <= 0;
        CONV_DONE <= 1'b0;
    end

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        tmp_X_Value <= 17'd0;
    else if(EN_CONV == 1'b0)
        tmp_X_Value <= 17'd0;
    else if(CONV_DONE && CONV_CNT[0])
        tmp_X_Value <= tmp_X_Value + Dtmp;

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        X_MAX <= 12'd0;
    else if(EN_CONV == 1'b0)
        X_MAX <= 12'd0;
    else if(CONV_DONE && CONV_CNT[0])begin
        if(Dtmp > X_MAX)
            X_MAX <= Dtmp;
        else
            X_MAX <= X_MAX;
    end

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        X_MIN <= 12'd0;
    else if(EN_CONV == 1'b0)
        X_MIN <= 12'd4095;
    else if(CONV_DONE && CONV_CNT[0])begin
        if(Dtmp < X_MIN)
            X_MIN <= Dtmp;
        else
            X_MIN <= X_MIN;
    end

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        tmp_Y_Value <= 17'd0;
    else if(EN_CONV == 1'b0)
        tmp_Y_Value <= 17'd0;
    else if(CONV_DONE && (!CONV_CNT[0]))
        tmp_Y_Value <= tmp_Y_Value + Dtmp;

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        Y_MAX <= 12'd0;
    else if(EN_CONV == 1'b0)
        Y_MAX <= 12'd0;
    else if(CONV_DONE && (~CONV_CNT[0]))begin
        if(Dtmp > Y_MAX)
            Y_MAX <= Dtmp;
        else
            Y_MAX <= Y_MAX;
    end

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        Y_MIN <= 12'd0;
    else if(EN_CONV == 1'b0)
        Y_MIN <= 12'd4095;
    else if(CONV_DONE && (~CONV_CNT[0]))begin
        if(Dtmp < Y_MIN)
            Y_MIN <= Dtmp;
        else
            Y_MIN <= Y_MIN;
    end

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        EN_CONV <= 1'b0;
    else if(EN)begin
        if(pen_state)
            EN_CONV <= 1'b1;
        else if((CONV_CNT == CONV_TIMES) && CLK_GEN_CNT == 29)
            EN_CONV <= 1'b0;
        else
            EN_CONV <= EN_CONV;
    end
    else
        EN_CONV <= 1'b0;

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        r_Get_Flag <= 1'b0;
    else if((CONV_CNT == CONV_TIMES) && CONV_DONE)
            r_Get_Flag <= 1'b1;
    else
        r_Get_Flag <= 1'b0;

    always@(posedge Clk50m)
        Get_Flag <= r_Get_Flag;

    always@(posedge Clk50m)
        CS_N <= ~EN_CONV;

    reg [11:0]r_X_Value,r_Y_Value;

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        r_X_Value <= 12'd0;
    else if(r_Get_Flag)
        r_X_Value <= (tmp_X_Value - X_MAX - X_MIN) >> FILTER_PARAM;
    else
        r_X_Value <= r_X_Value;

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        r_Y_Value <= 12'd0;
    else if(r_Get_Flag)
        r_Y_Value <= (tmp_Y_Value - Y_MAX - Y_MIN) >> FILTER_PARAM;
    else
        r_Y_Value <= r_Y_Value;

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        X_Value <= 12'd0;
    else if(r_Get_Flag)
        X_Value <= r_X_Value;

    always@(posedge Clk50m or negedge Rst_n)
    if(!Rst_n)
        Y_Value <= 12'd0;
    else if(r_Get_Flag)
        Y_Value <= r_Y_Value;

endmodule

// ------------------------------------------------------------
// 4. 듀얼포트 BRAM (28x28, write_master ext_rd 지원)
// ------------------------------------------------------------
module lcd_bram_dp #(
    parameter WIDTH = 8,
    parameter DEPTH = 28 * 28   // 784
)(
    // Port A: LCD 표시 읽기 + 터치/클리어 쓰기
    input  wire               clka,
    input  wire               ena,
    input  wire               wea,
    input  wire [9:0]         addra,
    input  wire [WIDTH-1:0]   dina,
    output reg  [WIDTH-1:0]   douta,

    // Port B: write_master 읽기 전용
    input  wire               clkb,
    input  wire               enb,
    input  wire [9:0]         addrb,
    output reg  [WIDTH-1:0]   doutb
);

    reg [WIDTH-1:0] ram [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            ram[i] = 8'h00;
    end

    // Port A: Write-First
    always @(posedge clka) begin
        if (ena) begin
            if (wea) begin
                ram[addra] <= dina;
                douta <= dina;
            end else begin
                douta <= ram[addra];
            end
        end
    end

    // Port B: 읽기 전용
    always @(posedge clkb) begin
        if (enb) begin
            doutb <= ram[addrb];
        end
    end

endmodule

// ------------------------------------------------------------
// 5. tft_lcd_top - AXI wrapper 연동용 최상위 모듈
//    tft_lcd_axi_wrapper.v 에서 인스턴스화됨
//    포트: pen_lock, bram_clear, ext_rd_addr, ext_rd_data
// ------------------------------------------------------------
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

    // AXI wrapper 제어 포트
    input  wire        pen_lock,      // 1이면 터치 입력 차단 (DMA 전송 중)
    input  wire        bram_clear,    // 1이면 내부 BRAM 전체 클리어

    // write_master 외부 읽기 포트
    input  wire [9:0]  ext_rd_addr,
    output wire [7:0]  ext_rd_data
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
    // 3. 내부 BRAM (듀얼포트)
    //    Port A: LCD 표시 읽기 + 터치/클리어 쓰기
    //    Port B: write_master 읽기 전용
    // =========================================================
    reg [9:0]  wr_addr;
    reg [7:0]  data_to_ram;
    wire [7:0] data_from_ram;

    // BRAM 클리어 FSM
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

    wire        bram_wr_en;
    wire [9:0]  bram_wr_addr;
    wire [7:0]  bram_wr_data;

    assign bram_wr_en   = clearing ? 1'b1 :
                          (~pen_lock && ~PenIrq_n) ? 1'b1 : 1'b0;
    assign bram_wr_addr = clearing ? clr_addr : wr_addr;
    assign bram_wr_data = clearing ? 8'h00    : 8'hff;

    lcd_bram_dp #(.DEPTH(28*28)) lcd_mem(
        .clka    (clk),
        .ena     (1'b1),
        .wea     (bram_wr_en),
        .addra   (bram_wr_en ? bram_wr_addr : rd_addr),
        .dina    (bram_wr_data),
        .douta   (data_from_ram),
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

    wire [15:0] peny_inv   = (16'd319 > peny_320) ? (16'd319 - peny_320) : 16'd0;
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
