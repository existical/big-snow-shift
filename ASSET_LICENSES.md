# Asset licences

The root MIT licence covers original project code and documentation. The
following asset terms are separate and remain applicable when redistributing
the game or its source.

## Original artwork and sounds

Original project artwork in `assets/art/` and original sound effects in
`assets/audio/` (excluding `assets/audio/music/`, `click.ogg`, `win.ogg` and `lose.ogg`) are offered under
**Creative Commons Attribution 4.0 International (CC BY 4.0)** by
Andrjus Valkuns / Existical Games. The complete terms are in
`assets/licenses/CC-BY-4.0.txt` and at
https://creativecommons.org/licenses/by/4.0/.

Suggested attribution: “Big Snow Shift artwork and sound effects —
Andrjus Valkuns / Existical Games, https://www.existical.com/,
CC BY 4.0.” Retain the licence reference and identify your modifications.

Much of the illustrated artwork was produced using OpenAI image generation.
This grant applies to rights held by the licensor, where such rights exist;
it does not assert exclusive copyright in unprotectable generated material
or grant rights to third-party intellectual property. The licence does not
imply endorsement of adaptations by Existical Games.

Hit, shovel and chime effects are original synthesis from `tools/create_audio.py`
and use no external samples. The click/win/lose recordings are third-party assets
under their individual terms below. Current hashes and provenance are in
`docs/sound-effects.json` and `docs/asset-sources.md`. The historical synthesis
tool `tools/create_release_effects.py` only generates comparison files in builds/.

## Third-party components

- **Music:** Kevin MacLeod's six recordings retain CC BY 4.0. Keep their
  individual attributions and source identifiers in
  `assets/licenses/MUSIC_CREDITS.txt`. Existical Games does not own these
  recordings.
- **Fonts:** the bundled M PLUS Rounded 1c, Nunito and Noto families retain
  their individual SIL Open Font Licences and copyright notices in
  `assets/fonts/*-LICENSE.txt`. Artwork licensing does not replace these.
- **Godot Engine:** MIT licence and its component notices remain applicable.
  `assets/licenses/THIRD_PARTY_NOTICES.txt` and the in-game Licences screen
  contain the notices. Engine binaries and Android build dependencies are
  not included in the public source archive.
- **God Jul! reference material:** original DOS binaries, artwork, decoded
  research material and audio are not licensed by this project and are
  excluded from the public source archive and game packages.
- **Menu click:** "Click" by complex_waveform,
  https://freesound.org/people/complex_waveform/sounds/213148/ — CC BY 4.0.
  The public OGG preview is included unchanged as `click.ogg`; playback volume
  follows the sound-effects setting. Retain the creator, source, licence and
  format/playback note in `assets/licenses/SOUND_CREDITS.txt`.
  Existical Games does not own this recording.
- **Win sound:** "Success Fanfare Trumpets.mp3" by FunWithSound,
  https://freesound.org/people/FunWithSound/sounds/456966/ — CC0 1.0 Universal.
- **Lose sound:** "horn_fail_wahwah_1.wav" by TaranP,
  https://freesound.org/people/TaranP/sounds/362206/ — CC0 1.0 Universal.
  These two recordings retain their CC0 dedication and are excluded from the
  project's CC BY 4.0 grant. Credits and full terms are included in
  `assets/licenses/SOUND_CREDITS.txt` and `assets/licenses/CC0-1.0.txt`.
  https://creativecommons.org/publicdomain/zero/1.0/
- **Original unidentified Freesound click:** archived and excluded. The
  current menu click is the credited complex_waveform recording above.

See `docs/asset-sources.md` for provenance. No licence here replaces a
third-party notice or grants rights beyond those held by the stated licensor.
