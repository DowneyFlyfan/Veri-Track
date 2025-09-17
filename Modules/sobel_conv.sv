`timescale 1ns / 100ps
// WARN:目前只考虑ROI_SIZE是IN_NUM_PER_CYCLE的整数倍

module sobel_conv #(
    parameter ROI_SIZE = 480,
    parameter PORT_BITS = 128,
    parameter IN_WIDTH = 8,
    parameter KERNEL_SIZE = 3,
    parameter KERNEL_DATA_WIDTH = 3,
    parameter KERNEL_NUM = 2,
    parameter OUT_NUM_PER_CYCLE = 2,

    parameter KERNEL_AREA = KERNEL_SIZE * KERNEL_SIZE,
    parameter INPUT_NUM = 6,
    parameter MULTIPLIED_WIDTH = IN_WIDTH + KERNEL_DATA_WIDTH + 1,  // [-255*2, 255*2]
    parameter ADDER_OUT_WIDTH = MULTIPLIED_WIDTH + $clog2(6),  // [-255*4, 255*4]
    parameter OUT_WIDTH = IN_WIDTH + 4,  // [0, 255*8]

    parameter IN_NUM_PER_CYCLE = PORT_BITS / IN_WIDTH,
    parameter READ_CONV_RATIO  = IN_NUM_PER_CYCLE / OUT_NUM_PER_CYCLE
) (
    input clk,
    input rst_n,
    input clk_en,
    input logic [PORT_BITS - 1:0] data_in,
    input logic signed [KERNEL_DATA_WIDTH - 1:0] kernel[KERNEL_NUM-1:0][KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
    output logic signed [OUT_WIDTH-1:0] data_out[OUT_NUM_PER_CYCLE- 1:0],
    output logic signed [OUT_WIDTH-1:0] max,
    output logic valid,
    output logic ready
);

  // Params
  localparam PAD_SIZE = (KERNEL_SIZE - 1) / 2;
  localparam BUF_WIDTH = ROI_SIZE + 2 * PAD_SIZE;
  localparam WIDTH_BITS = ROI_SIZE / IN_NUM_PER_CYCLE;

  localparam HW_BITS = $clog2(ROI_SIZE);
  localparam BUF_WIDTH_BITS = $clog2(BUF_WIDTH);
  localparam FLAG_BITS = $clog2(KERNEL_SIZE);

  localparam FIRST_RIGHT_PAD_IDX = ROI_SIZE + PAD_SIZE;

  // Buffers, Conv Matrix, Zeros
  logic [IN_WIDTH-1:0] buffer[KERNEL_SIZE-1:0][BUF_WIDTH-1:0];
  logic signed [OUT_WIDTH-1:0] dx[OUT_NUM_PER_CYCLE- 1:0];
  logic signed [OUT_WIDTH-1:0] dy[OUT_NUM_PER_CYCLE- 1:0];
  logic signed [MULTIPLIED_WIDTH-1:0] conv_mat[OUT_NUM_PER_CYCLE-1:0][KERNEL_NUM-1:0][KERNEL_SIZE-1:0][KERNEL_SIZE-2:0];

  // Indices
  logic [BUF_WIDTH_BITS - 1:0] read_h, read_w;
  logic [HW_BITS-1:0] conv_w, conv_h;  // Index for Conv Kernel on Top Left
  logic [FLAG_BITS-1:0] buf_h;
  logic signed [FLAG_BITS:0] conv_flag;

  // State Machine
  localparam IDLE = 3'b1;
  localparam READ = 3'b10;
  localparam CONV = 3'b100;
  reg [2:0] n_state;
  reg [2:0] c_state;

  // Enable Signals
  reg add_en;

  // Counter
  localparam COUNTER_BITS = $clog2(READ_CONV_RATIO);
  reg [COUNTER_BITS-1:0] counter;

  // AdderTree
  logic signed [INPUT_NUM*MULTIPLIED_WIDTH-1:0] adder_tree_input_x[OUT_NUM_PER_CYCLE-1:0];
  logic signed [INPUT_NUM*MULTIPLIED_WIDTH-1:0] adder_tree_input_y[OUT_NUM_PER_CYCLE-1:0];

  // Latency
  // NOTE: 单独仿真时多一个周期，连接到其他器件时少一个周期
  localparam ADDER_LATENCY = $clog2(INPUT_NUM * KERNEL_NUM) + 2;
  logic [ADDER_LATENCY-1:0] add_out_en;

  genvar n, c, h, w;
  generate
    for (n = 0; n < OUT_NUM_PER_CYCLE; n = n + 1) begin
      for (h = 0; h < KERNEL_SIZE; h = h + 1) begin
        for (w = 0; w < KERNEL_SIZE - 1; w = w + 1) begin
          assign adder_tree_input_x[n][(h*(KERNEL_SIZE-1) + w + 1) * MULTIPLIED_WIDTH -1-:MULTIPLIED_WIDTH] = conv_mat[n][0][h][w];
          assign adder_tree_input_y[n][(h*(KERNEL_SIZE-1) + w + 1) * MULTIPLIED_WIDTH -1-:MULTIPLIED_WIDTH] = conv_mat[n][1][h][w];
        end
      end
      adder_tree #(
          .INPUT_NUM(INPUT_NUM),
          .IN_WIDTH(MULTIPLIED_WIDTH),
          .OUT_WIDTH(ADDER_OUT_WIDTH),
          .MODE("sobel")
      ) adder_tree_x (
          .clk  (clk),
          .rst_n(rst_n),
          .din  (adder_tree_input_x[n]),
          .dout (dx[n])
      );

      adder_tree #(
          .INPUT_NUM(INPUT_NUM),
          .IN_WIDTH(MULTIPLIED_WIDTH),
          .OUT_WIDTH(ADDER_OUT_WIDTH),
          .MODE("sobel")
      ) adder_tree_y (
          .clk  (clk),
          .rst_n(rst_n),
          .din  (adder_tree_input_y[n]),
          .dout (dy[n])
      );
    end

  endgenerate

  // Main Logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      clr;
      add_out_en <= 0;
      max <= 0;
      valid <= 1'b0;

    end else if (clk_en) begin
      begin : valid_logic
        add_out_en <= {add_out_en[ADDER_LATENCY-2:0], add_en};
        valid <= add_out_en[ADDER_LATENCY-1];
      end

      if (valid) begin : max_compute
        for (int n = 0; n < OUT_NUM_PER_CYCLE; n++) begin
          if (data_out[n] > max) begin
            max <= data_out[n];
          end
        end
      end else begin
        max <= 0;
      end

      for (int n = 0; n < OUT_NUM_PER_CYCLE; n++) begin : dout_compute
        data_out[n] <= dx[n][OUT_WIDTH-1:0] + dy[n][OUT_WIDTH-1:0];  // WARN
      end

      case (c_state)
        IDLE: begin  // NOTE: 少了add_out_en, max, valid
          clr;
        end

        READ: begin
          if (read_h == KERNEL_SIZE - 1) begin : to_conv
            add_en <= 1'b1;
          end
          for (int n = 0; n < IN_NUM_PER_CYCLE; n = n + 1) begin
            buffer[buf_h][read_w+n] <= data_in[(n+1)*IN_WIDTH-1-:IN_WIDTH];
          end
          buf_idx_update;
        end

        CONV: begin
          if (counter == READ_CONV_RATIO - 1) begin : read_or_not
            counter <= 0;
            ready   <= 1'b1;
          end else begin
            counter <= counter + 1;
            ready   <= 1'b0;
          end

          if (conv_w == ROI_SIZE - OUT_NUM_PER_CYCLE) begin : conv_index_update
            if (conv_flag == KERNEL_SIZE - 1) begin
              conv_flag <= 0;
            end else begin
              conv_flag <= conv_flag + 1;
            end
            conv_w <= 0;
            conv_h <= conv_h + 1;
          end else begin
            conv_w <= conv_w + OUT_NUM_PER_CYCLE;
          end

          if (ready) begin : read_data_and_buffer_index_update
            buf_idx_update;
            for (int n = 0; n < IN_NUM_PER_CYCLE; n++) begin
              buffer[buf_h][read_w+n] <= (read_h >= FIRST_RIGHT_PAD_IDX) ? 0 :data_in[(n+1)*IN_WIDTH-1-:IN_WIDTH];
            end
          end

          for (int n = 0; n < OUT_NUM_PER_CYCLE; n = n + 1) begin : conv
            conv_mat[n][0][0][0] <= $signed(
                {1'b0, buffer[0][n+conv_w]}
            ) * kernel[0][(conv_flag==0)?0 : (KERNEL_SIZE-conv_flag)][0];
            conv_mat[n][0][0][1] <= $signed(
                {1'b0, buffer[0][n+2+conv_w]}
            ) * kernel[0][(conv_flag==0)?0 : (KERNEL_SIZE-conv_flag)][2];

            conv_mat[n][0][1][0] <= $signed(
                {1'b0, buffer[1][n+conv_w]}
            ) * kernel[0][(1-conv_flag>=0)?(1-conv_flag) : conv_flag][0];
            conv_mat[n][0][1][1] <= $signed(
                {1'b0, buffer[1][n+2+conv_w]}
            ) * kernel[0][(1-conv_flag>=0)?(1-conv_flag) : conv_flag][2];

            conv_mat[n][0][2][0] <= $signed(
                {1'b0, buffer[2][n+conv_w]}
            ) * kernel[0][2-conv_flag][0];
            conv_mat[n][0][2][1] <= $signed(
                {1'b0, buffer[2][n+2+conv_w]}
            ) * kernel[0][2-conv_flag][2];

            conv_mat[n][1][0][0] <= $signed({1'b0, buffer[conv_flag][n+conv_w]}) * kernel[1][0][0];
            conv_mat[n][1][1][0] <= $signed(
                {1'b0, buffer[conv_flag][n+1+conv_w]}
            ) * kernel[1][0][1];
            conv_mat[n][1][2][0] <= $signed(
                {1'b0, buffer[conv_flag][n+2+conv_w]}
            ) * kernel[1][0][2];

            conv_mat[n][1][0][1] <= $signed(
                {1'b0, buffer[(conv_flag==0)?2 : (conv_flag-1)][n+conv_w]}
            ) * kernel[1][2][0];
            conv_mat[n][1][1][1] <= $signed(
                {1'b0, buffer[(conv_flag==0)?2 : (conv_flag-1)][n+1+conv_w]}
            ) * kernel[1][2][1];
            conv_mat[n][1][2][1] <= $signed(
                {1'b0, buffer[(conv_flag==0)?2 : (conv_flag-1)][n+2+conv_w]}
            ) * kernel[1][2][2];
          end

          if (conv_h == ROI_SIZE - 1 && conv_w == ROI_SIZE - 2 * OUT_NUM_PER_CYCLE) begin : to_IDLE
            add_en <= 1'b0;
          end
        end

      endcase
    end
  end

  task clr;
    conv_h <= 0;
    conv_w <= 0;
    read_h <= PAD_SIZE;
    read_w <= PAD_SIZE;
    buf_h <= PAD_SIZE;
    conv_flag <= 0;

    ready <= 1'b1;
    add_en <= 1'b0;
    counter <= 0;

    for (int h = 0; h < KERNEL_SIZE; h++) begin
      for (int w = 0; w < BUF_WIDTH; w++) begin
        buffer[h][w] <= 0;
      end
    end
  endtask

  task automatic buf_idx_update;
    if (read_w == FIRST_RIGHT_PAD_IDX - IN_NUM_PER_CYCLE) begin
      read_w <= PAD_SIZE;
      read_h <= read_h + 1;
      if (buf_h == KERNEL_SIZE - 1) begin
        buf_h <= 0;
      end else begin
        buf_h <= buf_h + 1;
      end

    end else begin
      read_w <= read_w + IN_NUM_PER_CYCLE;
    end
  endtask

  // State Machine
  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      c_state <= IDLE;
    end else if (clk_en) begin
      c_state <= n_state;
    end
  end

  always_comb begin
    case (c_state)
      IDLE: begin
        n_state = valid ? IDLE : READ;
      end
      READ: begin
        n_state = add_en ? CONV : READ;
      end
      CONV: begin
        n_state = add_en ? CONV : IDLE;
      end
      default: begin
        n_state = IDLE;
      end
    endcase
  end
endmodule
