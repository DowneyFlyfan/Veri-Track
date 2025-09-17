`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/11/26 15:01:44
// Design Name: 
// Module Name: channel_addition_core
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

module channel_addition_core#(
    parameter FMS_PATCH_SIZE = 8,
    parameter INPUT_DATA_WIDTH = 2,
    parameter OUTPUT_DATA_WIDTH = 20,
    parameter VALID_CORE_NUM = 16,
    parameter SRAM_SIZE_W = 8,
    parameter SRAM_SIZE_H = 4
    )(
    input clk,
    input rst_n,
    input clk_en,
    // input chn_add_en,
    input sram_change_vld,
    input fc_patch_fms_finish,
    input layer_mode,
    input quant_mode,
    input fms_data_vld,
    input [SRAM_SIZE_W*SRAM_SIZE_H*FMS_PATCH_SIZE*FMS_PATCH_SIZE*INPUT_DATA_WIDTH-1 : 0] fms_data,
    output reg calc_en,
    output reg infms_data_vld,
    output [VALID_CORE_NUM*FMS_PATCH_SIZE*FMS_PATCH_SIZE*OUTPUT_DATA_WIDTH-1 : 0] infms_data
    );
    localparam          CONV                    = 1'b0;
    localparam          FC                      = 1'b1;
    localparam          STAGE                   = $clog2(SRAM_SIZE_W);
    localparam          ADDER_OUTPUT_FULL_WIDTH = 12;
    localparam          IDLE                    = 2'b1;
    localparam          CAL_NO_CPRS             = 2'b10;
    reg [1:0]           n_state;
    reg [1:0]           c_state;

    // localparam          INFMS_RST               = 6'b1;
    localparam          INFMS_ADD               = 6'b10;
    localparam          INFMS_SHFT_SM           = 6'b100;
    localparam          INFMS_SHFT_BG           = 6'b1000;
    localparam          INFMS_IDLE              = 6'b10000;
    localparam          INFMS_WAIT              = 6'b100000;
    reg [5:0]           infms_n_state;
    reg [5:0]           infms_c_state;

    reg                 sram_change_vld_keep;
    reg [STAGE : 0]     sram_change_vld_dly;
    reg                 fc_patch_fms_finish_keep;
    reg [STAGE : 0]     fc_patch_fms_finish_dly;
    reg [5:0]           sram_change_cnt;
    reg [2:0]           fc_fms_first_cycle_cnt; //layer_mode==FC, only do INFMS_SHFT_BG. count first cycle(4 times INFMS_SHFT_BG)
    reg [1:0]           fms_data_vld_dly;    //used to generate another 2-claps fms_data_vld to channel_adder_tree
    reg [2:0]           adder_tree_output_cnt;
    reg                 adder_tree_input_vld;   //represent channel adder tree's pipeline vld, include output vld
    reg                 adder_tree_first_input_vld;
    //only connect 15 reg to infms_data, the 0-wght reg is useless
    
    reg [4:0]           infms_shift_ctrl;
    reg                 infms_data_prcs_vld;
    wire    [INPUT_DATA_WIDTH*SRAM_SIZE_W-1 : 0]    adder_tree_input            [SRAM_SIZE_H-1 : 0][FMS_PATCH_SIZE-1 : 0][FMS_PATCH_SIZE-1 : 0];
    reg     [INPUT_DATA_WIDTH*SRAM_SIZE_W-1 : 0]    adder_tree_input_reg        [SRAM_SIZE_H-1 : 0][FMS_PATCH_SIZE-1 : 0][FMS_PATCH_SIZE-1 : 0];
    wire                                            adder_tree_output_vld       [SRAM_SIZE_H-1 : 0][FMS_PATCH_SIZE-1 : 0][FMS_PATCH_SIZE-1 : 0];
    wire    [INPUT_DATA_WIDTH-1 : 0]                adder_tree_output           [SRAM_SIZE_H-1 : 0][FMS_PATCH_SIZE-1 : 0][FMS_PATCH_SIZE-1 : 0];
    //here is 12bit, but eight signed 8-bit numbers' sum-output should use 11th bit to extend sign bit!!
    reg     [ADDER_OUTPUT_FULL_WIDTH-1 : 0]         adder_tree_output_full      [SRAM_SIZE_H-1 : 0][FMS_PATCH_SIZE-1 : 0][FMS_PATCH_SIZE-1 : 0];
    wire    [OUTPUT_DATA_WIDTH-1 : 0]               infms_shift_buffer_din_mat  [SRAM_SIZE_H-1 : 0][FMS_PATCH_SIZE-1 : 0][FMS_PATCH_SIZE-1 : 0];
    wire    [OUTPUT_DATA_WIDTH*SRAM_SIZE_H*FMS_PATCH_SIZE*FMS_PATCH_SIZE-1 : 0] infms_shift_buffer_din;
    reg     [OUTPUT_DATA_WIDTH*SRAM_SIZE_H*FMS_PATCH_SIZE*FMS_PATCH_SIZE-1 : 0] infms_shift_buffer_din_reg;
    genvar h,w,sram_h,sram_w,core_no;
    generate
        //generate channel_adder_tree
        for(sram_h=0;sram_h<SRAM_SIZE_H;sram_h=sram_h+1) begin
            for(h=0;h<FMS_PATCH_SIZE;h=h+1) begin
                for(w=0;w<FMS_PATCH_SIZE;w=w+1) begin
                    channel_adder_tree#(
                        .INPUT_NUM(SRAM_SIZE_W),
                        .INPUT_DATA_WIDTH(INPUT_DATA_WIDTH)
                    )
                    channel_adder_tree_inst(
                        .clk(clk),
                        .rst_n(rst_n),
                        .clk_en(clk_en),
                        .din_vld(adder_tree_input_vld),
                        .first_din_vld(adder_tree_first_input_vld),
                        .din(adder_tree_input_reg[sram_h][h][w]),
                        .dout(adder_tree_output[sram_h][h][w]),
                        .dout_vld(adder_tree_output_vld[sram_h][h][w])
                    );
                end
            end
        end
        //fms_data -> adder_tree_input
        for(sram_h=0;sram_h<SRAM_SIZE_H;sram_h=sram_h+1) begin
            for(sram_w=0;sram_w<SRAM_SIZE_W;sram_w=sram_w+1) begin
                for(h=0;h<FMS_PATCH_SIZE;h=h+1) begin
                    for(w=0;w<FMS_PATCH_SIZE;w=w+1) begin
                        assign adder_tree_input[sram_h][h][w][sram_w*INPUT_DATA_WIDTH +: INPUT_DATA_WIDTH] = {fms_data[(sram_h*SRAM_SIZE_W+sram_w)*FMS_PATCH_SIZE*FMS_PATCH_SIZE*INPUT_DATA_WIDTH + h*FMS_PATCH_SIZE + w + FMS_PATCH_SIZE*FMS_PATCH_SIZE],
                                                                                                                fms_data[(sram_h*SRAM_SIZE_W+sram_w)*FMS_PATCH_SIZE*FMS_PATCH_SIZE*INPUT_DATA_WIDTH + h*FMS_PATCH_SIZE + w]};
                    end
                end
            end
        end
        //adder_tree_output_full -> infms_shift_buffer_din_mat(extend sign bit)
        //infms_shift_buffer_din_mat -> infms_shift_buffer_din
        for(core_no=0;core_no<SRAM_SIZE_H;core_no=core_no+1) begin
            for(h=0;h<FMS_PATCH_SIZE;h=h+1) begin
                for(w=0;w<FMS_PATCH_SIZE;w=w+1) begin
                    assign infms_shift_buffer_din_mat[core_no][h][w] = {{(OUTPUT_DATA_WIDTH-ADDER_OUTPUT_FULL_WIDTH){adder_tree_output_full[core_no][h][w][ADDER_OUTPUT_FULL_WIDTH-1]}}, adder_tree_output_full[core_no][h][w]};
                    assign infms_shift_buffer_din[(core_no*FMS_PATCH_SIZE*FMS_PATCH_SIZE+h*FMS_PATCH_SIZE+w)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = infms_shift_buffer_din_mat[core_no][h][w];
                end
            end
        end
    endgenerate

    infms_shift_buffer #(
        .VALID_CORE_NUM(VALID_CORE_NUM),
        .FMS_PATCH_SIZE(FMS_PATCH_SIZE),
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH),
        .INPUT_DATA_WGHT_NUM(SRAM_SIZE_H)
    ) infms_shift_buffer_inst(
        .clk(clk),
        .rst_n(rst_n),
        .clk_en(clk_en),
        .idle(infms_shift_ctrl[4]),
        .shft_bg_en(infms_shift_ctrl[3]),
        .shft_sm_en(infms_shift_ctrl[2]),
        .add_en(infms_shift_ctrl[1]),
        .rst_en(infms_shift_ctrl[0]),

        .din(infms_shift_buffer_din_reg),
        .dout(infms_data)
    );
    
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            c_state <= IDLE;
            // infms_c_state <= INFMS_RST;
            infms_c_state <= INFMS_WAIT;
        end
        else if(clk_en) begin
            c_state <= n_state;
            infms_c_state <= infms_n_state;
        end
    end

    integer patch_h,patch_w,wght_no,i;
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            calc_en                     <= 1'b0;
            infms_data_vld              <= 1'b0;
            sram_change_vld_keep        <= 1'b0;
            fc_patch_fms_finish_keep    <= 1'b0;
            sram_change_cnt             <= 6'b0;
            fms_data_vld_dly            <= 2'b0;
            adder_tree_output_cnt       <= 3'b0;
            adder_tree_input_vld        <= 1'b0;
            adder_tree_first_input_vld  <= 1'b0;
            infms_data_prcs_vld         <= 1'b0;
            sram_change_vld_dly         <= {(STAGE+1){1'b0}};
            fc_patch_fms_finish_dly     <= {(STAGE+1){1'b0}};
            infms_shift_ctrl            <= INFMS_IDLE[0 +: 5];
            fc_fms_first_cycle_cnt      <= 3'b0;
        end
        else if(clk_en) begin
            case(c_state)
                IDLE: begin
                    calc_en                     <= 1'b0;
                    infms_data_vld              <= 1'b0;
                    sram_change_vld_keep        <= 1'b0;
                    fc_patch_fms_finish_keep    <= 1'b0;
                    sram_change_cnt             <= 6'b0;
                    fms_data_vld_dly            <= 2'b0;
                    adder_tree_output_cnt       <= 3'b0;
                    adder_tree_input_vld        <= 1'b0;
                    adder_tree_first_input_vld  <= 1'b0;
                    infms_data_prcs_vld         <= 1'b0;
                    sram_change_vld_dly         <= {(STAGE+1){1'b0}};
                    fc_patch_fms_finish_dly     <= {(STAGE+1){1'b0}};
                    infms_shift_ctrl            <= INFMS_IDLE[0 +: 5];
                    fc_fms_first_cycle_cnt      <= 3'b0;
                    if(fms_data_vld || sram_change_vld) begin
                        fms_data_vld_dly            <= {fms_data_vld_dly[0],fms_data_vld};
                        adder_tree_input_vld        <= ((|fms_data_vld_dly) || fms_data_vld);
                        adder_tree_first_input_vld  <= ({fms_data_vld_dly[0],fms_data_vld}==2'b01) ? 1'b1 : 1'b0;
                        sram_change_vld_dly         <= {sram_change_vld_dly[STAGE-1:0],sram_change_vld};
                        fc_patch_fms_finish_dly     <= {fc_patch_fms_finish_dly[STAGE-1:0],fc_patch_fms_finish};
                        if(fms_data_vld) begin
                            for(wght_no=0;wght_no<SRAM_SIZE_H;wght_no=wght_no+1) begin
                                for(patch_h=0;patch_h<FMS_PATCH_SIZE;patch_h=patch_h+1) begin
                                    for(patch_w=0;patch_w<FMS_PATCH_SIZE;patch_w=patch_w+1) begin
                                        adder_tree_input_reg[wght_no][patch_h][patch_w] <= adder_tree_input[wght_no][patch_h][patch_w];
                                    end
                                end
                            end
                        end
                    end
                end
                CAL_NO_CPRS: begin
                    fms_data_vld_dly            <= {fms_data_vld_dly[0],fms_data_vld};
                    adder_tree_input_vld        <= (|{fms_data_vld_dly,fms_data_vld});
                    adder_tree_first_input_vld  <= ({fms_data_vld_dly[0],fms_data_vld}==2'b01) ? 1'b1 : 1'b0;
                    calc_en                     <= 1'b0;
                    sram_change_vld_dly         <= {sram_change_vld_dly[STAGE-1:0],sram_change_vld};
                    fc_patch_fms_finish_dly     <= {fc_patch_fms_finish_dly[STAGE-1:0],fc_patch_fms_finish};
                    //input logic
                    if(fms_data_vld) begin
                        for(wght_no=0;wght_no<SRAM_SIZE_H;wght_no=wght_no+1) begin
                            for(patch_h=0;patch_h<FMS_PATCH_SIZE;patch_h=patch_h+1) begin
                                for(patch_w=0;patch_w<FMS_PATCH_SIZE;patch_w=patch_w+1) begin
                                    adder_tree_input_reg[wght_no][patch_h][patch_w] <= adder_tree_input[wght_no][patch_h][patch_w];
                                end
                            end
                        end
                    end
                    else begin
                        //extend sign bit, and output channel_adder_tree's internal cin data
                        for(wght_no=0;wght_no<SRAM_SIZE_H;wght_no=wght_no+1) begin
                            for(patch_h=0;patch_h<FMS_PATCH_SIZE;patch_h=patch_h+1) begin
                                for(patch_w=0;patch_w<FMS_PATCH_SIZE;patch_w=patch_w+1) begin
                                    for(i=0;i<SRAM_SIZE_W;i=i+1) begin
                                        adder_tree_input_reg[wght_no][patch_h][patch_w][i*2 +: 2] <= {2{adder_tree_input_reg[wght_no][patch_h][patch_w][i*2+1]}};
                                    end
                                end
                            end
                        end
                    end

                    if(adder_tree_output_vld[0][0][0] && adder_tree_output_cnt==3'd5) begin
                        infms_data_prcs_vld <= 1'b1;
                    end
                    else begin
                        infms_data_prcs_vld <= 1'b0;
                    end
                    if(adder_tree_output_vld[0][0][0]) begin
                        if(adder_tree_output_cnt==3'd5) begin
                            adder_tree_output_cnt <= 3'b0;
                        end
                        else begin
                            adder_tree_output_cnt <= adder_tree_output_cnt + 1'b1;
                        end
                        for(wght_no=0;wght_no<SRAM_SIZE_H;wght_no=wght_no+1) begin
                            for(patch_h=0;patch_h<FMS_PATCH_SIZE;patch_h=patch_h+1) begin
                                for(patch_w=0;patch_w<FMS_PATCH_SIZE;patch_w=patch_w+1) begin
                                    adder_tree_output_full[wght_no][patch_h][patch_w][ADDER_OUTPUT_FULL_WIDTH-1 -: 2] <= adder_tree_output[wght_no][patch_h][patch_w];
                                    adder_tree_output_full[wght_no][patch_h][patch_w][ADDER_OUTPUT_FULL_WIDTH-3 : 0] <= adder_tree_output_full[wght_no][patch_h][patch_w][ADDER_OUTPUT_FULL_WIDTH-1 : 2];
                                end
                            end
                        end
                    end

                    if(sram_change_vld_dly[STAGE]) begin
                        sram_change_vld_keep <= sram_change_vld_dly[STAGE];
                    end
                    if(fc_patch_fms_finish_dly[STAGE]) begin
                        fc_patch_fms_finish_keep <= fc_patch_fms_finish_dly[STAGE];
                    end

                    case(infms_c_state)
                        // INFMS_RST: begin
                        //     calc_en <= 1'b0;
                        //     infms_data_vld <= 1'b0;
                        //     sram_change_vld_keep <= 1'b0;
                        //     fc_patch_fms_finish_keep <= 1'b0;
                        //     infms_shift_ctrl <= INFMS_RST[0 +: 5];
                        // end
                        INFMS_ADD: begin
                            if(infms_data_prcs_vld) begin
                                infms_shift_ctrl <= INFMS_ADD[0 +: 5];
                                infms_shift_buffer_din_reg <= infms_shift_buffer_din;
                            end
                        end
                        INFMS_SHFT_SM: begin
                            calc_en <= 1'b0;
                            infms_data_vld <= 1'b0;
                            sram_change_vld_keep <= 1'b0;
                            fc_patch_fms_finish_keep <= 1'b0;
                            sram_change_cnt <= sram_change_cnt + 1'b1;
                            infms_shift_ctrl <= calc_en ? INFMS_IDLE[0 +: 5] : INFMS_SHFT_SM[0 +: 5];
                        end
                        INFMS_SHFT_BG: begin
                            case(layer_mode)
                                CONV: begin
                                    infms_data_vld  <= (sram_change_cnt==6'd16 || sram_change_cnt==6'd32) ? 1'b1 : 1'b0;
                                    calc_en         <= (sram_change_cnt==6'd16) ? 1'b1 : 1'b0;
                                end
                                FC: begin
                                    fc_fms_first_cycle_cnt  <= (fc_fms_first_cycle_cnt<3'd4) ? fc_fms_first_cycle_cnt+1'b1 : fc_fms_first_cycle_cnt;
                                    infms_data_vld          <= (fc_patch_fms_finish_keep || fc_patch_fms_finish_dly[STAGE]) ? 1'b1 : 1'b0;
                                    calc_en                 <= (fc_patch_fms_finish_keep || fc_patch_fms_finish_dly[STAGE]) ? 1'b1 : 1'b0;
                                    sram_change_vld_keep <= 1'b0;
                                    fc_patch_fms_finish_keep <= 1'b0;
                                end
                            endcase
                            infms_shift_ctrl <= INFMS_SHFT_BG[0 +: 5];
                        end
                        INFMS_WAIT: begin
                            calc_en <= 1'b0;
                            infms_data_vld <= 1'b0;
                            sram_change_vld_keep <= 1'b0;
                            fc_patch_fms_finish_keep <= 1'b0;
                            infms_shift_ctrl <= calc_en ? INFMS_IDLE[0 +: 5] : INFMS_WAIT[0 +: 5];
                            
                        end
                    endcase
                end
            endcase
        end
    end

    always @(*) begin
        case(c_state)
            IDLE: n_state = (fms_data_vld || sram_change_vld) ? CAL_NO_CPRS : IDLE;
            CAL_NO_CPRS: begin
                case(layer_mode)
                    CONV: begin
                        if (quant_mode) begin
                            n_state = (sram_change_cnt==6'd32 && infms_data_vld) ? IDLE : CAL_NO_CPRS;
                        end
                        else begin
                            n_state = (sram_change_cnt==6'd16 && infms_data_vld) ? IDLE : CAL_NO_CPRS;
                        end
                    end
                    FC: n_state = (infms_c_state==INFMS_SHFT_BG && (fc_patch_fms_finish_keep || fc_patch_fms_finish_dly[STAGE])) ? IDLE : CAL_NO_CPRS;
                    default: n_state = CAL_NO_CPRS;
                endcase
            end
            default: n_state = IDLE;
        endcase
    end

    always @(*) begin
        case(c_state)
            CAL_NO_CPRS: begin
                case(infms_c_state)
                    // INFMS_RST: begin
                    //     infms_n_state = adder_tree_output_vld[0][0][0] ? INFMS_ADD : (sram_change_vld_dly[STAGE] ? INFMS_SHFT_SM : INFMS_RST);
                    // end
                    INFMS_ADD: begin
                        case(layer_mode)
                            CONV:       infms_n_state = infms_data_prcs_vld ? ((sram_change_vld_keep || sram_change_vld_dly[STAGE]) ? INFMS_SHFT_SM : INFMS_WAIT) : INFMS_ADD;
                            FC:         infms_n_state = (infms_data_prcs_vld && (sram_change_vld_keep || sram_change_vld_dly[STAGE])) ? INFMS_SHFT_BG : INFMS_ADD;
                            // default:    infms_n_state = INFMS_RST;
                            default:    infms_n_state = INFMS_WAIT;
                        endcase
                    end
                    INFMS_SHFT_SM: begin
                        infms_n_state = ((sram_change_cnt+1'b1) % SRAM_SIZE_H == 0) ? INFMS_SHFT_BG : INFMS_WAIT;
                    end
                    INFMS_SHFT_BG: begin
                        // case(layer_mode)
                        //     CONV:       infms_n_state = INFMS_RST;
                        //     FC:         infms_n_state = (fc_patch_fms_finish_keep || fc_patch_fms_finish_dly[STAGE]) ? INFMS_RST : ((fc_fms_first_cycle_cnt < (3'd4-1'b1)) ? INFMS_RST : INFMS_WAIT);
                        //     default:    infms_n_state = INFMS_RST;
                        // endcase
                        infms_n_state = (sram_change_vld_dly[STAGE] ? INFMS_SHFT_SM : INFMS_WAIT);
                    end
                    INFMS_WAIT: begin
                        infms_n_state = adder_tree_output_vld[0][0][0] ? INFMS_ADD : (sram_change_vld_dly[STAGE] ? INFMS_SHFT_SM : INFMS_WAIT);
                    end
                    // default: infms_n_state = INFMS_RST;
                    default: infms_n_state = INFMS_WAIT;
                endcase
            end
            // default: infms_n_state = INFMS_RST;
            default: infms_n_state = INFMS_WAIT;
        endcase
    end
endmodule
