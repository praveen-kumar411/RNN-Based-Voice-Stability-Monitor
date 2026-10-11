# golden_corners.py : expected outputs for reset / flush corner cases
import random
from golden_gru import gru_step, export_params, pack, F, H

K, NF = 2, 61
random.seed(21)
export_params()

xs = [[random.randint(-6000, 6000) for _ in range(F)] for _ in range(NF)]
xs[5], xs[6]   = [32767] * F, [-32768] * F        # saturated, before reset
xs[25], xs[45] = [32767] * F, [-32768] * F        # saturated, after reset / flush

# frame 20 is aborted by reset -> no output.  Each segment starts fresh.
segments = [range(0, 20), range(21, 41), range(41, 61)]

scores = {}
for seg in segments:
    h = [0] * H
    for f in seg:
        h, scores[f] = gru_step(xs[f], h)

vals = sorted(scores.values())
T_LO = vals[len(vals) // 2]
T_HI = T_LO + 64

exp, irqs = {}, 0
for seg in segments:
    a, alert = 2048 << 12, 0
    for f in seg:
        a += ((scores[f] << 12) - a) >> K
        avg, irq = a >> 12, 0
        if not alert and avg < T_LO:
            alert, irq = 1, 1
            irqs += 1
        elif alert and avg > T_HI:
            alert = 0
        exp[f] = (scores[f], avg, alert, irq)

with open("corner_x.hex", "w") as fx, open("corner_exp.hex", "w") as fe:
    for f in range(NF):
        fx.write(pack(xs[f]) + "\n")
        s, avg, al, irq = exp.get(f, (0, 0, 0, 0))
        fe.write(f"{s:04x}{avg:04x}{al:01x}{irq:01x}\n")
with open("corner_cfg.hex", "w") as fc:
    fc.write(f"{T_LO:04x}\n{T_HI:04x}\n{K:04x}\n")
print(f"T_LO={T_LO} T_HI={T_HI}  expected IRQs={irqs}")
