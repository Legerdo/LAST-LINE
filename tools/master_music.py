"""Master the YuE2 tracks for the game: trim leading silence, cut length, fades, loudness to -16 LUFS,
encode Ogg Vorbis. Sources stay untouched in art_src/music/<name>/source.wav.
usage: python tools/master_music.py
"""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art_src" / "music"
OUT = ROOT / "assets" / "audio" / "music"
# name: (max seconds, fade in, fade out)
PLAN = {"title": (70, 1.5, 3.0), "hub": (180, 1.5, 3.0), "boss": (200, 0.3, 2.0), "end": (80, 2.0, 8.0)}


def dur(p: Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(p)],
                         capture_output=True, text=True).stdout.strip()
    return float(out)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (max_s, fi, fo) in PLAN.items():
        src = SRC / name / "source.wav"
        if not src.exists():
            print("missing", src)
            continue
        tmp = SRC / name / "trim.wav"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-af",
                        "silenceremove=start_periods=1:start_threshold=-50dB", "-t", str(max_s), str(tmp)], check=True)
        d = dur(tmp)
        af = f"afade=t=in:d={fi},afade=t=out:st={max(0.0, d - fo):.2f}:d={fo},loudnorm=I=-16:TP=-1.5:LRA=11"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp), "-af", af, "-ar", "44100",
                        "-c:a", "libvorbis", "-q:a", "5", str(OUT / f"{name}.ogg")], check=True)
        print(f"{name}: {d:.1f}s -> {name}.ogg")


if __name__ == "__main__":
    main()
