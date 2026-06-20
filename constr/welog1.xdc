## 时钟 100MHz
set_property -dict {PACKAGE_PIN R4 IOSTANDARD LVCMOS33} [get_ports clk100]
create_clock -name sys_clk -period 10.000 [get_ports clk100]
## (cpu_clk generated-clock constraint is applied post-implementation in
##  scripts/report_fmax.tcl, not here — keeping it in the build XDC wedges
##  Vivado 2017.3 synthesis on the divider pin reference.)

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
