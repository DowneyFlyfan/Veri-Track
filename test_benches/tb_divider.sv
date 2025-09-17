`timescale 1ns / 100ps
module tb_divider;
  // Parameters
  localparam IN_WIDTH = 12;
  localparam OUT_WIDTH = 12;
  localparam CLK_PERIOD = 10;
  localparam DELAY = 2 * IN_WIDTH;
  localparam SCALE = 2 ** (IN_WIDTH - 1);

  // Clock and Reset
  logic clk;
  logic rst_n;

  // Divider Inputs and Outputs
  logic signed [IN_WIDTH-1:0] rs1;
  logic signed [IN_WIDTH-1:0] rs2;
  logic signed [OUT_WIDTH-1:0] rd;
  logic valid;

  // Instantiate the fixed_point_divider module
  fixed_point_divider #(
      .IN_WIDTH (IN_WIDTH),
      .OUT_WIDTH(OUT_WIDTH)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .rs1(rs1),
      .rs2(rs2),
      .rd(rd),
      .valid(valid)
  );

  // Clock generation
  initial begin : clk_gen
    clk = 0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // Test sequence
  initial begin : test
    // 1. Reset
    rst_n = 1'b0;
    rs1   = '0;
    rs2   = '0;

    @(negedge clk);
    rst_n = 1'b1;

    // 2. Test cases
    @(negedge clk);
    rs1 = 3;
    rs2 = 10;
    @(negedge clk);
    rs1 = 345;
    rs2 = 1860;

    repeat (IN_WIDTH + OUT_WIDTH + 2) @(negedge clk);
    $finish;
  end

endmodule
