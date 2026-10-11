# run_all.py : full regression for rnn_vsm_top
# Regenerates golden vectors, runs every testbench, saves logs, writes logs/regression_summary.txt
import os, sys, subprocess, datetime

RTL = ("mem_rw.v hstate_rf.v requant.v act_lut_syn.v gru_core.v ema.v alert.v "
       "regs.v axis_feat_buf.v icg.v rnn_vsm_top.v").split()

PY_STEPS = [  # (script, text that must appear)
    ("fxp.py",            "requant self-test: PASSED"),
    ("gen_lut_vectors.py", "Wrote lut_vectors.hex"),
    ("golden_gru.py",     "Wrote weights.hex"),
    ("golden_post.py",    "expected IRQs"),
    ("golden_top.py",     "expected IRQs"),
    ("golden_corners.py", "expected IRQs"),
]

TESTS = [  # (name, files, pass text)
    ("tb_requant",  ["requant.v", "tb_requant.v"],                       "ALL TESTS PASSED"),
    ("tb_act_lut",  ["act_lut_syn.v", "tb_act_lut.v"],                   "ALL 1000 VECTORS PASSED"),
    ("tb_storage",  ["mem_rw.v", "hstate_rf.v", "tb_storage.v"],         "STORAGE: ALL TESTS PASSED"),
    ("tb_gru_core", ["mem_rw.v", "hstate_rf.v", "requant.v", "act_lut_syn.v",
                     "gru_core.v", "tb_gru_core.v"],                     "ALL 50 FRAMES BIT-EXACT"),
    ("tb_post",     ["ema.v", "alert.v", "tb_post.v"],                   "ALL 300 FRAMES MATCH"),
    ("tb_top",      RTL + ["tb_top.v"],                                  "TOP LEVEL: ALL 100 FRAMES MATCH"),
    ("tb_corners",  RTL + ["tb_corners.v"],                              "CORNER CASES: ALL PASSED"),
]

KEYWORDS = ("Latency", "IRQs", "Frames", "Core clock", "max err", "expected IRQs", "T_LO")

os.makedirs("logs", exist_ok=True)


def run(cmd, log):
    with open(log, "w") as f:
        subprocess.call(cmd, stdout=f, stderr=subprocess.STDOUT)
    with open(log, errors="replace") as f:
        return f.read()


def key_lines(text):
    return [l.strip() for l in text.splitlines() if any(k in l for k in KEYWORDS)][:4]


rows = []
print("Generating golden-model vectors...")
for script, must in PY_STEPS:
    out = run([sys.executable, script], f"logs/py_{script[:-3]}.log")
    rows.append((f"python {script}", must in out, key_lines(out)))

for name, files, must in TESTS:
    print(f"Running {name} ...")
    out = run(["irun", "-clean"] + files + ["-top", name], f"logs/{name}.log")
    rows.append((name, must in out, key_lines(out)))

print("Running cocotb test ...")
out = run(["make"], "logs/cocotb.log")
rows.append(("cocotb test_rnn_vsm", ("FAIL=0" in out and "PASS=1" in out), [
    l.strip() for l in out.splitlines() if "Frames:" in l or "TESTS=" in l][:2]))

long_log = "long_run/long_sim.log"
if os.path.exists(long_log):
    with open(long_log, errors="replace") as f:
        txt = f.read()
    rows.append(("tb_long (saved log)", "LONG TEST PASSED" in txt, key_lines(txt)))

lines = [f"Regression run: {datetime.datetime.now():%Y-%m-%d %H:%M}", "=" * 70]
for name, ok, info in rows:
    lines.append(f"{'PASS' if ok else 'FAIL'}  {name}")
    for i in info:
        lines.append(f"        {i}")
n_pass = sum(1 for _, ok, _ in rows if ok)
lines += ["=" * 70, f"TOTAL: {n_pass} / {len(rows)} PASSED"]

with open("logs/regression_summary.txt", "w") as f:
    f.write("\n".join(lines) + "\n")
print("\n".join(lines))
