`timescale 1ns / 1ps

/**
 * stream_write_master
 * 기능: FIFO에서 데이터를 꺼내 AXI4-Stream Master로 전송함.
 * 용도: 버전 A (DRAM_0 → NPU), 버전 C (DRAM_1 → 복호화IP)
 * 
 * ※ FWFT(First Word Fall Through) FIFO를 전제로 설계됨.
 *    데이터가 FIFO에 들어오는 즉시 i_w_data에 출력되는 방식.
 */
module stream_write_master #(
    parameter integer C_M_AXIS_DATA_WIDTH = 32   // 기본 32bit, 필요 시 128bit로 변경
)(
    input  wire clk,
    input  wire reset_n,

    // --- 사용자 제어 신호 ---
    input  wire        i_start,         // DMA 전송 시작 트리거
    input  wire [31:0] i_total_len,     // 전송할 총 바이트 수
    output reg         o_done,          // 전체 전송 완료 플래그

    // --- FIFO 인터페이스 (FWFT 모드) ---
    input  wire        i_fifo_empty,    // FIFO 비어있음 신호
    output wire        o_fifo_rd_en,    // FIFO 읽기 활성화 (pop)
    input  wire [C_M_AXIS_DATA_WIDTH-1:0] i_w_data,  // FIFO에서 꺼낸 데이터

    // --- AXI4-Stream Master ---
    output wire [C_M_AXIS_DATA_WIDTH-1:0] m_axis_tdata,   // 전송 데이터
    output wire        m_axis_tvalid,   // 데이터 유효 신호
    input  wire        m_axis_tready,   // 수신측 준비 완료 신호
    output wire        m_axis_tlast     // 마지막 데이터 표시
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
    // 전송 바이트 단위 수: DATA_WIDTH에 따라 한 beat당 바이트 수가 다름
    localparam BYTES_PER_BEAT = C_M_AXIS_DATA_WIDTH / 8;

    reg [31:0] r_remaining_bytes;   // 남은 전송 바이트 수

    // -------------------------------------------------------------------------
    // 3. AXI4-Stream 출력 (핵심 로직)
    // -------------------------------------------------------------------------
    // ACTIVE 상태이고 FIFO에 데이터가 있을 때만 tvalid 활성화
    assign m_axis_tvalid = (current_state == ACTIVE) && (!i_fifo_empty);

    // tvalid && tready 핸드셰이크 성립 시 FIFO에서 데이터를 pop
    assign o_fifo_rd_en  = m_axis_tvalid && m_axis_tready;

    // 데이터는 FIFO 출력 그대로 연결
    assign m_axis_tdata  = i_w_data;

    // 마지막 beat: 남은 바이트가 한 beat 이하일 때 tlast 활성화
    assign m_axis_tlast  = m_axis_tvalid && (r_remaining_bytes <= BYTES_PER_BEAT);

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
                if (m_axis_tlast && m_axis_tready)
                    next_state = IDLE;
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
                    if (m_axis_tvalid && m_axis_tready) begin
                        if (r_remaining_bytes <= BYTES_PER_BEAT) begin
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