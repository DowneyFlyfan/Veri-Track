`timescale 1ns / 100ps
// WARN:目前只考虑ROI_SIZE是IN_NUM_PER_CYCLE的整数倍

module sobel_conv #(
    parameter ROI_SIZE = 480,
    parameter PORT_BITS = 128,
    parameter IN_WIDTH = 8,
    parameter KERNEL_SIZE = 3,
    parameter KERNEL_DATA_WIDTH = 3,
    parameter KERNEL_NUM = 2,
    parameter PIXELS_OUT_PER_CYCLE = 2,

    parameter KERNEL_AREA = KERNEL_SIZE * KERNEL_SIZE,
    parameter INPUT_NUM = KERNEL_AREA,
    parameter MULTIPLIED_WIDTH = IN_WIDTH + KERNEL_DATA_WIDTH + 1,  // [-255*2, 255*2]
    parameter ADDER_OUT_WIDTH = IN_WIDTH + 4,  // [-255*4, 255*4]
    parameter OUT_WIDTH = IN_WIDTH + 4,  // [0, 255*8]

    parameter IN_NUM_PER_CYCLE = PORT_BITS / IN_WIDTH,
    parameter READ_CONV_RATIO  = IN_NUM_PER_CYCLE / PIXELS_OUT_PER_CYCLE
) (
    input clk,
    input rst_n,
    input clk_en,
    input logic [PORT_BITS - 1:0] data_in,
    input logic signed [KERNEL_DATA_WIDTH - 1:0] kernel[KERNEL_NUM-1:0][KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
    output logic signed [OUT_WIDTH-1:0] data_out[PIXELS_OUT_PER_CYCLE- 1:0],
    output logic signed [OUT_WIDTH-1:0] max,  // FIX:错误的
    output logic valid,
    output logic ready
);

  // Params
  localparam PAD_SIZE = (KERNEL_SIZE - 1) / 2;
  localparam BUF_WIDTH = ROI_SIZE + 2 * PAD_SIZE;

  localparam HW_BITS = $clog2(ROI_SIZE);
  localparam BUF_WIDTH_BITS = $clog2(BUF_WIDTH);
  localparam FLAG_BITS = $clog2(KERNEL_SIZE);

  localparam FIRST_RIGHT_PAD_IDX = ROI_SIZE + PAD_SIZE;

  // Buffers, Conv Matrix, Zeros
  // WARN: 位宽增加
  logic signed [IN_WIDTH:0] buffer[KERNEL_SIZE-1:0][BUF_WIDTH-1:0];
  logic signed [OUT_WIDTH-1:0] dx[PIXELS_OUT_PER_CYCLE- 1:0];
  logic signed [OUT_WIDTH-1:0] dy[PIXELS_OUT_PER_CYCLE- 1:0];
  logic signed [MULTIPLIED_WIDTH-1:0] conv_mat[PIXELS_OUT_PER_CYCLE-1:0][KERNEL_NUM-1:0][KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];

  // Indices
  logic [BUF_WIDTH_BITS - 1:0] read_w, read_h;
  logic [HW_BITS-1:0] conv_w, conv_h;  // Index for Conv Kernel on Top Left
  logic [FLAG_BITS-1:0] conv_flag, buf_h;

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
  logic signed [INPUT_NUM*MULTIPLIED_WIDTH-1:0] adder_tree_input_x[PIXELS_OUT_PER_CYCLE-1:0];
  logic signed [INPUT_NUM*MULTIPLIED_WIDTH-1:0] adder_tree_input_y[PIXELS_OUT_PER_CYCLE-1:0];

  // Latency
  localparam ADDER_LATENCY = $clog2(INPUT_NUM * KERNEL_NUM) + 2;
  logic [ADDER_LATENCY-1:0] add_out_en;

  genvar n, c, h, w;
  generate
    for (n = 0; n < PIXELS_OUT_PER_CYCLE; n = n + 1) begin
      for (h = 0; h < KERNEL_SIZE; h = h + 1) begin
        for (w = 0; w < KERNEL_SIZE; w = w + 1) begin
          assign adder_tree_input_x[n][(h*KERNEL_SIZE + w + 1) * MULTIPLIED_WIDTH -1-:MULTIPLIED_WIDTH] = conv_mat[n][0][h][w];
          assign adder_tree_input_y[n][(h*KERNEL_SIZE + w + 1) * MULTIPLIED_WIDTH -1-:MULTIPLIED_WIDTH] = conv_mat[n][1][h][w];
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
    assign valid = add_out_en[ADDER_LATENCY-1];
  endgenerate

  // Main Logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      conv_h <= 0;
      conv_w <= 0;
      read_w <= PAD_SIZE;
      read_h <= PAD_SIZE;
      buf_h <= PAD_SIZE;
      conv_flag <= 0;

      ready <= 1'b1;
      add_en <= 1'b0;
      counter <= 0;
      max <= 0;

      add_out_en <= 0;
      clr;
    end else if (clk_en) begin
      // Valid
      add_out_en <= {add_out_en[ADDER_LATENCY-2:0], add_en};

      if (valid) begin : max_compute
        for (int n = 0; n < PIXELS_OUT_PER_CYCLE; n++) begin
          if (data_out[n] > max) begin
            max <= data_out[n];
          end
        end
      end else begin
        max <= 0;
      end

      for (int n = 0; n < PIXELS_OUT_PER_CYCLE; n++) begin : dout_compute
        data_out[n] <= dx[n] + dy[n];
      end

      case (c_state)
        IDLE: begin  // NOTE: 少了一个add_out_en
          conv_h <= 0;
          conv_w <= 0;
          read_w <= PAD_SIZE;
          read_h <= PAD_SIZE;
          buf_h <= PAD_SIZE;
          conv_flag <= 0;

          ready <= valid ? 1'b0 : 1'b1;
          add_en <= 1'b0;
          counter <= '0;

          clr;
        end

        READ: begin
          // Read Data
          for (int n = 0; n < IN_NUM_PER_CYCLE; n = n + 1) begin
            buffer[buf_h][read_w+n] <= {1'b0, data_in[(n+1)*IN_WIDTH-1-:IN_WIDTH]};
          end

          // Update Buffer Index
          if (read_w + IN_NUM_PER_CYCLE == FIRST_RIGHT_PAD_IDX) begin
            read_w <= PAD_SIZE;
            read_h <= read_h + 1;
            if (buf_h == KERNEL_SIZE - 1) begin
              buf_h <= 0;
            end else begin
              buf_h <= buf_h + 1;
            end

          end else begin  // Normal Condition
            read_w <= read_w + IN_NUM_PER_CYCLE;
          end

          if (read_w + IN_NUM_PER_CYCLE == FIRST_RIGHT_PAD_IDX && read_h == KERNEL_SIZE - 2) begin: to_conv
            add_en <= 1'b1;
          end

        end

        CONV: begin
          if (counter == READ_CONV_RATIO - 1) begin : read_or_not
            counter <= '0;
            ready   <= 1'b1;
          end else begin
            counter <= counter + 1;
            ready   <= 1'b0;
          end

          if (conv_w + PIXELS_OUT_PER_CYCLE == ROI_SIZE) begin : conv_index_update
            if (conv_flag == KERNEL_SIZE - 1) begin
              conv_flag <= 0;
            end else begin
              conv_flag <= conv_flag + 1;
            end
            conv_w <= 0;
            conv_h <= conv_h + 1;
          end else begin
            conv_w <= conv_w + PIXELS_OUT_PER_CYCLE;
          end

          if (ready) begin : read_data_and_buffer_index_update
            if (read_w + IN_NUM_PER_CYCLE == FIRST_RIGHT_PAD_IDX) begin : buffer_index_update
              read_w <= PAD_SIZE;
              read_h <= read_h + 1;
              if (buf_h == KERNEL_SIZE - 1) begin
                buf_h <= 0;
              end else begin
                buf_h <= buf_h + 1;
              end
            end else begin  // Normal Condition
              read_w <= read_w + IN_NUM_PER_CYCLE;
            end

            if (read_h >= FIRST_RIGHT_PAD_IDX) begin : read_data
              for (int n = 0; n < IN_NUM_PER_CYCLE; n = n + 1) begin
                buffer[buf_h][read_w+n] <= '0;
              end
            end else begin
              for (int n = 0; n < IN_NUM_PER_CYCLE; n = n + 1) begin
                buffer[buf_h][read_w+n] <= {1'b0, data_in[(n+1)*IN_WIDTH-1-:IN_WIDTH]};
              end
            end
          end

          for (int n = 0; n < PIXELS_OUT_PER_CYCLE; n = n + 1) begin : conv
            for (int c = 0; c < KERNEL_NUM; c = c + 1) begin
              for (int h = 0; h < KERNEL_SIZE; h = h + 1) begin
                for (int w = 0; w < KERNEL_SIZE; w = w + 1) begin
                  if (h >= conv_flag) begin
                    conv_mat[n][c][h][w] <= buffer[h][n+w+conv_w] * kernel[c][h-conv_flag][w];
                  end else begin
                    conv_mat[n][c][h][w] <= buffer[h][n+w+conv_w] * kernel[c][h-conv_flag + KERNEL_SIZE][w];
                  end
                end
              end
            end
          end

          if (conv_h == ROI_SIZE - 1 && conv_w == ROI_SIZE - 2 * PIXELS_OUT_PER_CYCLE) begin : to_IDLE
            add_en <= 1'b0;
          end
        end

      endcase
    end
  end

  task clr;
    integer h, w;
    for (h = 0; h < KERNEL_SIZE; h = h + 1) begin
      for (w = 0; w < BUF_WIDTH; w = w + 1) begin
        buffer[h][w] <= 0;
      end
    end
    for (int n = 0; n < PIXELS_OUT_PER_CYCLE; n++) begin
      for (int c = 0; c < KERNEL_NUM; c++) begin
        for (int h = 0; h < KERNEL_SIZE; h++) begin
          for (int w = 0; w < KERNEL_SIZE; w++) begin
            conv_mat[n][c][h][w] <= 0;
          end
        end
      end
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
