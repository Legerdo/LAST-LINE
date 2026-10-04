"""Procedural adaptive music for the run: three sample-synced stems (base / tension / combat),
16 bars in D minor at 96 BPM. Tails are wrapped around so each stem loops seamlessly.
usage: python tools/gen_music.py   (writes assets/audio/music/run_*.ogg via ffmpeg)
"""
import subprocess
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
BPM = 96
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = 16
LEN = int(SR * BAR * BARS)
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio" / "music"
TMP = ROOT / "art_src" / "music_tmp"
rng = np.random.default_rng(3)

PROG = [("Dm", [50, 53, 57]), ("Bb", [46, 50, 53]), ("F", [53, 57, 60]), ("C", [48, 52, 55]),
        ("Dm", [50, 53, 57]), ("Bb", [46, 50, 53]), ("Gm", [43, 46, 50]), ("A", [45, 49, 52])]


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def lp(x, fc, order=2):
    b, a = signal.butter(order, min(fc, SR * 0.45) / (SR / 2), "low")
    return signal.lfilter(b, a, x, axis=0)


def hp(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), "high")
    return signal.lfilter(b, a, x, axis=0)


def bp(x, f0, f1):
    b, a = signal.butter(2, [f0 / (SR / 2), min(f1, SR * 0.45) / (SR / 2)], "band")
    return signal.lfilter(b, a, x, axis=0)


class Track:
    def __init__(self):
        self.buf = np.zeros((LEN + SR * 4, 2))

    def add(self, x, t, pan=0.0, vol=1.0):
        i = int(t * SR)
        if x.ndim == 1:
            l = x * vol * np.sqrt(0.5 * (1 - pan))
            r = x * vol * np.sqrt(0.5 * (1 + pan))
            x = np.stack([l, r], 1)
        else:
            x = x * vol
        j = min(len(self.buf), i + len(x))
        self.buf[i:j] += x[: j - i]

    def loop(self):
        out = self.buf[:LEN].copy()
        tail = self.buf[LEN:]
        n = min(len(tail), LEN)
        out[:n] += tail[:n]
        return out


def osc(freq, dur, kind="saw", detune=0.0):
    n = int(SR * dur)
    f = np.full(n, freq * (1 + detune)) if np.isscalar(freq) else freq[:n]
    ph = 2 * np.pi * np.cumsum(f) / SR + rng.uniform(0, 6.28)
    if kind == "sine":
        return np.sin(ph)
    if kind == "square":
        return np.sign(np.sin(ph)) * 0.8
    if kind == "tri":
        return 2 * np.abs(2 * ((ph / (2 * np.pi)) % 1.0) - 1) - 1
    return 2 * ((ph / (2 * np.pi)) % 1.0) - 1


def adsr(dur, a, d, s, r):
    n = int(SR * dur)
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = np.clip((dur - t) / max(r, 1e-4), 0, 1)
    return e * rel


def perc_env(dur, decay):
    t = np.arange(int(SR * dur)) / SR
    return np.exp(-t / decay) * np.clip(t / 0.001, 0, 1)


def delay(x, time, fb=0.35, wet=0.3, n=4):
    out = x.copy()
    d = int(time * SR)
    tap = x
    for k in range(1, n + 1):
        tap = np.concatenate([np.zeros((d, 2)), tap[:-d]]) * fb if len(tap) > d else tap * 0
        out += tap * wet / fb
    return out


def reverb(x, size=1.8, wet=0.25):
    n = int(SR * size)
    irl = rng.uniform(-1, 1, n) * np.exp(-np.linspace(0, 7, n))
    irr = rng.uniform(-1, 1, n) * np.exp(-np.linspace(0, 7, n))
    irl = lp(irl, 5000)
    irr = lp(irr, 5000)
    irl /= np.sqrt((irl ** 2).sum()) * 3
    irr /= np.sqrt((irr ** 2).sum()) * 3
    yl = signal.fftconvolve(x[:, 0], irl)[: len(x)]
    yr = signal.fftconvolve(x[:, 1], irr)[: len(x)]
    return x + np.stack([yl, yr], 1) * wet


