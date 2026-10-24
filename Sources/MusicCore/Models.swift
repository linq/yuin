import Foundation

public enum MusicPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
  case kw, kg, tx, wy, mg
  public var id: String { rawValue }
  public var name: String {
    switch self {
    case .kw: return L10n.text("酷我")
    case .kg: return L10n.text("酷狗")
    case .tx: return L10n.text("QQ 音乐")
    case .wy: return L10n.text("网易云")
    case .mg: return L10n.text("咪咕")
    }
  }
}
public enum JSONValue: Codable, Equatable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null
  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let x = try? c.decode(Bool.self) {
      self = .bool(x)
    } else if let x = try? c.decode(Double.self) {
      self = .number(x)
    } else if let x = try? c.decode(String.self) {
      self = .string(x)
    } else if let x = try? c.decode([String: JSONValue].self) {
      self = .object(x)
    } else {
      self = .array(try c.decode([JSONValue].self))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let x): try c.encode(x)
    case .number(let x): try c.encode(x)
    case .string(let x): try c.encode(x)
    case .object(let x): try c.encode(x)
    case .array(let x): try c.encode(x)
    }
  }
}
public struct Track: Codable, Identifiable, Equatable, Sendable {
  public var id: String { "\(platform.rawValue):\(songID)" }
  public var platform: MusicPlatform
  public var songID: String
  public var title: String
  public var artist: String
  public var album: String
  public var duration: Double
  public var artwork: String?
  public var sourceInfo: [String: JSONValue]
  public init(
    platform: MusicPlatform, songID: String, title: String, artist: String, album: String = "",
    duration: Double = 0, artwork: String? = nil, sourceInfo: [String: JSONValue] = [:]
  ) {
    self.platform = platform
    self.songID = songID
    self.title = title
    self.artist = artist
    self.album = album
    self.duration = duration
    self.artwork = artwork
    self.sourceInfo = sourceInfo
  }
  public var lxInfo: [String: JSONValue] {
    var info = sourceInfo
    info["name"] = .string(title)
    info["singer"] = .string(artist)
    info["source"] = .string(platform.rawValue)
    if info["songmid"] == nil { info["songmid"] = .string(songID) }
    info["albumName"] = .string(album)
    info["interval"] = .string(Self.time(duration))
    info["img"] = .string(artwork ?? "")
    if info["albumId"] == nil { info["albumId"] = .string("") }
    if info["types"] == nil { info["types"] = .array([]) }
    if info["_types"] == nil { info["_types"] = .object([:]) }
    info["typeUrl"] = .object([:])
    return info
  }
  public static func time(_ value: Double) -> String {
    let n = value.isFinite ? max(0, Int(value)) : 0
    return String(format: "%d:%02d", n / 60, n % 60)
  }
}
public struct MusicCollection: Identifiable, Sendable {
  public let id: String
  public let title: String
  public let subtitle: String
  public let artwork: String?
  public let platform: MusicPlatform
  public let isChart: Bool
  public init(
    id: String, title: String, subtitle: String = "", artwork: String? = nil,
    platform: MusicPlatform, isChart: Bool = false
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.artwork = artwork
    self.platform = platform
    self.isChart = isChart
  }
}
public struct TrackPage: Sendable {
  public var tracks: [Track]
  public var total: Int
}
public struct CollectionPage: Sendable {
  public var collections: [MusicCollection]
  public var total: Int
}
public struct LocalPlaylist: Codable, Identifiable, Equatable {
  public var id: UUID = UUID()
  public var name: String
  public var tracks: [Track] = []
  public init(name: String, tracks: [Track] = []) {
    self.name = name
    var seen = Set<String>()
    self.tracks = tracks.filter { seen.insert($0.id).inserted }
  }
}
public struct QueueEntry: Codable, Identifiable, Equatable {
  public var id: UUID = UUID()
  public var track: Track
  public init(track: Track) { self.track = track }
}
public enum PlaybackMode: String, Codable, CaseIterable {
  case sequential, shuffle, repeatOne
  public var name: String {
    switch self {
    case .sequential: return L10n.text("顺序播放")
    case .shuffle: return L10n.text("随机播放")
    case .repeatOne: return L10n.text("单曲循环")
    }
  }
  public var symbol: String {
    switch self {
    case .sequential: return "repeat"
    case .shuffle: return "shuffle"
    case .repeatOne: return "repeat.1"
    }
  }
}
public struct PlaybackQueue: Codable, Equatable {
  public var entries: [QueueEntry] = []
  public var currentID: UUID?
  public var position: Double = 0
  public var mode: PlaybackMode = .sequential
  public var nextEntryID: UUID?
  public init() {}
  public var index: Int? { entries.firstIndex { $0.id == currentID } }
  public var current: Track? { index.map { entries[$0].track } }
  public mutating func replace(_ tracks: [Track], start: Int) {
    nextEntryID = nil
    entries = tracks.map { QueueEntry(track: $0) }
    currentID = entries.indices.contains(start) ? entries[start].id : nil
    position = 0
  }
  public mutating func append(_ track: Track, next: Bool) {
    let entry = QueueEntry(track: track)
    if next, let index {
      entries.insert(entry, at: index + 1)
      nextEntryID = entry.id
    } else {
      entries.append(entry)
    }
    if currentID == nil { currentID = entry.id }
  }
  public mutating func append(contentsOf tracks: [Track], next: Bool) {
    let additions = tracks.map { QueueEntry(track: $0) }
    guard let first = additions.first else { return }
    if next, let index {
      entries.insert(contentsOf: additions, at: index + 1)
      nextEntryID = first.id
    } else {
      entries.append(contentsOf: additions)
    }
    if currentID == nil { currentID = first.id }
  }
  public var upcoming: [QueueEntry] {
    if mode == .shuffle { return entries.filter { $0.id != currentID } }
    guard let index else { return entries }
    return Array(entries.dropFirst(index + 1))
  }
  /// Reorder only pending entries; current identity and playback position stay untouched.
  public mutating func moveUpcoming(from offsets: IndexSet, to destination: Int) {
    var pending = upcoming
    guard destination >= 0, destination <= pending.count,
      !offsets.isEmpty,
      offsets.allSatisfy({ pending.indices.contains($0) })
    else { return }
    nextEntryID = nil
    let moved = offsets.sorted().map { pending[$0] }
    for offset in offsets.sorted(by: >) { pending.remove(at: offset) }
    pending.insert(contentsOf: moved, at: destination - offsets.filter { $0 < destination }.count)
    if mode == .shuffle, let index {
      let current = entries[index]
      entries = pending
      entries.insert(current, at: min(index, pending.count))
    } else {
      entries = Array(entries.prefix((index ?? -1) + 1)) + pending
    }
  }
  public mutating func playNext(_ id: UUID) {
    guard id != currentID, let old = entries.firstIndex(where: { $0.id == id }) else { return }
    let entry = entries.remove(at: old)
    entries.insert(entry, at: (index ?? -1) + 1)
    nextEntryID = id
  }
  public mutating func clearUpcoming() {
    // Playback history lives in LibraryState.history, independently of this queue.
    entries = entries.filter { $0.id == currentID }
    nextEntryID = nil
  }
  @discardableResult public mutating func advance(backward: Bool = false, automatic: Bool = false)
    -> Bool
  {
    guard let index else { return false }
    var next = index + (backward ? -1 : 1)
    if automatic && mode == .repeatOne {
      next = index
    } else if !backward, let priority = entries.firstIndex(where: { $0.id == nextEntryID }) {
      next = priority
      nextEntryID = nil
    } else if !backward && mode == .shuffle {
      next = entries.indices.filter { $0 != index }.randomElement() ?? index
    }
    guard entries.indices.contains(next) else { return false }
    currentID = entries[next].id
    position = 0
    return true
  }
  public mutating func remove(_ id: UUID) {
    if nextEntryID == id { nextEntryID = nil }
    let oldIndex = index ?? 0
    entries.removeAll { $0.id == id }
    if currentID == id {
      currentID = entries.isEmpty ? nil : entries[min(oldIndex, entries.count - 1)].id
      position = 0
    }
  }
}
public struct SourceRecord: Codable, Identifiable, Equatable {
  public var id = UUID()
  public var name: String
  public var version: String
  public var author: String
  public var description: String
  public var homepage: String
  public var script: String
  public var origin: String?
  public var importedAt = Date()
  public init(script: String, origin: String? = nil, fallbackName: String = L10n.text("未命名音乐源"))
    throws
  {
    guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      script.utf8.count <= 9_000_000
    else { throw MusicError.message(L10n.text("源文件为空或超过 9 MB")) }
    self.script = script
    self.origin = origin
    // Metadata is restricted to the opening comment, not arbitrary matches inside code.
    let prefix = String(script.prefix(8192))
    let comment: String
    if let range = prefix.range(of: #"(?s)^\s*/\*.*?\*/"#, options: .regularExpression) {
      comment = String(prefix[range])
    } else {
      comment = ""
    }
    func field(_ key: String) -> String {
      guard let regex = try? NSRegularExpression(pattern: "@" + key + "[ \\t]+([^\\r\\n]*)"),
        let match = regex.firstMatch(
          in: comment, range: NSRange(comment.startIndex..., in: comment)),
        let range = Range(match.range(at: 1), in: comment)
      else { return "" }
      return String(comment[range]).replacingOccurrences(of: "*/", with: "").trimmingCharacters(
        in: .whitespaces)
    }
    name = field("name")
    if name.isEmpty { name = fallbackName }
    version = field("version")
    author = field("author")
    description = field("description")
    homepage = field("homepage")
  }
}
public struct SourceCapability: Codable, Equatable {
  public var type: String
  public var actions: [String]
  public var qualitys: [String]
}
public enum DownloadStatus: String, Codable {
  case queued, resolving, downloading, completed, failed, cancelled, skipped
  public var name: String {
    switch self {
    case .queued: return L10n.text("等待中")
    case .resolving: return L10n.text("解析地址")
    case .downloading: return L10n.text("下载中")
    case .completed: return L10n.text("已完成")
    case .failed: return L10n.text("失败")
    case .cancelled: return L10n.text("已取消")
    case .skipped: return L10n.text("已存在，跳过")
    }
  }
}
public struct DownloadJob: Codable, Identifiable {
  public var id = UUID()
  public var track: Track
  public var quality: String
  public var directory: String
  public var status: DownloadStatus = .queued
  public var progress: Double = 0
  public var file: String?
  public var error: String?
  public init(track: Track, quality: String, directory: String) {
    self.track = track
    self.quality = quality
    self.directory = directory
  }
}
public struct LibraryState: Codable {
  public var schema = 1
  public var playlists: [LocalPlaylist] = [LocalPlaylist(name: L10n.text("我喜欢的音乐"))]
  public var history: [Track] = []
  public var queue = PlaybackQueue()
  public var sources: [SourceRecord] = []
  public var activeSourceID: UUID?
  /// Shared by search, playlists and charts. Optional for compatibility with older libraries.
  public var selectedPlatform: MusicPlatform?
  public var downloads: [DownloadJob] = []
  public var downloadDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Music/MyMusic").path
  public var playbackQuality = "320k"
  /// Optional on disk so libraries created before crossfade remain readable.
  public var crossfadeDuration: Double?
  public var crossfadeSeconds: Double {
    get {
      let value = crossfadeDuration ?? 5
      return value.isFinite ? min(12, max(0, value)) : 5
    }
    set { crossfadeDuration = newValue.isFinite ? min(12, max(0, newValue)) : 5 }
  }
  public var downloadQuality = "320k"
  public var volume: Float = 0.7
  public init() {}
}
public enum MusicError: LocalizedError {
  case message(String)
  public var errorDescription: String? {
    switch self {
    case .message(let text): return text
    }
  }
}
