`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: npu_v3_top
//
// [v3 통합]
//   npu_v2_top 기반 + pixel_en 인터페이스 유지
//   calc_busy 제거 (conv2d_calc의 busy 포트 제거에 따라)
//////////////////////////////////////////////////////////////////////////////////
module npu_v2_top(
    input clk, reset_p,
    input start,
    input [7:0] pixel,
    input pixel_en,                     // [npu_v2] 외부 인에이블 인터페이스
    output [9:0] buf_idx,
    output [3:0] final_digit,
    output result_valid
);

    // Buffer -> Calc 연결
    wire valid_buf;
    wire [7:0] v_00, v_01, v_02, v_03, v_04, v_05, v_06, v_07, v_08;

    // Calc -> MaxPool 연결
    wire valid_out_calc;
    wire signed [19:0] conv_0, conv_1, conv_2, conv_3, conv_4;

    // MaxPool -> Dense 연결
    wire max_value_valid;
    wire signed [19:0] pool_0, pool_1, pool_2, pool_3, pool_4;

    // Dense -> Output 연결
    wire dense_done;
    wire signed [19:0] d_out_0, d_out_1, d_out_2, d_out_3, d_out_4;

    // (1) 이미지 버퍼 및 3x3 윈도우 추출
    npu_conv2d_buf u_buf(
        .clk(clk), .reset_p(reset_p),
        .start(start), .pixel(pixel),
        .pixel_en(pixel_en),            // [npu_v2] 외부 인에이블
        .buf_idx(buf_idx),
        .valid_buf(valid_buf),
        .value_00(v_00), .value_01(v_01), .value_02(v_02),
        .value_03(v_03), .value_04(v_04), .value_05(v_05),
        .value_06(v_06), .value_07(v_07), .value_08(v_08)
    );

    // (2) Conv2D + ReLU 연산 (5개 필터)
    //     [수정] busy 포트 제거됨
    npu_conv2d_calc u_calc(
        .clk(clk), .reset_p(reset_p),
        .valid_buf(valid_buf),
        .value_00(v_00), .value_01(v_01), .value_02(v_02),
        .value_03(v_03), .value_04(v_04), .value_05(v_05),
        .value_06(v_06), .value_07(v_07), .value_08(v_08),
        .conv_out_0(conv_0), .conv_out_1(conv_1), .conv_out_2(conv_2),
        .conv_out_3(conv_3), .conv_out_4(conv_4),
        .valid_out_calc(valid_out_calc)
    );

    // (3) MaxPooling (26x26 → 13x13)
    npu_maxpool_conv2d u_pool(
        .clk(clk), .reset_p(reset_p),
        .valid_calc(valid_out_calc),
        .conv_out_0(conv_0), .conv_out_1(conv_1), .conv_out_2(conv_2),
        .conv_out_3(conv_3), .conv_out_4(conv_4),
        .max_value_0(pool_0), .max_value_1(pool_1), .max_value_2(pool_2),
        .max_value_3(pool_3), .max_value_4(pool_4),
        .max_value_valid(max_value_valid)
    );

    // (4) Flatten + Dense 통합 레이어 (뉴런 5개)
    npu_dense_integrated u_dense(
        .clk(clk), .reset_p(reset_p),
        .max_value_valid(max_value_valid),
        .max_value_0(pool_0), .max_value_1(pool_1), .max_value_2(pool_2),
        .max_value_3(pool_3), .max_value_4(pool_4),
        .d_out_0(d_out_0), .d_out_1(d_out_1), .d_out_2(d_out_2),
        .d_out_3(d_out_3), .d_out_4(d_out_4),
        .dense_done(dense_done)
    );

    // (5) Output 레이어 + Argmax
    npu_output_layer u_out(
        .clk(clk), .reset_p(reset_p),
        .dense_done(dense_done),
        .d_in_0(d_out_0), .d_in_1(d_out_1), .d_in_2(d_out_2),
        .d_in_3(d_out_3), .d_in_4(d_out_4),
        .final_digit(final_digit),
        .result_valid(result_valid)
    );

endmodule