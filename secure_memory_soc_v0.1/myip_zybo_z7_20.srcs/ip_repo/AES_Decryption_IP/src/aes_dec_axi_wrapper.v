`timescale 1ns / 1ps

module aes_dec_axi_wrapper (
    // System Clock & Reset
    input  wire aclk,
    input  wire aresetn,

    // ==========================================
    // 1. AXI4-Lite Slave Interface (복호화 키 설정)
    // ==========================================
    // 암호화 때와 동일한 키를 CPU가 설정해줍니다.
    input  wire [4:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,

    // ==========================================
    // 2. AXI4-Stream Slave (DRAM_1에서 오는 암호문)
    // ==========================================
    // 암호화된 데이터는 128비트 단위로 들어옵니다.
    input  wire [127:0] s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,

    // ==========================================
    // 3. AXI4-Stream Master (복구된 숫자 데이터 출력)
    // ==========================================
    // FND 컨트롤러로 보낼 원래의 숫자 데이터 (패딩 제거 전 128비트 전체 전달)
    output wire [127:0] m_axis_tdata, 
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready
);

    // --------------------------------------------------
    // [Part 1] 복호화 키 관리 (128비트)
    // --------------------------------------------------
    reg [31:0] key_reg0, key_reg1, key_reg2, key_reg3;
    wire [127:0] aes_key = {key_reg3, key_reg2, key_reg1, key_reg0};

    assign s_axi_awready = 1'b1;
    assign s_axi_wready  = 1'b1;
    assign s_axi_bresp   = 2'b00; // OKAY
    
    reg bvalid_reg;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)                                          bvalid_reg <= 0;
        else if (s_axi_awvalid && s_axi_wvalid && !bvalid_reg) bvalid_reg <= 1;
        else if (s_axi_bready)                                 bvalid_reg <= 0;
    end
    assign s_axi_bvalid = bvalid_reg;

    always @(posedge aclk or negedge aresetn)begin
        if (!aresetn) begin
            key_reg0 <= 0; key_reg1 <= 0; key_reg2 <= 0; key_reg3 <= 0;
        end else if (s_axi_awvalid && s_axi_wvalid) begin
            case (s_axi_awaddr[4:2])
                3'h0: key_reg0 <= s_axi_wdata;
                3'h1: key_reg1 <= s_axi_wdata;
                3'h2: key_reg2 <= s_axi_wdata;
                3'h3: key_reg3 <= s_axi_wdata;
            endcase
        end
    end

    // --------------------------------------------------
    // [Part 2] AES-128 Inverse Core 연동
    // --------------------------------------------------
    wire [127:0] dec_output;
    wire         dec_done;

    aes_128_inv_core u_aes_inv_core (
        .clk      (aclk),
        .reset_n  (aresetn),
        .key      (aes_key),
        .data_in  (s_axis_tdata),    // 128비트 암호문 입력
        .start    (s_axis_tvalid && s_axis_tready), 
        .data_out (dec_output),      // 복구된 128비트 데이터
        .done     (dec_done)
    );

    // --------------------------------------------------
    // [Part 3] AXI-Stream 제어 및 핸드쉐이킹
    // --------------------------------------------------
    // 코어가 완료되었거나 데이터가 없을 때 새 데이터를 받을 준비가 됨
    reg busy;
    wire start_pulse = s_axis_tvalid && s_axis_tready;
    
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)          busy <= 0;
        else if (start_pulse)  busy <= 1;
        else if (dec_done)     busy <= 0;
    end

    assign s_axis_tready = !busy && !output_valid;

    // 복호화가 완료되면 마스터 인터페이스를 통해 출력
    reg [127:0] output_reg;
    reg         output_valid;
    
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            output_valid <= 0;
            output_reg   <= 128'd0;
        end else if (dec_done) begin
            output_reg   <= dec_output;
            output_valid <= 1;
        end else if (m_axis_tready && output_valid) begin
            output_valid <= 0;
        end
    end
    
    assign m_axis_tdata  = output_reg;
    assign m_axis_tvalid = output_valid;

endmodule