`timescale 1ns / 1ps

module npu_top (
    input clk,
    input reset_p,
    
    // 1. 설정값들
    input start,
    input reg_pad_en,
    input [15:0] reg_img_w,
    input [15:0] reg_img_h,
    
    // 2. 외부 데이터 (DMA로부터 Stream 수신)
    input [7:0] pixel_in,
    input pixel_valid,
    
    // 3. 최종 출력 (0~9 판별 결과)
    output [3:0] final_digit,     // 최종 결과값 (4비트)
    output final_valid,           // 최종 결과 유효 신호
    output done_tick              // 프레임 데이터 입력 완료
);

    // 내부 배선 신호
    wire [15:0] x_cnt, y_cnt;
    wire pad_ctrl;
    wire buf_valid;
    wire [7:0] win_00, win_01, win_02, win_10, win_11, win_12, win_20, win_21, win_22;
    wire [71:0] pe_in_data_flat;
    
    wire signed [23:0] pe_out [0:4];   // 필터 5개 출력
    wire               pe_valid [0:4]; // 필터 5개 valid
    
    wire signed [23:0] pool_out [0:4];   // 풀링 5채널 출력
    wire               pool_valid [0:4]; // 풀링 5채널 valid

    // 컨볼루션 이후 이미지 너비 계산 (3x3 Valid Padding 기준)
    wire [15:0] conv_out_w = reg_img_w - 16'd2;
    
    // wire 선언 추가
    wire signed [119:0] pool_out_flat;   // 24bit × 5 = 120bit
    wire        [4:0]   pool_valid_flat; // 1bit  × 5 = 5bit
    
    // assign으로 묶기
    assign pool_out_flat   = {pool_out[4], pool_out[3], pool_out[2], 
                              pool_out[1], pool_out[0]};
    assign pool_valid_flat = {pool_valid[4], pool_valid[3], pool_valid[2], 
                              pool_valid[1], pool_valid[0]};

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
    genvar i;
    generate
        for (i = 0; i < 5; i = i + 1) begin : conv_filter
            conv_pe #(.FILTER_ID(i)) u_pe (       // ← 모듈명도 변경
                .clk(clk),
                .reset_p(reset_p),
                .in_data(pe_in_data_flat),
                .valid_in(buf_valid),
                .pe_out(pe_out[i]),
                .valid_out(pe_valid[i])
            );
        end
    endgenerate

    // [4] Max Pooling
    generate
        for (i = 0; i < 5; i = i + 1) begin : pooling
            max_pooling #(.MAX_WIDTH(26)) u_pool (
                .clk(clk),
                .reset_p(reset_p),
                .data_in(pe_out[i]),
                .valid_in(pe_valid[i]),
                .reg_img_w(conv_out_w),
                .data_out(pool_out[i]),
                .valid_out(pool_valid[i])
            );
        end
    endgenerate
    
    flatten_dense u_fc (
        .clk           (clk),
        .reset_p       (reset_p),
        .pool_data_in  (pool_out_flat),    // ✅ 5채널 묶음
        .pool_valid_in (pool_valid_flat),  // ✅ 5채널 valid 묶음
        .final_digit   (final_digit),
        .final_valid   (final_valid)
    );

endmodule