import MusicCore
import SwiftUI

struct SourcesView: View {
  @Environment(\.locale) private var locale
  @Environment(\.musicPageIsActive) private var isActive
  @EnvironmentObject var model: AppModel
  @State private var link = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "link").foregroundStyle(.secondary)
        TextField(L10n.text("粘贴音乐源的 HTTP(S) 链接"), text: $link).textFieldStyle(.plain)
        Button(L10n.text("在线导入")) {
          let value = link
          Task { await model.importOnline(value) }
        }
        .buttonStyle(.borderedProminent)
        .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.sourceBusy)
      }.padding(8).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
      if model.sourceBusy {
        HStack {
          ProgressView().controlSize(.small)
          Text(L10n.text("正在导入或验证音乐源…")).font(.callout).foregroundStyle(.secondary)
        }
      }
      if let issue = model.sourceIssue {
        Label(issue, systemImage: "exclamationmark.circle")
          .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
      }
      if model.state.sources.isEmpty {
        ContentUnavailableView(
          L10n.text("添加你的第一个音乐源"), systemImage: "waveform.path",
          description: Text(L10n.text("支持本地 .js 文件或在线链接。\n导入后点击启用，即可尝试播放和下载。"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 10) { ForEach(model.state.sources) { source in sourceCard(source) } }
            .padding(.bottom, 20).accessibilityHidden(!isActive)
        }.contentMargins(.bottom, FloatingPlayerOverlay.scrollClearance, for: .scrollContent)
          .background(ScrollPositionMemory(active: isActive))
      }
    }.padding(.horizontal, 32).padding(.top, 24)
      .toolbar {
        if isActive {
          ToolbarItem(placement: .primaryAction) {
            Button {
              model.importLocal()
            } label: {
              Label(L10n.text("本地导入"), systemImage: "square.and.arrow.down")
            }
            .disabled(model.sourceBusy)
          }
        }
      }
  }
  private func sourceCard(_ source: SourceRecord) -> some View {
    let active = source.id == model.state.activeSourceID && model.sourceReady
    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        Image(systemName: "waveform.path").font(.title3)
          .foregroundStyle(active ? MusicAccent.color : Color.secondary)
          .frame(width: 32, height: 32).background(
            .quaternary, in: RoundedRectangle(cornerRadius: 10))
        VStack(alignment: .leading, spacing: 5) {
          HStack {
            Text(source.name).font(.headline)
            if !source.version.isEmpty {
              Text(source.version).font(.caption).foregroundStyle(.secondary)
            }
          }
          Text(source.author.isEmpty ? L10n.text("作者未注明") : source.author).font(.caption)
            .foregroundStyle(
              .secondary)
        }
        Spacer()
        if active {
          Button(L10n.text("停用")) { model.disableSource() }
        } else {
          Button(L10n.text("启用")) { Task { await model.activate(source) } }.buttonStyle(
            .borderedProminent)
        }
        Menu {
          if source.origin != nil {
            Button(L10n.text("检查并更新")) { Task { await model.updateSource(source) } }
          }
          Button(L10n.text("移除"), role: .destructive) { model.deleteSource(source) }
        } label: {
          Image(systemName: "ellipsis")
        }.menuStyle(.borderlessButton).frame(width: 25)
      }.disabled(model.sourceBusy)
      if !source.description.isEmpty {
        Text(source.description).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
      }
      if active {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(MusicPlatform.allCases) { platform in
            if let capability = model.capabilities[platform.rawValue],
              capability.actions.contains("musicUrl")
            {
              Text("\(platform.name) · \(capability.qualitys.joined(separator: " / "))")
                .font(.caption).foregroundStyle(MusicAccent.color)
            }
          }
        }
      }
      HStack {
        Label(
          source.origin == nil ? L10n.text("本地导入") : L10n.text("在线导入 · 手动更新"),
          systemImage: source.origin == nil ? "doc" : "link")
        Spacer()
        if active {
          Label(L10n.text("正在使用"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
      }.font(.caption).foregroundStyle(.secondary)
    }.padding(12)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12).strokeBorder(
          active ? MusicAccent.color.opacity(0.4) : Color.secondary.opacity(0.12)))
  }
}
