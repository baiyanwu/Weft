# 打包与发布

macOS 应用使用 `Weft.xcodeproj` 的 Weft scheme。版本与构建号在 `Config/Weft.xcconfig` 中维护。应用信息使用 `Config/Info.plist`，发行导出配置使用 `Config/ExportOptions.plist`。签名、公证参考 Whirl：私钥和公证凭据留在本机，GitHub 自动生成测试包。

## Xcode 本地构建与归档

打开 `Weft.xcodeproj`，选择 Weft 和 My Mac。使用 `Command + B` 构建，`Product → Archive` 创建 Release 归档，随后在 Organizer 中选择 Developer ID 分发。Xcode 自动编译 Swift、处理资源和图标，并调用 Android 编译步骤。

Debug 默认 ad-hoc 签名；Release 使用 Developer ID Application。个人配置写入被忽略的 `Config/Signing.local.xcconfig`：

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
CODE_SIGN_IDENTITY[config=Release] = Developer ID Application: Your Name (YOUR_TEAM_ID)
```

证书名称和 Team ID 是公开身份信息，私钥始终保留在钥匙串中。项目不包含 Python 构建入口，也不使用 `work/` 目录。编译中间文件由 Xcode 的 DerivedData 管理。

## 可选的本机命令行发行

`scripts/release.sh` 调用标准的 `xcodebuild archive` 和 `-exportArchive`，随后创建 DMG，签名、提交 Apple 公证、装订票据并生成 SHA-256。它不提交代码、不推送或上传 GitHub。

使用同一 Apple 开发者团队已有的 notarytool 钥匙串配置，或者交互式创建：

```sh
xcrun notarytool store-credentials weft-local
NOTARY_PROFILE=weft-local ./scripts/release.sh
```

账号、团队和 App 专用密码在提示中输入，不写入仓库。有多个 Developer ID 身份时，通过 `SIGNING_IDENTITY` 指定证书全名。产物位于 `outputs/releases/<version>-<build>/`，已有目录不会覆盖。

本机发行脚本不运行测试、不启动应用或操作设备。时间戳或公证失败时立即停止并保留产物，不把未公证包标成正式版本。

## GitHub 自动产物

`.github/workflows/ci.yml` 在分支推送、PR、版本标签或手动触发时使用 Xcode 运行主机检查，再构建 Apple Silicon + Intel 通用 Release 应用。Actions 的 Artifacts 提供测试 ZIP、SHA-256 和 `UNNOTARIZED.txt`。

该工作流不需要签名 Secrets。标签必须是带注释的 `vX.Y.Z`，与 `Config/Weft.xcconfig` 一致，并位于 main 历史中。标签不会自动创建正式 GitHub Release。

## 正式公开发布

`main` 保存可公开的稳定版本，`dev` 用于日常开发。首次提交建立在 main，dev 从同一提交创建；后续发行前将准备好的版本合入 main。

审核首次提交文件后再推送。从干净的 main 提交打版本标签，等待该提交的 CI 通过，再从同一提交本机归档、签名和公证。将最终 DMG 与 `.dmg.sha256` 上传 GitHub Release 草稿，重新下载核对后再发布。

参考：[Apple 公证工作流](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)。
