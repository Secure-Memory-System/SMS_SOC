`timescale 1ns / 1ps

module conv_weight_rom #(
    parameter FILTER_ID = 0    // 0~4
)(
    input      [3:0] addr,     // 0~8 (9개)
    output reg [7:0] data
);
    reg [7:0] mem [0:8];

    initial begin
        case (FILTER_ID)
            0: $readmemh("conv2d_weights_filter_0.txt", mem);
            1: $readmemh("conv2d_weights_filter_1.txt", mem);
            2: $readmemh("conv2d_weights_filter_2.txt", mem);
            3: $readmemh("conv2d_weights_filter_3.txt", mem);
            4: $readmemh("conv2d_weights_filter_4.txt", mem);
        endcase
    end

    // 비동기 읽기 → Distributed RAM 합성
    always @(*) data = mem[addr];

endmodule
