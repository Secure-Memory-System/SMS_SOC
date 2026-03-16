`timescale 1ns / 1ps

module fnd_axi_stream_wrapper (
    // System
    input  wire        aclk,
    input  wire        aresetn,   // active-low

    // AXI4-Stream Slave
    input  wire [3:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    // FND 출력
    output wire [7:0]  seg,
    output wire [3:0]  com
);

    wire reset_p = ~aresetn;
    assign s_axis_tready = 1'b1;

    // 통신 대기 시간 체크 (Burst의 시작점 찾기)
    reg [7:0] idle_cnt;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) 
            idle_cnt <= 8'd0;
        else if (s_axis_tvalid) 
            idle_cnt <= 8'd0;
        else if (idle_cnt != 8'hFF) 
            idle_cnt <= idle_cnt + 1;
    end

    reg [3:0] digit_hold;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            digit_hold <= 4'd0;
        else if (s_axis_tvalid && s_axis_tready) begin
            // [핵심 마법]
            // 첫 번째 데이터가 들어올 때는 값을 초기화하고,
            if (idle_cnt == 8'hFF) 
                digit_hold <= s_axis_tdata;
            // 뒤이어 우르르 들어오는 나머지 124비트의 데이터들은 전부 OR 연산으로 누적!
            else 
                digit_hold <= digit_hold | s_axis_tdata;
        end
    end

    // FND 컨트롤러
    fnd_cntr u_fnd_cntr (
        .clk         (aclk),
        .reset_p     (reset_p),
        .digit_value (digit_hold),
        .seg         (seg),
        .com         (com)
    );

endmodule