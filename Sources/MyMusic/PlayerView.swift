import MusicCore
import SwiftUI

struct PlayerBar: View {
  @Environment(\.locale) private var locale
  @Environment(\.colorScheme) private var colorScheme
  @EnvironmentObject var model: AppModel
  @State private var showVolume = false
  var body: some View {
    GeometryReader { geometry in
      let compact = geometry.size.width < 560
      HStack(spacing: compact ? 10 : 14) {
        PlaybackControls(compact: compact)
        HStack(spacing: 9) {
          Button {
            model.showNowPlaying = true
          } label: {
            Color.clear.frame(width: 36, height: 36)
              .contentShape(Rectangle())
              .anchorPreference(key: PlayerArtworkAnchors.self, value: .bounds) { [.mini: $0] }
          }.buttonStyle(.plain).disabled(model.current == nil)
            .accessibilityLabel(L10n.text("展开正在播放"))
          VStack(alignment: .leading, spacing: 2) {
            Button {
              model.showNowPlaying = true
            } label: {
              PlayerTrackMetadata(track: model.current).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.current == nil)
              .help(
                model.current.map { "\($0.title)\n\($0.artist) — \($0.album)" }
                  ?? L10n.text("展开正在播放"))
            SeekBar(compact: true)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity)
        HStack(spacing: compact ? 10 : 13) {
          CurrentTrackMenu()
          Button {
            model.showLyrics = model.showNowPlaying ? !model.showLyrics : true
            model.showQueue = false
            model.showNowPlaying = true
          } label: {
            Image(systemName: "quote.bubble")
              .foregroundStyle(
                model.showNowPlaying && model.showLyrics ? MusicAccent.color : .primary)
          }.accessibilityLabel(L10n.text("歌词")).help(L10n.text("歌词"))
          Button {
            if model.showNowPlaying { model.showLyrics = false }
            model.showQueue.toggle()
          } label: {
            Image(systemName: "list.bullet")
              .foregroundStyle(model.showQueue ? MusicAccent.color : .primary)
              .frame(width: 27, height: 27)
              .background(
                model.showQueue ? Color.primary.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 6))
          }.accessibilityLabel(model.showQueue ? L10n.text("隐藏待播队列") : L10n.text("显示待播队列")).help(
            L10n.text("待播队列"))
          if !compact {
            Button {
              showVolume.toggle()
            } label: {
              Image(
                systemName: model.state.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }.accessibilityLabel(L10n.text("音量")).help(L10n.text("音量"))
              .popover(isPresented: $showVolume, arrowEdge: .top) {
                VolumeControl().padding(18).frame(width: 230)
              }
          }
        }.font(.system(size: 15)).buttonStyle(.plain)
      }.padding(.horizontal, compact ? 16 : 18).frame(height: 54)
        .background(.regularMaterial, in: Capsule())
        .overlay {
          Capsule().strokeBorder(
            LinearGradient(
              colors: colorScheme == .dark
                ? [.white.opacity(0.10), .white.opacity(0.02)]
                : [.black.opacity(0.10), .black.opacity(0.04)],
              startPoint: .top, endPoint: .bottom), lineWidth: 0.5
          )
          .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.14 : 0.05), radius: 8, y: 3)
    }.frame(height: 54).frame(maxWidth: 700)
  }
}

