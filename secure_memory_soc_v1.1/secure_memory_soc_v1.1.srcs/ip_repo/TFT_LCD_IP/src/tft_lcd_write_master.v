`timescale 1ns / 1ps

/**
 * tft_lcd_write_master  (v2 — 1픽셀 1 beat 방식)
 *
 * [수정 이유]
 *   기존: 8-bit 픽셀 4개를 32-bit로 packed → Word[0]에 pixel[0..3]
 *   NPU : buf_idx * 4 byte 주소에서 [7:0]만 사용
 *         → 기존 방식이면 pixel[0], pixel[4], pixel[8] ... (4칸 건너뜀)
 *
 *   수정: 1픽셀을 {24'b0, pixel} 형태로 개별 word에 저장
 *         total_beats = i_total_len (784), 1beat = 1pixel
 *         → NPU buf_idx=N → addr N*4 → [7:0] = pixel[N] ✓
 *
 * 동작 순서: IDLE → ADDR (AW) → DATA (W, burst) → RESP (B) → DONE
 */
module tft_lcd_write_master #(
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32,
    parameter integer BURST_LEN          = 16
)(
    input  wire clk,
    input  wire reset_n,

    input  wire        i_start,
    input  wire [31:0] i_dst_addr,
    input  wire [31:0] i_total_len,   // 전송할 픽셀 수 (= beat 수, 보통 784)
    output reg         o_write_done,

    output reg  [9:0]  o_bram_rd_addr,
    input  wire [7:0]  i_bram_rd_data,

    output reg  [C_M_AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]                     m_axi_awlen,
    output wire [2:0]                     m_axi_awsize,
    output wire [1:0]                     m_axi_awburst,
    output reg                            m_axi_awvalid,
    input  wire                           m_axi_awready,
    output reg  [C_M_AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    output reg                            m_axi_wlast,
    output reg                            m_axi_wvalid,
    input  wire                           m_axi_wready,
    input  wire [1:0]                     m_axi_bresp,
    input  wire                           m_axi_bvalid,
    output wire                           m_axi_bready
);

    assign m_axi_awsize  = 3'b010;                          // 4 bytes/beat
    assign m_axi_awburst = 2'b01;                           // INCR
    assign m_axi_wstrb   = {(C_M_AXI_DATA_WIDTH/8){1'b1}};
    assign m_axi_bready  = 1'b1;
    assign m_axi_awlen   = cur_burst_len - 1;               // 0-indexed

    // total_beats = 픽셀 수 (i_total_len beats, 각 beat = 1 pixel)
    wire [31:0] total_beats = i_total_len;  // ★ 기존 >> 2 제거

    localparam IDLE = 3'd0, ADDR = 3'd1, DATA = 3'd2, RESP = 3'd3, DONE = 3'd4;

    reg [2:0]  state;
    reg [31:0] beats_sent;
    reg [7:0]  burst_cnt;
    reg [7:0]  cur_burst_len;
    reg [31:0] cur_dst_addr;
    reg [9:0]  pixel_ptr;     // 현재 읽을 BRAM 픽셀 주소 (0~783)
    reg        rd_valid;      // BRAM 읽기 1-cycle 지연 보상 플래그

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state          <= IDLE;
            beats_sent     <= 0;
            burst_cnt      <= 0;
            cur_burst_len  <= BURST_LEN;
            cur_dst_addr   <= 0;
            pixel_ptr      <= 0;
            rd_valid       <= 0;
            o_write_done   <= 0;
            m_axi_awvalid  <= 0;
            m_axi_awaddr   <= 0;
            m_axi_wvalid   <= 0;
            m_axi_wlast    <= 0;
            m_axi_wdata    <= 0;
            o_bram_rd_addr <= 0;
        end else begin
            o_write_done <= 0;

            case (state)
                // ---------------------------------------------------
                IDLE: begin
                    if (i_start) begin
                        cur_dst_addr  <= i_dst_addr;
                        beats_sent    <= 0;
                        pixel_ptr     <= 0;
                        burst_cnt     <= 0;
                        rd_valid      <= 0;
                        cur_burst_len <= (total_beats < BURST_LEN)
                                         ? total_beats[7:0] : BURST_LEN;
                        state         <= ADDR;
                    end
                end

                // ---------------------------------------------------
                ADDR: begin
                    // BRAM 읽기 선발행 (1-cycle 지연 보상)
                    o_bram_rd_addr <= pixel_ptr;
                    rd_valid       <= 0;
                    m_axi_awaddr   <= cur_dst_addr;
                    m_axi_awvalid  <= 1;
                    if (m_axi_awready && m_axi_awvalid) begin
                        m_axi_awvalid <= 0;
                        burst_cnt     <= 0;
                        rd_valid      <= 0;
                        state         <= DATA;
                    end
                end

                // ---------------------------------------------------
                // ★ 핵심 변경: 4바이트 패킹 제거
                //   1클럭 = 1픽셀, wdata = {24'b0, pixel}
                DATA: begin
                    if (!rd_valid) begin
                        // 첫 진입: BRAM 주소 이미 발행됨, 다음 클럭에 데이터 나옴
                        rd_valid <= 1;
                    end else begin
                        // BRAM 데이터 유효
                        m_axi_wvalid <= 1;
                        m_axi_wdata  <= {24'b0, i_bram_rd_data};  // ★ zero-pad
                        m_axi_wlast  <= (burst_cnt == cur_burst_len - 1);

                        if (m_axi_wready && m_axi_wvalid) begin
                            beats_sent   <= beats_sent + 1;
                            burst_cnt    <= burst_cnt  + 1;
                            pixel_ptr    <= pixel_ptr  + 1;
                            m_axi_wvalid <= 0;
                            m_axi_wlast  <= 0;

                            // 다음 픽셀 BRAM 주소 선발행
                            o_bram_rd_addr <= pixel_ptr + 1;
                            rd_valid       <= 0;  // 다음 클럭에 데이터 필요

                            if (burst_cnt == cur_burst_len - 1) begin
                                state <= RESP;
                            end
                        end
                    end
                end

                // ---------------------------------------------------
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
                            // 다음 버스트 첫 픽셀 BRAM 주소 선발행
                            o_bram_rd_addr <= pixel_ptr;
                            rd_valid       <= 0;
                            state          <= ADDR;
                        end
                    end
                end

                // ---------------------------------------------------
                DONE: begin
                    o_write_done <= 1;
                    state        <= IDLE;
                end
            endcase
        end
    end

endmodule
