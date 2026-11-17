"""Install the pinned official Godot editor and Windows/Android templates locally.

Uses Python's standard library and the operating system's certificate store.
Run from any working directory: python tools/setup_godot.py
"""

from __future__ import annotations

import hashlib
import json
import shutil
import urllib.request
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
LOCK = json.loads((ROOT / "tools/godot-version.json").read_text(encoding="utf-8"))
VERSION = LOCK["version"]
RELEASE = LOCK["release"]
TOOLS = ROOT / ".tools"
DOWNLOADS = TOOLS / "downloads"
INSTALL = TOOLS / "godot" / VERSION
BASE_URL = f"https://github.com/godotengine/godot-builds/releases/download/{RELEASE}"
TEMPLATES = {
    "version.txt",
    "windows_debug_x86_64.exe",
    "windows_release_x86_64.exe",
    "android_debug.apk",
    "android_release.apk",
    "android_source.zip",
}


def sha256(path: Path) -> str:
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def download(name: str, expected_hash: str) -> Path:
    path = DOWNLOADS / name
    if path.is_file():
        if sha256(path) != expected_hash:
            raise RuntimeError(f"Existing download has an unexpected checksum: {path}")
        print(f"Verified cached {name}", flush=True)
        return path
    partial = path.with_suffix(path.suffix + ".partial")
    request = urllib.request.Request(
        f"{BASE_URL}/{name}", headers={"User-Agent": "BigSnowShift-Godot-Setup"}
    )
    digest = hashlib.sha256()
    count = 0
    next_report = 64 * 1024 * 1024
    print(f"Downloading {name}", flush=True)
    with urllib.request.urlopen(request, timeout=60) as response, partial.open("wb") as out:
        total = int(response.headers.get("Content-Length", 0))
        while chunk := response.read(4 * 1024 * 1024):
            out.write(chunk)
            digest.update(chunk)
            count += len(chunk)
            if count >= next_report:
                print(f"  {count // (1024 * 1024)} / {total // (1024 * 1024)} MiB", flush=True)
                next_report += 64 * 1024 * 1024
    if digest.hexdigest() != expected_hash:
        raise RuntimeError(f"Checksum mismatch; archive was not installed: {partial}")
    partial.replace(path)
    print(f"SHA-256 verified: {name}", flush=True)
    return path


def extract_selected(archive: Path, destination: Path, names: set[str]) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as source:
        entries = {Path(info.filename).name: info for info in source.infolist() if not info.is_dir()}
        missing = names - entries.keys()
        if missing:
            raise RuntimeError(f"Missing archive entries: {sorted(missing)}")
        for name in sorted(names):
            target = (destination / name).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise RuntimeError("Archive destination escaped the installation directory")
            with source.open(entries[name]) as src, target.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            print(f"Installed {name}", flush=True)


def main() -> None:
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    (TOOLS / ".gdignore").touch()
    editor_name = f"Godot_v{RELEASE}_win64.exe.zip"
    templates_name = f"Godot_v{RELEASE}_export_templates.tpz"
    editor = download(editor_name, LOCK["editor_sha256"])
    extract_selected(editor, INSTALL, {
        f"Godot_v{RELEASE}_win64.exe",
        f"Godot_v{RELEASE}_win64_console.exe",
    })
    (INSTALL / "_sc_").touch()
    templates = download(templates_name, LOCK["templates_sha256"])
    template_dir = INSTALL / "editor_data/export_templates" / f"{VERSION}.stable"
    extract_selected(templates, template_dir, TEMPLATES)
    manifest = {
        "version": VERSION,
        "release": RELEASE,
        "source": f"https://github.com/godotengine/godot-builds/releases/tag/{RELEASE}",
        "editor_sha256": LOCK["editor_sha256"],
        "templates_sha256": LOCK["templates_sha256"],
        "installed_templates": sorted(TEMPLATES),
        "self_contained": True,
    }
    (INSTALL / "install.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Godot is ready at {INSTALL}", flush=True)


if __name__ == "__main__":
    main()
