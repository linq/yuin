import Foundation

public struct LibraryStore {
  public let url: URL
  public init(url: URL? = nil) {
    self.url =
      url
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MyMusic/library.json")
  }
  public func load() throws -> LibraryState {
    guard FileManager.default.fileExists(atPath: url.path) else { return LibraryState() }
    return try decode(Data(contentsOf: url))
  }
  public func decode(_ data: Data) throws -> LibraryState {
    var state = try JSONDecoder().decode(LibraryState.self, from: data)
    guard state.schema == 1 else { throw MusicError.message(L10n.text("不支持此备份版本")) }
    guard Set(state.playlists.map(\.id)).count == state.playlists.count,
      Set(state.sources.map(\.id)).count == state.sources.count,
      Set(state.downloads.map(\.id)).count == state.downloads.count,
      Set(state.queue.entries.map(\.id)).count == state.queue.entries.count
    else { throw MusicError.message(L10n.text("备份包含重复标识，无法恢复")) }
    if !state.queue.entries.contains(where: { $0.id == state.queue.currentID }) {
      state.queue.currentID = state.queue.entries.first?.id
      state.queue.position = 0
    }
    state.queue.position = max(0, state.queue.position)
    if !state.sources.contains(where: { $0.id == state.activeSourceID }) {
      state.activeSourceID = nil
    }
    state.volume = min(1, max(0, state.volume))
    for i in state.downloads.indices
    where [.resolving, .downloading, .queued].contains(state.downloads[i].status) {
      state.downloads[i].status = .failed
      state.downloads[i].error = L10n.text("任务因应用关闭中断，请重试")
    }
    return state
  }
  public func save(_ state: LibraryState) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoded(state).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
  public func encoded(_ state: LibraryState) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(state)
  }
  public func export(_ state: LibraryState, to destination: URL) throws {
    try encoded(state).write(to: destination, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: destination.path)
  }
}
public enum DownloadFiles {
  public static func filename(track: Track, quality: String, extension ext: String) -> String {
    let forbidden = CharacterSet(charactersIn: "/\\:\n\r\0").union(.controlCharacters)
    func clean(_ s: String) -> String {
      String(s.components(separatedBy: forbidden).joined(separator: "_").prefix(100))
    }
    return
      "\(clean(track.artist)) - \(clean(track.title)) [\(clean(track.id))_\(clean(quality))].\(clean(ext))"
  }
}
