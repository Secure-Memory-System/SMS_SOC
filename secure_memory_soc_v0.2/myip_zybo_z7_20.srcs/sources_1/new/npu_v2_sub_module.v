`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: npu_v3_sub_module
//
// [v3 통합 전략]
//   npu_v2     장점: pixel_en 외부 제어 인터페이스, 간결한 output_layer
//   수정본     장점: k==8 누적 버그 수정, dense S_CALC 파이프라인 수정,
//                    동기 리셋 통일, $signed 명시적 부호 처리
//
// [모듈별 채택 방침]
//   npu_conv2d_buf      : pixel_en 방식 유지 (npu_v2) + 동기 리셋 전체 초기화 (npu_v2)
//   npu_conv2d_calc     : pixel_en 환경에 맞게 busy 제거 + k==9 버그 수정 (수정본)
//                         + 동기 리셋 + $signed 명시적 부호 처리 (수정본)
//   npu_maxpool_conv2d  : 동기 리셋 (수정본), 로직 동일
//   npu_dense_integrated: S_CALC 주소 고정 읽기 요청 방식 (수정본)
//                         + S_NEXT w_addr 명시적 뉴런 주소 점프 (수정본)
//   npu_output_layer    : 간결한 단일 S_CALC 구조 유지 (npu_v2) + 동기 리셋 (수정본)
//////////////////////////////////////////////////////////////////////////////////


// ============================================================
//  (1) npu_conv2d_buf
//  [채택] npu_v2: pixel_en 외부 인에이블 인터페이스
//  [채택] npu_v2: 리셋 시 value_00~08 전체 초기화
//  [수정] 동기 리셋으로 통일
// ============================================================
module npu_conv2d_buf(
    input clk, reset_p,
    input start,
    input [7:0] pixel,
    input pixel_en,                         // [npu_v2] 외부 인에이블 신호
    output reg [9:0] buf_idx,
    output reg [7:0] value_00, value_01, value_02,
                     value_03, value_04, value_05,
                     value_06, value_07, value_08,
    output reg valid_buf
);
    localparam WIDTH = 28;
    (* ram_style = "distributed" *) reg [7:0] line_buf0 [0:WIDTH-1];
    (* ram_style = "distributed" *) reg [7:0] line_buf1 [0:WIDTH-1];

    reg [7:0] win00, win01, win02, win10, win11, win12, win20, win21, win22;
    reg [4:0] col_cnt, row_cnt;
    reg [1:0] state;
    localparam S_IDLE = 0, S_STREAM = 1;

    always @(posedge clk) begin                     // [수정] 동기 리셋
        if (reset_p) begin
            state   <= S_IDLE;
            col_cnt <= 0; row_cnt <= 0;
            buf_idx <= 0; valid_buf <= 0;
            // [npu_v2] 리셋 시 출력 전체 초기화
            {value_00, value_01, value_02,
             value_03, value_04, value_05,
             value_06, value_07, value_08} <= 0;
        end else begin
            valid_buf <= 0;
            case (state)
                S_IDLE: begin
                    if (start) state <= S_STREAM;
                    col_cnt <= 0; row_cnt <= 0; buf_idx <= 0;
                end

                S_STREAM: begin
                    if (pixel_en) begin             // [npu_v2] pixel_en 외부 제어
                        win02 <= pixel;              win01 <= win02; win00 <= win01;
                        win12 <= line_buf0[col_cnt]; win11 <= win12; win10 <= win11;
                        win22 <= line_buf1[col_cnt]; win21 <= win22; win20 <= win21;

                        line_buf1[col_cnt] <= line_buf0[col_cnt];
                        line_buf0[col_cnt] <= pixel;

                        if (row_cnt >= 2 && col_cnt >= 2) begin
                            valid_buf <= 1;
                            value_00 <= win20; value_01 <= win21; value_02 <= win22;
                            value_03 <= win10; value_04 <= win11; value_05 <= win12;
                            value_06 <= win00; value_07 <= win01; value_08 <= win02;
                        end

                        if (col_cnt == WIDTH-1) begin
                            col_cnt <= 0;
                            if (row_cnt == WIDTH-1) state <= S_IDLE;
                            else row_cnt <= row_cnt + 1;
                        end else col_cnt <= col_cnt + 1;

                        buf_idx <= buf_idx + 1;
                    end
                end
            endcase
        end
    end
endmodule


// ============================================================
//  (2) npu_conv2d_calc
//  [채택] 수정본: k==9 딜레이 클럭으로 마지막 누적 버그 수정
//  [채택] 수정본: 동기 리셋
//  [채택] 수정본: $signed 명시적 부호 처리
//  [수정] pixel_en 환경에서는 calc_busy 불필요 → busy 포트 제거
//         valid_buf 수신 즉시 버퍼 저장 (npu_v2 방식 유지)
//         단, busy 플래그는 내부적으로 유지하여 valid_buf 재진입 방지
// ============================================================
module npu_conv2d_calc(
    input clk, reset_p,
    input valid_buf,
    input [7:0] value_00, value_01, value_02, value_03, value_04,
                value_05, value_06, value_07, value_08,
    output reg signed [19:0] conv_out_0, conv_out_1, conv_out_2, conv_out_3, conv_out_4,
    output reg valid_out_calc
);
    reg signed [7:0] weight_0 [0:8], weight_1 [0:8], weight_2 [0:8],
                     weight_3 [0:8], weight_4 [0:8];
    reg signed [7:0] bias [0:4];

    initial begin
        $readmemh("55_conv2d_weights_filter_0.txt", weight_0);
        $readmemh("55_conv2d_weights_filter_1.txt", weight_1);
        $readmemh("55_conv2d_weights_filter_2.txt", weight_2);
        $readmemh("55_conv2d_weights_filter_3.txt", weight_3);
        $readmemh("55_conv2d_weights_filter_4.txt", weight_4);
        $readmemh("55_conv2d_bias.txt", bias);
    end

    // k: 0~8 = 누적 중, 9 = 누적 완료 대기(출력 클럭)
    reg [3:0] k;
    reg [2:0] f;
    reg signed [19:0] acc;
    reg [7:0] value_buf [0:8];
    reg busy;                               // 내부 busy (외부 노출 제거)

    always @(posedge clk) begin             // [수정] 동기 리셋
        if (reset_p) begin
            {conv_out_0, conv_out_1, conv_out_2, conv_out_3, conv_out_4} <= 0;
            valid_out_calc <= 0;
            k <= 0; f <= 0; acc <= 0; busy <= 0;
        end else begin
            valid_out_calc <= 0;

            if (valid_buf && !busy) begin
                // 새 픽셀 윈도우 수신
                value_buf[0] <= value_00; value_buf[1] <= value_01; value_buf[2] <= value_02;
                value_buf[3] <= value_03; value_buf[4] <= value_04; value_buf[5] <= value_05;
                value_buf[6] <= value_06; value_buf[7] <= value_07; value_buf[8] <= value_08;
                k <= 0; f <= 0; acc <= 0; busy <= 1;

            end else if (busy) begin

                if (k <= 8) begin
                    // ── 누적 단계 (k=0~8) ──────────────────────────
                    case (f)
                        0: acc <= acc + $signed({1'b0, value_buf[k]}) * weight_0[k];
                        1: acc <= acc + $signed({1'b0, value_buf[k]}) * weight_1[k];
                        2: acc <= acc + $signed({1'b0, value_buf[k]}) * weight_2[k];
                        3: acc <= acc + $signed({1'b0, value_buf[k]}) * weight_3[k];
                        4: acc <= acc + $signed({1'b0, value_buf[k]}) * weight_4[k];
                    endcase

                    if (k == 8)
                        k <= 9;             // [수정] k=8 누적 후 출력 클럭(k=9)으로 분리
                    else
                        k <= k + 1;

                end else begin
                    // ── 출력 단계 (k=9): acc에 k=0~8 전부 반영된 상태 ──
                    case (f)
                        0: conv_out_0 <= ($signed(acc) + $signed(bias[0]) < 0) ? 20'sd0  // [수정] $signed 명시
                                       : $signed(acc) + $signed(bias[0]);
                        1: conv_out_1 <= ($signed(acc) + $signed(bias[1]) < 0) ? 20'sd0
                                       : $signed(acc) + $signed(bias[1]);
                        2: conv_out_2 <= ($signed(acc) + $signed(bias[2]) < 0) ? 20'sd0
                                       : $signed(acc) + $signed(bias[2]);
                        3: conv_out_3 <= ($signed(acc) + $signed(bias[3]) < 0) ? 20'sd0
                                       : $signed(acc) + $signed(bias[3]);
                        4: begin
                            conv_out_4 <= ($signed(acc) + $signed(bias[4]) < 0) ? 20'sd0
                                        : $signed(acc) + $signed(bias[4]);
                            valid_out_calc <= 1;
                            busy <= 0;
                        end
                    endcase

                    acc <= 0;
                    k   <= 0;
                    f   <= f + 1;
                end
            end
        end
    end
endmodule


// ============================================================
//  (3) npu_maxpool_conv2d
//  [수정] 동기 리셋 (수정본), 로직 동일
// ============================================================
module npu_maxpool_conv2d(
    input clk, reset_p,
    input valid_calc,
    input signed [19:0] conv_out_0, conv_out_1, conv_out_2, conv_out_3, conv_out_4,
    output reg signed [19:0] max_value_0, max_value_1, max_value_2, max_value_3, max_value_4,
    output reg max_value_valid
);
    (* ram_style = "distributed" *) reg signed [19:0] line_buf_0 [0:12];
    (* ram_style = "distributed" *) reg signed [19:0] line_buf_1 [0:12];
    (* ram_style = "distributed" *) reg signed [19:0] line_buf_2 [0:12];
    (* ram_style = "distributed" *) reg signed [19:0] line_buf_3 [0:12];
    (* ram_style = "distributed" *) reg signed [19:0] line_buf_4 [0:12];

    reg [4:0] cnt_x, cnt_y;
    wire [3:0] buf_idx = cnt_x[4:1];

    always @(posedge clk) begin             // [수정] 동기 리셋
        if (reset_p) begin
            cnt_x <= 0; cnt_y <= 0;
            max_value_valid <= 0;
        end else begin
            max_value_valid <= 0;

            if (valid_calc) begin
                case ({cnt_y[0], cnt_x[0]})
                    2'b00: begin
                        line_buf_0[buf_idx] <= conv_out_0;
                        line_buf_1[buf_idx] <= conv_out_1;
                        line_buf_2[buf_idx] <= conv_out_2;
                        line_buf_3[buf_idx] <= conv_out_3;
                        line_buf_4[buf_idx] <= conv_out_4;
                    end
                    2'b01, 2'b10: begin
                        if (conv_out_0 > line_buf_0[buf_idx]) line_buf_0[buf_idx] <= conv_out_0;
                        if (conv_out_1 > line_buf_1[buf_idx]) line_buf_1[buf_idx] <= conv_out_1;
                        if (conv_out_2 > line_buf_2[buf_idx]) line_buf_2[buf_idx] <= conv_out_2;
                        if (conv_out_3 > line_buf_3[buf_idx]) line_buf_3[buf_idx] <= conv_out_3;
                        if (conv_out_4 > line_buf_4[buf_idx]) line_buf_4[buf_idx] <= conv_out_4;
                    end
                    2'b11: begin
                        max_value_0 <= (conv_out_0 > line_buf_0[buf_idx]) ? conv_out_0 : line_buf_0[buf_idx];
                        max_value_1 <= (conv_out_1 > line_buf_1[buf_idx]) ? conv_out_1 : line_buf_1[buf_idx];
                        max_value_2 <= (conv_out_2 > line_buf_2[buf_idx]) ? conv_out_2 : line_buf_2[buf_idx];
                        max_value_3 <= (conv_out_3 > line_buf_3[buf_idx]) ? conv_out_3 : line_buf_3[buf_idx];
                        max_value_4 <= (conv_out_4 > line_buf_4[buf_idx]) ? conv_out_4 : line_buf_4[buf_idx];
                        max_value_valid <= 1;
                    end
                endcase

                if (cnt_x == 25) begin
                    cnt_x <= 0;
                    if (cnt_y == 25) cnt_y <= 0;
                    else cnt_y <= cnt_y + 1;
                end else cnt_x <= cnt_x + 1;
            end
        end
    end
endmodule


// ============================================================
//  (4) npu_dense_integrated
//  [채택] 수정본: S_CALC에서 주소 고정, 읽기 요청만 발행
//                 S_CALC_PIPE 첫 진입 시 유효 데이터 보장
//  [채택] 수정본: S_NEXT에서 다음 뉴런 w_addr 명시적 점프
//  [채택] 수정본: 동기 리셋
// ============================================================
module npu_dense_integrated(
    input clk, reset_p,
    input max_value_valid,
    input signed [19:0] max_value_0, max_value_1, max_value_2, max_value_3, max_value_4,
    output reg signed [19:0] d_out_0, d_out_1, d_out_2, d_out_3, d_out_4,
    output reg dense_done
);
    localparam S_IDLE      = 3'd0,
               S_STORE     = 3'd1,
               S_CALC      = 3'd2,
               S_CALC_PIPE = 3'd3,
               S_NEXT      = 3'd4;
    reg [2:0] state;

    (* ram_style = "block" *) reg signed [19:0] flat_mem0 [0:168];
    (* ram_style = "block" *) reg signed [19:0] flat_mem1 [0:168];
    (* ram_style = "block" *) reg signed [19:0] flat_mem2 [0:168];
    (* ram_style = "block" *) reg signed [19:0] flat_mem3 [0:168];
    (* ram_style = "block" *) reg signed [19:0] flat_mem4 [0:168];

    (* ram_style = "block" *)       reg signed [7:0] w_rom [0:4224];
    (* ram_style = "distributed" *) reg signed [7:0] b_rom [0:4];

    initial begin
        $readmemh("55_dense_weights.txt", w_rom);
        $readmemh("55_dense_bias.txt",    b_rom);
    end

    reg [7:0]  wr_addr;
    reg [7:0]  rd_addr;
    reg [2:0]  mem_sel;
    reg [2:0]  n_ptr;
    reg [12:0] w_addr;
    reg signed [27:0] acc;
    reg signed [19:0] d_out_reg [0:4];
    reg is_last_req;

    // ── BRAM 동기 읽기: flat_mem ─────────────────────────────
    reg signed [19:0] flat_rd_data;
    always @(posedge clk) begin
        case (mem_sel)
            3'd0: flat_rd_data <= flat_mem0[rd_addr];
            3'd1: flat_rd_data <= flat_mem1[rd_addr];
            3'd2: flat_rd_data <= flat_mem2[rd_addr];
            3'd3: flat_rd_data <= flat_mem3[rd_addr];
            3'd4: flat_rd_data <= flat_mem4[rd_addr];
            default: flat_rd_data <= 20'sd0;
        endcase
    end

    // ── BRAM 동기 읽기: w_rom ────────────────────────────────
    reg signed [7:0] w_rd_data;
    always @(posedge clk) begin
        w_rd_data <= w_rom[w_addr];
    end

    // ── BRAM 쓰기 (읽기 always와 분리) ──────────────────────
    always @(posedge clk) begin
        if (state == S_STORE && max_value_valid) begin
            flat_mem0[wr_addr] <= max_value_0;
            flat_mem1[wr_addr] <= max_value_1;
            flat_mem2[wr_addr] <= max_value_2;
            flat_mem3[wr_addr] <= max_value_3;
            flat_mem4[wr_addr] <= max_value_4;
        end
    end

    // ── FSM (동기 리셋) ──────────────────────────────────────
    always @(posedge clk) begin
        if (reset_p) begin
            state        <= S_IDLE;
            wr_addr      <= 8'd0;  rd_addr <= 8'd0;
            mem_sel      <= 3'd0;  w_addr  <= 13'd0;
            acc          <= 28'sd0;
            dense_done   <= 1'b0;
            n_ptr        <= 3'd0;
            is_last_req  <= 1'b0;
            d_out_reg[0] <= 20'sd0; d_out_reg[1] <= 20'sd0;
            d_out_reg[2] <= 20'sd0; d_out_reg[3] <= 20'sd0;
            d_out_reg[4] <= 20'sd0;
        end else begin
            case (state)

                S_IDLE: begin
                    dense_done  <= 1'b0;
                    is_last_req <= 1'b0;
                    if (max_value_valid) state <= S_STORE;
                end

                S_STORE: begin
                    if (max_value_valid) begin
                        if (wr_addr == 8'd168) begin
                            wr_addr <= 8'd0;
                            rd_addr <= 8'd0;
                            mem_sel <= 3'd0;
                            w_addr  <= 13'd0;
                            state   <= S_CALC;
                        end else begin
                            wr_addr <= wr_addr + 8'd1;
                        end
                    end
                end

                // ── S_CALC ──────────────────────────────────
                // [수정본] 현재 rd_addr/mem_sel/w_addr로 읽기 요청만 발행
                //          주소는 변경하지 않음 → 다음 클럭 S_CALC_PIPE에서 데이터 도착
                S_CALC: begin
                    if (mem_sel == 3'd4 && rd_addr == 8'd168)
                        is_last_req <= 1'b1;

                    state <= S_CALC_PIPE;
                end

                // ── S_CALC_PIPE ─────────────────────────────
                // [수정본] flat_rd_data/w_rd_data 도착 → acc 누적
                //          is_last_req가 아니면 다음 주소 발행 후 루프
                S_CALC_PIPE: begin
                    acc <= acc + (flat_rd_data * w_rd_data);

                    if (is_last_req) begin
                        is_last_req <= 1'b0;
                        state       <= S_NEXT;
                    end else begin
                        w_addr <= w_addr + 13'd1;

                        if (mem_sel == 3'd4) begin
                            mem_sel <= 3'd0;
                            if (rd_addr == 8'd168) begin
                                rd_addr     <= 8'd0;
                                is_last_req <= 1'b1;
                            end else begin
                                rd_addr <= rd_addr + 8'd1;
                            end
                        end else begin
                            mem_sel <= mem_sel + 3'd1;
                        end

                        state <= S_CALC_PIPE;
                    end
                end

                // ── S_NEXT ──────────────────────────────────
                S_NEXT: begin
                    if ((acc + ($signed(b_rom[n_ptr]) <<< 7)) < 28'sd0)
                        d_out_reg[n_ptr] <= 20'sd0;
                    else
                        d_out_reg[n_ptr] <= (acc + ($signed(b_rom[n_ptr]) <<< 7)) >>> 7;

                    acc <= 28'sd0;

                    if (n_ptr == 3'd4) begin
                        n_ptr      <= 3'd0;
                        w_addr     <= 13'd0;
                        dense_done <= 1'b1;
                        state      <= S_IDLE;
                    end else begin
                        n_ptr   <= n_ptr + 3'd1;
                        rd_addr <= 8'd0;
                        mem_sel <= 3'd0;
                        // [수정본] 다음 뉴런 가중치 시작 주소 명시적 점프 (845 = 169 * 5)
                        w_addr  <= (n_ptr + 3'd1) * 13'd845;
                        state   <= S_CALC;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

    always @(*) begin
        d_out_0 = d_out_reg[0]; d_out_1 = d_out_reg[1];
        d_out_2 = d_out_reg[2]; d_out_3 = d_out_reg[3];
        d_out_4 = d_out_reg[4];
    end

endmodule


// ============================================================
//  (5) npu_output_layer
//  [채택] npu_v2: 간결한 단일 S_CALC 구조 (10클럭 순차 처리)
//  [수정] 동기 리셋 (수정본)
//  [수정] $signed 명시적 부호 처리로 안전성 강화
//
//  [설계 근거]
//  수정본의 5단계 파이프라인은 타이밍 마진을 늘리지만,
//  output_layer는 호출 빈도가 낮고(이미지 1장당 1회) 크리티컬
//  패스 길이도 허용 범위 내이므로 npu_v2의 단순 구조 채택.
//  단, 합성 시 타이밍 위반이 발생한다면 파이프라인 확장 권장.
// ============================================================
module npu_output_layer(
    input clk, reset_p,
    input dense_done,
    input signed [19:0] d_in_0, d_in_1, d_in_2, d_in_3, d_in_4,
    output reg [3:0] final_digit,
    output reg result_valid
);
    localparam S_IDLE = 0, S_CALC = 1, S_ARGMAX = 2;
    reg [1:0] state;

    reg signed [7:0] w1_rom [0:49];
    reg signed [7:0] b1_rom [0:9];

    initial begin
        $readmemh("55_dense_1_weights.txt", w1_rom);
        $readmemh("55_dense_1_bias.txt",    b1_rom);
    end

    reg [3:0] n_ptr;
    reg signed [27:0] scores [0:9];
    reg signed [27:0] max_score;
    integer i;

    always @(posedge clk) begin             // [수정] 동기 리셋
        if (reset_p) begin
            state        <= S_IDLE;
            n_ptr        <= 0;
            final_digit  <= 0;
            result_valid <= 0;
            max_score    <= 28'sh8000000;
            for (i = 0; i < 10; i = i + 1) scores[i] <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    result_valid <= 0;
                    if (dense_done) state <= S_CALC;
                end

                // [npu_v2] 단일 클럭 연산 구조 유지
                // [수정]   $signed 명시 추가로 부호 연산 안전성 강화
                S_CALC: begin
                    scores[n_ptr] <= ($signed(d_in_0) * $signed(w1_rom[n_ptr*5 + 0])) +
                                     ($signed(d_in_1) * $signed(w1_rom[n_ptr*5 + 1])) +
                                     ($signed(d_in_2) * $signed(w1_rom[n_ptr*5 + 2])) +
                                     ($signed(d_in_3) * $signed(w1_rom[n_ptr*5 + 3])) +
                                     ($signed(d_in_4) * $signed(w1_rom[n_ptr*5 + 4])) +
                                     ($signed(b1_rom[n_ptr]) <<< 7);

                    if (n_ptr == 9) begin
                        n_ptr <= 0;
                        state <= S_ARGMAX;
                    end else n_ptr <= n_ptr + 1;
                end

                S_ARGMAX: begin
                    if (scores[n_ptr] > max_score) begin
                        max_score   <= scores[n_ptr];
                        final_digit <= n_ptr;
                    end
                    if (n_ptr == 9) begin
                        n_ptr        <= 0;
                        max_score    <= 28'sh8000000;
                        result_valid <= 1;
                        state        <= S_IDLE;
                    end else n_ptr <= n_ptr + 1;
                end
            endcase
        end
    end
endmodule