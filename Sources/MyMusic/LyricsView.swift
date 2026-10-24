import AppKit
import MusicCore
import SwiftUI

@MainActor final class LyricsPresentation: ObservableObject {
  @Published private(set) var document: LyricsDocument?
  @Published private(set) var loading = false
  @Published private(set) var failed = false
  private let service: LyricsService
  private var generation = UUID()
  init(service: LyricsService = .shared) { self.service = service }
  func load(_ track: Track, refresh: Bool = false) async {
    let token = UUID()
    generation = token
    document = nil
    failed = false
    loading = true
    defer { if generation == token { loading = false } }
    do {
      let result = try await service.lyrics(for: track, refresh: refresh)
      try Task.checkCancellation()
      if generation == token { document = result }
    } catch {
      if generation == token && !(error is CancellationError) && !Task.isCancelled { failed = true }
    }
  }
}

struct LyricsPanel: View {
  @Environment(\.locale) private var locale
  let track: Track
  let clock: PlaybackClock
  let seek: (Double) -> Void
  @StateObject private var lyrics = LyricsPresentation()
  @State private var retry = 0
  var body: some View {
    Group {
      if lyrics.loading {
        ProgressView(L10n.text("正在载入歌词…")).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let document = lyrics.document, !document.isEmpty {
        if document.isTimed {
          SyncedLyricsView(document: document, clock: clock, seek: seek)
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 20) {
              Text(L10n.text("此歌词暂不支持逐行同步")).font(.caption).foregroundStyle(.secondary)
              Text(document.plainText).font(.system(size: 25, weight: .semibold))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.vertical, 30).padding(.horizontal, 12)
          }.scrollIndicators(.hidden).background(LyricsScrollObserver {})
        }
      } else {
        VStack(spacing: 14) {
          Image(systemName: "quote.bubble").font(.system(size: 32)).foregroundStyle(.secondary)
          Text(lyrics.failed ? L10n.text("歌词暂时无法载入") : L10n.text("暂无歌词"))
            .font(.title3.weight(.semibold))
          Text(L10n.text("可以继续聆听，或稍后重试。")).font(.callout).foregroundStyle(.secondary)
          Button(L10n.text("重试")) { retry += 1 }.buttonStyle(.bordered)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .accessibilityElement(children: .contain).accessibilityLabel(L10n.text("歌词"))
    .task(id: "\(track.id):\(retry)") { await lyrics.load(track, refresh: retry > 0) }
  }
}

/// The playback clock is observed only here; lyric ticks never invalidate the catalog.
private struct SyncedLyricsView: View {
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let document: LyricsDocument
  @ObservedObject var clock: PlaybackClock
  let seek: (Double) -> Void
  @State private var following = true
  private var active: Int? { document.activeLine(at: clock.position) }
  var body: some View {
    GeometryReader { geometry in
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(document.lines) { line in
              Button {
                following = true
                seek(line.time)
                scroll(to: line.id, proxy: proxy)
              } label: {
                VStack(alignment: .leading, spacing: 8) {
                  Text(line.text.isEmpty ? "•••" : line.text)
                    .font(.system(size: geometry.size.width < 340 ? 24 : 29, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                  if let translation = line.translation, !translation.isEmpty {
                    Text(translation).font(.system(size: 17, weight: .medium))
                      .fixedSize(horizontal: false, vertical: true)
                  }
                }
                .foregroundStyle(.primary.opacity(active == line.id ? 1 : 0.35))
                .animation(
                  reduceMotion ? nil : .easeInOut(duration: 0.25), value: active == line.id
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4).contentShape(Rectangle())
              }.buttonStyle(.plain).id(line.id)
                .accessibilityLabel(line.text.isEmpty ? L10n.text("间奏") : line.text)
                .accessibilityHint(L10n.text("从此句开始播放"))
                .accessibilityAddTraits(active == line.id ? .isSelected : [])
            }
          }.padding(.horizontal, 18).padding(.vertical, geometry.size.height * 0.36)
        }
        .scrollIndicators(.hidden)
        .background(LyricsScrollObserver { following = false })
        .mask {
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0), .init(color: .black, location: 0.10),
              .init(color: .black, location: 0.88), .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .overlay(alignment: .bottomTrailing) {
          if !following {
            Button {
              following = true
              if let active { scroll(to: active, proxy: proxy) }
            } label: {
              Label(L10n.text("回到当前歌词"), systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered).background(.regularMaterial, in: Capsule()).padding(12)
          }
        }
        .onAppear { if let active { proxy.scrollTo(active, anchor: .center) } }
        .onChange(of: active) { _, value in
          if following, let value { scroll(to: value, proxy: proxy) }
        }
      }
    }
  }
  private func scroll(to id: Int, proxy: ScrollViewProxy) {
    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
      proxy.scrollTo(id, anchor: .center)
    }
  }
}

/// Native live-scroll notifications distinguish user browsing from animated follow scrolling.
private struct LyricsScrollObserver: NSViewRepresentable {
  let onScroll: () -> Void
  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) {
    view.onScroll = onScroll
    view.needsLayout = true
  }
  final class Anchor: NSView {
    var onScroll: (() -> Void)?
    private var observation: NSObjectProtocol?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil {
        detach()
      } else {
        DispatchQueue.main.async { [weak self] in self?.attach() }
      }
    }
    override func layout() {
      super.layout()
      attach()
    }
    private func attach() {
      guard observation == nil, window != nil else { return }
      func find(_ node: NSView) -> NSScrollView? {
        if let scroll = node as? NSScrollView { return scroll }
        for child in node.subviews where child !== self {
          if let found = find(child) { return found }
        }
        return nil
      }
      var parent = superview
      while let node = parent {
        if let scroll = find(node) {
          scroll.identifier = NSUserInterfaceItemIdentifier("MyMusic.synchronizedLyrics")
          scroll.hasVerticalScroller = false
          observation = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification, object: scroll, queue: .main
          ) { [weak self] _ in self?.onScroll?() }
          return
        }
        parent = node.superview
      }
    }
    private func detach() {
      if let observation { NotificationCenter.default.removeObserver(observation) }
      observation = nil
    }
    deinit { if let observation { NotificationCenter.default.removeObserver(observation) } }
  }
}
