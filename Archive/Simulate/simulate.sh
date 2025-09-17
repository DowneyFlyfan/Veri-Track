iverilog -g2012 -s tb_sobel_conv -o sim.out ../test_benches/tb_sobel_conv.sv ../Modules/adder_tree.sv ../Modules/sobel_conv.sv
vvp -lxt2 sim.out
rm sim.out
nohup gtkwave waveform.fst > /dev/null 2>&1 &
