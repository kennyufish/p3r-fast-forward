# P3R Fast Forward

[简体中文](README.zh-CN.md)

A UE4SS Lua mod for Persona 3 Reload (Steam). Press **F6** to cycle the game speed through 1× → 1.5× → 2× → 5×. Dialogue and sound effects speed up too, and at 1.5× and 2× their pitch is corrected back to normal.

Tested only on Steam build 22672075 with UE4SS 3.0.1 (d935b5b). A game update may break it.

## Install

1. Install [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) into `P3R\Binaries\Win64\`.
2. In `Win64\UE4SS-settings.ini`, set `MajorVersion = 4` and `MinorVersion = 27` under `[EngineVersionOverride]`.
3. Copy `Mods\P3R_FastForward\` into `Win64\Mods\`, then add `P3R_FastForward : 1` to `Win64\Mods\mods.txt`.
4. Exit the game, then add this to the end of `%LOCALAPPDATA%\P3R\Saved\Config\WindowsNoEditor\Engine.ini`:
   ```ini
   [/Script/CriWareRuntime.CriWarePluginSettings]
   AtomConfig=None
   AcfFileName=..\..\..\..\Binaries\Win64\Mods\P3R_FastForward\xrd777_ff.acf
   StandardMemoryVoiceSamplingRate=96000
   StandardStreamingVoiceSamplingRate=96000
   ```
   The two `SamplingRate` lines let the sound reach 2×. The `AtomConfig` and `AcfFileName` lines load the mod's audio config, which adds the pitch-correction buses. Edit `Engine.ini` only while the game is closed; the game overwrites it on exit.

When the mod loads, `UE4SS.log` shows `[P3RFF] Loaded v0.6.5`.

## Use

A small settings window (Chinese labels) opens with the game. Press **F8** to reopen it.

- Speed: 1.0× / 1.5× / 2.0× / 5.0×. F6 cycles the same list. The game always starts at 1.0×.
- Speed up game: game time. Off keeps the game at 1× (only the sound speeds up).
- Speed up sound: dialogue and sound effects.
- Fix pitch: on by default. Works at 1.5× and 2× only.

The toggles are saved in `Mods\P3R_FastForward\settings.txt`.

## Notes

- At 5×, the game runs at 5× but CRI caps the sound at about 2×. 5× is not pitch-corrected.
- Pitch-corrected sound loses some high frequencies, so it sounds a little muffled.
- BGM and cutscene video sound are not sped up.
- If another mod already uses F6, this mod does not load.

## Uninstall

1. Press F6 until you are back at 1×, then exit the game.
2. Remove `P3R_FastForward : 1` from `mods.txt`.
3. Remove the `AtomConfig` and `AcfFileName` lines from `Engine.ini`. If they stay after you delete the mod folder, the game cannot find its audio config.

## Tests

The tests run `main.lua` against a mocked UE4SS API. They are not a substitute for testing in the game.

```bash
pip install lupa
python tests/test_gameplay.py
python tests/test_pitch.py
```

## License

MIT. This project is not affiliated with SEGA or ATLUS. It contains no audio or other game assets, except `xrd777_ff.acf`: a patched copy of the game's CRI audio config, which adds two PitchShifter buses.