private struct PlaybackControls: View {
  @Environment(\.locale) private var locale
  @EnvironmentObject var model: AppModel
  var compact = false
  var large = false
  var spread = false
  var body: some View {
    HStack(spacing: spread ? 0 : large ? 22 : 12) {
      if !compact { modeButton(.shuffle, symbol: "shuffle", label: L10n.text("随机播放")) }
      if spread { Spacer(minLength: 12) }
      Button {
        model.next(backward: true)
      } label: {
        Image(systemName: "backward.fill")
      }.accessibilityLabel(L10n.text("上一首")).help(L10n.text("上一首"))
      if spread { Spacer(minLength: 12) }
      Button {
        model.togglePlayback()
      } label: {
        ZStack {
          if model.isLoadingAudio {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: large ? 32 : 22, weight: .semibold))
              .contentTransition(.symbolEffect(.replace))
          }
        }.frame(width: large ? 44 : 26, height: large ? 44 : 28)
      }.accessibilityLabel(
        model.isLoadingAudio
          ? L10n.text("取消载入") : model.isPlaying ? L10n.text("暂停") : L10n.text("播放")
      )
      .help(
        model.isLoadingAudio
          ? L10n.text("取消载入") : model.isPlaying ? L10n.text("暂停") : L10n.text("播放"))
      if spread { Spacer(minLength: 12) }
      Button {
        model.next()
      } label: {
        Image(systemName: "forward.fill")
      }.accessibilityLabel(L10n.text("下一首")).help(L10n.text("下一首"))
      if spread { Spacer(minLength: 12) }
      if !compact { modeButton(.repeatOne, symbol: "repeat.1", label: L10n.text("单曲循环")) }
    }.font(.system(size: large ? 20 : 15, weight: .semibold))
      .buttonStyle(.plain).disabled(model.current == nil)
  }
  private func modeButton(_ mode: PlaybackMode, symbol: String, label: String) -> some View {
    Button {
      model.state.queue.mode = model.state.queue.mode == mode ? .sequential : mode
      model.persist()
      model.prepareUpcomingPlayback()
    } label: {
      Image(systemName: symbol).font(.system(size: large ? 15 : 11, weight: .semibold))
        .foregroundStyle(model.state.queue.mode == mode ? MusicAccent.color : Color.secondary)
        .frame(width: 20, height: 24)
    }.accessibilityLabel(label).accessibilityValue(
      model.state.queue.mode == mode ? L10n.text("已开启") : L10n.text("已关闭")
    )
    .help(label)
  }
}

private struct CurrentTrackMenu: View {
  @Environment(\.locale) private var locale
  @EnvironmentObject var model: AppModel
  @State private var showDownload = false
  var body: some View {
    Menu {
      if let track = model.current {
        Button(L10n.text("正在播放…")) { model.showNowPlaying = true }
        Button(L10n.text("加入喜欢的音乐")) { model.favorite(track) }
        Menu(L10n.text("添加到列表")) {
          ForEach(model.state.playlists) { list in
            Button(list.name) { model.add([track], to: list.id) }
          }
        }
        Button(L10n.text("下载…")) { showDownload = true }
        Divider()
        Picker(
          L10n.text("播放模式"),
          selection: Binding(
            get: { model.state.queue.mode },
            set: {
              model.state.queue.mode = $0
              model.persist()
              model.prepareUpcomingPlayback()
            })
        ) {
          ForEach(PlaybackMode.allCases, id: \.self) { Text($0.name).tag($0) }
        }
      }
    } label: {
      Image(systemName: "ellipsis").frame(width: 20, height: 24)
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(.secondary)
    .disabled(model.current == nil).accessibilityLabel(L10n.text("歌曲操作")).help(L10n.text("歌曲操作"))
    .sheet(isPresented: $showDownload) {
      if let track = model.current { DownloadSheet(tracks: [track]) }
    }
  }
}

private struct VolumeControl: View {
  @Environment(\.locale) private var locale
  @EnvironmentObject var model: AppModel
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "speaker.fill").font(.caption)
      Slider(
        value: Binding(get: { Double(model.state.volume) }, set: { model.setVolume(Float($0)) }),
        in: 0...1
      )
      .accessibilityLabel(L10n.text("音量"))
      Image(systemName: "speaker.wave.3.fill").font(.caption)
    }.foregroundStyle(.secondary).tint(.secondary)
  }
}

struct SeekBar: View {
  @Environment(\.locale) private var locale
  @EnvironmentObject var model: AppModel
  var compact = false
  var body: some View {
    ClockSeekBar(
      clock: model.clock, enabled: model.current != nil, seek: model.seek, compact: compact)
  }
}

