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
    // Keep the native split mounted under the full-window player. Collapsing it
    // during the fade reflows every catalog cover and moves the artwork anchor.
    get { showQueue }
    set {
      // Dismissing the native inspector on expansion must not close the player queue.
      if !showNowPlaying { showQueue = newValue }
    }
  }
  @Published var nowQuality = ""
  let catalog: MusicCatalog
  private let store: LibraryStore
  private var runtime: SourceRuntime?
  private var player: AVPlayer
  private let makePlayer: @MainActor () -> AVPlayer
  private var tailPlayer: AVPlayer?
  private var tailGain: Float = 0
  private var overlapDuration: Double = 0
  private var overlapStarted = false
  private let audioURLResolver: (@MainActor (Track, String) async throws -> URL)?
  private var playTask: Task<Void, Never>?
  private var artworkTask: Task<Void, Never>?
  private let systemNowPlaying = SystemNowPlaying()
  private var fadeTask: Task<Void, Never>?
  private let preparation = AudioPreparation()
  private var loadedEntryID: UUID?
  private var refreshedEntryID: UUID?
  private var audioGain: Float = 1
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
  init(
    store: LibraryStore = LibraryStore(), startServices: Bool = true,
    catalog: MusicCatalog = MusicCatalog(),
    player: AVPlayer = AVPlayer(),
    makePlayer: @escaping @MainActor () -> AVPlayer = { AVPlayer() },
    audioURLResolver: (@MainActor (Track, String) async throws -> URL)? = nil
  ) {
    self.store = store
    self.catalog = catalog
    self.player = player
    self.makePlayer = makePlayer
    self.audioURLResolver = audioURLResolver
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
    installPlaybackObservers()
    refreshCurrentArtwork()
    setupRemoteCommands()
    updateNowPlaying()
    Task { if let source = activeSource { await activate(source) } }
  }
  private func installPlaybackObservers() {
    guard playerObservation == nil else { return }
    let observedPlayer = player
    playerObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
      Task { @MainActor [weak self] in
        guard let self, p === self.player else { return }
        self.isPlaying = p.timeControlStatus == .playing
        if self.isPlaying, self.loadedEntryID == self.state.queue.currentID {
          self.isLoadingAudio = false
          if (self.tailPlayer != nil || self.audioGain < 1) && !self.overlapStarted {
            let token = self.playGeneration
            self.fadeTask?.cancel()
            self.fadeTask = Task { [weak self] in
              guard let self, !Task.isCancelled, token == self.playGeneration else { return }
              if self.tailPlayer != nil {
                self.overlapStarted = true
                try? await self.fadeOutgoing(token: token)
              } else {
                try? await self.fade(to: 1, steps: 12, token: token)
              }
            }
          }
          self.prepareUpcomingPlayback()
        } else if self.tailPlayer != nil && self.overlapStarted {
          self.fadeTask?.cancel()
          self.overlapStarted = false
        }
        self.updateNowPlaying()
      }
    }
    timeToken = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
    ) { [weak self] time in
      // This callback is explicitly delivered on the main queue. Handle it in
      // place so an outgoing item's queued tick cannot land on its replacement.
      MainActor.assumeIsolated {
        guard let self, self.player === observedPlayer,
          self.player.currentItem != nil, !self.isLoadingAudio,
          self.loadedEntryID == self.state.queue.currentID
        else { return }
        self.updatePlaybackTime(
          position: time.seconds,
          duration: self.player.currentItem?.duration.seconds ?? 0)
        if self.duration - self.position > 0, self.duration - self.position <= 15,
          self.refreshedEntryID != self.loadedEntryID
        {
          self.refreshedEntryID = self.loadedEntryID
          self.prepareUpcomingPlayback()
        }
        let remaining = self.duration - self.position
        if self.isPlaying, !self.overlapStarted, self.tailPlayer == nil,
          self.state.crossfadeSeconds > 0, remaining > 0,
          remaining <= min(self.state.crossfadeSeconds, self.duration / 2),
          self.state.queue.mode != .repeatOne,
          !self.state.queue.upcoming.isEmpty
        {
          self.next(automatic: true)
          return
        }
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
        guard let self, let item = n.object as? AVPlayerItem, item === self.player.currentItem,
          self.loadedEntryID == self.state.queue.currentID, !self.isLoadingAudio
        else { return }
        self.next(automatic: true)
      }
    }
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
    systemNowPlaying.cancel()
    stopAudio()
    removePlaybackObservers()
    downloadTasks.values.forEach { $0.cancel() }
    runtime?.stop()
    persist()
  }
  private func removePlaybackObservers() {
    if let timeToken {
      player.removeTimeObserver(timeToken)
      self.timeToken = nil
    }
    if let endToken {
      NotificationCenter.default.removeObserver(endToken)
      self.endToken = nil
    }
    playerObservation = nil
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
      preparation.cancel()
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
    preparation.cancel()
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
        preparation.cancel()
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
    guard let track = current, let entryID = state.queue.currentID else { return }
    installPlaybackObservers()
    playTask?.cancel()
    fadeTask?.cancel()
    // Rapid skips while the incoming player is still buffering keep the audible
    // tail; once the incoming track is audible it becomes the next outgoing one.
    if let tailPlayer, player.timeControlStatus != .playing,
      tailPlayer.timeControlStatus == .playing
    {
      removePlaybackObservers()
      player.pause()
      player.replaceCurrentItem(with: nil)
      player = tailPlayer
      audioGain = tailGain
      self.tailPlayer = nil
      installPlaybackObservers()
    } else {
      stopTail()
    }
    overlapStarted = false
    let wantsOverlap = state.crossfadeSeconds > 0 && player.timeControlStatus == .playing
    let token = UUID()
    playGeneration = token
    isLoadingAudio = true
    refreshCurrentArtwork()
    let resume = state.queue.position
    position = resume
    duration = track.duration
    persist()
    updateNowPlaying()
    // Keep the old song audible while preparing its replacement. A zero duration
    // switches directly; otherwise only the outgoing voice fades after handoff.
    playTask = Task { [self] in
      do {
        let audio = try await prepareAudio(track, entryID: entryID).value
        try Task.checkCancellation()
        guard token == playGeneration else { return }
        let item = AVPlayerItem(asset: audio.asset)
        item.preferredForwardBufferDuration = 3
        if wantsOverlap, player.timeControlStatus == .playing {
          tailPlayer = player
          tailGain = audioGain
          let remaining = player.currentItem.map {
            $0.duration.seconds - player.currentTime().seconds
          }
          overlapDuration = min(
            state.crossfadeSeconds,
            remaining.map { $0.isFinite && $0 > 0 ? $0 : state.crossfadeSeconds }
              ?? state.crossfadeSeconds)
          removePlaybackObservers()
          player = makePlayer()
          audioGain = 1
          player.volume = state.volume
          installPlaybackObservers()
        } else {
          player.pause()
          audioGain = 1
          player.volume = state.volume
        }
        loadedEntryID = entryID
        refreshedEntryID = nil
        nowQuality = audio.quality
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
          Task { @MainActor [weak self] in
            guard let self, item === self.player.currentItem,
              self.loadedEntryID == self.state.queue.currentID
            else { return }
            if item.status == .failed {
              let error = item.error?.localizedDescription ?? L10n.text("播放失败，请重试")
              self.stopAudio()
              self.message = error
            }
          }
        }
        player.replaceCurrentItem(with: item)
        let resume = state.queue.position
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
        prepareUpcomingPlayback()
      } catch {
        if token == playGeneration {
          stopAudio()
          notify(error)
        }
      }
    }
  }

  private func prepareAudio(_ track: Track, entryID: UUID) throws -> Task<
    AudioPreparation.Audio, Error
  > {
    let file = offlineURL(track)
    let quality: String
    if file != nil {
      quality = L10n.text("本地")
    } else {
      guard sourceReady else { throw MusicError.message(L10n.text("请先在音乐源页面导入并启用音乐源")) }
      let supported = qualities(for: track)
      guard
        let selected = supported.contains(state.playbackQuality)
          ? state.playbackQuality
          : supported.contains("128k") ? "128k" : supported.first
      else {
        throw MusicError.message(L10n.text("当前音乐源不支持\(track.platform.name)，请在音乐源页面启用或切换源"))
      }
      quality = selected
    }
    let key = AudioPreparation.Key(
      entry: entryID, source: sourceGeneration, quality: quality, file: file)
    return preparation.prepare(key) { [weak self] in
      if let file { return file }
      guard let self else { throw CancellationError() }
      return try await self.resolve(track, quality: quality)
    }
  }

  func prepareUpcomingPlayback() {
    guard !isLoadingAudio, loadedEntryID == state.queue.currentID, player.currentItem != nil else {
      return
    }
    var queue = state.queue
    // Do not predict a random choice or consume an explicit play-next priority.
    guard queue.mode != .shuffle || queue.nextEntryID != nil,
      queue.advance(automatic: true), let track = queue.current, let id = queue.currentID
    else {
      preparation.cancel()
      return
    }
    _ = try? prepareAudio(track, entryID: id)
  }

  private func fade(to target: Float, steps: Int, token: UUID) async throws {
    let initial = audioGain
    for step in 1...steps {
      try Task.checkCancellation()
      guard token == playGeneration else { throw CancellationError() }
      audioGain = initial + (target - initial) * Float(step) / Float(steps)
      player.volume = state.volume * audioGain
      try await Task.sleep(for: .milliseconds(16))
    }
  }

  private func fadeOutgoing(token: UUID) async throws {
    let initialTail = tailGain
    let start = ContinuousClock.now
    // Buffering can consume part of the tail after the new item was attached.
    // Measure again when it actually becomes audible, not when play() was called.
    let remaining = tailPlayer.flatMap { tail in
      tail.currentItem.map { $0.duration.seconds - tail.currentTime().seconds }
    }
    let available =
      remaining.map { $0.isFinite ? max(0, $0) : overlapDuration }
      ?? overlapDuration
    let seconds = max(0.016, min(overlapDuration, available))
    while true {
      try Task.checkCancellation()
      guard token == playGeneration else { throw CancellationError() }
      let elapsed = start.duration(to: .now).components
      let progress = min(
        1, (Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18) / seconds)
      // The new song starts at normal volume. Only the previous voice fades.
      tailGain = initialTail * Float(cos(progress * .pi / 2))
      tailPlayer?.volume = state.volume * tailGain
      if progress >= 1 { break }
      try await Task.sleep(for: .milliseconds(16))
    }
    stopTail()
  }

  private func stopTail() {
    tailPlayer?.pause()
    tailPlayer?.replaceCurrentItem(with: nil)
    tailPlayer = nil
    tailGain = 0
    overlapStarted = false
  }

  private func stopAudio() {
    artworkTask?.cancel()
    playTask?.cancel()
    fadeTask?.cancel()
    stopTail()
    preparation.cancel()
    playGeneration = UUID()
    isLoadingAudio = false
    isPlaying = false
    player.pause()
    itemObservation = nil
    player.replaceCurrentItem(with: nil)
    loadedEntryID = nil
    audioGain = 1
    player.volume = state.volume
  }

  func refreshCurrentArtwork() {
    artworkTask?.cancel()
    guard let track = current, track.platform == .wy, track.artwork?.isEmpty != false else {
      return
    }
    artworkTask = Task { [weak self, catalog] in
      guard let enriched = try? await catalog.fillingMissingArtwork(in: [track]).first,
        !Task.isCancelled, let artwork = enriched.artwork, !artwork.isEmpty,
        let self, self.current?.id == track.id
      else { return }
      // Repair the old copies without replacing queue entries or resetting time.
      var updated = self.state
      func repair(_ song: inout Track) {
        if song.id == track.id, song.artwork?.isEmpty != false { song.artwork = artwork }
      }
      for index in updated.queue.entries.indices { repair(&updated.queue.entries[index].track) }
      for index in updated.history.indices { repair(&updated.history[index]) }
      for list in updated.playlists.indices {
        for index in updated.playlists[list].tracks.indices {
          repair(&updated.playlists[list].tracks[index])
        }
      }
      for index in updated.downloads.indices { repair(&updated.downloads[index].track) }
      self.state = updated
      self.persist()
      self.updateNowPlaying()
    }
  }

  func pausePlayback() {
    if isLoadingAudio {
      stopAudio()
    } else {
      fadeTask?.cancel()
      stopTail()
      player.pause()
      isPlaying = false
      audioGain = 1
      player.volume = state.volume
    }
    persist()
    updateNowPlaying()
  }
  func resolve(_ track: Track, quality: String) async throws -> URL {
    if let audioURLResolver { return try await audioURLResolver(track, quality) }
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
      pausePlayback()
      return
    }
    if isPlaying || player.rate > 0 {
      pausePlayback()
    } else if player.currentItem != nil && player.currentItem?.status != .failed,
      loadedEntryID == state.queue.currentID
    {
      isLoadingAudio = true
      audioGain = 0
      player.volume = 0
      player.play()
    } else {
      startCurrent()
    }
  }
  func next(backward: Bool = false, automatic: Bool = false) {
    guard state.queue.advance(backward: backward, automatic: automatic) else {
      if automatic {
        stopAudio()
        state.queue.position = 0
        position = 0
        persist()
      }
      return
    }
    startCurrent()
  }
  func seek(_ seconds: Double) {
    if tailPlayer != nil {
      fadeTask?.cancel()
      stopTail()
      audioGain = 1
      player.volume = state.volume
    }
    let value = min(max(0, seconds), max(duration, 0))
    position = value
    state.queue.position = value
    if player.currentItem != nil, loadedEntryID == state.queue.currentID {
      player.seek(to: CMTime(seconds: value, preferredTimescale: 600))
    }
    persist()
    updateNowPlaying()
  }
  func setVolume(_ value: Float) {
    state.volume = value
    player.volume = value * audioGain
    tailPlayer?.volume = value * tailGain
    persist()
  }
  func enqueue(_ track: Track, next: Bool) {
    state.queue.append(track, next: next)
    persist()
    prepareUpcomingPlayback()
  }
  func enqueue(_ tracks: [Track], next: Bool) {
    guard !tracks.isEmpty else { return }
    state.queue.append(contentsOf: tracks, next: next)
    persist()
    prepareUpcomingPlayback()
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
    prepareUpcomingPlayback()
  }
  func playNext(_ id: UUID) {
    state.queue.playNext(id)
    persist()
    prepareUpcomingPlayback()
  }
  func clearUpcoming() {
    state.queue.clearUpcoming()
    persist()
    prepareUpcomingPlayback()
  }
  func removeQueue(_ id: UUID) {
    let current = state.queue.currentID == id
    if current {
      stopAudio()
    }
    state.queue.remove(id)
    if current {
      position = 0
      duration = self.current?.duration ?? 0
      updateNowPlaying()
    }
    persist()
    prepareUpcomingPlayback()
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
      stopAudio()
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
        if !self.isPlaying && !self.isLoadingAudio { self.togglePlayback() }
      }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.pausePlayback()
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
    systemNowPlaying.update(
      track: current, position: position, duration: duration, isPlaying: isPlaying)
  }
}

@MainActor final class PlaybackClock: ObservableObject {
  @Published var position: Double = 0
  @Published var duration: Double = 0
}
