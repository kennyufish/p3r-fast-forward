# p3r-fast-forward | P3R 快进

Persona 3 Reload (Steam) 的 UE4SS Lua mod：按 **F6** 在 1× → 1.5× → 2× → 5× → 1× 之间切换游戏速度，对白和音效通过 CRI `AtomComponent:SetPitchMultiplier` 一起加速。

UE4SS Lua mod for Persona 3 Reload (Steam). **F6** cycles game speed 1× → 1.5× → 2× → 5× → 1×; dialogue and SFX speed up with it via CRI `AtomComponent:SetPitchMultiplier`. English summary at the bottom.

> 音频加速是重采样，**音调会跟着升高**（1.5× 约 +7 半音，2× 约 +12 半音）。降调补偿是可选项，见下文"可选：APO 降调"。

## 测试环境

只在下面这个环境里实机测试过，其他版本可能能用，但没有验证：

| 项 | 值 |
|---|---|
| 游戏 | P3R Steam 版（app 2161700），build 22672075 |
| `P3R.exe` SHA256 | `88244bade1988eafd8ababd66d4c2227091c4c6c253e6455c7097b1b1e5299b8` |
| UE4SS | v3.0.1 Beta #0（Git SHA d935b5b），Lua 5.4 |

游戏更新后可能失效。

## 安装

1. 装好 [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases)（本包不含 UE4SS），装到 `...\steamapps\common\P3R\P3R\Binaries\Win64\`。
2. 在 `Win64\UE4SS-settings.ini` 的 `[EngineVersionOverride]` 里设置：
   ```ini
   MajorVersion = 4
   MinorVersion = 27
   ```
   不设的话 UE4SS 可能识别不出引擎版本，扫描超时，mod 不加载。
3. 把本包的 `Mods\P3R_FastForward\` 文件夹复制到 `Win64\Mods\` 下。
4. 在 `Win64\Mods\mods.txt` 里加一行：
   ```
   P3R_FastForward : 1
   ```
5. **要让 2× 的声音真正加速**，在 `%LOCALAPPDATA%\P3R\Saved\Config\WindowsNoEditor\Engine.ini` 末尾加：
   ```ini
   [/Script/CriWareRuntime.CriWarePluginSettings]
   StandardMemoryVoiceSamplingRate=96000
   StandardStreamingVoiceSamplingRate=96000
   ```
   默认是 48000，对 48 kHz 音源来说 CRI 会把升频钳在 1×，声音不会变快。改之前先备份这个文件。
6. 启动游戏。`Win64\UE4SS.log` 里应该出现 `[P3RFF] Loaded v0.4.6`。

## 使用

- 进入游戏后按 **F6** 切换倍速。每次生效后日志会写一行 `[P3RFF] ===== SPEED NOW 1.5x =====`。
- 游戏自己的慢动作（过场等）不会被覆盖：被动轮询遇到非本 mod 设置的倍率时会让出控制。
- 加载、切换场景后会自动恢复当前倍速（每 500 ms 轮询一次）。

## 已知限制

- **音调升高**：没有做保持音调的变速。
- **5× 档的声音**：CRI 有 `MaxPitch=2400` 音分（约 4×）和 96 kHz 采样率上限，5× 档的声音大概率只有约 2×，画面和对白会对不上。画面 5× 已实测正常。
- **过场视频**（USM/CriMana）的声音不经过 `AtomComponent`，不会加速。
- **F6 冲突**：其他 mod 已占用 F6 时，本 mod 不加载，日志写 `INIT FAILED: F6 is already registered`。
- **不支持热重载**：改了 `main.lua` 要重启游戏。
- 不要打开 UE4SS 的 GUI 控制台（`GuiConsoleVisible = 1`），在本环境下会导致游戏启动时崩溃。

## 停用和卸载

1. 先按 F6 切回 1×，退出游戏。
2. 把 `mods.txt` 里的 `P3R_FastForward : 1` 改成 `: 0`，或者删掉 `Mods\P3R_FastForward\` 文件夹。
3. 想还原声音设置，就删掉 `Engine.ini` 里加的那一节。

## 可选：APO 降调

用系统级的 [Equalizer APO](https://sourceforge.net/projects/equalizerapo/) 加 [Pitchproof](https://aegeanmusic.com/) VST2 插件，在 F6 时同步降调：1.5× 降 7 半音，2× 降 12 半音，5× 不处理。**默认关闭。**

注意：APO 作用于整个输出设备，开着降调时浏览器、Discord 等其他声音也会被降调。

启用方法：

1. 安装 Equalizer APO，在 Device Selector 里勾选你的输出设备，按提示重启。
2. 把 `pitchproof-x64.dll` 放到 `C:\Program Files\EqualizerAPO\VSTPlugins\`。
3. 把 `C:\Program Files\EqualizerAPO\config\config.txt` 的内容改成只有一行（先备份原文件）：
   ```
   Include: p3r_pitch.txt
   ```
4. 把 `main.lua` 里的 `local APO_ENABLED = false` 改成 `true`，然后重启游戏。

mod 会在 F6 时改写 `C:\Program Files\EqualizerAPO\config\p3r_pitch.txt`，APO 检测到文件变化后自动重新加载。启动时会先写入 1×，清掉上次留下的降调。如果游戏崩溃时还在加速档，降调会一直开着，直到下次启动游戏；这时可以手动把 `p3r_pitch.txt` 改成只有一行 `#`。

## 测试

`tests/test_gameplay.py` 用 [lupa](https://pypi.org/project/lupa/) 在 Lua 5.4 里加载真实的 `main.lua`，配合 UE4SS 接口的 mock 运行。它只验证逻辑，不能代替游戏内测试。

```
pip install lupa
python tests/test_gameplay.py
```

## English summary

- **Requires** UE4SS 3.0.1 (d935b5b); set `[EngineVersionOverride] MajorVersion = 4`, `MinorVersion = 27` in `UE4SS-settings.ini`.
- **Install:** copy `Mods/P3R_FastForward/` into `P3R/Binaries/Win64/Mods/` and add `P3R_FastForward : 1` to `mods.txt`.
- **For 2× audio,** add the `CriWarePluginSettings` section above (both sampling rates set to 96000) to `%LOCALAPPDATA%\P3R\Saved\Config\WindowsNoEditor\Engine.ini`.
- **Pitch** rises with speed. Optional Equalizer APO + Pitchproof compensation is off by default (`APO_ENABLED` in `main.lua`).
- **5×:** CRI likely caps audio at about 2×. Cutscene video audio is not sped up.
- **Tested only** on the build and hashes listed above.

## License

MIT. Persona 3 Reload 是 SEGA / ATLUS 的商标。本项目与它们无关，不含任何游戏资产。
