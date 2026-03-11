`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 02:47:01 PM
// Design Name: 
// Module Name: aes_interface
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


interface aes_interface(input logic clk, reset_n);
    // 암호화 신호 및 데이터
    logic [127:0] key;
    logic [127:0] data_in;
    logic         enc_start;
    logic [127:0] enc_data_out;
    logic         enc_done;
    
    // 복호화 신호 및 데이터
    logic         dec_start;
    logic [127:0] dec_data_out;
    logic         dec_done;
    
    clocking driver_cb @(posedge clk);
        default input #1 output #1;
        output key, data_in, enc_start, dec_start;
        input enc_done, enc_data_out;
        input dec_done, dec_data_out;
    endclocking
    
    clocking monitor_cb @(posedge clk);
        default input #1;
        input key, data_in, enc_start, dec_start;
        input enc_done, enc_data_out;
        input dec_done, dec_data_out;
    endclocking
    
    modport driver_mp  (clocking driver_cb,  input clk, reset_n);
    modport monitor_mp (clocking monitor_cb, input clk, reset_n);
endinterface











