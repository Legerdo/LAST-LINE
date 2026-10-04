"""Voice lines via Fish Audio TTS (s2.1-pro-free), then a PA / radio filter with ffmpeg.
The API key is read from FISH_API_KEY and never printed.
usage: python tools/gen_voice.py [name ...]
"""
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "art_src" / "voice_raw"
OUT = ROOT / "assets" / "audio" / "voice"
PA_VOICE = "9aae54921dd944948ee08d35f6b5f984"        # calm, measured female narrator
DISPATCH_VOICE = "4e298b87e291459aa9ede6ed07a6b336"  # serious middle-aged female narrator

LINES = {
    "depart": (DISPATCH_VOICE, "radio", "[calm] 마지막 노선, 운행을 시작합니다. 모두 손잡이를 꽉 잡으세요."),
    "station_1": (PA_VOICE, "pa", "[calm] 정차합니다. 생존자 여러분은 서둘러 탑승해 주십시오."),
    "station_2": (PA_VOICE, "pa", "[calm] 이번 역입니다. 문이 열립니다. 물린 분은 탑승하실 수 없습니다."),
    "station_3": (PA_VOICE, "pa", "[calm] 잠시 정차합니다. 선로 위의 이물질은... 신경 쓰지 마십시오."),
    "depot": (PA_VOICE, "pa", "[calm] 차량기지에 도착했습니다. 계속 운행하시겠습니까, 귀환하시겠습니까?"),
    "boss_warning": (PA_VOICE, "alarm", "[urgent] 비상 방송. 비상 방송. 죽은 노선에서 검은 열차가 접근 중입니다. 전원 전투 위치로."),
    "returned": (DISPATCH_VOICE, "radio", "[relieved] 귀환을 환영해. 오늘도 살아남았어."),
    "destroyed": (DISPATCH_VOICE, "radio", "[sad] ...열차 신호 소실. 응답하라. ...응답하라."),
    "victory": (DISPATCH_VOICE, "radio", "[excited] 검은 열차 정지 확인! 이 노선은... 이제 우리 거야."),
}

FILTERS = {
    "pa": "highpass=f=260,lowpass=f=3800,acompressor=threshold=-20dB:ratio=4:attack=5:release=80,"
          "aecho=0.7:0.45:55|110:0.22|0.12,volume=1.6",
    "radio": "highpass=f=380,lowpass=f=3100,acompressor=threshold=-22dB:ratio=5,acrusher=bits=11:mix=0.25,volume=1.8",
    "alarm": "highpass=f=300,lowpass=f=3500,acompressor=threshold=-22dB:ratio=6,acrusher=bits=9:mix=0.3,"
             "aecho=0.8:0.6:90|180:0.3|0.2,volume=1.9",
}


def tts(text: str, voice: str, dest: Path) -> None:
    key = os.environ.get("FISH_API_KEY")
    if not key:
        raise SystemExit("FISH_API_KEY is not set")
    body = json.dumps({"text": text, "format": "mp3", "reference_id": voice, "mp3_bitrate": 128,
                       "normalize": True}).encode("utf-8")
    req = urllib.request.Request("https://api.fish.audio/v1/tts", data=body, method="POST", headers={
        "Authorization": f"Bearer {key}", "Content-Type": "application/json", "model": "s2.1-pro-free"})
    with urllib.request.urlopen(req, timeout=180) as r:
        data = r.read()
    if data[:1] == b"{":
        raise RuntimeError("TTS error: " + data[:300].decode("utf-8", "replace"))
    dest.write_bytes(data)


def main():
    RAW.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    names = sys.argv[1:] or list(LINES.keys())
    for name in names:
        voice, flt, text = LINES[name]
        raw = RAW / f"{name}.mp3"
        if not raw.exists():
            tts(text, voice, raw)
        size = raw.stat().st_size
        out = OUT / f"{name}.ogg"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw), "-af",
                        FILTERS[flt] + ",afade=t=in:d=0.02,apad=pad_dur=0.25", "-ac", "1", "-ar", "44100",
                        "-c:a", "libvorbis", "-q:a", "5", str(out)], check=True)
        print(f"{name}: raw {size} bytes -> {out.name}")


if __name__ == "__main__":
    main()
