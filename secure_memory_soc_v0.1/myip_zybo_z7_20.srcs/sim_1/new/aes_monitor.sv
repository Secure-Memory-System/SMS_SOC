//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 07:12:05 PM
// Design Name: 
// Module Name: aes_monitor
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


class aes_monitor extends uvm_monitor;
    `uvm_component_utils(aes_monitor)

    virtual aes_if.monitor_mp vif;

    // 스코어보드로 결과 전달하는 포트
    uvm_analysis_port #(aes_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual aes_if)::get(
            this, "", "aes_vif", vif))
            `uvm_fatal("NOVIF", "aes_if not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        aes_seq_item item;
        forever begin
            // dec_done 신호 대기
            @(posedge vif.clk);
            if (vif.monitor_cb.dec_done) begin
                item = aes_seq_item::type_id::create("mon_item");
                item.key        = vif.monitor_cb.key;
                item.plaintext  = vif.monitor_cb.data_in;
                item.ciphertext = vif.monitor_cb.enc_data_out;
                item.decrypted  = vif.monitor_cb.dec_data_out;
                ap.write(item);  // 스코어보드로 전송
            end
        end
    endtask
endclass
