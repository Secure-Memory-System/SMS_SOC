`timescale 1ns / 1ps

module universal_pe #(
    parameter DATA_WIDTH = 8,
    parameter KERNEL_SIZE = 9
)(
    input clk, 
    input reset_p,
    input [(DATA_WIDTH*KERNEL_SIZE)-1:0] in_data,  
    input [(DATA_WIDTH*KERNEL_SIZE)-1:0] weight_in, 
    input signed [15:0] bias_in,
    input valid_in,
    
    output reg signed [23:0] pe_out,
    output reg valid_out
);
    // 1. 내부 신호 선언 (모듈 최상단에 두는 것이 안전함)
    wire [DATA_WIDTH-1:0] data_arr [0:KERNEL_SIZE-1];
    wire signed [DATA_WIDTH-1:0] weight_arr [0:KERNEL_SIZE-1];
    reg signed [23:0] sum;
    integer i;

    // 2. 데이터 쪼개기 (Generate block)
    genvar g;
    generate
        for (g = 0; g < KERNEL_SIZE; g = g + 1) begin : unpack
            assign data_arr[g]   = in_data[g*DATA_WIDTH +: DATA_WIDTH];
            assign weight_arr[g] = weight_in[g*DATA_WIDTH +: DATA_WIDTH];
        end
    endgenerate // <--- 이 부분이 'endgenerate'여야 합니다!

    // 3. 연산 로직 (Sequential block)
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            pe_out <= 0;
            valid_out <= 0;
        end else if (valid_in) begin
            // MAC 연산
            sum = bias_in; 
            for (i = 0; i < KERNEL_SIZE; i = i + 1) begin
                sum = sum + ($signed({1'b0, data_arr[i]}) * weight_arr[i]);
            end
            
            // ReLU
            if (sum < 0) pe_out <= 24'd0;
            else         pe_out <= sum;
            
            valid_out <= 1'b1;
        end else begin
            valid_out <= 1'b0;
        end
    end

endmodule