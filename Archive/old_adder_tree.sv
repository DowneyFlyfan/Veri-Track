`timescale 1ns / 1ps

module adder_tree #(
    parameter INPUT_NUM,
    parameter IN_WIDTH,
    parameter OUT_WIDTH = IN_WIDTH + $clog2(INPUT_NUM)
) (
    input logic clk,
    input logic rst_n,
    input logic signed [INPUT_NUM*IN_WIDTH-1 : 0] din,
    output logic signed [OUT_WIDTH-1 : 0] dout
);
  localparam STAGE_NUM = $clog2(INPUT_NUM);
  localparam ADDER_SIZE = 2 ** STAGE_NUM;

  logic signed [OUT_WIDTH-1 : 0] adder_tree_data[STAGE_NUM : 0][ADDER_SIZE-1 : 0];

  // Reset or Reload
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int adder = 0; adder < ADDER_SIZE; adder = adder + 1) begin
        adder_tree_data[0][adder] <= '0;
      end
    end else begin
      for (int adder = 0; adder < ADDER_SIZE; adder = adder + 1) begin
        if (adder < INPUT_NUM) begin
          adder_tree_data[0][adder] <= signed'(din[(adder+1)*IN_WIDTH-1-:IN_WIDTH]);
        end else begin
          adder_tree_data[0][adder] <= '0;
        end
      end
    end
  end

  // Pipelined adder stages
  genvar stage;
  generate
    for (stage = 1; stage <= STAGE_NUM; stage = stage + 1) begin : gen_adder_stages
      localparam CRNT_STAGE_NUM = ADDER_SIZE >> stage;
      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          for (int adder = 0; adder < CRNT_STAGE_NUM; adder = adder + 1) begin
            adder_tree_data[stage][adder] <= '0;
          end
        end else begin
          begin
            for (int adder = 0; adder < CRNT_STAGE_NUM; adder = adder + 1) begin
              adder_tree_data[stage][adder] <= adder_tree_data[stage-1][adder*2] + adder_tree_data[stage-1][adder*2+1];
            end
          end
        end
      end
    end
    assign dout = adder_tree_data[STAGE_NUM][0];
  endgenerate
endmodule
