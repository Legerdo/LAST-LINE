"""Synthesize every sound effect for LAST LINE (numpy/scipy, 44.1 kHz mono WAV).
Layered designs: transient + body + tail, with variants so repeats do not sound robotic.
usage: python tools/gen_sfx.py
"""
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"
rng = np.random.default_rng(42)


# ------------------------------------------------------------------ primitives
def t_(dur):
    return np.arange(int(SR * dur)) / SR


def env_exp(dur, decay, attack=0.002):
    t = t_(dur)
    e = np.exp(-t / max(decay, 1e-4))
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return e * a


def env_ad(dur, attack, release):
    t = t_(dur)
    e = np.minimum(np.clip(t / max(attack, 1e-5), 0, 1), np.clip((dur - t) / max(release, 1e-5), 0, 1))
    return e


def osc(freq, dur, kind="sine", phase=0.0):
    """freq: float or array (sweep)"""
    n = int(SR * dur)
    f = np.full(n, freq, float) if np.isscalar(freq) else np.asarray(freq, float)[:n]
    ph = 2 * np.pi * np.cumsum(f) / SR + phase
    if kind == "sine":
        return np.sin(ph)
    if kind == "square":
        return np.sign(np.sin(ph))
    if kind == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if kind == "tri":
        return 2 * np.abs(2 * ((ph / (2 * np.pi)) % 1.0) - 1) - 1
    raise ValueError(kind)


def sweep(f0, f1, dur, curve=1.0):
    t = np.linspace(0, 1, int(SR * dur))
    return f0 + (f1 - f0) * t ** curve


