Yuin · 余音 — a native macOS music player.

## What's new in 0.1.1

- Smoother audio and artwork transitions, with next-track preparation. The outgoing song fades out for a configurable 0–12 seconds (5 seconds by default); the new song starts at normal volume.
- Space now reliably plays or pauses in the full player, including when a retained search field still has focus.
- Fixed catalog flashes when opening or closing the full player with the queue visible.
- Restored missing NetEase search and playback artwork, including songs saved in an existing library.
- Open playlists on launch, with reorganized native settings, larger search fields, and a more compact queue.
- Refined scrolling toolbar blur and continuous sidebar materials. Fixed missing red selection backgrounds in Recently Played, including multiple selection and history updates.
- English is now the default README, with a Simplified Chinese translation.

## 本次更新

- 切歌声音、封面与文字过渡更自然；原歌曲淡出时长可设为 0–12 秒，默认 5 秒，新歌曲以正常音量开始。
- 修复播放页空格暂停失效、队列打开时展开／关闭播放页闪烁，以及网易云搜索和播放封面缺失。
- 启动默认进入歌单页，重整原生设置，放大搜索框并优化待播队列。
- 统一顶部模糊与侧栏材质，修复最近播放中选中歌曲红色背景丢失，支持多选及历史更新后保持正确高亮。

## Download

- Universal app for Apple Silicon (arm64) and Intel (x86_64), requiring macOS 14 or later.
- Open the `.dmg` and drag `Yuin.app` to Applications, or extract the `.zip`.
- Use the `.sha256` file to verify your download.

This development release uses ad-hoc signing and is not Developer ID signed or notarized. macOS Gatekeeper may restrict the first launch. Third-party music sources are not bundled.
