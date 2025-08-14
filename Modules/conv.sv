`timescale 1ns / 100ps
// WARN:目前只考虑ROI_SIZE是IN_NUM_PER_CYCLE的整数倍

module conv #(
    parameter ROI_SIZE  = 480,
    parameter PORT_BITS = 128,
    parameter IN_WIDTH  = 8,

    parameter SOBEL_KERNEL_SIZE = 3,
    parameter SOBEL_KERNEL_DATA_WIDTH = 4,
    parameter SOBEL_KERNEL_NUM = 2,

    parameter HESSIAN_KERNEL_SIZE = 5,
    parameter HESSIAN_KERNEL_DATA_WIDTH = 16,
    parameter HESSIAN_KERNEL_NUM = 3,

    parameter PIXELS_OUT_PER_CYCLE = 2,

    // TODO: 
    // WARN: 
    parameter SOBEL_INPUT_NUM = SOBEL_KERNEL_SIZE * SOBEL_KERNEL_SIZE * SOBEL_KERNEL_NUM,
    parameter SOBEL_MULTIPLIED_WIDTH = IN_WIDTH + SOBEL_KERNEL_DATA_WIDTH,
    parameter SOBEL_OUT_WIDTH = SOBEL_MULTIPLIED_WIDTH + $clog2(SOBEL_INPUT_NUM),

    parameter IN_NUM_PER_CYCLE = PORT_BITS / IN_WIDTH,
    parameter READ_CONV_RATIO  = IN_NUM_PER_CYCLE / PIXELS_OUT_PER_CYCLE
) (
    input clk,
    input rst_n,
    input clk_en,
    input logic [PORT_BITS - 1:0] data_in,
    input logic signed [KERNEL_DATA_WIDTH - 1:0] sobel_kernel[KERNEL_NUM-1:0][KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
    output logic signed [OUT_WIDTH-1:0] data_out[PIXELS_OUT_PER_CYCLE- 1:0]
);
  logic sobel_valid;
  logic sobel_ready;

endmodule
