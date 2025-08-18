`timescale 1ns / 100ps
// NOTE: 定点数除法
module fixed_point_divider #(
    IN_WIDTH = 12,
    OUT_WIDTH = 12 // NOTE: 因为是最大值归一化，所以要确保精度就需要相同的位数
) (
    input clk,
    input rst_n,
    input logic din_valid,

    input  logic signed [ IN_WIDTH-1:0] rs1,
    input  logic signed [ IN_WIDTH-1:0] rs2,
    output logic        [OUT_WIDTH-1:0] rd,
    output logic                        dout_valid
);

  localparam IN_SGNFC_WIDTH = IN_WIDTH - 1;
  localparam OUT_SGNFC_WIDTH = OUT_WIDTH - 1;
  localparam TOTAL_WIDTH = IN_SGNFC_WIDTH + OUT_SGNFC_WIDTH;

  logic [TOTAL_WIDTH - 1:0] dividend[TOTAL_WIDTH - 1:0];
  logic [TOTAL_WIDTH - 1:0] divisor[TOTAL_WIDTH - 1:0];
  logic [TOTAL_WIDTH-1:0] quotient[TOTAL_WIDTH - 1:0];
  logic [TOTAL_WIDTH-1:0] quotient_msk[TOTAL_WIDTH - 1:0];
  logic [TOTAL_WIDTH - 1:0] outsign;
  logic [TOTAL_WIDTH - 1:0] counter;

  genvar num;
  generate
    for (num = 0; num < TOTAL_WIDTH; num++) begin : gen_quotient_mask
      assign quotient_msk[num] = 1 << (TOTAL_WIDTH - 1 - num);
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dout_valid <= 1'b0;
      rd <= 'bx;
      counter <= 0;
      quotient[0] <= 0;
    end else begin

      begin : IO_assign
        dividend[0] <= (rs1[IN_WIDTH-1] ? -rs1[IN_WIDTH-2:0] : rs1[IN_WIDTH-2:0]) << OUT_SGNFC_WIDTH;
        divisor[0] <= (rs2[IN_WIDTH-1] ? -rs2[IN_WIDTH-2:0] : rs2[IN_WIDTH-2:0]) << OUT_SGNFC_WIDTH;
        outsign[0] <= (rs1[IN_WIDTH-1] != rs2[IN_WIDTH-1]) && |rs2;

        rd <= {outsign[TOTAL_WIDTH-1], quotient[TOTAL_WIDTH-1][TOTAL_WIDTH-1:OUT_SGNFC_WIDTH-1]};
      end

      begin : count_logic
        counter <= {counter[TOTAL_WIDTH-2:0], din_valid};
        dout_valid <= counter[TOTAL_WIDTH-1];
      end

      for (int n = 0; n < TOTAL_WIDTH - 1; n++) begin : pipelined_divide
        if (divisor[n] <= dividend[n]) begin
          dividend[n+1] <= dividend[n] - divisor[n];
          quotient[n+1] <= quotient[n] | quotient_msk[n];
        end else begin
          dividend[n+1] <= dividend[n];
          quotient[n+1] <= quotient[n];
        end
        divisor[n+1] <= divisor[n] >> 1;
        outsign[n+1] <= outsign[n];

      end

    end
  end
endmodule
