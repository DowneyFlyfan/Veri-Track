`timescale 1ns / 100ps

// WARN: 使用之前一定要进行一次Reset
module adder_tree #(
    parameter INPUT_NUM = 18,
    parameter IN_WIDTH = 12,
    parameter OUT_WIDTH = IN_WIDTH + $clog2(INPUT_NUM),
    parameter PARITY = INPUT_NUM % 2
) (
    input logic clk,
    input logic rst_n,
    input logic signed [INPUT_NUM*IN_WIDTH-1 : 0] din,
    output logic signed [OUT_WIDTH-1 : 0] dout
);
  localparam STAGE_NUM = $clog2(INPUT_NUM) - 1;
  localparam ADDER_SIZE = 2 ** STAGE_NUM;
  localparam HALF_INPUT_NUM = INPUT_NUM / 2;
  logic signed [OUT_WIDTH-1 : 0] adder_tree_data[STAGE_NUM-1 : 0][ADDER_SIZE-1 : 0];
  logic signed [OUT_WIDTH-1 : 0] din_mat[INPUT_NUM-1:0];
  logic signed [OUT_WIDTH-1 : 0] zeros;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int adder = 0; adder < ADDER_SIZE; adder = adder + 1) begin
        adder_tree_data[0][adder] <= '0;
      end
      for (int stage = 1; stage < STAGE_NUM; stage = stage + 1) begin
        for (int adder = 0; adder < ADDER_SIZE; adder = adder + 1) begin
          adder_tree_data[stage][adder] <= '0;
        end
      end
    end else begin
      for (int i = 0; i < INPUT_NUM; i = i + 1) begin
        din_mat[i] <= signed'(din[(i+1)*IN_WIDTH-1-:IN_WIDTH]);
      end

      for (int adder = 0; adder < HALF_INPUT_NUM; adder = adder + 1) begin
        adder_tree_data[0][adder] <= din_mat[2*adder] + din_mat[2*adder+1];
      end
      if (PARITY) begin
        adder_tree_data[0][HALF_INPUT_NUM] <= din_mat[INPUT_NUM-1] + zeros;
      end

      for (int stage = 1; stage < STAGE_NUM; stage = stage + 1) begin
        for (int adder = 0; adder < (ADDER_SIZE >> stage); adder = adder + 1) begin
          adder_tree_data[stage][adder] <= adder_tree_data[stage-1][adder*2] + adder_tree_data[stage-1][adder*2+1];
        end
      end

      dout <= adder_tree_data[STAGE_NUM-1][0] + adder_tree_data[STAGE_NUM-1][1];
    end
  end
endmodule
