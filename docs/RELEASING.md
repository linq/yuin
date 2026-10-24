# 构建与发布

工作流：`.github/workflows/build-release.yml`。

## 版本与触发方式

- `VERSION` 保存应用的三段版本号，例如 `0.1.0`。打包时写入 `CFBundleShortVersionString`，设置和关于窗口随之更新。
- 推送 `main`、向 `main` 提交 PR，或手动运行工作流时，执行测试和打包；非标签构建使用 `0.1.0-dev.提交号` 标识文件名，不创建 Release。
- 推送 `v0.1.0` 这样的标签会自动发布正式 Release；`v0.1.0-beta.1` 会自动发布预发布版本。标签的基础版本必须与 `VERSION` 相同。
- Release 依赖整个 build job 成功，包含全部离线测试、通用架构校验、签名检查、源宿主资源初始化、DMG 验证和校验和验证。

发布新版本：先修改 `VERSION` 并提交、推送 `main`，再创建和推送相应的标签。标签推送后可在仓库 Actions 查看进度。

```bash
git tag v0.1.0
git push origin v0.1.0
```

工作流的 `workflow_dispatch` 也支持对已有标签重新打包发布；可通过 `gh workflow run build-release.yml --ref v0.1.0` 触发。重新运行同一标签时更新同名附件，不创建第二条 Release。

## 产物

每个版本包含：

- `Yuin-0.1.0-universal.dmg`：包含应用和 Applications 快捷方式。
- `Yuin-0.1.0-universal.zip`：保留包结构和执行权限的应用压缩包。
- `Yuin-0.1.0-universal.sha256`：两种安装包的 SHA-256 校验文件。

主程序和独立音乐源宿主均包含 arm64、x86_64；最低部署目标 macOS 14。本机/CI 不会把跨架构编译当作 Intel 真机运行验收。应用不包含个人资料库、下载音乐或自定义音乐源脚本。

当前使用 ad-hoc 签名，未使用 Apple Developer ID 证书或公证。Gatekeeper 可能限制首次打开。后续如需 Developer ID 签名与公证，需要另外接入相应的 Apple 凭据。

## 本地打包

要求 macOS、Xcode 26+，并使用完整 Xcode 工具链；脚本会在可用时选择 `/Applications/Xcode.app`，不改变全局 `xcode-select` 配置。

```bash
./scripts/build-app.sh                # 当前机器架构
APP_ARCH=universal ./scripts/build-app.sh
./scripts/package-release.sh 0.1.0   # Universal、ZIP、DMG、校验和
```

本地产物位于 `dist/`，不提交到 Git。`APP_BUILD_NUMBER` 可覆盖构建号；CI 使用 `github.run_number`。`APP_VERSION` 可覆盖应用版本，但必须为纯数字三段版本。

## 工作流环境

使用 `macos-26` runner 与 Xcode 26.6。Actions 的 checkout、upload-artifact 和 download-artifact 固定到上游提交 SHA。普通构建只有只读仓库权限；发布 job 单独获得 `contents: write`，通过 GitHub 自动提供的 `GITHUB_TOKEN` 发布附件，无需个人令牌。

联网平台检查、真实第三方源验收和滚动性能基准继续显式启用，不在公共 CI 中访问个人音乐源或依赖外部音乐平台的状态。
