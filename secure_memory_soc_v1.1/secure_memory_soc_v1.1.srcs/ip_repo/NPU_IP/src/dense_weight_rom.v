`timescale 1ns / 1ps

module dense_weight_rom (
    input            clk,
    input     [12:0] addr,     // 0~4224 (13비트)
    output reg [7:0] data
);
    reg [7:0] mem [0:4224];

    initial $readmemh("dense_weights.txt", mem);

    // 동기 읽기 → BRAM 합성
    always @(posedge clk) data <= mem[addr];

    // ⚠️ addr을 올린 다음 클럭에 data가 나옴!

endmodule