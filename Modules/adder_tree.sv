`timescale 1ns / 100ps

// WARN: 使用之前一定要进行一次Reset
module adder_tree #(
    parameter INPUT_NUM = 18,
    parameter IN_WIDTH = 12,
    parameter OUT_WIDTH = IN_WIDTH + $clog2(INPUT_NUM),
    parameter MODE = "sobel"
) (
    input logic clk,
    input logic rst_n,
    input logic signed [INPUT_NUM*IN_WIDTH-1 : 0] din,
    output logic signed [OUT_WIDTH-1 : 0] dout
);
  localparam STAGE_NUM = $clog2(INPUT_NUM);
  localparam ADDER_SIZE = 2 ** STAGE_NUM;
  logic signed [OUT_WIDTH-1 : 0] adder_tree_data[STAGE_NUM : 0][ADDER_SIZE-1 : 0];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int stage = 0; stage <= STAGE_NUM; stage = stage + 1) begin
        for (int adder = 0; adder < ADDER_SIZE; adder = adder + 1) begin
          adder_tree_data[stage][adder] <= '0;
        end
      end
    end else begin
      for (int adder = 0; adder < INPUT_NUM; adder = adder + 1) begin
        adder_tree_data[0][adder] <= signed'(din[(adder+1)*IN_WIDTH-1-:IN_WIDTH]);
      end

      for (int stage = 1; stage <= STAGE_NUM; stage = stage + 1) begin : adder_tree_stage
        for (int adder = 0; adder < (ADDER_SIZE >> stage); adder = adder + 1) begin
          adder_tree_data[stage][adder] <= adder_tree_data[stage-1][adder*2] + adder_tree_data[stage-1][adder*2+1];
        end
      end
    end
  end

  if (MODE == "sobel") begin  // Sobel(Abs)
    assign dout = (adder_tree_data[STAGE_NUM][0] >= 0) ? adder_tree_data[STAGE_NUM][0] : -adder_tree_data[STAGE_NUM][0];
  end else if (MODE == "hessian") begin  // Hessian
    assign dout = adder_tree_data[STAGE_NUM][0] >>> 15;
  end else begin  // NORMAL
    assign dout = adder_tree_data[STAGE_NUM][0];
  end

endmodule
