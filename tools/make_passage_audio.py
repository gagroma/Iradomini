# Synthesizes the sounds of the road between churches (scripts/passage.gd). No recordings.
#   python -I tools/make_passage_audio.py audio
# Writes:
#   record.wav  the music the stalker carries: the hymn "Old Hundredth" (Genevan Psalter, 1551 - public domain),
#               harmonized here, on a wheezing reed organ, warped and crackling like a worn gramophone record. Loops.
#   wind.wav    night wind over the graveyard. Loops.
#   twig.wav    something small snapping out in the dark.
import numpy as np, struct, sys, os
from scipy.signal import fftconvolve, butter, lfilter

SR = 22050
rng = np.random.default_rng(5)
OUT = sys.argv[1] if len(sys.argv) > 1 else "audio"
TAIL = 4.0


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def track(notes, beat, glide=0.01):
    """notes: [(midi or None, beats)] -> per-sample pitch and loudness."""
    n = int((sum(b for _, b in notes) * beat + TAIL) * SR)
    f0 = np.zeros(n); amp = np.zeros(n)
    pos = 0; last = None; rest_before = True
    for m, b in notes:
        L = int(b * beat * SR)
        if m is None:
            f0[pos:pos + L] = last if last else 100.0
            pos += L; rest_before = True
            continue
        f = hz(m)
        seg = np.full(L, f)
        if last is not None and not rest_before:
            g = min(int(glide * SR), L); seg[:g] = np.linspace(last, f, g)
        f0[pos:pos + L] = seg
        env = np.ones(L)
        a = min(int(0.12 * SR), L); r = min(int(0.2 * SR), L)
        env[:a] = np.linspace(0.0 if rest_before else 0.6, 1.0, a)
        env[-r:] *= np.linspace(1.0, 0.75, r)
        amp[pos:pos + L] = env
        last = f; pos += L; rest_before = False
    f0[pos:] = last
    k = int(0.05 * SR)
    return f0, np.convolve(amp, np.ones(k) / k, mode="same")


def drift(n, cents):
    d = np.cumsum(rng.normal(0, 1, n)); d -= np.linspace(d[0], d[-1], n)
    return 2 ** (cents * d / (np.max(np.abs(d)) + 1e-9) / 1200.0)


def reed(tr, detune, wow):
    """One voice of a wheezy reed organ (harmonium)."""
    f0, amp = tr
    n = len(f0); t = np.arange(n) / SR
    f = f0 * 2 ** (detune / 1200.0) * drift(n, 3.0) * wow
    phase = 2 * np.pi * np.cumsum(f) / SR
    out = np.zeros(n)
    for k in range(1, int(5000 / np.min(f0)) + 1):
        out += k ** -1.1 * np.exp(-k * f / 2200.0) * np.sin(k * phase + 0.3 * k)
    bellows = 1.0 + 0.07 * np.sin(2 * np.pi * 0.23 * t)
    return out * amp * bellows


def band(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return lfilter(b, a, x)


def write(name, x, loop=False):
    x = x - np.mean(x)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(pcm)) + pcm
    if loop:
        n = len(pcm) // 2
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0) + struct.pack("<6I", 0, 0, 0, n - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name), "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)
    print(f"{name}  {len(x) / SR:.1f} s", flush=True)


# ---------------------------------------------------------------- the hymn, harmonized in four parts
PCS = {"I": [7, 11, 2], "IV": [0, 4, 7], "V": [2, 6, 9], "vi": [4, 7, 11], "ii": [9, 0, 4]}
ROOT = {"I": 43, "IV": 48, "V": 50, "vi": 40, "ii": 45}
LINES = [[67, 67, 66, 64, 62, 67, 69, 71], [71, 71, 71, 69, 67, 72, 71, 69],
         [67, 69, 71, 69, 67, 64, 66, 67], [74, 71, 67, 69, 72, 71, 69, 67]]
DURS = [2, 1, 1, 1, 1, 1, 1, 3]


def pick(pcs, lo, hi, near):
    c = [p for p in range(lo, hi + 1) if p % 12 in pcs]
    if not c:
        c = [p for p in range(lo - 6, hi + 7) if p % 12 in pcs]
    return min(c, key=lambda p: abs(p - near))


