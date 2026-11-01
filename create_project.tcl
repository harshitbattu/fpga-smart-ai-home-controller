# ============================================================================
# create_project.tcl : builds the Vivado 2024.2 project for the
#                      FPGA Adaptive Smart Home Controller (Nexys 4 DDR)
#
# Usage (Vivado Tcl console):
#     cd <path to this folder>
#     source create_project.tcl
# Then: Run Simulation / Run Synthesis / Run Implementation / Generate Bitstream
# Or run everything automatically:
#     source create_project.tcl
#     build_all
# ============================================================================
set proj_name smart_home
set proj_dir  [file normalize ./vivado]
set src_dir   [file normalize .]

# Nexys 4 DDR part. If Artix-7 support is not installed, fall back to any
# installed part so that SIMULATION still works (bitstream needs Artix-7).
set part xc7a100tcsg324-1
if {[llength [get_parts -quiet $part]] == 0 && [llength [get_parts -quiet xc7a100tcsg324*]] > 0} {
    set part [lindex [lsort [get_parts -quiet xc7a100tcsg324*]] 0]
    puts "NOTE: xc7a100tcsg324-1 not found, using same chip/package $part"
}
if {[llength [get_parts -quiet $part]] == 0} {
    set part [lindex [get_parts] 0]
    puts "WARNING: xc7a100tcsg324-1 (Artix-7) is not installed in this Vivado."
    puts "WARNING: Using $part for SIMULATION ONLY. Install Artix-7 via"
    puts "WARNING: Help > Add Design Tools or Devices, before synthesis/bitstream."
}
create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]

# ---- design sources ----
add_files -norecurse [glob $src_dir/rtl/*.v]
add_files -norecurse [glob $src_dir/rtl/*.vh]
foreach f [get_files *.vh] { set_property file_type {Verilog Header} $f }
set_property include_dirs $src_dir/rtl [get_filesets sources_1]
set_property top smart_home_top [get_filesets sources_1]

# ---- constraints ----
add_files -fileset constrs_1 -norecurse $src_dir/constr/nexys4ddr_smart_home.xdc

# ---- simulation sources ----
add_files -fileset sim_1 -norecurse [list \
    $src_dir/tb/tb_smart_home.v \
    $src_dir/tb/tb_units_realtime.v \
    $src_dir/tb/adt7420_model.v \
    $src_dir/tb/tb_nn_engine.v \
    $src_dir/tb/tb_gas_latency.v \
    $src_dir/ai/nn_test_vectors.mem ]
set_property include_dirs $src_dir/rtl [get_filesets sim_1]
set_property top tb_smart_home [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
# the testbench writes its VCD to sim/ ; create it inside the xsim run folder
file mkdir $proj_dir/$proj_name.sim/sim_1/behav/xsim/sim

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Project created. Top = smart_home_top, simulation top = tb_smart_home"

proc build_all {} {
    if {![string match "xc7a100t*csg324*" [get_property PART [current_project]]]} {
        puts "ERROR: this project is not using the Nexys 4 DDR chip (xc7a100tcsg324-1)."
        puts "ERROR: Install Artix-7 (Help > Add Design Tools or Devices), delete the 'vivado' folder,"
        puts "ERROR: run 'source create_project.tcl' again, then 'build_all'. Simulation works without it."
        return
    }
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    open_run impl_1
    file mkdir reports
    report_utilization    -file reports/utilization.txt
    report_utilization    -hierarchical -file reports/utilization_hier.txt
    report_timing_summary -file reports/timing_summary.txt
    report_power          -file reports/power.txt
    puts "Bitstream: [get_property DIRECTORY [get_runs impl_1]]/smart_home_top.bit"
}
