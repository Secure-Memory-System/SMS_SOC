`timescale 1ns / 1ps

module npu_v2_top(
    input clk, reset_p,
    input start,
    input pixel_en,
    input [7:0] pixel,
    output [9:0] buf_idx,
    output [3:0] final_digit,
    output result_valid,
    output wire pixel_ready  // [추가됨] Wrapper로 전달할 Ready 신호
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
        .pixel_en(pixel_en),
        .calc_busy(calc_busy), .buf_idx(buf_idx), .valid_buf(valid_buf),
        .value_00(v_00), .value_01(v_01), .value_02(v_02),
        .value_03(v_03), .value_04(v_04), .value_05(v_05),
        .value_06(v_06), .value_07(v_07), .value_08(v_08),
        .pixel_ready(pixel_ready)  // [추가됨] 신호 연결
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