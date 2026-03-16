`timescale 1ns / 1ps

module aes_dec_axi_wrapper (
    // System Clock & Reset
    input  wire aclk,
    input  wire aresetn,

    // ==========================================
    // 1. AXI4-Lite Slave Interface (복호화 키 설정)
    // ==========================================
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
    // 2. AXI4-Stream Slave (DRAM에서 오는 암호문)
    // ==========================================
    input  wire [127:0] s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,

    // ==========================================
    // 3. AXI4-Stream Master (복구된 숫자 데이터 출력)
    // ==========================================
    output wire [127:0]   m_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready
);

    // --------------------------------------------------
    // [Part 1] 복호화 키 관리 (128비트)
    //
    //  AXI Interconnect는 AW/W 채널을 서로 다른 클럭에 보낼 수 있다.
    //  → awvalid, wvalid 를 각각 래치하고 둘 다 도착하면 처리한다.
    // --------------------------------------------------
    reg [31:0] key_reg0, key_reg1, key_reg2, key_reg3;
    wire [127:0] aes_key = {key_reg3, key_reg2, key_reg1, key_reg0};

    // --- AW / W 채널 래치 ---
    reg        aw_done;
    reg        w_done;
    reg [4:0]  aw_addr_hold;
    reg [31:0] w_data_hold;

    assign s_axi_awready = ~aw_done;
    assign s_axi_wready  = ~w_done;
    assign s_axi_bresp   = 2'b00; // OKAY

    // AW 채널 래치
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            aw_done      <= 0;
            aw_addr_hold <= 0;
        end else if (s_axi_awvalid && s_axi_awready) begin
            aw_done      <= 1;
            aw_addr_hold <= s_axi_awaddr;
        end else if (aw_done && w_done) begin
            aw_done      <= 0;
        end
    end

    // W 채널 래치
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            w_done      <= 0;
            w_data_hold <= 0;
        end else if (s_axi_wvalid && s_axi_wready) begin
            w_done      <= 1;
            w_data_hold <= s_axi_wdata;
        end else if (aw_done && w_done) begin
            w_done      <= 0;
        end
    end

    // --- 둘 다 도착하면 키 레지스터 쓰기 ---
    wire wr_fire = aw_done && w_done;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            key_reg0 <= 0; key_reg1 <= 0; key_reg2 <= 0; key_reg3 <= 0;
        end else if (wr_fire) begin
            case (aw_addr_hold[4:2])
                3'h0: key_reg0 <= w_data_hold;
                3'h1: key_reg1 <= w_data_hold;
                3'h2: key_reg2 <= w_data_hold;
                3'h3: key_reg3 <= w_data_hold;
            endcase
        end
    end

    // --- B 채널 (write response) ---
    reg bvalid_reg;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            bvalid_reg <= 0;
        else if (wr_fire && !bvalid_reg)
            bvalid_reg <= 1;
        else if (s_axi_bready && bvalid_reg)
            bvalid_reg <= 0;
    end
    assign s_axi_bvalid = bvalid_reg;

    // --------------------------------------------------
    // [Part 2] AES-128 Inverse Core 연동
    // --------------------------------------------------
    wire [127:0] dec_output;
    wire         dec_done;

    aes_128_inv_core u_aes_inv_core (
        .clk      (aclk),
        .reset_n  (aresetn),
        .key      (aes_key),
        .data_in  (s_axis_tdata),
        .start    (s_axis_tvalid && s_axis_tready),
        .data_out (dec_output),
        .done     (dec_done)
    );

    // --------------------------------------------------
    // [Part 3] AXI-Stream 제어 및 핸드쉐이킹
    // --------------------------------------------------
    reg busy;
    wire start_pulse = s_axis_tvalid && s_axis_tready;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn)          busy <= 0;
        else if (start_pulse)  busy <= 1;
        else if (dec_done)     busy <= 0;
    end

    assign s_axis_tready = !busy && !output_valid;

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
