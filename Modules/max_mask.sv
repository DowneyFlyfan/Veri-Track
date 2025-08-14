`timescale 1ns / 100ps
// WARN:目前测试max功能，mask还没上线

module max_mask #(
    parameter ROI_SIZE = 480,
    parameter IN_WIDTH = 12,
    parameter OUT_WIDTH = 12,  // WARN:还需商榷
    parameter MASK_SIZE = 5,
    parameter NUM_PER_CYCLE = 2,

    parameter ROI_AREA = ROI_SIZE * ROI_SIZE
) (
    input clk,
    input rst_n,
    input clk_en,
    input logic signed [OUT_WIDTH-1:0] max,
    input logic [IN_WIDTH - 1:0] din[NUM_PER_CYCLE-1:0],
    input logic sobel_conv_valid,
    output logic signed [OUT_WIDTH-1:0] dout[NUM_PER_CYCLE- 1:0]
);

  localparam addr_bits = $clog2(ROI_AREA);
  logic [addr_bits-1:0] write_addr, read_addr;
  logic [OUT_WIDTH - 1:0] dmid[NUM_PER_CYCLE-1:0];

  logic ram_full;

  // Params
  sobel_out sobel_bank (
      .clka (clk),
      .ena  (sobel_conv_valid),
      .wea  (sobel_conv_valid),
      .addra(write_addr),
      .dina (din),

      .clkb (clk),
      .enb  (sobel_conv_valid),
      .web  (1'b0),
      .addrb(read_addr),
      .doutb(dmid),
  );

  // Main Logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin : reset
      write_addr <= 0;
      read_addr  <= 0;
      ram_full   <= 1'b0;

    end else if (clk_en) begin

      begin : addr_update
        if (sobel_conv_valid) begin
          write_addr <= write_addr + NUM_PER_CYCLE;
        end
        if (ram_full && sobel_conv_valid) begin
          read_addr <= read_addr + NUM_PER_CYCLE;
          dout = dmid / max;
        end
        if (write_addr == ROI_AREA - 3) begin
          ram_full <= 1'b1;
        end
      end



    end
  end

endmodule

module divider #(
    IN_WIDTH  = 12,
    OUT_WIDTH = 12
) (
    input clk,
    input rst_n,

    input                               valid,
    input  logic signed [ IN_WIDTH-1:0] rs1,
    input  logic signed [ IN_WIDTH-1:0] rs2,
    output logic        [OUT_WIDTH-1:0] rd,
    output logic                        module_wait,
    output logic                        ready
);
  reg  module_wait_q;  // Holds the value of module_wait from the previous cycle.
  wire start = module_wait && !module_wait_q;

  always @(posedge clk) begin  // Decode
    module_wait   <= rst_n;
    module_wait_q <= module_wait && rst_n;
  end

  reg [IN_WIDTH-1:0] dividend[IN_WIDTH-1:0];
  reg [IN_WIDTH-1:0] divisor[IN_WIDTH-1:0];
  reg [OUT_WIDTH-1:0] quotient[IN_WIDTH-1:0];
  reg [OUT_WIDTH-1:0] quotient_msk[IN_WIDTH-1:0];
  reg running;
  reg outsign;

  always @(posedge clk) begin
    ready <= 0;
    rd <= 'bx;

    if (!rst_n) begin
      running <= 0;
    end else if (start) begin
      running <= 1;
      dividend <= rs1[IN_WIDTH-1] ? -rs1 : rs1;
      divisor <= (rs2[IN_WIDTH-1] ? -rs2 : rs2) << (IN_WIDTH - 1);

      // 除法->符号不同输出为负->分母不为0
      outsign <= (rs1[IN_WIDTH-1] != rs2[IN_WIDTH-1]) && |rs2;

      quotient <= 0;
      quotient_msk <= 1 << IN_WIDTH - 1;
    end else if (!quotient_msk && running) begin
      running    <= 0;
      ready <= 1;  // Signal completion to the CPU.

      rd <= outsign ? -quotient : quotient;
      if (divisor <= dividend) begin
        dividend <= dividend - divisor;
        quotient <= quotient | quotient_msk;
      end

      divisor <= divisor >> 1;
      quotient_msk <= quotient_msk >> 1;
    end
  end
endmodule
