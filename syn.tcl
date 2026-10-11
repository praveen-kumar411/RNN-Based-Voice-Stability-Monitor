# ================= syn.tcl : Genus synthesis for rnn_vsm_top =================
# >>> EDIT THESE TWO LINES to match your 'find' output <<<
set LIB_DIR  /home/install/FOUNDRY/digital/90nm/dig/lib
set LIB_FILE slow.lib

set_db init_lib_search_path $LIB_DIR
set_db library              $LIB_FILE
set_db hdl_search_path      .
set_db information_level    7

# ---------- read and elaborate RTL ----------
set RTL {mem_rw.v hstate_rf.v requant.v act_lut_syn.v gru_core.v ema.v alert.v
         regs.v axis_feat_buf.v icg.v rnn_vsm_top.v}
read_hdl $RTL
elaborate rnn_vsm_top
check_design -unresolved

# ---------- constraints: 10 MHz clock ----------
create_clock -name clk -period 100 [get_ports clk]
set_input_delay  10 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 10 -clock clk [all_outputs]

# ---------- synthesize ----------
syn_generic
syn_map
syn_opt

# ---------- reports ----------
file mkdir reports outputs
report_area   > reports/area.rpt
report_gates  > reports/gates.rpt
report_timing > reports/timing.rpt
report_power  > reports/power_default.rpt

# ---------- power with real switching activity (if top.vcd exists) ----------
if {[file exists top.vcd]} {
  if {[catch {read_vcd -static -vcd_scope tb_top/dut top.vcd} err]} {
    puts "WARNING: VCD read failed: $err"
  }
  report_power > reports/power_vcd.rpt
}

# ---------- outputs ----------
write_hdl > outputs/rnn_vsm_netlist.v
write_sdc > outputs/rnn_vsm.sdc
puts "\n===== SYNTHESIS DONE: see reports/ folder ====="
write_db rnn_vsm_final.db
