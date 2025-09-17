`timescale 1ns / 100ps
module cumsum #(
    parameter IMG_SIZE = 480,
    parameter MASK_SIZE = 6,
    parameter IN_WIDTH = 28,
    parameter NUM_PER_CYCLE = 2,
    parameter X_SUM_WIDTH = IN_WIDTH + $clog2(IMG_SIZE),
    parameter OUT_WIDTH = X_SUM_WIDTH + $clog2(IMG_SIZE)
) (
    input clk,
    input rst_n,
    input clk_en,
    input din_valid,
    input logic ready,
    input logic signed [IN_WIDTH-1:0] din[NUM_PER_CYCLE- 1:0],
    output logic signed [OUT_WIDTH-1:0] dout[NUM_PER_CYCLE- 1:0],
    output logic dout_valid
);

  // Params
  localparam ROI_SIZE = IMG_SIZE - MASK_SIZE * 2;
  localparam PAD_SIZE = (KERNEL_SIZE - 1) / 2;

  localparam HW_BITS = $clog2(IMG_SIZE);
  localparam ADDR_BITS = $clog2(IMG_SIZE ** 2);
  localparam SUM_DELAY = NUM_PER_CYCLE;

  logic signed [X_SUM_WIDTH-1:0] x_sum_in[SUM_DELAY-1:0][NUM_PER_CYCLE- 1:0];
  logic signed [X_SUM_WIDTH-1:0] x_sum_out[NUM_PER_CYCLE- 1:0];

  logic [SUM_DELAY-1:0] counter;
  logic store_valid;
  logic [ADDR_BITS-1:0] write_addr, read_addr;

  // Indices
  logic [HW_BITS-1:0] write_w, write_h, read_w, reah_h;

  cumsum_x cumsum_x_inst (
      .clka (clk),
      .ena  (store_valid),
      .wea  (store_valid),
      .addra(write_addr),
      .dina ({x_sum_in[SUM_DELAY-1][0], x_sum_in[SUM_DELAY-1][1]}),

      .clkb (clk),
      .enb  (read_en),
      .addrb(read_addr),
      .doutb({x_sum_out[0], x_sum_out[1]})
  );

  // Main Logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      write_addr <= (MASK_SIZE * IMG_SIZE + MASK_SIZE) / NUM_PER_CYCLE;
      read_addr <= 0;
      read_h <= 0;
      read_w <= 0;
      write_h <= MASK_SIZE;
      write_w <= MASK_SIZE;

      counter <= 0;
      store_valid <= 1'b0;

      for (n = 0; n < NUM_PER_CYCLE; n++) begin
        x_sum_out[n] <= 0;
        for (d = 0; d < SUM_DELAY; d++) begin
          x_sum_in[d][n] <= 0;
        end
      end

    end else if (clk_en) begin
      if (din_valid) begin
        x_sum_in[0][0] <= din[0] + x_sum_in[1][1];
        x_sum_in[0][1] <= din[1];
        x_sum_in[1][0] <= x_sum_in[0][0];
        x_sum_in[1][1] <= x_sum_in[0][0] + x_sum_in[0][1];

        counter <= {counter[SUM_DELAY-2:0], 1'b1};
        store_valid <= counter[SUM_DELAY-1];

        // if (store_valid) begin
        //   write_addr <= write_addr + 1;
        // end
      end

    end
  end

endmodule
