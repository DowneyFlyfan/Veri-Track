// This module encapsulates the hessian_conv and manages I/O
module top_hessian_conv #(
    parameter ROI_SIZE = 480,
    parameter PORT_BITS = 32,
    parameter IN_WIDTH = 8,
    parameter KERNEL_SIZE = 5,
    parameter KERNEL_DATA_WIDTH = 16,
    parameter KERNEL_NUM = 3,

    parameter KERNEL_AREA = KERNEL_SIZE * KERNEL_SIZE,
    parameter INPUT_NUM = KERNEL_AREA,
    parameter MULTIPLIED_WIDTH = IN_WIDTH + KERNEL_DATA_WIDTH,
    parameter OUT_WIDTH = MULTIPLIED_WIDTH + $clog2(INPUT_NUM),
    parameter NUM_PER_CYCLE = PORT_BITS / IN_WIDTH
) (
    input clk,
    input rst_n,
    input clk_en,

    // AXI4-Stream input for image data
    input logic [PORT_BITS - 1:0] axis_data_in_tdata,
    input logic axis_data_in_tvalid,
    output logic axis_data_in_tready,

    // AXI4-Stream output for convolution results
    output logic [OUT_WIDTH * KERNEL_NUM * NUM_PER_CYCLE - 1:0] axis_data_out_tdata,
    output logic axis_data_out_tvalid,
    input logic axis_data_out_tready,

    // AXI-Lite for kernel configuration
    input logic [31:0] kernel_addr,
    input logic [KERNEL_DATA_WIDTH - 1:0] kernel_data_in,
    input logic kernel_write_en
);

  // Params
  localparam PAD_SIZE = (KERNEL_SIZE - 1) / 2;
  localparam BUF_WIDTH = ROI_SIZE + 2 * PAD_SIZE;
  localparam HW_BITS = $clog2(ROI_SIZE);
  localparam BUF_WIDTH_BITS = $clog2(BUF_WIDTH);
  localparam KERNEL_BITS = $clog2(KERNEL_SIZE);
  localparam FIRST_RIGHT_PAD_IDX = ROI_SIZE + PAD_SIZE;
  localparam IMG_BOTTOM_KERNEL_IDX = BUF_WIDTH - PAD_SIZE - KERNEL_SIZE;
  localparam CONV_MAT_RIGHT_IDX = NUM_PER_CYCLE - PAD_SIZE;
  localparam ADDER_LATENCY = $clog2(INPUT_NUM) + 2;

  // Internal BRAM to store kernel data
  // The kernel is flattened into a 1D array for simpler BRAM access
  localparam KERNEL_TOTAL_NUM = KERNEL_NUM * KERNEL_AREA;
  logic signed [KERNEL_DATA_WIDTH - 1:0] kernel_bram[KERNEL_TOTAL_NUM - 1:0];

  // Internal signals for hessian_conv instantiation
  logic [PORT_BITS - 1:0] hessian_data_in;
  logic signed [KERNEL_DATA_WIDTH - 1:0] hessian_kernel[KERNEL_NUM-1:0][KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];
  logic signed [OUT_WIDTH-1:0] hessian_data_out[KERNEL_NUM-1:0][NUM_PER_CYCLE - 1:0];
  logic hessian_conv_out_vld;
  logic hessian_read_en;

  // State machine and control logic for AXI-Stream
  reg [2:0] stream_state;
  localparam S_IDLE = 3'b001, S_READ = 3'b010, S_WRITE = 3'b100;

  reg read_en_reg;
  reg write_en_reg;

  // AXI-Lite write logic to BRAM
  // Maps AXI-Lite address to BRAM index and writes data
  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      // Reset
    end else if (kernel_write_en) begin
      kernel_bram[kernel_addr] <= kernel_data_in;
    end
  end

  // Unflatten BRAM data to the multi-dimensional kernel array
  // This allows the original module to be used unchanged
  genvar c, h, w;
  generate
    for (c = 0; c < KERNEL_NUM; c = c + 1) begin
      for (h = 0; h < KERNEL_SIZE; h = h + 1) begin
        for (w = 0; w < KERNEL_SIZE; w = w + 1) begin
          assign hessian_kernel[c][h][w] = kernel_bram[c*KERNEL_AREA+h*KERNEL_SIZE+w];
        end
      end
    end
  endgenerate

  // AXI-Stream input to internal data_in
  assign axis_data_in_tready = hessian_read_en;
  assign hessian_data_in = (axis_data_in_tvalid && axis_data_in_tready) ? axis_data_in_tdata : 0;

  // AXI-Stream output from internal data_out
  assign axis_data_out_tvalid = hessian_conv_out_vld;
  assign axis_data_out_tdata = {
    hessian_data_out[KERNEL_NUM-1][NUM_PER_CYCLE-1],
    hessian_data_out[KERNEL_NUM-1][NUM_PER_CYCLE-2],
    // All other elements
    hessian_data_out[0][1],
    hessian_data_out[0][0]
  };

  // Instantiate your original module
  hessian_conv #(
      .ROI_SIZE(ROI_SIZE),
      .PORT_BITS(PORT_BITS),
      .IN_WIDTH(IN_WIDTH),
      .KERNEL_SIZE(KERNEL_SIZE),
      .KERNEL_DATA_WIDTH(KERNEL_DATA_WIDTH),
      .KERNEL_NUM(KERNEL_NUM),
  ) hessian_conv_inst (
      .clk(clk),
      .rst_n(rst_n),
      .clk_en(clk_en),
      .data_in(hessian_data_in),
      .kernel(hessian_kernel),
      .data_out(hessian_data_out),
      .conv_out_vld(hessian_conv_out_vld),
      .read_en(hessian_read_en)
  );
endmodule
