`timescale 1ns / 1ps

/**
 * stream_read_master
 * 기능: AXI4-Stream Slave로 데이터를 수신하여 내부 FIFO로 전달함.
 * 용도: 버전 B (암호화IP 출력 → DRAM_1 저장)
 *
 * ※ FWFT(First Word Fall Through) FIFO를 전제로 설계됨.
 * ※ 흐름 제어: FIFO가 가득 차면 tready를 내려 업스트림(암호화IP)을 자동으로 멈춤.
 */
module stream_read_master #(
    parameter integer C_S_AXIS_DATA_WIDTH = 32   // 기본 32bit, 필요 시 128bit로 변경
)(
    input  wire clk,
    input  wire reset_n,

    // --- 사용자 제어 신호 ---
    input  wire        i_start,         // 수신 시작 트리거
    input  wire [31:0] i_total_len,     // 수신할 총 바이트 수
    output reg         o_done,          // 전체 수신 완료 플래그

    // --- FIFO 인터페이스 ---
    input  wire        i_fifo_full,     // FIFO 가득 참 신호 (Backpressure 용)
    output wire        o_fifo_push,     // FIFO 쓰기 활성화 (push)
    output wire [C_S_AXIS_DATA_WIDTH-1:0] o_r_data,  // FIFO로 보낼 데이터

    // --- AXI4-Stream Slave ---
    input  wire [C_S_AXIS_DATA_WIDTH-1:0] s_axis_tdata,   // 수신 데이터
    input  wire        s_axis_tvalid,   // 데이터 유효 신호
    output wire        s_axis_tready,   // 수신 준비 완료 신호
    input  wire        s_axis_tlast     // 마지막 데이터 표시
);

    // -------------------------------------------------------------------------
    // 1. FSM 상태 정의
    // -------------------------------------------------------------------------
    localparam IDLE   = 2'b01;
    localparam ACTIVE = 2'b10;

    reg [1:0] current_state, next_state;

    // -------------------------------------------------------------------------
    // 2. 내부 레지스터
    // -------------------------------------------------------------------------
    localparam BYTES_PER_BEAT = C_S_AXIS_DATA_WIDTH / 8;

    reg [31:0] r_remaining_bytes;   // 남은 수신 바이트 수

    // -------------------------------------------------------------------------
    // 3. AXI4-Stream 입력 처리 (핵심 로직)
    // -------------------------------------------------------------------------
    // ACTIVE 상태이고 FIFO에 공간이 있을 때만 tready 활성화
    // → FIFO가 가득 차면 tready가 내려가 업스트림을 자동으로 멈춤 (Backpressure)
    assign s_axis_tready = (current_state == ACTIVE) && (!i_fifo_full);

    // tvalid && tready 핸드셰이크 성립 시 FIFO에 push
    assign o_fifo_push   = s_axis_tvalid && s_axis_tready;

    // 데이터는 Stream 입력 그대로 FIFO로 전달
    assign o_r_data      = s_axis_tdata;

    // -------------------------------------------------------------------------
    // 4. 상태 천이 로직 (Combinational)
    // -------------------------------------------------------------------------
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (i_start) next_state = ACTIVE;
            end
            ACTIVE: begin
                // 마지막 beat 핸드셰이크 완료 시 종료
                // tlast 유무와 관계없이 총 바이트 수 기준으로도 종료 가능
                if (s_axis_tvalid && s_axis_tready) begin
                    if (s_axis_tlast || (r_remaining_bytes <= BYTES_PER_BEAT))
                        next_state = IDLE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // 5. 레지스터 업데이트 (Sequential)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_state     <= IDLE;
            r_remaining_bytes <= 0;
            o_done            <= 0;
        end else begin
            current_state <= next_state;
            o_done        <= 0;     // 기본적으로 1클럭 펄스

            case (current_state)
                IDLE: begin
                    if (i_start) begin
                        r_remaining_bytes <= i_total_len;
                    end
                end

                ACTIVE: begin
                    // 핸드셰이크 성립 시마다 잔여 바이트 차감
                    if (s_axis_tvalid && s_axis_tready) begin
                        if (s_axis_tlast || (r_remaining_bytes <= BYTES_PER_BEAT)) begin
                            r_remaining_bytes <= 0;
                            o_done            <= 1; // 1클럭 완료 펄스
                        end else begin
                            r_remaining_bytes <= r_remaining_bytes - BYTES_PER_BEAT;
                        end
                    end
                end
            endcase
        end
    end

endmodule