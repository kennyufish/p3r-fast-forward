# P3R Fast Forward | P3R 快进

[English](README.md)

Persona 3 Reload（Steam 版）的 UE4SS Lua mod。按 **F6** 让游戏速度在 1×、1.5×、2×、5× 之间循环切换。对白和音效会一起加速，所以音调会变高。

只在 Steam build 22672075 和 UE4SS 3.0.1（d935b5b）上测试过，游戏更新后可能失效。

## 安装

1. 把 [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) 装到 `P3R\Binaries\Win64\`。
2. 打开 `Win64\UE4SS-settings.ini`，在 `[EngineVersionOverride]` 下设置 `MajorVersion = 4`、`MinorVersion = 27`。
3. 把 `Mods\P3R_FastForward\` 复制到 `Win64\Mods\`，再在 `Win64\Mods\mods.txt` 里加一行 `P3R_FastForward : 1`。
4. 要让 2× 时声音也加速，在 `%LOCALAPPDATA%\P3R\Saved\Config\WindowsNoEditor\Engine.ini` 末尾加上：
   ```ini
   [/Script/CriWareRuntime.CriWarePluginSettings]
   StandardMemoryVoiceSamplingRate=96000
   StandardStreamingVoiceSamplingRate=96000
   ```

加载成功后，`UE4SS.log` 里会出现 `[P3RFF] Loaded v0.4.6`。

## 注意

- 5× 时，游戏是 5×，但声音被 CRI 限制在约 2×。
- 过场视频的声音不会加速。
- 如果 F6 已经被别的 mod 占用，本 mod 不会加载。
- 卸载：先按 F6 切回 1×，退出游戏，再从 `mods.txt` 删掉那一行。

## 可选：降调补偿

降调补偿需要 [Equalizer APO](https://sourceforge.net/projects/equalizerapo/) 和 [Pitchproof](https://aegeanmusic.com/) 插件，默认关闭。APO 会影响整个输出设备的声音，不只是游戏。

1. 在输出设备上安装 APO。
2. 把 `pitchproof-x64.dll` 放进 `EqualizerAPO\VSTPlugins\`。
3. 把 `EqualizerAPO\config\config.txt` 改成只有一行 `Include: p3r_pitch.txt`。
4. 在 `main.lua` 里设置 `APO_ENABLED = true`。

## 许可

MIT。本项目与 SEGA、ATLUS 无关，不含任何游戏资产。
