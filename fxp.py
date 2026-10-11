# fxp.py : fixed-point helpers that MUST match the RTL bit-for-bit
# Formats: weights INT8 Q1.6, activations INT16 Q4.11  (1.0 = 2048)
import math

FRAC = 11                 # Q4.11 fraction bits
ONE  = 1 << FRAC          # 2048 = 1.0
INT16_MIN, INT16_MAX = -32768, 32767

# LUT setup: 256 entries, x in [-8, 8), step 1/16
LUT_SIZE  = 256
LUT_SHIFT = 7             # Q4.11 >> 7  ->  steps of 1/16
X_MIN_Q, X_MAX_Q = -8 * ONE, 8 * ONE - 1    # -16384 .. 16383


def sat16(x):
    """Clamp to INT16 range (same as RTL saturation)."""
    return max(INT16_MIN, min(INT16_MAX, x))


def requant(acc, shift=6):
    """Round, arithmetic shift right, saturate. Matches requant.v."""
    return sat16((acc + (1 << (shift - 1))) >> shift)


def to_q(x):
    """Float -> Q4.11 integer (for building inputs)."""
    return sat16(int(round(x * ONE)))


def from_q(q):
    """Q4.11 integer -> float (for printing / error analysis)."""
    return q / ONE


# ---------------- sigmoid LUT ----------------
def build_sigmoid_lut():
    """Each entry stores sigmoid at the MIDDLE of its 1/16-wide bin."""
    lut = []
    for idx in range(LUT_SIZE):
        x_mid = (idx - 128 + 0.5) / 16.0
        lut.append(int(round(ONE / (1.0 + math.exp(-x_mid)))))   # 0 .. 2048
    return lut


SIG_LUT = build_sigmoid_lut()


def lut_index(x_q):
    """Clamp to [-8, 8) and convert to a 0..255 address. Matches act_lut.v."""
    xc = max(X_MIN_Q, min(X_MAX_Q, x_q))
    return (xc >> LUT_SHIFT) + 128


def sigmoid_q(x_q):
    return SIG_LUT[lut_index(x_q)]


def tanh_q(x_q):
    """tanh(x) = 2*sigmoid(2x) - 1, using the same LUT."""
    x2 = max(X_MIN_Q, min(X_MAX_Q, 2 * x_q))
    return 2 * SIG_LUT[lut_index(x2)] - ONE


# ---------------- outputs ----------------
def write_hex(lut, fname="sigmoid.hex"):
    with open(fname, "w") as f:
        for v in lut:
            f.write(f"{v & 0xFFFF:04x}\n")
    print(f"Wrote {fname} ({len(lut)} entries)")


def error_report():
    """Max / mean absolute error of the LUT vs. the true functions."""
    errs_s, errs_t = [], []
    for x_q in range(-16 * ONE, 16 * ONE, 4):          # sweep -16 .. 16
        x = from_q(x_q)
        errs_s.append(abs(from_q(sigmoid_q(x_q)) - 1 / (1 + math.exp(-x))))
        errs_t.append(abs(from_q(tanh_q(x_q)) - math.tanh(x)))
    print(f"sigmoid LUT: max err = {max(errs_s):.5f}, mean err = {sum(errs_s)/len(errs_s):.5f}")
    print(f"tanh via LUT: max err = {max(errs_t):.5f}, mean err = {sum(errs_t)/len(errs_t):.5f}")


def self_test():
    """Same vectors as tb_requant.v. Must all pass."""
    tests = [(0, 0), (131072, 2048), (-131072, -2048),
             (131103, 2048), (131104, 2049), (-131104, -2048), (-131105, -2049),
             (2097087, 32767), (2097120, 32767), (-2097152, -32768),
             (-2097185, -32768), (2**31 - 1, 32767), (-2**31, -32768)]
    bad = [(a, e, requant(a)) for a, e in tests if requant(a) != e]
    print("requant self-test:", "PASSED" if not bad else f"FAILED {bad}")


if __name__ == "__main__":
    self_test()
    write_hex(SIG_LUT)
    error_report()
    print("sigmoid(0) =", sigmoid_q(0), "(expect ~1024)")
    print("tanh(0)    =", tanh_q(0),    "(expect ~0)")
