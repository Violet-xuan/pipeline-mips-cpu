# ============================================================
# build_vivado.tcl — create (and optionally build) the WELOG1
# pipeline-MIPS Vivado project from the command line. No GUI.
#
# Usage (from a shell with Vivado on PATH):
#   vivado -mode batch -source scripts/build_vivado.tcl
#
# Options (pass with -tclargs):
#   vivado -mode batch -source scripts/build_vivado.tcl -tclargs no_flow
#       -> only create the project (skip synth/impl/bitstream)
#   vivado -mode batch -source scripts/build_vivado.tcl -tclargs gui
#       -> create the project then leave the GUI open (use with -mode gui)
#
# Output: build/vivado/welog1_mips.xpr  and (if flow runs)
#         build/vivado/welog1_mips.runs/impl_1/top.bit
# ============================================================

set part        "xc7a35tfgg484-2"
set proj_name   "welog1_mips"
set top_module  "top"

# board program (machine code + preset data) used to initialize IMEM/DMEM
set imem_hex_rel "sim/imem_chuanzhitiao.hex"
set dmem_hex_rel "sim/dmem_chuanzhitiao.hex"

# ---- resolve paths relative to this script (scripts/..) ----
set script_dir [file normalize [file dirname [info script]]]
set root_dir   [file normalize [file join $script_dir ..]]
set build_dir  [file join $root_dir build vivado]

# ---- parse args ----
set run_flow 1
set keep_gui 0
set perf     0
foreach a $argv {
    if {$a eq "no_flow"} { set run_flow 0 }
    if {$a eq "gui"}     { set keep_gui 1; set run_flow 0 }
    if {$a eq "perf"}    { set perf 1 }
}

# ---- (re)create project ----
file mkdir $build_dir
if {[file exists [file join $build_dir $proj_name.xpr]]} {
    puts "INFO: removing existing project at $build_dir/$proj_name.xpr"
    file delete -force [file join $build_dir $proj_name.xpr] [file join $build_dir $proj_name.cache] \
        [file join $build_dir $proj_name.runs] [file join $build_dir $proj_name.srcs] \
        [file join $build_dir $proj_name.gen] [file join $build_dir $proj_name.hw] [file join $build_dir $proj_name.sim]
}
create_project $proj_name $build_dir -part $part -force

# ---- design sources (all RTL except testbenches) ----
set rtl [list \
    [file join $root_dir src ALU.v] \
    [file join $root_dir src ALUControl.v] \
    [file join $root_dir src Control.v] \
    [file join $root_dir src RegisterFile.v] \
    [file join $root_dir src InstructionMemory.v] \
    [file join $root_dir src DataMemory.v] \
    [file join $root_dir src ForwardingUnit.v] \
    [file join $root_dir src HazardUnit.v] \
    [file join $root_dir src PipelineCPU.v] \
    [file join $root_dir src MemBus.v] \
    [file join $root_dir src UART.v] \
    [file join $root_dir src top.v] \
]
add_files -norecurse $rtl

# ---- memory init hex files (so they travel with the project) ----
set imem_hex [file normalize [file join $root_dir $imem_hex_rel]]
set dmem_hex [file normalize [file join $root_dir $dmem_hex_rel]]
add_files -norecurse [list $imem_hex $dmem_hex]

# ---- constraints ----
add_files -fileset constrs_1 -norecurse [file join $root_dir constr welog1.xdc]

# ---- top + $readmemh init paths (absolute, forward slashes) ----
set_property top $top_module [current_fileset]
set defs "IMEM_FILE=\"$imem_hex\" DMEM_FILE=\"$dmem_hex\""
set_property verilog_define $defs [get_filesets sources_1]
set_property verilog_define $defs [get_filesets sim_1]
update_compile_order -fileset sources_1

puts "INFO: project created at [file join $build_dir $proj_name.xpr]"
puts "INFO: top=$top_module part=$part"
puts "INFO: IMEM=$imem_hex"
puts "INFO: DMEM=$dmem_hex"

# ---- optional timing-focused strategies (pass 'perf') ----
if {$perf} {
    puts "INFO: perf mode — retiming synth + post-route phys_opt impl"
    set_property strategy Flow_PerfOptimized_high            [get_runs synth_1]
    set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
}

# ---- optional: run synth -> impl -> bitstream ----
if {$run_flow} {
    puts "INFO: launching synthesis..."
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        error "synthesis failed; open the project to inspect logs"
    }
    puts "INFO: launching implementation + bitstream..."
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
        error "implementation failed; open the project to inspect logs"
    }
    set bit [file join $build_dir $proj_name.runs impl_1 $top_module.bit]
    puts "INFO: DONE. bitstream: $bit"
    puts "INFO: check timing/Fmax: open_run impl_1; report_timing_summary"
}

if {!$keep_gui} { puts "INFO: build_vivado.tcl finished." }
