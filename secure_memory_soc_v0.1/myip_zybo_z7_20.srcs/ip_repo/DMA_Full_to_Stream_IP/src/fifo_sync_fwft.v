`timescale 1ns / 1ps

/**
 * fifo_sync_fwft
 * 기능: 동기식 FWFT(First Word Fall Through) FIFO
 * 특징: Xilinx FIFO Generator IP 의존성 없이 순수 RTL로 구현
 * 용도: DMA_Full_to_Stream_IP, DMA_Stream_to_Full_IP 내부 버퍼
 *
 * FWFT 동작:
 *   - 데이터가 들어오는 즉시 dout에 출력됨
 *   - rd_en이 활성화되면 다음 데이터로 넘어감
 *   - empty가 0이면 dout의 데이터는 항상 유효
 */
module fifo_sync_fwft #(
    parameter DATA_WIDTH = 32,
    parameter FIFO_DEPTH = 1024,                        // 반드시 2의 거듭제곱
    parameter ADDR_WIDTH = $clog2(FIFO_DEPTH)           // 자동 계산 (1024 → 10)
)(
    input  wire                  clk,
    input  wire                  srst,       // 동기 리셋 (Active High)

    // Write 포트
    input  wire [DATA_WIDTH-1:0] din,
    input  wire                  wr_en,
    output wire                  full,

    // Read 포트
    output wire [DATA_WIDTH-1:0] dout,
    input  wire                  rd_en,
    output wire                  empty
);

    // -------------------------------------------------------------------------
    // 1. 내부 메모리 및 포인터
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    reg [ADDR_WIDTH:0] wr_ptr;  // MSB는 wrap-around 감지용
    reg [ADDR_WIDTH:0] rd_ptr;

    wire [ADDR_WIDTH-1:0] wr_addr = wr_ptr[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] rd_addr = rd_ptr[ADDR_WIDTH-1:0];

    // -------------------------------------------------------------------------
    // 2. Full / Empty 판단
    // -------------------------------------------------------------------------
    // Full:  포인터 상위 비트(wrap bit)가 다르고 하위 주소가 같을 때
    // Empty: 포인터 전체가 같을 때
    assign full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                   (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    assign empty = (wr_ptr == rd_ptr);

    // -------------------------------------------------------------------------
    // 3. Write 포트
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (srst) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            mem[wr_addr] <= din;
            wr_ptr       <= wr_ptr + 1;
        end
    end

    // -------------------------------------------------------------------------
    // 4. Read 포트 (FWFT 구현)
    // -------------------------------------------------------------------------
    // FWFT: rd_ptr이 가리키는 데이터를 dout에 즉시 출력
    // rd_en이 들어오면 포인터만 증가
    assign dout = mem[rd_addr];

    always @(posedge clk) begin
        if (srst) begin
            rd_ptr <= 0;
        end else if (rd_en && !empty) begin
            rd_ptr <= rd_ptr + 1;
        end
    end

endmodule