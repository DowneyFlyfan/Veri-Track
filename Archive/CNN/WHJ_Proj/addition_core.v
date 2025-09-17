`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/11/01 17:39:38
// Design Name: 
// Module Name: addition_core
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

// Data Path: 输入 -> 卷积 -> Ctrl1寄存器 -> Ctrl2寄存器 -> Pooling寄存器 ->
// ReLu寄存器 -> 输出
// Control Path: 

module addition_core #(
    parameter VALID_CORE_NUM = 16,  // 16个通道
    parameter FMS_MAX_SIZE = 32,
    parameter FMS_PATCH_SIZE = 8,  // 输入的patch大小
    parameter INFMS_DATA_WIDTH = 20,  // 输入位宽
    parameter MULTIPLIED_DATA_WIDTH = INFMS_DATA_WIDTH + 8,  // 8位权重相乘后的最大位宽
    parameter ADDED_DATA_WIDTH = INFMS_DATA_WIDTH + 12, // 16个28位数相加后的最大位宽 = 28 + log2(16) = 32
    parameter ADDED_DATA_CUT1_WIDTH = 12,
    parameter ADDED_DATA_CUT2_WIDTH = 8
) (
    input clk,
    input rst_n,
    input clk_en,
    input addition_en,
    input addition_mode,  //1:3x3 0:1x1
    input multiplied_data_vld,
    input [1:0] fms_size_mode,  //00:8*8 01:16*16 10:32*32 11:32*64
    input [$clog2(ADDED_DATA_WIDTH) - 1 : 0] head_cut_position,
    input [FMS_PATCH_SIZE * FMS_PATCH_SIZE * VALID_CORE_NUM * MULTIPLIED_DATA_WIDTH - 1 : 0] multiplied_data,
    input [FMS_PATCH_SIZE * FMS_PATCH_SIZE * ADDED_DATA_CUT1_WIDTH - 1 : 0] patch_bias, // 砍精度之后加bias
    input [FMS_PATCH_SIZE * FMS_PATCH_SIZE * ADDED_DATA_CUT1_WIDTH - 1 : 0] accumed_data, // 从外部累加器读入的
    input accumed_data_vld,
    input pooling_en,
    input relu_en,
    output reg added_data_to_accum_vld,
    output reg added_data_vld,
    output reg chn_over,
    output [FMS_PATCH_SIZE * FMS_PATCH_SIZE * ADDED_DATA_CUT1_WIDTH - 1 : 0] added_data_to_accum,
    output [FMS_PATCH_SIZE * FMS_PATCH_SIZE * ADDED_DATA_CUT2_WIDTH - 1 : 0] added_data
);
  localparam PATCH_CNT_WIDTH = $clog2(16);  // TODO:为什么是4
  localparam POOLING_PATCH_SIZE = FMS_PATCH_SIZE / 2;  // 4 = 2x2
  localparam POOLING_CNT_WIDTH = $clog2(POOLING_PATCH_SIZE);  // 2

  // 状态机参数
  // TODO:为什么状态机要用这种形式
  localparam IDLE = 4'b1;
  localparam CAL_2_SRAM = 4'b10;
  localparam CAL_2_ACCUM = 4'b100;
  localparam OUTPUT = 4'b1000;
  reg [3:0] n_state;
  reg [3:0] c_state;

  localparam x8x8 = 2'b00;
  localparam x16x16 = 2'b01;
  localparam x32x32 = 2'b10;

  // 判断各个步骤是否顺利进行
  reg cut1_vld;
  reg cut2_vld;  //used in CAL_2_SRAM state, OUTPUT state use accumed_data_vld instead
  reg pooling_vld;
  reg relu_vld;

  reg [PATCH_CNT_WIDTH-1 : 0] patch_cnt;
  reg [3:0] conv3_wght_cnt;

  // Adder Tree
  wire        [MULTIPLIED_DATA_WIDTH*VALID_CORE_NUM-1 : 0]        adder_tree_input_mat    [FMS_PATCH_SIZE - 1 : 0][FMS_PATCH_SIZE - 1 : 0];
  wire        [ADDED_DATA_WIDTH - 1 : 0]                          adder_tree_output_mat   [FMS_PATCH_SIZE - 1 : 0][FMS_PATCH_SIZE - 1 : 0]; // 切断组合逻辑，进入时序逻辑

  reg         [ADDED_DATA_WIDTH - 1 : 0]                          adder_tree_output_reg   [FMS_PATCH_SIZE - 1 : 0][FMS_PATCH_SIZE - 1 : 0];
  reg         [ADDED_DATA_CUT1_WIDTH : 0]                         added_data_cut1_mat     [FMS_PATCH_SIZE - 1 : 0][FMS_PATCH_SIZE - 1 : 0]; // 存一位小数判断四舍五入
  reg         [ADDED_DATA_CUT1_WIDTH - 1 : 0]                     added_data_cut1_reg     [FMS_PATCH_SIZE - 1 : 0][FMS_PATCH_SIZE - 1 : 0]; // 四舍五入后的加法器输出

  // Add Bias & Cut precision
  wire        [ADDED_DATA_CUT1_WIDTH - 1 : 0]                     accumed_data_mat        [FMS_PATCH_SIZE - 1 : 0][FMS_PATCH_SIZE - 1 : 0]; // 仅用于3x3卷积，wx + b
  reg         [ADDED_DATA_CUT2_WIDTH - 1 : 0]                     added_data_cut2_mat     [FMS_PATCH_SIZE - 1 : 0][FMS_PATCH_SIZE - 1 : 0]; // 组合逻辑输出
  reg  signed [ADDED_DATA_CUT2_WIDTH - 1 : 0]                     added_data_cut2_reg     [FMS_PATCH_SIZE - 1 : 0][FMS_PATCH_SIZE - 1 : 0]; // 进入时序逻辑，有符号方便后续比较
  reg         [ADDED_DATA_CUT2_WIDTH - 1 : 0]                     added_data_reg          [FMS_PATCH_SIZE - 1 : 0][FMS_PATCH_SIZE - 1 : 0]; // 最终输出数据

  // maxpooling compare signal
  wire    signed    [ADDED_DATA_CUT2_WIDTH - 1 : 0]             pooling_data_max_mat    [FMS_PATCH_SIZE - 1 : 0][POOLING_PATCH_SIZE - 1 : 0];
  wire    signed    [ADDED_DATA_CUT2_WIDTH - 1 : 0]             pooling_patch_data_mat  [POOLING_PATCH_SIZE - 1 : 0][POOLING_PATCH_SIZE - 1 : 0];
  wire              [ADDED_DATA_CUT2_WIDTH - 1 : 0]             relu_data_mat           [FMS_PATCH_SIZE - 1 : 0][FMS_PATCH_SIZE - 1   : 0];
  reg    signed     [ADDED_DATA_CUT2_WIDTH - 1 : 0]             pooling_data_reg        [FMS_PATCH_SIZE - 1 : 0][FMS_PATCH_SIZE - 1 : 0]; // 
  reg [POOLING_CNT_WIDTH -1 : 0] pooling_cnt;

  // reg连接最终输出
  genvar h, w;
  generate
    for (h = 0; h < FMS_PATCH_SIZE; h = h + 1) begin
      for (w = 0; w < FMS_PATCH_SIZE; w = w + 1) begin
        assign  added_data[(h*FMS_PATCH_SIZE+w)*ADDED_DATA_CUT2_WIDTH +: ADDED_DATA_CUT2_WIDTH] = added_data_reg[h][w];
      end
    end
  endgenerate

  // 第一次砍精度后的数据连接到added_data_to_accum. 3x3累加后的数据加bias, 1x1卷积后的数据相加
  genvar c;  //c: different multiplication core
  generate
    for (h = 0; h < FMS_PATCH_SIZE; h = h + 1) begin
      for (w = 0; w < FMS_PATCH_SIZE; w = w + 1) begin
        assign added_data_to_accum[(h*FMS_PATCH_SIZE+w)*ADDED_DATA_CUT1_WIDTH +: ADDED_DATA_CUT1_WIDTH] = added_data_cut1_reg[h][w][ADDED_DATA_CUT1_WIDTH-1:0];
        assign accumed_data_mat[h][w] = accumed_data[(h*FMS_PATCH_SIZE+w)*ADDED_DATA_CUT1_WIDTH +: ADDED_DATA_CUT1_WIDTH] + patch_bias[(h*FMS_PATCH_SIZE+w)*ADDED_DATA_CUT1_WIDTH +: ADDED_DATA_CUT1_WIDTH]; // wx + b
        for (c = 0; c < (VALID_CORE_NUM); c = c + 1) begin
          assign adder_tree_input_mat[h][w][c*MULTIPLIED_DATA_WIDTH +: MULTIPLIED_DATA_WIDTH] = 
                        multiplied_data[(c*FMS_PATCH_SIZE*FMS_PATCH_SIZE+h*FMS_PATCH_SIZE+w)*MULTIPLIED_DATA_WIDTH +: MULTIPLIED_DATA_WIDTH];
        end
      end
    end
  endgenerate

  // generate adder_tree
  generate
    for (h = 0; h < FMS_PATCH_SIZE; h = h + 1) begin : adder_tree_mat_h
      for (w = 0; w < FMS_PATCH_SIZE; w = w + 1) begin : adder_tree_mat_w
        adder_tree #(
            .INPUT_NUM(VALID_CORE_NUM),  //15 multiplication output + 1 bias
            .INPUT_DATA_WIDTH(MULTIPLIED_DATA_WIDTH)  // 28
        ) adder_tree_inst (
            .din (adder_tree_input_mat[h][w]),
            .dout(adder_tree_output_mat[h][w])
        );
      end
    end
  endgenerate

  // max_pooling: 先后横向、纵向比大小
  genvar pooling_patch_nn, pooling_patch_hh, pooling_patch_ww;
  generate
    for (
        pooling_patch_hh = 0;
        pooling_patch_hh < FMS_PATCH_SIZE;
        pooling_patch_hh = pooling_patch_hh + 1
    ) begin
      for (
          pooling_patch_ww = 0;
          pooling_patch_ww < POOLING_PATCH_SIZE;
          pooling_patch_ww = pooling_patch_ww + 1
      ) begin
        assign pooling_data_max_mat[pooling_patch_hh][pooling_patch_ww] = (added_data_cut2_reg[pooling_patch_hh][pooling_patch_ww*2] > added_data_cut2_reg[pooling_patch_hh][pooling_patch_ww*2 +1])?
                        added_data_cut2_reg[pooling_patch_hh][pooling_patch_ww*2] : added_data_cut2_reg[pooling_patch_hh][pooling_patch_ww*2 +1];
      end
    end
  endgenerate

  generate
    for (
        pooling_patch_hh = 0;
        pooling_patch_hh < POOLING_PATCH_SIZE;
        pooling_patch_hh = pooling_patch_hh + 1
    ) begin
      for (
          pooling_patch_ww = 0;
          pooling_patch_ww < POOLING_PATCH_SIZE;
          pooling_patch_ww = pooling_patch_ww + 1
      ) begin
        assign pooling_patch_data_mat[pooling_patch_hh][pooling_patch_ww] = (pooling_data_max_mat[pooling_patch_hh*2][pooling_patch_ww] > pooling_data_max_mat[pooling_patch_hh*2+1][pooling_patch_ww])?
                    pooling_data_max_mat[pooling_patch_hh*2][pooling_patch_ww] : pooling_data_max_mat[pooling_patch_hh*2+1][pooling_patch_ww];
      end
    end
  endgenerate

  // relu
  genvar patch_hh, patch_ww;
  generate
    for (patch_hh = 0; patch_hh < FMS_PATCH_SIZE; patch_hh = patch_hh + 1) begin
      for (patch_ww = 0; patch_ww < FMS_PATCH_SIZE; patch_ww = patch_ww + 1) begin
        // 两层if, 实现relu, 有符号数第一位判断正负
        assign relu_data_mat[patch_hh][patch_ww] = relu_en ? 
                    ((pooling_data_reg[patch_hh][patch_ww][ADDED_DATA_CUT2_WIDTH-1] == 1'b1)? {(ADDED_DATA_CUT2_WIDTH){1'b0}}:pooling_data_reg[patch_hh][patch_ww]):
                    pooling_data_reg[patch_hh][patch_ww];
      end
    end
  endgenerate

  // Initialize State Machine
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      c_state <= IDLE;
    end else if (clk_en) begin
      c_state <= n_state;
    end
  end

  integer patch_n, patch_h, patch_w;  // 一种32位有符号变量
  integer pooling_patch_n, pooling_patch_h, pooling_patch_w;

  // 进入状态
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      pooling_cnt             <= {(POOLING_CNT_WIDTH) {1'b0}};
      pooling_vld             <= 1'b0;
      relu_vld                <= 1'b0;
      chn_over                <= 1'b0;
      patch_cnt               <= {(PATCH_CNT_WIDTH) {1'b0}};  // {(repeat times) {vaule to repeat}}
      conv3_wght_cnt          <= 4'b0;
      cut1_vld                <= 1'b0;
      cut2_vld                <= 1'b0;
      added_data_vld          <= 1'b0;
      added_data_to_accum_vld <= 1'b0;
    end else if (clk_en) begin
      case (c_state)
        IDLE: begin
          pooling_cnt             <= {(POOLING_CNT_WIDTH) {1'b0}};
          pooling_vld             <= 1'b0;
          relu_vld                <= 1'b0;
          chn_over                <= 1'b0;
          patch_cnt               <= {(PATCH_CNT_WIDTH) {1'b0}};
          conv3_wght_cnt          <= 4'b0;
          cut1_vld                <= 1'b0;
          cut2_vld                <= 1'b0;
          added_data_vld          <= 1'b0;
          added_data_to_accum_vld <= 1'b0;

          // adder_tree输出到寄存器上
          if (addition_en) begin
            cut1_vld <= multiplied_data_vld;
            if (multiplied_data_vld) begin
              for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
                for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                  adder_tree_output_reg[patch_h][patch_w] <= adder_tree_output_mat[patch_h][patch_w];
                end
              end
            end
          end
        end

        CAL_2_SRAM: begin
          cut1_vld <= multiplied_data_vld;
          cut2_vld <= cut1_vld;
          pooling_vld <= cut2_vld;
          relu_vld <= pooling_en ? (pooling_cnt == 3'd3 && pooling_vld) : pooling_vld;
          added_data_vld <= relu_vld;

          // wire到寄存器
          if (multiplied_data_vld) begin
            for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
              for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                adder_tree_output_reg[patch_h][patch_w] <= adder_tree_output_mat[patch_h][patch_w];
              end
            end
          end

          // 第一次砍精度四舍五入(13 -> 12)
          if (cut1_vld) begin
            for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
              for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                added_data_cut1_reg[patch_h][patch_w] <= added_data_cut1_mat[patch_h][patch_w][0] ? added_data_cut1_mat[patch_h][patch_w][ADDED_DATA_CUT1_WIDTH : 1] + patch_bias[(patch_h*FMS_PATCH_SIZE+patch_w)*ADDED_DATA_CUT1_WIDTH +: ADDED_DATA_CUT1_WIDTH]+1 :
                                                                                                                    added_data_cut1_mat[patch_h][patch_w][ADDED_DATA_CUT1_WIDTH : 1] + patch_bias[(patch_h*FMS_PATCH_SIZE+patch_w)*ADDED_DATA_CUT1_WIDTH +: ADDED_DATA_CUT1_WIDTH];

              end
            end
          end

          // 第二次砍精度 (wire到reg, 12 -> 8)
          if (cut2_vld) begin
            for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
              for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                added_data_cut2_reg[patch_h][patch_w] <= added_data_cut2_mat[patch_h][patch_w];
              end
            end
          end

          // pooling
          if (pooling_en) begin
            if (pooling_vld) begin
              if (pooling_cnt == 2'd3) begin
                pooling_cnt <= {(POOLING_CNT_WIDTH) {1'b0}};  // 归零
              end else begin
                pooling_cnt <= pooling_cnt + 1'b1;
              end
              for (
                  pooling_patch_h = 0;
                  pooling_patch_h < POOLING_PATCH_SIZE;
                  pooling_patch_h = pooling_patch_h + 1
              ) begin
                for (
                    pooling_patch_w = 0;
                    pooling_patch_w < POOLING_PATCH_SIZE;
                    pooling_patch_w = pooling_patch_w + 1
                ) begin
                  pooling_data_reg[pooling_patch_h][pooling_patch_w] <= pooling_patch_data_mat[pooling_patch_h][pooling_patch_w];
                  pooling_data_reg[pooling_patch_h][pooling_patch_w+POOLING_PATCH_SIZE] <= pooling_data_reg[pooling_patch_h][pooling_patch_w];
                  pooling_data_reg[pooling_patch_h+POOLING_PATCH_SIZE][pooling_patch_w] <= pooling_data_reg[pooling_patch_h][pooling_patch_w+POOLING_PATCH_SIZE];
                  pooling_data_reg[pooling_patch_h+POOLING_PATCH_SIZE][pooling_patch_w+POOLING_PATCH_SIZE] <= pooling_data_reg[pooling_patch_h+POOLING_PATCH_SIZE][pooling_patch_w];
                end
              end

            end

            // 加法器输出到池化寄存器
          end else begin
            if (pooling_vld) begin
              for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
                for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                  pooling_data_reg[patch_h][patch_w] <= added_data_cut2_reg[patch_h][patch_w];
                end
              end
            end
          end

          // wire Relu数据到最后输出
          if (relu_vld) begin
            patch_cnt <= patch_cnt + 1'b1;
            for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
              for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                added_data_reg[patch_h][patch_w] <= relu_data_mat[patch_h][patch_w];
              end
            end
          end

          // channel conv over, 判断卷没卷完
          case (fms_size_mode)
            x8x8: begin
              chn_over <= relu_vld ? 1'b1 : chn_over;
            end
            x16x16: begin
              if (pooling_en) begin
                chn_over <= relu_vld ? 1'b1 : chn_over;
              end else begin
                chn_over <= (relu_vld && patch_cnt == 4'd3) ? 1'b1 : chn_over;
              end
            end
            x32x32: begin
              if (pooling_en) begin
                chn_over <= (relu_vld && patch_cnt == 4'd3) ? 1'b1 : chn_over;
              end else begin
                chn_over <= (relu_vld && patch_cnt == 4'd15) ? 1'b1 : chn_over;
              end
            end
            default: begin
              chn_over <= 1'b0;
            end
          endcase
        end

        // 3x3 卷积的累加
        CAL_2_ACCUM: begin
          cut1_vld <= multiplied_data_vld;
          added_data_to_accum_vld <= cut1_vld;
          if (multiplied_data_vld) begin
            for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
              for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                adder_tree_output_reg[patch_h][patch_w] <= adder_tree_output_mat[patch_h][patch_w];
              end
            end
          end
          if (cut1_vld) begin
            for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
              for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                added_data_cut1_reg[patch_h][patch_w] <= added_data_cut1_mat[patch_h][patch_w][0] ? added_data_cut1_mat[patch_h][patch_w][ADDED_DATA_CUT1_WIDTH : 1]+1 :
                                                                                                                    added_data_cut1_mat[patch_h][patch_w][ADDED_DATA_CUT1_WIDTH : 1];
              end
            end
            case (fms_size_mode)  // 根据图形大小重置patch_cnt和累加conv3_wght_cnt
              x8x8: begin
                conv3_wght_cnt <= conv3_wght_cnt + 1'b1;
              end
              x16x16: begin
                if (patch_cnt == 4'd3) begin
                  patch_cnt <= {(PATCH_CNT_WIDTH) {1'b0}};
                  conv3_wght_cnt <= conv3_wght_cnt + 1'b1;
                end else begin
                  patch_cnt <= patch_cnt + 1'b1;
                end
              end
              x32x32: begin
                if (patch_cnt == 4'd15) begin
                  patch_cnt <= {(PATCH_CNT_WIDTH) {1'b0}};
                  conv3_wght_cnt <= conv3_wght_cnt + 1'b1;
                end else begin
                  patch_cnt <= patch_cnt + 1'b1;
                end
              end
            endcase
          end
        end
        OUTPUT: begin
          conv3_wght_cnt <= 4'b0;
          cut1_vld <= 1'b0;
          added_data_to_accum_vld <= 1'b0;

          pooling_vld <= accumed_data_vld;
          relu_vld <= pooling_en ? (pooling_cnt == 3'd3 && pooling_vld) : pooling_vld;
          added_data_vld <= relu_vld;

          // cut 2次后的数据
          if (accumed_data_vld) begin
            for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
              for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                added_data_cut2_reg[patch_h][patch_w] <= added_data_cut2_mat[patch_h][patch_w];
              end
            end
          end
          // pooling
          if (pooling_en) begin
            if (pooling_vld) begin
              if (pooling_cnt == 2'd3) begin
                pooling_cnt <= {(POOLING_CNT_WIDTH) {1'b0}};
              end else begin
                pooling_cnt <= pooling_cnt + 1'b1;
              end
              for (
                  pooling_patch_h = 0;
                  pooling_patch_h < POOLING_PATCH_SIZE;
                  pooling_patch_h = pooling_patch_h + 1
              ) begin
                for (
                    pooling_patch_w = 0;
                    pooling_patch_w < POOLING_PATCH_SIZE;
                    pooling_patch_w = pooling_patch_w + 1
                ) begin
                  pooling_data_reg[pooling_patch_h][pooling_patch_w] <= pooling_patch_data_mat[pooling_patch_h][pooling_patch_w];
                  pooling_data_reg[pooling_patch_h][pooling_patch_w+POOLING_PATCH_SIZE] <= pooling_data_reg[pooling_patch_h][pooling_patch_w];
                  pooling_data_reg[pooling_patch_h+POOLING_PATCH_SIZE][pooling_patch_w] <= pooling_data_reg[pooling_patch_h][pooling_patch_w+POOLING_PATCH_SIZE];
                  pooling_data_reg[pooling_patch_h+POOLING_PATCH_SIZE][pooling_patch_w+POOLING_PATCH_SIZE] <= pooling_data_reg[pooling_patch_h+POOLING_PATCH_SIZE][pooling_patch_w];
                end
              end

            end
          end else begin
            if (pooling_vld) begin
              for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
                for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                  pooling_data_reg[patch_h][patch_w] <= added_data_cut2_reg[patch_h][patch_w];
                end
              end
            end
          end
          if (relu_vld) begin
            patch_cnt <= patch_cnt + 1'b1;
            for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
              for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                added_data_reg[patch_h][patch_w] <= relu_data_mat[patch_h][patch_w];
              end
            end
          end

          // channel conv over 
          case (fms_size_mode)
            x8x8: begin
              chn_over <= relu_vld ? 1'b1 : chn_over;
            end
            x16x16: begin
              if (pooling_en) begin
                chn_over <= relu_vld ? 1'b1 : chn_over;
              end else begin
                chn_over <= (relu_vld && patch_cnt == 4'd3) ? 1'b1 : chn_over;
              end
            end
            x32x32: begin
              if (pooling_en) begin
                chn_over <= (relu_vld && patch_cnt == 4'd3) ? 1'b1 : chn_over;
              end else begin
                chn_over <= (relu_vld && patch_cnt == 4'd15) ? 1'b1 : chn_over;
              end
            end
            default: begin
              chn_over <= 1'b0;
            end
          endcase
        end
        default: begin
          patch_cnt <= {(PATCH_CNT_WIDTH) {1'b0}};
          conv3_wght_cnt <= 4'b0;
          cut1_vld <= 1'b0;
          added_data_to_accum_vld <= 1'b0;
        end
      endcase
    end
  end

  // 状态机
  always @(*) begin
    case (c_state)
      IDLE: begin
        n_state = addition_en ? (addition_mode ? CAL_2_ACCUM : CAL_2_SRAM) : IDLE;
      end

      // 多复习
      CAL_2_SRAM: begin
        case (fms_size_mode)
          x8x8: n_state = relu_vld ? IDLE : CAL_2_SRAM;
          x16x16:
          n_state = pooling_en ? (relu_vld ? IDLE : CAL_2_SRAM) : (patch_cnt==4'd3 && relu_vld) ? IDLE : CAL_2_SRAM;
          x32x32:
          n_state = pooling_en ? ((patch_cnt==4'd3 && relu_vld) ? IDLE : CAL_2_SRAM) : (patch_cnt==4'd15 && relu_vld) ? IDLE : CAL_2_SRAM;
          default: n_state = IDLE;
        endcase
      end
      CAL_2_ACCUM: begin
        case (fms_size_mode)
          x8x8: n_state = (conv3_wght_cnt == 4'd8 && cut1_vld) ? OUTPUT : CAL_2_ACCUM;
          x16x16:
          n_state = (conv3_wght_cnt==4'd8 && patch_cnt==4'd3 && cut1_vld) ? OUTPUT : CAL_2_ACCUM;
          x32x32:
          n_state = (conv3_wght_cnt==4'd8 && patch_cnt==4'd15 && cut1_vld) ? OUTPUT : CAL_2_ACCUM;
          default: n_state = IDLE;
        endcase
      end
      OUTPUT: begin
        case (fms_size_mode)
          x8x8: n_state = relu_vld ? IDLE : OUTPUT;
          x16x16:
          n_state = pooling_en ? (relu_vld ? IDLE : OUTPUT) : (patch_cnt==4'd3 && relu_vld) ? IDLE : OUTPUT;
          x32x32:
          n_state = pooling_en ? ((patch_cnt==4'd3 && relu_vld) ? IDLE : OUTPUT) : (patch_cnt==4'd15 && relu_vld) ? IDLE : OUTPUT;
          default: n_state = IDLE;
        endcase
      end
      default: n_state = IDLE;
    endcase
  end

  always @(*) begin
    // 判断截断位置
    if(head_cut_position>=(ADDED_DATA_CUT1_WIDTH-1) && head_cut_position<=(ADDED_DATA_WIDTH-2)) begin // 在31 -> 11之间
      for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
        for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
          added_data_cut1_mat[patch_h][patch_w] = {
            adder_tree_output_reg[patch_h][patch_w][ADDED_DATA_WIDTH-1],
            adder_tree_output_reg[patch_h][patch_w][head_cut_position-:ADDED_DATA_CUT1_WIDTH]
          };
        end
      end
    end else begin  // 如果截断位置不对，就从最高位开始砍
      for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
        for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
          added_data_cut1_mat[patch_h][patch_w] = {
            adder_tree_output_reg[patch_h][patch_w][ADDED_DATA_WIDTH-1],
            adder_tree_output_reg[patch_h][patch_w][0+:(ADDED_DATA_CUT1_WIDTH-1)],
            {1'b0}
          };
        end
      end
    end
    //cut2
    if (addition_mode) begin  // 1x1 Conv
      for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
        for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
          added_data_cut2_mat[patch_h][patch_w] = accumed_data_mat[patch_h][patch_w][ADDED_DATA_CUT1_WIDTH-1 - ADDED_DATA_CUT2_WIDTH] ? 
                                                            accumed_data_mat[patch_h][patch_w][ADDED_DATA_CUT1_WIDTH-1 -: ADDED_DATA_CUT2_WIDTH]+1 : 
                                                            accumed_data_mat[patch_h][patch_w][ADDED_DATA_CUT1_WIDTH-1 -: ADDED_DATA_CUT2_WIDTH];
        end
      end
    end else begin  // 3x3 Conv
      for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
        for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
          added_data_cut2_mat[patch_h][patch_w] = added_data_cut1_reg[patch_h][patch_w][ADDED_DATA_CUT1_WIDTH-1 - ADDED_DATA_CUT2_WIDTH] ? 
                                                            added_data_cut1_reg[patch_h][patch_w][ADDED_DATA_CUT1_WIDTH-1 -: ADDED_DATA_CUT2_WIDTH]+1 :
                                                            added_data_cut1_reg[patch_h][patch_w][ADDED_DATA_CUT1_WIDTH-1 -: ADDED_DATA_CUT2_WIDTH];
        end
      end
    end
  end
endmodule
