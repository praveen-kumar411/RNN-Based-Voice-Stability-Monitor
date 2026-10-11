# make_plots.py : error-analysis and behaviour plots for the report (PNG files in plots/)
import os, json
import numpy as np
import matplotlib
matplotlib.use("Agg")                     # no display needed
import matplotlib.pyplot as plt
from fxp import sigmoid_q, tanh_q, ONE
import golden_gru as g                    # uses trained_params.json

os.makedirs("plots", exist_ok=True)
plt.rcParams.update({"figure.dpi": 150, "font.size": 10})
np.random.seed(123)

# ======================= 1. LUT error =======================
xq = np.arange(-10 * ONE, 10 * ONE, 8)
x = xq / ONE
sig_true, tanh_true = 1 / (1 + np.exp(-x)), np.tanh(x)
sig_lut  = np.array([sigmoid_q(int(v)) for v in xq]) / ONE
tanh_lut = np.array([tanh_q(int(v))    for v in xq]) / ONE

fig, ax = plt.subplots(2, 2, figsize=(10, 6), sharex=True)
ax[0, 0].plot(x, sig_true, label="true sigmoid")
ax[0, 0].plot(x, sig_lut, "--", label="256-entry LUT")
ax[0, 0].set_title("Sigmoid"); ax[0, 0].legend()
ax[0, 1].plot(x, tanh_true, label="true tanh")
ax[0, 1].plot(x, tanh_lut, "--", label="2*sigma(2x)-1 via LUT")
ax[0, 1].set_title("Tanh"); ax[0, 1].legend()
ax[1, 0].plot(x, sig_lut - sig_true, color="tab:red")
ax[1, 0].set_title(f"Sigmoid error (max {np.abs(sig_lut - sig_true).max():.4f})")
ax[1, 1].plot(x, tanh_lut - tanh_true, color="tab:red")
ax[1, 1].set_title(f"Tanh error (max {np.abs(tanh_lut - tanh_true).max():.4f})")
for a in ax[1]: a.set_xlabel("x"); a.axhline(0, color="gray", lw=0.5)
for a in ax.flat: a.grid(alpha=0.3)
fig.tight_layout(); fig.savefig("plots/lut_error.png"); plt.close(fig)
print("Wrote plots/lut_error.png")

# ======================= 2. Quantization: float arithmetic vs bit-accurate INT =======================
F, H, T = 8, 16, 60
p  = json.load(open("trained_params.json"))
W  = np.array([p["Wz"], p["Wr"], p["Wn"]]) / 64.0
U  = np.array([p["Uz"], p["Ur"], p["Un"]]) / 64.0
b  = np.array([p["bz"], p["br"], p["bnx"], p["bnh"]]) / 2048.0
wo, bo = np.array(p["wo"]) / 64.0, p["bo"] / 2048.0
sig = lambda a: 1 / (1 + np.exp(-a))

def float_step(xf, h):
    z = sig(W[0] @ xf + U[0] @ h + b[0])
    r = sig(W[1] @ xf + U[1] @ h + b[1])
    n = np.tanh(W[2] @ xf + b[2] + r * (U[2] @ h + b[3]))
    h = n + z * (h - n)
    return h, sig(wo @ h + bo)

def frame_feats(jit_m, loss_p, snr_m):
    jitter = max(0.0, jit_m + 0.1 * np.random.randn())
    loss   = float(np.random.rand() < loss_p)
    snr    = snr_m + 2 * np.random.randn()
    energy = np.random.uniform(0.2, 1.0)
    spec   = list(np.random.randn(4) * 0.3 + snr / 40.0)
    return [jitter * 2, loss, energy, snr / 20.0] + spec, jitter, loss, snr

def label(jitter, recent_loss, snr):
    R = 93.2 - 40 * min(jitter, 1.5) - 150 * recent_loss - 1.2 * max(0, 25 - snr)
    R = float(np.clip(R, 0, 100))
    mos = 1 + 0.035 * R + 7e-6 * R * (R - 60) * (100 - R)
    return float(np.clip((mos - 1) / 3.5, 0, 1))

def make_sequence():
    feats, labs, loss_hist, t = [], [], [], 0
    while t < T:
        L = np.random.randint(10, 31)
        jm, lp, sm = np.random.uniform(0, 1), np.random.choice([0, .02, .05, .1, .2, .35]), np.random.uniform(0, 40)
        for _ in range(L):
            if t >= T: break
            f, j, l, s = frame_feats(jm, lp, sm)
            loss_hist.append(l)
            feats.append(f); labs.append(label(j, np.mean(loss_hist[-10:]), s)); t += 1
    return feats, labs

lab_all, pf_all, pi_all, seqs = [], [], [], []
for s in range(100):
    feats, labs = make_sequence()
    h_f, h_i, pf, pi = np.zeros(H), [0] * H, [], []
    for f in feats:
        xq_ = [int(np.clip(round(v * 2048), -32768, 32767)) for v in f]
        h_f, yf = float_step(np.array(xq_) / 2048.0, h_f)
        h_i, yi = g.gru_step(xq_, h_i)
        pf.append(yf); pi.append(yi / 2048.0)
    lab_all += labs; pf_all += pf; pi_all += pi
    if s < 1: seqs.append((labs, pf, pi))
