`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 07:23:49 PM
// Design Name: 
// Module Name: aes_if
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


interface aes_if(input logic clk, reset_n);
    // 암호화 코어 신호
    logic [127:0] key;
    logic [127:0] data_in;
    logic         enc_start;
    logic [127:0] enc_data_out;
    logic         enc_done;

    // 복호화 코어 신호
    logic         dec_start;
    logic [127:0] dec_data_out;
    logic         dec_done;

    // 드라이버가 구동하는 방향 정의
    clocking driver_cb @(posedge clk);
        default input #1 output #1;
        output key, data_in, enc_start, dec_start;
        input  enc_done, enc_data_out;
        input  dec_done, dec_data_out;
    endclocking

    // 모니터가 감시하는 방향 정의
    clocking monitor_cb @(posedge clk);
        default input #1;
        input key, data_in, enc_start, dec_start;
        input enc_done, enc_data_out;
        input dec_done, dec_data_out;
    endclocking

    modport driver_mp  (clocking driver_cb,  input clk, reset_n);
    modport monitor_mp (clocking monitor_cb, input clk, reset_n);
endinterface
