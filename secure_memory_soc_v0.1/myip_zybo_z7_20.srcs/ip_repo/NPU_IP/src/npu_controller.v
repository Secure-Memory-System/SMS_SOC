`timescale 1ns / 1ps

module npu_controller (
    input clk,  
    input reset_p,
    
    // 1. 제어 및 상태 신호
    input start,              
    input [15:0] reg_img_w,   
    input [15:0] reg_img_h,   
    input reg_pad_en,         
    
    // 2. 데이터 흐름 신호
    input pixel_valid,        
    
    // 3. 내부 제어 신호
    output reg [15:0] x_cnt,  
    output reg [15:0] y_cnt,  
    output reg pad_ctrl,      
    output wire done_tick     // reg에서 wire로 변경하여 타이밍 직관성 확보
);

    // 상태 머신 정의
    localparam IDLE = 2'b00;
    localparam RUN  = 2'b01;
    localparam DONE = 2'b10;
    reg [1:0] state, next_state;

    // [Part 1] 상태 전이 로직
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) state <= IDLE;
        else         state <= next_state;
    end

    // [Part 2] 다음 상태 결정 (Combinational)
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: if (start) next_state = RUN;
            RUN:  begin
                // 마지막 픽셀(W-1, H-1)이 유효하게 들어오는 순간 DONE으로 전이
                if ((x_cnt == reg_img_w - 1) && (y_cnt == reg_img_h - 1) && pixel_valid) 
                    next_state = DONE;
            end
            DONE: next_state = IDLE; // 1클럭 동안 DONE 유지 후 IDLE 복귀
            default: next_state = IDLE;
        endcase
    end

    // [Part 3] 좌표 및 패딩 제어 (Sequential)
    wire is_border = (x_cnt == 0 || x_cnt == reg_img_w - 1 || 
                      y_cnt == 0 || y_cnt == reg_img_h - 1);

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            x_cnt <= 0;
            y_cnt <= 0;
            pad_ctrl <= 0;
        end 
        else begin
            case (state)
                IDLE: begin
                    x_cnt <= 0;
                    y_cnt <= 0;
                    pad_ctrl <= 0;
                end
                RUN: begin
                    if (pixel_valid) begin
                        if (x_cnt == reg_img_w - 1) begin
                            x_cnt <= 0;
                            if (y_cnt == reg_img_h - 1) y_cnt <= 0;
                            else y_cnt <= y_cnt + 1;
                        end 
                        else begin
                            x_cnt <= x_cnt + 1;
                        end
                    end
                    pad_ctrl <= reg_pad_en & is_border;
                end
                default: pad_ctrl <= 0;
            endcase
        end
    end

    // [Part 4] Done Tick 출력: 상태가 DONE인 1클럭 동안 High 유지
    assign done_tick = (state == DONE);

endmodule