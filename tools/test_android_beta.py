"""Smoke-check the exact release APK in a disposable Android Studio emulator.

Requires the existing Medium_Phone_API_36.1 AVD and host GPU. Screenshots allow
visual verification without enabling debug telemetry in the tablet release.
"""
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "builds/android/beta"
LOGS = OUTPUT / "logs"
PACKAGE = "com.existical.bigsnowshift.beta"
APK = OUTPUT / "BigSnowShift-0.30.5-beta.1-universal-release.apk"
SDK = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME") or "C:/Android/SDK")
ADB = SDK / "platform-tools/adb.exe"
HIDDEN = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def adb(*args, check=True, timeout=40):
    result = subprocess.run([str(ADB), *map(str, args)], capture_output=True,
        text=True, encoding="utf-8", errors="replace", timeout=timeout, creationflags=HIDDEN)
    if check and result.returncode:
        raise RuntimeError("ADB failed: " + result.stdout + result.stderr)
    return result.stdout.strip()


def main():
    if not APK.is_file():
        raise FileNotFoundError(APK)
    LOGS.mkdir(parents=True, exist_ok=True)
    # A TCP listener is enough to avoid claiming another caller's ADB server.
    import socket
    with socket.socket() as probe:
        owned_server = probe.connect_ex(("127.0.0.1", 5037)) != 0
    emulator = None
    serial = ""
    handles = []
    try:
        (OUTPUT / "emulator-verification.json").write_text(json.dumps({"status":"running", "apk":APK.name}) + "\n", encoding="utf-8")
        adb("start-server")
        devices = adb("devices")
        port = next(value for value in range(5556, 5682, 2) if "emulator-" + str(value) not in devices)
        serial = "emulator-" + str(port)
        for name in ("emulator-host.log", "emulator-host-errors.log"):
            handles.append((LOGS / name).open("w", encoding="utf-8"))
        emulator = subprocess.Popen([str(SDK / "emulator/emulator.exe"), "-avd", "Medium_Phone_API_36.1",
            "-port", str(port), "-read-only", "-no-snapshot", "-no-window", "-no-boot-anim",
            "-gpu", "host", "-cores", "4"], stdout=handles[0], stderr=handles[1], creationflags=HIDDEN)
        print("Booting disposable beta emulator " + serial, flush=True)
        deadline = time.monotonic() + 180
        while adb("-s", serial, "shell", "getprop", "sys.boot_completed", check=False) != "1":
            if emulator.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError("Emulator did not boot; see beta logs.")
            time.sleep(2)
        adb("-s", serial, "shell", "svc", "bluetooth", "disable", check=False)
        adb("-s", serial, "shell", "input", "keyevent", "4")
        # Only this disposable read-only emulator is changed. Exercise a tablet
        # aspect ratio instead of relying on the AVD's tall phone display.
        adb("-s", serial, "shell", "wm", "size", "1200x1600")
        adb("-s", serial, "shell", "wm", "density", "240")
        print("Installing the exact signed beta APK", flush=True)
        install = adb("-s", serial, "install", "-r", APK, timeout=90)
        if "Success" not in install:
            raise RuntimeError("Beta installation did not succeed: " + install)
        activity = adb("-s", serial, "shell", "cmd", "package", "resolve-activity", "--brief", PACKAGE).splitlines()[-1]
        if not activity.startswith(PACKAGE + "/"):
            raise RuntimeError("Beta launcher activity could not be resolved.")
        adb("-s", serial, "shell", "am", "start", "-W", "-n", activity)
        deadline = time.monotonic() + 45
        app_log = ""
        while time.monotonic() < deadline:
            pid = adb("-s", serial, "shell", "pidof", PACKAGE, check=False)
            if pid.isdigit():
                app_log = adb("-s", serial, "logcat", "-d", "--pid=" + pid)
                if "BIG_SNOW_SHIFT_GAME_READY" in app_log:
                    break
            time.sleep(1)
        if "BIG_SNOW_SHIFT_GAME_READY" not in app_log:
            raise RuntimeError("Release game startup was not observed.")
        (LOGS / "android-app.log").write_text(app_log, encoding="utf-8")
        activity_info = adb("-s", serial, "shell", "dumpsys", "activity", "activities")
        (LOGS / "tablet-activity.log").write_text(activity_info, encoding="utf-8")
        game_info = activity_info.split("packageName=" + PACKAGE, 1)[-1]
        config = re.search(r"CurrentConfiguration=([^\n]+)", game_info)
        if not config or " land " not in config.group(1):
            raise RuntimeError("Installed game activity is not configured for landscape.")

        def capture(name):
            adb("-s", serial, "shell", "screencap", "-p", "/sdcard/big-snow-shift-beta.png")
            path = OUTPUT / name
            adb("-s", serial, "pull", "/sdcard/big-snow-shift-beta.png", path)
            data = path.read_bytes()
            if data[:8] != b"\x89PNG\r\n\x1a\n":
                raise RuntimeError("Invalid beta screenshot.")
            return struct.unpack(">II", data[16:24])

        time.sleep(3)
        width, height = capture("beta-menu.png")
        device_rotated = False
        if width <= height:
            capture("beta-tablet-held-portrait.png")
            # Large-screen Android may leave the physical display upright while
            # letterboxing a correctly-landscape game. Simulate holding the
            # tablet horizontally; do not change the app's orientation policy.
            adb("-s", serial, "shell", "wm", "user-rotation", "lock", "1")
            time.sleep(3)
            width, height = capture("beta-menu.png")
            device_rotated = True
        if width <= height:
            raise RuntimeError("Tablet display did not rotate to landscape.")
        scale = min(width / 1280, height / 720)
        offset = (width - 1280 * scale) / 2
        offset_y = (height - 720 * scale) / 2
        def tap(x, y):
            adb("-s", serial, "shell", "input", "tap", round(offset + x * scale), round(offset_y + y * scale))
        tap(352, 467)
        time.sleep(1)
        capture("beta-difficulty-default.png")
        tap(1068, 270)
        time.sleep(.4)
        capture("beta-difficulty-extreme.png")
        tap(497, 270)
        time.sleep(.4)
        capture("beta-difficulty-medium.png")
        tap(210, 270)
        tap(240, 560)  # Separate Custom game screen.
        time.sleep(.4)
        tap(928, 178)
        time.sleep(.4)
        capture("beta-custom-help.png")
        tap(200, 650)  # Back to fixed Easy; Custom switches cannot leak.
        time.sleep(.4)
        tap(1019, 650)
        time.sleep(.5)
        capture("beta-gameplay-start.png")
        x, y = round(offset + 415 * scale), round(offset_y + 665 * scale)
        adb("-s", serial, "shell", "input", "swipe", x, y, x, y, 2500)
        capture("beta-gameplay-sideways.png")
        x, y = round(offset + 636 * scale), round(offset_y + 450 * scale)
        adb("-s", serial, "shell", "input", "swipe", x, y, x, y, 3500)
        capture("beta-gameplay-cleared.png")
        adb("-s", serial, "shell", "input", "keyevent", "4")
        time.sleep(1)
        capture("beta-paused.png")
        tap(640, 420)
        time.sleep(.4)
        capture("beta-easy-settings-locked-rules.png")
        tap(360, 602)  # Done returns to Pause with the same rules.
        time.sleep(.4)
        capture("beta-easy-unchanged-after-settings.png")
        tap(640, 502)  # Main menu, then a new game's draft.
        time.sleep(.4)
        tap(352, 555)
        time.sleep(.4)
        tap(240, 560)  # Custom settings exist only in pre-game setup.
        time.sleep(.4)
        # Saved switches are still on after the earlier cancelled edit/reset.
        tap(352,178)
        tap(928,178)
        for x,y in [(574,262),(1150,262),(574,348),(574,520)]:
            tap(x,y)
            time.sleep(.25)
        capture("beta-custom-numeric-values.png")
        tap(925,580)  # Hide landing warnings, preserving the falling icicles.
        capture("beta-hidden-landing-warnings.png")
        tap(312,580)  # One round; independent of the optional help switches.
        capture("beta-one-round-selected.png")
        tap(352,178)  # Untimed Custom, with icicles still active.
        time.sleep(.4)
        capture("beta-custom-before-start.png")
        tap(1019, 650)
        time.sleep(.4)
        capture("beta-custom-replacement-confirmation.png")
        tap(802, 462)  # Confirm a new run; the previous run was never edited.
        time.sleep(.5)
        capture("beta-new-custom-game.png")
        tap(1218, 58)
        time.sleep(.4)
        capture("beta-paused-custom-untimed.png")
        tap(1218, 58)
        time.sleep(.5)
        capture("beta-corner-resumed.png")
        tap(1218, 58)
        time.sleep(.5)
        capture("beta-corner-paused.png")
        adb("-s", serial, "shell", "input", "keyevent", "3")
        time.sleep(1)
        adb("-s", serial, "shell", "am", "start", "-W", "-n", activity)
        time.sleep(1)
        capture("beta-background-return.png")
        # Exercise the real menu button, process exit and saved-run return in
        # the non-debuggable release. No run-as or staged player data is used.
        pid = adb("-s", serial, "shell", "pidof", PACKAGE)
        if not pid.isdigit():
            raise RuntimeError("Beta process exited during the smoke check.")
        app_log = adb("-s", serial, "logcat", "-d", "--pid=" + pid)
        tap(640, 502)
        time.sleep(1)
        capture("beta-menu-with-save.png")
        tap(200,643)
        time.sleep(.5)
        capture("beta-scores-simple.png")
        tap(1060,220)  # My results uses the same touch target as its icon.
        time.sleep(.5)
        capture("beta-scores-personal.png")
        tap(640,644)  # The single centered Main menu action.
        time.sleep(.5)
        capture("beta-scores-return-to-menu.png")
        tap(1218, 58)
        exit_deadline = time.monotonic() + 10
        while adb("-s", serial, "shell", "pidof", PACKAGE, check=False):
            if time.monotonic() >= exit_deadline:
                raise RuntimeError("Red menu X did not close the game process.")
            time.sleep(.3)
        app_log += "\n" + adb("-s", serial, "logcat", "-d", "--pid=" + pid)
        capture("beta-exited.png")
        adb("-s", serial, "shell", "am", "start", "-W", "-n", activity)
        time.sleep(3)
        capture("beta-menu-after-exit.png")
        tap(352, 467)
        time.sleep(1)
        capture("beta-continue-after-exit.png")
        # Continue opens the pause menu already; Back would resume gameplay.
        tap(640,420)
        time.sleep(.5)
        capture("beta-continued-settings-locked-rules.png")
        tap(360,602)
        time.sleep(.5)
        capture("beta-continued-custom-pause.png")
        restored_pid = adb("-s", serial, "shell", "pidof", PACKAGE)
        if not restored_pid.isdigit():
            raise RuntimeError("Game did not relaunch after using the menu X.")
        app_log += "\n" + adb("-s", serial, "logcat", "-d", "--pid=" + restored_pid)
        (LOGS / "android-app.log").write_text(app_log, encoding="utf-8")
        if re.search(r"(?mi)\bgodot\s+:\s+(SCRIPT ERROR:|ERROR:)", app_log) or "FATAL EXCEPTION" in app_log:
            raise RuntimeError("Beta logged a runtime error; see android-app.log.")
        package_info = adb("-s", serial, "shell", "dumpsys", "package", PACKAGE)
        (LOGS / "installed-package.log").write_text(package_info, encoding="utf-8")
        if re.search(r"(?m)^\s*(?:pkgFlags|flags)=\[[^\]]*\bDEBUGGABLE\b", package_info):
            raise RuntimeError("Installed beta is debuggable.")
        # Full ending flows use a separate package with byte-identical game
        # scripts/assets and a test-only entry point. The production APK above
        # stays non-debuggable; no root or user-device save injection is needed.
        review_package = "com.existical.bigsnowshift.roundcountreview"
        review_apk = ROOT / "builds/round-count/android/RoundCountReview.apk"
        if not review_apk.is_file():
            raise FileNotFoundError("Run tools/build_round_count_review.py first")
        assert serial.startswith("emulator-") and emulator.poll() is None
        adb("-s", serial, "install", "-r", review_apk, timeout=90)
        review_activity = adb("-s", serial, "shell", "cmd", "package", "resolve-activity", "--brief", review_package).splitlines()[-1]
        adb("-s", serial, "shell", "am", "start", "-W", "-n", review_activity)
        deadline = time.monotonic()+90
        review_log = ""
        while time.monotonic() < deadline:
            review_pid = adb("-s", serial, "shell", "pidof", review_package, check=False)
            if review_pid.isdigit():
                review_log = adb("-s", serial, "logcat", "-d", "--pid="+review_pid)
                if "ROUND_COUNT_ANDROID_DONE" in review_log: break
                if "SCRIPT ERROR:" in review_log or "FATAL EXCEPTION" in review_log:
                    raise RuntimeError("Android short-game review failed: "+review_log[-2500:])
            time.sleep(1)
        (LOGS / "round-count-review.log").write_text(review_log,encoding="utf-8")
        if "ROUND_COUNT_ANDROID_DONE" not in review_log:
            raise RuntimeError("Android short-game review timed out")
        short_results = json.loads(adb("-s", serial, "shell", "run-as", review_package, "cat", "files/round-count-review-result.json"))
        if short_results.get("failures") or short_results.get("completed_lengths") != [1,2]:
            raise RuntimeError("Android short-game checks failed: "+str(short_results))
        review_output = ROOT / "builds/round-count/android"
        (review_output / "tests.json").write_text(json.dumps(short_results,indent=2),encoding="utf-8")
        files = adb("-s", serial, "shell", "run-as", review_package, "ls", "files").splitlines()
        for filename in files:
            if re.fullmatch(r"round-count-[\w-]+\.png",filename):
                result = subprocess.run([str(ADB),"-s",serial,"exec-out","run-as",review_package,"cat","files/"+filename],capture_output=True,check=True,timeout=30,creationflags=HIDDEN)
                (review_output / filename).write_bytes(result.stdout)
        report = {"apk": APK.name, "package": PACKAGE, "install": "passed", "release_startup": "passed",
            "short_custom_games": short_results,
            "display": str(width) + "x" + str(height), "android": adb("-s", serial, "shell", "getprop", "ro.build.version.release"),
            "abi": adb("-s", serial, "shell", "getprop", "ro.product.cpu.abi"),
            "touch_and_back": "screenshots captured for visual review", "background_return": "screenshot captured for visual review",
            "corner_pause_resume": "paused, resumed and paused-again screenshots captured for visual review",
            "debuggable": False, "runtime_errors": "no Godot script/engine errors observed", "physical_tablet_testing": "pending",
            "viewport": "4:3 tablet geometry in disposable AVD",
            "app_landscape_configuration": "passed before rotating physical display",
            "tablet_held_horizontally": device_rotated,
            "difficulty_controls": "Fixed Easy started after cancelling Custom; Custom numeric controls exercised only through New game, with replacement confirmation before starting",
            "locked_rules": "Settings from Easy and continued Custom have no rule editor; pause return screenshots captured for visual review",
            "scores_navigation": "Scores and My results opened by touch; the single Main menu action returned to the saved game's menu; screenshots captured",
            "menu_exit_process_closed": "passed",
            "exit_and_continue": "cold relaunch and Continue screenshots captured for visual review",
            "audio_service_warnings": [line for line in app_log.splitlines() if "E libOpenSLES:" in line],
            "audio": "initialization passed; human listening not assessed"}
        (OUTPUT / "emulator-verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print("Release beta installed and ran successfully; screenshots ready for review.", flush=True)
    finally:
        if emulator is not None:
            adb("-s", serial, "emu", "kill", check=False)
            try:
                emulator.wait(timeout=15)
            except subprocess.TimeoutExpired:
                emulator.terminate()
                emulator.wait(timeout=10)
        for handle in handles:
            handle.close()
        if owned_server:
            # The owned emulator can remain listed as offline briefly after it
            # exits. Only somebody else's device should keep our server alive.
            other_devices = [line for line in adb("devices").splitlines()
                if re.match(r"^\S+\s+(?:device|offline|unauthorized)\s*$", line)
                and line.split()[0] != serial]
            if not other_devices:
                adb("kill-server", check=False)


if __name__ == "__main__":
    main()
