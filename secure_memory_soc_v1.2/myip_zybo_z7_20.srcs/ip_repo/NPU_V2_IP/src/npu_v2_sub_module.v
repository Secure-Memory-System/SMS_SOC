`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: mnist_cnn_micro (Corrected Pipeline & Initialization)
//////////////////////////////////////////////////////////////////////////////////

// ============================================================
//  (1) npu_conv2d_buf  - BRAM/Reg 초기화 추가
// ============================================================
module npu_conv2d_buf(
    input clk, reset_p,
    input start,
    input [7:0] pixel,
    input calc_busy,
    output reg [9:0] buf_idx,
    output reg [7:0] value_00, value_01, value_02,
                     value_03, value_04, value_05,
                     value_06, value_07, value_08,
    output reg valid_buf
);
    localparam WIDTH = 28;
    (* ram_style = "distributed" *) reg [7:0] line_buf0 [0:WIDTH-1];
    (* ram_style = "distributed" *) reg [7:0] line_buf1 [0:WIDTH-1];
    reg [7:0] win00, win01, win02, win10, win11, win12, win20, win21, win22;
    reg [4:0] col_cnt, row_cnt;
    reg [1:0] state;
    localparam S_IDLE = 0, S_STREAM = 1;
    
    integer i; // 초기화를 위한 변수

    always @(posedge clk) begin
        if (reset_p) begin
            state <= S_IDLE;
            col_cnt <= 0; row_cnt <= 0;
            buf_idx <= 0; valid_buf <= 0;
            
            // x값 전파를 막기 위한 명시적 초기화
            for (i = 0; i < WIDTH; i = i + 1) begin
                line_buf0[i] <= 0;
                line_buf1[i] <= 0;
            end
            win00<=0; win01<=0; win02<=0; win10<=0; win11<=0; win12<=0; win20<=0; win21<=0; win22<=0;
            value_00<=0; value_01<=0; value_02<=0; value_03<=0; value_04<=0; value_05<=0; value_06<=0; value_07<=0; value_08<=0;
        end else begin
            valid_buf <= 0;
            case (state)
                S_IDLE: begin
                    if (start) state <= S_STREAM;
                    col_cnt <= 0; row_cnt <= 0; buf_idx <= 0;
                end
                S_STREAM: begin
                    if (!calc_busy) begin
                        win02 <= pixel;
                        win01 <= win02; win00 <= win01;
                        win12 <= line_buf0[col_cnt]; win11 <= win12; win10 <= win11;
                        win22 <= line_buf1[col_cnt];
                        win21 <= win22; win20 <= win21;

                        line_buf1[col_cnt] <= line_buf0[col_cnt];
                        line_buf0[col_cnt] <= pixel;
                        if (row_cnt >= 2 && col_cnt >= 2) begin
                            valid_buf <= 1;
                            value_00 <= win20; value_01 <= win21; value_02 <= win22;
                            value_03 <= win10; value_04 <= win11; value_05 <= win12;
                            value_06 <= win00; value_07 <= win01; value_08 <= win02;
                        end

                        if (col_cnt == WIDTH-1) begin
                            col_cnt <= 0;
                            if (row_cnt == WIDTH-1) state <= S_IDLE;
                            else row_cnt <= row_cnt + 1;
                        end else col_cnt <= col_cnt + 1;
                        buf_idx <= buf_idx + 1;
                    end
                end
            endcase
        end
    end
endmodule


// ============================================================
//  (2) npu_conv2d_calc
// ============================================================
module npu_conv2d_calc(
    input clk, reset_p,
    input valid_buf,
    input [7:0] value_00, value_01, value_02, value_03, value_04,
                value_05, value_06, value_07, value_08,
    output reg signed [19:0] conv_out_0, conv_out_1, conv_out_2, conv_out_3, conv_out_4,
    output reg valid_out_calc,
    output reg busy
);
    reg signed [7:0] weight_0 [0:8], weight_1 [0:8], weight_2 [0:8],
                     weight_3 [0:8], weight_4 [0:8];
    reg signed [7:0] bias [0:4];

    initial begin
        $readmemh("55_conv2d_weights_filter_0.txt", weight_0);
        $readmemh("55_conv2d_weights_filter_1.txt", weight_1);
        $readmemh("55_conv2d_weights_filter_2.txt", weight_2);
        $readmemh("55_conv2d_weights_filter_3.txt", weight_3);
        $readmemh("55_conv2d_weights_filter_4.txt", weight_4);
        $readmemh("55_conv2d_bias.txt", bias);
    end

    reg [3:0] k;
    reg [7:0] value_buf [0:8];
    reg [7:0] input_reg [0:8];
    reg       input_pending;
    reg signed [19:0] acc0, acc1, acc2, acc3, acc4;
    
    // ★ 안전한 바이어스 스케일 업 (128 -> 16384 맞춤)
    wire signed [19:0] ext_b0 = $signed(bias[0]);
    wire signed [19:0] ext_b1 = $signed(bias[1]);
    wire signed [19:0] ext_b2 = $signed(bias[2]);
    wire signed [19:0] ext_b3 = $signed(bias[3]);
    wire signed [19:0] ext_b4 = $signed(bias[4]);

    always @(posedge clk) begin
        if (reset_p) begin
            {conv_out_0, conv_out_1, conv_out_2, conv_out_3, conv_out_4} <= 0;
            valid_out_calc <= 0;
            busy <= 0; k <= 0;
            acc0 <= 0; acc1 <= 0; acc2 <= 0;
            acc3 <= 0; acc4 <= 0;
            input_pending <= 0;
        end else begin
            valid_out_calc <= 0;
            if (valid_buf && busy) begin
                input_reg[0] <= value_00;
                input_reg[1] <= value_01; input_reg[2] <= value_02;
                input_reg[3] <= value_03; input_reg[4] <= value_04; input_reg[5] <= value_05;
                input_reg[6] <= value_06;
                input_reg[7] <= value_07; input_reg[8] <= value_08;
                input_pending <= 1;
            end

            if (valid_buf && !busy) begin
                value_buf[0] <= value_00; value_buf[1] <= value_01; value_buf[2] <= value_02;
                value_buf[3] <= value_03; value_buf[4] <= value_04; value_buf[5] <= value_05;
                value_buf[6] <= value_06; value_buf[7] <= value_07; value_buf[8] <= value_08;
                acc0 <= 0; acc1 <= 0; acc2 <= 0; acc3 <= 0; acc4 <= 0;
                k <= 0; busy <= 1;

            end else if (busy) begin
                if (k <= 8) begin
                    acc0 <= acc0 + $signed({1'b0, value_buf[k]}) * weight_0[k];
                    acc1 <= acc1 + $signed({1'b0, value_buf[k]}) * weight_1[k];
                    acc2 <= acc2 + $signed({1'b0, value_buf[k]}) * weight_2[k];
                    acc3 <= acc3 + $signed({1'b0, value_buf[k]}) * weight_3[k];
                    acc4 <= acc4 + $signed({1'b0, value_buf[k]}) * weight_4[k];
                    if (k == 8) k <= 9;
                    else        k <= k + 1;
                end else begin
                    // ★ 변경: 바이어스를 7칸 시프트(x128)해서 스케일 통일
                    conv_out_0 <= ($signed(acc0) + (ext_b0<<<7) < 0) ? 20'sd0 : $signed(acc0) + (ext_b0<<<7);
                    conv_out_1 <= ($signed(acc1) + (ext_b1<<<7) < 0) ? 20'sd0 : $signed(acc1) + (ext_b1<<<7);
                    conv_out_2 <= ($signed(acc2) + (ext_b2<<<7) < 0) ? 20'sd0 : $signed(acc2) + (ext_b2<<<7);
                    conv_out_3 <= ($signed(acc3) + (ext_b3<<<7) < 0) ? 20'sd0 : $signed(acc3) + (ext_b3<<<7);
                    conv_out_4 <= ($signed(acc4) + (ext_b4<<<7) < 0) ? 20'sd0 : $signed(acc4) + (ext_b4<<<7);
                    valid_out_calc <= 1;
                    k <= 0;

                    if (input_pending) begin
                        value_buf[0] <= input_reg[0]; value_buf[1] <= input_reg[1]; value_buf[2] <= input_reg[2];
                        value_buf[3] <= input_reg[3]; value_buf[4] <= input_reg[4]; value_buf[5] <= input_reg[5];
                        value_buf[6] <= input_reg[6]; value_buf[7] <= input_reg[7]; value_buf[8] <= input_reg[8];
                        acc0 <= 0; acc1 <= 0; acc2 <= 0; acc3 <= 0; acc4 <= 0;
                        input_pending <= 0;
                        busy <= 1;
                    end else begin
                        busy <= 0;
                    end
                end
            end
        end
    end
endmodule

// ============================================================
//  (3) npu_maxpool_conv2d - BRAM/Reg 초기화 추가
// ============================================================
module npu_maxpool_conv2d(
    input clk, reset_p,
    input valid_calc,
    input signed [19:0] conv_out_0, conv_out_1, conv_out_2, conv_out_3, conv_out_4,
    output reg signed [19:0] max_value_0, max_value_1, max_value_2, max_value_3, max_value_4,
    output reg max_value_valid
);
    (* ram_style = "distributed" *) reg signed [19:0] line_buf_0 [0:12];
    (* ram_style = "distributed" *) reg signed [19:0] line_buf_1 [0:12];
    (* ram_style = "distributed" *) reg signed [19:0] line_buf_2 [0:12];
    (* ram_style = "distributed" *) reg signed [19:0] line_buf_3 [0:12];
    (* ram_style = "distributed" *) reg signed [19:0] line_buf_4 [0:12];

    reg [4:0] cnt_x, cnt_y;
    wire [3:0] buf_idx = cnt_x[4:1];
    integer i;

    always @(posedge clk) begin
        if (reset_p) begin
            cnt_x <= 0; cnt_y <= 0; max_value_valid <= 0;
            max_value_0 <= 0; max_value_1 <= 0; max_value_2 <= 0; max_value_3 <= 0; max_value_4 <= 0;
            for(i=0; i<13; i=i+1) begin
                line_buf_0[i] <= 0; line_buf_1[i] <= 0; line_buf_2[i] <= 0;
                line_buf_3[i] <= 0; line_buf_4[i] <= 0;
            end
        end else begin
            max_value_valid <= 0;
            if (valid_calc) begin
                case ({cnt_y[0], cnt_x[0]})
                    2'b00: begin
                        line_buf_0[buf_idx] <= conv_out_0; line_buf_1[buf_idx] <= conv_out_1;
                        line_buf_2[buf_idx] <= conv_out_2; line_buf_3[buf_idx] <= conv_out_3;
                        line_buf_4[buf_idx] <= conv_out_4;
                    end
                    2'b01, 2'b10: begin
                        if (conv_out_0 > line_buf_0[buf_idx]) line_buf_0[buf_idx] <= conv_out_0;
                        if (conv_out_1 > line_buf_1[buf_idx]) line_buf_1[buf_idx] <= conv_out_1;
                        if (conv_out_2 > line_buf_2[buf_idx]) line_buf_2[buf_idx] <= conv_out_2;
                        if (conv_out_3 > line_buf_3[buf_idx]) line_buf_3[buf_idx] <= conv_out_3;
                        if (conv_out_4 > line_buf_4[buf_idx]) line_buf_4[buf_idx] <= conv_out_4;
                    end
                    2'b11: begin
                        max_value_0 <= (conv_out_0 > line_buf_0[buf_idx]) ? conv_out_0 : line_buf_0[buf_idx];
                        max_value_1 <= (conv_out_1 > line_buf_1[buf_idx]) ? conv_out_1 : line_buf_1[buf_idx];
                        max_value_2 <= (conv_out_2 > line_buf_2[buf_idx]) ? conv_out_2 : line_buf_2[buf_idx];
                        max_value_3 <= (conv_out_3 > line_buf_3[buf_idx]) ? conv_out_3 : line_buf_3[buf_idx];
                        max_value_4 <= (conv_out_4 > line_buf_4[buf_idx]) ? conv_out_4 : line_buf_4[buf_idx];
                        max_value_valid <= 1;
                    end
                endcase

                if (cnt_x == 25) begin
                    cnt_x <= 0;
                    if (cnt_y == 25) cnt_y <= 0;
                    else cnt_y <= cnt_y + 1;
                end else cnt_x <= cnt_x + 1;
            end
        end
    end
endmodule// ============================================================
//  (4) npu_dense_integrated
// ============================================================
module npu_dense_integrated(
    input clk, reset_p,
    input max_value_valid,
    input signed [19:0] max_value_0, max_value_1, max_value_2, max_value_3, max_value_4,
    output reg signed [27:0] d_out_0, d_out_1, d_out_2, d_out_3, d_out_4,
    output reg dense_done
);
    localparam S_IDLE       = 3'd0,
               S_STORE      = 3'd1,
               S_CALC_START = 3'd2,
               S_CALC_PIPE  = 3'd3,
               S_NEXT       = 3'd4;
               
    reg [2:0] state;

    (* ram_style = "block" *) reg signed [19:0] flat_mem0 [0:168];
    (* ram_style = "block" *) reg signed [19:0] flat_mem1 [0:168];
    (* ram_style = "block" *) reg signed [19:0] flat_mem2 [0:168];
    (* ram_style = "block" *) reg signed [19:0] flat_mem3 [0:168];
    (* ram_style = "block" *) reg signed [19:0] flat_mem4 [0:168];
    (* ram_style = "block" *)       reg signed [7:0] w_rom [0:4224];
    (* ram_style = "distributed" *) reg signed [7:0] b_rom [0:4];

    integer i;
    initial begin
        $readmemh("55_dense_weights.txt", w_rom);
        $readmemh("55_dense_bias.txt",    b_rom);
        for(i=0; i<169; i=i+1) begin
            flat_mem0[i] = 0; flat_mem1[i] = 0; flat_mem2[i] = 0; 
            flat_mem3[i] = 0; flat_mem4[i] = 0;
        end
    end

    reg [7:0]  wr_addr;
    reg [7:0]  rd_addr;
    reg [2:0]  mem_sel;
    reg [2:0]  n_ptr;
    reg [12:0] w_addr;
    reg [10:0] pipe_cnt; 
    reg signed [39:0] acc;
    reg signed [27:0] d_out_reg [0:4];
    
    reg signed [19:0] flat_rd_data;
    always @(posedge clk) begin
        case (mem_sel)
            3'd0: flat_rd_data <= flat_mem0[rd_addr];
            3'd1: flat_rd_data <= flat_mem1[rd_addr];
            3'd2: flat_rd_data <= flat_mem2[rd_addr];
            3'd3: flat_rd_data <= flat_mem3[rd_addr];
            3'd4: flat_rd_data <= flat_mem4[rd_addr];
            default: flat_rd_data <= 20'sd0;
        endcase
    end

    reg signed [7:0] w_rd_data;
    always @(posedge clk) begin
        w_rd_data <= w_rom[w_addr];
    end

    always @(posedge clk) begin
        if ((state == S_IDLE || state == S_STORE) && max_value_valid) begin
            flat_mem0[wr_addr] <= max_value_0;
            flat_mem1[wr_addr] <= max_value_1;
            flat_mem2[wr_addr] <= max_value_2;
            flat_mem3[wr_addr] <= max_value_3;
            flat_mem4[wr_addr] <= max_value_4;
        end
    end

    wire signed [39:0] ext_flat = $signed(flat_rd_data);
    wire signed [39:0] ext_w    = $signed(w_rd_data);
    // ★ Dense 레이어 누적값은 2백만대 스케일! 바이어스는 14칸(x16384) 시프트해야 일치
    wire signed [39:0] ext_b    = $signed(b_rom[n_ptr]); 

    always @(posedge clk) begin
        if (reset_p) begin
            state       <= S_IDLE;
            wr_addr     <= 8'd0;  rd_addr <= 8'd0;
            mem_sel     <= 3'd0;  w_addr  <= 13'd0;
            pipe_cnt    <= 11'd0; acc     <= 40'sd0;
            dense_done  <= 1'b0;  n_ptr   <= 3'd0;
            d_out_reg[0]<= 28'sd0; d_out_reg[1]<= 28'sd0; d_out_reg[2]<= 28'sd0; 
            d_out_reg[3]<= 28'sd0; d_out_reg[4]<= 28'sd0;
        end else begin
            case (state)
                S_IDLE: begin
                    dense_done <= 1'b0; wr_addr <= 8'd0;
                    if (max_value_valid) begin wr_addr <= 8'd1; state <= S_STORE; end
                end
                
                S_STORE: begin
                    if (wr_addr == 8'd168) begin
                        // BRAM[168]은 이전 클럭에 이미 쓰임 -> 즉시 CALC로
                        wr_addr <= 8'd0; state <= S_CALC_START;
                    end else if (max_value_valid) begin
                        wr_addr <= wr_addr + 8'd1;
                    end
                end 

                S_CALC_START: begin
                    rd_addr <= 8'd0; mem_sel <= 3'd0;
                    w_addr <= {10'd0, n_ptr}; 
                    pipe_cnt <= 11'd0; acc <= 40'sd0;
                    state <= S_CALC_PIPE;
                end

                S_CALC_PIPE: begin
                    if (pipe_cnt > 0 && pipe_cnt <= 11'd845) acc <= acc + (ext_flat * ext_w);

                    if (pipe_cnt == 11'd845) begin
                        state <= S_NEXT;
                    end else begin
                        if (w_addr + 13'd5 <= 13'd4224) w_addr <= w_addr + 13'd5;
                        
                        if (mem_sel == 3'd4) begin
                            mem_sel <= 3'd0; rd_addr <= rd_addr + 8'd1;
                        end else mem_sel <= mem_sel + 3'd1;
                        pipe_cnt <= pipe_cnt + 11'd1;
                    end
                end

                S_NEXT: begin
                    // ★ 변경: (ext_b <<< 14) 로 스케일 통일
                    if ((acc + (ext_b <<< 14)) < 40'sd0)
                        d_out_reg[n_ptr] <= 28'sd0;
                    else
                        d_out_reg[n_ptr] <= (acc + (ext_b <<< 14)) >>> 7;

                    if (n_ptr == 3'd4) begin
                        n_ptr <= 3'd0; dense_done <= 1'b1; state <= S_IDLE;
                    end else begin
                        n_ptr <= n_ptr + 3'd1; state <= S_CALC_START;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    always @(*) begin
        d_out_0 = d_out_reg[0]; d_out_1 = d_out_reg[1]; d_out_2 = d_out_reg[2]; 
        d_out_3 = d_out_reg[3]; d_out_4 = d_out_reg[4];
    end
endmodule

// ============================================================
//  (5) npu_output_layer
// ============================================================
module npu_output_layer(
    input clk, reset_p,
    input dense_done,
    input signed [27:0] d_in_0, d_in_1, d_in_2, d_in_3, d_in_4,
    output reg [3:0] final_digit,
    output reg result_valid
);
    localparam S_IDLE  = 0, S_FETCH = 1, S_MULT  = 2,
               S_ADD_1 = 3, S_ADD_2 = 4, S_ADD_3 = 5, S_ARGMAX = 6;
    reg [2:0] state;

    reg signed [7:0] w1_rom [0:49];
    reg signed [7:0] b1_rom [0:9];
    initial begin
        $readmemh("55_dense_1_weights.txt", w1_rom);
        $readmemh("55_dense_1_bias.txt",    b1_rom);
    end

    reg [3:0] n_ptr;
    reg signed [43:0] scores [0:9];
    reg signed [43:0] max_score;
    reg signed [7:0]  tw0, tw1, tw2, tw3, tw4;
    reg signed [43:0] p0, p1, p2, p3, p4;
    reg signed [43:0] s01, s23, s4b;
    reg signed [43:0] s03;

    // ★ 안전한 바이어스 스케일링
    wire signed [43:0] ext_b1 = $signed(b1_rom[n_ptr]);

    integer i;
    always @(posedge clk) begin
        if (reset_p) begin
            state <= S_IDLE;
            n_ptr <= 0; final_digit <= 0; result_valid <= 0;
            max_score <= 44'sh80000000000;
            for (i = 0; i < 10; i = i + 1) scores[i] <= 0;
        end else begin
            case (state)
                S_IDLE: begin result_valid <= 0; if (dense_done) state <= S_FETCH; end
                S_FETCH: begin
                    // 파이썬: w_out.reshape(5,10) → raw[i*10+n]
                    // i=입력(0~4), n=출력뉴런(n_ptr)
                    tw0 <= w1_rom[0*10 + n_ptr];
                    tw1 <= w1_rom[1*10 + n_ptr];
                    tw2 <= w1_rom[2*10 + n_ptr];
                    tw3 <= w1_rom[3*10 + n_ptr];
                    tw4 <= w1_rom[4*10 + n_ptr];
                    state <= S_MULT;
                end
                S_MULT: begin
                    p0 <= d_in_0 * tw0; p1 <= d_in_1 * tw1; p2 <= d_in_2 * tw2;
                    p3 <= d_in_3 * tw3; p4 <= d_in_4 * tw4;
                    state <= S_ADD_1;
                end
                S_ADD_1: begin
                    s01 <= p0 + p1; s23 <= p2 + p3;
                    // ★ 변경: (ext_b1 <<< 14) 로 스케일 통일
                    s4b <= p4 + (ext_b1 <<< 14);
                    state <= S_ADD_2;
                end
                S_ADD_2: begin s03 <= s01 + s23; state <= S_ADD_3; end
                S_ADD_3: begin
                    scores[n_ptr] <= s03 + s4b;
                    if (n_ptr == 9) begin n_ptr <= 0; state <= S_ARGMAX; end 
                    else begin n_ptr <= n_ptr + 1; state <= S_FETCH; end
                end
                S_ARGMAX: begin
                    if (scores[n_ptr] > max_score) begin max_score <= scores[n_ptr]; final_digit <= n_ptr; end
                    if (n_ptr == 9) begin
                        n_ptr <= 0; max_score <= 44'sh80000000000;
                        result_valid <= 1; state <= S_IDLE;
                    end else n_ptr <= n_ptr + 1;
                end
            endcase
        end
    end
endmodule

// ============================================================
//  (6) npu_top
// ============================================================
module npu_top(
    input clk, reset_p,
    input start,
    input [7:0] pixel,
    output [9:0] buf_idx,
    output [3:0] final_digit,
    output result_valid
);
    wire calc_busy;
    wire valid_buf;
    wire [7:0] v_00, v_01, v_02, v_03, v_04, v_05, v_06, v_07, v_08;

    wire valid_out_calc;
    wire signed [19:0] conv_0, conv_1, conv_2, conv_3, conv_4;

    wire max_value_valid;
    wire signed [19:0] pool_0, pool_1, pool_2, pool_3, pool_4;

    wire dense_done;
    wire signed [27:0] d_out_0, d_out_1, d_out_2, d_out_3, d_out_4;

    reg signed [19:0] pool_0_r, pool_1_r, pool_2_r, pool_3_r, pool_4_r;
    reg max_valid_r;

    always @(posedge clk) begin
        max_valid_r <= max_value_valid;
        pool_0_r    <= pool_0;
        pool_1_r    <= pool_1;
        pool_2_r    <= pool_2;
        pool_3_r    <= pool_3;
        pool_4_r    <= pool_4;
    end

    npu_conv2d_buf u_buf(
        .clk(clk), .reset_p(reset_p), .start(start), .pixel(pixel),
        .calc_busy(calc_busy), .buf_idx(buf_idx), .valid_buf(valid_buf),
        .value_00(v_00), .value_01(v_01), .value_02(v_02),
        .value_03(v_03), .value_04(v_04), .value_05(v_05),
        .value_06(v_06), .value_07(v_07), .value_08(v_08)
    );
    npu_conv2d_calc u_calc(
        .clk(clk), .reset_p(reset_p), .valid_buf(valid_buf),
        .value_00(v_00), .value_01(v_01), .value_02(v_02),
        .value_03(v_03), .value_04(v_04), .value_05(v_05),
        .value_06(v_06), .value_07(v_07), .value_08(v_08),
        .conv_out_0(conv_0), .conv_out_1(conv_1), .conv_out_2(conv_2),
        .conv_out_3(conv_3), .conv_out_4(conv_4),
        .valid_out_calc(valid_out_calc),
        .busy(calc_busy)
    );
    npu_maxpool_conv2d u_pool(
        .clk(clk), .reset_p(reset_p), .valid_calc(valid_out_calc),
        .conv_out_0(conv_0), .conv_out_1(conv_1), .conv_out_2(conv_2),
        .conv_out_3(conv_3), .conv_out_4(conv_4),
        .max_value_0(pool_0), .max_value_1(pool_1), .max_value_2(pool_2),
        .max_value_3(pool_3), .max_value_4(pool_4),
        .max_value_valid(max_value_valid)
    );
    npu_dense_integrated u_dense(
        .clk(clk), .reset_p(reset_p),
        .max_value_valid(max_valid_r),
        .max_value_0(pool_0_r), .max_value_1(pool_1_r), .max_value_2(pool_2_r),
        .max_value_3(pool_3_r), .max_value_4(pool_4_r),
        .d_out_0(d_out_0), .d_out_1(d_out_1), .d_out_2(d_out_2),
        .d_out_3(d_out_3), .d_out_4(d_out_4),
        .dense_done(dense_done)
    );
    npu_output_layer u_out(
        .clk(clk), .reset_p(reset_p), .dense_done(dense_done),
        .d_in_0(d_out_0), .d_in_1(d_out_1), .d_in_2(d_out_2),
        .d_in_3(d_out_3), .d_in_4(d_out_4),
        .final_digit(final_digit), .result_valid(result_valid)
    );
endmodule