def expsweep(f0, f1, dur):
    t = np.linspace(0, 1, int(SR * dur))
    return f0 * (f1 / f0) ** t


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def lp(x, fc, order=2):
    b, a = signal.butter(order, min(fc, SR * 0.45) / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bp(x, f0, f1, order=2):
    b, a = signal.butter(order, [f0 / (SR / 2), min(f1, SR * 0.45) / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def dist(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def pad(x, dur):
    n = int(SR * dur)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x, delay):
    return np.concatenate([np.zeros(int(SR * delay)), x])


def reverb(x, size=0.4, wet=0.25, damp=3000):
    ir_len = int(SR * size)
    ir = rng.uniform(-1, 1, ir_len) * np.exp(-np.linspace(0, 6, ir_len))
    ir = lp(ir, damp)
    ir /= np.abs(ir).sum() ** 0.5 * 4
    y = signal.fftconvolve(x, ir)[: len(x) + ir_len]
    return mix(x * (1 - wet * 0.5), y * wet)


def crackle(dur, density=300, amp=1.0):
    n = int(SR * dur)
    out = np.zeros(n)
    k = int(density * dur)
    idx = rng.integers(0, n, k)
    out[idx] = rng.uniform(-amp, amp, k)
    return lp(out, 6000)


def norm(x, peak=0.89):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def fade_out(x, tail=0.01):
    n = int(SR * tail)
    if n > 0 and len(x) > n:
        x = x.copy()
        x[-n:] *= np.linspace(1, 0, n)
    return x


def save(name, x, peak=0.89):
    x = fade_out(norm(np.asarray(x, float), peak))
    OUT.mkdir(parents=True, exist_ok=True)
    data = (x * 32767).astype(np.int16)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# ------------------------------------------------------------------ weapons
def gun(v):
    d = 0.14
    click = hp(noise(0.006), 3000) * 0.8
    crack = bp(noise(d), 900 + 200 * v, 5000) * env_exp(d, 0.025)
    thump = osc(sweep(160, 60, d), d) * env_exp(d, 0.03) * 0.8
    return reverb(mix(click, crack, thump), 0.15, 0.15)


def boom(size):
    d = 0.35 + size * 0.6
    body = lp(noise(d), 900 - 300 * size) * env_exp(d, 0.08 + size * 0.2, 0.004)
    sub = osc(expsweep(90, 30, d), d) * env_exp(d, 0.12 + size * 0.25) * 1.2
    crack = hp(noise(0.03), 2000) * env_exp(0.03, 0.008)
    tail = crackle(d, 400, 0.6) * env_exp(d, 0.2 + size * 0.3)
    return reverb(dist(mix(crack, body * 1.2, sub, tail), 1.6), 0.5 + size * 0.5, 0.3)


def zap():
    d = 0.18
    f = 600 + rng.uniform(-300, 900, int(SR * d))
    f = lp(f, 60)
    buzz = osc(f, d, "square") * 0.4 + osc(f * 2.01, d, "saw") * 0.2
    sparks = hp(noise(d), 4000) * 0.4
    return reverb(mix(buzz, sparks) * env_exp(d, 0.06), 0.2, 0.2)


def flame():
    d = 0.3
    roar = lp(noise(d), 1400) * env_ad(d, 0.03, 0.15)
    hiss = bp(noise(d), 2000, 7000) * env_ad(d, 0.01, 0.2) * 0.3
    return mix(roar, hiss, crackle(d, 500, 0.5))


def mortar():
    d = 0.45
    thump = osc(expsweep(140, 40, d), d) * env_exp(d, 0.1) * 1.3
    puff = lp(noise(d), 1200) * env_exp(d, 0.06)
    tube = osc(420, d) * env_exp(d, 0.05) * 0.2
    return reverb(mix(thump, puff, tube), 0.4, 0.25)


def metal(d=0.4, base=420, amp=1.0, decay=0.12):
    parts = [osc(base * r, d) * env_exp(d, decay * k) * a
             for r, k, a in ((1.0, 1.0, 1.0), (2.76, 0.7, 0.6), (5.4, 0.45, 0.4), (8.9, 0.3, 0.25))]
    hit = hp(noise(0.02), 1500) * env_exp(0.02, 0.005)
    return mix(*parts, hit) * amp


def train_hit(v):
    d = 0.35
    clank = metal(d, 300 + 60 * v, 1.0, 0.09)
    thud = lp(noise(d), 400) * env_exp(d, 0.05)
    return reverb(dist(mix(clank, thud * 1.4), 1.3), 0.25, 0.2)


# ------------------------------------------------------------------ creatures
def hit_flesh(v):
    d = 0.09
    tick = hp(noise(0.01), 3000) * env_exp(0.01, 0.003)
    thwack = bp(noise(d), 300 + 100 * v, 2500) * env_exp(d, 0.02)
    return mix(tick * 0.6, thwack)


def squelch(v):
    d = 0.28
    wet = lp(noise(d), 900) * env_exp(d, 0.07)
    pitch = osc(expsweep(260 + 40 * v, 70, d), d, "saw") * env_exp(d, 0.05) * 0.4
    return reverb(mix(wet, lp(pitch, 1500)), 0.2, 0.15)


def roar(d=1.0, base=90):
    t = t_(d)
    wob = 1 + 0.3 * np.sin(2 * np.pi * 7 * t) + 0.2 * rng.uniform(-1, 1, len(t))
    src = osc(base * wob, d, "saw") + lp(noise(d), 800) * 0.8
    formant = bp(src, 300, 1200) + bp(src, 1800, 2600) * 0.4
    e = env_ad(d, 0.08, 0.4)
    return reverb(dist(formant * e, 2.5), 0.6, 0.35)


def splat():
    d = 0.6
    burst = lp(noise(d), 1100) * env_exp(d, 0.12)
    goo = osc(expsweep(200, 40, d), d) * env_exp(d, 0.15)
    drops = crackle(d, 120, 0.8) * env_exp(d, 0.3)
    return reverb(mix(burst, goo, drops), 0.4, 0.25)


# ------------------------------------------------------------------ ui / tones
def note(freq, dur, kind="tri", decay=0.2, vol=1.0):
    return osc(freq, dur, kind) * env_exp(dur, decay, 0.003) * vol


def chime(freqs, step=0.07, kind="tri", decay=0.25, verb=0.25):
    parts = [at(note(f, 0.6, kind, decay), i * step) for i, f in enumerate(freqs)]
    return reverb(mix(*parts), 0.5, verb)


def blip(f0, f1, dur=0.06, kind="square"):
    return osc(sweep(f0, f1, dur), dur, kind) * env_exp(dur, dur * 0.5) * 0.5


def swish(dur=0.12, f0=1500, f1=5000):
    n = noise(dur)
    return bp(n, f0, f1) * env_ad(dur, dur * 0.3, dur * 0.6)


def bell():
    d = 1.8
    parts = [osc(620 * r, d) * env_exp(d, k) * a for r, k, a in
             ((1.0, 0.9, 1.0), (2.41, 0.6, 0.5), (3.93, 0.35, 0.3), (5.4, 0.2, 0.2), (0.5, 1.2, 0.4))]
    return reverb(mix(*parts), 1.0, 0.3)


def station_chime():
    # two-tone platform chime (sustained sine bells)
    a = note(659.25, 1.2, "sine", 0.6) + note(1318.5, 1.2, "sine", 0.3, 0.2)
    b = note(523.25, 1.4, "sine", 0.7) + note(1046.5, 1.4, "sine", 0.35, 0.2)
    return reverb(mix(a, at(b, 0.42)), 0.9, 0.35)


def horn(d=1.1, f=(233.0, 294.0), vib=5.0, drive=1.4):
    t = t_(d)
    parts = []
    for fr in f:
        fv = fr * (1 + 0.004 * np.sin(2 * np.pi * vib * t))
        parts.append(osc(fv, d, "saw") * 0.5 + osc(fv * 1.003, d, "saw") * 0.5)
    x = lp(mix(*parts), 1800) * env_ad(d, 0.05, 0.25)
    return reverb(dist(x, drive), 0.8, 0.35)


def brake_hiss(d=0.8):
    return bp(noise(d), 3000, 9000) * env_ad(d, 0.02, 0.5) * 0.5


def siren(d=2.0):
    t = t_(d)
    f = 600 + 350 * np.sin(2 * np.pi * 0.9 * t - np.pi / 2)
    x = osc(f, d, "square") * 0.5 + osc(f * 1.5, d, "tri") * 0.3
    return reverb(lp(x, 2500) * env_ad(d, 0.05, 0.3), 0.6, 0.3)


def static(d=0.35):
    x = bp(noise(d), 800, 6000) * (0.6 + 0.4 * (rng.uniform(0, 1, int(SR * d)) > 0.5))
    return x * env_ad(d, 0.01, 0.1)


def rumble(d=1.6, f0=40, f1=110):
    x = osc(expsweep(f0, f1, d), d, "saw") * 0.6 + lp(noise(d), 300)
    return dist(lp(x, 500) * env_ad(d, d * 0.9, 0.05), 1.8)


def clicks(n=5, spacing=0.05, f=2500):
    parts = [at(hp(noise(0.01), f) * env_exp(0.01, 0.003), i * spacing) for i in range(n)]
    return mix(*parts)


def main():
    # weapons
    for v in range(4):
        save(f"gun_{v + 1}" if v else "gun", gun(v))
    save("boom_small", boom(0.0))
    save("boom_small_1", boom(0.1))
    save("boom", boom(0.45))
    save("boom_1", boom(0.55))
    save("big_boom", boom(1.0))
    save("zap", zap())
    save("zap_1", zap())
    save("flame", flame())
    save("flame_1", flame())
    save("mortar", mortar())
    save("cannon", reverb(mix(boom(0.3), metal(0.4, 180, 0.6, 0.1)), 0.4, 0.2))
    save("shot_enemy", lp(gun(1), 2200) * 0.7)
    save("throw", swish(0.22, 400, 2500))
    save("molotov", mix(hp(crackle(0.25, 2000, 1.0), 3000), at(flame(), 0.05)))
    # damage
    for v in range(3):
        save("train_hit" if v == 0 else f"train_hit_{v}", train_hit(v))
    save("metal_hit", metal(0.25, 520, 0.8, 0.05))
    save("metal_hit_1", metal(0.25, 610, 0.8, 0.05))
    for v in range(3):
        save("hit" if v == 0 else f"hit_{v}", hit_flesh(v))
    save("crit", mix(hit_flesh(2), metal(0.3, 1400, 0.4, 0.06)))
    for v in range(3):
        save("enemy_die" if v == 0 else f"enemy_die_{v}", squelch(v))
    save("ram", mix(lp(noise(0.25), 500) * env_exp(0.25, 0.06) * 1.3, squelch(1) * 0.7))
    save("thud", reverb(mix(osc(expsweep(90, 35, 0.5), 0.5) * env_exp(0.5, 0.12) * 1.3, lp(noise(0.5), 300) * env_exp(0.5, 0.08)), 0.3, 0.2))
    save("heavy_bite", mix(squelch(0) * 1.2, metal(0.3, 260, 0.6, 0.06)))
    save("splat", splat())
    save("spore", mix(bp(noise(0.6), 500, 3000) * env_ad(0.6, 0.1, 0.4), osc(sweep(300, 180, 0.6), 0.6) * env_ad(0.6, 0.1, 0.4) * 0.2))
    save("elite", roar(1.1, 80))
    save("roar", roar(1.4, 60))
    save("elite_die", mix(boom(0.6), at(roar(0.6, 110) * 0.6, 0.0)))
    # world
    save("place", reverb(mix(osc(expsweep(120, 45, 0.35), 0.35) * env_exp(0.35, 0.08) * 1.4,
                             lp(noise(0.35), 700) * env_exp(0.35, 0.06), metal(0.3, 330, 0.35, 0.05)), 0.35, 0.2))
    save("hostile_place", mix(osc(sweep(110, 82, 0.8), 0.8, "saw") * env_ad(0.8, 0.05, 0.5) * 0.25, rumble(0.8, 50, 40) * 0.4))
    save("evolve", mix(chime([523.25, 659.25, 783.99, 1046.5, 1318.5], 0.06, "tri", 0.3), hp(noise(0.8), 5000) * env_exp(0.8, 0.3) * 0.15))
    save("corrupt", mix(chime([466.16, 440.0, 392.0, 369.99], 0.09, "saw", 0.25, 0.3) * 0.6, splat() * 0.5))
    save("station", station_chime())
    save("depot", mix(chime([392.0, 523.25, 659.25], 0.18, "sine", 0.5, 0.35), at(brake_hiss(1.0), 0.3)))
    save("horn", horn())
    save("return", mix(horn(1.4, (196.0, 246.94)), at(brake_hiss(1.2), 0.9)))
    save("boss_horn", horn(2.2, (73.4, 77.8, 110.0), 3.0, 3.0))
    save("boss_charge", rumble(1.6, 35, 120))
    save("alarm", siren(2.2))
    save("bell", bell())
    save("couple", reverb(mix(metal(0.5, 240, 1.0, 0.08), at(metal(0.4, 300, 0.7, 0.06), 0.09), lp(noise(0.2), 500) * env_exp(0.2, 0.04)), 0.4, 0.25))
    save("repair", mix(clicks(4, 0.06, 3000) * 0.5, at(chime([880, 1174.7], 0.07, "sine", 0.15), 0.15) * 0.6))
    save("upgrade", mix(clicks(6, 0.045, 2500) * 0.6, at(chime([659.25, 987.77, 1318.5], 0.06, "square", 0.12), 0.25) * 0.4))
    save("board", mix(clicks(5, 0.08, 1500) * 0.5, at(chime([783.99, 1046.5], 0.08, "tri", 0.15), 0.2) * 0.5))
    save("relic", mix(chime([523.25, 659.25, 783.99, 1046.5, 783.99, 1046.5, 1318.5], 0.075, "square", 0.25, 0.35) * 0.55,
                      chime([261.63, 329.63, 392.0], 0.0, "tri", 0.9, 0.3) * 0.5))
    save("radio", mix(static(0.4), at(blip(1200, 1200, 0.08, "sine"), 0.3), at(blip(1600, 1600, 0.08, "sine"), 0.42)))
    save("radio_blip", mix(static(0.12) * 0.5, blip(1400, 1400, 0.07, "sine")))
    save("type", hp(noise(0.012), 2500) * env_exp(0.012, 0.003) * 0.6)
    save("bad", osc(sweep(220, 150, 0.35), 0.35, "square") * env_ad(0.35, 0.01, 0.2) * 0.4)
    save("build", mix(metal(0.3, 400, 0.8, 0.05), at(metal(0.3, 470, 0.7, 0.05), 0.14), at(chime([659.25, 987.77], 0.07, "tri", 0.2), 0.3) * 0.6))
    # ui
    save("click", blip(900, 700, 0.035, "square"))
    save("hover", blip(1400, 1500, 0.018, "sine") * 0.5)
    save("pick", chime([783.99, 1174.66], 0.06, "square", 0.08, 0.15) * 0.5)
    save("buy", mix(blip(1800, 2400, 0.05), at(chime([987.77, 1318.5], 0.05, "tri", 0.1), 0.05)))
    save("card_get", mix(chime([987.77, 1318.5, 1760.0], 0.05, "tri", 0.1, 0.2) * 0.6, swish(0.1, 3000, 8000) * 0.3))
    save("card_pick", swish(0.09, 2000, 7000))
    save("card_back", swish(0.12, 800, 3000) * 0.8)
    save("discard", mix(swish(0.15, 1500, 6000), crackle(0.15, 900, 0.5)))
    save("scrap", blip(1500, 2100, 0.05, "square") * 0.6)
    save("scrap_1", blip(1650, 2300, 0.05, "square") * 0.6)
    save("scrap_big", mix(blip(1500, 2100, 0.05), at(blip(1800, 2500, 0.05), 0.06), at(blip(2100, 2900, 0.07), 0.12)))
    save("tick", blip(1100, 1100, 0.03, "tri"))
    save("heavy", boom(0.2))
    print("sfx written to", OUT)


if __name__ == "__main__":
    main()