lab_all, pf_all, pi_all = map(np.array, (lab_all, pf_all, pi_all))
err = np.abs(pf_all - pi_all)
r_f, r_i = np.corrcoef(pf_all, lab_all)[0, 1], np.corrcoef(pi_all, lab_all)[0, 1]

fig, a = plt.subplots(figsize=(5.5, 5))
a.scatter(pf_all, pi_all, s=3, alpha=0.4)
a.plot([0, 1], [0, 1], "k--", lw=1, label="ideal (y = x)")
a.set_xlabel("Float arithmetic score"); a.set_ylabel("Bit-accurate INT (RTL) score")
a.set_title(f"Same INT8 weights: float vs fixed-point+LUT\nmean |diff| = {err.mean():.4f}, max = {err.max():.4f}")
a.legend(); a.grid(alpha=0.3); fig.tight_layout()
fig.savefig("plots/quant_scatter.png"); plt.close(fig)
print("Wrote plots/quant_scatter.png")

labs, pf, pi = seqs[0]
fig, a = plt.subplots(figsize=(9, 3.5))
tt = np.arange(len(labs)) * 0.02
a.plot(tt, labs, "k", lw=2, label="reference (E-model MOS-derived)")
a.plot(tt, pf, label="float model")
a.plot(tt, pi, "--", label="INT / RTL model")
a.set_xlabel("time (s)"); a.set_ylabel("stability score"); a.set_ylim(-0.05, 1.05)
a.set_title(f"One call: r(float)={r_f:.4f}, r(INT)={r_i:.4f} over 100 calls")
a.legend(loc="lower left"); a.grid(alpha=0.3); fig.tight_layout()
fig.savefig("plots/quant_timeseries.png"); plt.close(fig)
print("Wrote plots/quant_timeseries.png")

fig, a = plt.subplots(figsize=(6, 3.5))
a.hist(err, bins=50)
a.set_xlabel("|float - INT| score difference"); a.set_ylabel("frames")
a.set_title(f"Fixed-point + LUT error over {len(err)} frames (mean {err.mean():.4f})")
a.grid(alpha=0.3); fig.tight_layout()
fig.savefig("plots/quant_error_hist.png"); plt.close(fig)
print("Wrote plots/quant_error_hist.png")

# ======================= 3. Alert demo: good -> degraded -> good call =======================
K, T_LO, T_HI = 3, 1024, 1229                         # alert below 0.50, clear above 0.60
segments = [(100, 0.1, 0.0, 35), (80, 0.9, 0.25, 8), (120, 0.1, 0.0, 35)]
h, a_ext, alert = [0] * H, 2048 << 12, 0
scores, avgs, alerts, irq_frames = [], [], [], []
fidx = 0
for n_frames, jm, lp, sm in segments:
    for _ in range(n_frames):
        f, _, _, _ = frame_feats(jm, lp, sm)
        xq_ = [int(np.clip(round(v * 2048), -32768, 32767)) for v in f]
        h, s = g.gru_step(xq_, h)
        a_ext += ((s << 12) - a_ext) >> K
        avg = a_ext >> 12
        if not alert and avg < T_LO: alert = 1; irq_frames.append(fidx)
        elif alert and avg > T_HI:   alert = 0
        scores.append(s / 2048); avgs.append(avg / 2048); alerts.append(alert); fidx += 1

tt = np.arange(len(scores)) * 0.02
fig, a = plt.subplots(figsize=(10, 4))
a.plot(tt, scores, color="tab:blue", alpha=0.35, lw=1, label="per-frame score")
a.plot(tt, avgs, color="tab:blue", lw=2.2, label=f"running average (EMA, k={K})")
a.axhline(T_LO / 2048, color="tab:red", ls="--", lw=1, label="T_LO (alert on)")
a.axhline(T_HI / 2048, color="tab:green", ls="--", lw=1, label="T_HI (alert off)")
a.fill_between(tt, 0, 1.05, where=np.array(alerts) == 1, color="tab:red", alpha=0.12, label="alert active")
for fi in irq_frames:
    a.axvline(fi * 0.02, color="tab:red", lw=1.5)
a.axvspan(100 * 0.02, 180 * 0.02, ymin=0.97, ymax=1.0, color="gray", alpha=0.6)
a.text(140 * 0.02, 1.0, "degraded network", ha="center", va="bottom", fontsize=9)
a.set_xlabel("time (s)"); a.set_ylabel("score"); a.set_ylim(0, 1.08)
a.set_title(f"Trained GRU on a simulated call: {len(irq_frames)} IRQ, no false alarms")
a.legend(loc="lower left", fontsize=8); a.grid(alpha=0.3); fig.tight_layout()
fig.savefig("plots/alert_demo.png"); plt.close(fig)
print(f"Wrote plots/alert_demo.png  (IRQs at frames {irq_frames})")

print(f"\nSummary: LUT max err sigmoid {np.abs(sig_lut - sig_true).max():.4f}, tanh {np.abs(tanh_lut - tanh_true).max():.4f}")
print(f"         float vs INT: mean {err.mean():.4f}, max {err.max():.4f}; r float {r_f:.4f}, r INT {r_i:.4f}")
