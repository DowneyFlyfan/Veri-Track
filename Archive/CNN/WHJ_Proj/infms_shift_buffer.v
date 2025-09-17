`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/1/10 13:18:58
// Design Name: 
// Module Name: infms_shift_buffer
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

module infms_shift_buffer #(
    parameter VALID_CORE_NUM = 16,
    parameter FMS_PATCH_SIZE = 8,
    parameter OUTPUT_DATA_WIDTH = 20,
    parameter INPUT_DATA_WGHT_NUM = 4
) (
    input clk,
    input rst_n,
    input clk_en,

    input shft_sm_en,
    input shft_bg_en,
    input add_en,
    input rst_en,
    input idle,

    input [INPUT_DATA_WGHT_NUM*FMS_PATCH_SIZE*FMS_PATCH_SIZE*OUTPUT_DATA_WIDTH-1 : 0] din,
    output [VALID_CORE_NUM*FMS_PATCH_SIZE*FMS_PATCH_SIZE*OUTPUT_DATA_WIDTH-1 : 0] dout
);

  // localparam RST     = 5'b00001;
  localparam ADD = 5'b00010;
  localparam SHFT_SM = 5'b00100;
  localparam SHFT_BG = 5'b01000;
  localparam IDLE = 5'b10000;
  wire [4:0] c_state;
  assign c_state = {idle, shft_bg_en, shft_sm_en, add_en, rst_en};

  wire [OUTPUT_DATA_WIDTH-1 : 0] din_mat [INPUT_DATA_WGHT_NUM-1 : 0][FMS_PATCH_SIZE-1 : 0][FMS_PATCH_SIZE-1 : 0];
  reg [OUTPUT_DATA_WIDTH-1 : 0] dout_mat [VALID_CORE_NUM-1 : 0][FMS_PATCH_SIZE-1 : 0][FMS_PATCH_SIZE-1 : 0];

  genvar h, w, core_no;
  generate
    for (core_no = 0; core_no < VALID_CORE_NUM; core_no = core_no + 1) begin
      for (h = 0; h < FMS_PATCH_SIZE; h = h + 1) begin
        for (w = 0; w < FMS_PATCH_SIZE; w = w + 1) begin
          assign dout[(core_no*FMS_PATCH_SIZE*FMS_PATCH_SIZE+h*FMS_PATCH_SIZE+w)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = dout_mat[core_no][h][w];
        end
      end
    end
    for (core_no = 0; core_no < INPUT_DATA_WGHT_NUM; core_no = core_no + 1) begin
      for (h = 0; h < FMS_PATCH_SIZE; h = h + 1) begin
        for (w = 0; w < FMS_PATCH_SIZE; w = w + 1) begin
          assign din_mat[core_no][h][w] = din[(core_no*FMS_PATCH_SIZE*FMS_PATCH_SIZE+h*FMS_PATCH_SIZE+w)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
        end
      end
    end
  endgenerate

  integer patch_h, patch_w, wght_no, vld_core_no;
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      for (wght_no = 0; wght_no < INPUT_DATA_WGHT_NUM; wght_no = wght_no + 1) begin
        for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
          for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
            dout_mat[wght_no+VALID_CORE_NUM-INPUT_DATA_WGHT_NUM][patch_h][patch_w] <= {(OUTPUT_DATA_WIDTH){1'b0}};
          end
        end
      end
    end else if (clk_en) begin
      case (c_state)
        // RST: begin
        //     for(wght_no=0; wght_no<INPUT_DATA_WGHT_NUM; wght_no=wght_no+1) begin
        //         for(patch_h=0;patch_h<FMS_PATCH_SIZE;patch_h=patch_h+1) begin
        //             for(patch_w=0;patch_w<FMS_PATCH_SIZE;patch_w=patch_w+1) begin
        //                 dout_mat[wght_no+VALID_CORE_NUM-INPUT_DATA_WGHT_NUM][patch_h][patch_w] <= {(OUTPUT_DATA_WIDTH){1'b0}};
        //             end
        //         end
        //     end
        // end
        ADD: begin
          for (wght_no = 0; wght_no < INPUT_DATA_WGHT_NUM; wght_no = wght_no + 1) begin
            for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
              for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                dout_mat[wght_no+VALID_CORE_NUM-INPUT_DATA_WGHT_NUM][patch_h][patch_w] <= 
                                        dout_mat[wght_no+VALID_CORE_NUM-INPUT_DATA_WGHT_NUM][patch_h][patch_w] + din_mat[wght_no][patch_h][patch_w];
              end
            end
          end
        end
        //change wght's order, e.g. 3-2-1-0 to 2-1-0-3
        SHFT_SM: begin
          for (wght_no = 0; wght_no < INPUT_DATA_WGHT_NUM; wght_no = wght_no + 1) begin
            for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
              for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                if (wght_no == 0) begin
                  dout_mat[VALID_CORE_NUM-INPUT_DATA_WGHT_NUM][patch_h][patch_w] <=
                                        dout_mat[VALID_CORE_NUM-1][patch_h][patch_w];
                end else begin
                  dout_mat[wght_no+VALID_CORE_NUM-INPUT_DATA_WGHT_NUM][patch_h][patch_w] <=
                                        dout_mat[wght_no+VALID_CORE_NUM-INPUT_DATA_WGHT_NUM-1][patch_h][patch_w];
                end
              end
            end
          end
        end
        //change wght's value, e.g. 3-2-1-0 to 7-6-5-4
        SHFT_BG: begin
          for (wght_no = 0; wght_no < VALID_CORE_NUM; wght_no = wght_no + 1) begin
            for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
              for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                if (wght_no < (VALID_CORE_NUM - INPUT_DATA_WGHT_NUM)) begin
                  dout_mat[wght_no][patch_h][patch_w] <= dout_mat[wght_no+INPUT_DATA_WGHT_NUM][patch_h][patch_w];
                end else begin
                  dout_mat[wght_no][patch_h][patch_w] <= dout_mat[wght_no-(VALID_CORE_NUM-INPUT_DATA_WGHT_NUM)][patch_h][patch_w];
                end
              end
            end
          end
        end
        IDLE: begin
          for (vld_core_no = 0; vld_core_no < VALID_CORE_NUM; vld_core_no = vld_core_no + 1) begin
            for (patch_h = 0; patch_h < FMS_PATCH_SIZE; patch_h = patch_h + 1) begin
              for (patch_w = 0; patch_w < FMS_PATCH_SIZE; patch_w = patch_w + 1) begin
                dout_mat[vld_core_no][patch_h][patch_w] <= {(OUTPUT_DATA_WIDTH) {1'b0}};
              end
            end
          end
        end
      endcase
    end
  end

endmodule
