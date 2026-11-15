import numpy as np, struct, sys, os

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else "audio"
rng = np.random.default_rng(1717)

# Loudness of the sounds this replaces, so the game's mix stays the same (RMS dBFS).
TARGET_RMS = {
    "step1": -14.2, "step2": -13.9, "demon_step": -12.4, "demon_breath": -17.1, "demon_scream": -5.9,
    "demon_notice": -15.7, "heartbeat": -14.5, "drone": -10.2, "choir_rev": -20.8, "hit": -9.6,
    "candle_out": -23.8, "pickup": -19.9, "place": -18.2, "burn": -23.3, "banish": -17.3,
    "door_slam": -9.3, "door_creak": -17.4, "lighter_open": -22.8, "lighter_strike": -17.9,
    "lighter_close": -22.7, "prayer_murmur": -22.9, "sigh": -24.9, "book_open": -22.5,
    "book_close": -25.0, "clatter": -20.2, "ending": -16.3, "swing": -18.1,
}


# ------------------------------------------------------------------ basics

def t(sec):
    return np.arange(int(SR * sec)) / SR


def n_of(sec):
    return int(SR * sec)


def noise(sec):
    return rng.uniform(-1.0, 1.0, n_of(sec))


def pink(sec):
    n = n_of(sec)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = 1.0
    spec /= np.sqrt(f)
    x = np.fft.irfft(spec, n)
    return x / (np.abs(x).max() + 1e-9)


def place(x, at, total):
    out = np.zeros(n_of(total))
    i = int(SR * at)
    m = min(len(x), len(out) - i)
    if m > 0 and i >= 0:
        out[i:i + m] += x[:m]
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def env_ad(sec, attack, decay, curve=1.0):
    x = t(sec)
    a = np.clip(x / max(attack, 1e-5), 0.0, 1.0) ** curve
    return a * np.exp(-np.maximum(x - attack, 0.0) / max(decay, 1e-5))


def soft(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def smooth_noise(sec, rate, seed_scale=1.0):
    pts = int(sec * rate) + 3
    knots = rng.standard_normal(pts) * seed_scale
    xs = np.linspace(0, pts - 1, n_of(sec))
    i = np.floor(xs).astype(int)
    f = xs - i
    f = f * f * (3 - 2 * f)
    return knots[i] * (1 - f) + knots[np.minimum(i + 1, pts - 1)] * f


# ------------------------------------------------------------------ filters

def _coeffs(kind, fc, q, gain_db=0.0):
    fc = min(max(fc, 10.0), SR * 0.45)
    w0 = 2 * np.pi * fc / SR
    c = np.cos(w0)
    s = np.sin(w0)
    alpha = s / (2 * q)
    if kind == "lp":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
        a = [1 + alpha, -2 * c, 1 - alpha]
    elif kind == "hp":
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
        a = [1 + alpha, -2 * c, 1 - alpha]
    elif kind == "bp":
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * c, 1 - alpha]
    else:
        A = 10 ** (gain_db / 40)
        b = [1 + alpha * A, -2 * c, 1 - alpha * A]
        a = [1 + alpha / A, -2 * c, 1 - alpha / A]
    return [v / a[0] for v in b], [1.0, a[1] / a[0], a[2] / a[0]]


def biquad(x, kind, fc, q=0.707, gain_db=0.0):
    (b0, b1, b2), (_, a1, a2) = _coeffs(kind, fc, q, gain_db)
    xs = x.tolist()
    y = [0.0] * len(xs)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(xs):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return np.array(y)


def lp(x, fc, q=0.707):
    return biquad(x, "lp", fc, q)


def hp(x, fc, q=0.707):
    return biquad(x, "hp", fc, q)


def bp(x, fc, q=1.0):
    return biquad(x, "bp", fc, q)


def eq(x, fc, gain_db, q=1.0):
    return biquad(x, "peak", fc, q, gain_db)


def bp_sweep(x, f_curve, q, block=64):
    """Band-pass whose centre follows f_curve (one value per sample)."""
    xs = x.tolist()
    y = [0.0] * len(xs)
    x1 = x2 = y1 = y2 = 0.0
    for start in range(0, len(xs), block):
        (b0, b1, b2), (_, a1, a2) = _coeffs("bp", float(f_curve[min(start, len(f_curve) - 1)]), q)
        for i in range(start, min(start + block, len(xs))):
            v = xs[i]
            o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, v, y1, o
            y[i] = o
    return np.array(y)


def formants(src, tracks, block=64):
    """Parallel formant filter. tracks = [(freq_curve, bandwidth_curve, gain), ...]."""
    out = np.zeros(len(src))
    for f, bw, g in tracks:
        q = np.maximum(f / np.maximum(bw, 20.0), 0.5)
        xs = src.tolist()
        y = [0.0] * len(xs)
        x1 = x2 = y1 = y2 = 0.0
        for start in range(0, len(xs), block):
            k = min(start, len(f) - 1)
            (b0, b1, b2), (_, a1, a2) = _coeffs("bp", float(f[k]), float(q[k]))
            for i in range(start, min(start + block, len(xs))):
                v = xs[i]
                o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2, x1, y2, y1 = x1, v, y1, o
                y[i] = o
        out += np.array(y) * g
    return out


