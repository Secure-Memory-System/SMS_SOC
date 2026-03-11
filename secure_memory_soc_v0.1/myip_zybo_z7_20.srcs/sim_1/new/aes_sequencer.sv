`include "uvm_macros.svh"
import uvm_pkg::*;
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 07:53:33 PM
// Design Name: 
// Module Name: aes_sequencer
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


class aes_sequencer extends uvm_sequencer #(aes_seq_item);
    `uvm_component_utils(aes_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass
