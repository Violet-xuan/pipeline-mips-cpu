# program_board.tcl — download the pipeline-MIPS bitstream to the WELOG1
# (xc7a35t) over JTAG. Board must be powered and the USB-JTAG cable connected.
#
#   "D:/Xilinx/Vivado/2017.3/bin/vivado.bat" -mode batch -source scripts/program_board.tcl
#
# Optional: pass an explicit .bit path with -tclargs <path>.

set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]

if {[llength $argv] >= 1} {
    set bit [file normalize [lindex $argv 0]]
} else {
    set bit [file join $root_dir build vivado welog1_mips.runs impl_1 top.bit]
}
if {![file exists $bit]} { error "bitstream not found: $bit (build it first)" }
puts "INFO: programming bitstream: $bit"

open_hw
connect_hw_server
open_hw_target

# pick the Artix-7 device on the JTAG chain
set dev [lindex [get_hw_devices -regexp {xc7a.*}] 0]
if {$dev eq ""} { set dev [lindex [get_hw_devices] 0] }
puts "INFO: target device = $dev"
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "INFO: DONE — programmed $dev"

close_hw_target
disconnect_hw_server
close_hw
