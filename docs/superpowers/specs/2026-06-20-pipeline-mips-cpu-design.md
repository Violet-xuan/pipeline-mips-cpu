# 五级流水线 MIPS 处理器 — 设计方案

日期: 2026-06-20
课程: 数字逻辑与处理器基础实验 · 2026夏季学期综合大作业（方案一：流水线 CPU）
目标板: WELOG1 (Xilinx XC7A35T, `xc7a35tfgg484-2`)

---

## 1. 目标与范围

将春季单周期 MIPS 改进为 **5 级流水线**，运行 25 秋"传纸条"汇编任务（DFS + 记忆化），
将结果以 16 进制显示到七段数码管，并计算 CPI 与最高工作频率。

竞争问题处理（按实验 PDF 要求）：
- **完全 forwarding** 解决数据关联。
- **Load-use** 竞争：阻塞 1 周期 + forwarding。
- **分支指令在 EX 阶段判断**，分支发生时取消 ID、IF 两条指令。
- **J 类（j/jal）在 ID 阶段判断**，取消 IF 一条指令。

**关键决定（Option A）**：`jr`/`jalr` 也在 **EX 阶段**解决（复用分支冲刷逻辑，2 周期代价），
使 ID 阶段保持简单——只有立即数目标跳转活在 ID，不需要向 ID 转发寄存器值。

**本 session 产出范围**：先框架 + 核心数据通路（跑通无冒险程序），冒险/转发单元作为后续增量。
UART 纳入总体架构设计，核心跑通后再接线。

> 注：汇编目标程序（传纸条硬件版，去除 syscall、数据预置 RAM、数码管显示）由用户自行改写。
> 本设计冻结 CPU 的 ISA 作为汇编机器码的契约（见 §3）。

---

## 2. 流水线架构

5 级：IF / ID / EX / MEM / WB，4 个流水寄存器：IF/ID、ID/EX、EX/MEM、MEM/WB。
哈佛结构：指令 ROM 与数据地址空间分离。

```
   IF              ID                 EX                MEM               WB
┌───────┐    ┌────────────┐    ┌──────────────┐   ┌────────────┐    ┌─────────┐
│ PC    │    │ Decode     │    │ Forward mux  │   │ MemBus     │    │ WB mux  │
│ IMEM  │ →  │ RegFile RD │ →  │ ALU          │ → │ DMEM/Periph│ →  │ →RegFile│
│ +4    │    │ SignExt    │    │ Branch判断   │   │            │    │         │
│ j目标 │    │ j/jal目标  │    │ jr目标       │   │            │    │         │
└───────┘    └────────────┘    └──────────────┘   └────────────┘    └─────────┘
        IF/ID            ID/EX               EX/MEM            MEM/WB
```

- RegFile **写在前半周期、读在后半周期**（WB→ID 同周期旁路），减少一类转发。
- 分支/jr 在 EX 解析：taken 时冲刷 IF/ID 与 ID/EX（转 NOP），PC←目标。
- j/jal 在 ID 解析：冲刷 IF（IF/ID 转 NOP），PC←目标。

---

## 3. 冻结 ISA（汇编机器码契约）

CPU 兼容标准 MIPS32 编码。支持指令集（PDF 要求 + MARS 伪指令展开所需的超集）：

### R-type (op = `0x00`)
| 指令 | funct | 说明 |
|------|-------|------|
| sll  | 0x00  | rd = rt << shamt |
| srl  | 0x02  | rd = rt >> shamt (逻辑) |
| sra  | 0x03  | rd = rt >> shamt (算术) |
| add  | 0x20  | 有符号加 |
| addu | 0x21  | 无符号加 |
| sub  | 0x22  | 有符号减 |
| subu | 0x23  | 无符号减 |
| and  | 0x24  | |
| or   | 0x25  | |
| xor  | 0x26  | |
| nor  | 0x27  | |
| slt  | 0x2a  | 有符号小于 |
| sltu | 0x2b  | 无符号小于 |
| jr   | 0x08  | PC = rs（EX 解析） |
| jalr | 0x09  | rd = PC+4, PC = rs（EX 解析） |

