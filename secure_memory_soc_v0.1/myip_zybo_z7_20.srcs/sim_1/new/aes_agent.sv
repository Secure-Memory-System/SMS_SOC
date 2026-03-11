`include "uvm_macros.svh"
import uvm_pkg::*;
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 07:52:43 PM
// Design Name: 
// Module Name: aes_agent
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

class aes_agent extends uvm_agent;
    `uvm_component_utils(aes_agent)

    // agent가 가지는 3가지 컴포넌트
    aes_sequencer sequencer;
    aes_driver    driver;
    aes_monitor   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = aes_sequencer::type_id::create("sequencer", this);
        driver    = aes_driver::type_id::create("driver",    this);
        monitor   = aes_monitor::type_id::create("monitor",  this);
    endfunction

    function void connect_phase(uvm_phase phase);
        // driver의 seq_item_port를 sequencer의 seq_item_export에 연결
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass
