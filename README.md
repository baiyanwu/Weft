# weft

[中文](#中文) | [English](#english)

![weft logo](Assets/logo.png)

## 中文

一台 Mac 与多台 Android 设备共享鼠标。通过屏幕边缘、菜单栏或快捷键切换，设备可同时连接，同一时刻控制一台。

### 功能

- Mac ↔ Android 双向跨屏，拖动排列设备位置。
- 每台设备独立设置鼠标速度、自动连接和自动跨屏。
- 支持鼠标移动、五个按键和滚轮。
- USB / Wi-Fi 连接，内置 ADB，无需 root 或安装 Android APK。

### 使用

可从 GitHub Actions 的 **Artifacts → weft-macos-universal-UNNOTARIZED** 下载测试包，或按下文从源码构建。Actions 测试包未经过 Apple 公证。

1. 打开 `weft.app`，在 **系统设置 → 隐私与安全性 → 辅助功能** 中授权。
2. Android 开启 USB 调试并允许这台 Mac，在 **添加设备 → USB 连接** 中添加设备。
3. 在 **设备与布局** 中拖动排列设备，开启该设备的自动跨屏。绿色接壤区间是鼠标出入口，向外移动即可切换；按住鼠标拖拽时不会自动跨屏。

无线连接：开启 Android 的无线调试，在添加设备页填写连接地址、配对地址和配对码。配对地址与连接地址的端口通常不同；已配对设备只需连接地址。

ADB 默认优先使用本机已安装版本，未找到时使用内置版本。需要指定路径时，前往 **通用设置 → ADB 连接工具**。

| 操作 | 快捷键 |
| --- | --- |
| 切换 Mac / 上次设备 | `Control + Option + M` |
| 立即返回 Mac | 左侧 `Option` 或 `Esc` |

关闭设置窗口后，weft 继续在菜单栏运行。连接异常可在 **帮助与诊断** 中查看日志或导出报告。

### 兼容性

- macOS 13+，支持构建 Apple Silicon / Intel 通用包；Intel 实机尚未验证。
- 当前实测 Android 16 的 OnePlus OPD2413 和 Seeker；其他系统与厂商、无线稳定性尚未充分验证。
- 仅共享鼠标，不共享键盘、音视频或剪贴板。Android 设备之间需经 Mac 切换。
- 使用非公开系统接口，系统升级可能影响兼容性。

### 从源码构建

需要 Xcode、JDK 17+、Android SDK Platform 36 和 Build Tools 36.0.0。

打开 `Weft.xcodeproj`，选择 **Weft → My Mac**，`Command + R` 构建运行，`Command + U` 运行测试。Android 控制程序会自动编译并嵌入应用。

SDK 默认路径为 `~/Library/Android/sdk`，可通过 `ANDROID_SDK_ROOT` 或 `ANDROID_HOME` 覆盖；JDK 可通过 `JAVA_HOME` 指定。

Debug 使用 ad-hoc 签名。本机签名配置放在 `local/Signing.xcconfig`，版本配置见 [Config/Weft.xcconfig](Config/Weft.xcconfig)。正式打包使用 [scripts/release.sh](scripts/release.sh)，需要 Developer ID 证书和 `NOTARY_PROFILE` 指定的公证凭据配置。

### 许可证

[MIT](LICENSE)。内置 ADB 的第三方声明与来源见 [ADB-NOTICE.txt](Assets/ADB-NOTICE.txt) 和 [ADB-SOURCE.txt](Assets/ADB-SOURCE.txt)。

## English

Share one mouse between your Mac and multiple Android devices. Switch at screen edges, from the menu bar, or with a shortcut. Multiple devices can stay connected; one is controlled at a time.

### Features

- Switch in both directions between Mac and Android; drag devices to arrange their positions.
- Set pointer speed, automatic connection, and edge switching for each device.
- Supports pointer movement, five mouse buttons, and scrolling.
- USB / Wi-Fi connections with bundled ADB. No root or Android APK required.

### Usage

Download a test build from GitHub Actions under **Artifacts → weft-macos-universal-UNNOTARIZED**, or build from source below. Actions builds are not notarized by Apple.

1. Open `weft.app` and grant access in **System Settings → Privacy & Security → Accessibility**.
2. Enable USB debugging on Android, authorize your Mac, and add the device under **添加设备 → USB 连接** (Add Device → USB Connection).
3. Arrange devices under **设备与布局** (Devices & Layout) and enable edge switching for the device. Move the pointer outward through a green shared edge to switch. Automatic switching does not trigger while dragging.

For Wi-Fi, enable Android's wireless debugging and enter the connection address, pairing address, and pairing code on the Add Device page. The pairing and connection ports usually differ; paired devices only need the connection address.

weft prefers an existing local ADB installation and falls back to the bundled version. To choose a custom path, open **通用设置 → ADB 连接工具** (General Settings → ADB).

| Action | Shortcut |
| --- | --- |
| Switch between Mac and the last device | `Control + Option + M` |
| Return to Mac immediately | Left `Option` or `Esc` |

weft stays in the menu bar after its settings window is closed. View logs or export a report under **帮助与诊断** (Help & Diagnostics) if a connection fails.

### Compatibility

- macOS 13+. Universal Apple Silicon / Intel builds are supported; Intel hardware has not been tested.
- Tested on OnePlus OPD2413 and Seeker running Android 16. Other Android versions, vendors, and wireless reliability have not been fully tested.
- Mouse sharing only; keyboard, audio, video, and clipboard sharing are not supported. Switching between Android devices goes through the Mac.
- Uses private system APIs; OS updates may affect compatibility.

### Build from source

Requires Xcode, JDK 17+, Android SDK Platform 36, and Build Tools 36.0.0.

Open `Weft.xcodeproj`, select the **Weft** scheme and **My Mac**, then press `Command + R` to build and run or `Command + U` to run tests. The Android agent is built and embedded automatically.

The SDK defaults to `~/Library/Android/sdk`; override it with `ANDROID_SDK_ROOT` or `ANDROID_HOME`. Set `JAVA_HOME` to choose a JDK.

Debug builds use ad-hoc signing. Put local signing settings in `local/Signing.xcconfig`; version settings are in [Config/Weft.xcconfig](Config/Weft.xcconfig). For release packaging, use [scripts/release.sh](scripts/release.sh) with a Developer ID certificate and a notarization credentials profile specified by `NOTARY_PROFILE`.

### License

[MIT](LICENSE). Bundled ADB notices and provenance are in [ADB-NOTICE.txt](Assets/ADB-NOTICE.txt) and [ADB-SOURCE.txt](Assets/ADB-SOURCE.txt).
