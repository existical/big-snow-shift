"""Package the reviewed source inventory and verify the archived file hashes."""
import hashlib
import json
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
INVENTORY = ROOT / "tools/source-files.txt"


def source_files():
    names = INVENTORY.read_text(encoding="utf-8").splitlines()
    if names != sorted(set(names)):
        raise ValueError("Sort the source inventory and remove duplicate paths.")
    for name in names:
        path = PurePosixPath(name)
        if (not name or path.as_posix() != name or path.is_absolute()
                or ".." in path.parts or ":" in name or "\\" in name):
            raise ValueError(f"Invalid source path: {name!r}")
        source = ROOT / path
        if not source.is_file() or source.resolve() != source:
            raise ValueError(f"Expected a regular project file: {name}")
    if (ROOT / ".git").exists():
        tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
        difference = set(tracked.decode("utf-8").split("\0")[:-1]) ^ set(names)
        if difference:
            raise ValueError("Git and source inventory differ:\n" + "\n".join(sorted(difference)))
    return names


def main():
    names = source_files()
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    version = re.search(r'^config/version="([^"]+)"$', project, re.MULTILINE)[1]
    output = ROOT / f"builds/BigSnowShift-{version}-Source.zip"
    output.parent.mkdir(exist_ok=True)
    report_dir = output.parent / "release-preparation"
    report_dir.mkdir(exist_ok=True)
    manifest = {}
    with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".tmp", delete=False) as file:
        temporary = Path(file.name)
    try:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for name in names:
                data = (ROOT / name).read_bytes()
                archive.writestr("BigSnowShift/" + name, data)
                manifest[name] = hashlib.sha256(data).hexdigest()
            archive.writestr("BigSnowShift/SOURCE_MANIFEST.json", json.dumps(manifest, indent=2) + "\n")
        with zipfile.ZipFile(temporary) as archive:
            for name, digest in manifest.items():
                if hashlib.sha256(archive.read("BigSnowShift/" + name)).hexdigest() != digest:
                    raise ValueError(f"Archive checksum mismatch: {name}")
            if json.loads(archive.read("BigSnowShift/SOURCE_MANIFEST.json")) != manifest:
                raise ValueError("Archive manifest mismatch")
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    report = {"archive": output.name, "files": len(names) + 1, "bytes": output.stat().st_size,
              "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "allowlisted": True,
              "archive_integrity": True}
    (report_dir / "source-package.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {output} ({len(names)} source files plus manifest)")


if __name__ == "__main__":
    main()