private struct ClockSeekBar: View {
  @Environment(\.locale) private var locale
  @ObservedObject var clock: PlaybackClock
  let enabled: Bool
  let seek: (Double) -> Void
  var compact = false
  private var position: Double { clock.position }
  var body: some View {
    VStack(spacing: compact ? 0 : 5) {
      CompactSeekSlider(
        position: clock.position, duration: clock.duration,
        enabled: enabled && clock.duration > 0, seek: seek
      ).frame(height: 12).padding(.horizontal, compact ? 0 : -10)
      if !compact {
        HStack {
          Text(Track.time(position))
          Spacer()
          Text("−" + Track.time(max(0, clock.duration - position)))
        }.font(.system(size: 11, design: .rounded).monospacedDigit()).foregroundStyle(.secondary)
      }
    }
  }
}
struct QueueView: View {
  @Environment(\.locale) private var locale
  @EnvironmentObject var model: AppModel
  @State private var showHistory = false
  @State private var browsing = false
  @State private var jumpRequest = 0
  @State private var scrollScope = NativeScrollScope()
  var inPlayer: Bool? = nil
  private var player: Bool { inPlayer ?? model.showNowPlaying }
  private var upcoming: [QueueEntry] { model.state.queue.upcoming }
  var body: some View {
    VStack(spacing: 0) {
      if !player {
        HStack(spacing: 8) {
          queueMode(.repeatOne, symbol: "repeat.1", label: L10n.text("单曲循环"))
          queueMode(.shuffle, symbol: "shuffle", label: L10n.text("随机播放"))
        }.padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 14)
        header.padding(.horizontal, 16).padding(.bottom, 10)
        Divider()
      }
      ZStack(alignment: .bottomTrailing) {
        List {
          if player {
            header.padding(.vertical, 8)
              .listRowInsets(EdgeInsets(top: 0, leading: -8, bottom: 0, trailing: 8))
              .listRowBackground(Color.clear).listRowSeparator(.visible)
              .listRowSeparatorTint(.white.opacity(0.12)).id("queue-start")
          }
          ForEach(upcoming) { entry in
            QueueTrackRow(entry: entry, player: player).id(entry.id)
              .listRowBackground(Color.clear)
              .listRowInsets(
                EdgeInsets(top: 0, leading: player ? -8 : -10, bottom: 0, trailing: player ? 8 : 4)
              )
              .listRowSeparatorTint(player ? .white.opacity(0.10) : .primary.opacity(0.12))
              .alignmentGuide(.listRowSeparatorLeading) { _ in 46 }
          }
          .onMove { offsets, target in model.moveUpcoming(from: offsets, to: target) }
          if upcoming.isEmpty {
            Text(L10n.text("暂无待播歌曲")).font(.system(size: 13)).foregroundStyle(.secondary)
              .padding(.vertical, 18).listRowBackground(Color.clear).listRowSeparator(.hidden)
          }
          if !model.state.history.isEmpty {
            DisclosureGroup(L10n.text("播放历史"), isExpanded: $showHistory) {
              ForEach(model.state.history.prefix(30)) { track in
                HStack(spacing: 10) {
                  Artwork(url: track.artwork, size: player ? 34 : 28, radius: 4)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).lineLimit(1)
                    Text(
                      [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — ")
                    )
                    .font(.system(size: player ? 12 : 11)).foregroundStyle(.secondary).lineLimit(1)
                  }
                }.padding(.vertical, 5).contentShape(Rectangle())
                  .onTapGesture(count: 2) { model.play(track, in: [track]) }
                  .contextMenu {
                    Button(L10n.text("播放")) { model.play(track, in: [track]) }
                    Button(L10n.text("下一首播放")) { model.enqueue(track, next: true) }
                    Button(L10n.text("添加到队尾")) { model.enqueue(track, next: false) }
                  }.listRowBackground(Color.clear)
              }
            }.font(.system(size: player ? 14 : 12, weight: .semibold))
              .listRowBackground(Color.clear).listRowSeparator(.hidden)
          }
        }
        .listStyle(.plain).font(.system(size: player ? 14 : 12))
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.disabled)
        .background(NativeScrollBoundary(scope: scrollScope, isStart: true))
        .overlay(NativeScrollBoundary(scope: scrollScope, isStart: false).allowsHitTesting(false))
        .background(
          QueueListAppearance(
            player: player, scope: scrollScope, entryIDs: upcoming.map(\.id),
            active: player
              ? model.showNowPlaying && model.showQueue : !model.showNowPlaying && model.showQueue,
            jumpRequest: jumpRequest, browsingChanged: { browsing = $0 }))
        if browsing {
          Button {
            jumpRequest += 1
          } label: {
            Label(L10n.text("回到接下来播放"), systemImage: "arrow.up.to.line")
              .font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).padding(
                .vertical, 8
              )
              .background(.regularMaterial, in: Capsule())
          }.buttonStyle(.plain).padding(10)
        }
      }
      if model.state.queue.mode == .shuffle {
        Text(L10n.text("随机模式会从队列中随机选择歌曲"))
          .font(.caption2).foregroundStyle(.secondary).padding(10)
      }
    }
    .background {
      if !player {
        Rectangle().fill(MusicSurface.navigationMaterial)
      }
    }
    .overlay(alignment: .top) {
      if !player { NavigationToolbarBackdrop() }
    }
    .accessibilityElement(children: .contain).accessibilityLabel(L10n.text("待播队列"))
  }
  private var header: some View {
    HStack(spacing: 12) {
      Text(L10n.text("待播队列")).font(.system(size: player ? 15 : 14, weight: .semibold))
      Spacer(minLength: 0)
      Button(L10n.text("清除")) { model.clearUpcoming() }
        .buttonStyle(.plain).font(.system(size: 13))
        .foregroundStyle(Color(nsColor: TrackTableAppearance.selectionColor))
        .disabled(upcoming.isEmpty).help(L10n.text("保留正在播放和播放历史"))
    }
  }
  private func queueMode(_ mode: PlaybackMode, symbol: String, label: String) -> some View {
    let selected = model.state.queue.mode == mode
    return Button {
      model.state.queue.mode = selected ? .sequential : mode
      model.persist()
      model.prepareUpcomingPlayback()
    } label: {
      Image(systemName: symbol).font(.system(size: 17, weight: .medium))
        .foregroundStyle(
          selected ? Color(nsColor: TrackTableAppearance.selectionColor) : Color.secondary
        )
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(Color.primary.opacity(selected ? 0.10 : 0.045), in: Capsule())
    }.buttonStyle(.plain).help(label).accessibilityLabel(label)
      .accessibilityValue(selected ? L10n.text("已开启") : L10n.text("已关闭"))
  }

}

