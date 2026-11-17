"""Verify every player ZIP entry against the checked Windows export."""
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    version = re.search(r'config/version="([^"]+)"', (ROOT/'project.godot').read_text()).group(1)
    package = ROOT / f'builds/BigSnowShift-{version}-Windows.zip'
    expected = {'BigSnowShift.exe', 'BigSnowShift.pck', 'README.md', 'LICENSE',
                'ASSET_LICENSES.md', 'PRIVACY_POLICY.txt', 'MUSIC_CREDITS.txt',
                'SOUND_CREDITS.txt', 'CC0-1.0.txt',
                'CC-BY-4.0.txt', 'THIRD_PARTY_NOTICES.txt', 'Nunito-LICENSE.txt',
                'MPLUSRounded1c-LICENSE.txt'}
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None
        assert set(archive.namelist()) == expected
        for name in archive.namelist():
            assert archive.read(name) == (ROOT/'builds/windows'/name).read_bytes(), name
    report = {'version':version, 'sha256':hashlib.sha256(package.read_bytes()).hexdigest(),
              'entries':len(expected), 'zip_integrity':True, 'matches_verified_export':True}
    output = ROOT/'builds/release-preparation'
    output.mkdir(exist_ok=True)
    (output/'windows-package.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Windows ZIP integrity and all packaged files verified.')


if __name__ == '__main__':
    main()
