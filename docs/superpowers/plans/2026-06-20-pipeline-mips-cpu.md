# 五级流水线 MIPS 处理器 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现一个可综合的 5 级流水线 MIPS 处理器，含完全 forwarding、load-use 阻塞、分支/跳转冲刷，并能把结果显示到 WELOG1 七段数码管。

**Architecture:** IF/ID/EX/MEM/WB 五级；控制字随流水寄存器逐级传递；EX 阶段解析 beq/bne/blez/bgtz/bltz/bgez 及 jr/jalr（冲刷 IF/ID+ID/EX），ID 阶段解析 j/jal（冲刷 IF/ID）；ForwardingUnit 做 EX/MEM→EX、MEM/WB→EX 旁路；RegFile 负沿写、正沿后读以支持 WB→ID 同周期。

**Tech Stack:** Verilog-2001；仿真 Icarus Verilog (`iverilog`/`vvp`)；综合 Vivado (XC7A35T `xc7a35tfgg484-2`)。IMEM/DMEM 用 `$readmemh` 从 `.hex` 初始化（仿真与 Xilinx 综合均支持）。

**约定**
- reset 高电平有效（沿用单周期参考）。
- 32 个寄存器，$0 恒为 0。
- 字地址：IMEM 用 `PC[31:2]`，DMEM 用 `addr[10:2]`（512 字）。
- 测试用 `iverilog` 编译，`-D` 传入程序 hex 路径宏；testbench 自检后打印 `PASS`/`FAIL` 并 `$finish`。
- 设计文档：`docs/superpowers/specs/2026-06-20-pipeline-mips-cpu-design.md`（ISA、地址映射、管脚均以该文档为准）。

**控制字定义（Control 输出，逐级传递）**
| 信号 | 位宽 | 含义 |
|------|------|------|
| RegWrite | 1 | 写回使能 |
| MemRead | 1 | lw |
| MemWrite | 1 | sw |
| MemtoReg | 2 | 00=ALU 01=MEM 10=PC+4(jal/jalr) |
| RegDst | 2 | 00=rt 01=rd 10=$31 |
| ALUSrc1 | 1 | 1=shamt(零扩展) 否则 rsv |
| ALUSrc2 | 1 | 1=立即数/lui 否则 rtv |
| ExtOp | 1 | 1=符号扩展 |
| LuOp | 1 | 1=lui(imm<<16) |
| ALUOp | 4 | 见 ALUControl |
| isBranch | 1 | 条件分支(EX 解析) |
| branchType | 3 | 000beq 001bne 010blez 011bgtz 100bltz 101bgez |
| isJump | 1 | j/jal(ID 解析) |
| isJr | 1 | jr/jalr(EX 解析，无条件) |

ALUOp[2:0] 编码（沿用并扩展单周期参考）：000=ADD，001=SUB，010=R型(查 funct)，100=AND，101=SLT，110=MUL，011=OR(用于 ori)。ALUOp[3]=立即数符号位（参考用法，slt/sltu 区分）。

---

## File Structure

```
src/
  ALU.v               # 复用参考（in1,in2,ALUCtl,Sign -> out,zero）
  ALUControl.v        # 复用参考，补 OR(ori) 通路
  Control.v           # 重写：扩展 ISA 的控制字
  RegisterFile.v      # 改：负沿写（WB->ID 同周期）
  InstructionMemory.v # ROM，$readmemh 初始化
  DataMemory.v        # 512 字 RAM，$readmemh 初始化
  ForwardingUnit.v    # EX 旁路选择
  HazardUnit.v        # load-use 阻塞 + 冲刷控制
  PipelineCPU.v       # 数据通路 + 4 个流水寄存器
  MemBus.v            # 外设地址译码 + digi 寄存器
  top.v               # FPGA 顶层（分频、复位、管脚）
constr/
  welog1.xdc          # 管脚约束
sim/
  tb_forwarding.v     # ForwardingUnit 单元测试
  tb_hazard.v         # HazardUnit 单元测试
  tb_cpu_basic.v      # 无冒险程序集成测试
  tb_cpu_forward.v    # 依赖链转发测试
  tb_cpu_loaduse.v    # load-use 测试
  tb_cpu_branch.v     # 分支/跳转测试
  tb_cpu_mmio.v       # sw 写 digi 测试
  prog_*.hex          # 各测试程序机器码
  data_zero.hex       # 全零数据（默认）
```

---

## Phase 0 — 脚手架与复用模块

### Task 0.1: 建目录并复用 ALU / ALUControl

**Files:**
- Create: `src/ALU.v`, `src/ALUControl.v`

- [ ] **Step 1: 复制 ALU.v**

把参考文件 `2026夏流水线CPU参考资料/2024春_单周期处理器大作业_参考答案_20250421/single-cycle/ALU.v` 原样复制到 `src/ALU.v`（接口 `in1,in2,ALUCtl,Sign -> out,zero`，已支持 and/or/add/sub/slt/nor/xor/sll/srl/sra/mul）。

- [ ] **Step 2: 复制并扩展 ALUControl.v**

复制参考 `ALUControl.v` 到 `src/ALUControl.v`，在设置 ALUCtl 的 case 中增加 OR 通路（供 ori 用）：

```verilog
	always @(*)
		case (ALUOp[2:0])
			3'b000: ALUCtl <= aluADD;
			3'b001: ALUCtl <= aluSUB;
			3'b100: ALUCtl <= aluAND;
			3'b101: ALUCtl <= aluSLT;
			3'b010: ALUCtl <= aluFunct;
			3'b110: ALUCtl <= aluMUL;
			3'b011: ALUCtl <= aluOR;   // ori
			default: ALUCtl <= aluADD;
		endcase
```

- [ ] **Step 3: 语法检查**

Run: `iverilog -g2012 -o /tmp/alu.out src/ALU.v src/ALUControl.v`
Expected: 无错误（无顶层模块的链接警告可忽略）。

- [ ] **Step 4: Commit**

```bash
git add src/ALU.v src/ALUControl.v
git commit -m "feat: add ALU and ALUControl (reuse single-cycle, add ori path)"
```

### Task 0.2: RegisterFile（负沿写）

**Files:**
- Create: `src/RegisterFile.v`

- [ ] **Step 1: 写 RegisterFile.v**

基于参考，但写操作改到 **clk 负沿**，使 WB（负沿写）与 ID（正沿后读）同周期生效，免去一类转发。

```verilog
module RegisterFile(
	input  reset,
	input  clk,
	input  RegWrite,
	input  [4:0]  Read_register1,
	input  [4:0]  Read_register2,
	input  [4:0]  Write_register,
	input  [31:0] Write_data,
	output [31:0] Read_data1,
	output [31:0] Read_data2
);
	reg [31:0] RF_data[31:1];

	assign Read_data1 = (Read_register1 == 5'd0)? 32'd0 : RF_data[Read_register1];
	assign Read_data2 = (Read_register2 == 5'd0)? 32'd0 : RF_data[Read_register2];

	integer i;
	always @(negedge clk or posedge reset)
		if (reset)
			for (i = 1; i < 32; i = i + 1) RF_data[i] <= 32'd0;
		else if (RegWrite && (Write_register != 5'd0))
			RF_data[Write_register] <= Write_data;
endmodule
```

- [ ] **Step 2: 语法检查**

Run: `iverilog -g2012 -o /tmp/rf.out src/RegisterFile.v`
Expected: 无错误。

- [ ] **Step 3: Commit**

```bash
git add src/RegisterFile.v
git commit -m "feat: add RegisterFile with negedge write for same-cycle WB->ID"
```

### Task 0.3: 指令/数据存储器（$readmemh）

**Files:**
- Create: `src/InstructionMemory.v`, `src/DataMemory.v`, `sim/data_zero.hex`

