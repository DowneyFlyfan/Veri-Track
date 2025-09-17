`timescale 1ns / 100ps
module tb_hessian_conv;

  // Parameters
  localparam ROI_SIZE = 64;
  localparam ROI_AREA = ROI_SIZE * ROI_SIZE;
  localparam PORT_BITS = 128;

  localparam KERNEL_SIZE = 5;
  localparam KERNEL_AREA = KERNEL_SIZE * KERNEL_SIZE;
  localparam PAD_SIZE = (KERNEL_SIZE - 1) / 2;
  localparam KERNEL_NUM = 3;

  localparam IN_WIDTH = 8;
  localparam KERNEL_DATA_WIDTH = 16;
  localparam OUT_WIDTH = IN_WIDTH + KERNEL_DATA_WIDTH + $clog2(KERNEL_AREA);

  localparam IN_NUM_PER_CYCLE = PORT_BITS / IN_WIDTH;
  localparam CLK_PERIOD = 10;
  localparam PIXELS_OUT_PER_CYCLE = 2;

  // Signals
  logic clk;
  logic clk_en;
  logic rst_n;

  // Memory for file I/O
  reg signed [KERNEL_DATA_WIDTH-1:0] kernel_vec[KERNEL_NUM*KERNEL_SIZE*KERNEL_SIZE-1:0];
  reg signed [IN_WIDTH-1:0] in_img[ROI_AREA-1:0];

  // DUT I/O
  logic signed [KERNEL_DATA_WIDTH-1:0] kernel_mat[KERNEL_NUM-1:0][KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];
  logic signed [PORT_BITS-1:0] din;
  logic signed [OUT_WIDTH-1:0] dout[KERNEL_NUM-1:0][PIXELS_OUT_PER_CYCLE- 1:0];
  logic signed [OUT_WIDTH-1:0] out_img[KERNEL_NUM-1:0][ROI_AREA-1:0];
  logic conv_out_vld;
  logic ready;
  integer in_pixel_idx;
  integer out_pixel_idx;

  hessian_conv #(
      .ROI_SIZE(ROI_SIZE),
      .PORT_BITS(PORT_BITS),
      .IN_WIDTH(IN_WIDTH),
      .KERNEL_SIZE(KERNEL_SIZE),
      .KERNEL_DATA_WIDTH(KERNEL_DATA_WIDTH),
      .KERNEL_NUM(KERNEL_NUM),
      .PIXELS_OUT_PER_CYCLE(PIXELS_OUT_PER_CYCLE)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .clk_en(clk_en),
      .data_in(din),
      .kernel(kernel_mat),
      .data_out(dout),
      .conv_out_vld(conv_out_vld),
      .ready(ready)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // Connect kernels
  genvar n, h, w;
  generate
    for (n = 0; n < KERNEL_NUM; n = n + 1) begin : gen_kernel_connections
      for (h = 0; h < KERNEL_SIZE; h = h + 1) begin
        for (w = 0; w < KERNEL_SIZE; w = w + 1) begin
          assign kernel_mat[n][h][w] = signed'(kernel_vec[n*KERNEL_AREA+h*KERNEL_SIZE+w]);
        end
      end
    end
  endgenerate

  // Main process to drive inputs, control simulation, and handle outputs
  initial begin
    $dumpfile("waveform.fst");
    $dumpvars;
    in_pixel_idx = 0;
    out_pixel_idx = 0;

    // Initialize signals and load data
    din = '0;

    // $readmemh("D:\\Vivado\\Vivado_Projects\\Conv\\Codes\\texts\\input_img.txt", in_img);
    // $readmemh("D:\\Vivado\\Vivado_Projects\\Conv\\Codes\\texts\\hessian_kernel.txt", kernel_vec);

    $readmemh("../texts/input_img.txt", in_img);
    $readmemh("../texts/hessian_kernel.txt", kernel_vec);

    // Reset
    clk_en = 1'b1;

    rst_n  = 1'b0;
    @(negedge clk);
    rst_n = 1'b1;

    // Start Conv
    while (out_pixel_idx < ROI_AREA) begin
      // Drive inputs When enabled
      @(negedge clk);
      if (ready) begin
        if (in_pixel_idx < ROI_AREA) begin
          for (int i = 0; i < IN_NUM_PER_CYCLE; i++) begin
            din[(i+1)*IN_WIDTH-1-:IN_WIDTH] = signed'(in_img[in_pixel_idx+i]);
          end
          in_pixel_idx = in_pixel_idx + IN_NUM_PER_CYCLE;
        end else begin  // Send zeros
          din = '0;
        end
      end

      // Capture outputs when valid
      if (conv_out_vld) begin
        for (int i = 0; i < KERNEL_NUM; i++) begin
          for (int j = 0; j < PIXELS_OUT_PER_CYCLE; j++) begin
            out_img[i][out_pixel_idx+j] = dout[i][j];
          end
        end
        out_pixel_idx = out_pixel_idx + PIXELS_OUT_PER_CYCLE;
      end
    end

    // 4. Write output and finish simulation
    // $writememh("D:\\Vivado\\Vivado_Projects\\Conv\\Codes\\texts\\output_img.txt", out_img);
    $writememh("../texts/output_img.txt", out_img, 0);

    $display("Output written to output_img.txt! Finishing simulation.");
    $finish;
  end

endmodule
