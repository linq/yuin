import MusicCore
import SwiftUI

struct SettingsView: View {
  @Environment(\.locale) private var locale
  @EnvironmentObject var model: AppModel
  @AppStorage(MusicLanguage.preferenceKey) private var language: MusicLanguage = .system
  @AppStorage("appearanceMode") private var appearance: MusicAppearance = .system
  private var qualities: [String] {
    let available = Set(model.capabilities.values.flatMap(\.qualitys))
    return ["128k", "320k", "flac", "flac24bit"].filter { available.contains($0) }
  }
  var body: some View {
    Form {
      Section(L10n.text("外观")) {
        Picker(L10n.text("外观模式"), selection: $appearance) {
          ForEach(MusicAppearance.allCases) { Text($0.name).tag($0) }
        }
        Text(L10n.text("跟随系统时，应用会随 macOS 的亮色、深色外观自动切换。"))
          .font(.caption).foregroundStyle(.secondary)
      }
      Section(L10n.text("语言")) {
        Picker(L10n.text("应用语言"), selection: $language) {
          ForEach(MusicLanguage.allCases) { Text($0.name).tag($0) }
        }.pickerStyle(.segmented)
        Text(L10n.text("默认跟随 macOS 语言，切换后立即生效。"))
          .font(.caption).foregroundStyle(.secondary)
      }
      Section(L10n.text("播放与下载")) {
        LabeledContent(L10n.text("切歌淡出")) {
          Slider(
            value: Binding(
              get: { model.state.crossfadeSeconds },
              set: {
                model.state.crossfadeSeconds = $0
                model.persist()
              }
            ), in: 0...12, step: 1
          )
          .accessibilityLabel(L10n.text("切歌淡出时长"))
          Text(
            model.state.crossfadeSeconds == 0
              ? L10n.text("关闭") : L10n.text("\(Int(model.state.crossfadeSeconds)) 秒")
          )
          .monospacedDigit().frame(width: 48, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
        Text(L10n.text("新歌曲直接播放，原歌曲按设定时长淡出。0 秒关闭。"))
          .font(.caption).foregroundStyle(.secondary)
        if qualities.isEmpty {
          Text(L10n.text("启用音乐源后可选择默认音质。")).foregroundStyle(.secondary)
        } else {
          Picker(L10n.text("默认播放音质"), selection: $model.state.playbackQuality) {
            if !qualities.contains(model.state.playbackQuality) {
              Text(L10n.text("\(model.state.playbackQuality)（此源不支持）")).tag(
                model.state.playbackQuality)
            }
            ForEach(qualities, id: \.self) { Text($0).tag($0) }
          }
          Picker(L10n.text("默认下载音质"), selection: $model.state.downloadQuality) {
            if !qualities.contains(model.state.downloadQuality) {
              Text(L10n.text("\(model.state.downloadQuality)（此源不支持）")).tag(
                model.state.downloadQuality)
            }
            ForEach(qualities, id: \.self) { Text($0).tag($0) }
          }
        }
        LabeledContent(L10n.text("下载目录")) {
          Text(model.state.downloadDirectory).lineLimit(2)
          Button(L10n.text("选择…")) { model.chooseDirectory() }
        }
        Text(L10n.text("同时下载两首。重启后恢复待播队列，但不会自动播放。")).font(.caption).foregroundStyle(.secondary)
      }
      Section(L10n.text("备份与恢复")) {
        Text(L10n.text("备份包含列表、历史、设置和音乐源脚本；音频文件保留在下载目录，不包含在备份中。")).font(.callout).foregroundStyle(
          .secondary)
        HStack {
          Button(L10n.text("导出备份…")) { model.exportBackup() }
          Button(L10n.text("恢复备份…")) { model.restoreBackup() }
        }
      }
      Section(L10n.text("关于")) {
        let version =
          Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
          ?? "0.1.0"
        LabeledContent(L10n.text("余音"), value: L10n.text("\(version) · 开发版"))
        Text(L10n.text("macOS 原生音乐播放器 · LX 自定义源兼容\n真实源兼容性需要使用你的脚本验证。")).font(.caption)
          .foregroundStyle(
            .secondary)
      }
    }.formStyle(.grouped).padding(12).frame(width: 570, height: 580).onDisappear { model.persist() }
  }
}
