# Synthesizes audio/chant.wav: a slow, low Orthodox-style (Byzantine) chant for the passage between churches.
# Original music made here, no recordings: men's voices singing on vowels over an "ison" (the held drone note),
# in a plagal-second-mode-like scale (D, E-flat, F-sharp, G, A, B-flat, C-sharp: the augmented second gives the
# old, eastern sound), with a church-sized reverb. 22.05 kHz mono 16-bit, made to loop.
#   python tools/make_chant.py audio
import numpy as np, struct, sys, os
from scipy.signal import fftconvolve, butter, lfilter

SR = 22050
rng = np.random.default_rng(11)
out_dir = sys.argv[1] if len(sys.argv) > 1 else "audio"

# --- the scale (Hz). D3 = 146.8; the drone sits an octave and a fifth/octave lower
D2, A1 = 73.42, 55.0
SCALE = {"C#": 138.59, "D": 146.83, "Eb": 155.56, "F#": 185.0, "G": 196.0, "A": 220.0, "Bb": 233.08, "C#4": 277.18, "D4": 293.66}
# vowels: male formant centres (Hz), widths, gains - Church Slavonic sounds: "Gos-po-di po-mi-luj"
VOWELS = {"o": ([450, 800, 2830], [80, 90, 120], [1.0, 0.6, 0.15]),
          "a": ([700, 1220, 2600], [90, 110, 140], [1.0, 0.55, 0.2]),
          "i": ([270, 2290, 3010], [60, 140, 160], [1.0, 0.35, 0.25]),
          "u": ([325, 700, 2530], [60, 80, 120], [1.0, 0.4, 0.08]),
          "e": ([400, 1900, 2600], [70, 130, 140], [1.0, 0.45, 0.2])}
SYLL = ["o", "o", "i", "o", "i", "u", "a", "e", "o", "i"]

# --- the melody: (note, beats) phrases; a beat is 0.62 s. Phrases end on long notes; rests are ("-", beats)
BEAT = 0.62
PHRASES = [
    [("D", 2), ("D", 1), ("Eb", 1), ("F#", 2), ("Eb", 1), ("D", 4), ("-", 2)],
    [("F#", 1), ("G", 1), ("A", 3), ("G", 1), ("F#", 1), ("Eb", 2), ("D", 5), ("-", 2)],
    [("A", 2), ("Bb", 1), ("A", 1), ("G", 1), ("F#", 2), ("G", 1), ("A", 6), ("-", 2)],
    [("A", 1), ("C#4", 2), ("D4", 3), ("C#4", 1), ("Bb", 1), ("A", 2), ("G", 1), ("F#", 2), ("Eb", 1), ("D", 6), ("-", 3)],
    [("D", 1), ("Eb", 1), ("D", 1), ("C#", 2), ("D", 7), ("-", 3)],
]
# the ison follows the phrase: on A for the third and fourth, on D otherwise
ISON = [D2, D2, A1, A1, D2]


def build_tracks():
    """Per-sample arrays for the melody: f0, amplitude, vowel index; and for the ison: f0, amplitude."""
    total_beats = sum(b for ph in PHRASES for _, b in ph)
    n = int((total_beats * BEAT + 2.0) * SR)
    f0 = np.zeros(n); amp = np.zeros(n); vow = np.zeros(n, dtype=int)
    if0 = np.zeros(n); iamp = np.zeros(n)
    pos = 0; syl = 0; last = SCALE["D"]
    for pi, ph in enumerate(PHRASES):
        start = pos
        for note, beats in ph:
            m = int(beats * BEAT * SR)
            if note == "-":
                f0[pos:pos + m] = last
                pos += m
                continue
            f = SCALE[note]
            seg = np.full(m, f)
            g = min(int(0.09 * SR), m)                       # glide from the last note
            seg[:g] = np.linspace(last, f, g)
            f0[pos:pos + m] = seg
            env = np.ones(m)
            a = int(0.12 * SR); r = int(0.18 * SR)
            env[:a] = np.linspace(0.55, 1.0, a)              # legato: a dip, not a gap, between notes
            env[-r:] *= np.linspace(1.0, 0.75, r)
            amp[pos:pos + m] = env
            vow[pos:pos + m] = syl % len(SYLL)
            syl += 1
            last = f; pos += m
        # breath at the end of each phrase
        tail = int(0.35 * SR)
        amp[max(start, pos - int(2 * BEAT * SR) - tail):pos - int(2 * BEAT * SR)] *= np.linspace(1, 0, min(tail, pos - start))[:len(amp[max(start, pos - int(2 * BEAT * SR) - tail):pos - int(2 * BEAT * SR)])]
        if0[start:pos] = ISON[pi]
        iamp[start:pos] = 1.0
    f0[pos:] = last; if0[pos:] = ISON[-1]; iamp[pos:] = np.linspace(1, 0.0, n - pos)
    # smooth the ison changes
    k = int(0.4 * SR); kern = np.ones(k) / k
    if0 = np.convolve(if0, kern, mode="same"); iamp = np.convolve(iamp, kern, mode="same")
    amp = np.convolve(amp, np.ones(int(0.03 * SR)) / int(0.03 * SR), mode="same")
    return f0, amp, vow, if0, iamp


