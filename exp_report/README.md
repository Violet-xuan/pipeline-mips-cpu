# 实验报告 — Overleaf 上传说明

## 文件列表

```
exp_report/
  main.tex        主 LaTeX 文件（XeLaTeX 编译）
  README.md       本说明文件
```

## Overleaf 使用方法

1. 登录 [Overleaf](https://www.overleaf.com)
2. 创建新项目 → 上传项目 → 上传 `main.tex`
3. **编译器设置**：点击左上角 Menu → Compiler 选择 **XeLaTeX**
4. 点击 Recompile 编译

## 本地编译（如有 TeX Live）

```bash
xelatex main.tex
xelatex main.tex   # 两次编译以生成正确的交叉引用
```

## 报告内容

- 摘要
- 设计目标与方案
- CPU 架构设计（五级流水线、前推、冒险、分支跳转）
- 外设接口（MMIO、UART）
- 频率优化（DSP mul 流水线化、DMEM/IMEM 寄存器化、MMCM 80 MHz）
- 性能分析（Fmax=83.15 MHz、CPI=1.47、资源利用率）
- 验证结果（仿真 + 上板）
- 总结

## 数据来源

所有性能数据均为实际测量：
- Fmax：Vivado post-route timing report（`report_fmax.tcl`）
- CPI：iverilog 仿真（`tb_cpu_cpi_measure.v`），3×3 传纸条基准
- 资源：Vivado synthesis utilization report
- 上板验证：`host/send_chuanzhitiao.py --port COM12`（80 MHz）
