`timescale 1ns / 1ps

module fnd_cntr(
    input clk, reset_p,
    input [3:0] digit_value,
    output [7:0] seg,
    output reg[3:0] com);
    
    reg [16:0] clk_div;
    always @(posedge clk)clk_div = clk_div + 1;
    
    wire clk_div_ed;
    edge_detector_n ed_com(.clk(clk), .reset_p(reset_p), .cp(clk_div[16]), .p_edge(clk_div_ed));
    
    always @(posedge clk, posedge reset_p) begin
        if(reset_p)com = 4'b1110;
        else if (clk_div_ed) begin
            if(com[0] + com[1] + com[2] + com[3] != 3) com = 4'b1110;
            else com = {com[2:0], com[3]};
        end
    end

    seg_decoder dec(.hex_value(digit_value),.seg(seg));
    
endmodule 

