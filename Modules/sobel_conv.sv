`timescale 1ns / 100ps
// WARN:目前只考虑ROI_SIZE是NUM_PER_CYCLE的整数倍
// WARN: din, dout, n_state, read_en 等需要改一改

module sobel_conv #(
    parameter ROI_SIZE = 480,
    parameter PORT_BITS = 64,
    parameter IN_WIDTH = 8,
    parameter KERNEL_SIZE = 3,
    parameter KERNEL_DATA_WIDTH = 4,
    parameter KERNEL_NUM = 2,

    parameter KERNEL_AREA = KERNEL_SIZE * KERNEL_SIZE,
    parameter INPUT_NUM = KERNEL_AREA * KERNEL_NUM,
    parameter MULTIPLIED_WIDTH = IN_WIDTH + KERNEL_DATA_WIDTH,
    parameter OUT_WIDTH = MULTIPLIED_WIDTH + $clog2(INPUT_NUM),
    parameter NUM_PER_CYCLE = PORT_BITS / IN_WIDTH
) (
    input clk,
    input rst_n,
    input clk_en,
    input conv_en,
    input logic [PORT_BITS - 1:0] data_in,
    input logic signed [KERNEL_DATA_WIDTH - 1:0] kernel[KERNEL_NUM-1:0][KERNEL_SIZE-1:0][KERNEL_SIZE-1:0],
    output logic signed [OUT_WIDTH-1:0] data_out[NUM_PER_CYCLE - 1:0],
    output logic conv_out_vld,
    output logic read_en
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

  // Buffers, Conv Matrix, Zeros
  logic signed [IN_WIDTH - 1:0] buffer[KERNEL_SIZE-1:0][BUF_WIDTH-1:0];
  logic signed [MULTIPLIED_WIDTH-1:0] conv_mat[NUM_PER_CYCLE-1:0][KERNEL_NUM-1:0][KERNEL_SIZE-1:0][KERNEL_SIZE-1:0];
  logic [PORT_BITS-1:0] zeros = 0;

  // Indices
  logic [BUF_WIDTH_BITS - 1:0] buf_w, buf_h;
  logic [HW_BITS-1:0] conv_w, conv_h;  // Index for Conv Kernel on Top Left

  // State Machine
  localparam IDLE = 3'b1;
  localparam READ = 3'b10;
  localparam CONV = 3'b100;
  reg [2:0] n_state;
  reg [2:0] c_state;

  // Enable Signals
  reg add_en;

  // AdderTree
  logic signed [INPUT_NUM*MULTIPLIED_WIDTH-1:0] adder_tree_input[NUM_PER_CYCLE-1:0];

  // Latency
  localparam ADDER_LATENCY = $clog2(INPUT_NUM) + 2;
  logic [ADDER_LATENCY-1:0] add_out_en;

  genvar n, c, h, w;
  generate
    for (n = 0; n < NUM_PER_CYCLE; n = n + 1) begin
      for (c = 0; c < KERNEL_NUM; c = c + 1) begin
        for (h = 0; h < KERNEL_SIZE; h = h + 1) begin
          for (w = 0; w < KERNEL_SIZE; w = w + 1) begin
            assign adder_tree_input[n][(c*KERNEL_AREA + h*KERNEL_SIZE + w + 1) * MULTIPLIED_WIDTH -1-:MULTIPLIED_WIDTH] = conv_mat[n][c][h][w];
          end
        end
      end
      adder_tree #(
          .INPUT_NUM(INPUT_NUM),
          .IN_WIDTH (MULTIPLIED_WIDTH)
      ) adder_tree_inst (
          .clk  (clk),
          .rst_n(rst_n),
          .din  (adder_tree_input[n]),
          .dout (data_out[n])
      );
    end
  endgenerate

  // Main Logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      conv_h <= 0;
      conv_w <= 0;
      buf_w <= PAD_SIZE;
      buf_h <= PAD_SIZE;
      read_en <= 1'b1;
      add_en <= 1'b0;

      add_out_en <= '0;
      clear_buffer;
    end else if (clk_en) begin
      case (c_state)
        IDLE: begin  // NOTE: 少了一个add_out_en
          conv_h  <= 0;
          conv_w  <= 0;
          buf_w   <= PAD_SIZE;
          buf_h   <= PAD_SIZE;
          read_en <= conv_out_vld ? 1'b0 : 1'b1;
          add_en  <= 1'b0;

          clear_buffer;
        end

        READ: begin
          // Read Data
          for (int n = 0; n < NUM_PER_CYCLE; n = n + 1) begin
            buffer[KERNEL_SIZE-1][buf_w+n] <= signed'(data_in[(n+1)*IN_WIDTH-1-:IN_WIDTH]);
            for (int h = 0; h < KERNEL_SIZE - 1; h = h + 1) begin
              buffer[h][buf_w+n] <= buffer[h+1][buf_w+n];
            end
          end

          // Update Buffer Index
          if (buf_w + NUM_PER_CYCLE == FIRST_RIGHT_PAD_IDX) begin  // Last Column of Buffer
            buf_w <= PAD_SIZE;
            buf_h <= buf_h + 1;
          end else begin  // Normal Condition
            buf_w <= buf_w + NUM_PER_CYCLE;
          end

          // To Conv
          if (buf_w == PAD_SIZE && buf_h == KERNEL_SIZE - 1) begin
            add_en <= 1'b1;
          end
        end

        CONV: begin
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

          // Read Data
          if (buf_h >= FIRST_RIGHT_PAD_IDX) begin
            for (int n = 0; n < NUM_PER_CYCLE; n = n + 1) begin
              buffer[KERNEL_SIZE-1][buf_w+n] <= zeros;  // TODO:试试直接用'0
              for (int h = 0; h < KERNEL_SIZE - 1; h = h + 1) begin
                buffer[h][buf_w+n] <= buffer[h+1][buf_w+n];
              end
            end
          end else begin
            for (int n = 0; n < NUM_PER_CYCLE; n = n + 1) begin
              buffer[KERNEL_SIZE-1][buf_w+n] <= signed'(data_in[(n+1)*IN_WIDTH-1-:IN_WIDTH]);
              for (int h = 0; h < KERNEL_SIZE - 1; h = h + 1) begin
                buffer[h][buf_w+n] <= buffer[h+1][buf_w+n];
              end
            end
          end

          // Conv
          for (int n = 0; n < NUM_PER_CYCLE; n = n + 1) begin
            for (int c = 0; c < KERNEL_NUM; c = c + 1) begin
              for (int h = 0; h < KERNEL_SIZE; h = h + 1) begin
                for (int w = 0; w < KERNEL_SIZE; w = w + 1) begin
                  conv_mat[n][c][h][w] <= buffer[h][n+w+conv_w] * kernel[c][h][w];
                end
              end
            end
          end

          // To IDLE
          if (conv_h == ROI_SIZE - 1 && conv_w == ROI_SIZE - 2 * NUM_PER_CYCLE) begin
            add_en <= 1'b0;
          end
        end

      endcase
    end
  end

  task automatic clear_buffer;
    integer h, w;
    for (h = 0; h < KERNEL_SIZE; h = h + 1) begin
      for (w = 0; w < BUF_WIDTH; w = w + 1) begin
        buffer[h][w] <= '0;
      end
    end
  endtask

  // State Machine Setting
  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      c_state <= IDLE;
    end else if (clk_en) begin
      add_out_en <= {add_out_en[ADDER_LATENCY-2:0], add_en};
      conv_out_vld <= add_out_en[ADDER_LATENCY-1];  // WARN: 和其他器件连在一起的时候还是要连续赋值!!
      c_state <= n_state;
    end
  end

  always_comb begin
    case (c_state)
      IDLE: begin
        n_state = conv_en ? (conv_out_vld ? IDLE : READ) : IDLE;
      end
      READ: begin
        n_state = conv_en ? (add_en ? CONV : READ) : IDLE;
      end
      CONV: begin
        n_state = conv_en ? (add_en ? CONV : IDLE) : IDLE;
      end
      default: begin
        n_state = IDLE;
      end
    endcase
  end
endmodule
