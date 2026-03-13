`timescale 1ns / 1ps

module aes_enc_axi_wrapper(
    input  wire aclk,
    input  wire aresetn,

    // 1. AXI4-Lite Slave (키 설정)
    input  wire [4:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,

    // 2. AXI4-Stream Slave (NPU 입력)
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    // 3. AXI4-Stream Master (암호화 출력) 
    output wire [127:0] m_axis_tdata, 
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready
);

    // [Part 1] 키 관리 로직 
    reg [31:0] key_reg0, key_reg1, key_reg2, key_reg3;
    wire [127:0] aes_key = {key_reg3, key_reg2, key_reg1, key_reg0};
    
    assign s_axi_awready = 1'b1;
    assign s_axi_wready  = 1'b1;
    assign s_axi_bresp   = 2'b00;
    
    reg bvalid_reg;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            bvalid_reg <= 0;
        else if (s_axi_awvalid && s_axi_wvalid && !bvalid_reg)
            bvalid_reg <= 1;           // 쓰기 수신 완료 → response 준비
        else if (s_axi_bready)
            bvalid_reg <= 0;           // 마스터가 response 수신 확인
    end
    assign s_axi_bvalid = bvalid_reg;

    always @(posedge aclk or negedge aresetn) begin
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

    // [Part 2] AES-128 Core 연동 
    
    wire [127:0] aes_output;
    wire         aes_done;
    
    aes_128_core u_aes_core (
        .clk      (aclk),
        .reset_n  (aresetn),
        .key      (aes_key),
        .data_in ({96'd0, s_axis_tdata}),
        .start    (s_axis_tvalid && s_axis_tready), // 준비되었을 때만 시작
        .data_out (aes_output),
        .done     (aes_done)
    );

    // [Part 3] AXI-Stream 제어 보강
    wire start_pulse = s_axis_tvalid && s_axis_tready;
     
    reg busy;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)          busy <= 0;
        else if (start_pulse)  busy <= 1;  // 연산 시작
        else if (aes_done)     busy <= 0;  // 연산 완료
    end
    
    assign s_axis_tready = !busy && !output_valid;
    
    // 암호화 완료 시 출력 유효
    reg [127:0] output_reg;
    reg         output_valid;
    
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            output_valid <= 0;
        end else if (aes_done) begin
            output_reg   <= aes_output;  // done 시점에 래치
            output_valid <= 1;
        end else if (m_axis_tready && output_valid) begin
            output_valid <= 0;           // 핸드셰이크 완료 후 해제
        end
    end
    
    assign m_axis_tdata  = output_reg;
    assign m_axis_tvalid = output_valid;

endmodule