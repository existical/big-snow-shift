"""Download unmodified SIL OFL display and regional fonts.

Development utility, never required at runtime. Sources and hashes are recorded
in localization/font-sources.json. Existing downloads are not replaced.
"""
import concurrent.futures
import hashlib
import json
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FONTS = [
    ("mplusrounded1c", "MPLUSRounded1c-Black.ttf", "MPLUSRounded1c-Black.ttf"),
    ("mplusrounded1c", "MPLUSRounded1c-ExtraBold.ttf", "MPLUSRounded1c-ExtraBold.ttf"),
    ("notosans", "NotoSans[wdth,wght].ttf", "NotoSans.ttf"),
    ("notosansarabic", "NotoSansArabic[wdth,wght].ttf", "NotoSansArabic.ttf"),
    ("notosanshebrew", "NotoSansHebrew[wdth,wght].ttf", "NotoSansHebrew.ttf"),
    ("notosansarmenian", "NotoSansArmenian[wdth,wght].ttf", "NotoSansArmenian.ttf"),
    ("notosansgeorgian", "NotoSansGeorgian[wdth,wght].ttf", "NotoSansGeorgian.ttf"),
    ("notosansthai", "NotoSansThai[wdth,wght].ttf", "NotoSansThai.ttf"),
    ("notosansjp", "NotoSansJP[wght].ttf", "NotoSansJP.ttf"),
    ("notosanskr", "NotoSansKR[wght].ttf", "NotoSansKR.ttf"),
    ("notosanssc", "NotoSansSC[wght].ttf", "NotoSansSC.ttf"),
    ("notosanstc", "NotoSansTC[wght].ttf", "NotoSansTC.ttf"),
]


def download(entry):
    folder, filename, local = entry
    directory = ROOT / "assets" / "fonts"
    source = "https://raw.githubusercontent.com/google/fonts/main/ofl/" + folder + "/"
    result = {}
    downloads = [(source + urllib.parse.quote(filename), local)]
    if folder == "mplusrounded1c":
        # Both weights share one notice. One worker downloads it to avoid
        # racing two writes; the renamed Google Fonts directory owns the OFL.
        if "Black" in filename:
            downloads.append(("https://raw.githubusercontent.com/google/fonts/main/ofl/roundedmplus1c/OFL.txt", "MPLUSRounded1c-LICENSE.txt"))
    else:
        downloads.append((source + "OFL.txt", local.removesuffix(".ttf") + "-LICENSE.txt"))
    for url, destination in downloads:
        path = directory / destination
        if not path.exists():
            with urllib.request.urlopen(url, timeout=120) as response:
                data = response.read()
            if len(data) < 100:
                raise ValueError(f"Empty download: {url}")
            path.write_bytes(data)
        result[destination] = {"source": url, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "bytes": path.stat().st_size}
    print(local + " ready", flush=True)
    return result


if __name__ == "__main__":
    sources = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        for result in executor.map(download, FONTS):
            sources.update(result)
    (ROOT / "localization" / "font-sources.json").write_text(
        json.dumps(sources, indent=2) + "\n", encoding="utf-8")
