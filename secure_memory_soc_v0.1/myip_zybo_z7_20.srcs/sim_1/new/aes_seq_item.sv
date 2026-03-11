`include "uvm_macros.svh"
import uvm_pkg::*;
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/10/2026 03:24:41 PM
// Design Name: 
// Module Name: aes_seq_item
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


class aes_seq_item extends uvm_sequence_item;
    `uvm_object_utils(aes_seq_item)

    // 입력 필드
    rand logic [127:0] key;
    rand logic [127:0] plaintext;

    // 출력 필드 (드라이버→모니터→스코어보드로 전달)
    logic [127:0] ciphertext;
    logic [127:0] decrypted;

    // 제약: 평문 하위 32비트만 0~9 숫자
    constraint valid_digit {
        plaintext[127:32] == 96'd0;        // 상위 96비트는 0
        plaintext[31:0]   inside {[0:9]};  // 하위 32비트는 0~9
    }

    function new(string name = "aes_seq_item");
        super.new(name);
    endfunction

    // 로그 출력용
    function string convert2string();
        return $sformatf(
            "\n  Key       : %h\n  Plaintext : %h\n  Cipher    : %h\n  Decrypted : %h",
            key, plaintext, ciphertext, decrypted
        );
    endfunction
endclass
    
    
    
    
    
    
    
    
    
    
    
    
    
    
