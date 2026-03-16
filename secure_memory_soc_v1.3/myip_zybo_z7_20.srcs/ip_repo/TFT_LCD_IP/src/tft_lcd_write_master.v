`timescale 1ns / 1ps

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

    // BRAM 읽기 포트
    output reg  [7:0]  o_bram_rd_addr,  // 0 ~ 195 (32-bit 단위 주소)
    input  wire [31:0] i_bram_rd_data,  // 32-bit 데이터

    // AXI4-Full Write
    // AW Channel
    output reg  [C_M_AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]                    m_axi_awlen,
    output wire [2:0]                    m_axi_awsize,
    output wire [1:0]                    m_axi_awburst,
    output reg                           m_axi_awvalid,
    input  wire                          m_axi_awready,
    // W Channel
    output reg  [C_M_AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output reg                           m_axi_wlast,
    output reg                           m_axi_wvalid,
    input  wire                          m_axi_wready,
    // B Channel
    input  wire [1:0]                    m_axi_bresp,
    input  wire                          m_axi_bvalid,
    output wire                          m_axi_bready
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
    reg [31:0] beats_sent;      // 지금까지 전송한 총 beat 수
    reg [7:0]  burst_cnt;       // 현재 버스트 내 beat 카운터
    reg [7:0]  cur_burst_len;   // 이번 버스트의 실제 beat 수
    reg [31:0] cur_dst_addr;    // 현재 버스트 시작 주소

    // ★ Y축 반전용: 행 내 워드 위치 카운터 (0~6, 한 행 = 7워드 = 28픽셀)
    reg [2:0]  col_in_row;

    // 상태 선언부 변경 (fetch_state를 2비트로)
    localparam FETCH_ADDR  = 2'd0,
               FETCH_WAIT  = 2'd1,
               FETCH_READY = 2'd2;
    reg [1:0] fetch_state;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state          <= IDLE;
            beats_sent     <= 0;
            burst_cnt      <= 0;
            cur_burst_len  <= BURST_LEN;
            cur_dst_addr   <= 0;
            o_bram_rd_addr <= 0;
            col_in_row     <= 0;
            fetch_state    <= FETCH_WAIT;
            o_write_done   <= 0;
            m_axi_awvalid  <= 0;
            m_axi_awaddr   <= 0;
            m_axi_wvalid   <= 0;
            m_axi_wlast    <= 0;
            m_axi_wdata    <= 0;
        end else begin
            o_write_done <= 0; // 기본 0

            case (state)
                // -----------------------------------------------
                IDLE: begin
                    if (i_start) begin
                        cur_dst_addr   <= i_dst_addr;
                        beats_sent     <= 0;
                        o_bram_rd_addr <= 8'd189; // ★ row 27부터 시작 (27*7=189)
                        col_in_row     <= 3'd0;
                        fetch_state    <= FETCH_ADDR;
                        
                        // 첫 버스트 길이 결정
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
                        fetch_state   <= FETCH_ADDR;
                        state         <= DATA;
                    end
                end

                // -----------------------------------------------
                // W 채널: BRAM에서 32bit 통째로 읽어서 바로 쏘기
                DATA: begin
                    case (fetch_state)
                        FETCH_ADDR: begin
                            // o_bram_rd_addr는 이미 셋업됨. BRAM이 데이터를 꺼낼 1클럭 대기
                            fetch_state <= FETCH_WAIT;
                        end
                        
                        FETCH_WAIT: begin
                            // ★ Q7 정규화: 0xFF(255) → 0x80(128=1.0), 0x00 → 0x00
                            //   학습 시 x/255 정규화 사용 → Q7에서 1.0 = 128
                            //   LCD 표시용 BRAM(0xFF)은 그대로, NPU행 값만 변환
                            m_axi_wdata[ 7: 0] <= (i_bram_rd_data[ 7: 0] != 8'd0) ? 8'h80 : 8'h00;
                            m_axi_wdata[15: 8] <= (i_bram_rd_data[15: 8] != 8'd0) ? 8'h80 : 8'h00;
                            m_axi_wdata[23:16] <= (i_bram_rd_data[23:16] != 8'd0) ? 8'h80 : 8'h00;
                            m_axi_wdata[31:24] <= (i_bram_rd_data[31:24] != 8'd0) ? 8'h80 : 8'h00;
                            m_axi_wvalid <= 1;
                            m_axi_wlast  <= (burst_cnt == cur_burst_len - 1);
                            fetch_state  <= FETCH_READY;
                        end
            
                        FETCH_READY: begin
                            if (m_axi_wready && m_axi_wvalid) begin
                                m_axi_wvalid   <= 0;
                                m_axi_wlast    <= 0;
                                beats_sent     <= beats_sent + 1;
                                burst_cnt      <= burst_cnt + 1;

                                // ★ Y축 반전: 행 내에서는 +1, 행 끝(col=6)이면 이전 행 시작으로 점프
                                if (col_in_row == 3'd6) begin
                                    col_in_row     <= 3'd0;
                                    o_bram_rd_addr <= o_bram_rd_addr - 8'd13; // 현재행 시작 - 7 = 이전행 시작
                                end else begin
                                    col_in_row     <= col_in_row + 1;
                                    o_bram_rd_addr <= o_bram_rd_addr + 1;
                                end
                                
                                if (burst_cnt == cur_burst_len - 1) begin
                                    state <= RESP;
                                end else begin
                                    fetch_state <= FETCH_ADDR; // 다시 다음 데이터 주소부터 대기
                                end
                            end
                        end
                    endcase
                end

                // -----------------------------------------------
                // B 채널: 응답 수신 후 다음 버스트 or 완료
                RESP: begin
                    if (m_axi_bvalid) begin
                        cur_dst_addr <= cur_dst_addr + (cur_burst_len * 4);
                        if (beats_sent >= total_beats) begin
                            state <= DONE;
                        end else begin
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