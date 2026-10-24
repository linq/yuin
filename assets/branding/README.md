# 余音 · Yuin

应用中文名「余音」，英文名 Yuin。最终图标采用纯色红底与白色双声波，外轮廓参考用户提供的 Music ICNS 的连续大圆角。红色填满图标主体，没有内嵌底板。导出时按照参考文件，在 1024 像素画布内使用 824 像素的主体，四边各留 100 像素透明安全区域，使 Dock 中的视觉大小与 Music 一致。

- `yuin-icon.svg`：最终使用的矢量母版，纯色 `#FA2D48` + `#FFFFFF`，不含滤镜、渐变或半透明主体。
- `yuin-icon-final.png`：1024 × 1024 的最终 PNG 预览，主体不透明，主体之外为标准透明安全区域。
- `yuin-icon-red.png`、`yuin-icon.png`：早期生成的红色和蓝色草稿，保留供追溯，不用于打包。
- `../../scripts/make-icon.swift`：使用 AppKit 直接从 SVG 渲染 16–1024 像素的标准 macOS iconset，保留透明圆角。
- 构建产物：`../../dist/Yuin.app/Contents/Resources/AppIcon.icns`。
- 草稿使用内置 `image_gen.imagegen`。透明草稿出现主体雾感和边缘杂点，因此最终根据用户提供的 ICNS 参考重绘为代码原生 SVG；不使用存在问题的生成图片打包。
- 改名保留 `local.mymusic.mac` 标识及原有 MyMusic 数据路径，以兼容已有资料库、下载记录和偏好设置；Swift 包和内部模块名不变。

## 生成提示词

最终绘制规范：参考提供的 Music 图标大圆角及 Dock 主体比例，纯红色主体、纯白色双声波，无纹理、雾化、渐变或内嵌底板；按标准透明安全区域导出。以下为早期草稿提示词。

### 红色草稿

Edit this Yuin app icon. Preserve the existing two ivory-white flowing sound-wave ribbon shapes exactly in style, proportions, relative placement and simple silhouette. Change the background from blue to a clean vibrant warm red (#F12F48), with at most an extremely subtle red tonal gradient. Crucially REMOVE the inset rounded-square tile and ALL transparent/empty exterior margins: the red background must fill the ENTIRE square image edge to edge, including every corner. This is full-bleed artwork for a macOS icon; the OS will apply its own rounded mask. Enlarge/recenter the white symbol slightly so its combined silhouette occupies about 60% of the square width and remains optically centered. The entire result is one flat square of red with the white flowing mark, no inner tile, no rounded corners baked into the image, no outer white plate, no border, no shadow, no transparency, no blue, no words, no additional objects. Output only the finished square icon artwork.

### 初稿

Use case: logo-brand. Asset type: production macOS application icon for a minimalist native music player named Yuin (Chinese name 余音). Create a single finished icon, centered front-on, on a 1024 by 1024 square canvas. A deep midnight blue rounded-square macOS icon tile, inset about 9% from each canvas edge with generous rounded corners, exterior truly transparent. On the tile, a single bold ivory-white abstract sound-wave mark: two smooth, thick, gently curved ribbon strokes that together suggest a subtle lowercase y and lingering musical resonance. Keep the silhouette extremely simple, balanced, immediately legible at 16px. Nearly flat vector-like finish, only a very restrained blue tonal gradient in the tile; no texture, no glass or metallic effects. The white symbol occupies about half the tile, ample negative space. No words, no letters as typography, no musical note glyph, no headphones, no equalizer bars, no outer border, no mockup, no extra objects. Output the actual icon artwork only, not a presentation.
