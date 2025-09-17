TOP_SV_FILE=../test_benches/tb_divider.sv
TOP_MODULE_NAME=$(basename ${TOP_SV_FILE} .sv)

verilator \
    --clk clk \
    --timing \
    --timescale 1ns/100ps \
    -Wno-fatal \
    -Wno-WIDTHEXPAND \
    -Wno-SELRANGE \
    -Wno-WIDTHTRUNC \
    -Wno-CASEINCOMPLETE \
    --cc ${TOP_SV_FILE} \
    ../Modules/divider.sv \
    --exe sim.cc \
    --trace-fst

make -C obj_dir -f V${TOP_MODULE_NAME}.mk V${TOP_MODULE_NAME}
./obj_dir/V${TOP_MODULE_NAME}

rm -rf obj_dir

# python ../Verifications/verify.py verify sobel

nohup gtkwave waveform.fst > /dev/null 2>&1 &
