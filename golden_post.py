# golden_post.py : EMA + hysteresis alert, bit-accurate to ema.v / alert.v
import random

K, T_LO, T_HI = 3, 1024, 1280      # alpha = 1/8, alert below 0.5, clear above 0.625
random.seed(3)

def seg(center, n, amp):
    return [max(0, min(2048, center + random.randint(-amp, amp))) for _ in range(n)]

# test story: good -> bad call -> wobble near threshold -> good -> hard drop -> recover
scores  = seg(1800, 40, 100) + seg(300, 60, 150)
scores += [1000 if i % 2 else 1300 for i in range(40)]
scores += seg(1900, 60, 80) + [0] * 40 + [2048] * 60

avg_ext, alert, irq_count = 2048 << 12, 0, 0
with open("post_vectors.hex", "w") as f:
    for s in scores:
        avg_ext += ((s << 12) - avg_ext) >> K
        avg = avg_ext >> 12
        irq = 0
        if not alert and avg < T_LO:
            alert, irq = 1, 1
            irq_count += 1
        elif alert and avg > T_HI:
            alert = 0
        f.write(f"{s:04x}{avg:04x}{alert:01x}{irq:01x}\n")   # score|avg|alert|irq
print(f"Wrote post_vectors.hex ({len(scores)} frames), expected IRQs = {irq_count}")
