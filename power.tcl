source syn.tcl
read_vcd -static -vcd_scope tb_top.dut top.vcd
report_power > reports/power_vcd.rpt
report_power -by_hierarchy > reports/power_vcd_hier.rpt
puts "===== VCD POWER DONE ====="
