`timescale 1ns / 1ps

/**
 * stream_read_master
 * 기능: AXI4-Stream Slave로 데이터를 수신하여 내부 FIFO로 전달함.
 * 용도: 버전 B (암호화IP 출력 → DRAM_1 저장)
 *
 * ※ C_S_AXIS_DATA_WIDTH > 32인 경우 (예: 128bit)
 *   한 beat를 수신한 뒤 32-bit 단위로 직렬화하여 FIFO에 push합니다.
 * ※ FWFT(First Word Fall Through) FIFO를 전제로 설계됨.
 */
module stream_read_master #(
    parameter integer C_S_AXIS_DATA_WIDTH = 32
)(
    input  wire clk,
    input  wire reset_n,

    // --- 사용자 제어 신호 ---
    input  wire        i_start,
    input  wire [31:0] i_total_len,
    output reg         o_done,

    // --- FIFO 인터페이스 (항상 32-bit) ---
    input  wire        i_fifo_full,
    output wire        o_fifo_push,
    output wire [31:0] o_r_data,

    // --- AXI4-Stream Slave ---
    input  wire [C_S_AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast
);

    // -------------------------------------------------------------------------
    // 1. 파라미터
    // -------------------------------------------------------------------------
    localparam BYTES_PER_BEAT  = C_S_AXIS_DATA_WIDTH / 8;  // 128bit → 16
    localparam WORDS_PER_BEAT  = C_S_AXIS_DATA_WIDTH / 32; // 128bit → 4

    // -------------------------------------------------------------------------
    // 2. FSM 상태 정의
    // -------------------------------------------------------------------------
    localparam IDLE      = 2'd0;
    localparam ACTIVE    = 2'd1;   // 스트림 beat 수신 대기
    localparam SERIALIZE = 2'd2;   // 수신한 beat를 32-bit씩 FIFO에 push

    reg [1:0] state;

    // -------------------------------------------------------------------------
    // 3. 내부 레지스터
    // -------------------------------------------------------------------------
    reg [31:0] r_remaining_bytes;
    reg [C_S_AXIS_DATA_WIDTH-1:0] beat_hold;  // 수신한 beat 래치
    reg [$clog2(WORDS_PER_BEAT):0] ser_cnt;   // 직렬화 카운터

    // -------------------------------------------------------------------------
    // 4. 출력 할당
    // -------------------------------------------------------------------------
    // 스트림 수신: ACTIVE 상태이고 FIFO에 공간이 있을 때만
    assign s_axis_tready = (state == ACTIVE) && (!i_fifo_full);

    // FIFO push: SERIALIZE 상태에서 FIFO에 공간이 있을 때
    assign o_fifo_push = (state == SERIALIZE) && (!i_fifo_full);

    // FIFO 데이터: beat_hold의 하위 32-bit
    assign o_r_data = beat_hold[31:0];

    // -------------------------------------------------------------------------
    // 5. FSM 및 데이터 처리
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state             <= IDLE;
            r_remaining_bytes <= 0;
            o_done            <= 0;
            beat_hold         <= 0;
            ser_cnt           <= 0;
        end else begin
            o_done <= 0;  // 기본 1-clock 펄스

            case (state)
                // ----- IDLE: 시작 대기 -----
                IDLE: begin
                    if (i_start) begin
                        r_remaining_bytes <= i_total_len;
                        ser_cnt           <= 0;
                        state             <= ACTIVE;
                    end
                end

                // ----- ACTIVE: 스트림 beat 수신 -----
                ACTIVE: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        beat_hold <= s_axis_tdata;
                        ser_cnt   <= 0;

                        if (WORDS_PER_BEAT == 1) begin
                            // 32-bit 스트림이면 직렬화 불필요
                            r_remaining_bytes <= r_remaining_bytes - BYTES_PER_BEAT;
                            if (s_axis_tlast || (r_remaining_bytes <= BYTES_PER_BEAT)) begin
                                o_done <= 1;
                                state  <= IDLE;
                            end
                        end else begin
                            // 128-bit 등 → 직렬화 단계로
                            state <= SERIALIZE;
                        end
                    end
                end

                // ----- SERIALIZE: 128-bit → 4 × 32-bit FIFO push -----
                SERIALIZE: begin
                    if (!i_fifo_full) begin
                        // shift right 32 bits for next word
                        beat_hold <= {{32{1'b0}}, beat_hold[C_S_AXIS_DATA_WIDTH-1:32]};
                        ser_cnt   <= ser_cnt + 1;

                        if (ser_cnt == WORDS_PER_BEAT - 1) begin
                            // 마지막 word push 완료
                            r_remaining_bytes <= r_remaining_bytes - BYTES_PER_BEAT;

                            if (r_remaining_bytes <= BYTES_PER_BEAT) begin
                                o_done <= 1;
                                state  <= IDLE;
                            end else begin
                                state  <= ACTIVE;  // 다음 beat 수신
                            end
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
