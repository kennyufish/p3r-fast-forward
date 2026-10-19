# P3R Fast Forward | P3R 快进

[English](README.md)

Persona 3 Reload（Steam 版）的 UE4SS Lua mod。按 **F6** 让游戏速度在 1×、1.5×、2×、5× 之间循环切换。对白和音效会一起加速；1.5× 和 2× 时，音调会修正回原来的高度。

只在 Steam build 22672075 和 UE4SS 3.0.1（d935b5b）上测试过，游戏更新后可能失效。

## 安装

1. 把 [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) 装到 `P3R\Binaries\Win64\`。
2. 打开 `Win64\UE4SS-settings.ini`，在 `[EngineVersionOverride]` 下设置 `MajorVersion = 4`、`MinorVersion = 27`。
3. 把 `Mods\P3R_FastForward\` 复制到 `Win64\Mods\`，再在 `Win64\Mods\mods.txt` 里加一行 `P3R_FastForward : 1`。
4. 退出游戏，在 `%LOCALAPPDATA%\P3R\Saved\Config\WindowsNoEditor\Engine.ini` 末尾加上：
   ```ini
   [/Script/CriWareRuntime.CriWarePluginSettings]
   AtomConfig=None
   AcfFileName=..\..\..\..\Binaries\Win64\Mods\P3R_FastForward\xrd777_ff.acf
   StandardMemoryVoiceSamplingRate=96000
   StandardStreamingVoiceSamplingRate=96000
   ```
   两行 `SamplingRate` 让声音能加速到 2×。`AtomConfig` 和 `AcfFileName` 两行加载 mod 自带的音频配置，里面多了声调修正用的总线。只能在游戏关闭时改 `Engine.ini`，游戏退出时会覆盖这个文件。

加载成功后，`UE4SS.log` 里会出现 `[P3RFF] Loaded v0.6.5`。

## 使用

游戏启动时会打开一个小设置窗口，按 **F8** 可以重新打开。

- 倍速：1.0× / 1.5× / 2.0× / 5.0×，和 F6 循环的是同一组。每次启动都从 1.0× 开始。
- 加速游戏：游戏时间。关掉后游戏保持 1×，只加速声音。
- 加速声音：对白和音效。
- 修正声调：默认开启，只在 1.5× 和 2× 时生效。

开关设置保存在 `Mods\P3R_FastForward\settings.txt`。

## 注意

- 5× 时，游戏是 5×，但声音被 CRI 限制在约 2×。5× 不做声调修正。
- 修正后的声音会损失一部分高频，听起来有点闷。
- BGM 和过场视频的声音不会加速。
- 如果 F6 已经被别的 mod 占用，本 mod 不会加载。

## 卸载

1. 按 F6 切回 1×，然后退出游戏。
2. 从 `mods.txt` 删掉 `P3R_FastForward : 1`。
3. 从 `Engine.ini` 删掉 `AtomConfig` 和 `AcfFileName` 两行。如果删了 mod 文件夹却留着这两行，游戏会找不到音频配置。

## 测试

测试用模拟的 UE4SS API 运行 `main.lua`，不能代替游戏内实测。

```bash
pip install lupa
python tests/test_gameplay.py
python tests/test_pitch.py
```

## 许可

MIT。本项目与 SEGA、ATLUS 无关。除 `xrd777_ff.acf` 外不含任何音频或游戏资产；这个文件是游戏 CRI 音频配置的补丁版，加了两条 PitchShifter 总线。
