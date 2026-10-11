# golden_long.py : 1-hour call (180k frames @ 20 ms), bit-accurate expected outputs
import random
from golden_gru import gru_step, export_params, pack, F, H

NF, K, SEG = 180000, 3, 3000          # SEG = 3000 frames = 1 minute per segment
random.seed(99)
export_params()

# pass 1: inputs + scores
h, scores = [0] * H, []
with open("long_x.hex", "w") as fx:
    for f in range(NF):
        if f % 7777 == 0:   x = [32767] * F                    # periodic saturation
        elif f % 7777 == 1: x = [-32768] * F
        else:
            noisy = (f // SEG) % 2
            amp, off = (6000, -3000) if noisy else (1000, 0)
            x = [max(-32768, min(32767, off + random.randint(-amp, amp))) for _ in range(F)]
        h, s = gru_step(x, h)
        scores.append(s)
        fx.write(pack(x) + "\n")
        if f % 20000 == 0: print(f"  generated frame {f}")

# thresholds from the average's range
a, avgs = 2048 << 12, []
for s in scores:
    a += ((s << 12) - a) >> K
    avgs.append(a >> 12)
lo, hi = min(avgs[100:]), max(avgs[100:])
T_LO = (lo + hi) // 2
T_HI = T_LO + max(1, (hi - lo) // 8)

# pass 2: EMA + alert expected outputs
a, alert, irqs = 2048 << 12, 0, 0
with open("long_exp.hex", "w") as fe:
    for s in scores:
        a += ((s << 12) - a) >> K
        avg, irq = a >> 12, 0
        if not alert and avg < T_LO:
            alert, irq = 1, 1
            irqs += 1
        elif alert and avg > T_HI:
            alert = 0
        fe.write(f"{s:04x}{avg:04x}{alert:01x}{irq:01x}\n")
with open("long_cfg.hex", "w") as fc:
    fc.write(f"{T_LO:04x}\n{T_HI:04x}\n{K:04x}\n")
print(f"Done: {NF} frames, T_LO={T_LO}, T_HI={T_HI}, expected IRQs={irqs}")
