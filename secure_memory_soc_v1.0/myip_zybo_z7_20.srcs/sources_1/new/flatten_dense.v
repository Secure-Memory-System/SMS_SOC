`timescale 1ns / 1ps

module flatten_dense #(
    parameter DATA_WIDTH = 24,
    parameter IN_FEATURES = 169,  // Pooling에서 넘어오는 데이터 개수 (10x10 테스트 기준)
    parameter NUM_CLASSES = 10,  // 판별할 숫자 종류 (0~9)
    parameter WEIGHT_WIDTH = 8
)(
    input clk,
    input reset_p,

    // Max Pooling에서 들어오는 입력 스트림
    input signed [DATA_WIDTH-1:0] pool_data_in,
    input pool_valid_in,

    // 최종 결과 출력
    output reg [3:0] final_digit, // 0~9 판별 결과
    output reg final_valid
);

    // 1. Flatten: 데이터를 모아둘 레지스터 배열
    reg signed [DATA_WIDTH-1:0] flat_mem [0:IN_FEATURES-1];
    reg [15:0] gather_cnt;

    // 2. 가상 ROM: 가중치(Weight)와 편향(Bias)
    // Python에서 추출한 값을 나중에 $readmemh("weights.mem", weight_rom) 등으로 덮어씌울 예정입니다.
    reg signed [WEIGHT_WIDTH-1:0] weight_rom [0:(NUM_CLASSES * IN_FEATURES)-1];
    reg signed [15:0] bias_rom [0:NUM_CLASSES-1];

//    // 임시 더미 데이터 초기화
//    integer i;
//    initial begin
//        for (i=0; i<NUM_CLASSES*IN_FEATURES; i=i+1) weight_rom[i] = 1; 
//        for (i=0; i<NUM_CLASSES; i=i+1) bias_rom[i] = 0;
//    end
    initial begin   
        $readmemh("fc_weights.mem", weight_rom);
        $readmemh("fc_biases.mem", bias_rom);
    end
    
    // 3. 상태 머신 선언
    localparam S_GATHER   = 3'd0; // 데이터 모으기
    localparam S_MAC_INIT = 3'd1; // 점수 계산 준비
    localparam S_MAC_RUN  = 3'd2; // 곱하고 더하기
    localparam S_EVAL     = 3'd3; // 최댓값 비교 (ArgMax)
    localparam S_DONE     = 3'd4; // 완료 및 출력

    reg [2:0] state;
    reg [3:0] class_cnt; // 0~9 클래스 카운터
    reg [15:0] feat_cnt; // 0~15 피처 카운터
    
    // 오버플로우 방지를 위해 넉넉한 48비트 사용
    reg signed [47:0] mac_sum;  
    reg signed [47:0] max_score;
    reg [3:0] best_class;

    // 4. 메인 제어 블록
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            state <= S_GATHER;
            gather_cnt <= 0; class_cnt <= 0; feat_cnt <= 0;
            mac_sum <= 0; max_score <= 0; best_class <= 0;
            final_valid <= 0; final_digit <= 0;
        end else begin
            case (state)
                // [단계 1] 데이터 모으기
                S_GATHER: begin
                    final_valid <= 0;
                    if (pool_valid_in) begin
                        flat_mem[gather_cnt] <= pool_data_in;
                        if (gather_cnt == IN_FEATURES - 1) begin
                            gather_cnt <= 0;
                            state <= S_MAC_INIT; // 다 모았으면 연산하러 출발!
                        end else begin
                            gather_cnt <= gather_cnt + 1;
                        end
                    end
                end

                // [단계 2] 특정 클래스(0~9) 점수 계산 준비
                S_MAC_INIT: begin
                    mac_sum <= bias_rom[class_cnt]; // 초기값은 Bias
                    feat_cnt <= 0;
                    state <= S_MAC_RUN;
                end

                // [단계 3] 16번 곱하고 더하기 (MAC)
                S_MAC_RUN: begin
                    // 1클럭에 1번씩 곱셈 수행 (타이밍 에러 방지)
                    mac_sum <= mac_sum + (flat_mem[feat_cnt] * weight_rom[(class_cnt * IN_FEATURES) + feat_cnt]);
                    
                    if (feat_cnt == IN_FEATURES - 1) begin
                        state <= S_EVAL;
                    end else begin
                        feat_cnt <= feat_cnt + 1;
                    end
                end

                // [단계 4] 점수 비교 (가장 높은 확률 찾기)
                S_EVAL: begin
                    // 처음(class 0)이거나, 현재 점수가 기존 최고 점수보다 높으면 갱신
                    if (class_cnt == 0 || mac_sum > max_score) begin
                        max_score <= mac_sum;
                        best_class <= class_cnt;
                    end

                    // 0~9까지 다 비교했는가?
                    if (class_cnt == NUM_CLASSES - 1) begin
                        state <= S_DONE; 
                    end else begin
                        class_cnt <= class_cnt + 1;
                        state <= S_MAC_INIT; // 다음 숫자 점수 매기러 감
                    end
                end

                // [단계 5] 출력 및 초기화
                S_DONE: begin
                    final_digit <= best_class; // 🎉 최종 숫자 결정!
                    final_valid <= 1'b1;
                    
                    // 다음 프레임을 위해 리셋
                    state <= S_GATHER;
                    class_cnt <= 0;
                end
            endcase
        end
    end
endmodule