def curve(points, sec):
    """Piecewise-linear curve through (time, value) points."""
    tt = t(sec)
    ts = [p[0] for p in points]
    vs = [p[1] for p in points]
    return np.interp(tt, ts, vs)


# ------------------------------------------------------------------ sources

def modal(sec, modes, onset=0.0):
    """Struck object: modes = [(freq, decay_seconds, amplitude), ...]."""
    tt = t(sec)
    out = np.zeros(len(tt))
    for f, d, a in modes:
        ph = rng.uniform(0, 2 * np.pi)
        out += a * np.sin(2 * np.pi * f * tt + ph) * np.exp(-tt / d)
    attack = np.clip(tt / max(onset, 1e-4), 0, 1) if onset > 0 else 1.0
    return out * attack


def click(sec=0.004, lo=1500, hi=8000):
    x = noise(sec) * np.exp(-t(sec) / (sec * 0.25))
    return bp(hp(x, lo), np.sqrt(lo * hi), 0.7)


def glottal(f0, open_q=0.6, jitter=0.0, shimmer=0.0, fry=0.0):
    """Glottal-flow-derivative pulse train following the f0 curve (Hz per sample)."""
    sec = (len(f0) + 2) / SR
    f = f0 * (1.0 + jitter * smooth_noise(sec, 60.0)[:len(f0)])
    phase = np.cumsum(f / SR)
    ph = phase % 1.0
    flow = np.where(ph < open_q, 0.5 * (1 - np.cos(np.pi * ph / open_q)),
                    np.where(ph < open_q + 0.15, np.cos(0.5 * np.pi * (ph - open_q) / 0.15), 0.0))
    d = np.diff(flow, prepend=0.0) * SR / np.maximum(f, 1.0)
    amp = 1.0 + shimmer * smooth_noise(sec, 40.0)[:len(f0)]
    if fry > 0:
        period = np.floor(phase).astype(int)
        amp = amp * np.where(period % 2 == 0, 1.0, 1.0 - fry)
    return d * amp


# ------------------------------------------------------------------ space

def make_ir(t60, predelay=0.012, early=0.07, bright=0.6):
    sec = t60 * 1.3
    n = n_of(sec)
    tt = t(sec)
    raw = rng.standard_normal(n)
    spec = np.fft.rfft(raw)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    low = np.fft.irfft(spec * (f < 400), n)
    mid = np.fft.irfft(spec * ((f >= 400) & (f < 3000)), n)
    high = np.fft.irfft(spec * (f >= 3000), n)
    tail = (low * np.exp(-6.9 * tt / (t60 * 1.15)) + mid * np.exp(-6.9 * tt / t60)
            + high * bright * np.exp(-6.9 * tt / (t60 * 0.45)))
    tail *= np.clip((tt - predelay) / 0.03, 0, 1)
    er = np.zeros(n)
    for k in range(14):
        at = predelay + rng.uniform(0.0, early)
        er[int(at * SR)] += rng.choice([-1, 1]) * (1.0 - at / (predelay + early)) * 0.7
    er = lp(er, 5000)
    ir = er + tail * 0.35
    return ir / np.sqrt((ir ** 2).sum())


IR_ROOM = make_ir(0.6, 0.006, 0.03, 0.7)
IR_CHURCH = make_ir(2.8, 0.02, 0.09, 0.5)


