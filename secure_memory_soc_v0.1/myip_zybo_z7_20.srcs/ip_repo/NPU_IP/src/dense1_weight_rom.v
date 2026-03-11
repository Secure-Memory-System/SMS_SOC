`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/11/2026 11:38:03 AM
// Design Name: 
// Module Name: dense1_weight_rom
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


module dense1_weight_rom (
    input      [5:0] addr,     // 0~49 (6비트)
    output reg [7:0] data
);
    reg [7:0] mem [0:49];

    initial $readmemh("dense_1_weights.txt", mem);

    // 비동기 읽기 → Distributed RAM 합성
    always @(*) data = mem[addr];

endmodule