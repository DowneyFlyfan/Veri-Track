`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/11/25 21:06:58
// Design Name: 
// Module Name: channel_adder_tree
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module channel_adder_tree#(
    parameter INPUT_NUM = 8,
    parameter INPUT_DATA_WIDTH = 2
    )(
    input clk,
    input rst_n,
    input clk_en,
    input din_vld,
    input first_din_vld,
    input [INPUT_NUM*INPUT_DATA_WIDTH-1 : 0] din,
    output [INPUT_DATA_WIDTH-1 : 0] dout,
    output dout_vld
    );

    localparam STAGE =  $clog2(INPUT_NUM);
    localparam INPUT_NUM_INIT = 2 ** STAGE;
    reg                             adder_tree_vld          [STAGE : 0];
    reg                             adder_tree_first_vld    [STAGE : 0];
    reg [INPUT_DATA_WIDTH-1 : 0]    adder_tree_data_2bit    [STAGE : 0][INPUT_NUM_INIT-1 : 0];
    reg                             adder_tree_data_cin     [STAGE-1 : 0][(INPUT_NUM_INIT>>1)-1 : 0];

    genvar stage,no;    //stage and number
    // generate
    //     for(stage=0;stage<STAGE;stage=stage+1) begin
    //         localparam CRNT_STAGE_NUM = INPUT_NUM_INIT >> stage;
    //         for(no=0;no<CRNT_STAGE_NUM;no=no+1) begin
    //             full_adder_2bit#(
    //                 .INPUT_DATA_WIDTH(INPUT_DATA_WIDTH))
    //             full_adder_2bit_inst(
    //                 .din_vld(din_vld_pipe[stage]),
    //                 .din_a(adder_tree_data_2bit[stage][no*2]),
    //                 .din_b(adder_tree_data_2bit[stage][no*2+1]),
    //                 .cin())
    //         end
    //     end
    // endgenerate
    generate
        for(stage=0;stage<=STAGE;stage=stage+1) begin
            localparam CRNT_STAGE_NUM = INPUT_NUM_INIT >> stage;
            if(stage==0) begin
                always @(*) begin
                    adder_tree_vld[stage] = din_vld;
                    adder_tree_first_vld[stage] = first_din_vld;
                end
                for(no=0;no<CRNT_STAGE_NUM;no=no+1) begin
                    always @(*) begin
                        if(no<INPUT_NUM)
                            adder_tree_data_2bit[stage][no] = din[no*INPUT_DATA_WIDTH +: INPUT_DATA_WIDTH];
                        else
                            adder_tree_data_2bit[stage][no] = {(INPUT_DATA_WIDTH){1'b0}};
                    end
                end
            end
            else begin
                always @(posedge clk or negedge rst_n) begin
                    if(~rst_n) begin
                        adder_tree_vld[stage] <= 1'b0;
                        adder_tree_first_vld[stage] <= 1'b0;
                    end
                    else if(clk_en) begin
                        adder_tree_vld[stage] <= adder_tree_vld[stage - 1];
                        adder_tree_first_vld[stage] <= adder_tree_first_vld[stage - 1];
                    end
                end
                for(no=0;no<CRNT_STAGE_NUM;no=no+1) begin
                    always @(posedge clk) begin
                        if(clk_en) begin
                            if(adder_tree_vld[stage-1]) begin
                                if(adder_tree_first_vld[stage-1]) begin
                                    {adder_tree_data_cin[stage-1][no],adder_tree_data_2bit[stage][no]} <= adder_tree_data_2bit[stage-1][no*2] + adder_tree_data_2bit[stage-1][no*2+1];
                                end
                                else begin
                                    {adder_tree_data_cin[stage-1][no],adder_tree_data_2bit[stage][no]} <= adder_tree_data_2bit[stage-1][no*2] + adder_tree_data_2bit[stage-1][no*2+1]
                                                                                                        + adder_tree_data_cin[stage-1][no];
                                end
                                
                            end
                        end
                    end
                end
            end
        end
    endgenerate
    assign dout = adder_tree_data_2bit[STAGE][0];
    assign dout_vld = adder_tree_vld[STAGE];
endmodule
