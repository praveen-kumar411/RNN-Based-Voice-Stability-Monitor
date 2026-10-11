# train_gru_np.py : NumPy-only GRU training with the exact hardware equations
# QAT: forward/backward use INT8/INT16-quantized weights, updates go to float weights (STE)
import json, time
import numpy as np

F, H, T = 8, 16, 60
np.random.seed(0)

# ---------------- synthetic dataset (simplified ITU-T G.107 E-model labels) ----------------
def make_sequence():
    feats, labels = np.zeros((T, F)), np.zeros(T)
    t, loss_hist = 0, []
    while t < T:
        seg_len = np.random.randint(10, 31)
        jit_m   = np.random.uniform(0, 1)
        loss_p  = np.random.choice([0.0, 0.02, 0.05, 0.1, 0.2, 0.35])
        snr_m   = np.random.uniform(0, 40)
        for _ in range(seg_len):
            if t >= T: break
            jitter = max(0.0, jit_m + 0.1 * np.random.randn())
            loss   = float(np.random.rand() < loss_p)
            snr    = snr_m + 2 * np.random.randn()
            energy = np.random.uniform(0.2, 1.0)
            spec   = np.random.randn(4) * 0.3 + snr / 40.0
            feats[t] = [jitter * 2, loss, energy, snr / 20.0] + list(spec)
            loss_hist.append(loss)
            recent_loss = np.mean(loss_hist[-10:])
            R = 93.2 - 40 * min(jitter, 1.5) - 150 * recent_loss - 1.2 * max(0, 25 - snr)
            R = float(np.clip(R, 0, 100))
            mos = 1 + 0.035 * R + 7e-6 * R * (R - 60) * (100 - R)
            labels[t] = np.clip((mos - 1) / 3.5, 0, 1)
            t += 1
    return feats, labels

def make_set(n):
    xs, ys = zip(*[make_sequence() for _ in range(n)])
    return np.stack(xs), np.stack(ys)

Xtr, Ytr = make_set(1500)
Xte, Yte = make_set(200)

# ---------------- model ----------------
def sig(a): return 1.0 / (1.0 + np.exp(-a))

def init_params():
    return {"W": np.random.randn(3, H, F) * 0.2,      # z, r, n input weights
            "U": np.random.randn(3, H, H) * 0.2,      # z, r, n hidden weights
            "b": np.zeros((4, H)),                    # bz, br, bnx, bnh
            "wo": np.random.randn(H) * 0.2,
            "bo": np.zeros(1)}

def fake_quant(P):
    Q = dict(P)
    for k in ("W", "U", "wo"): Q[k] = np.clip(np.round(P[k] * 64), -128, 127) / 64
    for k in ("b", "bo"):      Q[k] = np.clip(np.round(P[k] * 2048), -32768, 32767) / 2048
    return Q

def forward(P, X, keep=False):
    W, U, b, wo, bo = P["W"], P["U"], P["b"], P["wo"], P["bo"]
    B = X.shape[0]
    h, Y, cache = np.zeros((B, H)), np.zeros((B, T)), []
    for t in range(T):
        x = X[:, t]
        z  = sig(x @ W[0].T + h @ U[0].T + b[0])
        r  = sig(x @ W[1].T + h @ U[1].T + b[1])
        g  = h @ U[2].T + b[3]
        n  = np.tanh(x @ W[2].T + b[2] + r * g)
        hn = n + z * (h - n)                          # same as RTL gate combine
        y  = sig(hn @ wo + bo[0])
        if keep: cache.append((x, h, z, r, g, n, hn, y))
        h, Y[:, t] = hn, y
    return Y, cache

def backward(P, cache, Ylab):
    W, U, wo = P["W"], P["U"], P["wo"]
    G = {k: np.zeros_like(v) for k, v in P.items()}
    B = Ylab.shape[0]
    dh_next, scale = np.zeros((B, H)), 2.0 / (B * T)
    for t in reversed(range(T)):
        x, hp, z, r, g, n, hn, y = cache[t]
        dao = scale * (y - Ylab[:, t]) * y * (1 - y)
        G["wo"] += hn.T @ dao
        G["bo"][0] += dao.sum()
        dh  = dh_next + np.outer(dao, wo)
        dn, dz, dhp = dh * (1 - z), dh * (hp - n), dh * z
        dan = dn * (1 - n * n)
        G["W"][2] += dan.T @ x;  G["b"][2] += dan.sum(0)
        dr, dg = dan * g, dan * r
        G["U"][2] += dg.T @ hp;  G["b"][3] += dg.sum(0);  dhp += dg @ U[2]
        dar = dr * r * (1 - r)
        G["W"][1] += dar.T @ x;  G["U"][1] += dar.T @ hp;  G["b"][1] += dar.sum(0);  dhp += dar @ U[1]
        daz = dz * z * (1 - z)
        G["W"][0] += daz.T @ x;  G["U"][0] += daz.T @ hp;  G["b"][0] += daz.sum(0);  dhp += daz @ U[0]
        dh_next = dhp
    return G