private struct QueueTrackRow: View {
  @Environment(\.locale) private var locale
  @EnvironmentObject var model: AppModel
  let entry: QueueEntry
  var current = false
  var player = false
  @State private var hovered = false
  var body: some View {
    HStack(spacing: 12) {
      Artwork(url: entry.track.artwork, size: 34, radius: 5)
        .overlay(
          RoundedRectangle(cornerRadius: 5).strokeBorder(
            Color.primary.opacity(0.12), lineWidth: 0.5))
      VStack(alignment: .leading, spacing: 3) {
        Text(entry.track.title).font(.system(size: 14)).lineLimit(1)
          .foregroundStyle(current ? MusicAccent.color : .primary)
        Text(
          [entry.track.artist, entry.track.album].filter { !$0.isEmpty }.joined(separator: " — ")
        )
        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading)
      if current {
        PlaybackStateIcon(isLoading: model.isLoadingAudio, isPlaying: model.isPlaying).frame(
          width: 16)
      }
      Menu {
        actions
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
      .foregroundStyle(.secondary).tint(.secondary).opacity(hovered ? 1 : 0.7)
      .accessibilityLabel(L10n.text("\(entry.track.title)的队列操作"))
    }.padding(.vertical, 7).contentShape(Rectangle())
      .onHover { hovered = $0 }
      .onTapGesture(count: 2) { model.selectQueue(entry.id) }
      .contextMenu { actions }.help("\(entry.track.title) — \(entry.track.artist)")
  }
  @ViewBuilder private var actions: some View {
    Button(L10n.text("播放")) { model.selectQueue(entry.id) }
    if !current { Button(L10n.text("移到下一首")) { model.playNext(entry.id) } }
    Button(L10n.text("从队列移除"), role: .destructive) { model.removeQueue(entry.id) }
  }
}

struct PlaybackStateIcon: View {
  @Environment(\.locale) private var locale
  var isLoading = false
  var isPlaying = false
  var body: some View {
    Group {
      if isLoading {
        ProgressView().controlSize(.mini)
      } else {
        Image(systemName: isPlaying ? "waveform" : "pause.fill").font(.system(size: 11))
      }
    }.foregroundStyle(MusicAccent.color)
      .accessibilityLabel(
        isLoading ? L10n.text("载入中") : isPlaying ? L10n.text("正在播放") : L10n.text("已暂停"))
  }
}

struct NowPlayingView: View {
  @Environment(\.locale) private var locale
  @EnvironmentObject var model: AppModel
  @Environment(\.colorScheme) private var colorScheme
  private var isFavorite: Bool {
    guard let current = model.current else { return false }
    return model.state.playlists.first?.tracks.contains(where: { $0.id == current.id }) == true
  }
  var body: some View {
    GeometryReader { geometry in
      let metrics = NowPlayingMetrics(size: geometry.size)
      let split = model.showLyrics || model.showQueue
      ZStack(alignment: .topLeading) {
        VStack(spacing: 0) {
          cover(metrics.artworkSize)
          Color.clear.frame(height: metrics.artworkGap)
          controls
        }
        .frame(width: metrics.columnWidth)
        .offset(
          x: split ? metrics.leading : (geometry.size.width - metrics.columnWidth) / 2,
          y: metrics.top)
        if model.showNowPlaying, split {
          Group {
            if model.showQueue {
              QueueView()
                .mask {
                  LinearGradient(
                    stops: [
                      .init(color: .black, location: 0), .init(color: .black, location: 0.90),
                      .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .padding(.trailing, geometry.size.width < 900 ? 20 : 60)
                .padding(.top, 88).padding(.bottom, 12)
            } else if let track = model.current {
              LyricsPanel(track: track, clock: model.clock, seek: model.seek).id(track.id)
                .padding(.horizontal, geometry.size.width < 900 ? 20 : 40)
                .padding(.top, 60).padding(.bottom, 50)
            }
          }
          .frame(width: geometry.size.width / 2, height: geometry.size.height)
          .offset(x: geometry.size.width / 2)
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .overlay(alignment: .top) {
      HStack {
        Button {
          model.showNowPlaying = false
        } label: {
          Image(systemName: "xmark").font(.system(size: 17, weight: .medium))
            .frame(width: 36, height: 36).background(.white.opacity(0.12), in: Capsule())
        }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
          .accessibilityLabel(L10n.text("返回浏览")).help(L10n.text("返回浏览"))
        Spacer()
        VolumeControl().controlSize(.mini).frame(width: 150)
          .padding(.horizontal, 14).padding(.vertical, 10)
          .background(.white.opacity(0.12), in: Capsule())
      }.padding(.leading, 100).padding(.trailing, 10).padding(.top, 8)
    }
    .overlay(alignment: .bottomTrailing) { footer.padding(12) }
    .background {
      PlayerBackdrop(
        artwork: model.current?.artwork, active: model.showNowPlaying, dark: colorScheme == .dark)
    }
    // Album-colored full-window players use light controls in both system modes,
    // as Apple Music does. This affects this component, not the window appearance.
    .environment(\.colorScheme, .dark).foregroundStyle(.white).tint(.white)
  }
  private func cover(_ size: CGFloat) -> some View {
    Color.clear.frame(width: size, height: size)
      .anchorPreference(key: PlayerArtworkAnchors.self, value: .bounds) { [.expanded: $0] }
      .accessibilityHidden(true)
  }
  private var controls: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        PlayerTrackMetadata(track: model.current, large: true).textSelection(.enabled)
        Button {
          if let track = model.current { model.favorite(track) }
        } label: {
          Image(systemName: isFavorite ? "star.fill" : "star")
            .font(.system(size: 17)).frame(width: 26, height: 26)
            .background(.white.opacity(0.10), in: Circle())
        }.buttonStyle(.plain).disabled(model.current == nil || isFavorite)
          .accessibilityLabel(isFavorite ? L10n.text("已加入喜欢的音乐") : L10n.text("加入喜欢的音乐"))
        CurrentTrackMenu().font(.system(size: 16)).frame(width: 26, height: 26)
          .background(.white.opacity(0.10), in: Circle())
      }
      SeekBar()
      PlaybackControls(large: true, spread: true).frame(maxWidth: .infinity).padding(.top, 0)
    }
  }
  private var footer: some View {
    HStack(spacing: 8) {
      Button {
        model.showLyrics.toggle()
        model.showQueue = false
      } label: {
        Image(systemName: "quote.bubble.fill").frame(width: 32, height: 32)
          .foregroundStyle(
            model.showLyrics && !model.showQueue ? Color.black.opacity(0.65) : .white.opacity(0.8)
          )
          .background(
            model.showLyrics && !model.showQueue ? .white.opacity(0.85) : .clear, in: Circle())
      }.accessibilityLabel(L10n.text("歌词")).help(L10n.text("歌词"))
      Button {
        model.showQueue.toggle()
        if model.showQueue { model.showLyrics = false }
      } label: {
        Image(systemName: "list.bullet").frame(width: 32, height: 32)
          .foregroundStyle(model.showQueue ? Color.black.opacity(0.65) : .white.opacity(0.8))
          .background(model.showQueue ? .white.opacity(0.85) : .clear, in: Circle())
      }.accessibilityLabel(L10n.text("待播队列")).help(L10n.text("待播队列"))
    }.buttonStyle(.plain).font(.system(size: 17)).padding(4)
      .background(.white.opacity(0.08), in: Capsule())
  }
}

/// A single cover is drawn above both layouts; only its frame and corner radius animate.
struct PlayerArtworkAnchors: PreferenceKey {
  enum Placement: Hashable { case mini, expanded }
  static var defaultValue: [Placement: Anchor<CGRect>] = [:]
  static func reduce(
    value: inout [Placement: Anchor<CGRect>],
    nextValue: () -> [Placement: Anchor<CGRect>]
  ) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}
