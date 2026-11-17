"""Publisher tool for the Existical Games signed tablet beta.

Signing material stays under ignored .tools/signing; passwords are passed through
environment variables rather than command arguments or committed export presets.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.30.5-beta.1"
PACKAGE = "com.existical.bigsnowshift.beta"
OUTPUT = ROOT / "builds/android/beta"
LOGS = OUTPUT / "logs"
SIGNING = ROOT / ".tools/signing"
KEYSTORE = SIGNING / "big-snow-shift-beta.keystore"
CREDENTIALS = SIGNING / "big-snow-shift-beta-signing.json"
APK = OUTPUT / ("BigSnowShift-" + VERSION + "-universal-release.apk")


def run(label, args, env=None, timeout=180):
    print(label, flush=True)
    log = LOGS / (label + ".log")
    with log.open("w", encoding="utf-8") as stream:
        result = subprocess.run(
            [str(arg) for arg in args], cwd=ROOT, env=env,
            stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT,
            timeout=timeout, check=False,
        )
    value = log.read_text(encoding="utf-8", errors="replace")
    if result.returncode != 0 or re.search(r"(?m)^(SCRIPT ERROR:|ERROR:|FAIL:)", value):
        raise RuntimeError(label + " failed; see " + str(log))
    return value


def main():
    LOGS.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT / "tools/godot-version.json").read_text(encoding="utf-8-sig"))
    engine = ROOT / (".tools/godot/" + lock["version"] + "/Godot_v" + lock["release"] + "_win64_console.exe")
    java_home = Path(os.environ.get("JAVA_HOME", "C:/Program Files/Eclipse Adoptium/jdk-17.0.17.10-hotspot"))
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or "C:/Android/SDK")
    versions = [path for path in (sdk / "build-tools").iterdir() if re.fullmatch(r"\d+\.\d+\.\d+", path.name)]
    build_tools = max(versions, key=lambda path: tuple(map(int, path.name.split("."))))
    java = java_home / "bin/java.exe"
    keytool = java_home / "bin/keytool.exe"
    signer = build_tools / "lib/apksigner.jar"
    for path in (engine, java, keytool, signer, ROOT / "assets/art/icon_caretaker_tree_v019.png", ROOT / "assets/art/icon_caretaker_tree_adaptive_v019.png", ROOT / "assets/art/icon_caretaker_tree_monochrome_v019.png"):
        if not path.is_file():
            raise FileNotFoundError(path)
    SIGNING.mkdir(parents=True, exist_ok=True)
    signing_env = os.environ.copy()
    if CREDENTIALS.is_file():
        credentials = json.loads(CREDENTIALS.read_text(encoding="utf-8"))
        if not KEYSTORE.is_file():
            raise RuntimeError("Existing beta credentials have no keystore. Restore the matching key before rebuilding.")
    else:
        if KEYSTORE.exists():
            raise RuntimeError("Existing beta keystore has no credential record. Restore its matching beta-signing.json.")
        credentials = {"alias": "big-snow-shift-beta", "password": secrets.token_hex(24)}
        # Persist the credentials first so an interrupted key generation remains recoverable.
        CREDENTIALS.write_text(json.dumps(credentials, indent=2) + "\n", encoding="utf-8")
        signing_env["BIG_SNOW_SHIFT_BETA_STORE_PASSWORD"] = credentials["password"]
        run("create-beta-key", [keytool, "-genkeypair", "-noprompt", "-keystore", KEYSTORE,
            "-alias", credentials["alias"], "-keyalg", "RSA", "-keysize", "3072", "-validity", "10000",
            "-dname", "CN=Big Snow Shift Beta, OU=Local Playtesting, O=Existical Games",
            "-storepass:env", "BIG_SNOW_SHIFT_BETA_STORE_PASSWORD", "-keypass:env", "BIG_SNOW_SHIFT_BETA_STORE_PASSWORD"], signing_env)
        signing_env.pop("BIG_SNOW_SHIFT_BETA_STORE_PASSWORD", None)
    signing_env.update({
        "GODOT_ANDROID_KEYSTORE_RELEASE_PATH": str(KEYSTORE),
        "GODOT_ANDROID_KEYSTORE_RELEASE_USER": credentials["alias"],
        "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": credentials["password"],
    })
    run("import", [engine, "--headless", "--path", ROOT, "--editor", "--import", "--quit"])
    run("export-beta-release", [engine, "--headless", "--path", ROOT, "--export-release", "Android Beta", APK], signing_env)
    signature = run("signature", [java, "-jar", signer, "verify", "--verbose", "--print-certs", APK])
    if "CN=Big Snow Shift Beta" not in signature or "CN=Android Debug" in signature:
        raise RuntimeError("Unexpected beta signing certificate.")
    manifest = run("manifest", [build_tools / "aapt.exe", "dump", "badging", APK])
    for required in ["package: name='" + PACKAGE + "'", "versionCode='63'", "versionName='" + VERSION + "'",
                     "application-label:'Big Snow Shift Beta'", "sdkVersion:'24'", "android.hardware.screen.landscape"]:
        if required not in manifest:
            raise RuntimeError("Unexpected APK metadata: " + required)
    if "application-debuggable" in manifest or "android.permission.INTERNET" in manifest:
        raise RuntimeError("Beta must be non-debuggable and offline.")
    xml = run("manifest-xml", [build_tools / "aapt.exe", "dump", "xmltree", APK, "AndroidManifest.xml"])
    # Godot's category enum is not Android's: Game is 2 in the preset and 0 in
    # the manifest. Android 16 exempts games from large-screen rotation overrides.
    if not re.search(r"android:appCategory\([^\n]+\)=\(type 0x10\)0x0\b", xml):
        raise RuntimeError("Beta must declare Android's Game application category.")
    if not re.search(r"android:screenOrientation\([^\n]+\)=\(type 0x10\)0x0\b", xml):
        raise RuntimeError("Beta must request landscape orientation.")
    run("alignment", [build_tools / "zipalign.exe", "-c", "-P", "16", "-v", "4", APK])
    credits = (ROOT / "assets/licenses/MUSIC_CREDITS.txt").read_bytes()
    with zipfile.ZipFile(APK) as archive:
        if any(name.endswith("game_settings.cfg") for name in archive.namelist()):
            raise RuntimeError("The retired external tuning file must not be packaged.")
        if any(name.endswith((".keystore", ".jks", "big-snow-shift-beta-signing.json", "export_credentials.cfg")) or name.startswith((".tools/", "assets/.tools/", "assets/reference/", "assets/archive/")) for name in archive.namelist()):
            raise RuntimeError("A private signing or research file was unexpectedly included in the APK.")
        architectures = sorted({name.split("/")[1] for name in archive.namelist() if name.startswith("lib/") and name.endswith(".so")})
        if architectures != ["arm64-v8a", "armeabi-v7a", "x86", "x86_64"]:
            raise RuntimeError("APK does not contain every configured tablet architecture.")
        credit_files = [name for name in archive.namelist() if name.endswith("MUSIC_CREDITS.txt")]
        if len(credit_files) != 1 or archive.read(credit_files[0]) != credits:
            raise RuntimeError("APK credits do not match current source.")
        for notice in ["SOUND_CREDITS.txt", "CC0-1.0.txt", "ASSET_LICENSES.txt"]:
            paths = [name for name in archive.namelist() if name.endswith("/" + notice)]
            if len(paths) != 1 or archive.read(paths[0]) != (ROOT / "assets/licenses" / notice).read_bytes():
                raise RuntimeError("APK sound credits or licences missing/stale: " + notice)
        font_notice = "MPLUSRounded1c-LICENSE.txt"
        notices = [name for name in archive.namelist() if name.endswith(font_notice)]
        if len(notices) != 1 or archive.read(notices[0]) != (ROOT / "assets/fonts" / font_notice).read_bytes():
            raise RuntimeError("APK must include the original rounded-font OFL notice.")
        if any("LilitaOne" in name for name in archive.namelist()):
            raise RuntimeError("Archived Lilita font was unexpectedly exported.")
        if any("winter_house.png" in name or "art-masters/" in name for name in archive.namelist()):
            raise RuntimeError("Retired background or source artwork was unexpectedly exported.")
        if any("icon_caretaker_tree_adaptive_v019.png" in name or "icon_caretaker_tree_monochrome_v019.png" in name for name in archive.namelist()):
            raise RuntimeError("Export-only launcher sources were unexpectedly bundled as game textures.")
        if not any("door_plain_v014.png-" in name and name.endswith(".ctex") for name in archive.namelist()):
            raise RuntimeError("Shared cottage/door texture is missing.")
    digest = hashlib.sha256(APK.read_bytes()).hexdigest()
    (OUTPUT / "SHA256SUMS.txt").write_text(digest + "  " + APK.name + "\n", encoding="utf-8")
    report = {"name": "Big Snow Shift Beta", "version": VERSION, "package": PACKAGE, "apk": APK.name, "bytes": APK.stat().st_size,
        "sha256": digest, "release_template": True, "debuggable": False, "signature_verified": True,
        "signer": "CN=Big Snow Shift Beta, OU=Local Playtesting, O=Existical Games", "zip_alignment": "passed, including 16 KiB library alignment",
        "architectures": architectures, "minimum_android_api": 24, "orientation": "landscape", "app_category": "game",
        "internet_permission": False, "credits_match_source": True, "sound_credits_match_source": True,
        "rounded_font_license_matches_source": True, "retired_lilita_absent": True,
        "external_tuning_file_absent": True,
        "physical_device_testing": "pending"}
    (OUTPUT / "build-verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("Beta ready: " + str(APK), flush=True)


if __name__ == "__main__":
    main()
