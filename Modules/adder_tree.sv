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

  // Pipelined Input
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int adder = 0; adder < ADDER_SIZE; adder = adder + 1) begin
        adder_tree_data[0][adder] <= '0;
      end
    end else begin
      for (int adder = 0; adder < HALF_INPUT_NUM; adder = adder + 1) begin
        adder_tree_data[0][adder] <= signed'(din[(2*adder+1)*IN_WIDTH-1-:IN_WIDTH]) + signed'(din[(2*adder+2)*IN_WIDTH-1-:IN_WIDTH]);
      end
      if (PARITY) begin
        adder_tree_data[0][HALF_INPUT_NUM] <= signed'(din[(2*HALF_INPUT_NUM+1)*IN_WIDTH-1-:IN_WIDTH]);
      end
    end
  end

  // Pipelined adding
  genvar stage;
  generate
    for (stage = 1; stage < STAGE_NUM; stage = stage + 1) begin
      localparam CRNT_STAGE_NUM = ADDER_SIZE >> stage;
      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          for (int adder = 0; adder < ADDER_SIZE; adder = adder + 1) begin
            adder_tree_data[stage][adder] <= '0;
          end
        end else begin
          begin
            for (int adder = 0; adder < CRNT_STAGE_NUM; adder = adder + 1) begin
              adder_tree_data[stage][adder] <= adder_tree_data[stage-1][adder*2] + adder_tree_data[stage-1][adder*2+1];
            end
            dout <= adder_tree_data[STAGE_NUM-1][0] + adder_tree_data[STAGE_NUM-1][1];
          end
        end
      end
    end
  endgenerate
endmodule
