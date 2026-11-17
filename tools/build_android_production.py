"""Publisher tool for the Existical Games Google Play upload bundle.

Requires a verified Windows package first. Signing secrets stay in .tools/signing.
The production application ID remains reviewable until its first store upload.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import zipfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'builds/android/production'
LOGS = OUT / 'logs'
VERSION = '0.30.5'
PACKAGE = 'com.existical.bigsnowshift'
BUNDLETOOL_SHA256 = 'a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29'


def run(name, args, env=None, timeout=900):
    print(name, flush=True)
    result = subprocess.run(list(map(str, args)), cwd=ROOT, env=env,
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout)
    text = result.stdout.decode('utf-8', errors='replace')
    # Godot/Gradle diagnostics can echo command arguments. Redact secret values
    # before writing any retained diagnostic log.
    for key, value in (env or {}).items():
        if ('PASSWORD' in key or key.endswith('_PASS')) and value:
            text = text.replace(value, '[REDACTED]')
    (LOGS / (name + '.log')).write_text(text, encoding='utf-8')
    if result.returncode or re.search(r'(?m)^(ERROR:|SCRIPT ERROR:|FAIL:)', text):
        raise RuntimeError(f'{name} failed; see {LOGS / (name + ".log")}')
    return text


def main():
    windows = ROOT / f'builds/BigSnowShift-{VERSION}-Windows.zip'
    verification = json.loads((ROOT / 'builds/release-preparation/windows-package.json').read_text())
    if verification['sha256'] != hashlib.sha256(windows.read_bytes()).hexdigest():
        raise RuntimeError('Build and verify Windows first.')
    LOGS.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT / 'tools/godot-version.json').read_text(encoding='utf-8-sig'))
    engine = ROOT / f'.tools/godot/{lock["version"]}/Godot_v{lock["release"]}_win64_console.exe'
    java_home = Path(os.getenv('JAVA_HOME', 'C:/Program Files/Eclipse Adoptium/jdk-17.0.17.10-hotspot'))
    java = java_home / 'bin/java.exe'
    sdk = Path(os.getenv('ANDROID_SDK_ROOT', 'C:/Android/SDK'))
    bundletool = ROOT / '.tools/bundletool/bundletool-all-1.18.3.jar'
    if not bundletool.exists():
        bundletool.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve('https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar', bundletool)
    if hashlib.sha256(bundletool.read_bytes()).hexdigest() != BUNDLETOOL_SHA256:
        raise RuntimeError('Unexpected bundletool archive.')
    android = ROOT / 'android/build'
    if not (android / 'build.gradle').exists():
        android.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(engine.parent / f'editor_data/export_templates/{lock["version"]}.stable/android_source.zip') as archive:
            archive.extractall(android)
        (android / '.gdignore').touch()
        (android.parent / '.build_version').write_text(lock['version'] + '.stable')
    signing = ROOT / '.tools/signing'
    signing.mkdir(parents=True, exist_ok=True)
    key = signing / 'big-snow-shift-upload.keystore'
    credentials = signing / 'production-upload-signing.json'
    env = os.environ.copy()
    env.update(JAVA_HOME=str(java_home), ANDROID_HOME=str(sdk), ANDROID_SDK_ROOT=str(sdk),
               GRADLE_USER_HOME=str(ROOT / '.tools/gradle'), GRADLE_OPTS='-Dorg.gradle.daemon=false')
    if os.name == 'nt':
        env['JAVA_TOOL_OPTIONS'] = env.get('JAVA_TOOL_OPTIONS', '') + ' -Djavax.net.ssl.trustStoreType=Windows-ROOT -Djavax.net.ssl.trustStore=NONE'
    if credentials.exists():
        credential = json.loads(credentials.read_text())
        if not key.exists():
            raise RuntimeError('Restore the matching upload keystore; do not replace it.')
    else:
        if key.exists():
            raise RuntimeError('Restore credentials for the existing upload keystore.')
        credential = {'alias': 'big-snow-shift-upload', 'password': secrets.token_hex(24)}
        credentials.write_text(json.dumps(credential, indent=2) + '\n')
        env['BIG_SNOW_SHIFT_UPLOAD_PASSWORD'] = credential['password']
        run('create-upload-key', [java_home / 'bin/keytool.exe', '-genkeypair', '-noprompt',
            '-keystore', key, '-alias', credential['alias'], '-keyalg', 'RSA', '-keysize', '3072',
            '-validity', '10000', '-dname', 'CN=Existical Games Upload, O=Existical Games',
            '-storepass:env', 'BIG_SNOW_SHIFT_UPLOAD_PASSWORD', '-keypass:env', 'BIG_SNOW_SHIFT_UPLOAD_PASSWORD'], env)
    env.update(GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(key),
               GODOT_ANDROID_KEYSTORE_RELEASE_USER=credential['alias'],
               GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=credential['password'])
    aab = OUT / f'BigSnowShift-{VERSION}-upload.aab'
    run('export-production', [engine, '--headless', '--path', ROOT, '--export-release', 'Android Production', aab], env, 1800)
    signature = run('bundle-signature', [java_home / 'bin/jarsigner.exe', '-verify', '-verbose', '-certs', aab])
    if 'jar verified.' not in signature or 'CN=Existical Games Upload' not in signature:
        raise RuntimeError('Unexpected bundle signature.')
    run('bundle-validation', [java, '-jar', bundletool, 'validate', '--bundle=' + str(aab)])
    manifest = run('bundle-manifest', [java, '-jar', bundletool, 'dump', 'manifest', '--bundle=' + str(aab), '--module=base'])
    for expected in [f'package="{PACKAGE}"', 'android:versionCode="63"', f'android:versionName="{VERSION}"', 'android:targetSdkVersion="36"']:
        if expected not in manifest:
            raise RuntimeError('Unexpected production metadata: ' + expected)
    if 'uses-permission' in manifest or 'android:debuggable="true"' in manifest:
        raise RuntimeError('Production must be offline and non-debuggable.')
    with zipfile.ZipFile(aab) as archive:
        names = archive.namelist()
        for name in names:
            if any(part in name for part in ['.keystore', '.jks', 'signing.json', 'SCLAUS', '/reference/', '/archive/', '/art-masters/', 'winter_house.png', '/.tools/']):
                raise RuntimeError('Forbidden content: ' + name)
        if not any('door_plain_v014.png-' in name and name.endswith('.ctex') for name in names):
            raise RuntimeError('Shared cottage/door texture is missing.')
        if any('icon_caretaker_tree_adaptive_v019.png' in name or 'icon_caretaker_tree_monochrome_v019.png' in name for name in names):
            raise RuntimeError('Export-only launcher sources were unexpectedly bundled as game textures.')
        for notice in ['PRIVACY_POLICY.txt', 'MUSIC_CREDITS.txt', 'SOUND_CREDITS.txt', 'CC0-1.0.txt', 'ASSET_LICENSES.txt']:
            paths = [n for n in names if n.endswith('/' + notice)]
            if len(paths) != 1 or archive.read(paths[0]) != (ROOT / 'assets/licenses' / notice).read_bytes():
                raise RuntimeError('Notice missing or stale: ' + notice)
        abis = sorted({n.split('/')[2] for n in names if n.startswith('base/lib/') and n.endswith('.so')})
    # Public upload certificate, not the private key, may be used in Console.
    env['BIG_SNOW_SHIFT_UPLOAD_PASSWORD'] = credential['password']
    run('upload-certificate', [java_home / 'bin/keytool.exe', '-exportcert', '-rfc', '-keystore', key,
        '-alias', credential['alias'], '-storepass:env', 'BIG_SNOW_SHIFT_UPLOAD_PASSWORD', '-file', OUT / 'upload-certificate.pem'], env)
    digest = hashlib.sha256(aab.read_bytes()).hexdigest()
    report = {'version': VERSION, 'version_code': int(re.search(r'android:versionCode="(\d+)"', manifest).group(1)), 'package': PACKAGE, 'application_id_status': 'confirmed by owner on 2026-11-17',
              'aab': aab.name, 'sha256': digest, 'bytes': aab.stat().st_size, 'target_api': 36,
              'permissions': [], 'debuggable': False, 'architectures': abis, 'signed_upload_candidate': True,
              'bundletool_validation': True, 'policy_and_notices_match': True,
              'play_app_signing_enrollment': 'pending in Play Console', 'store_upload': 'not performed'}
    (OUT / 'build-verification.json').write_text(json.dumps(report, indent=2) + '\n')
    (OUT / 'SHA256SUMS.txt').write_text(f'{digest}  {aab.name}\n')
    print('Upload candidate verified: ' + str(aab), flush=True)


if __name__ == '__main__':
    main()