def chord_at(bar):
    return PROG[(bar // 2) % len(PROG)]


# ------------------------------------------------------------------ instruments
def pad_note(m, dur):
    f = mtof(m)
    x = osc(f, dur, "saw", -0.004) + osc(f, dur, "saw", 0.004) + 0.5 * osc(f * 0.5, dur, "tri")
    x = lp(x, 1100)
    return x * adsr(dur, 0.5, 1.0, 0.8, 0.8) * 0.12


def bass_note(m, dur, accent=1.0):
    f = mtof(m)
    x = osc(f, dur, "saw") * 0.7 + osc(f * 0.5, dur, "square") * 0.4
    t = np.arange(len(x)) / SR
    cutoff = 250 + 1400 * accent * np.exp(-t / 0.08)
    # time-varying lowpass via short blocks
    y = np.zeros_like(x)
    blk = 256
    zi = None
    for i in range(0, len(x), blk):
        fc = float(cutoff[min(i, len(cutoff) - 1)])
        b, a = signal.butter(2, fc / (SR / 2), "low")
        if zi is None:
            zi = signal.lfilter_zi(b, a) * 0
        seg, zi = signal.lfilter(b, a, x[i:i + blk], zi=zi)
        y[i:i + blk] = seg
    return y * adsr(dur, 0.003, 0.12, 0.55, 0.03) * 0.5


def pluck(m, dur=0.35, kind="tri"):
    f = mtof(m)
    x = osc(f, dur, kind) + 0.3 * osc(f * 2, dur, "sine")
    return lp(x, 3500) * perc_env(dur, 0.12) * 0.12


def hat(dur=0.05, open_=False):
    n = rng.uniform(-1, 1, int(SR * (0.25 if open_ else dur)))
    return hp(n, 7000) * perc_env(len(n) / SR, 0.12 if open_ else 0.018) * 0.2


def clack():
    # wheels over a rail joint: dull wooden/metal knock
    d = 0.09
    n = bp(rng.uniform(-1, 1, int(SR * d)), 500, 2600) * perc_env(d, 0.02)
    tone = np.sin(2 * np.pi * 310 * np.arange(int(SR * d)) / SR) * perc_env(d, 0.03) * 0.5
    return (n + tone) * 0.35


def kick():
    d = 0.35
    t = np.arange(int(SR * d)) / SR
    f = 50 + 110 * np.exp(-t / 0.04)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.18)
    click = hp(rng.uniform(-1, 1, len(t)), 3000) * np.exp(-t / 0.004) * 0.3
    return np.tanh((x + click) * 1.5) * 0.7


def snare():
    d = 0.25
    t = np.arange(int(SR * d)) / SR
    n = bp(rng.uniform(-1, 1, len(t)), 1500, 9000) * np.exp(-t / 0.07)
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05) * 0.6
    return (n * 0.8 + body) * 0.55


def tom(f0):
    d = 0.3
    t = np.arange(int(SR * d)) / SR
    f = f0 * (1 + 0.6 * np.exp(-t / 0.05))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.14) * 0.5


def lead_note(m, dur):
    f = mtof(m)
    t = np.arange(int(SR * dur)) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.15, 0, 1)
    x = osc(f * vib, dur, "saw") + osc(f * vib * 1.005, dur, "square") * 0.5
    x = np.tanh(lp(x, 2600) * 2.0)
    return x * adsr(dur, 0.005, 0.1, 0.7, 0.05) * 0.16


def swell(dur, m):
    f = mtof(m)
    x = osc(f, dur, "saw") + osc(f * 1.06, dur, "saw")
    env = np.linspace(0, 1, int(SR * dur)) ** 2
    return lp(x, 2400) * env * 0.08


