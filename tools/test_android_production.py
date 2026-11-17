"""Exercise device-specific APK splits generated from the exact upload AAB.

Only a newly started, disposable, read-only emulator is modified. Local split
APKs use the upload key for testing, not Google's eventual app-signing key.
"""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time
import zipfile

from build_android_production import ROOT, OUT, PACKAGE, run
from test_android_beta import adb, SDK, ADB, HIDDEN


def install_splits(label, serial, split_paths):
    # Some emulator/ADB combinations lose the final session response while
    # PackageManager is still compiling the app. Retry the same exact splits;
    # a normal successful install is still required before running any checks.
    for attempt in range(3):
        name = label + '-attempt-' + str(attempt + 1)
        try:
            return run(name, [ADB, '-s', serial, 'install-multiple', '--no-streaming', '-r', *split_paths])
        except RuntimeError:
            log = (OUT / 'logs' / (name + '.log')).read_text(encoding='utf-8')
            if 'failed to finalize session' not in log or attempt == 2:
                raise
            print('ADB lost the install completion response; retrying identical splits.', flush=True)
            time.sleep(4)


def main():
    java = Path(os.getenv('JAVA_HOME', 'C:/Program Files/Eclipse Adoptium/jdk-17.0.17.10-hotspot')) / 'bin/java.exe'
    bundletool = ROOT / '.tools/bundletool/bundletool-all-1.18.3.jar'
    aab = OUT / 'BigSnowShift-0.30.5-upload.aab'
    bundle_args = [java, '-jar', bundletool]
    adb('start-server')
    devices = adb('devices')
    port = next(n for n in range(5556,5682,2) if 'emulator-'+str(n) not in devices)
    serial = 'emulator-'+str(port)
    logs = OUT / 'logs'
    password_file = ROOT / '.tools/signing/upload-test-password.txt'
    emulator = None
    try:
        with (logs / 'emulator-host.log').open('w') as host:
            emulator = subprocess.Popen([str(SDK/'emulator/emulator.exe'), '-avd','Medium_Phone_API_36.1',
                '-port',str(port),'-read-only','-no-snapshot','-no-window','-no-boot-anim','-gpu','host','-cores','4','-memory','3072'],
                stdout=host, stderr=subprocess.STDOUT, creationflags=HIDDEN)
        deadline = time.monotonic()+180
        while adb('-s',serial,'shell','getprop','sys.boot_completed',check=False) != '1':
            if emulator.poll() is not None or time.monotonic()>deadline: raise RuntimeError('Emulator boot failed')
            time.sleep(2)
        print('Production split test: ' + serial,flush=True)
        # Match the beta harness: this disposable AVD's Bluetooth host bridge
        # can crash and leave a system dialog intercepting gameplay test taps.
        adb('-s',serial,'shell','svc','bluetooth','disable',check=False)
        adb('-s',serial,'shell','input','keyevent','4')
        adb('-s',serial,'shell','wm','size','1200x1600')
        adb('-s',serial,'shell','wm','density','240')
        adb('-s',serial,'shell','wm','user-rotation','lock','1')
        spec = OUT/'emulator-device-spec.json'
        run('device-spec',bundle_args+['get-device-spec','--adb='+str(ADB),'--device-id='+serial,'--output='+str(spec),'--overwrite'])
        credentials = json.loads((ROOT/'.tools/signing/production-upload-signing.json').read_text())
        password_file.write_text(credentials['password'])
        apks = OUT/'emulator-test.apks'
        run('device-splits',bundle_args+['build-apks','--bundle='+str(aab),'--output='+str(apks),'--overwrite',
            '--device-spec='+str(spec),'--ks='+str(ROOT/'.tools/signing/big-snow-shift-upload.keystore'),
            '--ks-key-alias='+credentials['alias'],'--ks-pass=file:'+str(password_file),'--key-pass=file:'+str(password_file)])
        password_file.unlink()
        run('split-download-size',bundle_args+['get-size','total','--apks='+str(apks),'--device-spec='+str(spec)])
        split_folder = OUT / 'emulator-splits'
        split_folder.mkdir(exist_ok=True)
        split_paths = []
        with zipfile.ZipFile(apks) as archive:
            for index, name in enumerate(n for n in archive.namelist() if n.endswith('.apk')):
                path = split_folder / f'split-{index}.apk'
                path.write_bytes(archive.read(name))
                split_paths.append(path)
        install_splits('install-splits', serial, split_paths)
        activity = adb('-s',serial,'shell','cmd','package','resolve-activity','--brief',PACKAGE).splitlines()[-1]
        assert activity.startswith(PACKAGE+'/')
        adb('-s',serial,'shell','am','start','-W','-n',activity)
        def app_log():
            pid = adb('-s',serial,'shell','pidof',PACKAGE,check=False)
            return adb('-s',serial,'logcat','-d','--pid='+pid) if pid.isdigit() else ''
        deadline = time.monotonic()+45
        while 'BIG_SNOW_SHIFT_GAME_READY' not in app_log():
            if time.monotonic()>deadline: raise RuntimeError('Production startup failed')
            time.sleep(1)
        def capture(name):
            windows = adb('-s',serial,'shell','dumpsys','window')
            focus = next((line for line in windows.splitlines() if 'mCurrentFocus=' in line), '')
            if PACKAGE not in focus or 'Application Error' in focus:
                (logs/(name+'-window-focus.log')).write_text(windows,encoding='utf-8')
                raise RuntimeError('Game is obscured or not focused at '+name+': '+focus.strip())
            data = subprocess.check_output([str(ADB),'-s',serial,'exec-out','screencap','-p'],creationflags=HIDDEN)
            assert data[:8] == b'\x89PNG\r\n\x1a\n'
            (OUT/(name+'.png')).write_bytes(data)
            return struct.unpack('>II',data[16:24])
        time.sleep(3)
        width,height=capture('android-tablet-01-menu')
        if width <= height:
            adb('-s',serial,'shell','wm','user-rotation','lock','1')
            time.sleep(3)
            width,height=capture('android-tablet-01-menu')
        assert width>height
        scale=min(width/1280,height/720); ox=(width-1280*scale)/2; oy=(height-720*scale)/2
        def tap(x,y):
            adb('-s',serial,'shell','input','tap',round(ox+x*scale),round(oy+y*scale)); time.sleep(.5)
        def back():
            adb('-s',serial,'shell','input','keyevent','4'); time.sleep(.5)
        tap(490,565) # Settings on a fresh menu.
        capture('android-tablet-settings')
        tap(640,602)
        capture('android-tablet-privacy-before')
        adb('-s',serial,'shell','input','swipe',round(ox+640*scale),round(oy+480*scale),round(ox+640*scale),round(oy+260*scale),650)
        time.sleep(.4)
        capture('android-tablet-privacy-after')
        back(); tap(790,602)
        capture('android-tablet-credits')
        back(); tap(400,602)
        tap(352,467)
        capture('android-tablet-02-difficulties')
        tap(185,300); tap(1040,650)
        adb('-s',serial,'shell','input','swipe',round(ox+400*scale),round(oy+500*scale),round(ox+400*scale),round(oy+500*scale),2500)
        capture('android-tablet-03-gameplay')
        tap(1218,58); capture('android-tablet-paused')
        # Background and cold Continue on the same signed production install.
        adb('-s',serial,'shell','input','keyevent','3'); time.sleep(.4)
        adb('-s',serial,'shell','am','force-stop',PACKAGE)
        adb('-s',serial,'shell','am','start','-W','-n',activity); time.sleep(3)
        capture('android-tablet-cold-menu')
        tap(352,467); capture('android-tablet-continued-paused')
        # Reinstall the exact same splits; persisted progress must remain.
        adb('-s',serial,'shell','am','force-stop',PACKAGE)
        install_splits('reinstall-splits', serial, split_paths)
        adb('-s',serial,'shell','am','start','-W','-n',activity); time.sleep(3)
        tap(352,467); capture('android-tablet-update-continue')
        # Capture a phone viewport too; release builds intentionally omit view telemetry.
        adb('-s',serial,'shell','wm','size','1080x1920')
        adb('-s',serial,'shell','wm','density','420')
        adb('-s',serial,'shell','wm','user-rotation','lock','1')
        time.sleep(3)
        width,height=capture('android-phone-01-paused')
        scale=min(width/1280,height/720); ox=(width-1280*scale)/2; oy=(height-720*scale)/2
        tap(640,328)
        capture('android-phone-02-gameplay')
        # Exercise the larger phone targets near their edges, including returning
        # to the overview after changing a rule on the secondary page.
        tap(1178,18); tap(640,504)  # Pause, Main menu
        tap(350,551); tap(225,552)  # New game, Custom game
        tap(377,198); capture('android-phone-custom-overview')
        tap(354,456); capture('android-phone-custom-options')
        tap(614,142); capture('android-phone-custom-edited')
        back(); capture('android-phone-custom-return')
        final_log=app_log()
        assert all(s not in final_log for s in ['SCRIPT ERROR:','FATAL EXCEPTION','ERROR:'])
        (logs/'production-app.log').write_text(final_log,encoding='utf-8')
        report={'aab_sha256':hashlib.sha256(aab.read_bytes()).hexdigest(),'package':PACKAGE,
            'device':'Disposable Android API 36.1 image, x86_64 emulator, tablet and phone viewports',
            'kernel_page_size':adb('-s',serial,'shell','getconf','PAGE_SIZE'),
            'device_specific_splits':True,'startup':True,'offline_privacy_and_touch':'screenshots captured for visual review',
            'gameplay_and_pause':'screenshots for visual review','cold_continue':'screenshots for visual review','same_identity_reinstall_continue':'screenshots for visual review',
            'runtime_errors':False,'signing':'local upload key; Play-generated app signature not yet tested',
            'physical_tablet_tested':False}
        (OUT/'emulator-verification.json').write_text(json.dumps(report,indent=2)+'\n')
        print('Production split installation completed; navigation and Continue screenshots ready for review',flush=True)
    finally:
        password_file.unlink(missing_ok=True)
        if emulator is not None and emulator.poll() is None:
            (logs/'emulator-system.log').write_text(adb('-s',serial,'logcat','-d','-t','2500',check=False),encoding='utf-8')
            adb('-s',serial,'emu','kill',check=False)
            try: emulator.wait(timeout=15)
            except subprocess.TimeoutExpired: emulator.terminate()


if __name__ == '__main__':
    main()