def hymn_parts():
    S, A, T, B = [], [], [], []
    pa, pt = 62, 55
    for line in LINES:
        for i, m in enumerate(line):
            d = DURS[i]
            if i == len(line) - 1:
                ch = "I" if m % 12 in PCS["I"] else "V"
            else:
                ch = next(c for c in ["I", "IV", "V", "vi", "ii"] if m % 12 in PCS[c])
            bass = ROOT[ch]
            alto = pick(PCS[ch], max(55, m - 9), m - 1, pa)
            ten = pick(PCS[ch], max(bass + 3, 50), min(alto - 1, 65), pt)
            S.append((m, d)); A.append((alto, d)); T.append((ten, d)); B.append((bass, d))
            pa, pt = alto, ten
        for p in (S, A, T, B):
            p.append((None, 1))
    return S, A, T, B


def record():
    S, A, T, B = hymn_parts()
    beat = 0.95
    body = int(sum(b for _, b in S) * beat * SR)
    n = int((sum(b for _, b in S) * beat + TAIL) * SR)
    t = np.arange(n) / SR
    wow = 1.0 + 0.004 * np.sin(2 * np.pi * 0.55 * t) + 0.0015 * np.sin(2 * np.pi * 7.0 * t)    # warped disc, worn motor
    mix = 0
    for part, gain in ((S, 0.6), (A, 0.4), (T, 0.4), (B, 0.55)):
        tr = track(part, beat)
        mix = mix + gain * reed(tr, rng.uniform(-6, 6), wow) + gain * 0.5 * reed(tr, rng.uniform(8, 14), wow)
    # a small room around the organ
    ir_n = int(2.5 * SR); tt = np.arange(ir_n) / SR
    ir = rng.normal(0, 1, ir_n) * np.exp(-tt / 0.6)
    b, a = butter(1, 3000 / (SR / 2), "low"); ir = lfilter(b, a, ir); ir[:int(0.02 * SR)] = 0.0
    wet = fftconvolve(mix, ir)[:n]
    x = 0.6 * mix / np.max(np.abs(mix)) + 0.6 * wet / np.max(np.abs(wet))
    # loop: the echo of the last chord runs on under the first
    x[:n - body] += x[body:]
    x = x[:body]
    x = np.concatenate([x, x])                                       # filter two turns, keep the second: no click at the seam
    x = band(x, 220, 3000, 3)[body:]                                 # the thin horn of an old gramophone
    x = np.tanh(2.0 * x / np.max(np.abs(x)))
    hiss = band(rng.normal(0, 1, body), 1000, 6000) * 0.035
    crackle = np.zeros(body)
    pops = rng.random(body) < 30.0 / SR
    crackle[pops] = rng.normal(0, 1, pops.sum()) * rng.uniform(0.1, 0.6, pops.sum())
    crackle = band(crackle, 800, 7000) * 1.5
    write("record.wav", x + hiss + crackle, loop=True)


def wind():
    secs = 28.0; fade = 3.0
    n = int((secs + fade) * SR); t = np.arange(n) / SR
    low = band(rng.normal(0, 1, n), 90, 700)
    mid = band(rng.normal(0, 1, n), 500, 1400)
    # slow swells; every period divides the loop length, so the swell itself loops
    sw = 0.55 + 0.25 * np.sin(2 * np.pi * t / 14.0) + 0.2 * np.sin(2 * np.pi * t / 7.0 + 1.3) + 0.1 * np.sin(2 * np.pi * t / 4.0 + 0.4)
    whistle = band(rng.normal(0, 1, n), 620, 760, 2) * np.clip(sw - 0.6, 0, 1) * 2.0
    x = low * sw + 0.35 * mid * sw ** 2 + 0.25 * whistle
    f = int(fade * SR); body = int(secs * SR)
    k = np.linspace(0, 1, f)
    x[:f] = x[:f] * k + x[body:body + f] * (1 - k)                  # crossfade the end into the start
    write("wind.wav", x[:body], loop=True)


def twig():
    n = int(0.35 * SR); x = np.zeros(n)
    for at, g in ((0.0, 1.0), (0.035, 0.5), (0.11, 0.3)):
        i = int(at * SR); m = n - i
        x[i:] += g * rng.normal(0, 1, m) * np.exp(-np.arange(m) / (0.012 * SR))
    write("twig.wav", band(x, 1200, 6500))


record()
wind()
twig()
