# 五级流水线 MIPS CPU（WELOG1 FPGA）

清华大学《数字逻辑电路实验》夏季学期绪论大作业。本项目用 Verilog 实现了一个支持
数据前推（forwarding）与冒险检测（hazard detection）的**五级流水线 MIPS 处理器**，
并在 WELOG1（Xilinx Artix-7 `xc7a35t`）开发板上完成上板验证。板上通过 UART 与 PC
双向通信，运行《传纸条》动态规划程序：PC 发送数据集，CPU 计算后回传结果，同时在
七段数码管上显示。

## 特性

- **经典 5 级流水线**：IF / ID / EX / MEM / WB。
- **数据前推**：EX/MEM、MEM/WB 旁路到 EX，消除大部分 RAW 相关。
- **冒险处理**：load-use 相关插入一周期气泡；分支/跳转在 EX（`beq`/`jr`）与 ID
  （`j`/`jal`）解析并冲刷流水线。
- **内存映射外设（MMIO）**：七段数码管 + UART（9600 8N1）。
- **真机验证**：CPU 时钟 = `clk100 / 2 = 50 MHz`，时序收敛（WNS ≈ +4.3 ns），
  上板《传纸条》全部测试集结果正确。

## 目录结构

```
src/                 综合用 Verilog 源码
  top.v              顶层：时钟分频、七段译码、外设接线
  PipelineCPU.v      五级流水线数据通路 + 控制
  Control.v          主控制器        ALUControl.v   ALU 控制
  ALU.v              算术逻辑单元    RegisterFile.v 寄存器堆
  ForwardingUnit.v   前推单元        HazardUnit.v   冒险/冲刷单元
  InstructionMemory.v / DataMemory.v
  MemBus.v           内存+外设总线（地址译码、MMIO）
  UART.v             UART 收发器

asm/                 MIPS 汇编源码（chuanzhitiao.asm = 传纸条主程序；*_diag = 诊断）
host/                PC 端 UART 驱动（send_chuanzhitiao.py）
sim/                 testbench 与 .hex 测试向量
constr/welog1.xdc    管脚 / 时序约束
scripts/             Vivado 批处理脚本（构建 / 烧录 / 时序报告）
docs/                文档
```

> 参考资料、MARS jar、说明书 PDF 与 Vivado 生成物（`build/`）已在 `.gitignore` 中排除。

## 架构

| 阶段 | 功能 |
|------|------|
| IF   | 取指；PC 选择（顺序 / ID 跳转 / EX 重定向） |
| ID   | 译码、读寄存器堆、`j`/`jal` 目标计算 |
| EX   | ALU 运算、前推 MUX、`beq`/`jr` 分支解析 |
| MEM  | 数据存储器 / MMIO 访问 |
| WB   | 写回寄存器堆 |

### 内存映射

| 地址 | 含义 |
|------|------|
| `0x0000_0000`–    | 数据存储器（片上分布式 RAM） |
| `0x4000_0010` | 七段数码管 `digi[11:0]`（写） |
| `0x4000_0018` | UART TXD（写一字节即发送） |
| `0x4000_001C` | UART RXD（读接收字节） |
| `0x4000_0020` | UART CON：bit2 `tx_done`(idle) / bit3 `rx_done` / bit4 `tx_busy` |

`0x4xxx_xxxx`（`Address[30]`）为外设区，其余为数据存储器。

## 上板：综合、实现、烧录

需在已加载 Vivado 的命令行中执行（本项目用 Vivado 2017.3，目标器件 `xc7a35tfgg484-2`）。

```sh
# 创建工程并跑完综合/实现/生成比特流 -> build/vivado/welog1_mips.runs/impl_1/top.bit
vivado -mode batch -source scripts/build_vivado.tcl

# 通过 JTAG 烧录到开发板
vivado -mode batch -source scripts/program_board.tcl

# 时序报告（Fmax / 各时钟 WNS）
vivado -mode batch -source scripts/report_fmax.tcl
```

IMEM/DMEM 初始化向量来自 `sim/imem_chuanzhitiao.hex` 与 `sim/dmem_chuanzhitiao.hex`
（见 `build_vivado.tcl` 顶部的路径设置）。

## 仿真

使用 iverilog / vvp（本机位于 `D:\iverilog`）：

```sh
iverilog -o sim/_tb.out sim/tb_cpu_basic.v src/*.v
vvp sim/_tb.out
```

`sim/` 下提供多组 testbench：`tb_cpu_basic` / `tb_cpu_forward` / `tb_cpu_loaduse` /
`tb_cpu_branch` / `tb_cpu_mmio`、`tb_forwarding`、`tb_hazard`、`tb_uart`，以及
端到端的 `tb_cpu_chuanzhitiao`。

## 主机驱动：《传纸条》

CPU 复位后等待 PC 经 UART 发送数据集，计算后回传 32 位结果（大端，4 字节），并刷新
七段数码管。

**二进制协议（8N1）**
- PC → 板：字节 `m`、字节 `n`，随后 `m*n` 个网格字节（行主序，每个 0..255）。
- 板 → PC：4 字节结果，MSB 优先。

```sh
pip install pyserial
# 跑内置数据集（自带参考 DP 求解器对拍，逐条 OK/FAIL）
python host/send_chuanzhitiao.py --port COM3
# 跑自定义网格："m n g00 g01 ... "
python host/send_chuanzhitiao.py --port COM3 --grid "3 3 0 3 9 2 8 5 5 7 0"
```

> 在 WELOG1 上 UART 桥接为 FT2232 双串口：一个走 JTAG，另一个为 UART（9600 8N1）。
> 在设备管理器中选择对应的 COM 口。

## 工具链

- **综合/实现/烧录**：Vivado 2017.3（不在 PATH 上，需在 Vivado 命令行中调用脚本）。
- **仿真**：iverilog / vvp / gtkwave。
- **汇编**：MARS（MIPS 汇编器/模拟器）生成机器码 hex。
