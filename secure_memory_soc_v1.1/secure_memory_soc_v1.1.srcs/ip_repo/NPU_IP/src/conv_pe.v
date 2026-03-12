`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/11/2026 11:40:31 AM
// Design Name: 
// Module Name: conv_pe
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

module conv_pe #(
    parameter FILTER_ID = 0
)(
    input              clk,
    input              reset_p,
    input      [71:0]  in_data,    // 8bit × 9개 픽셀
    input              valid_in,
    output reg signed [23:0] pe_out,   // MAC 결과
    output reg         valid_out
);

    wire [7:0] pixel [0:8];
    genvar j;
    generate
        for(j = 0; j < 9; j = j + 1) begin
            assign pixel[j] = in_data[j*8 +: 8];
        end
    endgenerate
    
    wire [7:0] weight [0:8];
    genvar k;
    generate
        for(k = 0; k < 9; k = k + 1) begin
            conv_weight_rom#(.FILTER_ID(FILTER_ID)) u_rom(.addr(k[3:0]), .data(weight[k]));
        end
    endgenerate
    
    reg signed [7:0] bias_mem [0:4];
    initial $readmemh("conv2d_bias.txt", bias_mem);
    wire signed [7:0] bias = bias_mem[FILTER_ID];
    
    // 부호 확장 주의!
    // pixel   → unsigned 8bit → {1'b0, pixel} 로 9bit signed
    // weight  → signed   8bit → $signed(weight) 그대로

    wire signed [20:0] mac;
    assign mac =
        $signed({1'b0, pixel[0]}) * $signed(weight[0]) +
        $signed({1'b0, pixel[1]}) * $signed(weight[1]) +
        $signed({1'b0, pixel[2]}) * $signed(weight[2]) +
        $signed({1'b0, pixel[3]}) * $signed(weight[3]) +
        $signed({1'b0, pixel[4]}) * $signed(weight[4]) +
        $signed({1'b0, pixel[5]}) * $signed(weight[5]) +
        $signed({1'b0, pixel[6]}) * $signed(weight[6]) +
        $signed({1'b0, pixel[7]}) * $signed(weight[7]) +
        $signed({1'b0, pixel[8]}) * $signed(weight[8]);
    
    // 바이어스 더하기 (부호 확장 후 합산)
    wire signed [23:0] mac_with_bias;
    assign mac_with_bias = {{3{mac[20]}}, mac} + {{16{bias[7]}}, bias};
                           
    always @(posedge clk) begin
        if (reset_p) begin
            pe_out    <= 0;
            valid_out <= 0;
        end else begin
            pe_out    <= mac_with_bias;
            valid_out <= valid_in;
        end
    end

endmodule















