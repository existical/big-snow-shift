"""Recreate the historical 0.29.0 synthesized effects for comparison.

Requires FFmpeg with libvorbis. Pass --ffmpeg if it is not in PATH; the pinned
local development copy is used when present. Outputs go to builds/original-effects;
the current third-party click/win/lose assets and their manifest are never changed.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import struct
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 44100


def tone(buffer, start, note, duration, gain, soft=False):
    frequency = 440 * 2 ** ((note - 69) / 12)
    offset = round(start * RATE)
    for i in range(round(duration * RATE)):
        if offset + i >= len(buffer):
            break
        t = i / RATE
        attack = min(t / .008, 1.0)
        release = min((duration - t) / .08, 1.0)
        decay = math.exp(-t * (3.7 if soft else 4.8))
        partials = ((1, 1), (2, .16 if soft else .25), (3, .05), (4.02, .025))
        value = sum(amplitude * math.sin(math.tau * frequency * multiple * t)
                    for multiple, amplitude in partials)
        buffer[offset + i] += value * attack * release * decay * gain


def synthesize(name):
    duration = {"click": .16, "win": 2.8, "lose": 1.9}[name]
    buffer = [0.0] * round(duration * RATE)
    if name == "click":
        tone(buffer, 0, 88, .14, .23)
        tone(buffer, .012, 76, .12, .11, True)
    elif name == "win":
        for start, note in [(0, 72), (.15, 76), (.30, 79), (.48, 84)]:
            tone(buffer, start, note, 1.1, .20)
        for note in [60, 67, 76, 84]:
            tone(buffer, .85, note, 1.8, .11, True)
        tone(buffer, 1.15, 91, 1.3, .06)
    else:
        # A gentle, short falling phrase; no harsh failure buzzer.
        for start, note in [(0, 67), (.24, 64), (.50, 60)]:
            tone(buffer, start, note, 1.25, .21, True)
        tone(buffer, .50, 48, 1.3, .09, True)
    peak = max(abs(value) for value in buffer)
    gain = min(1.0, .72 / peak)
    samples = [max(-32767, min(32767, round(value * gain * 32767))) for value in buffer]
    return samples, peak * gain


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", type=Path)
    args = parser.parse_args()
    local = ROOT / ".tools/video/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v9.0.2.exe"
    encoder = args.ffmpeg or (local if local.is_file() else shutil.which("ffmpeg"))
    if not encoder:
        raise RuntimeError("FFmpeg with libvorbis is required. Use --ffmpeg PATH.")
    work = ROOT / "builds/original-effects"
    work.mkdir(parents=True, exist_ok=True)
    manifest_path = work / "synthesized-effects.json"
    manifest = {"creator": "Andrjus Valkuns / Existical Games", "license": "CC-BY-4.0",
                "license_url": "https://creativecommons.org/licenses/by/4.0/",
                "method": "Original oscillator synthesis; historical 0.29.0 cues.",
                "effects": []}
    for name in ["click", "win", "lose"]:
        target = work / (name + ".ogg")
        samples, peak = synthesize(name)
        pcm = work / (name + ".wav")
        with wave.open(str(pcm), "wb") as stream:
            stream.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
            stream.writeframes(struct.pack("<" + "h" * len(samples), *samples))
        subprocess.run([str(encoder), "-hide_banner", "-loglevel", "error", "-y", "-i", str(pcm),
                        "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", "5",
                        "-fflags", "+bitexact", "-flags:a", "+bitexact", str(target)], check=True)
        manifest["effects"].append({"path": target.relative_to(ROOT).as_posix(),
                                    "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                                    "duration_seconds": len(samples) / RATE,
                                    "sample_rate": RATE, "pcm_peak": round(peak, 6)})
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("Historical synthesized cues generated in builds/original-effects; game audio preserved.")


if __name__ == "__main__":
    main()