# ---------------- optimizer ----------------
class Adam:
    def __init__(self, P, lr):
        self.lr, self.t = lr, 0
        self.m = {k: np.zeros_like(v) for k, v in P.items()}
        self.v = {k: np.zeros_like(v) for k, v in P.items()}
    def step(self, P, G):
        self.t += 1
        for k in P:
            self.m[k] = 0.9 * self.m[k] + 0.1 * G[k]
            self.v[k] = 0.999 * self.v[k] + 0.001 * G[k] ** 2
            mh = self.m[k] / (1 - 0.9 ** self.t)
            vh = self.v[k] / (1 - 0.999 ** self.t)
            P[k] -= self.lr * mh / (np.sqrt(vh) + 1e-8)

def clamp_ranges(P):                                  # keep inside INT8 Q1.6 / INT16 Q4.11
    for k in ("W", "U", "wo"): np.clip(P[k], -2.0, 127 / 64, out=P[k])
    for k in ("b", "bo"):      np.clip(P[k], -16.0, 32767 / 2048, out=P[k])

def train(P, epochs, lr, quant):
    opt = Adam(P, lr)
    for ep in range(epochs):
        t0, perm, total = time.time(), np.random.permutation(len(Xtr)), 0.0
        for i in range(0, len(Xtr), 64):
            idx = perm[i:i + 64]
            Pf = fake_quant(P) if quant else P
            Y, cache = forward(Pf, Xtr[idx], keep=True)
            G = backward(Pf, cache, Ytr[idx])
            norm = np.sqrt(sum((g ** 2).sum() for g in G.values()))
            if norm > 5.0:
                for k in G: G[k] *= 5.0 / norm
            opt.step(P, G)
            clamp_ranges(P)
            total += ((Y - Ytr[idx]) ** 2).mean() * len(idx)
        print(f"  epoch {ep+1:2d}  quant={quant}  train MSE = {total/len(Xtr):.5f}  ({time.time()-t0:.1f}s)")

def pearson(a, b):
    return float(np.corrcoef(np.ravel(a), np.ravel(b))[0, 1])

P = init_params()
print("Float training:");                train(P, 20, 1e-2, quant=False)
print("Quantization-aware fine-tune:");  train(P, 8, 3e-3, quant=True)

p_float = forward(P, Xte)[0]
p_fq    = forward(fake_quant(P), Xte)[0]

# ---------------- export INT weights ----------------
def q8(a):  return np.clip(np.round(a * 64),   -128,   127).astype(int).tolist()
def q16(a): return np.clip(np.round(a * 2048), -32768, 32767).astype(int).tolist()

params = {
    "Wz": q8(P["W"][0]), "Uz": q8(P["U"][0]),
    "Wr": q8(P["W"][1]), "Ur": q8(P["U"][1]),
    "Wn": q8(P["W"][2]), "Un": q8(P["U"][2]),
    "wo": q8(P["wo"]),
    "bz": q16(P["b"][0]), "br": q16(P["b"][1]),
    "bnx": q16(P["b"][2]), "bnh": q16(P["b"][3]),
    "bo": q16(P["bo"])[0],
}
with open("trained_params.json", "w") as f:
    json.dump(params, f)
print("Wrote trained_params.json")

# ---------------- bit-accurate INT model (same as RTL) ----------------
import golden_gru as g
g.export_params()                                     # weights.hex / biases.hex (trained)

p_int = np.zeros_like(p_float)
for s in range(len(Xte)):
    h = [0] * H
    for t in range(T):
        xq = [int(np.clip(round(float(v) * 2048), -32768, 32767)) for v in Xte[s, t]]
        h, score = g.gru_step(xq, h)
        p_int[s, t] = score / 2048

y = Yte
print("\n================ ACCURACY REPORT ================")
print(f"Float model      : Pearson r = {pearson(p_float, y):.4f}   MAE = {np.abs(p_float - y).mean():.4f}")
print(f"Fake-quant model : Pearson r = {pearson(p_fq, y):.4f}")
print(f"INT / RTL model  : Pearson r = {pearson(p_int, y):.4f}   MAE = {np.abs(p_int - y).mean():.4f}")
print(f"Quantization loss: delta r = {pearson(p_float, y) - pearson(p_int, y):.4f},"
      f"  mean |float - INT| = {np.abs(p_float - p_int).mean():.4f}")
