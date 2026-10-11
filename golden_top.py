# golden_top.py : full-chip expected outputs (GRU + EMA + alert)
import random
from golden_gru import gru_step, export_params, pack, F, H

NF, K = 100, 2
random.seed(11)
export_params()                                   # weights.hex / biases.hex

# input story: calm and noisy segments alternate every 25 frames
xs = []
for f in range(NF):
    if   f == 10: x = [32767] * F
    elif f == 11: x = [-32768] * F
    else:
        noisy = (f // 25) % 2
        amp, off = (6000, -3000) if noisy else (1000, 0)
        x = [max(-32768, min(32767, off + random.randint(-amp, amp))) for _ in range(F)]
    xs.append(x)

h, scores = [0] * H, []
for x in xs:
    h, s = gru_step(x, h)
    scores.append(s)

# pick thresholds from the average's range so alerts really happen
a, avgs = 2048 << 12, []
for s in scores:
    a += ((s << 12) - a) >> K
    avgs.append(a >> 12)
lo, hi = min(avgs[5:]), max(avgs[5:])
T_LO = (lo + hi) // 2
T_HI = T_LO + max(1, (hi - lo) // 8)

a, alert, irqs = 2048 << 12, 0, 0
with open("top_vectors.hex", "w") as fv, open("top_x.hex", "w") as fx:
    for x, s in zip(xs, scores):
        a += ((s << 12) - a) >> K
        avg, irq = a >> 12, 0
        if not alert and avg < T_LO:
            alert, irq = 1, 1
            irqs += 1
        elif alert and avg > T_HI:
            alert = 0
        fv.write(f"{s:04x}{avg:04x}{alert:01x}{irq:01x}\n")
        fx.write(pack(x) + "\n")
with open("top_cfg.hex", "w") as fc:
    fc.write(f"{T_LO:04x}\n{T_HI:04x}\n{K:04x}\n")
print(f"T_LO={T_LO} T_HI={T_HI} K={K}  expected IRQs={irqs}")
if irqs == 0: print("WARNING: no IRQs - change seed")
