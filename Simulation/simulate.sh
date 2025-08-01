verilator \
    --clk clk \
    --timing \
    --timescale 1ns/100ps \
    -Wno-fatal \
    -Wno-WIDTHEXPAND \
    -Wno-SELRANGE \
    -Wno-WIDTHTRUNC \
    -Wno-CASEINCOMPLETE \
    --cc ../test_benches/tb_sobel_conv.sv \
    ../Modules/adder_tree.sv \
    ../Modules/sobel_conv.sv \
    --exe sim_main.cc \
    --trace-fst

make -C obj_dir -f Vtb_sobel_conv.mk Vtb_sobel_conv
./obj_dir/Vtb_sobel_conv
rm -rf obj_dir

nohup gtkwave waveform.fst > /dev/null 2>&1 &