### mul (op = `0x1c`, funct = `0x02`)
| mul | rd = rs * rt（低 32 位） |

### I-type
| 指令 | op | 说明 |
|------|----|------|
| addi | 0x08 | 立即数有符号加（溢出忽略，按 addiu 实现） |
| addiu| 0x09 | |
| andi | 0x0c | 零扩展 |
| ori  | 0x0d | 零扩展 |
| slti | 0x0a | 有符号 |
| sltiu| 0x0b | 无符号 |
| lui  | 0x0f | rt = imm << 16 |
| lw   | 0x23 | |
| sw   | 0x2b | |
| beq  | 0x04 | |
| bne  | 0x05 | |
| blez | 0x06 | rs <= 0 |
| bgtz | 0x07 | rs > 0 |
| bltz | 0x01, rt=0x00 | rs < 0 |
| bgez | 0x01, rt=0x01 | rs >= 0 |

### J-type
| j   | 0x02 | PC = {PC+4[31:28], imm26, 2'b00}（ID 解析） |
| jal | 0x03 | $31 = PC+4, 同上目标（ID 解析） |

`nop` = `0x00000000` (sll $0,$0,0)。
新增 `bne, ori, slti, bgez` 是因为 MARS 把 `bge/blt/ble/bgt/move/li/la` 展开到这些指令。

---

## 4. 存储与外设

### 地址映射
| 地址范围（字节） | 功能 |
|------------------|------|
| 0x00000000 ~ 0x000007FF | 数据存储器 RAM（2KB = 512 字） |
| 0x40000010 | 七段数码管寄存器 `digi[11:0]` |
| 0x40000018 | UART_TXD（选做，低 8 bit，写触发发送） |
| 0x4000001C | UART_RXD（选做，低 8 bit） |
| 0x40000020 | UART_CON（选做，bit2 发送完成 / bit3 接收完成 / bit4 发送忙） |

- **IMEM**：ROM，组合读，`case(PC[?:2])`，粘贴 MARS 机器码（沿用单周期参考流程）。
- **DMEM**：512 字 RAM，同步写、异步读，`reset` 时预置测试数据（PDF 推荐方式）。
  `$sp` 初始化指向 RAM 高端。`sbrk` 分配区由汇编改写为固定地址。
- **MemBus**（MEM 阶段地址译码器/"外设控制器"）：`addr[30]`/高位判定 `0x4xxxxxxx` 走外设，否则走 DMEM。
- **digi 寄存器语义**（PDF 第 11–12 页固定）：
  `digi[11:8]` = AN3..AN0（位选，高电平选中），`digi[7]` = dp，`digi[6:0]` = g..a（高电平点亮）。
  软件方式译码 + 软件延时扫描（每位 ~1ms 轮显）。**不使用硬件译码器。**

### 约束：2KB 数据 RAM
传纸条改写版的 grid + 记忆表 + 栈必须放进 512 字。小规模用例（m,n ≤ ~5）可容纳，
布置固定地址（替代 sbrk）时需留意。

---

## 5. 模块划分（模块化，便于调试）

复用/改写自单周期参考：
- `ALU.v`（直接复用）
- `ALUControl.v`（扩展 mul 已有，按需补充）
- `RegisterFile.v`（改为写前半周期 / 读后半周期）
- `Control.v`（扩展全部 ISA 的控制信号）
- `InstructionMemory.v`（ROM）
- `DataMemory.v`（512 字 RAM + 预置数据）

新增：
- `PipelineCPU.v`：数据通路 + 4 个流水寄存器（按阶段分段、注释清晰）
- `ForwardingUnit.v`：EX/MEM→EX、MEM/WB→EX 旁路（ForwardA/ForwardB）
- `HazardUnit.v`：load-use 阻塞（冻结 PC、IF/ID，插入气泡）+ 分支/jr/j 冲刷
- `MemBus.v`：外设地址译码
- `SevenSeg`（digi 寄存器，含在 MemBus 或顶层）
- `UART.v`：收发外设（先设计、后接线）
- `top.v`：FPGA 顶层（分频/PLL、复位、数码管与 UART 管脚映射）
- 各阶段 testbench：`tb_*.v`

---

## 6. FPGA 管脚约束（WELOG1，来自《WELOG1 说明书》）

芯片：`xc7a35tfgg484-2`。时钟 100MHz → **R4**（设计很可能跑不到 100MHz，需分频/PLL 到接近但不超过最高工作频率）。

### 时钟
| 信号 | 管脚 |
|------|------|
| clk (100MHz) | R4 |

### 七段数码管（共阴极，段/位选均高电平有效）
| digi 位 | 功能 | 板上名 | 管脚 |
|---------|------|--------|------|
| digi[0] | a    | SEGA | N2 |
| digi[1] | b    | SEGB | P5 |
| digi[2] | c    | SEGC | V5 |
| digi[3] | d    | SEGD | U5 |
| digi[4] | e    | SEGE | T5 |
| digi[5] | f    | SEGF | P1 |
| digi[6] | g    | SEGG | W4 |
| digi[7] | dp   | SEGDP| V3 |
| digi[8] | AN0  | SEL1 | M2 |
| digi[9] | AN1  | SEL2 | P2 |
| digi[10]| AN2  | SEL3 | R1 |
| digi[11]| AN3  | SEL4 | Y3 |

### UART（选做）
| 信号 | 板上名 | 管脚 |
|------|--------|------|
| uart_txd (FPGA→PC) | FPGA_TXD | A20 |
| uart_rxd (PC→FPGA) | FPGA_RXD | B20 |

### 其他可用资源（备用，按需）
- 5 按键（按下高电平）：KEY1 B22, KEY2 B21, KEY3 K22, KEY4 K21, KEY5 J22（KEY3-5 带防抖）
- 8 拨码（上拨高电平）：GPIO1 H2, GPIO2 J2, GPIO3 J1, GPIO4 K2, GPIO5 K1, GPIO6 L3, GPIO7 L1, GPIO8 M1
- 8 LED（高电平亮）：V2 W1 W2 Y1 Y2 AA1 AB1 AB2

> reset 建议用某个按键（如 KEY1=B22，按下高电平 → 直接作 active-high 复位）。

---

## 7. 构建顺序与验证标准（本 session 核心优先）

1. `PipelineCPU.v` 骨架 + 全部流水寄存器 + 扩展 `Control`/`ALUControl`
   → 跑通**无依赖**程序。**验证**：无关联测试程序仿真寄存器结果正确。
2. `ForwardingUnit.v` → 背靠背 ALU 依赖。**验证**：连续依赖 add 测试。
3. `HazardUnit.v`（load-use 阻塞 + 分支/跳转冲刷）。**验证**：load-use 测试 + taken 分支测试。
4. `MemBus` + `digi` 七段寄存器 + `top.v`。**验证**：写 0x40000010 后 digi 输出正确；上板。
5. （后续）`UART.v` 接线 → 串口收发。
6. （后续）传纸条硬件版机器码导入，跑通完整任务；统计 C（周期数），结合 MARS 指令数 N 算 CPI。

每步独立可测，通过后再进入下一步。

---

## 8. 性能分析（报告需要）

- **CPI** = C / N：N 来自 MARS Instruction Counter，C 来自 Verilog 仿真完成算法的时钟周期数。
- **最高工作频率**：以 Vivado implement 时序报告为准。
- **资源对比**：流水线 vs 单周期的 LUT/寄存器消耗（报告项，非主要评分）。
