import AppKit
import MusicCore
import SwiftUI

struct DownloadsView: View {
  @Environment(\.locale) private var locale
  @Environment(\.musicPageIsActive) private var isActive
  @State private var selection = Set<UUID>()
  @EnvironmentObject var model: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.state.downloadDirectory).font(.caption).foregroundStyle(.secondary).textSelection(
        .enabled
      ).padding(.horizontal, 32).padding(.top, 24)
      if model.state.downloads.isEmpty {
        ContentUnavailableView(
          L10n.text("还没有下载"), systemImage: "arrow.down.circle",
          description: Text(L10n.text("在歌曲菜单中选择下载，或批量下载整个列表。"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(selection: $selection) {
          ForEach(model.state.downloads.reversed()) { job in
            HStack(spacing: 10) {
              Artwork(url: job.track.artwork, size: 30, radius: 4)
              VStack(alignment: .leading, spacing: 5) {
                Text(job.track.title).font(.headline)
                Text("\(job.track.artist) · \(job.quality)").font(.caption).foregroundStyle(
                  .secondary)
                if let error = job.error {
                  Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
              }.frame(maxWidth: .infinity, alignment: .leading)
              VStack(alignment: .trailing, spacing: 6) {
                Text(job.status.name).font(.caption).foregroundStyle(
                  job.status == .failed ? Color.red : .secondary)
                if job.status == .downloading {
                  ProgressView(value: job.progress).frame(width: 120)
                  Text("\(Int(job.progress*100))%").font(.caption2).monospacedDigit()
                }
              }
              if [.queued, .resolving, .downloading].contains(job.status) {
                Button {
                  model.cancelDownload(job.id)
                } label: {
                  Image(systemName: "xmark.circle")
                }.help(L10n.text("取消下载"))
              }
              if [.failed, .cancelled].contains(job.status) {
                Button(L10n.text("重试")) { model.retryDownload(job.id) }
              }
              if let path = job.file, [.completed, .skipped].contains(job.status) {
                Button {
                  model.play(job.track)
                } label: {
                  Image(systemName: "play.fill")
                }.help(L10n.text("播放已下载歌曲"))
                Button {
                  NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                  Image(systemName: "folder")
                }.help(L10n.text("在 Finder 显示"))
              }
            }.padding(.vertical, 3).tag(job.id)
          }
        }.listStyle(.inset)
          .background(ScrollPositionMemory(active: isActive, table: true))
          .accessibilityHidden(!isActive)
      }
    }.toolbar {
      if isActive {
        ToolbarItem(placement: .primaryAction) {
          Button(L10n.text("保存位置…")) { model.chooseDirectory() }
        }
      }
    }.onChange(of: model.state.downloads.map(\.id)) { _, ids in selection.formIntersection(Set(ids))
    }
  }
}
struct DownloadSheet: View {
  @Environment(\.locale) private var locale
  @EnvironmentObject var model: AppModel
  @Environment(\.dismiss) var dismiss
  let tracks: [Track]
  @State private var quality = "320k"
  private var choices: [String] {
    guard let first = tracks.first else { return [] }
    let intersection = tracks.dropFirst().reduce(Set(model.qualities(for: first))) {
      $0.intersection(model.qualities(for: $1))
    }
    return ["128k", "320k", "flac", "flac24bit"].filter { intersection.contains($0) }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(L10n.text("下载 \(tracks.count) 首歌曲")).font(.title2.bold())
      Text(L10n.text("选择下载音质，文件将保存在指定目录。已有文件会跳过。")).foregroundStyle(.secondary)
      if choices.isEmpty {
        Label(
          L10n.text("当前音乐源无法以同一种音质下载这些歌曲，请先启用源或按平台分批选择。"), systemImage: "exclamationmark.circle"
        )
        .foregroundStyle(.orange)
      } else {
        Picker(L10n.text("音质"), selection: $quality) {
          ForEach(choices, id: \.self) { Text($0).tag($0) }
        }
      }
      HStack {
        Text(model.state.downloadDirectory).font(.callout).lineLimit(2).textSelection(.enabled)
        Spacer()
        Button(L10n.text("更改…")) { model.chooseDirectory() }
      }
      HStack {
        Spacer()
        Button(L10n.text("取消"), role: .cancel) { dismiss() }
        Button(L10n.text("开始下载")) {
          model.state.downloadQuality = quality
          model.enqueueDownloads(tracks, quality: quality)
          dismiss()
        }.buttonStyle(.borderedProminent).disabled(!choices.contains(quality) || tracks.isEmpty)
      }
    }.padding(28).frame(width: 500).onAppear {
      quality =
        choices.contains(model.state.downloadQuality)
        ? model.state.downloadQuality : choices.first ?? "320k"
    }
  }
}
