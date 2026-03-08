`timescale 1ns / 1ps

module tb_enc_dec();

    // Clock & Reset
    reg clk;
    reg reset_n;

    // Common Key & Data
    reg [127:0] master_key;
    reg [127:0] plaintext_in;
    wire [127:0] ciphertext;
    wire [127:0] decrypted_out; // 선언된 진짜 이름

    // Control Signals
    reg enc_start;
    wire enc_done;
    reg dec_start;
    wire dec_done;

    // --------------------------------------------------
    // 1. 암호화 코어 인스턴스화 (Encryption)
    // --------------------------------------------------
    aes_128_core u_enc_core (
        .clk(clk),
        .reset_n(reset_n),
        .key(master_key),
        .data_in(plaintext_in),
        .start(enc_start),
        .data_out(ciphertext),
        .done(enc_done)
    );

    // --------------------------------------------------
    // 2. 복호화 코어 인스턴스화 (Decryption)
    // --------------------------------------------------
    aes_128_inv_core u_dec_core (
        .clk(clk),
        .reset_n(reset_n),
        .key(master_key),
        .data_in(ciphertext), // 암호화된 출력을 바로 입력으로 넣음
        .start(dec_start),
        .data_out(decrypted_out), // <--- 수정 1: dec_out을 decrypted_out으로 변경!
        .done(dec_done)
    );

    // Clock Generation (100MHz)
    always #5 clk = ~clk;

    // --------------------------------------------------
    // 3. Test Sequence
    // --------------------------------------------------
    initial begin
        // 초기화
        clk = 0;
        reset_n = 0;
        enc_start = 0;
        dec_start = 0;
        master_key = 128'h2b7e151628aed2a6abf7158809cf4f3c; // 표준 테스트 키
        
        // NPU에서 인식한 숫자 '7' (앞에 96비트 패딩 포함)
        plaintext_in = 128'h0000_0000_0000_0000_0000_0000_0000_0007;

        #20 reset_n = 1;
        #10;

        // --- STEP 1: 암호화 시작 ---
        $display("Time %0t: Encryption Started...", $time);
        enc_start = 1;
        #10 enc_start = 0;

        wait(enc_done);
        $display("Time %0t: Encryption Finished!", $time);
        $display("Ciphertext: %h", ciphertext);

        #50;

        // --- STEP 2: 복호화 시작 ---
        $display("Time %0t: Decryption Started...", $time);
        dec_start = 1;
        #10 dec_start = 0;

        wait(dec_done);
        $display("Time %0t: Decryption Finished!", $time);
        $display("Decrypted Result: %h", decrypted_out); // <--- 수정 2: dec_out을 decrypted_out으로 변경!

        // --- STEP 3: 최종 비교 ---
        if (plaintext_in == decrypted_out) begin // <--- 수정 3: dec_out을 decrypted_out으로 변경!
            $display("*****************************************");
            $display("** SUCCESS: Data Integrity Verified!   **");
            $display("*****************************************");
        end else begin
            $display("#########################################");
            $display("## FAILURE: Data Mismatch!             ##");
            $display("#########################################");
        end

        #100 $finish;
    end
    
endmodule