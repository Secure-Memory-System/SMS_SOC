`timescale 1ns / 1ps

module fnd_axi_stream_wrapper (
    // System
    input  wire        aclk,
    input  wire        aresetn,   // active-low (복호화 IP와 동일한 극성)

    // AXI4-Stream Slave (from aes_dec_axi_wrapper)
    input  wire [3:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    // FND 출력
    output wire [7:0]  seg,
    output wire [3:0]  com
);

    // --------------------------------------------------
    // [Part 1] 극성 변환: aresetn → reset_p
    // --------------------------------------------------
    wire reset_p = ~aresetn;  // fnd_cntr은 active-high reset 사용

    // --------------------------------------------------
    // [Part 2] digit 값 레지스터 (handshake로 업데이트)
    // --------------------------------------------------
    // tready는 항상 1: fnd_cntr은 언제든 새 값을 받을 수 있음
    // (FND는 현재 저장된 digit을 계속 표시하면 되므로 back-pressure 불필요)
    assign s_axis_tready = 1'b1;

    reg [3:0] digit_hold;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            digit_hold <= 4'd0;
        else if (s_axis_tvalid && s_axis_tready)
            digit_hold <= s_axis_tdata;  // 유효한 데이터가 올 때만 업데이트
    end

    // --------------------------------------------------
    // [Part 3] fnd_cntr 인스턴스
    // --------------------------------------------------
    fnd_cntr u_fnd_cntr (
        .clk         (aclk),
        .reset_p     (reset_p),
        .digit_value (digit_hold),
        .seg         (seg),
        .com         (com)
    );

endmodule