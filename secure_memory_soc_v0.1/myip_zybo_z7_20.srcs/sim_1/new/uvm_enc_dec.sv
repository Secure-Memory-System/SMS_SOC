`timescale 1ns / 1ps
`include "uvm_macros.svh"
import uvm_pkg::*;
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 02:35:45 PM
// Design Name: 
// Module Name: uvm_enc_dec
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

`include "aes_seq_item.sv"
`include "aes_sequence.sv"
`include "aes_sequencer.sv"
`include "aes_driver.sv"
`include "aes_monitor.sv"
`include "aes_scoreboard.sv"
`include "aes_agent.sv"
`include "aes_env.sv"
`include "aes_test.sv" 


module tb_top;
    logic clk;
    logic reset_n;

    aes_if dut_if(.clk(clk), .reset_n(reset_n));

    aes_128_core u_enc (
        .clk      (clk),
        .reset_n  (reset_n),
        .key      (dut_if.key),
        .data_in  (dut_if.data_in),
        .start    (dut_if.enc_start),
        .data_out (dut_if.enc_data_out),
        .done     (dut_if.enc_done)
    );

    aes_128_inv_core u_dec (
        .clk      (clk),
        .reset_n  (reset_n),
        .key      (dut_if.key),
        .data_in  (dut_if.enc_data_out),
        .start    (dut_if.dec_start),
        .data_out (dut_if.dec_data_out),
        .done     (dut_if.dec_done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        reset_n = 0;
        #20 reset_n = 1;
    end

    initial begin
        uvm_config_db #(virtual aes_if)::set(
            null, "uvm_test_top.*", "aes_vif", dut_if);
        run_test("aes_digit_test");
    end
endmodule
