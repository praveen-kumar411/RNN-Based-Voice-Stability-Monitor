# gen_lut_vectors.py : expected outputs for act_lut.v, taken from fxp.py
import random
from fxp import sigmoid_q, tanh_q

random.seed(1)
N = 1000
edges = [0, 1, -1, 127, 128, -128, -129, 2048, -2048, 8191, 8192, -8192, -8193,
         16383, 16384, -16384, -16385, 32767, -32768]

cases = [(m, x) for m in (0, 1) for x in edges]          # edge cases, both modes
while len(cases) < N:                                    # fill the rest randomly
    cases.append((random.randint(0, 1), random.randint(-32768, 32767)))

with open("lut_vectors.hex", "w") as f:
    for m, x in cases:
        y = sigmoid_q(x) if m == 0 else tanh_q(x)
        f.write(f"{m:01x}{x & 0xFFFF:04x}{y & 0xFFFF:04x}\n")   # mode | x | expected
print(f"Wrote lut_vectors.hex ({N} vectors)")
