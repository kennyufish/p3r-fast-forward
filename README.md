# P3R Fast Forward

[简体中文](README.zh-CN.md)

A UE4SS Lua mod for Persona 3 Reload (Steam). Press **F6** to cycle the game speed through 1× → 1.5× → 2× → 5×. Dialogue and sound effects speed up too, so their pitch goes up.

Tested only on Steam build 22672075 with UE4SS 3.0.1 (d935b5b). A game update may break it.

## Install

1. Install [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) into `P3R\Binaries\Win64\`.
2. In `Win64\UE4SS-settings.ini`, set `MajorVersion = 4` and `MinorVersion = 27` under `[EngineVersionOverride]`.
3. Copy `Mods\P3R_FastForward\` into `Win64\Mods\`, then add `P3R_FastForward : 1` to `Win64\Mods\mods.txt`.
4. For the sound to speed up at 2×, add this to the end of `%LOCALAPPDATA%\P3R\Saved\Config\WindowsNoEditor\Engine.ini`:
   ```ini
   [/Script/CriWareRuntime.CriWarePluginSettings]
   StandardMemoryVoiceSamplingRate=96000
   StandardStreamingVoiceSamplingRate=96000
   ```

When the mod loads, `UE4SS.log` shows `[P3RFF] Loaded v0.4.6`.

## Notes

- At 5×, the game runs at 5× but CRI caps the sound at about 2×.
- Cutscene video sound is not sped up.
- If another mod already uses F6, this mod does not load.
- To uninstall, press F6 until you are back at 1×, then exit the game and remove the line from `mods.txt`.

## Optional: pitch correction

Pitch correction uses [Equalizer APO](https://sourceforge.net/projects/equalizerapo/) with the [Pitchproof](https://aegeanmusic.com/) plugin. It is off by default. APO changes every sound on the output device, not only the game.

1. Install APO on your output device.
2. Put `pitchproof-x64.dll` in `EqualizerAPO\VSTPlugins\`.
3. Make `EqualizerAPO\config\config.txt` contain only `Include: p3r_pitch.txt`.
4. In `main.lua`, set `APO_ENABLED = true`.

## License

MIT. This project is not affiliated with SEGA or ATLUS and contains no game assets.
