`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/11/01 20:11:41
// Design Name: 
// Module Name: adder_tree
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// 组合逻辑: 上升沿可能无法接收到信号
module adder_tree #(  // # is used to declare parameters for the module
    parameter INPUT_NUM = 15,
    parameter INPUT_DATA_WIDTH = 24,
    parameter OUTPUT_DATA_WIDTH = INPUT_DATA_WIDTH + $clog2(
        INPUT_NUM
    )  // $clog2(N) computes ceil(log2(N)), the number of bits required to represent N values.
) (
    input [INPUT_NUM*INPUT_DATA_WIDTH-1 : 0] din,
    output [OUTPUT_DATA_WIDTH-1 : 0] dout
);
  localparam STAGE_NUM = $clog2(INPUT_NUM);  // 4
  localparam INPUT_NUM_INIT = 2 ** STAGE_NUM;  // 16

  wire signed [INPUT_DATA_WIDTH-1 : 0] signed_din[INPUT_NUM-1 : 0];
  reg signed [OUTPUT_DATA_WIDTH-1 : 0] adder_tree_data[STAGE_NUM : 0][INPUT_NUM_INIT-1 : 0];

  // 定义输出归零的情况
  wire signed [OUTPUT_DATA_WIDTH-1 : 0] zeros;
  assign zeros = {(OUTPUT_DATA_WIDTH) {1'b0}};  // (复制次数){复制对象}

  //生成有符号输入
  genvar stage, adder;
  generate
    for (adder = 0; adder < INPUT_NUM; adder = adder + 1) begin
      assign signed_din[adder] = din[adder*INPUT_DATA_WIDTH+:INPUT_DATA_WIDTH]; // Bit Slicing, 用+形式实现
    end
  endgenerate

  generate
    for (stage = 0; stage <= STAGE_NUM; stage = stage + 1) begin : stage_gen
      localparam CRNT_STAGE_NUM = INPUT_NUM_INIT >> stage;

      if (stage == 0) begin
        for (adder = 0; adder < CRNT_STAGE_NUM; adder = adder + 1) begin : input_gen
          always @(*) begin
            if (adder < INPUT_NUM) begin
              adder_tree_data[stage][adder] = signed_din[adder];
            end else begin
              adder_tree_data[stage][adder] = zeros;
            end
          end
        end
      end else begin
        for (adder = 0; adder < CRNT_STAGE_NUM; adder = adder + 1) begin : adder_gen
          always @(*) begin
            adder_tree_data[stage][adder] = adder_tree_data[stage-1][adder*2] + adder_tree_data[stage-1][adder*2+1];
          end
        end
      end
    end
  endgenerate

  // 越加到后面，Adder_Tree浪费得越多
  assign dout = adder_tree_data[STAGE_NUM][0];
endmodule
