# Big Snow Shift

*with Uncle Bolyus*

Clear the snowy steps, dodge the icicles and reach the cottage door to meet Santa. Each of the four difficulties has three rounds. In a Custom game you can choose one to three rounds and set your rules before play. The game runs offline on Windows and Android.

Created by Andrjus Valkuns for daughter Karolina Valkunaite. [Existical Games](https://www.existical.com/)

## Play

For a packaged Windows build, extract the entire player ZIP and open **BigSnowShift.exe** with its PCK beside it. The Android beta comes as an APK. See the [player guide](docs/PLAYER_README.md) for controls, saves and scoring.

## Run from source

Clone the repository using the URL under GitHub’s **Code** button, or extract the source ZIP. Run the following commands from the directory containing `project.godot`. Windows automation uses PowerShell and Python 3.11 or newer. All game assets, translations and notices are included.

```powershell
python tools/setup_godot.py
python -X utf8 tools/check_localization.py
& '.\Open Godot.cmd'
```

The setup script verifies the official downloads and installs Godot 4.7.2 and its export templates under `.tools/`. Press **F5** in the editor to play. After the first import you can also launch **Play Big Snow Shift.cmd**. On another desktop OS, open `project.godot` in the matching standard editor. [Godot 4.7.2 downloads](https://godotengine.org/download/archive/4.7.2-stable/)

## Build and test on Windows

```powershell
.\tools\build.ps1 -WindowsOnly
```

Run this on a graphical Windows desktop. It imports the project, runs gameplay, audio, localization, touch and rendering tests, starts the exported game and verifies every file in the playable ZIP. The ZIP is under `builds/`. Diagnostics are under `builds/logs/`.

## Export an Android debug APK

1. Complete the Windows build above. Install JDK 17 and the Android SDK with platform-tools, Android 36 and Build-Tools 36.0.0, the version used by the pinned editor for the debug APK.
2. Open the project with **Open Godot.cmd**. Under **Editor → Editor Settings → Export → Android**, set **Java SDK Path** and **Android SDK Path** to your local installations. Godot uses a local debug keystore for testing.
3. Close the editor and export an ARM64 tablet APK.

```powershell
.\tools\godot.ps1 --headless --path . --export-debug Android builds/android/BigSnowShift-debug.apk
```

The **Android Emulator** preset targets x86-64. Substitute that preset name in quotes for an emulator build. Both debug presets use `com.existical.bigsnowshift.debug`. [Godot Android export guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)

The signed beta and Google Play scripts under `tools/build_android_*.py` are publisher tools. They use Existical Games’ application IDs, local signing files and release verification. Forks distributing their own game should set their own application ID and signing configuration in Godot.

## Source releases and contributions

Edit gameplay in `scripts/`, difficulty presets in `resources/difficulty/` and translations in `localization/translations/`. Preserve save compatibility and run the Windows checks before submitting gameplay changes. [Localization guide](docs/localization.md)

`tools/source-files.txt` lists the reviewed files included in source distributions. Add new public files to Git and to this inventory. To build the source ZIP with a SHA-256 manifest, run `python tools/package_source.py`. Tool downloads, signing material and private artwork masters stay outside the repository.

## Credits and licences

Original code and documentation use the [MIT licence](LICENSE). Original artwork and sound effects are offered under CC BY 4.0 to the extent of the rights held by Existical Games. The asset licence map documents the separate terms for Kevin MacLeod’s music, the Freesound recordings and the bundled fonts. The illustrations and initial translations were created with AI assistance. [Asset licences](ASSET_LICENSES.md) · [Asset sources](docs/asset-sources.md)

Support is available at **existicalgames[at]gmail[dot]com**. [Privacy policy source](docs/privacy/big-snow-shift/index.html)
