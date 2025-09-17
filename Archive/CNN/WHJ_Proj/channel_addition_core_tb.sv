`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/11/05 16:34:47
// Design Name: 
// Module Name: multiplication_core_tb
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


module channel_addition_core_tb;

parameter
    FMS_PATCH_SIZE = 8,
    INPUT_DATA_WIDTH = 2,
    OUTPUT_DATA_WIDTH = 20,
    VALID_CORE_NUM = 15,
    SRAM_SIZE_W = 8,
    SRAM_SIZE_H = 4,
    FMS_NUM = 9216;

integer i, h;
integer fd1, fd2;

// IO
reg clk;
reg rst_n;
reg clk_en;
reg chn_add_en;
reg sram_change_vld;
reg quant_mode;
reg sram_data_vld;
reg [SRAM_SIZE_W*SRAM_SIZE_H*FMS_PATCH_SIZE*FMS_PATCH_SIZE*INPUT_DATA_WIDTH-1 : 0] sram_data;

reg [SRAM_SIZE_W*SRAM_SIZE_H*FMS_PATCH_SIZE*FMS_PATCH_SIZE*INPUT_DATA_WIDTH-1 : 0] sram_data_int4_mem [FMS_NUM-1 : 0];
reg [SRAM_SIZE_W*SRAM_SIZE_H*FMS_PATCH_SIZE*FMS_PATCH_SIZE*INPUT_DATA_WIDTH-1 : 0] sram_data_int8_mem [FMS_NUM*2-1 : 0];
reg [VALID_CORE_NUM*FMS_PATCH_SIZE*FMS_PATCH_SIZE*OUTPUT_DATA_WIDTH-1 : 0] infms_data_int4_mem [FMS_NUM/64-1 : 0];
reg [VALID_CORE_NUM*FMS_PATCH_SIZE*FMS_PATCH_SIZE*OUTPUT_DATA_WIDTH-1 : 0] infms_data_int8_mem [FMS_NUM/32-1 : 0];
reg result_correct;
reg [10:0] cnt;

wire calc_en;
wire infms_data_vld;
wire [VALID_CORE_NUM*FMS_PATCH_SIZE*FMS_PATCH_SIZE*OUTPUT_DATA_WIDTH-1 : 0] infms_data;

//////////////////////////////////////////////////////////////////////////////////

// Clock define
always #4 clk <= ~clk;	// T=8ns,f=125MHz

// Module under test
channel_addition_core channel_addition_core_inst(
    .clk(clk),
    .rst_n(rst_n),
    .clk_en(clk_en),
    .chn_add_en(chn_add_en),
    .sram_change_vld(sram_change_vld),
    .quant_mode(quant_mode),
    .sram_data_vld(sram_data_vld),
    .sram_data(sram_data),
    
    .calc_en(calc_en),
    .infms_data_vld(infms_data_vld),
    .infms_data(infms_data)
);

//////////////////////////////////////////////////////////////////////////////////

// Define test task
task load_test_data;
    input weight_quant_mode;
    begin
        // debug file
//        fd1 = $fopen("D:/Data/CVISP/CVISP.sim/fms/channel_add_output_verilog.mem", "w");
        if (weight_quant_mode == 1'b0) begin  // 0-int4, 1-int8
            $readmemb("D:/Data/CVISP/project_2/project_2.sim/fms/sram_data_int4.mem", sram_data_int4_mem);
            $readmemb("D:/Data/CVISP/project_2/project_2.sim/fms/fms_sum_int4.mem", infms_data_int4_mem);
        end
        else if (weight_quant_mode == 1'b1) begin  // 0-int4, 1-int8
            $readmemb("D:/Data/CVISP/project_2/project_2.sim/fms/sram_data_int8.mem", sram_data_int8_mem);
            $readmemb("D:/Data/CVISP/project_2/project_2.sim/fms/fms_sum_int8.mem", infms_data_int8_mem);
        end
    end
endtask 

task verify_result_int4;
    input [VALID_CORE_NUM*FMS_PATCH_SIZE*FMS_PATCH_SIZE*OUTPUT_DATA_WIDTH-1 : 0] result_input;
    begin
        if (infms_data == result_input) begin
            result_correct = 1'b1;
            cnt = cnt+1;
        end
        else begin
            result_correct = 1'b0;
        end
        repeat(1) @(negedge clk);
        result_correct = 1'b0;
    end
endtask 

task verify_result_int8;
    input [VALID_CORE_NUM*FMS_PATCH_SIZE*FMS_PATCH_SIZE*OUTPUT_DATA_WIDTH-1 : 0] result_input;
    begin
        if (infms_data == result_input) begin
            result_correct = 1'b1;
            cnt = cnt+1;
        end
        else begin
            result_correct = 1'b0;
        end
        repeat(1) @(negedge clk);
        result_correct = 1'b0;
    end
endtask 

task load_sram_data;
    input quant_mode;
    begin
        $display("[INFO] Quant mode: %b",quant_mode);
        cnt = 11'b0;
        load_test_data(.weight_quant_mode(quant_mode));
//        repeat(1) @(negedge clk);
//        chn_add_en = 1'b1;    // chn_add_en and sram_data_vld async
//        repeat(1) @(negedge clk);
//        chn_add_en = 1'b0;
        if (quant_mode == 1'b0) begin    //0:INT4 1:INT8
            for (i=0;i<FMS_NUM;i=i+1) begin
                if ((i+1) == FMS_NUM) begin
                    sram_data = sram_data_int4_mem[i];
                    sram_data_vld = 1'b1;
                    repeat(1) @(negedge clk);
                    sram_data_vld = 1'b0;
                    repeat(1) @(negedge clk);
                    sram_change_vld = 1'b1;
                    repeat(1) @(negedge clk);
                    sram_change_vld = 1'b0;
                    repeat(1) @(channel_addition_core_inst.c_state==3'b1);
                    repeat(2) @(negedge clk);
                end
                else if ((i+1) % 64 == 0) begin
                    sram_data = sram_data_int4_mem[i];
                    sram_data_vld = 1'b1;
                    repeat(1) @(negedge clk);
                    sram_data_vld = 1'b0;
                    repeat(1) @(negedge clk);
                    sram_change_vld = 1'b1;
                    repeat(1) @(negedge clk);
                    sram_change_vld = 1'b0;
                    repeat(1) @(channel_addition_core_inst.c_state==3'b1);
                    repeat(2) @(negedge clk);
                    chn_add_en = 1'b1;
                    repeat(1) @(negedge clk);
                    chn_add_en = 1'b0;
                end
                else if ((i+1) == 1) begin  // chn_add_en and sram_data_vld sync
                    sram_data = sram_data_int4_mem[i];
                    sram_data_vld = 1'b1;
                    chn_add_en = 1'b1;
                    repeat(1) @(negedge clk);
                end
                else if ((i+1) % 4 == 0) begin
                    sram_data = sram_data_int4_mem[i];
                    sram_data_vld = 1'b1;
                    repeat(1) @(negedge clk);
                    sram_data_vld = 1'b0;
                    repeat(1) @(negedge clk);
                    sram_change_vld = 1'b1;
                    repeat(1) @(negedge clk);
                    sram_change_vld = 1'b0;
                    repeat(2) @(negedge clk);
                end
                else begin
                    sram_data = sram_data_int4_mem[i];
                    sram_data_vld = 1'b1;
                    chn_add_en = 1'b0;
                    repeat(1) @(negedge clk);
                end
            end
        end
        else if (quant_mode == 1'b1) begin    //0:INT4 1:INT8
            for (i=0;i<FMS_NUM*2;i=i+1) begin
                if ((i+1) == FMS_NUM*2) begin
                    sram_data = sram_data_int8_mem[i];
                    sram_data_vld = 1'b1;
                    repeat(1) @(negedge clk);
                    sram_data_vld = 1'b0;
                    repeat(1) @(negedge clk);
                    sram_change_vld = 1'b1;
                    repeat(1) @(negedge clk);
                    sram_change_vld = 1'b0;
                    repeat(1) @(channel_addition_core_inst.c_state==3'b1);
                    repeat(2) @(negedge clk);
                end
                else if ((i+1) % 128 == 0) begin
                    sram_data = sram_data_int8_mem[i];
                    sram_data_vld = 1'b1;
                    repeat(1) @(negedge clk);
                    sram_data_vld = 1'b0;
                    repeat(1) @(negedge clk);
                    sram_change_vld = 1'b1;
                    repeat(1) @(negedge clk);
                    sram_change_vld = 1'b0;
                    repeat(1) @(channel_addition_core_inst.c_state==3'b1);
                    repeat(2) @(negedge clk);
                    chn_add_en = 1'b1;
                    repeat(1) @(negedge clk);
                    chn_add_en = 1'b0;
                end
                else if ((i+1) == 1) begin  // chn_add_en and sram_data_vld sync
                    sram_data = sram_data_int8_mem[i];
                    sram_data_vld = 1'b1;
                    chn_add_en = 1'b1;
                    repeat(1) @(negedge clk);
                end
                else if ((i+1) % 4 == 0) begin
                    sram_data = sram_data_int8_mem[i];
                    sram_data_vld = 1'b1;
                    repeat(1) @(negedge clk);
                    sram_data_vld = 1'b0;
                    repeat(1) @(negedge clk);
                    sram_change_vld = 1'b1;
                    repeat(1) @(negedge clk);
                    sram_change_vld = 1'b0;
                    repeat(2) @(negedge clk);
                end
                else begin
                    sram_data = sram_data_int8_mem[i];
                    sram_data_vld = 1'b1;
                    chn_add_en = 1'b0;
                    repeat(1) @(negedge clk);
                end
            end
        end
    end
endtask

//////////////////////////////////////////////////////////////////////////////////

// Initial define
initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    clk_en = 1'b0;
    chn_add_en = 1'b0;
    sram_change_vld = 1'b0;
    quant_mode = 1'b0;
    sram_data_vld = 1'b0;
    sram_data = 4096'b0;

    result_correct = 1'b0;
    repeat(1) @(negedge clk);
    clk_en = 1'b1;
    repeat(1) @(negedge clk);
    rst_n = 1'b1;
end

// Perform random test
always begin
    repeat(3) @(negedge clk);
    // different mode test
    quant_mode = 1'b1;
    load_sram_data(.quant_mode(quant_mode)); 
    quant_mode = 1'b0;
    load_sram_data(.quant_mode(quant_mode));
     
	repeat(8) @(negedge clk);
//	$fclose(fd1);
	$finish;
end

// Perform result checking
always begin
    repeat(1) @(infms_data_vld==1'b1);
    repeat(1) @(negedge clk);
    // write debug data
//    $fdisplay(fd1, "%b", infms_data);
    if (quant_mode == 1'b0) begin    //0:INT4 1:INT8
        verify_result_int4(.result_input(infms_data_int4_mem[cnt]));
    end
    else begin
        verify_result_int8(.result_input(infms_data_int8_mem[cnt]));
    end
end

endmodule
