`timescale 1ns / 1ps
// WARN:目前只考虑ROI_SIZE是NUM_PER_CYCLE的整数倍 

module convolution_core #(
    parameter ROI_SIZE = 480,
    parameter PORT_BITS = 128,
    parameter IN_WIDTH = 8,
    parameter KERNEL_SIZE = 3,
    parameter KERNEL_DATA_WIDTH = 4,
    parameter KERNEL_NUM = 2,
    parameter CHANNEL_ADD_VLD = 1,
    parameter MULTIPLIED_WIDTH = IN_WIDTH + KERNEL_DATA_WIDTH,
    parameter OUT_WIDTH = (CHANNEL_ADD_VLD == 1) ? (MULTIPLIED_WIDTH + $clog2(
        KERNEL_AREA * KERNEL_NUM
    )) : (MULTIPLIED_WIDTH + $clog2(
        KERNEL_AREA
    )),
    parameter NUM_PER_CYCLE = PORT_BITS / IN_WIDTH
) (
    input clk,
    input rst_n,
    input clk_en,
    input conv_en,
    input logic [PORT_BITS - 1:0] data_in,
    input logic signed [KERNEL_DATA_WIDTH - 1:0] kernel[KERNEL_NUM-1:0][KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
    output logic signed [OUT_WIDTH-1:0] data_out[KERNEL_NUM-1:0][NUM_PER_CYCLE - 1:0],
    output logic conv_out_vld,
    output logic read_en
);

  // Params
  localparam KERNEL_AREA = KERNEL_SIZE * KERNEL_SIZE;
  localparam KERNEL_SIZE_MINUS_1 = KERNEL_SIZE - 1;

  localparam PAD_SIZE = (KERNEL_SIZE - 1) / 2;
  localparam BUF_WIDTH = ROI_SIZE + 2 * PAD_SIZE;

  localparam HW_BITS = $clog2(ROI_SIZE);
  localparam BUF_WIDTH_BITS = $clog2(BUF_WIDTH);
  localparam KERNEL_BITS = $clog2(KERNEL_SIZE);

  localparam FIRST_RIGHT_PAD_IDX = ROI_SIZE + PAD_SIZE;
  localparam IMG_BOTTOM_KERNEL_IDX = BUF_WIDTH - PAD_SIZE - KERNEL_SIZE;
  localparam CONV_MAT_RIGHT_IDX = NUM_PER_CYCLE - PAD_SIZE;

  // Buffers, Conv Matrix, Zeros
  logic signed [IN_WIDTH - 1:0] buffer[KERNEL_SIZE-1:0][BUF_WIDTH-1:0];
  logic signed [MULTIPLIED_WIDTH-1:0] conv_mat[NUM_PER_CYCLE-1:0][KERNEL_NUM-1:0][KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];
  logic [PORT_BITS-1:0] zeros = 0;

  // Indices
  logic [BUF_WIDTH_BITS - 1:0] buf_w, buf_h;  // WARN: buf_h 应该把位扩大一些
  logic [HW_BITS-1:0] conv_w, conv_h;  // Index for Conv Kernel on Top Left

  // State Machine
  localparam IDLE = 4'b1;
  localparam READ = 4'b10;
  localparam MIDDLE_CONV = 4'b100;
  localparam BOTTOM_CONV = 4'b1000;
  reg [3:0] n_state;
  reg [3:0] c_state;

  // Enable Signals
  logic add_en;
  logic middle_en;
  logic bottom_en;

  // Debug
  localparam TOTAL_BITS = $clog2(ROI_SIZE * (ROI_SIZE + BUF_WIDTH));
  logic [TOTAL_BITS-1:0] count;

  // Latency
  localparam ADDER_LATENCY = (CHANNEL_ADD_VLD == 1) ? ($clog2(
      KERNEL_AREA * KERNEL_NUM
  ) + 2) : ($clog2(
      KERNEL_AREA
  ) + 2);
  logic [ADDER_LATENCY-1:0] add_out_en;

  // TODO: MAYBE Optimize Adder Tree for this task
  genvar n, kn, ka;  // NUM_PER_CYCLE, KERNEL_NUM, KERNEL_AREA
  generate
    if (CHANNEL_ADD_VLD) begin
      localparam INPUT_NUM = KERNEL_AREA * KERNEL_NUM;
      logic signed [INPUT_NUM*MULTIPLIED_WIDTH-1:0] adder_tree_input[NUM_PER_CYCLE-1:0];
      logic signed [OUT_WIDTH-1:0] adder_tree_output[NUM_PER_CYCLE-1:0];

      for (n = 0; n < NUM_PER_CYCLE; n = n + 1) begin : gen_single_channel_adder
        for (kn = 0; kn < KERNEL_NUM; kn = kn + 1) begin
          for (ka = 0; ka < KERNEL_AREA; ka = ka + 1) begin
            assign adder_tree_input[n][(kn*KERNEL_AREA + (ka+1))*MULTIPLIED_WIDTH-1-:MULTIPLIED_WIDTH] = conv_mat[n][kn][ka/KERNEL_SIZE][ka%KERNEL_SIZE];
          end
        end

        adder_tree #(
            .INPUT_NUM(INPUT_NUM),
            .IN_WIDTH (MULTIPLIED_WIDTH)
        ) adder_tree_inst (
            .clk  (clk),
            .rst_n(rst_n),
            .din  (adder_tree_input[n]),
            .dout (adder_tree_output[n])
        );
        assign data_out[0][n] = adder_tree_output[n];
      end
    end else begin
      // WARN:先不管
      localparam INPUT_NUM = KERNEL_AREA;

      logic signed [INPUT_NUM*MULTIPLIED_WIDTH-1:0] adder_tree_input[NUM_PER_CYCLE*KERNEL_NUM-1:0];
      logic signed [OUT_WIDTH-1:0] adder_tree_output[KERNEL_NUM-1:0][NUM_PER_CYCLE-1:0];

      for (n = 0; n < NUM_PER_CYCLE; n = n + 1) begin : gen_multi_channel_adders
        for (kn = 0; kn < KERNEL_NUM; kn = kn + 1) begin
          for (ka = 0; ka < KERNEL_AREA; ka = ka + 1) begin
            assign adder_tree_input[(n+1)*(kn+1)-1][(ka+1)*MULTIPLIED_WIDTH-1-:MULTIPLIED_WIDTH] = conv_mat[n][kn][ka/KERNEL_SIZE][ka%KERNEL_SIZE];
          end
          adder_tree #(
              .INPUT_NUM(INPUT_NUM),
              .IN_WIDTH (MULTIPLIED_WIDTH)
          ) adder_tree_inst (
              .clk  (clk),
              .rst_n(rst_n),
              .din  (adder_tree_input[(n+1)*(kn+1)-1]),
              .dout (adder_tree_output[kn][n])
          );
          assign data_out[kn][n] = adder_tree_output[kn][n];
        end
      end
    end
  endgenerate

  // Main Logic
  always_ff @(posedge clk or negedge rst_n) begin
    count <= count + 1;
    if (~rst_n) begin
      conv_h <= 0;
      conv_w <= 0;
      buf_w <= PAD_SIZE;
      buf_h <= PAD_SIZE;
      count <= 0;

      add_en <= 1'b0;
      bottom_en <= 1'b0;
      middle_en <= 1'b0;
      read_en <= 1'b0;
      add_out_en <= '0;

      // Pad Buffer Area With 0
      for (int h = 0; h < KERNEL_SIZE; h = h + 1) begin
        for (int w = 0; w < BUF_WIDTH; w = w + 1) begin
          buffer[h][w] <= '0;
        end
      end

      $display("Reset, count %d", count);

    end else if (clk_en) begin
      add_out_en <= {add_out_en[ADDER_LATENCY-2:0], add_en};
      case (c_state)
        IDLE: begin  // NOTE: 少了一个add_out_en
          $display("At IDLE stage, add_out_en:%b count %d", add_out_en, count);
          conv_h <= 0;
          conv_w <= 0;
          buf_w <= PAD_SIZE;
          buf_h <= PAD_SIZE;

          add_en <= 1'b0;
          bottom_en <= 1'b0;
          middle_en <= 1'b0;
          read_en <= 1'b1;

          // Pad Buffer Area With 0
          for (int h = 0; h < KERNEL_SIZE; h = h + 1) begin
            for (int w = 0; w < BUF_WIDTH; w = w + 1) begin
              buffer[h][w] <= '0;
            end
          end
        end

        READ: begin
          $display("At READ stage, add_out_en:%b, count %d, add_en:%b, n_state:%b, conv_out_vld:%b",
                   add_out_en, count, add_en, n_state, conv_out_vld);
          // Read Data
          for (int i = 0; i < NUM_PER_CYCLE; i = i + 1) begin
            buffer[buf_h][buf_w+i] <= signed'(data_in[(i+1)*IN_WIDTH-1-:IN_WIDTH]);
          end

          // Update Buffer Index
          if (buf_w + NUM_PER_CYCLE == FIRST_RIGHT_PAD_IDX) begin  // Last Column of Buffer
            buf_w <= PAD_SIZE;
            buf_h <= buf_h + 1;
          end else begin  // Normal Condition
            buf_w <= buf_w + NUM_PER_CYCLE;
          end

          if (buf_h == KERNEL_SIZE - 1 && buf_w == PAD_SIZE) begin
            middle_en <= 1'b1;
          end

          if (buf_h == KERNEL_SIZE - 1 && buf_w == PAD_SIZE + NUM_PER_CYCLE) begin
            add_en <= 1'b1;
          end

        end

        MIDDLE_CONV: begin
          // Update Buffer Index
          $display(
              "At MIDDLE_CONV stage, add_out_en:%b, count %d, add_en:%b, n_state:%b, conv_out_vld:%b, buf_h:%d, buf_w:%d, conv_w:%d, conv_h:%d, bottom_en:%d",
              add_out_en, count, add_en, n_state, conv_out_vld, buf_h, buf_w, conv_w, conv_h,
              bottom_en);

          // Update Buffer Index
          if (buf_w + NUM_PER_CYCLE == FIRST_RIGHT_PAD_IDX) begin  // Last Column of Buffer
            buf_w <= PAD_SIZE;
            buf_h <= buf_h + 1;
          end else begin  // Normal Condition
            buf_w <= buf_w + NUM_PER_CYCLE;
          end

          // To bottom
          if (buf_w + NUM_PER_CYCLE == FIRST_RIGHT_PAD_IDX - NUM_PER_CYCLE && buf_h == FIRST_RIGHT_PAD_IDX - 1) begin
            bottom_en <= 1'b1;
            middle_en <= 1'b0;
          end

          // Update Conv Index
          if (conv_w + NUM_PER_CYCLE == ROI_SIZE) begin
            conv_w <= 0;
            conv_h <= conv_h + 1;
          end else begin
            conv_w <= conv_w + NUM_PER_CYCLE;
          end

          // Read Data
          if (buf_h > KERNEL_SIZE - 1) begin
            for (int i = 0; i < NUM_PER_CYCLE; i = i + 1) begin
              buffer[KERNEL_SIZE-1][buf_w+i] <= signed'(data_in[(i+1)*IN_WIDTH-1-:IN_WIDTH]);
            end
            for (int h = 0; h < KERNEL_SIZE - 1; h = h + 1) begin
              for (int j = 0; j < NUM_PER_CYCLE; j = j + 1) begin
                buffer[h][buf_w+j] <= buffer[h+1][buf_w+j];
              end
            end
          end else begin
            for (int i = 0; i < NUM_PER_CYCLE; i = i + 1) begin
              buffer[buf_h][buf_w+i] <= signed'(data_in[(i+1)*IN_WIDTH-1-:IN_WIDTH]);
            end
          end

          // Conv
          for (int n = conv_w; n < conv_w + NUM_PER_CYCLE; n = n + 1) begin
            for (int c = 0; c < KERNEL_NUM; c = c + 1) begin
              for (int h = 0; h < KERNEL_SIZE; h = h + 1) begin
                for (int w = 0; w < KERNEL_SIZE; w = w + 1) begin
                  conv_mat[n-conv_w][c][h][w] <= buffer[h][n+w] * kernel[c][h][w];
                end
              end
            end
          end

        end

        BOTTOM_CONV: begin
          // Update Buffer Index
          $display(
              "At BOTTOM_CONV stage, add_out_en:%b, count %d, add_en:%b, n_state:%b, conv_out_vld:%b, buf_h:%d, buf_w:%d, conv_w:%d, conv_h:%d, bottom_en:%d",
              add_out_en, count, add_en, n_state, conv_out_vld, buf_h, buf_w, conv_w, conv_h,
              bottom_en);

          // Update Buffer Index
          if (buf_w + NUM_PER_CYCLE == FIRST_RIGHT_PAD_IDX) begin  // Last Column of Buffer
            buf_w <= PAD_SIZE;
            buf_h <= buf_h + 1;
          end else begin  // Normal Condition
            buf_w <= buf_w + NUM_PER_CYCLE;
          end

          // Update Conv Index
          if (conv_w + NUM_PER_CYCLE == ROI_SIZE) begin
            conv_w <= 0;
            conv_h <= conv_h + 1;
          end else begin
            conv_w <= conv_w + NUM_PER_CYCLE;
          end

          // To IDLE
          if (conv_w + NUM_PER_CYCLE == ROI_SIZE - NUM_PER_CYCLE && conv_h == ROI_SIZE - 1) begin
            bottom_en <= 1'b0;
          end

          if (conv_w + NUM_PER_CYCLE == ROI_SIZE && conv_h == ROI_SIZE - 1) begin
            add_en <= 1'b0;
          end

          // Read Zeros
          for (int i = 0; i < NUM_PER_CYCLE; i = i + 1) begin
            buffer[KERNEL_SIZE-1][buf_w+i] <= zeros[(i+1)*IN_WIDTH-1-:IN_WIDTH];
          end
          for (int h = 0; h < KERNEL_SIZE - 1; h = h + 1) begin
            for (int j = 0; j < NUM_PER_CYCLE; j = j + 1) begin
              buffer[h][buf_w+j] <= buffer[h+1][buf_w+j];
            end
          end

          // Conv
          for (int n = conv_w; n < conv_w + NUM_PER_CYCLE; n = n + 1) begin
            for (int c = 0; c < KERNEL_NUM; c = c + 1) begin
              for (int h = 0; h < KERNEL_SIZE; h = h + 1) begin
                for (int w = 0; w < KERNEL_SIZE; w = w + 1) begin
                  conv_mat[n-conv_w][c][h][w] <= buffer[h][n+w] * kernel[c][h][w];
                end
              end
            end
          end

        end
      endcase
    end
  end

  // State Machine Setting
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
        n_state = conv_en ? (conv_out_vld ? IDLE : READ) : IDLE;
      end
      READ: begin
        n_state = conv_en ? (middle_en ? MIDDLE_CONV : READ) : IDLE;
      end
      MIDDLE_CONV: begin
        n_state = conv_en ? (bottom_en ? BOTTOM_CONV : MIDDLE_CONV) : IDLE;
      end
      BOTTOM_CONV: begin
        n_state = conv_en ? (bottom_en ? BOTTOM_CONV : IDLE) : IDLE;
      end
      default: n_state = IDLE;
    endcase

    assign conv_out_vld = add_out_en[ADDER_LATENCY-1];
  end

endmodule
