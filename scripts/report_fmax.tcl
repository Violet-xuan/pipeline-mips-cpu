# report_fmax.tcl — report the CPU Fmax AFTER implementation.
# The CPU runs on cpu_clk = clk100/2 = 50 MHz (generated clock, 20 ns period in
# welog1.xdc). The worst setup slack on cpu_clk is the real timing margin and the
# implied Fmax is 1000/(period - WNS) = 1000/critical_path_delay.
#
# Usage:
#   vivado -mode batch -source scripts/report_fmax.tcl
#
# Prints the worst setup slack and the implied Fmax; full report in build/fmax_timing.rpt

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set xpr        [file join $root_dir build vivado welog1_mips.xpr]

open_project $xpr
open_run impl_1

# cpu_clk target period (must match create_generated_clock in welog1.xdc)
set clk_period 20.0

report_timing_summary -file [file join $root_dir build fmax_timing.rpt]

# worst setup slack within the cpu_clk domain
set paths [get_timing_paths -setup -max_paths 1 -nworst 1 -group cpu_clk]
if {[llength $paths] == 0} {
    puts "WARN: no cpu_clk paths found"
} else {
    set wns [get_property SLACK [lindex $paths 0]]
    set crit [expr {$clk_period - $wns}]
    set fmax [expr {1000.0 / $crit}]
    puts "================ CPU Fmax ================"
    puts "cpu_clk period (target) = $clk_period ns (= 50 MHz)"
    puts "worst setup slack (WNS) = $wns ns"
    puts "critical path delay     = $crit ns"
    puts [format "implied Fmax            = %.2f MHz" $fmax]
    puts "========================================="
}
close_project
