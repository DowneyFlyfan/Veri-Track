// 还没写完
`timescale 1ns / 100ps
// WARN:目前只考虑ROI_SIZE是NUM_PER_CYCLE的整数倍

module cumsum #(
    parameter ROI_SIZE = 470,  // 因为打了mask
    parameter WIDTH = 28,
    parameter NUM_PER_CYCLE = 10
) (
    input clk,
    input rst_n,
    input clk_en,
    input logic ready,
    input logic signed [WIDTH-1:0] din[NUM_PER_CYCLE- 1:0],
    output logic signed [WIDTH-1:0] dout[NUM_PER_CYCLE- 1:0],
    output logic valid,
);

  // Params
  localparam EDGE_SIZE = 4;
  localparam PAD_SIZE = (KERNEL_SIZE - 1) / 2;
  localparam BUF_WIDTH = ROI_SIZE + EDGE_SIZE * 2;  // 470 + 8 = 478

  localparam HW_BITS = $clog2(ROI_SIZE + 4);  // log2(474)
  localparam BUF_WIDTH_BITS = $clog2(BUF_WIDTH);
  localparam FLAG_BITS = $clog2(KERNEL_SIZE);

  localparam FIRST_RIGHT_PAD_IDX = ROI_SIZE + EDGE_SIZE;

  // Temp

  // Buffers, Conv Matrix
  logic signed [WIDTH - 1:0] buffer[KERNEL_SIZE-1:0][BUF_WIDTH-1:0];

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

  // AdderTree
  logic signed [INPUT_NUM*MULTIPLIED_WIDTH-1:0] adder_tree_input[NUM_PER_CYCLE-1:0][KERNEL_NUM-1:0];

  // Latency
  localparam ADDER_LATENCY = $clog2(INPUT_NUM) + 2;
  logic [ADDER_LATENCY-1:0] add_out_en;

  genvar n, c, h, w, d;
  generate
    for (n = 0; n < NUM_PER_CYCLE; n = n + 1) begin
      for (c = 0; c < KERNEL_NUM; c = c + 1) begin
        for (h = 0; h < KERNEL_SIZE; h = h + 1) begin
          for (w = 0; w < KERNEL_SIZE; w = w + 1) begin
            assign adder_tree_input[n][c][(h*KERNEL_SIZE + w + 1) * MULTIPLIED_WIDTH -1-:MULTIPLIED_WIDTH] = conv_mat[n][c][h][w];
          end
        end
        adder_tree #(
            .INPUT_NUM(INPUT_NUM),
            .WIDTH(MULTIPLIED_WIDTH),
            .MODE("hessian")  // WARN: 要改一下
        ) adder_tree_inst (
            .clk  (clk),
            .rst_n(rst_n),
            .din  (adder_tree_input[n][c]),
            .dout (hessian_out[c][n])
        );
      end
    end
  endgenerate

  // Main Logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      conv_h <= 0;
      conv_w <= 0;
      read_w <= EDGE_SIZE;
      read_h <= EDGE_SIZE;
      buf_h <= EDGE_SIZE;
      conv_flag <= 0;

      ready <= 1'b1;
      add_en <= 1'b0;

      add_out_en <= 0;
      clr;
    end else if (clk_en) begin
      add_out_en <= {add_out_en[ADDER_LATENCY-2:0], add_en};
      valid <= add_out_en[ADDER_LATENCY-1];

      for (int n = 0; n < NUM_PER_CYCLE; n = n + 1) begin : post_hessian_conv
        for (int d = 0; d < TRACE_DELAY - 1; d = d + 1) begin : trace_update
          trace[d+1][n] <= trace[d][n];
        end

        // Cycle 1
        trace[0][n] <= hessian_out[0][n] + hessian_out[2][n];
        dxx_times_dyy[n] <= hessian_out[0][n] * hessian_out[2][n];
        dxy_square[n] <= hessian_out[1][n] ** 2;

        // Cycle 2
        det[n] <= dxx_times_dyy[n] - dxy_square[n];

        // Cycle 3
        det_square[n] <= det[n] ** 2;

        // Cycle 4
        quad_det_square[n] <= det_square[n] * 4;
        trace_square[n] <= trace[2][n] ** 2;

        // Cycle 5
        eigen[n] <= (trace_square[n] - quad_det_square[n] < 0) ? '0 : (trace_square[n] - quad_det_square[n]);

        // Cycle 6
        lambda1[n] <= trace[TRACE_DELAY-1] - eigen[n];
        lambda2[n] <= trace[TRACE_DELAY-1] + eigen[n];

        // Cycle 7
        lambda_sum[n] <= (lambda1[n] > 0 ? lambda1[n] : -lambda1[n]) + (lambda2[n] > 0 ? lambda2[n] : -lambda2[n]);
        lambda_diff[n] <= lambda2[n] - lambda1[n];

        // Cycle 8
        dout[n] <= lambda_sum[n] * lambda_diff[n];

      end

      case (c_state)
        IDLE: begin  // NOTE: 少了一个add_out_en
          conv_h <= 0;
          conv_w <= 0;
          read_w <= EDGE_SIZE;
          read_h <= EDGE_SIZE;
          buf_h <= EDGE_SIZE;
          conv_flag <= 0;

          ready <= valid ? 1'b0 : 1'b1;
          add_en <= 1'b0;

          clr;
        end

        READ: begin
          // Read Data
          for (int n = 0; n < NUM_PER_CYCLE; n = n + 1) begin
            buffer[buf_h][read_w+n] <= signed'(din[n]);
          end

          // Update Buffer Index & Conv Flag
          if (read_w + NUM_PER_CYCLE == FIRST_RIGHT_PAD_IDX) begin
            read_w <= EDGE_SIZE;
            read_h <= read_h + 1;
            if (buf_h == KERNEL_SIZE - 1) begin
              buf_h <= 0;
            end else begin
              buf_h <= buf_h + 1;
            end

          end else begin  // Normal Condition
            read_w <= read_w + NUM_PER_CYCLE;
          end

          if (read_w + NUM_PER_CYCLE == FIRST_RIGHT_PAD_IDX && read_h == KERNEL_SIZE - 2) begin: to_conv
            add_en <= 1'b1;
          end
        end

        CONV: begin
          if (conv_w + NUM_PER_CYCLE == ROI_SIZE) begin : conv_index_update
            if (conv_flag == KERNEL_SIZE - 1) begin
              conv_flag <= 0;
            end else begin
              conv_flag <= conv_flag + 1;
            end
            conv_w <= 0;
            conv_h <= conv_h + 1;
          end else begin
            conv_w <= conv_w + NUM_PER_CYCLE;
          end

          if (ready) begin : read_data_and_buffer_index_update
            if (read_w + NUM_PER_CYCLE == FIRST_RIGHT_PAD_IDX) begin : buffer_index_update
              read_w <= EDGE_SIZE;
              read_h <= read_h + 1;
              if (buf_h == KERNEL_SIZE - 1) begin
                buf_h <= 0;
              end else begin
                buf_h <= buf_h + 1;
              end
            end else begin  // Normal Condition
              read_w <= read_w + NUM_PER_CYCLE;
            end

            if (read_h >= FIRST_RIGHT_PAD_IDX) begin : read_data
              for (int n = 0; n < NUM_PER_CYCLE; n = n + 1) begin
                buffer[buf_h][read_w+n] <= '0;
              end
            end else begin
              for (int n = 0; n < NUM_PER_CYCLE; n = n + 1) begin
                buffer[buf_h][read_w+n] <= signed'(din[n]);
              end
            end
          end

          for (int n = 0; n < NUM_PER_CYCLE; n = n + 1) begin : conv
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

          if (conv_h == ROI_SIZE - 1 && conv_w == ROI_SIZE - 2 * NUM_PER_CYCLE) begin : to_IDLE
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
    for (int n = 0; n < NUM_PER_CYCLE; n++) begin
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
