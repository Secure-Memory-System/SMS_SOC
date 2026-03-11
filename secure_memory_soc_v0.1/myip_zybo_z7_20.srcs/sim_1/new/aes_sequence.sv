`include "uvm_macros.svh"
import uvm_pkg::*;
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 04:00:02 PM
// Design Name: 
// Module Name: aes_sequence
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


class aes_base_seq extends uvm_sequence #(aes_seq_item);
    `uvm_object_utils(aes_base_seq) // class 등록
    
    function new(string name = "aes_base_seq");
        super.new(name);
    endfunction
    
    task body();
        aes_seq_item item;
        
        item = aes_seq_item::type_id::create("item");
        start_item(item);
        assert(item.randomize() with {key == 128'h2b7e151628aed2a6abf7158809cf4f3c;});
        finish_item(item);
    endtask
endclass

class aes_digit_seq extends uvm_sequence #(aes_seq_item);
    `uvm_object_utils(aes_digit_seq)
    
    function new(string name = "aes_digit_seq");
        super.new(name);
    endfunction
    
    task body();
        aes_seq_item item;
        for (int i = 0; i <= 9; i++) begin
            item = aes_seq_item::type_id::create($sformatf("item_%0d", i));
            start_item(item);
            assert(item.randomize() with {
                key                == 128'h2b7e151628aed2a6abf7158809cf4f3c;
                plaintext[127:32]  == 96'd0;
                plaintext[31:0]    == i;   // 0~9 순서대로
            });
            finish_item(item);
        end
    endtask
endclass



















