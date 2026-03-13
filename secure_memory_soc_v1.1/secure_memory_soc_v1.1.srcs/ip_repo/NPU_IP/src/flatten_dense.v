`timescale 1ns / 1ps

module flatten_dense #(
    parameter IN_FEATURES = 845,
    parameter CH_FEATURES = 169,  
    parameter DENSE1_OUT  = 5,  
    parameter NUM_CLASSES = 10
)(
    input clk,
    input reset_p,

    input signed [119:0] pool_data_in,   // 24bit × 5채널
    input        [4:0]   pool_valid_in,  // 5채널 valid

    output reg [3:0] final_digit,
    output reg       final_valid
);

    // Flatten 버퍼 (BRAM으로 합성)
    reg signed [23:0] flat_mem [0:844];
    reg [9:0] gather_cnt;           // 0~168 (CH_FEATURES)

    // Dense-1 결과 저장
    reg signed [47:0] dense1_out [0:4];  // ReLU 후 5개
    
    // Dense ROM 인스턴스
    reg [12:0] d1_addr;
    wire [7:0]  d1_data;
    dense_weight_rom  u_d1_rom (.clk(clk), .addr(d1_addr), .data(d1_data));

    reg [5:0]  d2_addr;
    wire [7:0]  d2_data;
    dense1_weight_rom u_d2_rom (.addr(d2_addr), .data(d2_data));

    // 바이어스
    reg signed [7:0] dense_bias  [0:4];
    reg signed [7:0] dense1_bias [0:9];
    initial begin
        $readmemh("dense_bias.txt",   dense_bias);
        $readmemh("dense_1_bias.txt", dense1_bias);
    end
    
    // FSM
    localparam S_GATHER    = 4'd0;
    localparam S_MAC1_INIT = 4'd1;
    localparam S_MAC1_RUN  = 4'd2;
    localparam S_MAC1_WAIT = 4'd3;
    localparam S_RELU      = 4'd4;
    localparam S_MAC2_INIT = 4'd5;
    localparam S_MAC2_RUN  = 4'd6;
    localparam S_MAC2_WAIT = 4'd7;
    localparam S_EVAL      = 4'd8;
    localparam S_DONE      = 4'd9;
    
    reg [3:0]  state;
    reg [3:0]  neuron_cnt;   // Dense-1: 0~4, Dense-2: 0~9
    reg [9:0]  feat_cnt;     // 0~844
    reg signed [47:0] mac_sum;
    reg signed [47:0] max_score;
    reg [3:0]  best_class;

    // 4. 메인 제어 블록
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            state <= S_GATHER;
            gather_cnt <= 0;
            neuron_cnt  <= 0;
            feat_cnt <= 0;
            mac_sum <= 0;
            max_score <= 0;
            best_class <= 0;
            final_valid <= 0;
            final_digit <= 0;
            d1_addr     <= 0;
            d2_addr     <= 0;
        end else begin
            case (state)
                // [단계 1] 데이터 모으기
                S_GATHER: begin
                    final_valid <= 0;
                    if (pool_valid_in[0]) begin
                        // 5채널 동시에 저장
                        // flat_mem 배치:
                        // [0~168]   → 채널 0 (13×13)
                        // [169~337] → 채널 1
                        // [338~506] → 채널 2
                        // [507~675] → 채널 3
                        // [676~844] → 채널 4
                        flat_mem[gather_cnt]           <= pool_data_in[23:0];
                        flat_mem[gather_cnt + 169]     <= pool_data_in[47:24];
                        flat_mem[gather_cnt + 338]     <= pool_data_in[71:48];
                        flat_mem[gather_cnt + 507]     <= pool_data_in[95:72];
                        flat_mem[gather_cnt + 676]     <= pool_data_in[119:96];
    
                        if (gather_cnt == CH_FEATURES - 1) begin
                            gather_cnt <= 0;
                            state      <= S_MAC1_INIT;
                        end else begin
                            gather_cnt <= gather_cnt + 1;
                        end
                    end
                end
                
                S_MAC1_INIT: begin
                    mac_sum <= {{40{dense_bias[neuron_cnt][7]}}, dense_bias[neuron_cnt]};
                    feat_cnt <= 0;
                    d1_addr <= neuron_cnt * IN_FEATURES;
                    state <= S_MAC1_RUN;
                end
                
                S_MAC1_RUN: begin
                    mac_sum <= mac_sum + ($signed(flat_mem[feat_cnt]) * $signed(d1_data));
                    
                    if(feat_cnt == IN_FEATURES - 1) begin
                        state <= S_MAC1_WAIT;
                    end
                    else begin
                        feat_cnt <= feat_cnt + 1;
                        d1_addr <= d1_addr + 1;
                    end
                end
                
                S_MAC1_WAIT: begin
                    state <= S_RELU;  // 이제 mac_sum 최신값 반영 완료
                end
                
                S_RELU: begin
                    dense1_out[neuron_cnt] <= mac_sum[47] ? 48'd0 : mac_sum;
                    
                    if(neuron_cnt == DENSE1_OUT - 1) begin
                        neuron_cnt <= 0;
                        state <= S_MAC2_INIT;
                    end
                    else begin
                        neuron_cnt <= neuron_cnt + 1;
                        state <= S_MAC1_INIT;
                    end
                end

                S_MAC2_INIT: begin
                    mac_sum <= {{40{dense1_bias[neuron_cnt][7]}}, dense1_bias[neuron_cnt]};
                    feat_cnt <= 0;
                    d2_addr <= neuron_cnt * DENSE1_OUT;
                    state <= S_MAC2_RUN;
                end
                
                S_MAC2_RUN: begin
                    mac_sum <= mac_sum + ($signed(dense1_out[feat_cnt]) * $signed(d2_data));
                    
                    if(feat_cnt == DENSE1_OUT - 1) begin
                        state <= S_MAC2_WAIT;
                    end
                    else begin
                        feat_cnt <= feat_cnt + 1;
                        d2_addr <= d2_addr + 1;
                    end
                end
                
                S_MAC2_WAIT: begin
                    state <= S_EVAL;  // 이제 mac_sum에 마지막 곱셈 반영 완료
                end
                
                S_EVAL: begin
                    if(neuron_cnt == 0 || mac_sum > max_score) begin
                        max_score <= mac_sum;
                        best_class <= neuron_cnt;
                    end
                    
                    if(neuron_cnt == NUM_CLASSES - 1) begin
                        state <= S_DONE;
                    end
                    else begin
                        neuron_cnt <= neuron_cnt + 1;
                        state      <= S_MAC2_INIT;
                    end
                end
                
                S_DONE: begin
                    final_digit <= best_class;
                    final_valid <= 1'b1;
                    // 다음 프레임 준비
                    neuron_cnt  <= 0;
                    state       <= S_GATHER;
                end
            endcase
        end
    end
endmodule