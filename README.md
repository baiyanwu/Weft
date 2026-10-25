# weft

<img src="Assets/logo.png" width="120" height="120" alt="weft logo">

一台 Mac 与多台 Android 设备共享鼠标。通过屏幕边缘、菜单栏或快捷键切换，设备可同时连接，同一时刻控制一台。

## 功能

- Mac ↔ Android 双向跨屏，拖动设备贴到 Mac 任一边并调整接壤位置。
- 每台设备独立设置鼠标速度、自动连接和自动跨屏。
- 支持鼠标移动、五个按键和滚轮。
- USB / Wi-Fi 连接，内置 ADB，无需 root 或安装 Android APK。

## 使用

从 [Releases](https://github.com/baiyanwu/Weft/releases) 下载最新的 `weft-<版本>-universal.dmg`：Developer ID 签名并已公证，包含 Apple Silicon 与 Intel 架构，可配合随附的 `.sha256` 文件校验。也可按下文从源码构建；CI 构建成功时，会在对应 Actions 运行的 **Artifacts → weft-macos-universal-UNNOTARIZED** 提供未公证测试包。

1. 将 DMG 中的 `weft.app` 拖入“应用程序”并打开，在 **系统设置 → 隐私与安全性 → 辅助功能** 中授权。
2. Android 开启 USB 调试并允许这台 Mac，在 **添加设备 → USB 连接** 中选中设备并点击 **添加并连接**。
3. 在 **设备与布局** 中拖动设备贴到 Mac 的任一边，开启该设备的自动跨屏。绿色接壤区间是鼠标出入口，向外移动即可切换；按住鼠标拖拽时不会自动跨屏。

无线连接：开启 Android 的无线调试（Android 11 及以上，且 Mac 与设备处于同一网络），在添加设备页填写连接地址、配对地址和配对码。配对地址与连接地址的端口通常不同；已配对设备只需连接地址。

ADB 默认优先使用本机已安装版本，未找到时使用内置版本。需要指定路径时，前往 **通用设置 → ADB 连接工具**。

| 操作 | 快捷键 |
| --- | --- |
| 切换 Mac / 上次设备 | `Control + Option + M` |
| 立即返回 Mac | 左侧 `Option` 或 `Esc` |

关闭设置窗口后，weft 继续在菜单栏运行。连接异常可在 **帮助与诊断** 中查看日志或导出报告。

## 兼容性

- macOS 13+；支持构建 Apple Silicon / Intel 通用包，Intel 实机尚未验证。
- 当前实测 Android 16 的 OnePlus OPD2413 和 Seeker；其他系统与厂商尚未充分验证。Wi-Fi 配对与连接入口已实现，但尚未在无线链路上实机验收。
- 仅共享鼠标，不共享键盘、音视频或剪贴板。Android 设备之间需经 Mac 切换。
- 使用非公开系统接口，系统升级可能影响兼容性。

## 从源码构建

需要 Xcode、JDK 17+、Android SDK Platform 36 和 Build Tools 36.0.0。

打开 `Weft.xcodeproj`，选择 Weft scheme 和 My Mac 运行目标，`Command + R` 构建运行，`Command + U` 运行测试。Android 控制程序会自动编译并嵌入应用。

SDK 默认路径为 `~/Library/Android/sdk`，可通过 `ANDROID_SDK_ROOT` 或 `ANDROID_HOME` 覆盖；JDK 可通过 `JAVA_HOME` 指定。

Debug 使用 ad-hoc 签名。本机签名配置放在 `local/Signing.xcconfig`，版本配置见 [Config/Weft.xcconfig](Config/Weft.xcconfig)。正式打包使用 [scripts/release.sh](scripts/release.sh)，需要 Developer ID 证书和 `NOTARY_PROFILE` 指定的公证凭据配置。

## 许可证

[MIT](LICENSE)。内置 ADB 的第三方声明与来源见 [ADB-NOTICE.txt](Assets/ADB-NOTICE.txt) 和 [ADB-SOURCE.txt](Assets/ADB-SOURCE.txt)。
