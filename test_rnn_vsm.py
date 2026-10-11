# test_rnn_vsm.py : cocotb testbench for rnn_vsm_top
# Drives the chip through its pins (registers + AXI-Stream) and checks every frame
# against the Python golden model, computed live (no vector files).
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer
import golden_gru as g

(A_CTRL, A_STATUS, A_TLO, A_THI, A_K, A_SCORE,
 A_AVG, A_WADDR, A_WDATA, A_BADDR, A_BDATA, A_FCNT) = range(12)
K, NF = 2, 60


def s16(v):
    v &= 0xFFFF
    return v - 65536 if v & 0x8000 else v


async def reg_write(dut, addr, data):
    await FallingEdge(dut.clk)
    dut.reg_wr.value = 1
    dut.reg_addr.value = addr
    dut.reg_wdata.value = data & 0xFFFF
    await FallingEdge(dut.clk)
    dut.reg_wr.value = 0


async def reg_read(dut, addr):
    dut.reg_addr.value = addr
    await Timer(1, "ns")
    return int(dut.reg_rdata.value)


async def send_frame(dut, x):
    """AXI-Stream master: 8 words, TLAST on the last, respects TREADY."""
    for j, v in enumerate(x):
        await FallingEdge(dut.clk)
        dut.s_tvalid.value = 1
        dut.s_tdata.value = v & 0xFFFF
        dut.s_tlast.value = int(j == len(x) - 1)
        while not int(dut.s_tready.value):
            await FallingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.s_tvalid.value = 0
    dut.s_tlast.value = 0


def weight_list():
    w = []
    for i in range(g.H):
        w += g.Wz[i] + g.Uz[i]
    for i in range(g.H):
        w += g.Wr[i] + g.Ur[i]
    for i in range(g.H):
        w += g.Un[i] + g.Wn[i]
    return w + g.wo


def make_frames():
    random.seed(5)
    xs = []
    for f in range(NF):
        if f == 7:
            x = [32767] * g.F                      # saturated high
        elif f == 8:
            x = [-32768] * g.F                     # saturated low
        else:
            noisy = (f // 15) % 2
            amp, off = (6000, -3000) if noisy else (1000, 0)
            x = [max(-32768, min(32767, off + random.randint(-amp, amp))) for _ in range(g.F)]
        xs.append(x)
    return xs


@cocotb.test()
async def test_bit_exact_stream(dut):
    """Load weights via registers, stream frames, compare score/avg/alert/irq per frame."""
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    for sig in (dut.s_tvalid, dut.s_tlast, dut.s_tdata, dut.reg_wr, dut.reg_addr, dut.reg_wdata):
        sig.value = 0
    dut.rst.value = 1
    for _ in range(3):
        await FallingEdge(dut.clk)
    dut.rst.value = 0

    # thresholds chosen from the golden average trajectory
    xs = make_frames()
    h, scores = [0] * g.H, []
    for x in xs:
        h, s = g.gru_step(x, h)
        scores.append(s)
    a, avgs = 2048 << 12, []
    for s in scores:
        a += ((s << 12) - a) >> K
        avgs.append(a >> 12)
    lo, hi = min(avgs[3:]), max(avgs[3:])
    T_LO = (lo + hi) // 2
    T_HI = T_LO + max(1, (hi - lo) // 8)

    # load weights and biases through the register map
    w = weight_list()
    b = g.bz + g.br + g.bnx + g.bnh + [g.bo]
    await reg_write(dut, A_WADDR, 0)
    for v in w:
        await reg_write(dut, A_WDATA, v & 0xFF)
    await reg_write(dut, A_BADDR, 0)
    for v in b:
        await reg_write(dut, A_BDATA, v)
    await reg_write(dut, A_TLO, T_LO)
    await reg_write(dut, A_THI, T_HI)
    await reg_write(dut, A_K, K)
    await reg_write(dut, A_CTRL, 0x7)                       # EN | FLUSH | IRQ_EN
    dut._log.info(f"Loaded {len(w)} weights + {len(b)} biases, T_LO={T_LO} T_HI={T_HI} K={K}")

    # stream frames, golden model runs alongside
    h, a, alert = [0] * g.H, 2048 << 12, 0
    errors, irq_gold, irq_dut = 0, 0, 0
    for f, x in enumerate(xs):
        await send_frame(dut, x)

        h, s = g.gru_step(x, h)                             # expected values
        a += ((s << 12) - a) >> K
        avg, irq = a >> 12, 0
        if not alert and avg < T_LO:
            alert, irq = 1, 1
            irq_gold += 1
        elif alert and avg > T_HI:
            alert = 0

        await RisingEdge(dut.done)                          # core finished the frame
        for _ in range(3):                                  # EMA, then alert, update
            await FallingEdge(dut.clk)
        rs = s16(await reg_read(dut, A_SCORE))
        ra = s16(await reg_read(dut, A_AVG))
        st = await reg_read(dut, A_STATUS)
        d_alert, d_irq = (st >> 2) & 1, (st >> 1) & 1

        if (rs, ra, d_alert, d_irq) != (s, avg, alert, irq):
            errors += 1
            dut._log.error(f"frame {f}: DUT score={rs} avg={ra} alert={d_alert} irq={d_irq} | "
                           f"golden score={s} avg={avg} alert={alert} irq={irq}")
        if d_irq:
            irq_dut += 1
            await reg_write(dut, A_STATUS, 0x2)             # W1C clear

    fcnt = await reg_read(dut, A_FCNT)
    dut._log.info(f"Frames: {fcnt}/{NF}  IRQs DUT/golden: {irq_dut}/{irq_gold}  errors: {errors}")
    assert fcnt == NF, "frame counter mismatch"
    assert irq_dut == irq_gold, "IRQ count mismatch"
    assert errors == 0, f"{errors} frames did not match the golden model"
    dut._log.info("*** COCOTB: ALL FRAMES BIT-EXACT vs PYTHON GOLDEN MODEL ***")
