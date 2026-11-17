"""Fetch the selected Kevin MacLeod recordings and prepare credited game audio.

Original MP3s and the official catalogue are cached under reference/ (not exported).
The game receives unchanged MP3 files and a provenance manifest. Playback gain
is measured separately by tools/measure_music.gd.
"""
import hashlib
import json
import urllib.parse
import shutil
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "reference/audio/incompetech"
OUTPUT = ROOT / "assets/audio/music"
CATALOGUE = "https://incompetech.com/music/royalty-free/pieces.json"
LICENSE = "https://creativecommons.org/licenses/by/4.0/"
SELECTION = [
    ("jingle_bells", "USUAN1100187", "menu"),
    ("blue_ska", "USUAN1600011", "gameplay"),
    ("sunday_dub", "USUAN1700031", "gameplay"),
    ("no_frills_comparsa", "USUAN1100285", "gameplay"),
    ("peppy_pepe", "USUAN1100115", "gameplay"),
    ("bama_country", "USUAN1100359", "gameplay"),
]


def fetch(url, destination):
    if destination.exists():
        return
    request = urllib.request.Request(url, headers={"User-Agent": "BigSnowShift soundtrack preparation"})
    with urllib.request.urlopen(request, timeout=90) as response:
        data = response.read()
    temporary = destination.with_suffix(destination.suffix + ".download")
    temporary.write_bytes(data)
    temporary.replace(destination)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    fetch(CATALOGUE, CACHE / "pieces.json")
    catalogue = json.loads((CACHE / "pieces.json").read_text(encoding="utf-8"))
    records = []
    for identifier, isrc, role in SELECTION:
        piece = next(item for item in catalogue if item["isrc"] == isrc)
        url = "https://incompetech.com/music/royalty-free/mp3-royaltyfree/" + urllib.parse.quote(piece["filename"])
        original = CACHE / (isrc + ".mp3")
        output = OUTPUT / (identifier + ".mp3")
        print("Preparing " + piece["title"] + " (" + isrc + ")", flush=True)
        fetch(url, original)
        if original.read_bytes()[:1] == b"<":
            raise ValueError("Expected MP3, received HTML: " + url)
        shutil.copyfile(original, output)
        records.append({
            "id": identifier, "title": piece["title"], "artist": "Kevin MacLeod", "isrc": isrc,
            "role": role, "catalogue_filename": piece["filename"], "download_url": url,
            "source_page": "https://incompetech.com/music/royalty-free/index.html?isrc=" + isrc,
            "license": "CC-BY-4.0", "license_url": LICENSE,
            "path": str(output.relative_to(ROOT)).replace("\\", "/"),
            "original_sha256": sha(original), "game_audio_sha256": sha(output),
            "modifications": "Original MP3 copied unchanged. Playback volume is balanced by the game; no musical edits.",
        })
    manifest = {
        "version": "0.19.0", "retrieved": "2026-11-12", "catalogue_url": CATALOGUE,
        "music": records,
        "aliases": {"Comparsa": "no_frills_comparsa", "No Frills Comparsa": "no_frills_comparsa"},
    }
    (ROOT / "docs/soundtrack-v0.19.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    credits = ["BIG SNOW SHIFT — MUSIC CREDITS", "", "All tracks below are by Kevin MacLeod (incompetech.com).", "Creative Commons Attribution 4.0 International (CC BY 4.0)", LICENSE]
    for item in records:
        credits.extend(["", '"' + item["title"] + '" — Kevin MacLeod', "ISRC: " + item["isrc"], "Source: " + item["source_page"]])
    credits.extend(["", "The game balances playback volume for the six original, unedited recordings."])
    (ROOT / "assets/licenses/MUSIC_CREDITS.txt").write_text("\n".join(credits) + "\n", encoding="utf-8")
    fetch(LICENSE + "legalcode.txt", ROOT / "assets/licenses/CC-BY-4.0.txt")
    print("Prepared " + str(len(records)) + " distinct recordings and licence records.", flush=True)


if __name__ == "__main__":
    main()
