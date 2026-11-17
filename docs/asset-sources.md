# Asset sources

## Artwork

Andrjus Valkuns / Existical Games created the illustrated assets with OpenAI image generation. The artwork register identifies each shipped painting or atlas, its source references, any processing and the SHA-256 of the distributed PNG. The caretaker and Santa animations used poses from *God Jul!* as visual references. Original DOS files and decoded images remain in the private research archive. The asset grant covers rights held by the licensor. [Artwork register](artwork.json) · [Asset licences](../ASSET_LICENSES.md)

The cottage painting supplies both the background and the animated arched door leaves. Wreaths use a separate sprite. Santa and the caretaker share a sprite for the handshake and gift exchange. Snow, shovel geometry, particles, door movement and the clock hands are drawn in code. The menu and HUD icons are SVGs. Original private masters are optional for working on the game. The image-sizing record preserves the five downscaled assets’ master hashes, sizes and runtime hashes. [Image sizing record](image-optimization-v0.30.3.json)

## Sound and music

The menu click is “Click” by complex_waveform under CC BY 4.0. The public OGG preview is distributed with its original audio bytes. The win cue is credited to FunWithSound and the loss cue to TaranP, both under CC0. The project owner identified both sources. The decoded loss audio closely matches its source preview. The shorter archived win cue could not be independently matched to the preview, and its edit history is unknown. The game distributes the restored recordings with their recorded hashes. [Sound credits](../assets/licenses/SOUND_CREDITS.txt) · [Sound file hashes and sources](sound-effects.json) · [Restoration evidence](recovered-freesound-effects.json)

The shovel, hit and chime are original synthesized recordings by Andrjus Valkuns / Existical Games. The synthesis script generates these three WAV files. [Audio generator](../tools/create_audio.py)

Six unedited Kevin MacLeod recordings are used under CC BY 4.0. “Jingle Bells” plays in the menu. Five recordings play during the game. “Comparsa” and “No Frills Comparsa” identify the same recording. The game adjusts playback volume. The soundtrack manifest records source pages, ISRCs and file hashes. [Music credits](../assets/licenses/MUSIC_CREDITS.txt) · [Soundtrack manifest](soundtrack-v0.19.json)

## Fonts and engine

M PLUS Rounded 1c, Nunito and the Noto Sans families retain their original SIL Open Font License notices under `assets/fonts/`. The font manifest records upstream sources and hashes for the M PLUS and Noto families. Nunito’s notice is included separately. [Font manifest](../localization/font-sources.json) · [Nunito licence](../assets/fonts/Nunito-LICENSE.txt)

The in-game Licences screen includes Godot’s MIT licence and its component notices. The Windows player ZIP also carries the component notices. [Engine notices](../assets/licenses/THIRD_PARTY_NOTICES.txt)
