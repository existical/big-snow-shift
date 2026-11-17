# Localization

The game ships 56 locale variants. English is the source catalogue. Other languages use AI-assisted drafts and welcome native-speaker corrections. The language list records the native names and review status. [Language list](../localization/languages.json) · [English catalogue](../localization/translations/en.json)

Edit the matching keys in `localization/translations/`. Preserve named placeholders such as `{{score}}` and the credited proper names and titles. Keep short buttons and HUD labels readable in landscape. The game uses script-specific font fallbacks and right-to-left shaping. Full legal notices retain their original text. [Protected credit terms](../localization/protected-terms.json) · [Font sources](../localization/font-sources.json)

Run the offline checks from the project root in PowerShell.

```powershell
python -X utf8 tools/check_localization.py
python -X utf8 tools/test_localization_tools.py
```

The full Windows build also tests catalogue loading, interpolation, fallback, font coverage, persistent language choice and UI layout. For visual review, select the language in Settings or launch with a temporary language override after importing the project.

```powershell
.\tools\godot.ps1 --path . -- --language=lv-LV
```

The optional `tools/prepare_localization.py` translates drafts using an external service. Its `--keys` option selects messages to regenerate. The `--overwrite` option replaces existing drafts. Normal builds read the bundled catalogues offline.
