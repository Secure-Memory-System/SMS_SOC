`timescale 1ns / 1ps

/**
 * write_master
 * 기능: 외부에서 주어진 데이터(BRAM 포트)를 AXI4-Full Burst Write로 메모리에 저장.
 *
 * 동작 순서:
 *   IDLE → ADDR (AW 채널) → DATA (W 채널, burst) → RESP (B 채널) → DONE
 *
 * 파라미터:
 *   BURST_LEN  : 한 번의 버스트에 전송할 beat 수 (최대 256)
 *   TOTAL_BEATS: 전송할 총 beat 수 (28*28=784 bytes → 196 beats @32bit)
 */
module tft_lcd_write_master #(
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32,
    parameter integer BURST_LEN          = 16   // 한 버스트당 beat 수 (조정 가능)
)(
    input  wire clk,
    input  wire reset_n,

    // 제어
    input  wire        i_start,       // 1클럭 start 펄스
    input  wire [31:0] i_dst_addr,    // 목적지 메모리 주소
    input  wire [31:0] i_total_len,   // 전송할 총 바이트 수 (784)
    output reg         o_write_done,  // 완료 펄스 (1클럭)

    // BRAM 읽기 포트 (tft_lcd_top의 ext_rd_addr/ext_rd_data)
    output reg  [9:0]  o_bram_rd_addr,
    input  wire [7:0]  i_bram_rd_data,

    // AXI4-Full Write
    // AW Channel
    output reg  [C_M_AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]                     m_axi_awlen,
    output wire [2:0]                     m_axi_awsize,
    output wire [1:0]                     m_axi_awburst,
    output reg                            m_axi_awvalid,
    input  wire                           m_axi_awready,
    // W Channel
    output reg  [C_M_AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output reg                            m_axi_wlast,
    output reg                            m_axi_wvalid,
    input  wire                           m_axi_wready,
    // B Channel
    input  wire [1:0]                     m_axi_bresp,
    input  wire                           m_axi_bvalid,
    output wire                           m_axi_bready
);

    // 고정 설정
    assign m_axi_awsize  = 3'b010;                 // 4 bytes per beat
    assign m_axi_awburst = 2'b01;                  // INCR
    assign m_axi_wstrb   = {(C_M_AXI_DATA_WIDTH/8){1'b1}};
    assign m_axi_bready  = 1'b1;                   // 항상 응답 수락

    // awlen은 cur_burst_len 레지스터로 동적 결정 (마지막 버스트 나머지 처리)
    assign m_axi_awlen = cur_burst_len - 1;        // 0-indexed

    // 총 beat 수 계산 (바이트 수 / 4)
    wire [31:0] total_beats = i_total_len >> 2;    // 784 / 4 = 196

    // FSM 상태
    localparam IDLE  = 3'd0,
               ADDR  = 3'd1,
               DATA  = 3'd2,
               RESP  = 3'd3,
               DONE  = 3'd4;

    reg [2:0]  state;
    reg [31:0] beats_sent;      // 지금까지 전송한 beat 수
    reg [7:0]  burst_cnt;       // 현재 버스트 내 beat 카운터
    reg [7:0]  cur_burst_len;   // 이번 버스트의 실제 beat 수 (마지막 버스트 나머지 대응)
    reg [31:0] cur_dst_addr;    // 현재 버스트 시작 주소

    // BRAM 주소는 beat 단위 (32bit = 4bytes → bram_addr는 byte 단위이므로 *4)
    // 단, 내부 BRAM은 8bit 폭이므로 beats_sent * 4 가 bram byte 주소
    // ext_rd_addr는 10비트(0~783), 여기서는 byte 순서로 읽고 32bit 패킹
    reg [9:0]  byte_ptr;        // 현재 읽고 있는 BRAM byte 주소 (0~783)
    reg [1:0]  pack_cnt;        // 4바이트 패킹 카운터
    reg [31:0] packed_data;     // 패킹 중인 32bit 워드

    // 패킹 상태
    localparam PACK_IDLE  = 2'd0,
               PACK_READ  = 2'd1,
               PACK_READY = 2'd2;
    reg [1:0] pack_state;
    reg       data_ready;       // 32bit 워드 준비 완료

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= IDLE;
            beats_sent    <= 0;
            burst_cnt     <= 0;
            cur_burst_len <= BURST_LEN;
            cur_dst_addr  <= 0;
            byte_ptr     <= 0;
            pack_cnt     <= 0;
            packed_data  <= 0;
            pack_state   <= PACK_IDLE;
            data_ready   <= 0;
            o_write_done <= 0;
            m_axi_awvalid <= 0;
            m_axi_awaddr  <= 0;
            m_axi_wvalid  <= 0;
            m_axi_wlast   <= 0;
            m_axi_wdata   <= 0;
            o_bram_rd_addr <= 0;
        end else begin
            o_write_done <= 0; // 기본 0

            case (state)
                // -----------------------------------------------
                IDLE: begin
                    if (i_start) begin
                        cur_dst_addr  <= i_dst_addr;
                        beats_sent    <= 0;
                        byte_ptr      <= 0;
                        pack_cnt      <= 0;
                        pack_state    <= PACK_IDLE;
                        data_ready    <= 0;
                        // 첫 버스트 길이 결정: total_beats < BURST_LEN이면 나머지만
                        cur_burst_len <= (total_beats < BURST_LEN) ? total_beats[7:0] : BURST_LEN;
                        state         <= ADDR;
                    end
                end

                // -----------------------------------------------
                // AW 채널: 버스트 주소 발행
                ADDR: begin
                    m_axi_awaddr  <= cur_dst_addr;
                    m_axi_awvalid <= 1;
                    if (m_axi_awready && m_axi_awvalid) begin
                        m_axi_awvalid <= 0;
                        burst_cnt     <= 0;
                        state         <= DATA;
                    end
                end

                // -----------------------------------------------
                // W 채널: 버스트 데이터 전송
                // BRAM은 8bit이므로 4클럭마다 32bit 워드 1개 조립
                DATA: begin
                    // --- BRAM 4바이트 패킹 ---
                    case (pack_state)
                        PACK_IDLE: begin
                            data_ready <= 0;
                            o_bram_rd_addr <= byte_ptr;
                            pack_state     <= PACK_READ;
                            pack_cnt       <= 0;
                            packed_data    <= 0;
                        end

                        PACK_READ: begin
                            // 매 클럭 1바이트 읽어서 32bit에 쌓기
                            packed_data <= {i_bram_rd_data, packed_data[31:8]};
                            pack_cnt    <= pack_cnt + 1;
                            if (pack_cnt < 3) begin
                                o_bram_rd_addr <= byte_ptr + pack_cnt + 1;
                            end else begin
                                // 4바이트 완성
                                data_ready <= 1;
                                pack_state <= PACK_READY;
                            end
                        end

                        PACK_READY: begin
                            // data_ready=1, wvalid 올리기
                        end
                    endcase

                    // --- AXI W 채널 핸드셰이크 ---
                    if (data_ready) begin
                        m_axi_wvalid <= 1;
                        m_axi_wdata  <= packed_data;
                        // wlast: 현재 버스트의 마지막 beat (cur_burst_len 기준)
                        m_axi_wlast  <= (burst_cnt == cur_burst_len - 1);

                        if (m_axi_wready && m_axi_wvalid) begin
                            beats_sent   <= beats_sent + 1;
                            burst_cnt    <= burst_cnt + 1;
                            byte_ptr     <= byte_ptr + 4;
                            data_ready   <= 0;
                            pack_state   <= PACK_IDLE;
                            m_axi_wvalid <= 0;
                            m_axi_wlast  <= 0;

                            if (burst_cnt == cur_burst_len - 1) begin
                                // 버스트 완료 → B채널 응답 대기
                                state <= RESP;
                            end
                        end
                    end
                end

                // -----------------------------------------------
                // B 채널: 응답 수신 후 다음 버스트 or 완료
                RESP: begin
                    if (m_axi_bvalid) begin
                        cur_dst_addr <= cur_dst_addr + (cur_burst_len * 4);
                        if (beats_sent >= total_beats) begin
                            state <= DONE;
                        end else begin
                            // 남은 beat가 BURST_LEN보다 적으면 나머지만 전송
                            cur_burst_len <= ((total_beats - beats_sent) < BURST_LEN)
                                            ? (total_beats - beats_sent)
                                            : BURST_LEN;
                            burst_cnt <= 0;
                            state     <= ADDR;
                        end
                    end
                end

                // -----------------------------------------------
                DONE: begin
                    o_write_done <= 1;
                    state        <= IDLE;
                end
            endcase
        end
    end

endmodule