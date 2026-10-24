import AVFoundation
import AppKit
import MediaPlayer
import MusicCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class AppModel: ObservableObject {
  private var storedState = LibraryState()
  var state: LibraryState {
    get { storedState }
    set {
      objectWillChange.send()
      storedState = newValue
    }
  }
  @Published var message: String?
  @Published var sourceBusy = false
  @Published var sourceReady = false
  @Published var sourceIssue: String?
  @Published var capabilities: [String: SourceCapability] = [:]
  @Published var isPlaying = false
  @Published var isLoadingAudio = false
  let clock = PlaybackClock()
  var position: Double {
    get { clock.position }
    set { if clock.position != newValue { clock.position = newValue } }
  }
  var duration: Double {
    get { clock.duration }
    set { if clock.duration != newValue { clock.duration = newValue } }
  }
  @Published var showQueue = false
  @Published var showNowPlaying = false
  @Published var showLyrics = true
  var queueInspectorIsPresented: Bool {
    get { showQueue && !showNowPlaying }
    set {
      // Dismissing the native inspector on expansion must not close the player queue.
      if !showNowPlaying { showQueue = newValue }
    }
  }
  @Published var nowQuality = ""
  let catalog = MusicCatalog()
  private let store: LibraryStore
  private var runtime: SourceRuntime?
  private let player = AVPlayer()
  private var playTask: Task<Void, Never>?
  private var playGeneration = UUID()
  private var sourceGeneration = UUID()
  private var playerObservation: NSKeyValueObservation?
  private var itemObservation: NSKeyValueObservation?
  private var timeToken: Any?
  private var endToken: NSObjectProtocol?
  private var lastPersist = Date.distantPast
  private var saveAllowed = true
  private var downloadTasks: [UUID: Task<Void, Never>] = [:]
  private var restoring = false
  var current: Track? { state.queue.current }
  var activeSource: SourceRecord? { state.sources.first { $0.id == state.activeSourceID } }
  init(store: LibraryStore = LibraryStore(), startServices: Bool = true) {
    self.store = store
    do { state = try store.load() } catch {
      state = LibraryState()
      saveAllowed = false
      message = L10n.text("本地数据读取失败，原文件已保留。请从设置恢复有效备份。\n\(error.localizedDescription)")
    }
    position = state.queue.position
    duration = state.queue.current?.duration ?? 0
    player.volume = state.volume
    // Rendering/scroll benchmarks use an isolated store without audio or remote commands.
    guard startServices else { return }
    playerObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
      Task { @MainActor [weak self] in
        self?.isPlaying = p.timeControlStatus == .playing
        self?.updateNowPlaying()
      }
    }
    timeToken = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
    ) { [weak self] time in
      Task { @MainActor [weak self] in
        guard let self, self.player.currentItem != nil else { return }
        self.updatePlaybackTime(
          position: time.seconds,
          duration: self.player.currentItem?.duration.seconds ?? 0)
        if Date().timeIntervalSince(self.lastPersist) > 5 {
          self.persist()
          self.lastPersist = Date()
          self.updateNowPlaying()
        }
      }
    }
    endToken = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
    ) { [weak self] n in
      Task { @MainActor [weak self] in
        guard let self, let item = n.object as? AVPlayerItem, item === self.player.currentItem
        else { return }
        self.next(automatic: true)
      }
    }
    setupRemoteCommands()
    Task { if let source = activeSource { await activate(source) } }
  }
  func updatePlaybackTime(position: Double, duration: Double) {
    if position.isFinite {
      self.position = position
      // The queue still retains its latest resume position, without broadcasting
      // a library change to every retained catalog on each audio timer tick.
      storedState.queue.position = position
    }
    if duration.isFinite && duration > 0 { self.duration = duration }
  }
  func persist() {
    guard saveAllowed else { return }
    do { try store.save(state) } catch { message = L10n.text("保存失败：\(error.localizedDescription)") }
  }
  func shutdown() {
    player.pause()
    playTask?.cancel()
    downloadTasks.values.forEach { $0.cancel() }
    runtime?.stop()
    persist()
  }
  func notify(_ error: Error) {
    if !(error is CancellationError) { message = error.localizedDescription }
  }
  func qualities(for track: Track) -> [String] {
    capabilities[track.platform.rawValue]?.qualitys ?? []
  }
  func activate(_ source: SourceRecord) async {
    guard !sourceBusy else { return }
    sourceBusy = true
    defer { sourceBusy = false }
    let token = UUID()
    sourceGeneration = token
    let candidate = SourceRuntime()
    candidate.onUpdate = { [weak self] text in self?.message = L10n.text("音乐源更新提示：\(text)") }
    do {
      try await candidate.start(source)
      guard sourceGeneration == token else {
        candidate.stop()
        return
      }
      runtime?.stop()
      runtime = candidate
      capabilities = candidate.capabilities
      sourceReady = true
      sourceIssue = nil
      state.activeSourceID = source.id
      persist()
    } catch {
      candidate.stop()
      sourceIssue = "\(source.name)：\(error.localizedDescription)"
      notify(error)
    }
  }
  func disableSource() {
    sourceGeneration = UUID()
    runtime?.stop()
    runtime = nil
    sourceReady = false
    sourceIssue = nil
    capabilities = [:]
    state.activeSourceID = nil
    persist()
  }
  func importLocal() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.javaScript]
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }
    for url in panel.urls {
      do { state.sources.append(try SourceImport.local(url)) } catch { notify(error) }
    }
    persist()
  }
  func importOnline(_ link: String) async {
    guard !sourceBusy else { return }
    sourceBusy = true
    defer { sourceBusy = false }
    do {
      state.sources.append(try await SourceImport.online(link))
      persist()
    } catch { notify(error) }
  }
  func updateSource(_ source: SourceRecord) async {
    guard let origin = source.origin, !sourceBusy else { return }
    sourceBusy = true
    defer { sourceBusy = false }
    let token = UUID()
    sourceGeneration = token
    let candidate = SourceRuntime()
    do {
      var update = try await SourceImport.online(origin)
      update.id = source.id
      try await candidate.start(update)
      guard sourceGeneration == token,
        let index = state.sources.firstIndex(where: { $0.id == source.id })
      else {
        candidate.stop()
        return
      }
      if state.activeSourceID == source.id {
        runtime?.stop()
        runtime = candidate
        capabilities = candidate.capabilities
        sourceReady = true
        candidate.onUpdate = { [weak self] in self?.message = $0 }
      } else {
        candidate.stop()
      }
      state.sources[index] = update
      persist()
      message = L10n.text("音乐源已更新并通过初始化验证")
    } catch {
      candidate.stop()
      notify(error)
    }
  }
  func deleteSource(_ source: SourceRecord) {
    if source.id == state.activeSourceID { disableSource() }
    state.sources.removeAll { $0.id == source.id }
    persist()
  }
  func play(_ track: Track, in tracks: [Track]? = nil) {
    if let tracks, let index = tracks.firstIndex(where: { $0.id == track.id }) {
      state.queue.replace(tracks, start: index)
    } else {
      state.queue.replace([track], start: 0)
    }
    position = 0
    startCurrent()
  }
  func startCurrent() {
    guard let track = current else { return }
    playTask?.cancel()
    let token = UUID()
    playGeneration = token
    player.pause()
    itemObservation = nil
    player.replaceCurrentItem(with: nil)
    isPlaying = false
    isLoadingAudio = true
    let resume = state.queue.position
    position = resume
    duration = track.duration
    persist()
    playTask = Task { [self] in
      defer { if token == playGeneration { isLoadingAudio = false } }
      do {
        let url: URL
        if let file = offlineURL(track) {
          url = file
          nowQuality = L10n.text("本地")
        } else {
          guard sourceReady else { throw MusicError.message(L10n.text("请先在音乐源页面导入并启用音乐源")) }
          let q = qualities(for: track)
          let quality: String?
          if q.contains(state.playbackQuality) {
            quality = state.playbackQuality
          } else if q.contains("128k") {
            quality = "128k"
          } else {
            quality = q.first
          }
          guard let quality else {
            throw MusicError.message(L10n.text("当前音乐源不支持\(track.platform.name)，请在音乐源页面启用或切换源"))
          }
          url = try await resolve(track, quality: quality)
          nowQuality = quality
        }
        try Task.checkCancellation()
        guard token == playGeneration else { return }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else {
          throw MusicError.message(L10n.text("当前系统无法播放此音频格式"))
        }
        try Task.checkCancellation()
        guard token == playGeneration else { return }
        let item = AVPlayerItem(asset: asset)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
          Task { @MainActor [weak self] in
            guard let self, item === self.player.currentItem else { return }
            if item.status == .failed {
              self.message = item.error?.localizedDescription ?? L10n.text("播放失败，请重试")
              self.isPlaying = false
            }
          }
        }
        player.replaceCurrentItem(with: item)
        if resume > 0 {
          await player.seek(
            to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero,
            toleranceAfter: .zero)
        }
        try Task.checkCancellation()
        guard token == playGeneration else { return }
        player.play()
        state.history.removeAll { $0.id == track.id }
        state.history.insert(track, at: 0)
        state.history = Array(state.history.prefix(200))
        persist()
        updateNowPlaying()
      } catch { if token == playGeneration { notify(error) } }
    }
  }
  func resolve(_ track: Track, quality: String) async throws -> URL {
    guard let runtime, sourceReady else { throw MusicError.message(L10n.text("请先导入并启用音乐源")) }
    do { return try await runtime.resolve(track, quality: quality) } catch {
      if runtime.capabilities.isEmpty {
        sourceReady = false
        sourceIssue = error.localizedDescription
        capabilities = [:]
      }
      throw error
    }
  }
  func togglePlayback() {
    if isLoadingAudio {
      playTask?.cancel()
      playGeneration = UUID()
      isLoadingAudio = false
      return
    }
    if isPlaying {
      player.pause()
      persist()
    } else if player.currentItem != nil && player.currentItem?.status != .failed {
      player.play()
    } else {
      startCurrent()
    }
  }
  func next(backward: Bool = false, automatic: Bool = false) {
    guard state.queue.advance(backward: backward, automatic: automatic) else {
      if automatic {
        player.pause()
        state.queue.position = 0
        position = 0
        player.replaceCurrentItem(with: nil)
        persist()
      }
      return
    }
    startCurrent()
  }
  func seek(_ seconds: Double) {
    let value = min(max(0, seconds), max(duration, 0))
    position = value
    state.queue.position = value
    if player.currentItem != nil {
      player.seek(to: CMTime(seconds: value, preferredTimescale: 600))
    }
    persist()
    updateNowPlaying()
  }
  func setVolume(_ value: Float) {
    state.volume = value
    player.volume = value
    persist()
  }
  func enqueue(_ track: Track, next: Bool) {
    state.queue.append(track, next: next)
    persist()
  }
  func enqueue(_ tracks: [Track], next: Bool) {
    guard !tracks.isEmpty else { return }
    state.queue.append(contentsOf: tracks, next: next)
    persist()
  }
  func selectQueue(_ id: UUID) {
    guard state.queue.entries.contains(where: { $0.id == id }) else { return }
    state.queue.nextEntryID = nil
    state.queue.currentID = id
    state.queue.position = 0
    startCurrent()
  }
  func moveUpcoming(from offsets: IndexSet, to destination: Int) {
    state.queue.moveUpcoming(from: offsets, to: destination)
    persist()
  }
  func playNext(_ id: UUID) {
    state.queue.playNext(id)
    persist()
  }
  func clearUpcoming() {
    state.queue.clearUpcoming()
    persist()
  }
  func removeQueue(_ id: UUID) {
    let current = state.queue.currentID == id
    if current {
      playTask?.cancel()
      playGeneration = UUID()
      isLoadingAudio = false
      player.pause()
      player.replaceCurrentItem(with: nil)
    }
    state.queue.remove(id)
    if current {
      position = 0
      duration = self.current?.duration ?? 0
      updateNowPlaying()
    }
    persist()
  }
  func offlineURL(_ track: Track) -> URL? {
    for job in state.downloads.reversed()
    where job.track.id == track.id && [.completed, .skipped].contains(job.status) {
      if let file = job.file, FileManager.default.fileExists(atPath: file) {
        return URL(fileURLWithPath: file)
      }
    }
    return nil
  }
  func add(_ tracks: [Track], to id: UUID) {
    guard let index = state.playlists.firstIndex(where: { $0.id == id }) else { return }
    var seen = Set(state.playlists[index].tracks.map(\.id))
    state.playlists[index].tracks += tracks.filter { seen.insert($0.id).inserted }
    persist()
  }
  @discardableResult func createPlaylist(_ name: String, tracks: [Track] = []) -> UUID {
    let playlist = LocalPlaylist(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? L10n.text("未命名列表") : name,
      tracks: tracks)
    state.playlists.append(playlist)
    persist()
    return playlist.id
  }
  func favorite(_ track: Track) {
    if state.playlists.isEmpty { createPlaylist(L10n.text("我喜欢的音乐")) }
    add([track], to: state.playlists[0].id)
  }
  func chooseDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    if panel.runModal() == .OK, let url = panel.url {
      state.downloadDirectory = url.path
      persist()
    }
  }
  func enqueueDownloads(_ tracks: [Track], quality: String) {
    var unsupported = 0
    for track in tracks {
      guard qualities(for: track).contains(quality) else {
        unsupported += 1
        continue
      }
      guard
        !state.downloads.contains(where: {
          $0.track.id == track.id && $0.quality == quality
            && [.queued, .resolving, .downloading].contains($0.status)
        })
      else { continue }
      state.downloads.append(
        DownloadJob(track: track, quality: quality, directory: state.downloadDirectory))
    }
    if unsupported > 0 { message = L10n.text("\(unsupported) 首歌曲的当前平台不支持所选音质，未加入下载") }
    persist()
    pumpDownloads()
  }
  func retryDownload(_ id: UUID) {
    guard let i = state.downloads.firstIndex(where: { $0.id == id }), downloadTasks[id] == nil
    else { return }
    state.downloads[i].status = .queued
    state.downloads[i].error = nil
    state.downloads[i].progress = 0
    pumpDownloads()
  }
  func cancelDownload(_ id: UUID) {
    downloadTasks[id]?.cancel()
    if let i = state.downloads.firstIndex(where: { $0.id == id }) {
      state.downloads[i].status = .cancelled
      state.downloads[i].error = nil
    }
    persist()
  }
  private func changeJob(_ id: UUID, _ change: (inout DownloadJob) -> Void) {
    if let i = state.downloads.firstIndex(where: { $0.id == id }) { change(&state.downloads[i]) }
  }
  private func pumpDownloads() {
    guard !restoring else { return }
    while downloadTasks.count < 2,
      let job = state.downloads.first(where: { $0.status == .queued && downloadTasks[$0.id] == nil }
      )
    {
      changeJob(job.id) { $0.status = .resolving }
      downloadTasks[job.id] = Task { [self] in
        defer {
          downloadTasks.removeValue(forKey: job.id)
          persist()
          pumpDownloads()
        }
        do {
          let url = try await resolve(job.track, quality: job.quality)
          try Task.checkCancellation()
          changeJob(job.id) { $0.status = .downloading }
          let result = try await DownloadService.download(
            url, track: job.track, quality: job.quality,
            directory: URL(fileURLWithPath: job.directory)
          ) { [weak self] progress in
            Task { @MainActor [weak self] in
              self?.changeJob(job.id) { if $0.status == .downloading { $0.progress = progress } }
            }
          }
          // Once a complete file has been committed, retain it even if cancellation arrives simultaneously.
          changeJob(job.id) {
            $0.file = result.url.path
            $0.progress = 1
            $0.status = result.skipped ? .skipped : .completed
            $0.error = nil
          }
        } catch {
          let cancelled =
            Task.isCancelled || error is CancellationError
            || (error as? URLError)?.code == .cancelled
          changeJob(job.id) {
            $0.status = cancelled ? .cancelled : .failed
            $0.error = cancelled ? nil : error.localizedDescription
          }
        }
      }
    }
  }
  func exportBackup() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Yuin-backup.json"
    panel.allowedContentTypes = [.json]
    if panel.runModal() == .OK, let url = panel.url {
      do { try store.export(state, to: url) } catch { notify(error) }
    }
  }
  func restoreBackup() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let restored = try store.decode(Data(contentsOf: url))
      let alert = NSAlert()
      alert.messageText = L10n.text("恢复备份并替换当前资料？")
      alert.informativeText = L10n.text("当前资料会先保存到应用数据目录的恢复前备份。音频文件不会删除。")
      alert.addButton(withTitle: L10n.text("恢复"))
      alert.addButton(withTitle: L10n.text("取消"))
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      if saveAllowed {
        try store.export(
          state,
          to: store.url.deletingLastPathComponent().appendingPathComponent(
            "before-restore-\(Int(Date().timeIntervalSince1970)).json"))
      }
      restoring = true
      playTask?.cancel()
      playGeneration = UUID()
      isLoadingAudio = false
      player.pause()
      player.replaceCurrentItem(with: nil)
      downloadTasks.values.forEach { $0.cancel() }
      let tasks = Array(downloadTasks.values)
      Task {
        for task in tasks { await task.value }
        disableSource()
        state = restored
        state.activeSourceID = nil
        saveAllowed = true
        position = state.queue.position
        duration = current?.duration ?? 0
        player.volume = state.volume
        restoring = false
        persist()
        updateNowPlaying()
        // Restored scripts remain inactive until the user explicitly enables one.
        state.activeSourceID = nil
        persist()
        message = L10n.text("备份已恢复，请在音乐源页面手动启用所需源")
      }
    } catch { notify(error) }
  }
  private func setupRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if !self.isPlaying { self.togglePlayback() }
      }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.player.pause()
        self?.persist()
      }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      Task { @MainActor [weak self] in self?.togglePlayback() }
      return .success
    }
    center.nextTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor [weak self] in self?.next() }
      return .success
    }
    center.previousTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor [weak self] in self?.next(backward: true) }
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      Task { @MainActor [weak self] in self?.seek(e.positionTime) }
      return .success
    }
  }
  private func updateNowPlaying() {
    guard let track = current else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
      MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
    ]
    MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
  }
}

@MainActor final class PlaybackClock: ObservableObject {
  @Published var position: Double = 0
  @Published var duration: Double = 0
}
