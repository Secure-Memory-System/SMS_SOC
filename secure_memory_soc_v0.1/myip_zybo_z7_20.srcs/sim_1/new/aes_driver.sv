`include "uvm_macros.svh"
import uvm_pkg::*;
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 07:09:03 PM
// Design Name: 
// Module Name: aes_driver
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


class aes_driver extends uvm_driver #(aes_seq_item);
    `uvm_component_utils(aes_driver)

    virtual aes_if.driver_mp vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual aes_if)::get(
            this, "", "aes_vif", vif))
            `uvm_fatal("NOVIF", "aes_if not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        aes_seq_item item;
        // 초기화
        vif.driver_cb.enc_start <= 0;
        vif.driver_cb.dec_start <= 0;

        forever begin
            seq_item_port.get_next_item(item);
            drive_enc(item);   // 암호화 구동
            drive_dec(item);   // 복호화 구동
            seq_item_port.item_done();
        end
    endtask

    // 암호화 구동
    task drive_enc(aes_seq_item item);
        // 키와 평문 설정
        vif.driver_cb.key      <= item.key;
        vif.driver_cb.data_in  <= item.plaintext;
        @(vif.driver_cb);

        // start 1클럭 펄스
        vif.driver_cb.enc_start <= 1;
        @(vif.driver_cb);
        vif.driver_cb.enc_start <= 0;

        // done 대기
        wait(vif.enc_done === 1);
        @(vif.driver_cb);

        // 암호문 저장
        item.ciphertext = vif.monitor_cb.enc_data_out;
        `uvm_info("DRV", $sformatf("ENC done: %h → %h",
            item.plaintext, item.ciphertext), UVM_MEDIUM)
    endtask

    // 복호화 구동
    task drive_dec(aes_seq_item item);
        // 암호화 결과를 그대로 입력
        vif.driver_cb.data_in  <= item.ciphertext;
        @(vif.driver_cb);

        vif.driver_cb.dec_start <= 1;
        @(vif.driver_cb);
        vif.driver_cb.dec_start <= 0;

        wait(vif.dec_done === 1);
        @(vif.driver_cb);

        item.decrypted = vif.monitor_cb.dec_data_out;
        `uvm_info("DRV", $sformatf("DEC done: %h → %h",
            item.ciphertext, item.decrypted), UVM_MEDIUM)
    endtask
endclass