# ------------------------------------------------------------------ stems
def base_stem():
    tr = Track()
    for bar in range(BARS):
        t0 = bar * BAR
        name, notes = chord_at(bar)
        if bar % 2 == 0:
            for k, m in enumerate(notes):
                tr.add(pad_note(m + 12, BAR * 2 + 0.6), t0, pan=(-0.4, 0.0, 0.4)[k])
        root = notes[0] - 12
        # galloping bass: 1, 1&, 2&, 3, 3&, 4&
        for s, acc in ((0, 1.0), (0.5, 0.6), (1.5, 0.7), (2, 0.9), (2.5, 0.6), (3.5, 0.8)):
            tr.add(bass_note(root if s != 3.5 else root + 7, BEAT * 0.45, acc), t0 + s * BEAT)
        # rail joints
        for s in (0, 2):
            tr.add(clack(), t0 + s * BEAT, pan=-0.2)
            tr.add(clack(), t0 + s * BEAT + 0.16, pan=0.2, vol=0.8)
        for s in range(8):
            tr.add(hat(), t0 + s * BEAT * 0.5, pan=0.3, vol=0.5 if s % 2 else 0.8)
        # quiet arpeggio with echo
        arp = [notes[0] + 24, notes[1] + 24, notes[2] + 24, notes[1] + 24]
        for s in range(16):
            if (s + bar) % 3 == 2:
                continue
            tr.add(pluck(arp[s % 4]), t0 + s * BEAT * 0.25, pan=0.5 if s % 2 else -0.5, vol=0.7)
    x = tr.loop()
    x = delay(x, BEAT * 0.75, 0.3, 0.25)
    return reverb(x, 2.2, 0.28)


def tension_stem():
    tr = Track()
    for bar in range(BARS):
        t0 = bar * BAR
        name, notes = chord_at(bar)
        root = notes[0] - 24
        if bar % 2 == 0:
            d = BAR * 2
            t = np.arange(int(SR * d)) / SR
            drone = np.sin(2 * np.pi * mtof(root) * t) * (0.7 + 0.3 * np.sin(2 * np.pi * (BPM / 60) * t * 0.5)) * 0.35
            grit = lp(np.tanh(osc(mtof(root + 12), d, "saw") * 3), 400) * 0.08
            tr.add((drone + grit) * adsr(d, 0.2, 1, 0.9, 0.3), t0)
        for s in range(16):
            tr.add(hat(0.03), t0 + s * BEAT * 0.25, pan=-0.3 if s % 2 else 0.3, vol=0.55 if s % 4 else 0.9)
        # pulsing low synth on 8ths
        for s in range(8):
            tr.add(bass_note(notes[0] - 12, BEAT * 0.2, 0.4) * 0.6, t0 + s * BEAT * 0.5, pan=0.1)
        if bar % 4 == 3:
            tr.add(swell(BAR, notes[2] + 24), t0, pan=0.0)
            tr.add(swell(BAR, notes[2] + 25), t0, pan=0.5, vol=0.6)
    return reverb(tr.loop(), 2.5, 0.3)


RIFF = [0, None, 3, 0, 7, None, 5, 3, 0, None, 3, 5, 7, 10, 7, 5]


def combat_stem():
    tr = Track()
    for bar in range(BARS):
        t0 = bar * BAR
        name, notes = chord_at(bar)
        for s in (0, 1.5, 2, 2.75):
            tr.add(kick(), t0 + s * BEAT)
        for s in (1, 3):
            tr.add(snare(), t0 + s * BEAT, pan=0.05)
        tr.add(hat(open_=True), t0 + 3.5 * BEAT, pan=0.4, vol=0.7)
        if bar % 4 == 3:
            for k, f in enumerate((200, 160, 130, 100)):
                tr.add(tom(f), t0 + (3 + k * 0.25) * BEAT, pan=-0.5 + k * 0.33)
        base = notes[0] + 12
        for s in range(16):
            iv = RIFF[s]
            if iv is None or (bar % 2 == 1 and s >= 12):
                continue
            tr.add(lead_note(base + iv, BEAT * 0.22), t0 + s * BEAT * 0.25, pan=0.25)
        if bar % 2 == 0:
            for m in notes:
                st = osc(mtof(m), 0.3, "saw") + osc(mtof(m) * 1.01, 0.3, "saw")
                tr.add(lp(st, 1500) * perc_env(0.3, 0.12) * 0.12, t0, pan=-0.3)
    return reverb(tr.loop(), 1.4, 0.18)


def write_wav(path, x, peak):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def main():
    TMP.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    stems = {"run_base": (base_stem(), 0.72), "run_tension": (tension_stem(), 0.55), "run_combat": (combat_stem(), 0.62)}
    for name, (x, peak) in stems.items():
        wav = TMP / f"{name}.wav"
        write_wav(wav, x, peak)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "5",
                        str(OUT / f"{name}.ogg")], check=True)
        print(name, f"{len(x) / SR:.2f}s")


if __name__ == "__main__":
    main()
