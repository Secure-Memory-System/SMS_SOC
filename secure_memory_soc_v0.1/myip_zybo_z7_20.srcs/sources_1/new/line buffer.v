`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/07 15:53:24
// Design Name: 
// Module Name: line buffer
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


module line_buffer #(
parameter MAX_WIDTH = 1920 // 최대 허용 가로 크기
)(
    input clk,
    input reset_p,
    input [15:0] reg_img_w,   // CPU에서 설정한 실제 이미지 가로 크기
    input [7:0] pixel_in,
    input pixel_valid,
    input pad_ctrl,

    output reg [7:0] win_00, win_01, win_02,
    output reg [7:0] win_10, win_11, win_12,
    output reg [7:0] win_20, win_21, win_22,
    output reg valid_out
);

    // 1. 라인 버퍼 메모리 (SRAM/BRAM 유도를 위해 배열 사용)
    reg [7:0] line_buf_0 [0:MAX_WIDTH-1]; 
    reg [7:0] line_buf_1 [0:MAX_WIDTH-1]; 
    
    reg [15:0] ptr;     
    reg [1:0]  row_cnt; 

    // 내부 윈도우 레지스터 (초기화 추가)
    reg [7:0] raw_win_00, raw_win_01, raw_win_02;
    reg [7:0] raw_win_10, raw_win_11, raw_win_12;
    reg [7:0] raw_win_20, raw_win_21, raw_win_22;

    // 2. 버퍼 제어 로직
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            ptr <= 0;
            row_cnt <= 0;
            valid_out <= 0;
            {raw_win_00, raw_win_01, raw_win_02} <= 0;
            {raw_win_10, raw_win_11, raw_win_12} <= 0;
            {raw_win_20, raw_win_21, raw_win_22} <= 0;
        end 
        else if (pixel_valid) begin
            // 포인터 제어: parameter(WIDTH) 대신 입력받은(reg_img_w) 사용
            if (ptr == reg_img_w - 1) begin
                ptr <= 0;
                if (row_cnt < 2) row_cnt <= row_cnt + 1;
            end else begin
                ptr <= ptr + 1;
            end

            // [중요] 메모리 읽기와 윈도우 업데이트 타이밍
            // 메모리에서 읽은 값은 다음 클럭에 raw_win에 반영됨
            raw_win_02 <= line_buf_0[ptr];
            raw_win_12 <= line_buf_1[ptr];
            raw_win_22 <= pixel_in;

            // 기존 데이터 Shift
            raw_win_01 <= raw_win_02; raw_win_00 <= raw_win_01;
            raw_win_11 <= raw_win_12; raw_win_10 <= raw_win_11;
            raw_win_21 <= raw_win_22; raw_win_20 <= raw_win_21;

            // 메모리 업데이트: 읽은 후 현재 위치에 새 데이터 쓰기
            line_buf_0[ptr] <= line_buf_1[ptr];
            line_buf_1[ptr] <= pixel_in;

            // 유효 신호 생성 (3x3이 완전히 채워지는 타이밍 계산)
            if (row_cnt >= 2 && ptr >= 2) valid_out <= 1;
            else                          valid_out <= 0;
        end 
        else begin
            valid_out <= 0;
        end
    end

    // 3. 패딩 적용 (조합 회로)
    always @(*) begin
        if (pad_ctrl) begin
            {win_00, win_01, win_02} = 24'd0;
            {win_10, win_11, win_12} = 24'd0;
            {win_20, win_21, win_22} = 24'd0;
        end else begin
            win_00 = raw_win_00; win_01 = raw_win_01; win_02 = raw_win_02;
            win_10 = raw_win_10; win_11 = raw_win_11; win_12 = raw_win_12;
            win_20 = raw_win_20; win_21 = raw_win_21; win_22 = raw_win_22;
        end
    end

endmodule
