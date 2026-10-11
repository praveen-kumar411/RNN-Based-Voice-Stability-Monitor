# Cadence Genus(TM) Synthesis Solution, Version 21.14-s082_1, built Jun 23 2022 14:32:08

# Date: Sun Oct 11 06:40:58 2026
# Host: ic312.vit.ac.in (x86_64 w/Linux 4.18.0-477.13.1.el8_8.x86_64) (12cores*20cpus*1physical cpu*12th Gen Intel(R) Core(TM) i7-12700 25600KB)
# OS:   Red Hat Enterprise Linux release 8.8 (Ootpa)

source power.tcl
tail -25 reports/power_vcd.rpt
grep -i -A3 "annotat\|asserted" genus_power.log | head -20
