`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/07 17:13:23
// Design Name: 
// Module Name: max_pooling
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module max_pooling #(
    parameter DATA_WIDTH = 24,
    parameter MAX_WIDTH = 1024
)(
    input clk,
    input reset_p,
    input signed [DATA_WIDTH-1:0] data_in,
    input valid_in,
    input [15:0] reg_img_w,

    output reg signed [DATA_WIDTH-1:0] data_out,
    output reg valid_out
);

    // 1. 변수 선언은 반드시 always 블록 외부에서!
    reg [15:0] x_cnt, y_cnt;
    reg signed [DATA_WIDTH-1:0] prev_pixel;
    reg signed [DATA_WIDTH-1:0] line_buf [0:(MAX_WIDTH/2)-1]; 
    
    // 중간 계산용 변수는 always 블록 안에서 쓸 경우 reg로 선언합니다.
    reg signed [DATA_WIDTH-1:0] current_row_max;
    reg signed [DATA_WIDTH-1:0] top_row_max;

    // 2. 좌표 관리 로직
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            x_cnt <= 0;
            y_cnt <= 0;
        end else if (valid_in) begin
            if (x_cnt == reg_img_w - 1) begin
                x_cnt <= 0;
                y_cnt <= y_cnt + 1;
            end else begin
                x_cnt <= x_cnt + 1;
            end
        end
    end

    // 3. 연산 로직 (내부에서 wire/assign 제거)
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            data_out <= 0;
            valid_out <= 0;
            prev_pixel <= 0;
            current_row_max <= 0;
            top_row_max <= 0;
        end else if (valid_in) begin
            // 짝수 줄 (0, 2, 4...)
            if (y_cnt[0] == 1'b0) begin
                valid_out <= 1'b0;
                if (x_cnt[0] == 1'b1) begin
                    // 이전 픽셀과 현재 픽셀 비교 후 버퍼 저장
                    line_buf[x_cnt >> 1] <= (data_in > prev_pixel) ? data_in : prev_pixel;
                end else begin
                    prev_pixel <= data_in;
                end
            end 
            // 홀수 줄 (1, 3, 5...)
            else begin
                if (x_cnt[0] == 1'b1) begin
                    // 현재 줄의 가로 최댓값 계산
                    current_row_max = (data_in > prev_pixel) ? data_in : prev_pixel;
                    // 이전 줄에서 저장해둔 값 가져오기
                    top_row_max = line_buf[x_cnt >> 1];
                    
                    // 최종 비교 결과 출력
                    data_out <= (current_row_max > top_row_max) ? current_row_max : top_row_max;
                    valid_out <= 1'b1;
                end else begin
                    prev_pixel <= data_in;
                    valid_out <= 1'b0;
                end
            end
        end else begin
            valid_out <= 1'b0;
        end
    end
endmodule