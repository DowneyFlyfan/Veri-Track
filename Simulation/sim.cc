#include "obj_dir/Vtb_divider.h"
#include "verilated.h"
#include "verilated_fst_c.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  Vtb_divider *top = new Vtb_divider;
  Verilated::traceEverOn(true);
  VerilatedFstC *tfp =
      new VerilatedFstC; // tfp: trace file pointer (跟踪文件指针), fst: Fast
                         // Signal Trace (快速信号跟踪)
  top->trace(tfp, 99);   // 启用波形跟踪，将所有信号（深度为99）写入跟踪文件
  tfp->open("waveform.fst");

  while (!Verilated::gotFinish()) {
    top->eval();
    tfp->dump(Verilated::time());
    Verilated::timeInc(1); // increase仿真时间
  }

  tfp->close();
  delete top;
  return 0;
}
