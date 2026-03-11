`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/10 12:54:43
// Design Name: 
// Module Name: fnd_sub_module
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


module edge_detector_n(
    input clk, reset_p,
    input cp,
    output p_edge, n_edge);
    
    reg ff_cur, ff_old;
    always @(posedge clk, posedge reset_p) begin
        if(reset_p)begin
            ff_cur = 0;
            ff_old = 0;
        end
        else begin
            ff_cur = ff_old;
            ff_old = cp;
        end
    end
    
    assign p_edge = ({ff_cur, ff_old} == 2'b10) ? 1 : 0;
    assign n_edge = ({ff_cur, ff_old} == 2'b01) ? 1 : 0;
    
endmodule

module seg_decoder(
    input [3:0]hex_value,
    output reg[7:0]seg);
    
    always @(hex_value)begin
        case(hex_value)
            //             pgfe_dcba
            4'd0: seg = 8'b1100_0000;
            4'd1: seg = 8'b1111_1001;
            4'd2: seg = 8'b1010_0100;
            4'd3: seg = 8'b1011_0000;
            4'd4: seg = 8'b1001_1001;
            4'd5: seg = 8'b1001_0010;
            4'd6: seg = 8'b1000_0010;
            4'd7: seg = 8'b1111_1000;
            4'd8: seg = 8'b1000_0000;
            4'd9: seg = 8'b1001_1000;
            
            4'd10: seg = 8'b1000_1000; // A
            4'd11: seg = 8'b1000_0011; // B
            4'd12: seg = 8'b1100_0110; // C
            4'd13: seg = 8'b1010_0001; // D
            4'd14: seg = 8'b1000_0110; // E
            4'd15: seg = 8'b1000_1110; // F
        endcase
    end
endmodule
