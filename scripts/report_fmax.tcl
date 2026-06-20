# report_fmax.tcl — measure the real CPU Fmax AFTER implementation.
# The CPU runs on cpu_clk = clk100/4 (divider in top.v). That divided clock is
# left unconstrained during the build (constraining it wedges Vivado 2017.3 synth),
# so we apply the generated-clock constraint here, on the fully-routed netlist where
# the divider register pin exists, and read the worst setup slack.
#
# Usage:
#   vivado -mode batch -source scripts/report_fmax.tcl
#
# Prints CPU_CLK_WNS and the implied Fmax; full report in build/fmax_timing.rpt

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set xpr        [file join $root_dir build vivado welog1_mips.xpr]

open_project $xpr
open_run impl_1

# cpu_clk = clk100 / 4 (period 40 ns)
set cpu_period 40.0
create_generated_clock -name cpu_clk -source [get_ports clk100] -divide_by 4 [get_pins {divcnt_reg[1]/Q}]

report_timing_summary -file [file join $root_dir build fmax_timing.rpt]

# worst setup slack within the cpu_clk domain
set paths [get_timing_paths -setup -max_paths 1 -nworst 1 -group cpu_clk]
if {[llength $paths] == 0} {
    puts "WARN: no cpu_clk paths found (check divider pin name)"
} else {
    set wns [get_property SLACK [lindex $paths 0]]
    set crit [expr {$cpu_period - $wns}]
    set fmax [expr {1000.0 / $crit}]
    puts "================ CPU Fmax ================"
    puts "cpu_clk period (target) = $cpu_period ns (= clk100/4 = 25 MHz)"
    puts "worst setup slack (WNS) = $wns ns"
    puts "critical path delay     = $crit ns"
    puts [format "implied Fmax            = %.2f MHz" $fmax]
    puts "========================================="
}
close_project
