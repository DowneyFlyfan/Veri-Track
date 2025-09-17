`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/11/01 14:57:15
// Design Name: 
// Module Name: multiplication_core
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

module multiplication_core #(
    parameter CORE_NO = 3,
    parameter FMS_PATCH_SIZE = 8,
    parameter INFMS_DATA_WIDTH = 20,
    parameter MULTIPLIED_DATA_WIDTH = INFMS_DATA_WIDTH + 8
) (
    input clk,
    input rst_n,
    input clk_en,
    input quant_mode,  //1 means INT8, 0 means INT4
    input layer_mode,  //1:fc 0:conv
    input calc_en,     //Q1: For this signal, will there be a pulse every time an INT8 or INT4 operation is performed? Q2:Will this signal come together with the data valid signal?
    input infms_data_vld,
    input [INFMS_DATA_WIDTH * FMS_PATCH_SIZE * FMS_PATCH_SIZE -1 : 0] infms_data,
    output reg multiplied_data_vld,
    output reg [MULTIPLIED_DATA_WIDTH * FMS_PATCH_SIZE * FMS_PATCH_SIZE - 1 : 0] multiplied_data
);

  localparam FC_CORE_NUM = CORE_NO % 4;

  // TODO:为什么不从0000开始
  localparam CONV_CORE_NUM0 = 4'b1110;
  localparam CONV_CORE_NUM1 = 4'b1111;
  localparam CONV_CORE_NUM2 = 4'b0001;
  localparam CONV_CORE_NUM3 = 4'b0010;
  localparam CONV_CORE_NUM4 = 4'b1100;
  localparam CONV_CORE_NUM5 = 4'b1101;
  localparam CONV_CORE_NUM6 = 4'b0011;
  localparam CONV_CORE_NUM7 = 4'b0100;
  localparam CONV_CORE_NUM8 = 4'b1010;
  localparam CONV_CORE_NUM9 = 4'b1011;
  localparam CONV_CORE_NUM10 = 4'b0101;
  localparam CONV_CORE_NUM11 = 4'b0110;
  localparam CONV_CORE_NUM12 = 4'b1000;
  localparam CONV_CORE_NUM13 = 4'b1001;
  localparam CONV_CORE_NUM14 = 4'b0111;
  localparam CONV_CORE_NUM15 = 4'b0000;

  localparam IDLE = 3'b1;
  localparam CAL_L4 = 3'b10;
  localparam CAL_H4 = 3'b100;
  reg [2:0] c_state;  //Current state
  reg [2:0] n_state;  //Next state

  reg [7:0] dsp_input_b;
  wire signed [INFMS_DATA_WIDTH-1 : 0] infms_data_mat[FMS_PATCH_SIZE-1 : 0][FMS_PATCH_SIZE-1 : 0]; // 20x8x8
  wire signed [MULTIPLIED_DATA_WIDTH : 0] dsp_output_mat [FMS_PATCH_SIZE-1 : 0][FMS_PATCH_SIZE-1 : 0]; //DSP's output width is MULTIPLIED_DATA_WIDTH+1, 29x8x8
  wire signed [MULTIPLIED_DATA_WIDTH-1 : 0] multiplied_data_mat [FMS_PATCH_SIZE-1 : 0][FMS_PATCH_SIZE-1 : 0]; // 28x8x8
  wire signed [MULTIPLIED_DATA_WIDTH-4-1 : 0]  dsp_input_c_mat [FMS_PATCH_SIZE-1 : 0][FMS_PATCH_SIZE-1 : 0];  //DSP's port C, A*B+C, 24x8x8

  genvar h, w;
  generate
    for (h = 0; h < FMS_PATCH_SIZE; h = h + 1) begin
      for (w = 0; w < FMS_PATCH_SIZE; w = w + 1) begin
        assign infms_data_mat[h][w] = infms_data[h*FMS_PATCH_SIZE*INFMS_DATA_WIDTH + w*INFMS_DATA_WIDTH +: INFMS_DATA_WIDTH];
        assign dsp_input_c_mat[h][w] = {
          multiplied_data[h*FMS_PATCH_SIZE*MULTIPLIED_DATA_WIDTH+w*MULTIPLIED_DATA_WIDTH+MULTIPLIED_DATA_WIDTH-1],
          multiplied_data[h*FMS_PATCH_SIZE*MULTIPLIED_DATA_WIDTH+w*MULTIPLIED_DATA_WIDTH +: (MULTIPLIED_DATA_WIDTH-4-1)]
        };  // 符号位 + 低23位
        assign multiplied_data_mat[h][w] = {
          dsp_output_mat[h][w][MULTIPLIED_DATA_WIDTH],
          dsp_output_mat[h][w][0+:(MULTIPLIED_DATA_WIDTH-1)]
        };
        // TODO:配置DSP Core
        multiplication_dsp_ip multiplication_dsp_ip_inst (
            .SEL(c_state[2]),
            .A  (infms_data_mat[h][w]),
            .B  (dsp_input_b),
            .C  (dsp_input_c_mat[h][w]),
            .P  (dsp_output_mat[h][w])
        );  //Mode: P = A*B +C
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

  integer hh, ww;
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      multiplied_data_vld <= 1'b0;
    end else if (clk_en) begin
      case (c_state)
        IDLE: begin
          multiplied_data_vld <= 1'b0;
          if (~layer_mode) begin  // conv
            if (CORE_NO == 0) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM0[3:0]} : {{4{CONV_CORE_NUM0[3]}},CONV_CORE_NUM0[3:0]}; // 符号位扩展
            end else if (CORE_NO == 1) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM1[3:0]} : {{4{CONV_CORE_NUM1[3]}},CONV_CORE_NUM1[3:0]};
            end else if (CORE_NO == 2) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM2[3:0]} : {{4{CONV_CORE_NUM2[3]}},CONV_CORE_NUM2[3:0]};
            end else if (CORE_NO == 3) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM3[3:0]} : {{4{CONV_CORE_NUM3[3]}},CONV_CORE_NUM3[3:0]};
            end else if (CORE_NO == 4) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM4[3:0]} : {{4{CONV_CORE_NUM4[3]}},CONV_CORE_NUM4[3:0]};
            end else if (CORE_NO == 5) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM5[3:0]} : {{4{CONV_CORE_NUM5[3]}},CONV_CORE_NUM5[3:0]};
            end else if (CORE_NO == 6) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM6[3:0]} : {{4{CONV_CORE_NUM6[3]}},CONV_CORE_NUM6[3:0]};
            end else if (CORE_NO == 7) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM7[3:0]} : {{4{CONV_CORE_NUM7[3]}},CONV_CORE_NUM7[3:0]};
            end else if (CORE_NO == 8) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM8[3:0]} : {{4{CONV_CORE_NUM8[3]}},CONV_CORE_NUM8[3:0]};
            end else if (CORE_NO == 9) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM9[3:0]} : {{4{CONV_CORE_NUM9[3]}},CONV_CORE_NUM9[3:0]};
            end else if (CORE_NO == 10) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM10[3:0]} : {{4{CONV_CORE_NUM10[3]}},CONV_CORE_NUM10[3:0]};
            end else if (CORE_NO == 11) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM11[3:0]} : {{4{CONV_CORE_NUM11[3]}},CONV_CORE_NUM11[3:0]};
            end else if (CORE_NO == 12) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM12[3:0]} : {{4{CONV_CORE_NUM12[3]}},CONV_CORE_NUM12[3:0]};
            end else if (CORE_NO == 13) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM13[3:0]} : {{4{CONV_CORE_NUM13[3]}},CONV_CORE_NUM13[3:0]};
            end else if (CORE_NO == 14) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM14[3:0]} : {{4{CONV_CORE_NUM14[3]}},CONV_CORE_NUM14[3:0]};
            end else if (CORE_NO == 15) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM15[3:0]} : {{4{CONV_CORE_NUM15[3]}},CONV_CORE_NUM15[3:0]};
            end
          end else begin  //fc
            if (FC_CORE_NUM == 0) begin
              dsp_input_b <= 8'b0000_0001;
            end else if (FC_CORE_NUM == 1) begin
              dsp_input_b <= 8'b0000_0010;
            end else if (FC_CORE_NUM == 2) begin
              dsp_input_b <= 8'b0000_0100;
            end else if (FC_CORE_NUM == 3) begin
              dsp_input_b <= 8'b1111_1000;
            end
          end
          // 输出
          if (calc_en && infms_data_vld) begin
            for (hh = 0; hh < FMS_PATCH_SIZE; hh = hh + 1) begin
              for (ww = 0; ww < FMS_PATCH_SIZE; ww = ww + 1) begin
                multiplied_data[hh*FMS_PATCH_SIZE*MULTIPLIED_DATA_WIDTH + ww*MULTIPLIED_DATA_WIDTH +: MULTIPLIED_DATA_WIDTH] <= multiplied_data_mat[hh][ww];
              end
            end
            // TODO:Why
            multiplied_data_vld <= quant_mode ? 1'b0 : 1'b1;
          end
        end

        CAL_L4: begin
          if (~layer_mode) begin  // conv
            if (CORE_NO == 0) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM0[3:0]} : {{4{CONV_CORE_NUM0[3]}},CONV_CORE_NUM0[3:0]};
            end else if (CORE_NO == 1) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM1[3:0]} : {{4{CONV_CORE_NUM1[3]}},CONV_CORE_NUM1[3:0]};
            end else if (CORE_NO == 2) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM2[3:0]} : {{4{CONV_CORE_NUM2[3]}},CONV_CORE_NUM2[3:0]};
            end else if (CORE_NO == 3) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM3[3:0]} : {{4{CONV_CORE_NUM3[3]}},CONV_CORE_NUM3[3:0]};
            end else if (CORE_NO == 4) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM4[3:0]} : {{4{CONV_CORE_NUM4[3]}},CONV_CORE_NUM4[3:0]};
            end else if (CORE_NO == 5) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM5[3:0]} : {{4{CONV_CORE_NUM5[3]}},CONV_CORE_NUM5[3:0]};
            end else if (CORE_NO == 6) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM6[3:0]} : {{4{CONV_CORE_NUM6[3]}},CONV_CORE_NUM6[3:0]};
            end else if (CORE_NO == 7) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM7[3:0]} : {{4{CONV_CORE_NUM7[3]}},CONV_CORE_NUM7[3:0]};
            end else if (CORE_NO == 8) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM8[3:0]} : {{4{CONV_CORE_NUM8[3]}},CONV_CORE_NUM8[3:0]};
            end else if (CORE_NO == 9) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM9[3:0]} : {{4{CONV_CORE_NUM9[3]}},CONV_CORE_NUM9[3:0]};
            end else if (CORE_NO == 10) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM10[3:0]} : {{4{CONV_CORE_NUM10[3]}},CONV_CORE_NUM10[3:0]};
            end else if (CORE_NO == 11) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM11[3:0]} : {{4{CONV_CORE_NUM11[3]}},CONV_CORE_NUM11[3:0]};
            end else if (CORE_NO == 12) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM12[3:0]} : {{4{CONV_CORE_NUM12[3]}},CONV_CORE_NUM12[3:0]};
            end else if (CORE_NO == 13) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM13[3:0]} : {{4{CONV_CORE_NUM13[3]}},CONV_CORE_NUM13[3:0]};
            end else if (CORE_NO == 14) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM14[3:0]} : {{4{CONV_CORE_NUM14[3]}},CONV_CORE_NUM14[3:0]};
            end else if (CORE_NO == 15) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM15[3:0]} : {{4{CONV_CORE_NUM15[3]}},CONV_CORE_NUM15[3:0]};
            end
          end else begin  //fc
            if (FC_CORE_NUM == 0) begin
              dsp_input_b <= 8'b0000_0001;
            end else if (FC_CORE_NUM == 1) begin
              dsp_input_b <= 8'b0000_0010;
            end else if (FC_CORE_NUM == 2) begin
              dsp_input_b <= 8'b0000_0100;
            end else if (FC_CORE_NUM == 3) begin
              dsp_input_b <= 8'b1111_1000;
            end
          end

          if (infms_data_vld) begin
            for (hh = 0; hh < FMS_PATCH_SIZE; hh = hh + 1) begin
              for (ww = 0; ww < FMS_PATCH_SIZE; ww = ww + 1) begin
                multiplied_data[hh*FMS_PATCH_SIZE*MULTIPLIED_DATA_WIDTH + ww*MULTIPLIED_DATA_WIDTH +: MULTIPLIED_DATA_WIDTH] <= multiplied_data_mat[hh][ww];
              end
            end
            multiplied_data_vld <= quant_mode ? 1'b0 : 1'b1;
          end
        end
        CAL_H4: begin  // 补0
          if (CORE_NO == 0) begin
            dsp_input_b <= {CONV_CORE_NUM0[3:0], 4'b0};
          end else if (CORE_NO == 1) begin
            dsp_input_b <= {CONV_CORE_NUM1[3:0], 4'b0};
          end else if (CORE_NO == 2) begin
            dsp_input_b <= {CONV_CORE_NUM2[3:0], 4'b0};
          end else if (CORE_NO == 3) begin
            dsp_input_b <= {CONV_CORE_NUM3[3:0], 4'b0};
          end else if (CORE_NO == 4) begin
            dsp_input_b <= {CONV_CORE_NUM4[3:0], 4'b0};
          end else if (CORE_NO == 5) begin
            dsp_input_b <= {CONV_CORE_NUM5[3:0], 4'b0};
          end else if (CORE_NO == 6) begin
            dsp_input_b <= {CONV_CORE_NUM6[3:0], 4'b0};
          end else if (CORE_NO == 7) begin
            dsp_input_b <= {CONV_CORE_NUM7[3:0], 4'b0};
          end else if (CORE_NO == 8) begin
            dsp_input_b <= {CONV_CORE_NUM8[3:0], 4'b0};
          end else if (CORE_NO == 9) begin
            dsp_input_b <= {CONV_CORE_NUM9[3:0], 4'b0};
          end else if (CORE_NO == 10) begin
            dsp_input_b <= {CONV_CORE_NUM10[3:0], 4'b0};
          end else if (CORE_NO == 11) begin
            dsp_input_b <= {CONV_CORE_NUM11[3:0], 4'b0};
          end else if (CORE_NO == 12) begin
            dsp_input_b <= {CONV_CORE_NUM12[3:0], 4'b0};
          end else if (CORE_NO == 13) begin
            dsp_input_b <= {CONV_CORE_NUM13[3:0], 4'b0};
          end else if (CORE_NO == 14) begin
            dsp_input_b <= {CONV_CORE_NUM14[3:0], 4'b0};
          end else if (CORE_NO == 15) begin
            dsp_input_b <= {CONV_CORE_NUM15[3:0], 4'b0};
          end
          if (infms_data_vld) begin
            for (hh = 0; hh < FMS_PATCH_SIZE; hh = hh + 1) begin
              for (ww = 0; ww < FMS_PATCH_SIZE; ww = ww + 1) begin
                multiplied_data[hh*FMS_PATCH_SIZE*MULTIPLIED_DATA_WIDTH + ww*MULTIPLIED_DATA_WIDTH +: MULTIPLIED_DATA_WIDTH] <= multiplied_data_mat[hh][ww];
              end
            end
            multiplied_data_vld <= 1'b1;
          end
        end
        default: begin
          multiplied_data_vld <= 1'b0;
          if (~layer_mode) begin  // conv
            if (CORE_NO == 0) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM0[3:0]} : {{4{CONV_CORE_NUM0[3]}},CONV_CORE_NUM0[3:0]};
            end else if (CORE_NO == 1) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM1[3:0]} : {{4{CONV_CORE_NUM1[3]}},CONV_CORE_NUM1[3:0]};
            end else if (CORE_NO == 2) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM2[3:0]} : {{4{CONV_CORE_NUM2[3]}},CONV_CORE_NUM2[3:0]};
            end else if (CORE_NO == 3) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM3[3:0]} : {{4{CONV_CORE_NUM3[3]}},CONV_CORE_NUM3[3:0]};
            end else if (CORE_NO == 4) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM4[3:0]} : {{4{CONV_CORE_NUM4[3]}},CONV_CORE_NUM4[3:0]};
            end else if (CORE_NO == 5) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM5[3:0]} : {{4{CONV_CORE_NUM5[3]}},CONV_CORE_NUM5[3:0]};
            end else if (CORE_NO == 6) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM6[3:0]} : {{4{CONV_CORE_NUM6[3]}},CONV_CORE_NUM6[3:0]};
            end else if (CORE_NO == 7) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM7[3:0]} : {{4{CONV_CORE_NUM7[3]}},CONV_CORE_NUM7[3:0]};
            end else if (CORE_NO == 8) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM8[3:0]} : {{4{CONV_CORE_NUM8[3]}},CONV_CORE_NUM8[3:0]};
            end else if (CORE_NO == 9) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM9[3:0]} : {{4{CONV_CORE_NUM9[3]}},CONV_CORE_NUM9[3:0]};
            end else if (CORE_NO == 10) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM10[3:0]} : {{4{CONV_CORE_NUM10[3]}},CONV_CORE_NUM10[3:0]};
            end else if (CORE_NO == 11) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM11[3:0]} : {{4{CONV_CORE_NUM11[3]}},CONV_CORE_NUM11[3:0]};
            end else if (CORE_NO == 12) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM12[3:0]} : {{4{CONV_CORE_NUM12[3]}},CONV_CORE_NUM12[3:0]};
            end else if (CORE_NO == 13) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM13[3:0]} : {{4{CONV_CORE_NUM13[3]}},CONV_CORE_NUM13[3:0]};
            end else if (CORE_NO == 14) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM14[3:0]} : {{4{CONV_CORE_NUM14[3]}},CONV_CORE_NUM14[3:0]};
            end else if (CORE_NO == 15) begin
              dsp_input_b <= quant_mode ? {4'b0,CONV_CORE_NUM15[3:0]} : {{4{CONV_CORE_NUM15[3]}},CONV_CORE_NUM15[3:0]};
            end
          end else begin  //fc
            if (FC_CORE_NUM == 0) begin
              dsp_input_b <= 8'b0000_0001;
            end else if (FC_CORE_NUM == 1) begin
              dsp_input_b <= 8'b0000_0010;
            end else if (FC_CORE_NUM == 2) begin
              dsp_input_b <= 8'b0000_0100;
            end else if (FC_CORE_NUM == 3) begin
              dsp_input_b <= 8'b1111_1000;
            end
          end
        end
      endcase
    end
  end

  always @(*) begin
    case (c_state)
      IDLE: n_state = calc_en ? (infms_data_vld ? (quant_mode ? CAL_H4 : IDLE) : CAL_L4) : IDLE;
      CAL_L4: n_state = infms_data_vld ? (quant_mode ? CAL_H4 : IDLE) : CAL_L4;
      CAL_H4: n_state = infms_data_vld ? IDLE : CAL_H4;
      default: n_state = IDLE;
    endcase
  end

endmodule
