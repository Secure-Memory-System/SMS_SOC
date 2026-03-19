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
    // 3. 암호화 중간값 모니터링 (계층적 참조)
    // --------------------------------------------------
    always @(posedge clk) begin
        // ROUND_OP 재진입 시 → 이전 라운드 MixColumns+AddRoundKey 결과 (Round 1~8)
        if (u_enc_core.state == 3'd1 && u_enc_core.round_count > 1) begin
            $display("[ENC] Round %-2d After MixColumns+AddKey  : %h",
                      u_enc_core.round_count - 1, u_enc_core.state_reg);
        end
        // FINAL_RD 진입 시 → Round 9 MixColumns+AddRoundKey 결과
        if (u_enc_core.state == 3'd3) begin
            $display("[ENC] Round 9  After MixColumns+AddKey  : %h",
                      u_enc_core.state_reg);
        end
        // enc_done 신호로 Round 10 최종 암호문 캡처 (state_reg = FINAL_RD 결과)
        if (enc_done) begin
            $display("[ENC] Round 10 Final Ciphertext          : %h", u_enc_core.state_reg);
        end
    end

    // --------------------------------------------------
    // 4. 복호화 중간값 모니터링 (negedge: posedge NBA 완료 후 안정된 값 캡처)
    // --------------------------------------------------
    always @(negedge clk) begin
        // [진단] round_count가 0~9이면 복호화 진행 중 → 실제 state 값 출력
        if (u_dec_core.round_count <= 4'd9) begin
            $display("[DEC_DBG] negedge: state=%0d rc=%0d sr=%h",
                      u_dec_core.state, u_dec_core.round_count, u_dec_core.state_reg);
        end

        // ROUND_OP 진입 후 → INITIAL 결과 (Round 10 AddKey), round_count==9
        if (u_dec_core.state == 3'd3 && u_dec_core.round_count == 9) begin
            $display("[DEC] Round 10 After InitialKey XOR      : %h",
                      u_dec_core.state_reg);
        end
        // ROUND_OP 재진입 시 round_count 1~8 → InvMixColumns 결과 (Round 9~2)
        if (u_dec_core.state == 3'd3 && u_dec_core.round_count >= 1 && u_dec_core.round_count <= 8) begin
            $display("[DEC] Round %-2d After InvMixColumns       : %h",
                      u_dec_core.round_count + 1, u_dec_core.state_reg);
        end
        // FINAL_RD 진입 후 → Round 1 InvMixColumns 결과
        if (u_dec_core.state == 3'd5) begin
            $display("[DEC] Round 1  After InvMixColumns       : %h",
                      u_dec_core.state_reg);
        end
        // dec_done 신호로 Round 0 최종 복호화 결과 캡처
        if (dec_done) begin
            $display("[DEC] Round 0  Final Decrypted           : %h", decrypted_out);
        end
    end

    // --------------------------------------------------
    // 5. Test Sequence
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