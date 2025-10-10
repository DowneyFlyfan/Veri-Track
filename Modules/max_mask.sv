// 还没写完
`timescale 1ns / 100ps

// FIX: 有较大的 计算误差 和 读数位移
module max_mask #(
    parameter ROI_SIZE = 480,
    parameter IN_WIDTH = 12,
    parameter OUT_WIDTH = 12,
    parameter MASK_SIZE = 6,
    parameter NUM_PER_CYCLE = 2,

    parameter ROI_AREA = ROI_SIZE * ROI_SIZE
) (
    input clk,
    input rst_n,
    input clk_en,
    input logic signed [OUT_WIDTH-1:0] max,
    input logic [IN_WIDTH - 1:0] din[NUM_PER_CYCLE-1:0],
    input logic din_valid,
    output logic dout_valid,
    output logic signed [OUT_WIDTH-1:0] dout[NUM_PER_CYCLE- 1:0]
);

  // Params
  localparam HW_BITS = $clog2(ROI_SIZE);
  localparam ADDR_BITS = $clog2(ROI_AREA / NUM_PER_CYCLE);
  localparam DELAY = IN_WIDTH + OUT_WIDTH + 1;

  logic [ADDR_BITS-1:0] write_addr, read_addr;
  logic [OUT_WIDTH - 1:0] sobel_dout[NUM_PER_CYCLE-1:0];

  logic [HW_BITS-1:0] read_h, read_w;

  logic ram_full, read_en;

  sobel_out sobel_bank (
      .clka (clk),
      .ena  (din_valid),
      .wea  (din_valid),
      .addra(write_addr),
      .dina ({din[0], din[1]}),

      .clkb (clk),
      .enb  (read_en),
      .addrb(read_addr),
      .doutb({sobel_dout[0], sobel_dout[1]})
  );

  genvar n;
  generate
    for (n = 0; n < NUM_PER_CYCLE; n++) begin
      fixed_point_divider #(
          .IN_WIDTH (IN_WIDTH),
          .OUT_WIDTH(OUT_WIDTH)
      ) divider (
          .clk(clk),
          .rst_n(rst_n),
          .rs1(sobel_dout[n]),
          .rs2(max),
          .rd(dout[n]),
          .din_valid(read_en),
          .dout_valid(dout_valid)
      );
    end
  endgenerate

  // Main Logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin : reset
      write_addr <= 0;
      read_addr <= MASK_SIZE * ROI_SIZE + MASK_SIZE;
      read_w <= MASK_SIZE;
      read_h <= MASK_SIZE;
      ram_full <= 1'b0;
      read_en <= 1'b0;

    end else if (clk_en) begin
      begin : addr_update
        if (din_valid) begin : write_update
          write_addr <= write_addr + 1;
        end else begin
          write_addr <= 0;
        end

        if (write_addr == 0) begin : reset_read_params
          read_en <= 1'b1;
          read_h <= MASK_SIZE;
          read_w <= MASK_SIZE;
          read_addr <= MASK_SIZE * ROI_SIZE + MASK_SIZE;
        end

        if (read_h == ROI_SIZE - MASK_SIZE - 1 && read_w + NUM_PER_CYCLE == ROI_SIZE - MASK_SIZE) begin: read_disable
          read_en <= 1'b0;
        end

        if (write_addr == ROI_AREA / NUM_PER_CYCLE - 1) begin : ram_full_update
          ram_full <= 1'b1;
        end

        if (ram_full && read_en) begin : read_update
          if (read_w + NUM_PER_CYCLE == ROI_SIZE - MASK_SIZE) begin
            read_w <= MASK_SIZE;
            read_h <= read_h + 1;
            read_addr <= read_addr + 1 + MASK_SIZE / 2;
          end else begin
            read_w <= read_w + NUM_PER_CYCLE;
            read_addr <= read_addr + 1;
          end
        end

      end
    end
  end

endmodule
