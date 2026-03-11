`include "uvm_macros.svh"
import uvm_pkg::*;
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 07:18:43 PM
// Design Name: 
// Module Name: aes_env
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


class aes_env extends uvm_env;
    `uvm_component_utils(aes_env)

    aes_agent      agent;
    aes_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = aes_agent::type_id::create("agent", this);
        scoreboard = aes_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        // 모니터 출력 → 스코어보드 입력 연결
        agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction
endclass
