import AppKit
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
    TabView {
      pane {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 18) {
          row("外观模式") {
            VStack(alignment: .leading, spacing: 8) {
              Picker(L10n.text("外观模式"), selection: $appearance) {
                ForEach(MusicAppearance.allCases) { Text($0.name).tag($0) }
              }.labelsHidden().frame(width: 220)
              note("跟随系统时，应用会随 macOS 的亮色、深色外观自动切换。")
            }
          }
          Divider().gridCellUnsizedAxes(.horizontal)
          row("应用语言") {
            VStack(alignment: .leading, spacing: 8) {
              Picker(L10n.text("应用语言"), selection: $language) {
                ForEach(MusicLanguage.allCases) { Text($0.name).tag($0) }
              }.labelsHidden().frame(width: 220)
              note("默认跟随 macOS 语言，切换后立即生效。")
            }
          }
          Divider().gridCellUnsizedAxes(.horizontal)
          row("关于") {
            let version =
              Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
              ?? "0.1.0"
            Text(L10n.text("余音") + "  " + L10n.text("\(version) · 开发版"))
              .foregroundStyle(.secondary)
          }
        }
      }.tabItem { Label(L10n.text("通用"), systemImage: "gearshape") }

      pane {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 18) {
          row("音质") { qualityPicker(playback: true) }
          Divider().gridCellUnsizedAxes(.horizontal)
          row("切歌淡出") {
            VStack(alignment: .leading, spacing: 8) {
              HStack(spacing: 12) {
                Slider(
                  value: Binding(
                    get: { model.state.crossfadeSeconds },
                    set: {
                      model.state.crossfadeSeconds = $0
                      model.persist()
                    }), in: 0...12, step: 1
                )
                .accessibilityLabel(L10n.text("切歌淡出时长"))
                Text(
                  model.state.crossfadeSeconds == 0
                    ? L10n.text("关闭") : L10n.text("\(Int(model.state.crossfadeSeconds)) 秒")
                )
                .monospacedDigit().frame(width: 44, alignment: .trailing)
              }
              note("新歌曲直接播放，原歌曲按设定时长淡出。0 秒关闭。")
            }
          }
          Divider().gridCellUnsizedAxes(.horizontal)
          row("待播队列") { note("重启后恢复待播队列，但不会自动播放。") }
        }
      }.tabItem { Label(L10n.text("播放设置"), systemImage: "play.circle") }

      pane {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 18) {
          row("音质") { qualityPicker(playback: false) }
          Divider().gridCellUnsizedAxes(.horizontal)
          row("下载目录") {
            VStack(alignment: .leading, spacing: 10) {
              Text(model.state.downloadDirectory).lineLimit(2).textSelection(.enabled)
                .font(.system(size: 12)).foregroundStyle(.secondary)
              Button(L10n.text("选择…")) { model.chooseDirectory() }
            }
          }
          Divider().gridCellUnsizedAxes(.horizontal)
          row("下载") { note("同时下载两首。") }
        }
      }.tabItem { Label(L10n.text("文件"), systemImage: "folder") }

      pane {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 18) {
          row("备份与恢复") {
            VStack(alignment: .leading, spacing: 14) {
              note("备份包含列表、历史、设置和音乐源脚本；音频文件保留在下载目录，不包含在备份中。")
              HStack(spacing: 12) {
                Button(L10n.text("导出备份…")) { model.exportBackup() }
                Button(L10n.text("恢复备份…")) { model.restoreBackup() }
              }
            }
          }
        }
      }.tabItem { Label(L10n.text("高级"), systemImage: "gearshape.2") }
    }
    .frame(width: 640, height: 350)
    .font(.system(size: 14))
    .tint(Color(nsColor: TrackTableAppearance.selectionColor))
    .onChange(of: model.state.playbackQuality) { _, _ in model.persist() }
    .onChange(of: model.state.downloadQuality) { _, _ in model.persist() }
    .onDisappear { model.persist() }
  }
  private func pane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
      ScrollView {
        content().frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(.horizontal, 24).padding(.vertical, 26)
      }
      Divider()
      HStack {
        Spacer()
        Button(L10n.text("完成")) { NSApp.keyWindow?.performClose(nil) }
          .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
          .controlSize(.regular).frame(minWidth: 72)
      }.padding(.horizontal, 20).padding(.vertical, 12)
    }.background(Color(nsColor: .controlBackgroundColor))
  }
  private func row<Content: View>(_ title: MusicLocalizedText, @ViewBuilder content: () -> Content)
    -> some View
  {
    GridRow(alignment: .firstTextBaseline) {
      Text(L10n.text(title)).frame(width: 140, alignment: .trailing)
      content().frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private func note(_ text: MusicLocalizedText) -> some View {
    Text(L10n.text(text)).font(.system(size: 12)).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
  @ViewBuilder private func qualityPicker(playback: Bool) -> some View {
    if qualities.isEmpty {
      note("启用音乐源后可选择默认音质。")
    } else {
      let selection = playback ? model.state.playbackQuality : model.state.downloadQuality
      Picker(
        L10n.text(playback ? "默认播放音质" : "默认下载音质"),
        selection: Binding(
          get: { playback ? model.state.playbackQuality : model.state.downloadQuality },
          set: {
            if playback {
              model.state.playbackQuality = $0
            } else {
              model.state.downloadQuality = $0
            }
          }
        )
      ) {
        if !qualities.contains(selection) {
          Text(L10n.text("\(selection)（此源不支持）")).tag(selection)
        }
        ForEach(qualities, id: \.self) { Text($0).tag($0) }
      }.labelsHidden().frame(width: 220)
    }
  }
}
