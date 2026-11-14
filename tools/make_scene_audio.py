import numpy as np, struct, sys, os
SR = 22050
rng = np.random.default_rng(11)
out_dir = sys.argv[1]


def t(sec):
    return np.arange(int(SR * sec)) / SR


def lowpass(x, a):
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        y[i] = acc
    return y


def ring(freqs, sec, decay):
    tt = t(sec)
    return sum(a * np.sin(2 * np.pi * f * tt + rng.uniform(0, 6)) * np.exp(-tt / (decay * d)) for f, a, d in freqs)


def place(x, at, total):
    o = np.zeros(int(SR * total))
    i = int(SR * at)
    n = min(len(x), len(o) - i)
    if n > 0:
        o[i:i + n] += x[:n]
    return o


def write(name, x, peak=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    f = 100
    x[:f] *= np.linspace(0, 1, f)
    x[-f:] *= np.linspace(1, 0, f)
    pcm = (np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()
    fmt = struct.pack('<HHIIHH', 1, 1, SR, SR * 2, 2, 16)
    chunks = b'fmt ' + struct.pack('<I', len(fmt)) + fmt + b'data' + struct.pack('<I', len(pcm)) + pcm
    with open(os.path.join(out_dir, name + '.wav'), 'wb') as fh:
        fh.write(b'RIFF' + struct.pack('<I', 4 + len(chunks)) + b'WAVE' + chunks)
    print(name, round(len(x) / SR, 2))


L = 0.95
n = int(SR * L)
tt = t(L)
u = tt / L
rate = 38 + 95 * u ** 1.4 + 18 * np.sin(2 * np.pi * 2.3 * tt + 0.7) + 6 * rng.standard_normal(n).cumsum() / np.sqrt(np.arange(1, n + 1))
phase = np.cumsum(rate) / SR
x = np.zeros(n)
grain = t(0.03)
kernel = sum(a * np.sin(2 * np.pi * f * grain) * np.exp(-grain / d) for f, d, a in [(720, 0.006, 1.0), (1180, 0.004, 0.6), (1930, 0.003, 0.35), (2650, 0.002, 0.2)])
for i in np.nonzero(np.diff(np.floor(phase)) > 0)[0]:
    amp = rng.uniform(0.55, 1.0) * np.sin(np.pi * min(u[i] / 0.12, 1.0) * 0.5) ** 2
    m = min(len(kernel), n - i)
    x[i:i + m] += kernel[:m] * amp * rng.choice([-1, 1])
x += np.sin(2 * np.pi * 95 * tt) * np.exp(-((u - 0.5) / 0.35) ** 2) * 0.08
x *= np.minimum(1.0, (1.0 - u) / 0.15)
write("door_creak", x)

clink = ring([(3150, 1.0, 1.0), (4720, 0.6, 0.7), (6900, 0.35, 0.5), (2210, 0.3, 1.4)], 0.35, 0.045)
tick = rng.uniform(-1, 1, int(SR * 0.004)) * np.exp(-t(0.004) / 0.0012)
write("lighter_open", place(tick, 0.0, 0.4) * 0.8 + place(clink, 0.002, 0.4), 0.7)

S = 0.9
scrape = rng.uniform(-1, 1, int(SR * 0.09))
scrape = scrape - lowpass(scrape, 0.25)
scrape *= np.sin(np.pi * t(0.09) / 0.09) ** 0.6
sparks = np.zeros(int(SR * S))
for k in range(9):
    at = 0.03 + rng.uniform(0, 0.12)
    burst = rng.uniform(-1, 1, int(SR * 0.006)) * np.exp(-t(0.006) / 0.0015)
    sparks += place(burst, at, S) * rng.uniform(0.3, 0.9)
tt = t(S)
whoosh = lowpass(rng.uniform(-1, 1, len(tt)), 0.06) * np.clip((tt - 0.08) / 0.07, 0, 1) * np.exp(-np.maximum(tt - 0.15, 0) / 0.18)
hiss = lowpass(rng.uniform(-1, 1, len(tt)), 0.15) * np.clip((tt - 0.15) / 0.2, 0, 1) * np.exp(-np.maximum(tt - 0.3, 0) / 0.3) * 0.25
write("lighter_strike", place(scrape, 0.0, S) * 0.9 + sparks * 0.6 + whoosh * 3.5 + hiss, 0.75)

snap = ring([(1850, 1.0, 1.0), (2900, 0.5, 0.6), (980, 0.5, 1.5)], 0.25, 0.03)
thud = lowpass(rng.uniform(-1, 1, int(SR * 0.03)), 0.2) * np.exp(-t(0.03) / 0.006)
write("lighter_close", place(thud, 0.0, 0.3) * 2.0 + place(snap, 0.001, 0.3), 0.7)


def resonate(x, freq, bw):
    r = np.exp(-np.pi * bw / SR)
    c1 = 2 * r * np.cos(2 * np.pi * freq / SR)
    c2 = -r * r
    y = np.zeros_like(x)
    y1 = y2 = 0.0
    for i, v in enumerate(x):
        y0 = v + c1 * y1 + c2 * y2
        y[i] = y0
        y2, y1 = y1, y0
    return y


def syllable(sec, f1, f2, voiced):
    n = int(SR * sec)
    tt = np.arange(n) / SR
    src = rng.uniform(-1, 1, n) * 0.6
    if voiced > 0:
        pitch = 105 + 12 * np.sin(2 * np.pi * 0.7 * tt + rng.uniform(0, 6))
        ph = np.cumsum(pitch) / SR
        src += voiced * (2 * (ph % 1.0) - 1.0)
    out = resonate(src, f1, 90) * 0.6 + resonate(src, f2, 140) * 0.4
    env = np.sin(np.pi * np.clip(tt / sec, 0, 1)) ** 0.7
    return out * env


L = 15.0
x = np.zeros(int(SR * L))
at = 0.25
vowels = [(320, 900), (500, 1100), (650, 1250), (420, 1900), (300, 2100), (550, 1600)]
while at < L - 0.6:
    words = rng.integers(3, 7)
    for w in range(words):
        for s in range(rng.integers(1, 4)):
            d = rng.uniform(0.09, 0.2)
            f1, f2 = vowels[rng.integers(0, len(vowels))]
            x += place(syllable(d, f1 * rng.uniform(0.9, 1.1), f2 * rng.uniform(0.9, 1.1), 0.35) * rng.uniform(0.6, 1.0), at, L)
            at += d * rng.uniform(0.75, 0.95)
        at += rng.uniform(0.03, 0.09)
    at += rng.uniform(0.35, 0.7)
write("prayer_murmur", x, 0.6)

tt = t(2.2)
inhale = resonate(rng.uniform(-1, 1, len(tt)), 900, 600) * np.clip(tt / 0.5, 0, 1) * np.clip((0.75 - tt) / 0.15, 0, 1) * 0.35
ex = np.clip((tt - 0.85) / 0.12, 0, 1) * np.exp(-np.maximum(tt - 0.95, 0) / 0.45)
exhale = (resonate(rng.uniform(-1, 1, len(tt)), 520, 250) * 0.7 + resonate(rng.uniform(-1, 1, len(tt)), 1450, 400) * 0.4) * ex
hum = np.sin(2 * np.pi * np.cumsum(118 - 22 * np.clip((tt - 0.9) / 1.0, 0, 1)) / SR) * ex * 0.05
write("sigh", inhale + exhale + hum, 0.55)

L = 0.7
x = np.zeros(int(SR * L))
for k in range(6):
    d = rng.uniform(0.03, 0.08)
    burst = resonate(rng.uniform(-1, 1, int(SR * d)), rng.uniform(2500, 4200), 1800) * np.sin(np.pi * t(d) / d)
    x += place(burst, 0.08 + k * rng.uniform(0.05, 0.09), L) * rng.uniform(0.4, 1.0)
creak = resonate(rng.uniform(-1, 1, int(SR * 0.25)), 380, 60) * np.sin(np.pi * t(0.25) / 0.25) * 0.3
write("book_open", x + place(creak, 0.0, L), 0.5)

L = 0.45
thump = resonate(rng.uniform(-1, 1, int(SR * 0.08)), 160, 120) * np.exp(-t(0.08) / 0.02)
air = resonate(rng.uniform(-1, 1, int(SR * 0.12)), 2200, 2000) * np.sin(np.pi * t(0.12) / 0.12) * 0.25
write("book_close", place(air, 0.0, L) + place(thump, 0.1, L) * 3.0, 0.6)