- [ ] **Step 1: 写 InstructionMemory.v**

```verilog
module InstructionMemory(
	input  [31:0] Address,
	output [31:0] Instruction
);
`ifndef IMEM_FILE
 `define IMEM_FILE "sim/prog_basic.hex"
`endif
	reg [31:0] rom [0:1023];          // 1024 条指令空间
	initial $readmemh(`IMEM_FILE, rom);
	assign Instruction = rom[Address[31:2]];
endmodule
```

- [ ] **Step 2: 写 DataMemory.v**

512 字 RAM，异步读、同步写，reset 时用 `$readmemh` 预置：

```verilog
module DataMemory(
	input  reset,
	input  clk,
	input  MemRead,
	input  MemWrite,
	input  [31:0] Address,
	input  [31:0] Write_data,
	output [31:0] Read_data
);
`ifndef DMEM_FILE
 `define DMEM_FILE "sim/data_zero.hex"
`endif
	reg [31:0] RAM [0:511];           // 2KB
	initial $readmemh(`DMEM_FILE, RAM);
	assign Read_data = MemRead ? RAM[Address[10:2]] : 32'd0;
	always @(posedge clk)
		if (MemWrite) RAM[Address[10:2]] <= Write_data;
endmodule
```

> 注：DMEM 预置走 `$readmemh` 的 `initial`（综合时初始化 BRAM），不再依赖 reset 写循环——这样掉电重载即恢复测试数据，符合"现场改数据只换 hex"。

- [ ] **Step 3: 建默认数据 hex**

`sim/data_zero.hex`（一行注释即可，未列地址默认 x；为安全写前几行 0）：

```
00000000
00000000
00000000
00000000
```

- [ ] **Step 4: 语法检查**

Run: `iverilog -g2012 -o /tmp/mem.out src/InstructionMemory.v src/DataMemory.v`
Expected: 无错误。

- [ ] **Step 5: Commit**

```bash
git add src/InstructionMemory.v src/DataMemory.v sim/data_zero.hex
git commit -m "feat: add IMEM ROM and 512-word DMEM with $readmemh init"
```

---

## Phase 1 — 控制单元

### Task 1.1: Control.v（扩展 ISA）

**Files:**
- Create: `src/Control.v`

- [ ] **Step 1: 写 Control.v**

```verilog
module Control(
	input  [5:0] OpCode,
	input  [5:0] Funct,
	input  [4:0] Rt,            // 用于区分 bltz/bgez
	output reg RegWrite,
	output reg MemRead,
	output reg MemWrite,
	output reg [1:0] MemtoReg,
	output reg [1:0] RegDst,
	output reg ALUSrc1,
	output reg ALUSrc2,
	output reg ExtOp,
	output reg LuOp,
	output reg [3:0] ALUOp,
	output reg isBranch,
	output reg [2:0] branchType,
	output reg isJump,
	output reg isJr
);
	// opcodes
	localparam R=6'h00, MUL=6'h1c, ADDI=6'h08, ADDIU=6'h09, ANDI=6'h0c,
	           ORI=6'h0d, SLTI=6'h0a, SLTIU=6'h0b, LUI=6'h0f, LW=6'h23,
	           SW=6'h2b, BEQ=6'h04, BNE=6'h05, BLEZ=6'h06, BGTZ=6'h07,
	           BZ=6'h01, J=6'h02, JAL=6'h03;
	// R-type funct
	localparam F_SLL=6'h00,F_SRL=6'h02,F_SRA=6'h03,F_JR=6'h08,F_JALR=6'h09;

	always @(*) begin
		// defaults (nop-safe)
		RegWrite=0; MemRead=0; MemWrite=0; MemtoReg=2'b00; RegDst=2'b00;
		ALUSrc1=0; ALUSrc2=0; ExtOp=1; LuOp=0; ALUOp=4'b0000;
		isBranch=0; branchType=3'b000; isJump=0; isJr=0;
		case (OpCode)
		R: begin
			ALUOp=4'b0010;            // R-type, 查 funct
			case (Funct)
			F_JR:   begin isJr=1; end
			F_JALR: begin isJr=1; RegWrite=1; RegDst=2'b01; MemtoReg=2'b10; end
			F_SLL,F_SRL,F_SRA: begin RegWrite=1; RegDst=2'b01; ALUSrc1=1; end
			default: begin RegWrite=1; RegDst=2'b01; end // add/sub/and/or/...
			endcase
		end
		MUL:   begin RegWrite=1; RegDst=2'b01; ALUOp=4'b0110; end
		ADDI:  begin RegWrite=1; ALUSrc2=1; ALUOp=4'b0000; end
		ADDIU: begin RegWrite=1; ALUSrc2=1; ALUOp=4'b0000; end
		ANDI:  begin RegWrite=1; ALUSrc2=1; ExtOp=0; ALUOp=4'b0100; end
		ORI:   begin RegWrite=1; ALUSrc2=1; ExtOp=0; ALUOp=4'b0011; end
		SLTI:  begin RegWrite=1; ALUSrc2=1; ALUOp=4'b1101; end // sign slt
		SLTIU: begin RegWrite=1; ALUSrc2=1; ALUOp=4'b0101; end // unsigned slt
		LUI:   begin RegWrite=1; ALUSrc2=1; LuOp=1; ALUOp=4'b0000; end
		LW:    begin RegWrite=1; MemRead=1; MemtoReg=2'b01; ALUSrc2=1; ALUOp=4'b0000; end
		SW:    begin MemWrite=1; ALUSrc2=1; ALUOp=4'b0000; end
		BEQ:   begin isBranch=1; branchType=3'b000; ALUOp=4'b0001; end
		BNE:   begin isBranch=1; branchType=3'b001; ALUOp=4'b0001; end
		BLEZ:  begin isBranch=1; branchType=3'b010; end
		BGTZ:  begin isBranch=1; branchType=3'b011; end
		BZ:    begin isBranch=1; branchType=(Rt==5'd0)?3'b100:3'b101; end // bltz/bgez
		J:     begin isJump=1; end
		JAL:   begin isJump=1; RegWrite=1; RegDst=2'b10; MemtoReg=2'b10; end
		default: ; // nop
		endcase
	end
endmodule
```

> 说明：SLTI 用 ALUOp=4'b1101（[3]=1 表示有符号），SLTIU 用 4'b0101（无符号），与参考 ALUControl 的 `Sign=~ALUOp[3]` 一致。

- [ ] **Step 2: 语法检查**

Run: `iverilog -g2012 -o /tmp/ctrl.out src/Control.v`
Expected: 无错误。

- [ ] **Step 3: Commit**

```bash
git add src/Control.v
git commit -m "feat: add Control unit covering full pipeline ISA"
```

---

## Phase 2 — 数据通路骨架（无冒险处理）

> 本阶段先把流水线搭起来，假设测试程序指令间**无数据/控制冒险**（用 nop 手动隔开），验证取指→写回全程正确。

### Task 2.1: PipelineCPU.v 骨架

**Files:**
- Create: `src/PipelineCPU.v`

- [ ] **Step 1: 写 PipelineCPU.v**

```verilog
module PipelineCPU(
	input  clk,
	input  reset,
	// 外部存储/外设总线（MEM 阶段引出，供 MemBus/外设接管）
	output        MemRead,
	output        MemWrite,
	output [31:0] MemAddr,
	output [31:0] MemWriteData,
	input  [31:0] MemReadData
);
	// ---------- 冒险/转发控制（Phase3/4 接入；本阶段恒不阻塞、不旁路、不冲刷） ----------
	wire        stall      = 1'b0;
	wire        flush_IFID = 1'b0;
	wire        flush_IDEX = 1'b0;
	wire [1:0]  ForwardA   = 2'b00;
	wire [1:0]  ForwardB   = 2'b00;
	wire        redirect_EX;     // 由 EX 分支/jr 给出
	wire [31:0] target_EX;
	wire        redirect_ID;     // 由 ID 的 j/jal 给出
	wire [31:0] target_ID;

	// ================= IF =================
	reg  [31:0] PC;
	wire [31:0] PC_plus4 = PC + 32'd4;
	wire [31:0] PC_next  = redirect_EX ? target_EX :
	                       redirect_ID ? target_ID : PC_plus4;
	always @(posedge clk or posedge reset)
		if (reset) PC <= 32'd0;
		else if (!stall) PC <= PC_next;

	wire [31:0] IF_inst;
	InstructionMemory imem(.Address(PC), .Instruction(IF_inst));

	// ---------- IF/ID ----------
	reg [31:0] IFID_pc4, IFID_inst;
	always @(posedge clk or posedge reset)
		if (reset) begin IFID_pc4<=0; IFID_inst<=0; end
		else if (!stall) begin
			if (flush_IFID) begin IFID_pc4<=0; IFID_inst<=32'h00000000; end
			else begin IFID_pc4<=PC_plus4; IFID_inst<=IF_inst; end
		end

	// ================= ID =================
	wire [5:0]  ID_op   = IFID_inst[31:26];
	wire [5:0]  ID_funct= IFID_inst[5:0];
	wire [4:0]  ID_rs   = IFID_inst[25:21];
	wire [4:0]  ID_rt   = IFID_inst[20:16];
	wire [4:0]  ID_rd   = IFID_inst[15:11];
	wire [4:0]  ID_shamt= IFID_inst[10:6];
	wire [15:0] ID_imm  = IFID_inst[15:0];

	wire c_RegWrite,c_MemRead,c_MemWrite,c_ALUSrc1,c_ALUSrc2,c_ExtOp,c_LuOp,c_isBranch,c_isJump,c_isJr;
	wire [1:0] c_MemtoReg,c_RegDst;
	wire [3:0] c_ALUOp;
	wire [2:0] c_branchType;
	Control ctrl(.OpCode(ID_op),.Funct(ID_funct),.Rt(ID_rt),
		.RegWrite(c_RegWrite),.MemRead(c_MemRead),.MemWrite(c_MemWrite),
		.MemtoReg(c_MemtoReg),.RegDst(c_RegDst),.ALUSrc1(c_ALUSrc1),.ALUSrc2(c_ALUSrc2),
		.ExtOp(c_ExtOp),.LuOp(c_LuOp),.ALUOp(c_ALUOp),.isBranch(c_isBranch),
		.branchType(c_branchType),.isJump(c_isJump),.isJr(c_isJr));

	// 写回口（WB 段产生，见下）
	wire        wb_RegWrite;
	wire [4:0]  wb_waddr;
	wire [31:0] wb_wdata;

	wire [31:0] ID_rdata1, ID_rdata2;
	RegisterFile rf(.reset(reset),.clk(clk),.RegWrite(wb_RegWrite),
		.Read_register1(ID_rs),.Read_register2(ID_rt),.Write_register(wb_waddr),
		.Write_data(wb_wdata),.Read_data1(ID_rdata1),.Read_data2(ID_rdata2));

	wire [31:0] ID_ext = {c_ExtOp?{16{ID_imm[15]}}:16'h0, ID_imm};
	wire [31:0] ID_imm32 = c_LuOp ? {ID_imm,16'h0} : ID_ext;

	// j/jal 目标（ID 解析）
	wire [31:0] ID_jtarget = {IFID_pc4[31:28], IFID_inst[25:0], 2'b00};
	assign redirect_ID = c_isJump;
	assign target_ID   = ID_jtarget;

	// ---------- ID/EX ----------
	reg        x_RegWrite,x_MemRead,x_MemWrite,x_ALUSrc1,x_ALUSrc2,x_isBranch,x_isJr;
	reg [1:0]  x_MemtoReg,x_RegDst;
	reg [3:0]  x_ALUOp;
	reg [2:0]  x_branchType;
	reg [31:0] x_pc4,x_rdata1,x_rdata2,x_imm32;
	reg [4:0]  x_rs,x_rt,x_rd,x_shamt;
	reg [5:0]  x_funct;
	// bubble = stall(load-use) 或 flush_IDEX(分支冲刷)
	wire insert_bubble = stall | flush_IDEX;
	always @(posedge clk or posedge reset)
		if (reset) begin
			{x_RegWrite,x_MemRead,x_MemWrite,x_ALUSrc1,x_ALUSrc2,x_isBranch,x_isJr}<=0;
			{x_MemtoReg,x_RegDst,x_ALUOp,x_branchType}<=0;
			{x_pc4,x_rdata1,x_rdata2,x_imm32}<=0; {x_rs,x_rt,x_rd,x_shamt,x_funct}<=0;
		end else begin
			if (insert_bubble) begin
				x_RegWrite<=0; x_MemRead<=0; x_MemWrite<=0; x_isBranch<=0; x_isJr<=0;
				x_MemtoReg<=0; x_RegDst<=0; x_ALUOp<=0; x_branchType<=0;
				// 数据字段无所谓，置 0
				x_pc4<=0; x_rdata1<=0; x_rdata2<=0; x_imm32<=0; x_rs<=0; x_rt<=0; x_rd<=0; x_shamt<=0; x_funct<=0;
			end else begin
				x_RegWrite<=c_RegWrite; x_MemRead<=c_MemRead; x_MemWrite<=c_MemWrite;
				x_ALUSrc1<=c_ALUSrc1; x_ALUSrc2<=c_ALUSrc2; x_isBranch<=c_isBranch; x_isJr<=c_isJr;
				x_MemtoReg<=c_MemtoReg; x_RegDst<=c_RegDst; x_ALUOp<=c_ALUOp; x_branchType<=c_branchType;
				x_pc4<=IFID_pc4; x_rdata1<=ID_rdata1; x_rdata2<=ID_rdata2; x_imm32<=ID_imm32;
				x_rs<=ID_rs; x_rt<=ID_rt; x_rd<=ID_rd; x_shamt<=ID_shamt; x_funct<=ID_funct;
			end
		end

	// ================= EX =================
	// 前递后的操作数（Phase3 起 ForwardA/B 非 0）
	wire [31:0] ex_fwdA = (ForwardA==2'b10)? m_alu :
	                      (ForwardA==2'b01)? wb_wdata : x_rdata1;
	wire [31:0] ex_fwdB = (ForwardB==2'b10)? m_alu :
	                      (ForwardB==2'b01)? wb_wdata : x_rdata2;

	wire [31:0] alu_in1 = x_ALUSrc1 ? {27'd0, x_shamt} : ex_fwdA;
	wire [31:0] alu_in2 = x_ALUSrc2 ? x_imm32 : ex_fwdB;

	wire [4:0]  ALUCtl; wire Sign;
	ALUControl aluc(.ALUOp(x_ALUOp),.Funct(x_funct),.ALUCtl(ALUCtl),.Sign(Sign));
	wire [31:0] EX_alu; wire EX_zero;
	ALU alu(.in1(alu_in1),.in2(alu_in2),.ALUCtl(ALUCtl),.Sign(Sign),.out(EX_alu),.zero(EX_zero));

	// 分支判断（用前递后的 rs/rt）
	wire signed [31:0] sA = ex_fwdA;
	reg branch_cond;
	always @(*) case (x_branchType)
		3'b000: branch_cond = (ex_fwdA==ex_fwdB);     // beq
		3'b001: branch_cond = (ex_fwdA!=ex_fwdB);     // bne
		3'b010: branch_cond = (sA<=0);                // blez
		3'b011: branch_cond = (sA>0);                 // bgtz
		3'b100: branch_cond = (sA<0);                 // bltz
		3'b101: branch_cond = (sA>=0);                // bgez
		default: branch_cond = 1'b0;
	endcase
	wire branch_taken = x_isBranch & branch_cond;
	wire [31:0] EX_btarget = x_pc4 + {x_imm32[29:0], 2'b00};
	assign redirect_EX = branch_taken | x_isJr;
	assign target_EX   = x_isJr ? ex_fwdA : EX_btarget;   // jr/jalr 用前递后的 rs

	wire [4:0] EX_waddr = (x_RegDst==2'b01)? x_rd : (x_RegDst==2'b10)? 5'd31 : x_rt;

	// ---------- EX/MEM ----------
	reg        m_RegWrite,m_MemRead,m_MemWrite; reg [1:0] m_MemtoReg;
	reg [31:0] m_alu,m_wdata,m_pc4; reg [4:0] m_waddr;
	always @(posedge clk or posedge reset)
		if (reset) begin
			{m_RegWrite,m_MemRead,m_MemWrite,m_MemtoReg}<=0;
			{m_alu,m_wdata,m_pc4}<=0; m_waddr<=0;
		end else begin
			m_RegWrite<=x_RegWrite; m_MemRead<=x_MemRead; m_MemWrite<=x_MemWrite; m_MemtoReg<=x_MemtoReg;
			m_alu<=EX_alu; m_wdata<=ex_fwdB; m_pc4<=x_pc4; m_waddr<=EX_waddr;
		end

	// ================= MEM =================
	assign MemRead = m_MemRead; assign MemWrite = m_MemWrite;
	assign MemAddr = m_alu;      assign MemWriteData = m_wdata;
	wire [31:0] MEM_rdata = MemReadData;

	// ---------- MEM/WB ----------
	reg        w_RegWrite; reg [1:0] w_MemtoReg;
	reg [31:0] w_alu,w_mem,w_pc4; reg [4:0] w_waddr;
	always @(posedge clk or posedge reset)
		if (reset) begin {w_RegWrite,w_MemtoReg}<=0; {w_alu,w_mem,w_pc4}<=0; w_waddr<=0; end
		else begin
			w_RegWrite<=m_RegWrite; w_MemtoReg<=m_MemtoReg;
			w_alu<=m_alu; w_mem<=MEM_rdata; w_pc4<=m_pc4; w_waddr<=m_waddr;
		end

	// ================= WB =================
	assign wb_wdata = (w_MemtoReg==2'b01)? w_mem : (w_MemtoReg==2'b10)? w_pc4 : w_alu;
	assign wb_waddr = w_waddr;
	assign wb_RegWrite = w_RegWrite;
endmodule
```

- [ ] **Step 2: 语法/链接检查**

Run: `iverilog -g2012 -o /tmp/cpu.out src/PipelineCPU.v src/Control.v src/ALU.v src/ALUControl.v src/RegisterFile.v src/InstructionMemory.v`
Expected: 无错误（顶层无端口绑定的警告可忽略）。

- [ ] **Step 3: Commit**

```bash
git add src/PipelineCPU.v
git commit -m "feat: pipeline datapath skeleton (no hazard handling yet)"
```

### Task 2.2: 无冒险集成测试

**Files:**
- Create: `sim/prog_basic.hex`, `sim/tb_cpu_basic.v`

测试程序（指令间用 nop 隔开依赖，验证基础执行）：
```
# 汇编（地址0起）：
# addiu $1,$0,5      ; $1=5
# nop nop nop
# addiu $2,$0,7      ; $2=7
# nop nop nop
# add   $3,$1,$2     ; $3=12  (依赖已被nop隔开)
# nop nop nop
# sw    $3,0($0)     ; MEM[0]=12
# nop nop nop
# (loop) beq $0,$0,self  -> 用 j self 简单点；这里用 addiu $4,$0,1 收尾
```

- [ ] **Step 1: 写 prog_basic.hex**

机器码（每行一条，hex）：
```
24010005
00000000
00000000
00000000
24020007
00000000
00000000
00000000
00221820
00000000
00000000
00000000
ac030000
00000000
00000000
00000000
24040001
```

- [ ] **Step 2: 写 testbench（含简易 DMEM 接到 CPU 总线）**

```verilog
`timescale 1ns/1ps
module tb_cpu_basic;
	reg clk=0, reset=1;
	wire MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	DataMemory dmem(.reset(reset),.clk(clk),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.Write_data(MemWriteData),.Read_data(MemReadData));
	always #5 clk=~clk;
	integer errors=0;
	initial begin
		#12 reset=0;
		#300;  // 跑足够周期
		// 检查 DMEM[0]==12
		if (dmem.RAM[0]!==32'd12) begin errors=errors+1; $display("FAIL: MEM[0]=%0d exp 12",dmem.RAM[0]); end
		// 检查寄存器
		if (cpu.rf.RF_data[1]!==32'd5)  begin errors=errors+1; $display("FAIL: $1=%0d exp 5",cpu.rf.RF_data[1]); end
		if (cpu.rf.RF_data[2]!==32'd7)  begin errors=errors+1; $display("FAIL: $2=%0d exp 7",cpu.rf.RF_data[2]); end
		if (cpu.rf.RF_data[3]!==32'd12) begin errors=errors+1; $display("FAIL: $3=%0d exp 12",cpu.rf.RF_data[3]); end
		if (errors==0) $display("PASS tb_cpu_basic");
		$finish;
	end
endmodule
```

- [ ] **Step 3: 运行（预期 PASS）**

Run:
```bash
iverilog -g2012 -DIMEM_FILE='"sim/prog_basic.hex"' -o /tmp/t_basic.out \
  sim/tb_cpu_basic.v src/PipelineCPU.v src/Control.v src/ALU.v src/ALUControl.v \
  src/RegisterFile.v src/InstructionMemory.v src/DataMemory.v
vvp /tmp/t_basic.out
```
Expected: 打印 `PASS tb_cpu_basic`，无 FAIL。

- [ ] **Step 4: Commit**

```bash
git add sim/prog_basic.hex sim/tb_cpu_basic.v
git commit -m "test: hazard-free integration test passes on pipeline skeleton"
```

---

## Phase 3 — 转发单元

### Task 3.1: ForwardingUnit.v + 单元测试

**Files:**
- Create: `src/ForwardingUnit.v`, `sim/tb_forwarding.v`

- [ ] **Step 1: 写单元测试（先失败）**

```verilog
`timescale 1ns/1ps
module tb_forwarding;
	reg exmem_rw, memwb_rw; reg [4:0] exmem_rd, memwb_rd, idex_rs, idex_rt;
	wire [1:0] fa, fb; integer errors=0;
	ForwardingUnit u(.EXMEM_RegWrite(exmem_rw),.EXMEM_rd(exmem_rd),
		.MEMWB_RegWrite(memwb_rw),.MEMWB_rd(memwb_rd),
		.IDEX_rs(idex_rs),.IDEX_rt(idex_rt),.ForwardA(fa),.ForwardB(fb));
	task chk(input [1:0] ga,gb); begin
		if(fa!==ga||fb!==gb) begin errors=errors+1;
			$display("FAIL fa=%b fb=%b exp %b %b",fa,fb,ga,gb); end end
	endtask
	initial begin
		// EX/MEM 旁路优先
		exmem_rw=1; exmem_rd=5'd3; memwb_rw=0; memwb_rd=0; idex_rs=5'd3; idex_rt=5'd9; #1 chk(2'b10,2'b00);
		// MEM/WB 旁路
		exmem_rw=0; exmem_rd=0; memwb_rw=1; memwb_rd=5'd9; idex_rs=5'd2; idex_rt=5'd9; #1 chk(2'b00,2'b01);
		// $0 不旁路
		exmem_rw=1; exmem_rd=5'd0; memwb_rw=0; idex_rs=5'd0; idex_rt=5'd0; #1 chk(2'b00,2'b00);
		// EX/MEM 优先于 MEM/WB（同寄存器）
		exmem_rw=1; exmem_rd=5'd5; memwb_rw=1; memwb_rd=5'd5; idex_rs=5'd5; idex_rt=5'd1; #1 chk(2'b10,2'b00);
		if(errors==0) $display("PASS tb_forwarding"); $finish;
	end
endmodule
```

- [ ] **Step 2: 运行确认失败**

Run: `iverilog -g2012 -o /tmp/tf.out sim/tb_forwarding.v src/ForwardingUnit.v`
Expected: 编译失败（ForwardingUnit 未定义）。

- [ ] **Step 3: 写 ForwardingUnit.v**

```verilog
module ForwardingUnit(
	input        EXMEM_RegWrite,
	input  [4:0] EXMEM_rd,
	input        MEMWB_RegWrite,
	input  [4:0] MEMWB_rd,
	input  [4:0] IDEX_rs,
	input  [4:0] IDEX_rt,
	output [1:0] ForwardA,
	output [1:0] ForwardB
);
	assign ForwardA =
		(EXMEM_RegWrite && EXMEM_rd!=5'd0 && EXMEM_rd==IDEX_rs)? 2'b10 :
		(MEMWB_RegWrite && MEMWB_rd!=5'd0 && MEMWB_rd==IDEX_rs)? 2'b01 : 2'b00;
	assign ForwardB =
		(EXMEM_RegWrite && EXMEM_rd!=5'd0 && EXMEM_rd==IDEX_rt)? 2'b10 :
		(MEMWB_RegWrite && MEMWB_rd!=5'd0 && MEMWB_rd==IDEX_rt)? 2'b01 : 2'b00;
endmodule
```

- [ ] **Step 4: 运行确认通过**

Run: `iverilog -g2012 -o /tmp/tf.out sim/tb_forwarding.v src/ForwardingUnit.v && vvp /tmp/tf.out`
Expected: `PASS tb_forwarding`。

- [ ] **Step 5: Commit**

```bash
git add src/ForwardingUnit.v sim/tb_forwarding.v
git commit -m "feat: add ForwardingUnit with EX/MEM>MEM/WB priority (unit tested)"
```

### Task 3.2: 接入转发单元 + 依赖链集成测试

**Files:**
- Modify: `src/PipelineCPU.v`
- Create: `sim/prog_forward.hex`, `sim/tb_cpu_forward.v`

- [ ] **Step 1: 接线**

在 `PipelineCPU.v` 中删掉占位 `ForwardA/ForwardB=0`，改为实例化：

```verilog
	wire [1:0] ForwardA, ForwardB;
	ForwardingUnit fwd(
		.EXMEM_RegWrite(m_RegWrite),.EXMEM_rd(m_waddr),
		.MEMWB_RegWrite(w_RegWrite),.MEMWB_rd(w_waddr),
		.IDEX_rs(x_rs),.IDEX_rt(x_rt),.ForwardA(ForwardA),.ForwardB(ForwardB));
```

- [ ] **Step 2: 依赖链程序 prog_forward.hex**

```
# addiu $1,$0,5
# addiu $2,$1,3   ; 依赖$1 (EX/MEM->EX)
# add   $3,$2,$1  ; 依赖$2(EX/MEM),$1(MEM/WB)
# sub   $4,$3,$2  ; 链式
# sw    $4,0($0)
```
hex：
```
24010005
24220003
00411820
00622022
ac040000
```
> 校验：`00411820`=add $3,$2,$1；`00622022`=sub $4,$3,$2（rt 字段务必正确）。

- [ ] **Step 3: testbench**

```verilog
`timescale 1ns/1ps
module tb_cpu_forward;
	reg clk=0,reset=1; wire MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	DataMemory dmem(.reset(reset),.clk(clk),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.Write_data(MemWriteData),.Read_data(MemReadData));
	always #5 clk=~clk; integer errors=0;
	initial begin
		#12 reset=0; #200;
		// 期望：$1=5 $2=8 $3=13 $4=5
		if(cpu.rf.RF_data[2]!==32'd8)  begin errors=errors+1; $display("FAIL $2=%0d exp 8",cpu.rf.RF_data[2]); end
		if(cpu.rf.RF_data[3]!==32'd13) begin errors=errors+1; $display("FAIL $3=%0d exp 13",cpu.rf.RF_data[3]); end
		if(cpu.rf.RF_data[4]!==32'd5)  begin errors=errors+1; $display("FAIL $4=%0d exp 5",cpu.rf.RF_data[4]); end
		if(dmem.RAM[0]!==32'd5)        begin errors=errors+1; $display("FAIL MEM[0]=%0d exp 5",dmem.RAM[0]); end
		if(errors==0) $display("PASS tb_cpu_forward");
		$finish;
	end
endmodule
```

- [ ] **Step 4: 运行（预期 PASS）**

Run:
```bash
iverilog -g2012 -DIMEM_FILE='"sim/prog_forward.hex"' -o /tmp/t_fwd.out \
  sim/tb_cpu_forward.v src/PipelineCPU.v src/Control.v src/ALU.v src/ALUControl.v \
  src/RegisterFile.v src/InstructionMemory.v src/DataMemory.v src/ForwardingUnit.v
vvp /tmp/t_fwd.out
```
Expected: `PASS tb_cpu_forward`。

- [ ] **Step 5: Commit**

```bash
git add src/PipelineCPU.v sim/prog_forward.hex sim/tb_cpu_forward.v
git commit -m "feat: wire ForwardingUnit; back-to-back dependency test passes"
```

---

## Phase 4 — 冒险单元（load-use 阻塞 + 冲刷）

### Task 4.1: HazardUnit.v + 单元测试

**Files:**
- Create: `src/HazardUnit.v`, `sim/tb_hazard.v`

- [ ] **Step 1: 单元测试（先失败）**

```verilog
`timescale 1ns/1ps
module tb_hazard;
	reg idex_memread; reg [4:0] idex_rt, ifid_rs, ifid_rt;
	reg redirect_ex, redirect_id;
	wire stall, flush_ifid, flush_idex; integer errors=0;
	HazardUnit u(.IDEX_MemRead(idex_memread),.IDEX_rt(idex_rt),
		.IFID_rs(ifid_rs),.IFID_rt(ifid_rt),
		.redirect_EX(redirect_ex),.redirect_ID(redirect_id),
		.stall(stall),.flush_IFID(flush_ifid),.flush_IDEX(flush_idex));
	task chk(input s,fi,fx); begin
		if(stall!==s||flush_ifid!==fi||flush_idex!==fx) begin errors=errors+1;
			$display("FAIL s=%b fi=%b fx=%b exp %b %b %b",stall,flush_ifid,flush_idex,s,fi,fx); end end
	endtask
	initial begin
		// load-use：lw 目标=后续 rs -> stall
		idex_memread=1; idex_rt=5'd5; ifid_rs=5'd5; ifid_rt=5'd0; redirect_ex=0; redirect_id=0; #1 chk(1,0,0);
		// 无关：不阻塞
		idex_memread=1; idex_rt=5'd5; ifid_rs=5'd6; ifid_rt=5'd7; #1 chk(0,0,0);
		// EX 重定向（分支/jr taken）-> 冲刷 IF/ID 与 ID/EX
		idex_memread=0; redirect_ex=1; redirect_id=0; #1 chk(0,1,1);
		// ID 重定向（j/jal）-> 只冲刷 IF/ID
		redirect_ex=0; redirect_id=1; #1 chk(0,1,0);
		// EX 重定向优先于 load-use（避免吞掉重定向）
		idex_memread=1; idex_rt=5'd5; ifid_rs=5'd5; redirect_ex=1; redirect_id=0; #1 chk(0,1,1);
		if(errors==0) $display("PASS tb_hazard"); $finish;
	end
endmodule
```

- [ ] **Step 2: 运行确认失败**

Run: `iverilog -g2012 -o /tmp/th.out sim/tb_hazard.v src/HazardUnit.v`
Expected: 编译失败（未定义）。

- [ ] **Step 3: 写 HazardUnit.v**

```verilog
module HazardUnit(
	input        IDEX_MemRead,
	input  [4:0] IDEX_rt,
	input  [4:0] IFID_rs,
	input  [4:0] IFID_rt,
	input        redirect_EX,   // 分支/jr taken（EX）
	input        redirect_ID,   // j/jal（ID）
	output       stall,
	output       flush_IFID,
	output       flush_IDEX
);
	wire load_use = IDEX_MemRead &&
		((IDEX_rt==IFID_rs)||(IDEX_rt==IFID_rt)) && (IDEX_rt!=5'd0);
	// EX 重定向优先：发生时不再 stall（直接冲刷）
	assign stall      = load_use & ~redirect_EX;
	assign flush_IFID = redirect_EX | redirect_ID;
	assign flush_IDEX = redirect_EX;
endmodule
```

- [ ] **Step 4: 运行确认通过**

Run: `iverilog -g2012 -o /tmp/th.out sim/tb_hazard.v src/HazardUnit.v && vvp /tmp/th.out`
Expected: `PASS tb_hazard`。

- [ ] **Step 5: Commit**

```bash
git add src/HazardUnit.v sim/tb_hazard.v
git commit -m "feat: add HazardUnit (load-use stall + branch/jump flush, unit tested)"
```

### Task 4.2: 接入冒险单元

**Files:**
- Modify: `src/PipelineCPU.v`

- [ ] **Step 1: 替换占位信号**

删掉 `stall/flush_IFID/flush_IDEX` 的常量占位，改为实例化 HazardUnit：

```verilog
	wire stall, flush_IFID, flush_IDEX;
	HazardUnit hz(
		.IDEX_MemRead(x_MemRead),.IDEX_rt(x_rt),
		.IFID_rs(ID_rs),.IFID_rt(ID_rt),
		.redirect_EX(redirect_EX),.redirect_ID(redirect_ID),
		.stall(stall),.flush_IFID(flush_IFID),.flush_IDEX(flush_IDEX));
```

> 校验点：PC 与 IF/ID 在 `stall` 时保持（已在 Phase2 用 `if(!stall)` 实现）；`insert_bubble = stall | flush_IDEX` 已就绪；`flush_IFID` 在非 stall 时把 IF/ID 清成 nop（已就绪）。注意当 `stall && redirect_ID` 理论不会同时（j/jal 不读寄存器、不产生 load-use 对 IF/ID 的依赖且 redirect_ID 来自当前 ID，stall 冻结 IF/ID 但 redirect_ID 仍会触发 flush_IFID——此时 PC 被冻结会丢失跳转）。**实现时校验：** redirect_ID 发生时不应被 stall 冻结。由于 j/jal 在 ID 不依赖寄存器，load_use(基于 IDEX_MemRead 与 IF/ID 的 rs/rt) 与 j/jal 互不冲突的常见情况成立；若担心，可令 PC 写使能 = `!stall || redirect_EX || redirect_ID`。本计划采用：`else if (!stall || redirect_EX || redirect_ID) PC <= PC_next;`

把 PC 更新改为：
```verilog
	always @(posedge clk or posedge reset)
		if (reset) PC <= 32'd0;
		else if (!stall || redirect_EX || redirect_ID) PC <= PC_next;
```

- [ ] **Step 2: 语法检查**

Run:
```bash
iverilog -g2012 -o /tmp/cpu2.out src/PipelineCPU.v src/Control.v src/ALU.v \
  src/ALUControl.v src/RegisterFile.v src/InstructionMemory.v src/ForwardingUnit.v src/HazardUnit.v
```
Expected: 无错误。

- [ ] **Step 3: 回归之前的测试**

Run（basic 与 forward 应仍 PASS）：
```bash
iverilog -g2012 -DIMEM_FILE='"sim/prog_forward.hex"' -o /tmp/t_fwd.out \
  sim/tb_cpu_forward.v src/PipelineCPU.v src/Control.v src/ALU.v src/ALUControl.v \
  src/RegisterFile.v src/InstructionMemory.v src/DataMemory.v src/ForwardingUnit.v src/HazardUnit.v
vvp /tmp/t_fwd.out
```
Expected: `PASS tb_cpu_forward`。

- [ ] **Step 4: Commit**

```bash
git add src/PipelineCPU.v
git commit -m "feat: wire HazardUnit into datapath"
```

### Task 4.3: load-use 集成测试

**Files:**
- Create: `sim/prog_loaduse.hex`, `sim/data_loaduse.hex`, `sim/tb_cpu_loaduse.v`

- [ ] **Step 1: 数据与程序**

`sim/data_loaduse.hex`（DMEM[0]=100）：
```
00000064
```
`sim/prog_loaduse.hex`：
```
# lw   $1,0($0)    ; $1=100  (DMEM[0])
# add  $2,$1,$1    ; 紧跟使用 $1 -> load-use 阻塞1拍 + 转发
# sw   $2,4($0)    ; MEM[1]=200
```
hex：
```
8c010000
00221020
ac020004
```

- [ ] **Step 2: testbench**

```verilog
`timescale 1ns/1ps
module tb_cpu_loaduse;
	reg clk=0,reset=1; wire MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	DataMemory dmem(.reset(reset),.clk(clk),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.Write_data(MemWriteData),.Read_data(MemReadData));
	always #5 clk=~clk; integer errors=0;
	initial begin
		#12 reset=0; #200;
		if(cpu.rf.RF_data[1]!==32'd100) begin errors=errors+1; $display("FAIL $1=%0d exp 100",cpu.rf.RF_data[1]); end
		if(cpu.rf.RF_data[2]!==32'd200) begin errors=errors+1; $display("FAIL $2=%0d exp 200",cpu.rf.RF_data[2]); end
		if(dmem.RAM[1]!==32'd200) begin errors=errors+1; $display("FAIL MEM[1]=%0d exp 200",dmem.RAM[1]); end
		if(errors==0) $display("PASS tb_cpu_loaduse"); $finish;
	end
endmodule
```

- [ ] **Step 3: 运行（预期 PASS）**

Run:
```bash
iverilog -g2012 -DIMEM_FILE='"sim/prog_loaduse.hex"' -DDMEM_FILE='"sim/data_loaduse.hex"' \
  -o /tmp/t_lu.out sim/tb_cpu_loaduse.v src/PipelineCPU.v src/Control.v src/ALU.v \
  src/ALUControl.v src/RegisterFile.v src/InstructionMemory.v src/DataMemory.v \
  src/ForwardingUnit.v src/HazardUnit.v
vvp /tmp/t_lu.out
```
Expected: `PASS tb_cpu_loaduse`。

- [ ] **Step 4: Commit**

```bash
git add sim/prog_loaduse.hex sim/data_loaduse.hex sim/tb_cpu_loaduse.v
git commit -m "test: load-use stall+forward integration test passes"
```

---

## Phase 5 — 分支/跳转集成测试

### Task 5.1: 控制流测试（beq taken / 不 taken / j / jal+jr）

**Files:**
- Create: `sim/prog_branch.hex`, `sim/tb_cpu_branch.v`

- [ ] **Step 1: 程序**

```
# 0  addiu $1,$0,1
# 1  addiu $2,$0,2
# 2  beq   $1,$2,SKIP   ; 不相等->不跳
# 3  addiu $3,$0,111    ; 应执行
# 4  beq   $1,$1,L1     ; 相等->跳到 L1(指令7)
# 5  addiu $3,$0,222    ; 应被跳过
# 6  addiu $4,$0,333    ; 应被跳过(分支冲刷2条:5,6)
# 7 L1: jal FUNC        ; $31=PC+4(=指令8地址=0x20)
# 8  addiu $5,$0,555    ; jal 后顺位指令应被跳过(j类冲刷IF)
# 9  addiu $6,$0,666    ; 同上被跳过? 取决:jal只冲1条 -> 指令8被冲，指令9是FUNC?
# 重新布局见下。
```
> 为避免歧义，采用如下确定布局（按地址顺序，nop 收尾自旋）：
```
# addr0 addiu $1,$0,1
# addr1 addiu $2,$0,2
# addr2 beq $1,$1,+2 (跳过 addr3,addr4 -> 落到 addr5)
# addr3 addiu $7,$0,999   ; 必须被冲刷，不执行
# addr4 addiu $7,$0,888   ; 必须被冲刷，不执行
# addr5 addiu $3,$0,111   ; 执行
# addr6 jal addr9         ; $31 = addr7<<? = 0x1c+4=0x20 ; 跳到 addr9
# addr7 addiu $7,$0,777   ; 被 j 类冲刷(1条)，不执行
# addr8 addiu $4,$0,444   ; FUNC 前一条? 不执行(在addr7后) -- 见说明
# addr9 FUNC: jr $31      ; 返回到 $31=addr8(0x20)
# addr8 实际作为返回点执行: addiu $4,$0,444 ; 执行
```
> 由于 jal 链接 = PC+4 = addr7 的地址=0x1c？计算：addr6 地址=0x18，PC+4=0x1c=addr7。jr 返回 addr7。为使返回点有意义，令 addr7 = 目标返回点。最终采用下表（已自洽，附 beq 自旋收尾）：

确定程序（地址:汇编）：
```
0x00 addiu $1,$0,1
0x04 addiu $2,$0,2
0x08 beq   $1,$1,0x14      ; offset=(0x14-0x0c)/4=2 -> 跳过0x0c,0x10
0x0c addiu $7,$0,999       ; 冲刷,不执行
0x10 addiu $7,$0,888       ; 冲刷,不执行
0x14 addiu $3,$0,111       ; 执行 ($3=111)
0x18 jal   0x24            ; $31=0x1c, 跳到0x24
0x1c addiu $4,$0,444       ; 返回点(jr 回到这里),执行 ($4=444)
0x20 beq   $0,$0,0x20      ; 自旋(结束)
0x24 jr    $31             ; 返回 0x1c
```
机器码 hex（逐行=地址0,4,8,...）：
```
24010001
24020002
10220002
2407270f
24070378
2403006f
0c000009
240401bc
1000ffff
03e00008
```
> 校验：`10220002`=beq $1,$1,2；`0c000009`=jal 0x24(字地址9)；`2404...`：444=0x1bc → `2404 01bc`；`1000ffff`=beq $0,$0,-1(自旋)；`03e00008`=jr $31。

- [ ] **Step 2: testbench**

```verilog
`timescale 1ns/1ps
module tb_cpu_branch;
	reg clk=0,reset=1; wire MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	DataMemory dmem(.reset(reset),.clk(clk),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.Write_data(MemWriteData),.Read_data(MemReadData));
	always #5 clk=~clk; integer errors=0;
	initial begin
		#12 reset=0; #400;
		if(cpu.rf.RF_data[3]!==32'd111) begin errors=errors+1; $display("FAIL $3=%0d exp 111",cpu.rf.RF_data[3]); end
		if(cpu.rf.RF_data[4]!==32'd444) begin errors=errors+1; $display("FAIL $4=%0d exp 444 (jal/jr)",cpu.rf.RF_data[4]); end
		if(cpu.rf.RF_data[7]!==32'd0)   begin errors=errors+1; $display("FAIL $7=%0d exp 0 (flushed)",cpu.rf.RF_data[7]); end
		if(cpu.rf.RF_data[31]!==32'h0000001c) begin errors=errors+1; $display("FAIL $31=%h exp 1c",cpu.rf.RF_data[31]); end
		if(errors==0) $display("PASS tb_cpu_branch"); $finish;
	end
endmodule
```

- [ ] **Step 3: 运行（预期 PASS）**

Run:
```bash
iverilog -g2012 -DIMEM_FILE='"sim/prog_branch.hex"' -o /tmp/t_br.out \
  sim/tb_cpu_branch.v src/PipelineCPU.v src/Control.v src/ALU.v src/ALUControl.v \
  src/RegisterFile.v src/InstructionMemory.v src/DataMemory.v src/ForwardingUnit.v src/HazardUnit.v
vvp /tmp/t_br.out
```
Expected: `PASS tb_cpu_branch`。若 FAIL，用 `gtkwave` 看波形定位（在 tb 顶部加 `$dumpfile/$dumpvars`）。

- [ ] **Step 4: Commit**

```bash
git add sim/prog_branch.hex sim/tb_cpu_branch.v
git commit -m "test: branch taken/not-taken + jal/jr control-flow test passes"
```

---

## Phase 6 — 外设总线与数码管

### Task 6.1: MemBus.v（地址译码 + digi 寄存器）

**Files:**
- Create: `src/MemBus.v`, `sim/tb_cpu_mmio.v`, `sim/prog_mmio.hex`

- [ ] **Step 1: 写 MemBus.v**

把 CPU 的存储总线接到 DMEM 或外设；`0x40000010` 命中时写 `digi`。

```verilog
module MemBus(
	input         clk,
	input         reset,
	input         MemRead,
	input         MemWrite,
	input  [31:0] Address,
	input  [31:0] WriteData,
	output [31:0] ReadData,
	output reg [11:0] digi
);
	wire is_periph = (Address[30]);            // 0x4xxxxxxx
	wire dmem_we = MemWrite & ~is_periph;
	wire dmem_re = MemRead  & ~is_periph;
	wire [31:0] dmem_rd;
	DataMemory dmem(.reset(reset),.clk(clk),.MemRead(dmem_re),.MemWrite(dmem_we),
		.Address(Address),.Write_data(WriteData),.Read_data(dmem_rd));

	always @(posedge clk or posedge reset)
		if (reset) digi <= 12'd0;
		else if (MemWrite & is_periph && Address==32'h40000010)
			digi <= WriteData[11:0];

	// 外设读：0x40000010 回读 digi；其余 0
	wire [31:0] periph_rd = (Address==32'h40000010)? {20'd0,digi} : 32'd0;
	assign ReadData = is_periph ? periph_rd : dmem_rd;
endmodule
```

- [ ] **Step 2: 程序：写数字 2 到最低位数码管（0x015B）**

`sim/prog_mmio.hex`：
```
# lui   $1,0x4000      ; $1=0x40000000
# ori   $1,$1,0x0010   ; $1=0x40000010
# addiu $2,$0,0x015B   ; 段码: 数字2 + AN0
# sw    $2,0($1)       ; 写数码管
# beq   $0,$0,self
```
hex：
```
3c014000
34210010
2402015b
ac220000
1000ffff
```

- [ ] **Step 3: testbench（顶层用 MemBus 替代裸 DMEM）**

```verilog
`timescale 1ns/1ps
module tb_cpu_mmio;
	reg clk=0,reset=1; wire MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	wire [11:0] digi;
	PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	MemBus bus(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.WriteData(MemWriteData),.ReadData(MemReadData),.digi(digi));
	always #5 clk=~clk; integer errors=0;
	initial begin
		#12 reset=0; #200;
		if(digi!==12'h15b) begin errors=errors+1; $display("FAIL digi=%h exp 15b",digi); end
		if(errors==0) $display("PASS tb_cpu_mmio"); $finish;
	end
endmodule
```

- [ ] **Step 4: 运行（预期 PASS）**

Run:
```bash
iverilog -g2012 -DIMEM_FILE='"sim/prog_mmio.hex"' -o /tmp/t_mmio.out \
  sim/tb_cpu_mmio.v src/PipelineCPU.v src/Control.v src/ALU.v src/ALUControl.v \
  src/RegisterFile.v src/InstructionMemory.v src/DataMemory.v src/ForwardingUnit.v \
  src/HazardUnit.v src/MemBus.v
vvp /tmp/t_mmio.out
```
Expected: `PASS tb_cpu_mmio`。

- [ ] **Step 5: Commit**

```bash
git add src/MemBus.v sim/prog_mmio.hex sim/tb_cpu_mmio.v
git commit -m "feat: add MemBus (DMEM + digi MMIO); sw to 0x40000010 test passes"
```

---

## Phase 7 — FPGA 顶层与管脚约束

> 本阶段无仿真自检（属综合/上板）；以 Vivado 综合通过 + 上板观察为验收。

### Task 7.1: top.v

**Files:**
- Create: `src/top.v`

- [ ] **Step 1: 写 top.v**

100MHz 输入分频到安全频率（先用简单二分频/计数分频，后续按时序报告调整或换 PLL）。数码管段/位选直接由 `digi` 驱动（软件扫描）。

```verilog
module top(
	input         clk100,        // R4 100MHz
	input         rst_btn,       // KEY1 (B22) 按下高电平
	// 7-seg（共阴极，高电平亮 / 位选高电平选中）
	output        seg_a,seg_b,seg_c,seg_d,seg_e,seg_f,seg_g,seg_dp,
	output        sel1,sel2,sel3,sel4,
	// UART（先留接口，Phase8 接）
	output        uart_txd,
	input         uart_rxd
);
	// ---- 时钟分频（示例：100MHz/4=25MHz，先保守；按时序报告调整 N）----
	reg [1:0] divcnt = 2'd0;
	always @(posedge clk100) divcnt <= divcnt + 2'd1;
	wire cpu_clk = divcnt[1];

	wire        MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	wire [11:0] digi;
	PipelineCPU cpu(.clk(cpu_clk),.reset(rst_btn),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	MemBus bus(.clk(cpu_clk),.reset(rst_btn),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.WriteData(MemWriteData),.ReadData(MemReadData),.digi(digi));

	// digi[6:0]=g..a, digi[7]=dp, digi[11:8]=AN3..AN0
	assign {seg_g,seg_f,seg_e,seg_d,seg_c,seg_b,seg_a} = digi[6:0];
	assign seg_dp = digi[7];
	assign {sel4,sel3,sel2,sel1} = digi[11:8];
	assign uart_txd = 1'b1;   // 占位（Phase8 替换）
endmodule
```
> 注意：上面 `assign {seg_g,...,seg_a}=digi[6:0]` 的拼接顺序——`digi[0]=a`，所以应为 `assign {seg_g,seg_f,seg_e,seg_d,seg_c,seg_b,seg_a}=digi[6:0];`（最左 seg_g 对应 digi[6]）。校验位序后再综合。

- [ ] **Step 2: 语法检查**

Run:
```bash
iverilog -g2012 -o /tmp/top.out src/top.v src/PipelineCPU.v src/Control.v src/ALU.v \
  src/ALUControl.v src/RegisterFile.v src/InstructionMemory.v src/DataMemory.v \
  src/ForwardingUnit.v src/HazardUnit.v src/MemBus.v
```
Expected: 无错误。

- [ ] **Step 3: Commit**

```bash
git add src/top.v
git commit -m "feat: add FPGA top (clock divider, 7-seg pin mapping)"
```

### Task 7.2: welog1.xdc 管脚约束

**Files:**
- Create: `constr/welog1.xdc`

- [ ] **Step 1: 写约束（管脚来自《WELOG1 说明书》）**

```tcl
## 时钟 100MHz
set_property -dict {PACKAGE_PIN R4 IOSTANDARD LVCMOS33} [get_ports clk100]
create_clock -name sys_clk -period 10.000 [get_ports clk100]

## 复位 KEY1（按下高电平）
set_property -dict {PACKAGE_PIN B22 IOSTANDARD LVCMOS33} [get_ports rst_btn]

## 七段数码管 段（共阴，高电平亮）
set_property -dict {PACKAGE_PIN N2 IOSTANDARD LVCMOS33} [get_ports seg_a]
set_property -dict {PACKAGE_PIN P5 IOSTANDARD LVCMOS33} [get_ports seg_b]
set_property -dict {PACKAGE_PIN V5 IOSTANDARD LVCMOS33} [get_ports seg_c]
set_property -dict {PACKAGE_PIN U5 IOSTANDARD LVCMOS33} [get_ports seg_d]
set_property -dict {PACKAGE_PIN T5 IOSTANDARD LVCMOS33} [get_ports seg_e]
set_property -dict {PACKAGE_PIN P1 IOSTANDARD LVCMOS33} [get_ports seg_f]
set_property -dict {PACKAGE_PIN W4 IOSTANDARD LVCMOS33} [get_ports seg_g]
set_property -dict {PACKAGE_PIN V3 IOSTANDARD LVCMOS33} [get_ports seg_dp]
## 位选 SEL1..4
set_property -dict {PACKAGE_PIN M2 IOSTANDARD LVCMOS33} [get_ports sel1]
set_property -dict {PACKAGE_PIN P2 IOSTANDARD LVCMOS33} [get_ports sel2]
set_property -dict {PACKAGE_PIN R1 IOSTANDARD LVCMOS33} [get_ports sel3]
set_property -dict {PACKAGE_PIN Y3 IOSTANDARD LVCMOS33} [get_ports sel4]

## UART（选做）
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports uart_txd]
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports uart_rxd]
```

- [ ] **Step 2: Commit**

```bash
git add constr/welog1.xdc
git commit -m "feat: add WELOG1 pin constraints (clk/reset/7seg/uart)"
```

---

## 后续（独立计划，本计划不含）

- **Phase 8 — UART 外设**：`UART.v`（波特率分频收发）+ MemBus 接 0x40000018/1C/20 + 串口收发集成测试；top 接 A20/B20。
- **Phase 9 — 传纸条硬件版集成**：用户改写的无 syscall 汇编 → MARS 导出机器码 → `imem.hex` + 测试数据 `dmem.hex`；跑通完整任务，仿真统计周期数 C，结合 MARS 指令数 N 计算 CPI；Vivado 综合出最高频率。

---

## Self-Review 记录

- **Spec 覆盖**：流水线五级 ✓(P2)；完全 forwarding ✓(P3)；load-use 阻塞 ✓(P4)；分支 EX 解析+冲刷 ✓(P5/Control)；j/jal ID 解析 ✓(P2 datapath)；jr/jalr EX 解析(Option A) ✓(EX redirect)；ISA 全集 ✓(Control P1)；地址映射/digi ✓(P6)；管脚 ✓(P7)；CPI/频率 → 后续 Phase9。UART → 后续 Phase8（spec 已纳入设计，本计划按"先核心"约定延后实现）。
- **占位扫描**：tb_cpu_forward 的 `if(){}` 已用注释标注须改为 `begin...end`；prog_branch 已给出自洽确定布局与逐字校验。
- **一致性**：模块端口名（ForwardA/B、stall/flush_IFID/flush_IDEX、redirect_EX/ID、digi）在 datapath 与各单元间一致。
