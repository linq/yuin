# 余音 · Yuin

[English](README.md) | 简体中文

[![Build and Release](https://github.com/linq/yuin/actions/workflows/build-release.yml/badge.svg)](https://github.com/linq/yuin/actions/workflows/build-release.yml)

参考 Apple Music 布局的 macOS 原生音乐应用，使用 SwiftUI、AppKit 和 AVPlayer，支持导入 LX 自定义 JavaScript 音乐源。

当前是 **0.1.0 开发版**。五个平台的公开浏览接口已联网验证；用户提供的 Hei Music 聚合源 v2.2.1-fix 已通过在线/本地导入、初始化、五平台取流播放和下载至离线播放样本验证。各音质请求成功不等于实际码率或位深认证，详见验收记录。

## 运行

可在 [GitHub Releases](https://github.com/linq/yuin/releases) 下载 Universal 版本，同时支持 Apple Silicon 和 Intel。提供 DMG、ZIP 及 SHA-256 校验文件。当前构建使用 ad-hoc 签名，尚未使用 Apple Developer ID 签名或公证。

已经构建的应用位于 `dist/Yuin.app`，可直接打开。中文名称为「余音」，英文名称为 Yuin。

```bash
./scripts/build-app.sh
open dist/Yuin.app
```

脚本默认生成 Release 构建；`./scripts/build-app.sh debug` 生成 Debug 构建。项目无外部 Swift 包依赖，使用完整 Xcode 工具链。脚本通过单次进程的 `DEVELOPER_DIR` 选择 `/Applications/Xcode.app`，不修改系统的 `xcode-select` 设置。

也可在 Xcode 打开 `Package.swift` 编辑，构建需要 Xcode 26 或更新版本。单独 `swift run MyMusic` 前应先执行 `swift build`，确保 `MusicSourceHost` 同时构建。部署目标 macOS 14+，本机验证环境为 macOS 27.0.1 / Apple Silicon，CI 使用 macOS 26；Universal 包含 Intel 架构，但尚未在 Intel 真机或 macOS 14–15 上运行验收。

## 自动构建与发布

- 推送 `main` 或创建 Pull Request：运行测试，编译 Universal 应用，生成 DMG、ZIP 和校验文件，可在 Actions 的 Artifacts 下载。
- 推送 `vX.Y.Z` 或 `vX.Y.Z-beta.1` 标签：相同检查通过后自动创建 GitHub Release，并上传安装包；带后缀的标签会标记为预发布。
- 修改根目录 `VERSION` 并提交，再推送与该版本对应的标签即可发布。只在 Release 发布步骤授予 `contents: write`，无需配置个人访问令牌。

```bash
./scripts/package-release.sh 0.1.0
# 确认 VERSION 与准备发布的版本一致后：
git tag v0.1.0
git push origin v0.1.0
```

详情见 [构建与发布说明](docs/RELEASING.md)。

## 使用

1. 可先在搜索、歌单、排行榜页面选择音乐平台，浏览真实数据。三个页面共用最近选择的平台，切换页面和重启后都会保留，也包含在备份中。
2. 在“音乐源”页面通过本地 `.js` 文件或 HTTP(S) 链接导入源，点击“启用”。可保存多个源，同时启用一个。
3. 双击歌曲播放；右键或歌曲菜单支持下一首播放、加入队尾、收藏、加入列表和下载。
4. 歌单、排行榜详情可保存完整本地副本或批量下载。列表未完整获取时会提示错误，不静默保存部分结果。
5. 下载选择音质与目录，最多两首并发。保存前校验编码格式、码率及 24bit 位深，源返回低档音质时明确报错；已有文件也重新校验。已下载歌曲优先使用本地文件，断网也可播放。
6. 设置中可修改默认音质、导出与恢复备份。恢复备份后，音乐源需手动启用。

底部悬浮播放器支持播放控制、随机/单曲循环、进度、歌曲菜单、待播队列和音量。点击封面或歌曲名称展开大封面播放页；窄窗口会收起部分按钮，播放模式仍可从歌曲菜单选择。

切歌支持交叉淡化：两首歌重叠播放，上一首渐弱、下一首渐强。在「设置 → 播放与下载」中调整为 0–12 秒，默认 5 秒，0 秒关闭。顺序播放会预先准备下一首，并在当前歌曲结束前开始衔接；网络缓冲可能缩短实际重叠时间。封面与曲目信息平滑过渡，新封面载入前保留旧封面。

同一窗口内切换到歌单、排行榜或其他页面再回到搜索，会保留输入中的关键词、已提交的搜索结果、已加载分页、选中项和滚动位置，不会因切页重新搜索。若在其他页面更换了音乐平台，返回搜索时会按新平台重新查询。搜索会话暂不跨应用重启恢复。

快捷键：`⌘N` 新建列表，`⇧⌘I` 导入源，`空格` 播放／暂停，`⌘←` / `⌘→` 上一首／下一首，`⌘U` 待播队列。在搜索及其他文本输入框内，空格仍正常用于输入。支持系统媒体播放控制。

## 数据

应用原名 MyMusic。改名保留原有应用标识、资料库和偏好设置，下面的数据路径继续兼容旧版本。

- 本地状态：`~/Library/Application Support/MyMusic/library.json`。
- 默认下载目录：`~/Music/MyMusic`，可在设置或下载对话框更改。
- 备份包含列表、历史、队列、设置、源脚本和下载记录，**不包含音频文件**。离线文件仍依赖原路径。
- 恢复会先保存恢复前快照；损坏的状态文件不会被空状态自动覆盖。
- 重启恢复队列和进度，不自动播放。中断的下载保留记录，需手动重试。

## 测试

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
MUSIC_NETWORK_TESTS=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

普通测试不依赖音乐平台，只使用本地 HTTP 测试服务及临时目录。联网测试需要设置 `MUSIC_NETWORK_TESTS=1`，会打印各平台能力与完整列表读取结果。平台偶发失败会单独报告，不能从测试套件通过推断每个平台永远可用。

本地集成测试覆盖在线源导入、LX HTTP 回调、Buffer、MD5、AES/RSA OpenSSL 对照、zlib、初始化失败保留旧源、无限循环脚本超时终止、下载取消、重复文件跳过、下载文件验证和 AVPlayer 离线播放。测试音频是程序生成的静音 WAV，并非真实音乐服务；不随应用提供演示音乐源。

真实源验收需显式提供可信脚本，可用 URL 或本地路径：

```bash
MUSIC_REAL_SOURCE='/absolute/path/source.js' DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RealSourceTests
```

可选环境变量：`MUSIC_REAL_ALL_QUALITIES=1` 遍历源声明的音质；`MUSIC_REAL_QUERY` 指定搜索词；`MUSIC_REAL_PLATFORM=kw` 仅测指定平台；`MUSIC_REAL_DOWNLOAD_ALL=1` 下载各个成功播放的样本。测试静音播放，下载至临时目录并自动清理；不会修改应用资料库。最低通过门槛是至少一个真实样本播放、下载并在停止源后离线播放，单个平台失败仍会打印，需逐项检查日志。第三方脚本不随仓库分发，脚本可能自行访问统计接口。

## 实现结构

- `Sources/MusicCore/`：歌曲模型、五个平台适配器、完整列表分页、本地持久化、源进程客户端、下载保存。
- `Sources/MusicSourceHost/`：独立 JavaScriptCore 进程，提供 `window.lx` API 2.0 桥接；超时可终止，不阻塞原生界面。
- `Sources/MyMusic/`：SwiftUI 页面、AVPlayer、系统媒体控制、下载调度与源管理。
- `Tests/`：模型、分页回归、源协议、本地端到端和可选联网测试。
- `scripts/build-app.sh`：构建完整 `.app`、资源和源进程，使用本机临时签名，未公证。

兼容层提供 HTTP、定时器、基础 Buffer 操作、MD5、随机字节、AES CBC/ECB、LX 1024 位 RSA 原始填充语义和 zlib。它不是完整 Node.js 或浏览器环境，不提供 DOM、Node 文件系统、任意原生模块等能力。独立进程用于隔离脚本故障，不等于操作系统权限沙箱。所有真实源兼容范围需以具体脚本验证。

平台接口可能随时变动。接口错误会显示并允许重试，不用示例结果代替。当前已支持歌词；平台账号登录、跨设备同步、本地目录扫描、断点续传等不在本轮范围。

详见 [确认的需求](docs/REQUIREMENTS.md)、[当前验收记录](docs/STATUS.md) 和 [第三方声明](docs/THIRD_PARTY_NOTICES.md)。
