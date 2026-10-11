# PS-01 RNN-Based Voice Stability Monitor (rnn_vsm_top)

Low-power GRU accelerator: grades call quality every frame, keeps a running
average, raises an interrupt when quality drops.
GRU F=8, H=16, INT8 Q1.6 weights, INT16 Q4.11 activations, 1 MAC, 256-entry LUT,
shift-based EMA, hysteresis alert, AXI-Stream input, register map, clock gating.

## Files

| Group | Files |
|---|---|
| RTL (synthesizable) | mem_rw.v, hstate_rf.v, requant.v, act_lut_syn.v, gru_core.v, ema.v, alert.v, regs.v, axis_feat_buf.v, icg.v, rnn_vsm_top.v |
| RTL (simulation-only LUT) | act_lut.v (uses $readmemh; do NOT compile together with act_lut_syn.v) |
| Verilog testbenches | tb_requant.v, tb_act_lut.v, tb_storage.v, tb_gru_core.v, tb_post.v, tb_top.v, tb_corners.v, tb_long.v, tb_mac.v |
| cocotb testbench | test_rnn_vsm.py, Makefile |
| Python golden model | fxp.py (requant, LUT), golden_gru.py (GRU step, weight export) |
| Vector generators | gen_lut_vectors.py, golden_post.py, golden_top.py, golden_corners.py, golden_long.py |
| ML | train_gru_np.py (NumPy QAT training -> trained_params.json), make_plots.py |
| Scripts | run_all.py (full regression), syn.tcl (Genus synthesis), gen_lut_rom.py (writes act_lut_syn.v) |
| Outputs | logs/, reports/, plots/, screenshots/, evidence/, long_run/long_sim.log |

## Environment (every new terminal starts in bash)

    csh
    source /home/install/cshrc
    setenv PATH ~/.local/bin:/home/install/XCELIUM2209/tools/bin:$PATH
    setenv PYTHONPATH /home/vlsi/Desktop/hackathon
    cd /home/vlsi/Desktop/hackathon

## How to run

| Task | Command |
|---|---|
| Full regression (all tests, PASS/FAIL summary) | `python3 run_all.py` -> logs/regression_summary.txt |
| One Verilog test | `irun -clean <files> -top <tb_name>` (generate vectors with the matching golden_*.py first) |
| One test with waveforms | add `-access +rwc -gui` to the irun command |
| cocotb test | `make` |
| One-hour test (slow) | in long_run/: `python3 golden_long.py`, then irun with tb_long.v |
| Train the model | `python3 train_gru_np.py` |
| Plots | `python3 make_plots.py` -> plots/ |
| Synthesis | `genus -files syn.tcl -log genus_run` -> reports/ |
| Reopen synthesized design | `genus`, then `read_db rnn_vsm_final.db`, `gui_show` |

## Key results

| Item | Value |
|---|---|
| Latency | ~1,316 cycles = 132 us at 10 MHz (target < 1 ms) |
| Area | 308,937 um^2, 25,274 cells (gpdk 90 nm slow) |
| Timing | slack +39.2 ns at 100 ns clock (fmax ~16 MHz) |
| Power | 3.30 mW peak; ~1.78 mW average at 1.3% duty |
| Accuracy | Pearson r = 0.9925 (INT/RTL) vs synthetic E-model MOS labels |
| Quantization loss | delta r = 0.0001, mean |float - INT| = 0.0053 |
| LUT error | sigmoid max 0.00795, tanh max 0.01590 |
| Verification | all blocks bit-exact; 180,000-frame test 0 errors; corner cases pass; cocotb PASS |

## Gotchas

- `irun/genus: command not found` -> run `csh` and `source /home/install/cshrc`.
- `*E,MTOMDU: More than one unit matches` -> `rm -rf INCA_libs/worklib/*`, recompile. Never mix NCLaunch Single Step and Multiple Step.
- If trained_params.json exists, every golden script uses the TRAINED weights; delete or rename it to go back to random weights.
- Compile act_lut.v OR act_lut_syn.v, never both.
- $readmemh paths are relative to the folder the simulator is started from.