def voice(f0, amp, vowels, detune_cents, vib_rate, vib_depth, delay, brightness=1.0):
    n = len(f0)
    t = np.arange(n) / SR
    d = int(delay * SR)
    f0 = np.roll(f0, d); amp = np.roll(amp, d)
    drift = np.cumsum(rng.normal(0, 1, n)); drift = drift / (np.max(np.abs(drift)) + 1e-9)
    f = f0 * 2 ** ((detune_cents + 4.0 * drift) / 1200.0) * (1.0 + vib_depth * np.sin(2 * np.pi * vib_rate * t + rng.uniform(0, 6)))
    phase = 2 * np.pi * np.cumsum(f) / SR
    # formants follow the vowel, gliding between syllables
    if isinstance(vowels, str):
        F = np.array([VOWELS[vowels][0]] * n, dtype=float); B = np.array([VOWELS[vowels][1]] * n, dtype=float)
        G = np.array([VOWELS[vowels][2]] * n, dtype=float)
    else:
        vlist = [VOWELS[SYLL[i]] for i in range(len(SYLL))]
        F = np.array([vlist[v][0] for v in vowels], dtype=float); B = np.array([vlist[v][1] for v in vowels], dtype=float)
        G = np.array([vlist[v][2] for v in vowels], dtype=float)
        sm = np.ones(int(0.06 * SR)) / int(0.06 * SR)
        for j in range(3):
            F[:, j] = np.convolve(F[:, j], sm, mode="same"); G[:, j] = np.convolve(G[:, j], sm, mode="same")
    out = np.zeros(n)
    kmax = int(3800 / max(np.min(f0[f0 > 0]), 40))
    for k in range(1, kmax + 1):
        hk = k * f
        env = np.zeros(n)
        for j in range(3):
            env += G[:, j] * np.exp(-((hk - F[:, j]) / (B[:, j] * 1.6)) ** 2)
        env += 0.04 * np.exp(-hk / 900.0)                       # a little body under the formants
        src = k ** (-0.6 * (2.0 - brightness))
        out += src * env * np.sin(k * phase)
    return out * amp


def main():
    f0, amp, vow, if0, iamp = build_tracks()
    mix = np.zeros(len(f0))
    # the melody: four tenors, slightly apart in pitch and time - a choir, not a synth
    for i in range(4):
        mix += 0.55 * voice(f0, amp, vow, rng.uniform(-9, 9), rng.uniform(4.6, 5.6), 0.005, rng.uniform(0, 0.05))
    # a bass doubling the melody an octave below on the last phrase-notes: dark weight
    mix += 0.35 * voice(f0 * 0.5, amp, vow, rng.uniform(-6, 6), 4.8, 0.004, 0.03, 0.8)
    # the ison: three basses holding the drone on "o"
    for i in range(3):
        mix += 0.7 * voice(if0, iamp, "o", rng.uniform(-7, 7), rng.uniform(4.0, 5.0), 0.003, rng.uniform(0, 0.08), 0.7)
    # breath noise
    b, a = butter(2, [300 / (SR / 2), 3000 / (SR / 2)], "band")
    mix += 0.015 * lfilter(b, a, rng.normal(0, 1, len(mix))) * np.convolve(amp, np.ones(400) / 400, mode="same")
    # a big stone church: 4 s reverb tail
    ir_n = int(4.0 * SR); tt = np.arange(ir_n) / SR
    ir = rng.normal(0, 1, ir_n) * np.exp(-tt / 0.95)
    b, a = butter(1, 2500 / (SR / 2), "low"); ir = lfilter(b, a, ir)
    ir[0] = 6.0
    dry = np.concatenate([mix, np.zeros(ir_n)])
    wet = np.zeros(len(dry))
    full = fftconvolve(mix, ir)
    wet[:min(len(full), len(dry))] = full[:len(dry)]
    x = 0.45 * dry / (np.max(np.abs(dry)) + 1e-9) + 0.9 * wet / (np.max(np.abs(wet)) + 1e-9)
    # loop: fold the reverb tail back onto the start
    head = len(mix)
    x[:ir_n] += x[head:head + ir_n]
    x = x[:head]
    b, a = butter(2, 60 / (SR / 2), "high"); x = lfilter(b, a, x)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    n = len(pcm) // 2
    smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0) + struct.pack("<6I", 0, 0, 0, n - 1, 0, 0)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(pcm)) + pcm + b"smpl" + struct.pack("<I", len(smpl)) + smpl
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "chant.wav"), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)
    print(f"chant.wav {len(x) / SR:.1f} s")


main()
