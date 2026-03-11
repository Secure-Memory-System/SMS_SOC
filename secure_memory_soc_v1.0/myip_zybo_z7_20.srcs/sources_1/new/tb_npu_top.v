`timescale 1ns / 1ps

module tb_npu_top();

    reg clk;
    reg reset_p;
    reg start;
    reg [15:0] reg_img_w;
    reg [15:0] reg_img_h;
    reg reg_pad_en;
    
    reg [7:0] w [0:8]; 
    reg signed [15:0] bias_in;
    
    reg [7:0] pixel_in;
    reg pixel_valid;
    
    // 바뀐 포트 이름 반영
    wire [3:0] final_digit;
    wire final_valid;
    wire done_tick;

    npu_top u_dut (
        .clk(clk), .reset_p(reset_p), .start(start),
        .reg_img_w(reg_img_w), .reg_img_h(reg_img_h), .reg_pad_en(reg_pad_en),
        .weight_in_0(w[0]), .weight_in_1(w[1]), .weight_in_2(w[2]),
        .weight_in_3(w[3]), .weight_in_4(w[4]), .weight_in_5(w[5]),
        .weight_in_6(w[6]), .weight_in_7(w[7]), .weight_in_8(w[8]),
        .bias_in(bias_in), .pixel_in(pixel_in), .pixel_valid(pixel_valid),
        .final_digit(final_digit), .final_valid(final_valid), .done_tick(done_tick)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer x, y, i;

    // 784개의 진짜 이미지 픽셀을 담을 메모리 배열
    reg [7:0] test_img [0:783];
    
    initial begin
        $readmemh("test_image.mem", test_img);
        reset_p = 1; start = 0; pixel_in = 0; pixel_valid = 0;
        
        // 1. 이미지 크기를 실제 MNIST 규격으로 변경!
        reg_img_w = 28; 
        reg_img_h = 28;
        reg_pad_en = 0; 

        // 2. 파이참 터미널 창에 떴던 [Conv2D Weights] 10줄
        w[8] = 8'h81;  // 원본: -1.3658
        w[7] = 8'h2d;  // 원본: 0.4853
        w[6] = 8'h8d;  // 원본: -1.2381
        w[5] = 8'h97;  // 원본: -1.1342
        w[4] = 8'h9f;  // 원본: -1.0457
        w[3] = 8'hc6;  // 원본: -0.6218
        w[2] = 8'h29;  // 원본: 0.4378
        w[1] = 8'he1;  // 원본: -0.3332
        w[0] = 8'hc8;  // 원본: -0.6058
        bias_in = 16'h7fff;

        #22 reset_p = 0; 
        #20;

        @(posedge clk); #1; 
        start = 1;
        @(posedge clk); #1; 
        start = 0;

        for (i = 0; i < 784; i = i + 1) begin
            @(posedge clk); #1; 
            pixel_valid = 1;
            pixel_in = test_img[i]; // test_img 배열에서 값을 하나씩 빼옴
        end
        
        @(posedge clk); #1; 
        pixel_valid = 0;

        wait(done_tick);
        $display("--- Input Finished (done_tick) ---");
        
        // 4. 데이터가 169개로 늘어났으니 Dense 연산 대기 시간도 대폭 늘리기
        repeat(3000) @(posedge clk); 
        
        $display("--- Simulation Finished ---");
        $finish;
    end
   // 모니터링: 딱 1개의 숫자만 출력
   always @(posedge clk) begin
       if (final_valid) begin
           $display("Time: %0t | *** NPU Final Recognized Digit: %d ***", $time, final_digit);
       end
   end
endmodule