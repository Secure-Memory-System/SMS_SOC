`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/03/08 13:33:10
// Design Name: 
// Module Name: aes_key_expansion
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


module aes_key_expansion(
    input  wire         clk,
    input  wire [127:0] initial_key, 
    input  wire [3:0]   round,       
    output reg  [127:0] expanded_key 
);

    // --------------------------------------------------
    // 1. 라운드 상수 (Rcon) 정의
    // --------------------------------------------------
    function automatic[7:0] rcon_func;
        input [3:0] r;
        case (r)
            4'd1: rcon_func = 8'h01; 4'd2: rcon_func = 8'h02; 4'd3: rcon_func = 8'h04;
            4'd4: rcon_func = 8'h08; 4'd5: rcon_func = 8'h10; 4'd6: rcon_func = 8'h20;
            4'd7: rcon_func = 8'h40; 4'd8: rcon_func = 8'h80; 4'd9: rcon_func = 8'h1b;
            4'd10: rcon_func = 8'h36; default: rcon_func = 8'h00;
        endcase
    endfunction

    // --------------------------------------------------
    // 2. 키 확장 전용 S-Box 함수 선언 (에러 해결의 핵심!)
    // --------------------------------------------------
    function automatic[7:0] sbox_func;
        input [7:0] data_in;
        begin
            case (data_in)
                8'h00: sbox_func = 8'h63; 8'h01: sbox_func = 8'h7c; 8'h02: sbox_func = 8'h77; 8'h03: sbox_func = 8'h7b;
                8'h04: sbox_func = 8'hf2; 8'h05: sbox_func = 8'h6b; 8'h06: sbox_func = 8'h6f; 8'h07: sbox_func = 8'hc5;
                8'h08: sbox_func = 8'h30; 8'h09: sbox_func = 8'h01; 8'h0a: sbox_func = 8'h67; 8'h0b: sbox_func = 8'h2b;
                8'h0c: sbox_func = 8'hfe; 8'h0d: sbox_func = 8'hd7; 8'h0e: sbox_func = 8'hab; 8'h0f: sbox_func = 8'h76;
                8'h10: sbox_func = 8'hca; 8'h11: sbox_func = 8'h82; 8'h12: sbox_func = 8'hc9; 8'h13: sbox_func = 8'h7d;
                8'h14: sbox_func = 8'hfa; 8'h15: sbox_func = 8'h59; 8'h16: sbox_func = 8'h47; 8'h17: sbox_func = 8'hf0;
                8'h18: sbox_func = 8'had; 8'h19: sbox_func = 8'hd4; 8'h1a: sbox_func = 8'ha2; 8'h1b: sbox_func = 8'haf;
                8'h1c: sbox_func = 8'h9c; 8'h1d: sbox_func = 8'ha4; 8'h1e: sbox_func = 8'h72; 8'h1f: sbox_func = 8'hc0;
                8'h20: sbox_func = 8'hb7; 8'h21: sbox_func = 8'hfd; 8'h22: sbox_func = 8'h93; 8'h23: sbox_func = 8'h26;
                8'h24: sbox_func = 8'h36; 8'h25: sbox_func = 8'h3f; 8'h26: sbox_func = 8'hf7; 8'h27: sbox_func = 8'hcc;
                8'h28: sbox_func = 8'h34; 8'h29: sbox_func = 8'ha5; 8'h2a: sbox_func = 8'he5; 8'h2b: sbox_func = 8'hf1;
                8'h2c: sbox_func = 8'h71; 8'h2d: sbox_func = 8'hd8; 8'h2e: sbox_func = 8'h31; 8'h2f: sbox_func = 8'h15;
                8'h30: sbox_func = 8'h04; 8'h31: sbox_func = 8'hc7; 8'h32: sbox_func = 8'h23; 8'h33: sbox_func = 8'hc3;
                8'h34: sbox_func = 8'h18; 8'h35: sbox_func = 8'h96; 8'h36: sbox_func = 8'h05; 8'h37: sbox_func = 8'h9a;
                8'h38: sbox_func = 8'h07; 8'h39: sbox_func = 8'h12; 8'h3a: sbox_func = 8'h80; 8'h3b: sbox_func = 8'he2;
                8'h3c: sbox_func = 8'heb; 8'h3d: sbox_func = 8'h27; 8'h3e: sbox_func = 8'hb2; 8'h3f: sbox_func = 8'h75;
                8'h40: sbox_func = 8'h09; 8'h41: sbox_func = 8'h83; 8'h42: sbox_func = 8'h2c; 8'h43: sbox_func = 8'h1a;
                8'h44: sbox_func = 8'h1b; 8'h45: sbox_func = 8'h6e; 8'h46: sbox_func = 8'h5a; 8'h47: sbox_func = 8'ha0;
                8'h48: sbox_func = 8'h52; 8'h49: sbox_func = 8'h3b; 8'h4a: sbox_func = 8'hd6; 8'h4b: sbox_func = 8'hb3;
                8'h4c: sbox_func = 8'h29; 8'h4d: sbox_func = 8'he3; 8'h4e: sbox_func = 8'h2f; 8'h4f: sbox_func = 8'h84;
                8'h50: sbox_func = 8'h53; 8'h51: sbox_func = 8'hd1; 8'h52: sbox_func = 8'h00; 8'h53: sbox_func = 8'hed;
                8'h54: sbox_func = 8'h20; 8'h55: sbox_func = 8'hfc; 8'h56: sbox_func = 8'hb1; 8'h57: sbox_func = 8'h5b;
                8'h58: sbox_func = 8'h6a; 8'h59: sbox_func = 8'hcb; 8'h5a: sbox_func = 8'hbe; 8'h5b: sbox_func = 8'h39;
                8'h5c: sbox_func = 8'h4a; 8'h5d: sbox_func = 8'h4c; 8'h5e: sbox_func = 8'h58; 8'h5f: sbox_func = 8'hcf;
                8'h60: sbox_func = 8'hd0; 8'h61: sbox_func = 8'hef; 8'h62: sbox_func = 8'haa; 8'h63: sbox_func = 8'hfb;
                8'h64: sbox_func = 8'h43; 8'h65: sbox_func = 8'h4d; 8'h66: sbox_func = 8'h33; 8'h67: sbox_func = 8'h85;
                8'h68: sbox_func = 8'h45; 8'h69: sbox_func = 8'hf9; 8'h6a: sbox_func = 8'h02; 8'h6b: sbox_func = 8'h7f;
                8'h6c: sbox_func = 8'h50; 8'h6d: sbox_func = 8'h3c; 8'h6e: sbox_func = 8'h9f; 8'h6f: sbox_func = 8'ha8;
                8'h70: sbox_func = 8'h51; 8'h71: sbox_func = 8'ha3; 8'h72: sbox_func = 8'h40; 8'h73: sbox_func = 8'h8f;
                8'h74: sbox_func = 8'h92; 8'h75: sbox_func = 8'h9d; 8'h76: sbox_func = 8'h38; 8'h77: sbox_func = 8'hf5;
                8'h78: sbox_func = 8'hbc; 8'h79: sbox_func = 8'hb6; 8'h7a: sbox_func = 8'hda; 8'h7b: sbox_func = 8'h21;
                8'h7c: sbox_func = 8'h10; 8'h7d: sbox_func = 8'hff; 8'h7e: sbox_func = 8'hf3; 8'h7f: sbox_func = 8'hd2;
                8'h80: sbox_func = 8'hcd; 8'h81: sbox_func = 8'h0c; 8'h82: sbox_func = 8'h13; 8'h83: sbox_func = 8'hec;
                8'h84: sbox_func = 8'h5f; 8'h85: sbox_func = 8'h97; 8'h86: sbox_func = 8'h44; 8'h87: sbox_func = 8'h17;
                8'h88: sbox_func = 8'hc4; 8'h89: sbox_func = 8'ha7; 8'h8a: sbox_func = 8'h7e; 8'h8b: sbox_func = 8'h3d;
                8'h8c: sbox_func = 8'h64; 8'h8d: sbox_func = 8'h5d; 8'h8e: sbox_func = 8'h19; 8'h8f: sbox_func = 8'h73;
                8'h90: sbox_func = 8'h60; 8'h91: sbox_func = 8'h81; 8'h92: sbox_func = 8'h4f; 8'h93: sbox_func = 8'hdc;
                8'h94: sbox_func = 8'h22; 8'h95: sbox_func = 8'h2a; 8'h96: sbox_func = 8'h90; 8'h97: sbox_func = 8'h88;
                8'h98: sbox_func = 8'h46; 8'h99: sbox_func = 8'hee; 8'h9a: sbox_func = 8'hb8; 8'h9b: sbox_func = 8'h14;
                8'h9c: sbox_func = 8'hde; 8'h9d: sbox_func = 8'h5e; 8'h9e: sbox_func = 8'h0b; 8'h9f: sbox_func = 8'hdb;
                8'ha0: sbox_func = 8'he0; 8'ha1: sbox_func = 8'h32; 8'ha2: sbox_func = 8'h3a; 8'ha3: sbox_func = 8'h0a;
                8'ha4: sbox_func = 8'h49; 8'ha5: sbox_func = 8'h06; 8'ha6: sbox_func = 8'h24; 8'ha7: sbox_func = 8'h5c;
                8'ha8: sbox_func = 8'hc2; 8'ha9: sbox_func = 8'hd3; 8'haa: sbox_func = 8'hac; 8'hab: sbox_func = 8'h62;
                8'hac: sbox_func = 8'h91; 8'had: sbox_func = 8'h95; 8'hae: sbox_func = 8'he4; 8'haf: sbox_func = 8'h79;
                8'hb0: sbox_func = 8'he7; 8'hb1: sbox_func = 8'hc8; 8'hb2: sbox_func = 8'h37; 8'hb3: sbox_func = 8'h6d;
                8'hb4: sbox_func = 8'h8d; 8'hb5: sbox_func = 8'hd5; 8'hb6: sbox_func = 8'h4e; 8'hb7: sbox_func = 8'ha9;
                8'hb8: sbox_func = 8'h6c; 8'hb9: sbox_func = 8'h56; 8'hba: sbox_func = 8'hf4; 8'hbb: sbox_func = 8'hea;
                8'hbc: sbox_func = 8'h65; 8'hbd: sbox_func = 8'h7a; 8'hbe: sbox_func = 8'hae; 8'hbf: sbox_func = 8'h08;
                8'hc0: sbox_func = 8'hba; 8'hc1: sbox_func = 8'h78; 8'hc2: sbox_func = 8'h25; 8'hc3: sbox_func = 8'h2e;
                8'hc4: sbox_func = 8'h1c; 8'hc5: sbox_func = 8'ha6; 8'hc6: sbox_func = 8'hb4; 8'hc7: sbox_func = 8'hc6;
                8'hc8: sbox_func = 8'he8; 8'hc9: sbox_func = 8'hdd; 8'hca: sbox_func = 8'h74; 8'hcb: sbox_func = 8'h1f;
                8'hcc: sbox_func = 8'h4b; 8'hcd: sbox_func = 8'hbd; 8'hce: sbox_func = 8'h8b; 8'hcf: sbox_func = 8'h8a;
                8'hd0: sbox_func = 8'h70; 8'hd1: sbox_func = 8'h3e; 8'hd2: sbox_func = 8'hb5; 8'hd3: sbox_func = 8'h66;
                8'hd4: sbox_func = 8'h48; 8'hd5: sbox_func = 8'h03; 8'hd6: sbox_func = 8'hf6; 8'hd7: sbox_func = 8'h0e;
                8'hd8: sbox_func = 8'h61; 8'hd9: sbox_func = 8'h35; 8'hda: sbox_func = 8'h57; 8'hdb: sbox_func = 8'hb9;
                8'hdc: sbox_func = 8'h86; 8'hdd: sbox_func = 8'hc1; 8'hde: sbox_func = 8'h1d; 8'hdf: sbox_func = 8'h9e;
                8'he0: sbox_func = 8'he1; 8'he1: sbox_func = 8'hf8; 8'he2: sbox_func = 8'h98; 8'he3: sbox_func = 8'h11;
                8'he4: sbox_func = 8'h69; 8'he5: sbox_func = 8'hd9; 8'he6: sbox_func = 8'h8e; 8'he7: sbox_func = 8'h94;
                8'he8: sbox_func = 8'h9b; 8'he9: sbox_func = 8'h1e; 8'hea: sbox_func = 8'h87; 8'heb: sbox_func = 8'he9;
                8'hec: sbox_func = 8'hce; 8'hed: sbox_func = 8'h55; 8'hee: sbox_func = 8'h28; 8'hef: sbox_func = 8'hdf;
                8'hf0: sbox_func = 8'h8c; 8'hf1: sbox_func = 8'ha1; 8'hf2: sbox_func = 8'h89; 8'hf3: sbox_func = 8'h0d;
                8'hf4: sbox_func = 8'hbf; 8'hf5: sbox_func = 8'he6; 8'hf6: sbox_func = 8'h42; 8'hf7: sbox_func = 8'h68;
                8'hf8: sbox_func = 8'h41; 8'hf9: sbox_func = 8'h99; 8'hfa: sbox_func = 8'h2d; 8'hfb: sbox_func = 8'h0f;
                8'hfc: sbox_func = 8'hb0; 8'hfd: sbox_func = 8'h54; 8'hfe: sbox_func = 8'hbb; 8'hff: sbox_func = 8'h16;
                default: sbox_func = 8'h63;
            endcase
        end
    endfunction

    // --------------------------------------------------
    // 3. SubWord 함수 (이제 에러 안 남!)
    // --------------------------------------------------
    function automatic[31:0] sub_word;
        input [31:0] w;
        begin
            sub_word[31:24] = sbox_func(w[31:24]);
            sub_word[23:16] = sbox_func(w[23:16]);
            sub_word[15:8]  = sbox_func(w[15:8]);
            sub_word[7:0]   = sbox_func(w[7:0]);
        end
    endfunction

    // --------------------------------------------------
    // 4. 키 생성 로직 (Iterative 구조)
    // --------------------------------------------------
    reg [127:0] key_mem [0:10];
    integer i;

    always @(*) begin
        key_mem[0] = initial_key;
        for (i = 1; i <= 10; i = i + 1) begin
            key_mem[i][127:96] = key_mem[i-1][127:96] ^ 
                                 sub_word({key_mem[i-1][23:0], key_mem[i-1][31:24]}) ^ 
                                 {rcon_func(i[3:0]), 24'h0};
            
            key_mem[i][95:64] = key_mem[i-1][95:64] ^ key_mem[i][127:96];
            key_mem[i][63:32] = key_mem[i-1][63:32] ^ key_mem[i][95:64];
            key_mem[i][31:0]  = key_mem[i-1][31:0]  ^ key_mem[i][63:32];
        end
    end

    // 현재 라운드에 맞는 키 출력
    always @(*) begin
        expanded_key = key_mem[round];
    end

endmodule