def reverb(x, ir, wet, extra=0.0):
    n = len(x) + len(ir)
    size = 1 << int(np.ceil(np.log2(n)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n]
    out = np.zeros(len(x) + n_of(extra))
    out[:len(x)] += x
    m = min(len(out), len(y))
    out[:m] += y[:m] * wet
    return out


def loop_seamless(x, fade):
    k = n_of(fade)
    body = x[:-k].copy()
    w = np.sin(np.linspace(0, np.pi / 2, k)) ** 2
    body[:k] = body[:k] * w + x[-k:] * (1 - w)
    return body


# ------------------------------------------------------------------ output

def write(name, x, loop=False):
    x = np.asarray(x, dtype=float)
    x -= np.mean(x)
    x = hp(x, 25)
    rms = np.sqrt(np.mean(x ** 2)) + 1e-12
    x *= 10 ** (TARGET_RMS[name] / 20) / rms
    peak = np.abs(x).max()
    if peak > 0.89:
        x = 0.95 * np.tanh(x / 0.95)
        x *= min(1.0, 0.95 / (np.abs(x).max() + 1e-9))
    if not loop:
        f = min(200, len(x) // 4)
        x[-f:] *= np.linspace(1, 0, f)
        x[:16] *= np.linspace(0, 1, 16)
    pcm = (np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()
    fmt = struct.pack('<HHIIHH', 1, 1, SR, SR * 2, 2, 16)
    chunks = b'fmt ' + struct.pack('<I', len(fmt)) + fmt + b'data' + struct.pack('<I', len(pcm)) + pcm
    with open(os.path.join(OUT, name + '.wav'), 'wb') as fh:
        fh.write(b'RIFF' + struct.pack('<I', 4 + len(chunks)) + b'WAVE' + chunks)
    print(f"{name:16s} {len(x) / SR:5.2f}s")


# ================================================================== FOOTSTEPS, OBJECTS

def footstep(seed):
    global rng
    rng = np.random.default_rng(seed)
    L = 0.42
    heel = click(0.006, 400, 5000) * 0.9
    heel = mix(heel, lp(noise(0.03) * env_ad(0.03, 0.001, 0.008), 900) * 0.8)
    stone = modal(0.12, [(rng.uniform(88, 102), 0.025, 0.5), (rng.uniform(150, 175), 0.018, 0.35),
                         (rng.uniform(230, 260), 0.012, 0.25), (rng.uniform(410, 470), 0.008, 0.15)])
    toe_at = rng.uniform(0.045, 0.065)
    toe = bp(noise(0.05) * env_ad(0.05, 0.002, 0.012), rng.uniform(1100, 1500), 0.8) * 0.5
    grit = np.zeros(n_of(0.05))
    for _ in range(rng.integers(6, 12)):
        i = rng.integers(0, len(grit) - 40)
        grit[i:i + 30] += rng.uniform(-1, 1, 30) * np.exp(-np.arange(30) / 6) * rng.uniform(0.2, 0.6)
    grit = hp(grit, 2500) * 0.35
    x = mix(heel, stone, place(toe, toe_at, L), place(grit, toe_at * 0.6, L))
    x = place(x, 0.0, L)
    return lp(reverb(x, IR_ROOM, 0.18)[:n_of(L)], 7000)


def demon_step():
    L = 0.75
    tt = t(0.4)
    f = 62 * np.exp(-tt / 0.15) + 34
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(0.4, 0.004, 0.09)
    thud = lp(noise(0.15) * env_ad(0.15, 0.002, 0.03), 280) * 0.9
    x = mix(boom * 1.2, thud)
    for k in range(4):
        at = 0.018 + k * rng.uniform(0.012, 0.03)
        clack = mix(click(0.003, 2500, 9000), modal(0.04, [(rng.uniform(2300, 3400), 0.006, 0.4), (rng.uniform(4200, 5600), 0.004, 0.25)]))
        x = mix(x, place(clack * rng.uniform(0.35, 0.6), at, L))
    scrape = bp(noise(0.12) * env_ad(0.12, 0.01, 0.04), 1800, 0.6) * 0.15
    x = mix(place(x, 0, L), place(scrape, 0.07, L))
    return reverb(x, IR_ROOM, 0.3)[:n_of(L)]


def door_creak():
    L = 1.15
    tt = t(L)
    u = tt / L
    rate = 34 + 110 * u ** 1.3 + 22 * np.sin(2 * np.pi * 1.7 * tt + 0.4) + 8 * smooth_noise(L, 12)
    phase = np.cumsum(rate) / SR
    exc = np.zeros(len(tt))
    hits = np.nonzero(np.diff(np.floor(phase)) > 0)[0]
    for i in hits:
        exc[i] = rng.uniform(0.5, 1.0) * rng.choice([-1, 1])
    swell = np.clip(u / 0.08, 0, 1) * np.clip((1 - u) / 0.12, 0, 1) * (0.7 + 0.3 * smooth_noise(L, 3) ** 2)
    exc *= swell
    wood_ir = modal(0.06, [(310, 0.012, 1.0), (520, 0.010, 0.8), (790, 0.008, 0.6), (1150, 0.006, 0.5),
                           (1630, 0.004, 0.35), (2400, 0.003, 0.2)])
    size = 1 << int(np.ceil(np.log2(len(exc) + len(wood_ir))))
    body = np.fft.irfft(np.fft.rfft(exc, size) * np.fft.rfft(wood_ir, size), size)[:len(exc)]
    squeak_f = 1350 + 700 * u + 120 * np.sin(2 * np.pi * 5.5 * tt)
    squeak = np.sin(2 * np.pi * np.cumsum(squeak_f) / SR) * swell * (0.5 + 0.5 * np.clip(smooth_noise(L, 8), 0, 1)) * 0.12
    groan = bp(noise(L), 120, 2.0) * swell * 0.4
    return reverb(mix(body, squeak, groan), IR_ROOM, 0.25)


def door_slam():
    L = 2.6
    crack = hp(noise(0.02) * env_ad(0.02, 0.0005, 0.004), 1200) * 0.9
    panel = modal(1.2, [(54, 0.28, 1.0), (79, 0.22, 0.8), (117, 0.16, 0.7), (164, 0.12, 0.55), (212, 0.09, 0.45),
                        (288, 0.07, 0.35), (372, 0.05, 0.3), (455, 0.04, 0.22), (610, 0.03, 0.15)])
    boom = np.sin(2 * np.pi * 42 * t(0.8)) * env_ad(0.8, 0.003, 0.22) * 0.8
    latch = modal(0.4, [(1830, 0.07, 0.5), (2620, 0.05, 0.4), (3910, 0.035, 0.3), (5420, 0.02, 0.2)])
    rattle = np.zeros(n_of(0.4))
    for k in range(5):
        r = modal(0.08, [(rng.uniform(1700, 2700), 0.015, 0.3), (rng.uniform(3200, 4800), 0.01, 0.2)])
        rattle = mix(rattle, place(r * 0.6 ** k, 0.04 + k * rng.uniform(0.025, 0.05), 0.4))
    x = mix(crack, panel * 1.1, boom, place(latch * 0.45, 0.012, 0.6), place(rattle * 0.5, 0.02, 0.6))
    x = soft(x * 1.3, 1.4)
    return reverb(place(x, 0, L), IR_CHURCH, 0.45)[:n_of(L)]


def lighter_open():
    L = 0.45
    tick = click(0.002, 3000, 12000) * 0.6
    clink = modal(0.3, [(2870, 0.07, 0.6), (4130, 0.05, 0.45), (6290, 0.035, 0.3), (8020, 0.02, 0.2)])
    bounce = modal(0.15, [(2900, 0.03, 0.3), (6300, 0.015, 0.15)])
    return reverb(mix(tick, place(clink, 0.004, L), place(bounce, 0.03, L)), IR_ROOM, 0.12)


def lighter_strike():
    L = 1.0
    sc = 0.075
    grind = bp(noise(sc), 4200, 0.6) * (0.55 + 0.45 * np.sin(2 * np.pi * 190 * t(sc))) * env_ad(sc, 0.005, 0.05)
    grind = mix(grind, hp(noise(sc), 6000) * env_ad(sc, 0.002, 0.03) * 0.5)
    sparks = np.zeros(n_of(0.2))
    for _ in range(12):
        sparks = mix(sparks, place(click(0.0015, 4000, 14000) * rng.uniform(0.2, 0.7), rng.uniform(0.0, 0.16), 0.2))
    whoomp = lp(noise(0.5), 700) * env_ad(0.5, 0.018, 0.11) * 1.4
    whoomp = mix(whoomp, bp(noise(0.5), 1500, 0.7) * env_ad(0.5, 0.01, 0.06) * 0.4)
    hiss = bp(pink(0.85), 900, 0.5) * env_ad(0.85, 0.05, 0.35) * 0.25 * (0.8 + 0.2 * smooth_noise(0.85, 20))
    x = mix(grind, place(sparks * 0.6, 0.02, L), place(whoomp, 0.06, L), place(hiss, 0.08, L))
    return lp(reverb(x, IR_ROOM, 0.12)[:n_of(L)], 10000)


def lighter_close():
    L = 0.32
    thud = lp(noise(0.05) * env_ad(0.05, 0.001, 0.008), 600) * 0.9
    snap = modal(0.2, [(1910, 0.04, 0.5), (3050, 0.03, 0.35), (980, 0.06, 0.4)])
    return reverb(mix(thud, place(snap, 0.002, L)), IR_ROOM, 0.12)


def page_flick(sec):
    x = bp(noise(sec), rng.uniform(2200, 4500), 0.8) * env_ad(sec, 0.002, sec * 0.35)
    crk = np.zeros(len(x))
    for _ in range(rng.integers(3, 8)):
        i = rng.integers(0, max(1, len(x) - 60))
        crk[i:i + 50] += rng.uniform(-1, 1, 50) * np.exp(-np.arange(50) / 10)
    return x + hp(crk, 3000) * 0.4


def book_open():
    L = 0.9
    leather_rate = 45 + 40 * t(0.25) / 0.25
    ph = np.cumsum(leather_rate) / SR
    exc = (np.diff(np.floor(ph), prepend=0) > 0).astype(float) * rng.uniform(0.4, 1.0, n_of(0.25))
    leather = bp(exc * np.hanning(len(exc)), 420, 3.0) * 1.5
    air = lp(noise(0.4), 600) * env_ad(0.4, 0.12, 0.12) * 0.25
    x = mix(leather, place(air, 0.1, L))
    at = 0.14
    for k in range(rng.integers(7, 11)):
        x = mix(x, place(page_flick(rng.uniform(0.03, 0.07)) * rng.uniform(0.3, 0.8), at, L))
        at += rng.uniform(0.025, 0.06)
    return lp(reverb(place(x, 0, L), IR_ROOM, 0.15)[:n_of(L)], 9000)


def book_close():
    L = 0.6
    puff = lp(noise(0.08), 900) * env_ad(0.08, 0.04, 0.02) * 0.5
    thump = modal(0.25, [(118, 0.05, 1.0), (181, 0.035, 0.6), (262, 0.025, 0.4)]) * 1.2
    slap = bp(noise(0.03), 900, 0.7) * env_ad(0.03, 0.001, 0.007) * 0.8
    x = mix(puff, place(mix(thump, slap), 0.07, L))
    return reverb(place(x, 0, L), IR_ROOM, 0.2)[:n_of(L)]


def rustle(sec, density=60):
    x = np.zeros(n_of(sec))
    for _ in range(int(density * sec)):
        g = bp(noise(0.03), rng.uniform(1500, 5000), 1.0) * env_ad(0.03, 0.003, 0.008)
        x = mix(x, place(g * rng.uniform(0.2, 1.0), rng.uniform(0, sec - 0.03), sec))
    return x


def pickup():
    L = 1.2
    cloth = rustle(0.35, 70) * np.hanning(n_of(0.35)) * 0.8
    tap = modal(0.2, [(rng.uniform(900, 1100), 0.05, 0.4), (2300, 0.03, 0.25)])
    shimmer = modal(1.0, [(1568, 0.5, 0.15), (2349, 0.4, 0.1), (3136, 0.3, 0.07), (4699, 0.25, 0.05)], onset=0.02)
    x = mix(place(cloth, 0, L), place(tap, 0.12, L), place(shimmer * 0.6, 0.18, L))
    return reverb(x, IR_CHURCH, 0.25)[:n_of(L)]


def place_down():
    L = 2.0
    clink = modal(0.8, [(1460, 0.25, 0.5), (2390, 0.18, 0.35), (3870, 0.12, 0.25), (5210, 0.08, 0.15)])
    thud = lp(noise(0.06) * env_ad(0.06, 0.001, 0.012), 500) * 0.8
    stone = modal(0.2, [(190, 0.04, 0.4), (330, 0.03, 0.25)])
    settle = place(modal(0.2, [(1480, 0.06, 0.15), (3900, 0.03, 0.08)]), 0.09, 0.3)
    x = mix(thud, stone, clink * 0.7, settle)
    return reverb(place(x, 0, L), IR_CHURCH, 0.35)[:n_of(L)]


def candle_out():
    L = 0.55
    blow = bp(noise(0.3), 1400, 0.5) * env_ad(0.3, 0.04, 0.09)
    blow = mix(blow, hp(noise(0.3), 3500) * env_ad(0.3, 0.03, 0.06) * 0.3)
    flutter = lp(noise(0.25), 220) * (0.5 + 0.5 * np.sin(2 * np.pi * 18 * t(0.25))) * env_ad(0.25, 0.01, 0.07) * 0.6
    hiss = hp(noise(0.3), 5000) * env_ad(0.3, 0.02, 0.12) * 0.08
    return lp(reverb(mix(blow, place(flutter, 0.05, L), place(hiss, 0.12, L)), IR_ROOM, 0.15)[:n_of(L)], 6000)


def burn():
    L = 0.7
    x = np.zeros(n_of(L))
    for _ in range(60):
        at = rng.uniform(0, L) ** 1.5 / L ** 0.5
        x = mix(x, place(click(0.002, 1200, 6000) * rng.uniform(0.1, 0.6), at, L))
    hiss = bp(noise(L), 3200, 0.8) * env_ad(L, 0.05, 0.2) * 0.18
    whoosh = bp(noise(L), 700, 0.6) * env_ad(L, 0.08, 0.15) * 0.4
    return lp(reverb(mix(x, hiss, whoosh), IR_ROOM, 0.15)[:n_of(L)], 7000)


def clatter():
    L = 1.8
    x = np.zeros(n_of(L))
    at = 0.0
    gap = 0.22
    for k in range(9):
        amp = 0.85 ** k
        hit = modal(0.6, [(523 * rng.uniform(0.98, 1.02), 0.2, 0.5), (1342, 0.14, 0.45), (2481, 0.1, 0.35),
                          (3897, 0.07, 0.25), (5310, 0.05, 0.15)])
        hit = mix(hit, click(0.003, 1500, 9000) * 0.6)
        x = mix(x, place(hit * amp, at, L))
        at += gap
        gap *= rng.uniform(0.6, 0.78)
        if at > 1.2:
            break
    roll = bp(noise(0.4), 2600, 3.0) * (0.5 + 0.5 * np.sin(2 * np.pi * 26 * t(0.4))) * env_ad(0.4, 0.05, 0.12) * 0.25
    x = mix(x, place(roll, at, L))
    return reverb(x, IR_CHURCH, 0.4)[:n_of(L)]


# ================================================================== DEMON AND BODY

def demon_scream():
    L = 2.1
    f0 = curve([(0.0, 170), (0.12, 330), (0.5, 430), (1.1, 390), (1.6, 300), (2.1, 220)], L)
    voice = glottal(f0, open_q=0.5, jitter=0.07, shimmer=0.35, fry=0.45)
    growl = glottal(f0 * 0.47, open_q=0.7, jitter=0.12, shimmer=0.5, fry=0.7)
    asp = noise(L) * 0.08
    src = voice + growl * 0.9 + asp
    f1 = curve([(0, 650), (0.4, 820), (1.2, 700), (2.1, 420)], L)
    f2 = curve([(0, 1100), (0.4, 1250), (1.2, 1900), (2.1, 2300)], L)
    f3 = curve([(0, 2500), (2.1, 2900)], L)
    bw = np.full(n_of(L), 110.0)
    v = formants(src, [(f1, bw, 1.0), (f2, bw * 1.3, 0.75), (f3, bw * 1.6, 0.5), (f3 * 1.35, bw * 2.0, 0.3)])
    v = soft(v * 2.2, 1.6)
    ring = v * (0.7 + 0.3 * np.sin(2 * np.pi * 38 * t(L)))
    sf = 3300 + 500 * np.sin(2 * np.pi * 6.5 * t(L)) + 400 * t(L) + 120 * smooth_noise(L, 30)
    screech = np.sin(2 * np.pi * np.cumsum(sf) / SR) * (0.6 + 0.4 * smooth_noise(L, 25) ** 2) * 0.18
    e = curve([(0, 0), (0.03, 1), (1.4, 0.85), (2.1, 0)], L)
    x = mix(ring * e, screech * e * curve([(0, 0), (0.15, 1), (1.6, 0.6), (2.1, 0)], L))
    x = lp(eq(x, 180, 4.0, 0.8), 7000)
    return reverb(x, IR_CHURCH, 0.5, 0.8)


def demon_notice():
    L = 1.0
    f0 = curve([(0, 38), (0.4, 44), (0.7, 120), (1.0, 90)], L)
    src = glottal(f0, open_q=0.3, jitter=0.15, shimmer=0.6, fry=0.6) + noise(L) * 0.15
    f1 = curve([(0, 380), (0.6, 420), (1.0, 700)], L)
    f2 = curve([(0, 900), (1.0, 1300)], L)
    bw = np.full(n_of(L), 90.0)
    v = soft(formants(src, [(f1, bw, 1.0), (f2, bw, 0.6), (f2 * 2.1, bw * 2, 0.25)]) * 4.0, 2.5)
    v *= curve([(0, 0), (0.05, 0.7), (0.55, 0.8), (0.75, 1.0), (1.0, 0)], L)
    return reverb(v, IR_CHURCH, 0.45, 0.5)


def demon_breath():
    L = 3.6
    inhale = 1.3
    tt = t(L)
    air = bp(pink(L), 800, 0.6) * 0.8 + bp(noise(L), 2200, 1.2) * 0.25
    rattle = 0.6 + 0.4 * np.sin(2 * np.pi * np.cumsum(np.full(len(tt), 31.0) + 6 * smooth_noise(L, 3)) / SR)
    shape = np.where(tt < inhale, np.sin(np.pi * tt / inhale) ** 1.5 * 0.55,
                     np.sin(np.pi * np.clip((tt - inhale) / (L - inhale - 0.15), 0, 1)) ** 1.2)
    f0 = np.full(len(tt), 52.0) + 4 * smooth_noise(L, 2)
    growl = glottal(f0, open_q=0.35, jitter=0.2, shimmer=0.6, fry=0.7)
    growl = formants(growl, [(np.full(len(tt), 420.0), np.full(len(tt), 120.0), 1.0),
                             (np.full(len(tt), 1050.0), np.full(len(tt), 160.0), 0.4)])
    growl *= np.where(tt < inhale, 0.15, 1.0)
    return (air * rattle + growl * 0.6) * shape


def heartbeat():
    L = 0.5
    def beat(f_hi, f_lo, dur, amp):
        tt = t(dur)
        f = f_lo + (f_hi - f_lo) * np.exp(-tt / 0.03)
        s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(dur, 0.008, dur * 0.25)
        return (s + lp(noise(dur), 150) * env_ad(dur, 0.004, 0.02) * 0.6) * amp
    x = mix(beat(70, 42, 0.16, 1.0), place(beat(82, 50, 0.12, 0.75), 0.17, L))
    return soft(place(x, 0, L) * 1.5, 1.5)


def hit():
    L = 1.1
    tt = t(0.4)
    f = 95 * np.exp(-tt / 0.05) + 48
    punch = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(0.4, 0.002, 0.08) * 1.3
    slap = bp(noise(0.06), 1200, 0.6) * env_ad(0.06, 0.0008, 0.012) * 0.9
    rake = np.zeros(n_of(0.25))
    for k in range(3):
        sc = bp_sweep(noise(0.1), np.linspace(5200, 2400, n_of(0.1)), 3.0) * env_ad(0.1, 0.005, 0.03)
        rake = mix(rake, place(sc * 0.6, 0.01 + k * 0.025, 0.25))
    cloth = rustle(0.15, 120) * 0.4
    x = soft(mix(punch, slap, rake, cloth) * 1.4, 1.6)
    return reverb(place(x, 0, L), IR_ROOM, 0.3)[:n_of(L)]


def swing():
    L = 0.42
    tt = t(L)
    u = tt / L
    fc = 450 + 2600 * np.sin(np.pi * np.clip(u * 1.1, 0, 1)) ** 2
    w = bp_sweep(noise(L), fc, 1.4) * np.sin(np.pi * u) ** 2
    rasp = bp_sweep(noise(L), fc * 2.2, 5.0) * np.sin(np.pi * u) ** 3 * 0.3
    return mix(w, rasp)


def sigh():
    L = 2.4
    inh = bp(noise(0.7), 2100, 0.8) * np.sin(np.pi * t(0.7) / 0.7) ** 1.5 * 0.3
    ex_len = 1.5
    f0 = curve([(0, 150), (0.3, 132), (1.5, 92)], ex_len)
    voice = glottal(f0, open_q=0.65, jitter=0.02, shimmer=0.1) * 0.35 + noise(ex_len) * 0.6
    bw = np.full(n_of(ex_len), 140.0)
    ex = formants(voice, [(curve([(0, 700), (1.5, 620)], ex_len), bw, 1.0),
                          (curve([(0, 1150), (1.5, 1050)], ex_len), bw * 1.3, 0.6),
                          (np.full(n_of(ex_len), 2500.0), bw * 2, 0.3)])
    ex *= curve([(0, 0), (0.12, 1), (0.6, 0.75), (1.5, 0)], ex_len)
    x = mix(place(inh, 0.0, L), place(ex, 0.78, L))
    return reverb(x, IR_ROOM, 0.2)[:n_of(L)]


# ================================================================== AMBIENCE, VOICES, STINGERS

VOWELS = {
    "a": (750, 1150, 2600), "o": (480, 850, 2550), "u": (340, 780, 2400),
    "e": (480, 1850, 2600), "i": (300, 2200, 2950), "ah": (650, 1080, 2650),
}


def sung(note_hz, sec, vowel, vib=5.2, breath=0.12):
    f0 = np.full(n_of(sec), note_hz) * (1 + 0.012 * np.sin(2 * np.pi * vib * t(sec) + rng.uniform(0, 6))) * (1 + 0.004 * smooth_noise(sec, 2))
    src = glottal(f0, open_q=0.6, jitter=0.008, shimmer=0.06) + noise(sec) * breath
    f1, f2, f3 = VOWELS[vowel]
    n = n_of(sec)
    return formants(src, [(np.full(n, f1), np.full(n, 90.0), 1.0), (np.full(n, f2), np.full(n, 110.0), 0.6),
                          (np.full(n, f3), np.full(n, 150.0), 0.35), (np.full(n, 3200.0), np.full(n, 300.0), 0.2)])


def choir(notes, sec, vowel, voices_per_note=2):
    out = np.zeros(n_of(sec))
    for hz in notes:
        for v in range(voices_per_note):
            out += sung(hz * rng.uniform(0.993, 1.007), sec, vowel, vib=rng.uniform(4.6, 5.8)) / (len(notes) * voices_per_note)
    return out


def drone():
    L = 10.0
    tt = t(L + 1.0)
    organ = np.zeros(len(tt))
    for hz, a in [(65.4, 1.0), (65.9, 0.8), (98.0, 0.45), (130.8, 0.3), (196.0, 0.12)]:
        organ += a * np.sin(2 * np.pi * hz * tt + rng.uniform(0, 6))
    organ = lp(organ, 400) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.07 * tt))
    wind = lp(pink(L + 1.0), 380) * (0.6 + 0.4 * (0.5 + 0.5 * smooth_noise(L + 1.0, 0.25))) * 0.9
    rumble = lp(noise(L + 1.0), 45) * 3.0
    hum = bp(pink(L + 1.0), 140, 2.0) * 0.4
    x = organ * 0.5 + wind + rumble + hum
    return loop_seamless(x, 1.0)


def choir_rev():
    L = 9.0
    total = L + 1.2
    x = np.zeros(n_of(total))
    plan = [([110.0, 130.8, 164.8], 0.0, 4.0, "ah"), ([116.5, 138.6, 174.6], 3.4, 4.0, "o"),
            ([98.0, 123.5, 146.8], 6.2, 4.0, "u")]
    for notes, at, dur, vowel in plan:
        c = choir(notes, dur, vowel) * np.sin(np.pi * t(dur) / dur) ** 2
        x = mix(x, place(c, at, total))
    wet = reverb(x, IR_CHURCH, 1.2)[:n_of(total)]
    rev = wet[::-1].copy()
    return loop_seamless(rev, 1.2)


def ending():
    L = 7.5
    swell = choir([196.0, 246.9, 293.7, 392.0, 587.3], 6.5, "ah", 2) * curve([(0, 0), (1.8, 1), (4.8, 0.9), (6.5, 0)], 6.5)
    bell = modal(5.0, [(392.0, 2.5, 0.5), (784.0 * 1.002, 1.8, 0.3), (1178, 1.2, 0.2), (1567, 0.9, 0.12), (2350, 0.6, 0.08)])
    x = mix(swell, place(bell * 0.7, 0.2, L), place(bell * 0.4, 2.6, L))
    return reverb(place(x, 0, L), IR_CHURCH, 0.7)[:n_of(L)]


def banish():
    L = 3.8
    rise = bp_sweep(noise(0.45), np.linspace(300, 3000, n_of(0.45)), 0.9) * np.linspace(0, 1, n_of(0.45)) ** 2
    tt = t(1.5)
    boom = np.sin(2 * np.pi * np.cumsum(40 + 50 * np.exp(-tt / 0.08)) / SR) * env_ad(1.5, 0.003, 0.35)
    shimmer = np.zeros(n_of(3.0))
    for _ in range(18):
        f = rng.uniform(1800, 7000)
        shimmer += modal(3.0, [(f, rng.uniform(0.6, 1.8), rng.uniform(0.02, 0.06))])
    chord = choir([261.6, 329.6, 392.0], 1.6, "ah", 2) * curve([(0, 0), (0.05, 1), (1.6, 0)], 1.6)
    crackle = burn() * 0.6
    x = mix(rise, place(boom * 1.2, 0.45, L), place(shimmer, 0.45, L), place(chord * 0.8, 0.47, L), place(crackle, 0.5, L))
    return reverb(x, IR_CHURCH, 0.6)[:n_of(L)]


def prayer_murmur():
    L = 15.0
    x = np.zeros(n_of(L))
    at = 0.3
    keys = list(VOWELS.keys())
    while at < L - 1.2:
        phrase = rng.uniform(1.6, 3.2)
        pitch0 = rng.uniform(112, 124)
        end = min(at + phrase, L - 0.6)
        while at < end:
            syl = rng.uniform(0.11, 0.22)
            v = VOWELS[keys[rng.integers(0, len(keys))]]
            p = pitch0 * (1 - 0.18 * (at - (end - phrase)) / phrase)
            f0 = np.full(n_of(syl), p) * (1 + 0.03 * np.sin(np.linspace(0, np.pi, n_of(syl))))
            src = glottal(f0, open_q=0.65, jitter=0.02, shimmer=0.1) * 0.5 + noise(syl) * 0.55
            n = n_of(syl)
            s = formants(src, [(np.full(n, v[0]), np.full(n, 110.0), 1.0), (np.full(n, v[1]), np.full(n, 140.0), 0.55),
                               (np.full(n, v[2]), np.full(n, 200.0), 0.25)])
            s *= np.sin(np.pi * np.linspace(0, 1, n)) ** 0.8
            r = rng.uniform()
            if r < 0.3:
                fric = bp(noise(0.06), rng.choice([4800.0, 6500.0, 3200.0]), 2.0) * env_ad(0.06, 0.01, 0.025) * 0.5
                s = mix(fric, place(s, 0.04, syl + 0.04))
            elif r < 0.5:
                s = mix(place(click(0.004, 500, 4000) * 0.6, 0.0, syl), s)
            x = mix(x, place(s * rng.uniform(0.6, 1.0), at, L))
            at += syl * rng.uniform(0.8, 0.95)
        breath = bp(noise(0.35), 1600, 0.7) * np.sin(np.pi * t(0.35) / 0.35) ** 2 * 0.12
        x = mix(x, place(breath, at + 0.05, L))
        at += rng.uniform(0.45, 0.8)
    return reverb(x[:n_of(L)], IR_ROOM, 0.18)[:n_of(L)]


# ================================================================== BUILD

if __name__ == "__main__":
    jobs = [
        ("step1", lambda: footstep(101)), ("step2", lambda: footstep(202)), ("demon_step", demon_step),
        ("door_creak", door_creak), ("door_slam", door_slam), ("lighter_open", lighter_open),
        ("lighter_strike", lighter_strike), ("lighter_close", lighter_close), ("book_open", book_open),
        ("book_close", book_close), ("pickup", pickup), ("place", place_down), ("candle_out", candle_out),
        ("burn", burn), ("clatter", clatter), ("demon_scream", demon_scream), ("demon_notice", demon_notice),
        ("heartbeat", heartbeat), ("hit", hit), ("swing", swing), ("sigh", sigh), ("ending", ending),
        ("banish", banish), ("prayer_murmur", prayer_murmur),
    ]
    loops = [("demon_breath", demon_breath), ("drone", drone), ("choir_rev", choir_rev)]
    only = set(sys.argv[2:])
    for name, fn in jobs:
        if not only or name in only:
            write(name, fn())
    for name, fn in loops:
        if not only or name in only:
            write(name, fn(), loop=True)
