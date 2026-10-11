# golden_gru.py : bit-accurate GRU model + test-vector generator
# Uses random weights (training comes later). Matches gru_core.v exactly.
import random
from fxp import requant, sigmoid_q, tanh_q, sat16

F, H, NF = 8, 16, 50            # features, hidden units, frames to test
random.seed(7)

def mat(rows, cols, lo=-40, hi=40):
    return [[random.randint(lo, hi) for _ in range(cols)] for _ in range(rows)]
def vec(n, lo=-1024, hi=1024):
    return [random.randint(lo, hi) for _ in range(n)]

# INT8 weights (Q1.6) and INT16 biases (Q4.11)
Wz, Uz = mat(H, F), mat(H, H)
Wr, Ur = mat(H, F), mat(H, H)
Wn, Un = mat(H, F), mat(H, H)
wo = vec(H, -40, 40)
bz, br, bnx, bnh = vec(H), vec(H), vec(H), vec(H)
bo = random.randint(-1024, 1024)
import json, os
if os.path.exists("trained_params.json"):
    _p = json.load(open("trained_params.json"))
    Wz, Uz, Wr, Ur = _p["Wz"], _p["Uz"], _p["Wr"], _p["Ur"]
    Wn, Un, wo     = _p["Wn"], _p["Un"], _p["wo"]
    bz, br, bnx, bnh, bo = _p["bz"], _p["br"], _p["bnx"], _p["bnh"], _p["bo"]
    print("golden_gru: using TRAINED weights")

def export_params():
    w = []
    for i in range(H): w += Wz[i] + Uz[i]        # z rows: W then U
    for i in range(H): w += Wr[i] + Ur[i]        # r rows: W then U
    for i in range(H): w += Un[i] + Wn[i]        # n rows: U FIRST, then W
    w += wo
    assert len(w) == 1168
    with open("weights.hex", "w") as f:
        for v in w: f.write(f"{v & 0xFF:02x}\n")
    b = bz + br + bnx + bnh + [bo]
    assert len(b) == 65
    with open("biases.hex", "w") as f:
        for v in b: f.write(f"{v & 0xFFFF:04x}\n")

def gru_step(x, h):
    z, r = [], []
    for i in range(H):
        acc = (bz[i] << 6) + sum(Wz[i][j]*x[j] for j in range(F)) + sum(Uz[i][k]*h[k] for k in range(H))
        z.append(sigmoid_q(requant(acc, 6)))
    for i in range(H):
        acc = (br[i] << 6) + sum(Wr[i][j]*x[j] for j in range(F)) + sum(Ur[i][k]*h[k] for k in range(H))
        r.append(sigmoid_q(requant(acc, 6)))
    h_new = []
    for i in range(H):
        a   = requant((bnh[i] << 6) + sum(Un[i][k]*h[k] for k in range(H)), 6)
        ra  = requant(r[i] * a, 11)
        acc = ((ra + bnx[i]) << 6) + sum(Wn[i][j]*x[j] for j in range(F))
        n   = tanh_q(requant(acc, 6))
        h_new.append(sat16(n + requant(z[i] * (h[i] - n), 11)))
    acc = (bo << 6) + sum(wo[k]*h_new[k] for k in range(H))
    return h_new, sigmoid_q(requant(acc, 6))

def pack(vals):                       # element 0 goes in the LSB (rightmost)
    return "".join(f"{v & 0xFFFF:04x}" for v in reversed(vals))

if __name__ == "__main__":
    export_params()
    h = [0] * H                       # state after flush
    with open("x_vectors.hex", "w") as fx, open("exp_scores.hex", "w") as fs, \
         open("exp_h.hex", "w") as fh:
        for frame in range(NF):
            if   frame == 10: x = [32767] * F          # corner: saturated high
            elif frame == 11: x = [-32768] * F         # corner: saturated low
            else:             x = [random.randint(-4096, 4096) for _ in range(F)]
            h, score = gru_step(x, h)
            fx.write(pack(x) + "\n")
            fs.write(f"{score & 0xFFFF:04x}\n")
            fh.write(pack(h) + "\n")
            if frame < 3: print(f"frame {frame}: score = {score} ({score/2048:.3f})")
    print("Wrote weights.hex, biases.hex, x_vectors.hex, exp_scores.hex, exp_h.hex")
