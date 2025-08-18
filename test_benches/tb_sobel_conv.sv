`timescale 1ns / 100ps
module tb_sobel_conv;

  // Parameters
  localparam ROI_SIZE = 64;
  localparam ROI_AREA = ROI_SIZE * ROI_SIZE;
  localparam PORT_BITS = 128;
  localparam CLK_PERIOD = 10;
  localparam PIXELS_OUT_PER_CYCLE = 2;

  localparam IN_WIDTH = 8;
  localparam KERNEL_DATA_WIDTH = 4;
  localparam OUT_WIDTH = IN_WIDTH + 4;
  localparam MASK_SIZE = 6;

  localparam KERNEL_SIZE = 3;
  localparam PAD_SIZE = (KERNEL_SIZE - 1) / 2;
  localparam KERNEL_NUM = 2;

  localparam CORE_NUM = KERNEL_SIZE * KERNEL_SIZE * KERNEL_NUM;
  localparam KERNEL_AREA = KERNEL_SIZE * KERNEL_SIZE;
  localparam IN_NUM_PER_CYCLE = PORT_BITS / IN_WIDTH;

  // Signals
  logic clk;
  logic clk_en;
  logic rst_n;

  // Memory for file I/O
  reg signed [KERNEL_DATA_WIDTH-1:0] kernel_vec[KERNEL_NUM*KERNEL_SIZE*KERNEL_SIZE-1:0];
  reg [IN_WIDTH-1:0] in_img[ROI_AREA-1:0];
  reg signed [OUT_WIDTH-1:0] out_img[ROI_AREA-1:0];

  // DUT I/O
  logic signed [KERNEL_DATA_WIDTH-1:0] kernel_mat[KERNEL_NUM-1:0][KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];
  logic [PORT_BITS-1:0] din;
  logic signed [OUT_WIDTH-1:0] sobel_dout[PIXELS_OUT_PER_CYCLE- 1:0];
  logic signed [OUT_WIDTH-1:0] dout[PIXELS_OUT_PER_CYCLE- 1:0];
  logic signed [OUT_WIDTH-1:0] max;
  logic sobel_conv_valid, dout_valid, ready;

  integer in_pixel_idx;
  integer out_pixel_idx;

  max_mask #(
      .ROI_SIZE(ROI_SIZE),
      .IN_WIDTH(OUT_WIDTH),
      .OUT_WIDTH(OUT_WIDTH),
      .MASK_SIZE(MASK_SIZE),
      .NUM_PER_CYCLE(PIXELS_OUT_PER_CYCLE)
  ) max_mask_inst (
      .clk(clk),
      .rst_n(rst_n),
      .clk_en(clk_en),
      .max(max),
      .din(sobel_dout),
      .din_valid(sobel_conv_valid),
      .dout_valid(dout_valid),
      .dout(dout)
  );

  sobel_conv #(
      .ROI_SIZE(ROI_SIZE),
      .PORT_BITS(PORT_BITS),
      .IN_WIDTH(IN_WIDTH),
      .KERNEL_SIZE(KERNEL_SIZE),
      .KERNEL_DATA_WIDTH(KERNEL_DATA_WIDTH),
      .KERNEL_NUM(KERNEL_NUM),
      .PIXELS_OUT_PER_CYCLE(PIXELS_OUT_PER_CYCLE)
  ) sobel_conv_inst (
      .clk(clk),
      .rst_n(rst_n),
      .clk_en(clk_en),
      .data_in(din),
      .kernel(kernel_mat),
      .data_out(sobel_dout),
      .valid(sobel_conv_valid),
      .ready(ready),
      .max(max)
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

    begin : Initialization_and_load
      clk_en = 1'b1;
      din = '0;

      for (int i = 0; i < ROI_AREA; i = i + 1) begin
        out_img[i] = '0;
      end
      in_pixel_idx  = 0;
      out_pixel_idx = ROI_SIZE * MASK_SIZE + MASK_SIZE;

      $readmemh("D:\\Vivado\\Vivado_Projects\\Conv\\Codes\\texts\\input_img.txt", in_img);
      $readmemb("D:\\Vivado\\Vivado_Projects\\Conv\\Codes\\texts\\sobel_kernel.txt", kernel_vec);

      // $readmemh("../texts/input_img.txt", in_img);
      // $readmemb("../texts/sobel_kernel.txt", kernel_vec);
    end

    begin : reset
      rst_n = 1'b0;
      @(negedge clk);
      rst_n = 1'b1;
    end

    while (out_pixel_idx < ROI_AREA) begin : IO
      @(negedge clk);
      if (ready) begin : read
        if (in_pixel_idx < ROI_AREA) begin
          for (int i = 0; i < IN_NUM_PER_CYCLE; i++) begin
            din[(i+1)*IN_WIDTH-1-:IN_WIDTH] = in_img[in_pixel_idx+i];
          end
          in_pixel_idx = in_pixel_idx + IN_NUM_PER_CYCLE;
        end else begin  // Send zeros
          din = '0;
        end
      end

      if (dout_valid) begin : write
        for (int i = 0; i < PIXELS_OUT_PER_CYCLE; i++) begin
          out_img[out_pixel_idx+i] = sobel_dout[i];
        end

        if ((out_pixel_idx + PIXELS_OUT_PER_CYCLE) % (ROI_SIZE - MASK_SIZE) == 0) begin
          out_pixel_idx <= out_pixel_idx + MASK_SIZE + PIXELS_OUT_PER_CYCLE;
        end else begin
          out_pixel_idx <= out_pixel_idx + PIXELS_OUT_PER_CYCLE;
        end
      end
    end

    begin : write_and_finish
      $writememh("D:\\Vivado\\Vivado_Projects\\Conv\\Codes\\texts\\output_img.txt", out_img);
      // $writememh("../texts/output_img.txt", out_img, 0);
      $display("Output written to output_img.txt! Finishing simulation.");
      $finish;
    end

  end

endmodule
