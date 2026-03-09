`timescale 1ns / 1ps

module npu_top (
    input clk,
    input reset_p,
    
    // 1. 설정값들
    input start,
    input [15:0] reg_img_w,
    input [15:0] reg_img_h,
    input reg_pad_en,
    input [7:0] weight_in_0, weight_in_1, weight_in_2,
    input [7:0] weight_in_3, weight_in_4, weight_in_5,
    input [7:0] weight_in_6, weight_in_7, weight_in_8,  
    input signed [15:0] bias_in,
    
    // 2. 외부 데이터 (DMA로부터 Stream 수신)
    input [7:0] pixel_in,
    input pixel_valid,
    
    // 3. 최종 출력 (0~9 판별 결과)
    output [3:0] final_digit,     // 최종 결과값 (4비트)
    output final_valid,           // 최종 결과 유효 신호
    output done_tick              // 프레임 데이터 입력 완료
);

    // 내부 배선 신호
    wire [71:0] weight_flat;
    wire [15:0] x_cnt, y_cnt;
    wire pad_ctrl;
    wire buf_valid;
    wire [7:0] win_00, win_01, win_02, win_10, win_11, win_12, win_20, win_21, win_22;
    wire [71:0] pe_in_data_flat;
    
    // 모듈 간 연결을 위한 내부 wire
    wire signed [23:0] pe_out_internal;
    wire pe_out_valid_internal;
    wire signed [23:0] pool_out_internal;
    wire pool_out_valid_internal;

    // 컨볼루션 이후 이미지 너비 계산 (3x3 Valid Padding 기준)
    wire [15:0] conv_out_w = reg_img_w - 16'd2;

    assign weight_flat = {weight_in_8, weight_in_7, weight_in_6, 
                          weight_in_5, weight_in_4, weight_in_3, 
                          weight_in_2, weight_in_1, weight_in_0};

    assign pe_in_data_flat = {win_22, win_21, win_20, win_12, win_11, win_10, win_02, win_01, win_00};

    // [1] 컨트롤러
    npu_controller u_ctrl (
        .clk(clk), .reset_p(reset_p), .start(start),
        .reg_img_w(reg_img_w), .reg_img_h(reg_img_h), .reg_pad_en(reg_pad_en),
        .pixel_valid(pixel_valid), .x_cnt(x_cnt), .y_cnt(y_cnt),
        .pad_ctrl(pad_ctrl), .done_tick(done_tick)
    );

    // [2] 라인 버퍼
    line_buffer u_buf (
        .clk(clk), .reset_p(reset_p), .reg_img_w(reg_img_w),
        .pixel_in(pixel_in), .pixel_valid(pixel_valid), .pad_ctrl(pad_ctrl),
        .win_00(win_00), .win_01(win_01), .win_02(win_02),
        .win_10(win_10), .win_11(win_11), .win_12(win_12),
        .win_20(win_20), .win_21(win_21), .win_22(win_22),
        .valid_out(buf_valid)
    );

    // [3] 유니버설 PE
    universal_pe u_pe (
        .clk(clk), .reset_p(reset_p),
        .in_data(pe_in_data_flat), .weight_in(weight_flat), .bias_in(bias_in),
        .valid_in(buf_valid),
        .pe_out(pe_out_internal),           
        .valid_out(pe_out_valid_internal)   
    );

    // [4] Max Pooling
    max_pooling u_pool (
        .clk(clk), .reset_p(reset_p),
        .data_in(pe_out_internal),
        .valid_in(pe_out_valid_internal),
        .reg_img_w(conv_out_w),             
        .data_out(pool_out_internal),       // Flatten으로 보낼 wire 연결
        .valid_out(pool_out_valid_internal) // Flatten으로 보낼 wire 연결
    );

    // [5] Flatten & Dense 
    flatten_dense u_fc (
        .clk(clk),
        .reset_p(reset_p),
        .pool_data_in(pool_out_internal),
        .pool_valid_in(pool_out_valid_internal),
        .final_digit(final_digit),    // Top의 최종 출력 포트로 연결
        .final_valid(final_valid)     // Top의 최종 출력 포트로 연결
    );

endmodule