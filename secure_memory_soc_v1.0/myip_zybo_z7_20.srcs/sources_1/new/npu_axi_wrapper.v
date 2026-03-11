`timescale 1ns / 1ps

module npu_axi_wrapper (
    // System Clock & Reset
    input  wire aclk,
    input  wire aresetn,

    // ==========================================
    // 1. AXI4-Lite Slave Interface (CPU 제어 버스)
    // ==========================================
    input  wire [4:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [4:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // ==========================================
    // 2. AXI4-Stream Slave (DMA에서 들어오는 픽셀 데이터)
    // ==========================================
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    // ==========================================
    // 3. AXI4-Stream Master (NPU에서 나가는 최종 결과)
    // ==========================================
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);

    // --------------------------------------------------
    // [Part 1] AXI-Lite 레지스터 맵 (간소화)
    // --------------------------------------------------
    reg [31:0] slv_reg0; // 제어 레지스터 (Bit 0: start, Bit 1: pad_en)
    reg [31:0] slv_reg1; // 해상도 (상위 16비트: Height, 하위 16비트: Width)
    reg [31:0] slv_reg2; // Weight 0~3
    reg [31:0] slv_reg3; // Weight 4~7
    reg [31:0] slv_reg4; // Bias(16bit) & Weight 8(8bit)

    // AXI-Lite Write 상태 머신
    reg awready_reg, wready_reg, bvalid_reg;
    assign s_axi_awready = awready_reg;
    assign s_axi_wready  = wready_reg;
    assign s_axi_bvalid  = bvalid_reg;
    assign s_axi_bresp   = 2'b00; 

    always @(posedge aclk) begin
        if (!aresetn) begin
            awready_reg <= 0; wready_reg <= 0; bvalid_reg <= 0;
        end else begin
            if (s_axi_awvalid && !awready_reg) awready_reg <= 1;
            else awready_reg <= 0;

            if (s_axi_wvalid && !wready_reg) wready_reg <= 1;
            else wready_reg <= 0;

            if (awready_reg && wready_reg) bvalid_reg <= 1;
            else if (s_axi_bready && bvalid_reg) bvalid_reg <= 0;
        end
    end

    // 레지스터 쓰기 로직
    wire [2:0] reg_addr = s_axi_awaddr[4:2]; 
    always @(posedge aclk) begin
        if (!aresetn) begin
            slv_reg0 <= 0; slv_reg1 <= 0; slv_reg2 <= 0; slv_reg3 <= 0; slv_reg4 <= 0;
        end else if (awready_reg && wready_reg) begin
            case (reg_addr)
                3'h0: slv_reg0 <= s_axi_wdata;
                3'h1: slv_reg1 <= s_axi_wdata;
                3'h2: slv_reg2 <= s_axi_wdata;
                3'h3: slv_reg3 <= s_axi_wdata;
                3'h4: slv_reg4 <= s_axi_wdata;
            endcase
        end else begin
            // 하드웨어 트리거: CPU가 start(0번 비트)에 1을 쓰면 1클럭 후 자동으로 0으로 복귀
            if (slv_reg0[0]) slv_reg0[0] <= 1'b0;
        end
    end

    // AXI-Lite Read 로직 (생략: 쓰기 전용으로 구현하여 자원 최적화, 필요시 읽기 추가 가능)
    assign s_axi_arready = 1'b1;
    assign s_axi_rvalid  = s_axi_arvalid;
    assign s_axi_rdata   = 32'd0;
    assign s_axi_rresp   = 2'b00;

    // --------------------------------------------------
    // [Part 2] npu_top 조립 및 신호 맵핑
    // --------------------------------------------------
    wire [3:0] final_digit;
    wire       final_valid;
    wire       done_tick;

    npu_top u_npu (
        .clk         (aclk),
        .reset_p     (~aresetn), // AXI의 Active-Low 리셋을 Active-High로 뒤집어줌

        // AXI-Lite 레지스터와 연결
        .start       (slv_reg0[0]),
        .reg_pad_en  (slv_reg0[1]),
        .reg_img_w   (slv_reg1[15:0]),
        .reg_img_h   (slv_reg1[31:16]),
        
        // 8비트 가중치들을 32비트 레지스터에서 쪼개서 넣음
        .weight_in_0 (slv_reg2[7:0]),
        .weight_in_1 (slv_reg2[15:8]),
        .weight_in_2 (slv_reg2[23:16]),
        .weight_in_3 (slv_reg2[31:24]),

        .weight_in_4 (slv_reg3[7:0]),
        .weight_in_5 (slv_reg3[15:8]),
        .weight_in_6 (slv_reg3[23:16]),
        .weight_in_7 (slv_reg3[31:24]),

        .weight_in_8 (slv_reg4[7:0]),
        .bias_in     (slv_reg4[23:8]), 

        // AXI-Stream 입력 연결 (하위 8비트만 사용)
        .pixel_in    (s_axis_tdata[7:0]),
        .pixel_valid (s_axis_tvalid),

        // 최종 출력
        .final_digit (final_digit),
        .final_valid (final_valid),
        .done_tick   (done_tick)
    );

    // --------------------------------------------------
    // [Part 3] AXI-Stream 출력 및 제어 연결
    // --------------------------------------------------
    // NPU는 데이터를 항상 받을 준비가 되어 있음
    assign s_axis_tready = 1'b1; 

    // 최종 산출된 숫자 1개를 AXI-Stream 규격(32비트)에 맞게 포장해서 다음 IP로 전송
    assign m_axis_tdata  = {28'd0, final_digit};
    assign m_axis_tvalid = final_valid;
    assign m_axis_tlast  = final_valid; // 1개만 나가므로 나가는 순간이 곧 패킷의 끝(tlast)

endmodule