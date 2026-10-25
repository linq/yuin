import MusicCore
import SwiftUI

struct ContentView: View {
  @Environment(\.locale) private var locale
  @EnvironmentObject var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var navigation = BrowserNavigationHistory()
  private var section: String? {
    get { navigation.current.section }
    nonmutating set { if let newValue { navigation.visit(MusicLocation(section: newValue)) } }
  }
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var showNewList = false
  @State private var listName = ""
  @State private var searchFocusRequest = 0
  @State private var backdrop = SidebarBackdropState()
  var body: some View {
    browser
      .background(
        PlaybackKeyboardShortcuts(expanded: model.showNowPlaying, toggle: model.togglePlayback)
      )
      .allowsHitTesting(!model.showNowPlaying)
      .accessibilityHidden(model.showNowPlaying)
      .overlay {
        // Keep both artwork anchors alive so reversing the animation uses the actual
        // mini-player position, including sidebar, queue and window-size changes.
        NowPlayingView()
          .opacity(model.showNowPlaying ? 1 : 0)
          .allowsHitTesting(model.showNowPlaying)
          .accessibilityHidden(!model.showNowPlaying)
          .ignoresSafeArea()
          .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.32), value: model.showNowPlaying)
      }
      .overlayPreferenceValue(PlayerArtworkAnchors.self) { anchors in
        GeometryReader { geometry in
          if let anchor = anchors[model.showNowPlaying ? .expanded : .mini] {
            let rect = geometry[anchor]
            PlayerArtwork(
              url: model.current?.artwork, size: rect.width,
              radius: model.showNowPlaying ? 10 : 5
            )
            .shadow(
              color: .black.opacity(model.showNowPlaying ? 0.28 : 0.16),
              radius: model.showNowPlaying ? 20 : 5, y: model.showNowPlaying ? 12 : 2
            )
            .scaleEffect(
              model.showNowPlaying && !(model.isPlaying || model.isLoadingAudio) ? 0.88 : 1
            )
            .animation(
              reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.86),
              value: model.isPlaying || model.isLoadingAudio
            )
            .position(x: rect.midX, y: rect.midY)
            .animation(
              reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.9),
              value: model.showLyrics
            )
            .animation(
              reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.9),
              value: model.showQueue
            )
            .animation(
              reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.88),
              value: model.showNowPlaying
            )
          }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
      .toolbar(model.showNowPlaying ? .hidden : .visible, for: .windowToolbar)
      .toolbarBackground(.hidden, for: .windowToolbar)
      .ignoresSafeArea(.container, edges: model.showNowPlaying ? .top : [])
  }

  private var browser: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      VStack(alignment: .leading, spacing: 0) {
        List {
          Section {
            sidebarItem(L10n.text("搜索"), icon: "magnifyingglass", id: "search")
            sidebarItem(L10n.text("歌单"), icon: "square.grid.2x2", id: "playlists")
            sidebarItem(L10n.text("排行榜"), icon: "chart.bar.xaxis", id: "charts")
          }
          Section {
            sidebarItem(L10n.text("最近播放"), icon: "clock", id: "history")
            sidebarItem(L10n.text("下载"), icon: "arrow.down.circle", id: "downloads")
          } header: {
            sidebarHeader(L10n.text("资料库"))
          }
          Section {
            ForEach(model.state.playlists) { list in
              sidebarItem(list.name, icon: "music.note.list", id: "list:\(list.id)")
            }
            Button {
              listName = ""
              showNewList = true
            } label: {
              Label(L10n.text("新建列表"), systemImage: "plus").font(.system(size: 15))
            }.buttonStyle(.plain).foregroundStyle(.secondary)
              .padding(.horizontal, 14).frame(height: 30, alignment: .leading)
              .listRowSeparator(.hidden).listRowBackground(Color.clear)
          } header: {
            sidebarHeader(L10n.text("我的列表"))
          }
          Section { sidebarItem(L10n.text("音乐源"), icon: "waveform.path", id: "sources") }
        }.listStyle(.plain).font(.system(size: 15))
          .contentMargins(.horizontal, 0, for: .scrollContent)
          .listRowSeparator(.hidden)
          .onMoveCommand { direction in
            let ids =
              ["search", "playlists", "charts", "history", "downloads"]
              + model.state.playlists.map { "list:\($0.id)" } + ["sources"]
            guard let index = ids.firstIndex(of: section ?? "search") else { return }
            if direction == .up { section = ids[max(0, index - 1)] }
            if direction == .down { section = ids[min(ids.count - 1, index + 1)] }
          }
          .scrollContentBackground(.hidden)
          .padding(.top, 6)
          .labelStyle(SidebarLabelStyle())
          .environment(\.defaultMinListRowHeight, 24)
        Button {
          section = "sources"
          model.showNowPlaying = false
        } label: {
          HStack(spacing: 8) {
            Circle().fill(model.sourceReady ? .green : .orange).frame(width: 6, height: 6)
            Text(model.activeSource?.name ?? L10n.text("导入音乐源")).font(.system(size: 11)).lineLimit(
              1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
          }.foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
          .help(model.sourceReady ? L10n.text("音乐源已启用 · 点击管理") : L10n.text("音乐源未就绪 · 点击查看详情"))
          .accessibilityLabel(model.sourceReady ? L10n.text("管理音乐源") : L10n.text("查看音乐源状态"))
      }.frame(minWidth: 200, idealWidth: 200)
        .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 260)
        .background(SidebarWidthAnchor())
        .background {
          SidebarArtworkBackdrop(state: backdrop).ignoresSafeArea(edges: .top)
        }
        .background(SidebarDividerCover(visible: !model.showNowPlaying))
        .toolbar(removing: .sidebarToggle)
    } detail: {
      VStack(spacing: 0) {
        ZStack {
          // Retain each visited catalog and its native scroll views across sidebar navigation.
          ForEach(navigation.visited.filter { $0.catalog != nil }) { location in
            if let kind = location.catalog {
              CatalogView(
                kind: kind, isActive: navigation.current == location && !model.showNowPlaying,
                searchFocusRequest: searchFocusRequest, initialCollection: location.collection,
                navigateCollection: { item in
                  navigation.visit(MusicLocation(section: kind.rawValue, collection: item))
                }
              )
              .modifier(
                RetainedPage(active: navigation.current == location, covered: model.showNowPlaying))
            }
          }
          ForEach(
            navigation.visited.filter { $0.catalog == nil && libraryPages.contains($0.section) }
          ) { location in
            libraryPage(location.section)
              .modifier(
                RetainedPage(active: navigation.current == location, covered: model.showNowPlaying))
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      .coordinateSpace(name: "musicDetail")
      .background(Color(nsColor: MusicSurface.content))
      .overlay(alignment: .top) {
        // Scope toolbar blur to this column; a window-wide material would also
        // paint over the sidebar's continuous background behind the controls.
        NavigationToolbarBackdrop()
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        PlayerBar().padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 18)
          .opacity(model.showNowPlaying ? 0 : 1)
          .allowsHitTesting(!model.showNowPlaying)
          .accessibilityHidden(model.showNowPlaying)
      }

    }
    .background(WindowChrome())
    .modifier(HideWindowToolbarTitle())
    .onChange(of: navigation.current) { _, _ in model.showNowPlaying = false }
    .onChange(of: model.state.playlists.map(\.id)) { _, _ in
      navigation.removeMissingLists(valid: Set(libraryPages))
    }
    .onReceive(NotificationCenter.default.publisher(for: .focusMusicSearch)) { _ in
      model.showNowPlaying = false
      section = "search"
      searchFocusRequest += 1
    }
    .onPreferenceChange(SidebarArtworkPreference.self) {
      if !model.showNowPlaying { backdrop.submit($0) }
    }
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button {
          columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        } label: {
          Image(systemName: "sidebar.left")
        }
        .help(columnVisibility == .detailOnly ? L10n.text("显示侧栏") : L10n.text("隐藏侧栏"))
        .accessibilityLabel(columnVisibility == .detailOnly ? L10n.text("显示侧栏") : L10n.text("隐藏侧栏"))
        .keyboardShortcut("s", modifiers: [.command, .control])
      }
      if !model.showNowPlaying {
        ToolbarItem(placement: .navigation) {
          HStack(spacing: 12) {
            Button {
              navigation.back()
            } label: {
              Image(systemName: "chevron.left").frame(width: 20, height: 28)
            }.disabled(!navigation.canGoBack)
              .help(L10n.text("后退")).accessibilityLabel(L10n.text("后退"))
              .keyboardShortcut("[", modifiers: .command)
            Button {
              navigation.forward()
            } label: {
              Image(systemName: "chevron.right").frame(width: 20, height: 28)
            }.disabled(!navigation.canGoForward)
              .help(L10n.text("前进")).accessibilityLabel(L10n.text("前进"))
              .keyboardShortcut("]", modifiers: .command)
            Text(pageTitle).lineLimit(1).truncationMode(.tail).frame(
              maxWidth: 240, alignment: .leading
            ).font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.secondary)
          }.fixedSize()
        }
      }
      if #available(macOS 26, *) {
        ToolbarSpacer(.flexible, placement: .primaryAction)
      } else {
        ToolbarItem(placement: .automatic) { Spacer() }
      }

    }
    .inspector(
      isPresented: Binding(
        get: { model.queueInspectorIsPresented }, set: { model.queueInspectorIsPresented = $0 })
    ) {
      QueueView(inPlayer: false)
        .allowsHitTesting(!model.showNowPlaying)
        .accessibilityHidden(model.showNowPlaying)
        .inspectorColumnWidth(min: 240, ideal: QueueWidthPreference.width(), max: 360)
        .background(QueueWidthMemory(active: model.showQueue && !model.showNowPlaying))
    }

    .alert(
      L10n.text("余音"),
      isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })
    ) {
      Button(L10n.text("好"), role: .cancel) { model.message = nil }
    } message: {
      Text(model.message ?? "")
    }
    .alert(L10n.text("新建列表"), isPresented: $showNewList) {
      TextField(L10n.text("列表名称"), text: $listName)
      Button(L10n.text("取消"), role: .cancel) {}
      Button(L10n.text("创建")) {
        let id = model.createPlaylist(listName)
        section = "list:\(id)"
      }
    }
  }
  private func sidebarHeader(_ title: String) -> some View {
    Text(title).font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.secondary).padding(.leading, 8)
  }

  private func sidebarItem(_ title: String, icon: String, id: String) -> some View {
    let selected = section == id
    return Button {
      section = id
    } label: {
      Label(title, systemImage: icon)
        .font(.system(size: 15))
        .fontWeight(selected ? .semibold : .regular)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).frame(height: 32)
        .background(
          selected ? Color(nsColor: MusicSurface.sidebarSelection) : .clear,
          in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2))
    .listRowBackground(Color.clear).listRowSeparator(.hidden)
  }

  private var libraryPages: [String] {
    ["sources", "downloads", "history"] + model.state.playlists.map { "list:\($0.id)" }
  }
  private var pageTitle: String {
    if let activeCatalog { return activeCatalog.title }
    switch section {
    case "sources": return L10n.text("音乐源")
    case "downloads": return L10n.text("下载")
    case "history": return L10n.text("最近播放")
    default:
      return model.state.playlists.first { "list:\($0.id)" == section }?.name ?? L10n.text("我的列表")
    }
  }
  @ViewBuilder private func libraryPage(_ page: String) -> some View {
    switch page {
    case "sources": SourcesView()
    case "downloads": DownloadsView()
    case "history": TrackLibraryView(tracks: model.state.history)
    default:
      if let list = model.state.playlists.first(where: { "list:\($0.id)" == page }) {
        PlaylistView(id: list.id)
      }
    }
  }
  private var activeCatalog: CatalogView.Kind? {
    switch section {
    case nil, "search": return .search
    case "playlists": return .playlists
    case "charts": return .charts
    default: return nil
    }
  }
}
struct Artwork: View {
  @Environment(\.locale) private var locale
  let url: String?
  var size: CGFloat = 48
  var radius: CGFloat = 8
  var body: some View {
    AsyncImage(url: URL(string: url ?? "")) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      ZStack {
        LinearGradient(
          colors: [Color.pink.opacity(0.18), Color.purple.opacity(0.16)], startPoint: .topLeading,
          endPoint: .bottomTrailing)
        Image(systemName: "music.note").font(.system(size: size * 0.32, weight: .medium))
          .foregroundStyle(.pink.opacity(0.7))
      }
    }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: radius))
      .accessibilityHidden(true)
  }
}
struct PageTitle: View {
  @Environment(\.locale) private var locale
  let title: String
  let subtitle: String
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.system(size: 22, weight: .semibold)).lineLimit(2)
      if !subtitle.isEmpty {
        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
