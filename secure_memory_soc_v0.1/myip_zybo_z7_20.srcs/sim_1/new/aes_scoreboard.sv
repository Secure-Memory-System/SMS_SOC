`include "uvm_macros.svh"
import uvm_pkg::*;  
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 07:17:41 PM
// Design Name: 
// Module Name: aes_scoreboard
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


class aes_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(aes_scoreboard)

    uvm_analysis_imp #(aes_seq_item, aes_scoreboard) analysis_export;

    int pass_count = 0;
    int fail_count = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_export = new("analysis_export", this);
    endfunction

    // 모니터에서 트랜잭션 수신 시 자동 호출
    function void write(aes_seq_item item);
        if (item.plaintext === item.decrypted) begin
            pass_count++;
            `uvm_info("SCB", $sformatf(
                "✅ PASS [%0d] plaintext=%h decrypted=%h",
                pass_count, item.plaintext, item.decrypted), UVM_LOW)
        end else begin
            fail_count++;
            `uvm_error("SCB", $sformatf(
                "❌ FAIL plaintext=%h decrypted=%h",
                item.plaintext, item.decrypted))
        end
    endfunction

    // 시뮬레이션 종료 시 통계 출력
    function void report_phase(uvm_phase phase);
        `uvm_info("SCB", $sformatf(
            "\n========== 최종 결과 ==========\n  PASS: %0d\n  FAIL: %0d\n================================",
            pass_count, fail_count), UVM_NONE)
    endfunction
endclass
