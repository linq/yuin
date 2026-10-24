import Foundation
import zlib

public struct LyricLine: Codable, Equatable, Identifiable, Sendable {
  public var id: Int
  public var time: Double
  public var text: String
  public var translation: String?
}

public struct LyricsDocument: Codable, Equatable, Sendable {
  public var lines: [LyricLine]
  public var plainText: String
  public var isTimed: Bool { !lines.isEmpty }
  public var isEmpty: Bool { lines.allSatisfy { $0.text.isEmpty } && plainText.isEmpty }

  public func activeLine(at position: Double) -> Int? {
    guard position.isFinite else { return nil }
    var low = 0
    var high = lines.count
    while low < high {
      let mid = (low + high) / 2
      if lines[mid].time <= position { low = mid + 1 } else { high = mid }
    }
    return low > 0 ? lines[low - 1].id : nil
  }

  public static func parse(_ lyric: String, translation: String = "") -> Self {
    let main = parseLines(lyric)
    let translated = parseLines(translation).lines
    var lines = main.lines
    var cursor = 0
    for index in lines.indices {
      while cursor < translated.count && translated[cursor].time < lines[index].time - 0.1 {
        cursor += 1
      }
      if cursor < translated.count, abs(translated[cursor].time - lines[index].time) <= 0.1,
        translated[cursor].text != lines[index].text
      {
        lines[index].translation = translated[cursor].text
      }
    }
    return Self(lines: lines, plainText: lines.isEmpty ? main.plainText : "")
  }

  private static func parseLines(_ value: String) -> Self {
    guard value.utf8.count <= 2_000_000 else { return Self(lines: [], plainText: "") }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.hasPrefix("<html"), !trimmed.hasPrefix("<!doctype") else {
      return Self(lines: [], plainText: "")
    }
    let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
    let krcTime = try! NSRegularExpression(pattern: #"^\[(\d+),\d+\]"#)
    let wordTags = try! NSRegularExpression(pattern: #"<\d+,\d+(?:,\d+)?>|\(\d+,\d+(?:,\d+)?\)"#)
    let metadata = try! NSRegularExpression(pattern: #"^\[[a-zA-Z]+:.*\]$"#)
    let offsetTag = try! NSRegularExpression(
      pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
    let nsValue = value as NSString
    let offset =
      offsetTag.firstMatch(in: value, range: NSRange(location: 0, length: nsValue.length))
      .flatMap { Double(nsValue.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
    var entries: [(Double, String)] = []
    var plain: [String] = []
    for raw in value.replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
      .prefix(5000)
    {
      let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      let ns = line as NSString
      let range = NSRange(location: 0, length: ns.length)
      let times = timestamp.matches(in: line, range: range)
      let krc = krcTime.firstMatch(in: line, range: range)
      if times.isEmpty && krc == nil {
        if !line.isEmpty && metadata.firstMatch(in: line, range: range) == nil
          && !line.hasPrefix("{")
        {
          plain.append(line)
        }
        continue
      }
      var text = timestamp.stringByReplacingMatches(in: line, range: range, withTemplate: "")
      text = krcTime.stringByReplacingMatches(
        in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
      text = wordTags.stringByReplacingMatches(
        in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
      text = text.trimmingCharacters(in: .whitespacesAndNewlines)
      for match in times {
        let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
        let seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
        guard seconds < 60 else { continue }
        let fraction =
          match.range(at: 3).location == NSNotFound ? "" : ns.substring(with: match.range(at: 3))
        let time = minutes * 60 + seconds + (Double("0." + fraction) ?? 0) - offset
        entries.append((max(0, time), text))
      }
      if let krc, let ms = Double(ns.substring(with: krc.range(at: 1))) {
        entries.append((max(0, ms / 1000 - offset), text))
      }
    }
    entries = entries.enumerated().sorted {
      $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0
    }.map(\.element)
    var result: [LyricLine] = []
    for (time, text) in entries {
      if let last = result.last, abs(last.time - time) < 0.001 {
        if !text.isEmpty && !last.text.components(separatedBy: "\n").contains(text) {
          result[result.count - 1].text += (last.text.isEmpty ? "" : "\n") + text
        }
      } else {
        result.append(LyricLine(id: result.count, time: time, text: text))
      }
    }
    return Self(lines: result, plainText: plain.joined(separator: "\n"))
  }
}

/// Lyrics use the selected track's platform identity, independently of audio URL sources.
/// Successful documents are cached for offline listening; failures remain retryable.
public actor LyricsService {
  public static let shared = LyricsService()
  private let session: URLSession
  private let cacheDirectory: URL?
  private var memory: [String: LyricsDocument] = [:]
  public init(
    session: URLSession = .shared,
    cacheDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
      .first?.appendingPathComponent("MyMusic/Lyrics")
  ) {
    self.session = session
    self.cacheDirectory = cacheDirectory
  }
  public func lyrics(for track: Track, refresh: Bool = false) async throws -> LyricsDocument {
    let safeID = Data(track.id.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
    let file = cacheDirectory?.appendingPathComponent(String(safeID.prefix(180)) + ".json")
    if !refresh {
      if let cached = memory[track.id] { return cached }
      if let file, let data = try? Data(contentsOf: file), data.count <= 2_000_000,
        let cached = try? JSONDecoder().decode(LyricsDocument.self, from: data), !cached.isEmpty
      {
        memory[track.id] = cached
        return cached
      }
    }
    let document = try await fetch(track)
    try Task.checkCancellation()
    if !document.isEmpty {
      if memory.count >= 50 { memory.removeAll() }
      memory[track.id] = document
      if let file {
        try? FileManager.default.createDirectory(
          at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(document) {
          try? data.write(to: file, options: .atomic)
        }
      }
    }
    return document
  }
  private func fetch(_ track: Track) async throws -> LyricsDocument {
    switch track.platform {
    case .wy:
      let data = try await object(
        "https://music.163.com/api/song/lyric",
        ["id": track.songID, "lv": "-1", "kv": "-1", "tv": "-1"])
      guard (data["code"] as? Int) == 200 else { throw unavailable() }
      return .parse(
        (data["lrc"] as? [String: Any])?["lyric"] as? String ?? "",
        translation: (data["tlyric"] as? [String: Any])?["lyric"] as? String ?? "")
    case .kw:
      let data = try await request(
        "https://mlyric.kuwo.cn/mobi.s",
        ["f": "web", "type": "lyric", "lrcx": "0", "rid": track.songID, "encode": "utf8"])
      guard String(decoding: data.prefix(10), as: UTF8.self).lowercased() == "tp=content",
        let boundary = data.range(of: Data("\r\n\r\n".utf8))
      else { throw unavailable() }
      var text = try Self.inflate(Data(data[boundary.upperBound...]))
      let header = String(decoding: data[..<boundary.lowerBound], as: UTF8.self).lowercased()
      if header.contains("lrcx=1") {
        guard let encoded = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else {
          throw unavailable()
        }
        let key = Array("yeelion".utf8)
        text = String(
          decoding: encoded.enumerated().map { $0.element ^ key[$0.offset % key.count] },
          as: UTF8.self)
      }
      return .parse(Self.entities(text))
    case .tx:
      let data = try await object(
        "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg",
        [
          "songmid": track.songID, "g_tk": "5381", "format": "json", "nobase64": "1",
          "platform": "yqq.json",
        ], referer: "https://y.qq.com/portal/player.html")
      guard (data["code"] as? Int) == 0 else { throw unavailable() }
      func decode(_ key: String) -> String {
        let string = data[key] as? String ?? ""
        if string.contains("[") { return Self.entities(string) }
        return Self.entities(
          Data(base64Encoded: string).flatMap { String(data: $0, encoding: .utf8) } ?? string)
      }
      return .parse(decode("lyric"), translation: decode("trans"))
    case .kg:
      guard case .string(let hash) = track.sourceInfo["hash"], !hash.isEmpty else {
        throw unavailable()
      }
      let result = try await object(
        "https://lyrics.kugou.com/search",
        [
          "ver": "1", "man": "yes", "client": "pc", "hash": hash,
          "timelength": String(Int(track.duration * 1000)), "lrctxt": "1",
        ])
      guard let candidate = (result["candidates"] as? [[String: Any]])?.first,
        let id = candidate["id"], let key = candidate["accesskey"] as? String
      else { return .parse("") }
      let data = try await object(
        "https://lyrics.kugou.com/download",
        [
          "ver": "1", "client": "pc", "id": String(describing: id), "accesskey": key, "fmt": "lrc",
          "charset": "utf8",
        ])
      guard let content = data["content"] as? String, var decoded = Data(base64Encoded: content)
      else { throw unavailable() }
      if decoded.starts(with: Data("krc1".utf8)) {
        let key: [UInt8] = [
          0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47, 0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e,
          0x69,
        ]
        decoded = Data(
          decoded.dropFirst(4).enumerated().map { $0.element ^ key[$0.offset % key.count] })
        return .parse(try Self.inflate(decoded))
      }
      return .parse(Self.entities(String(data: decoded, encoding: .utf8) ?? ""))
    case .mg:
      var url = track.sourceInfo["lrcUrl"]?.stringValue ?? ""
      var translation = track.sourceInfo["trcUrl"]?.stringValue ?? ""
      if url.isEmpty {
        let data = try await object(
          "https://c.musicapp.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do",
          ["resourceType": "2", "resourceId": track.songID])
        let root = data["data"] as? [String: Any] ?? data
        guard let info = (root["resource"] as? [[String: Any]])?.first else { throw unavailable() }
        url = info["lrcUrl"] as? String ?? ""
        translation = info["trcUrl"] as? String ?? ""
      }
      guard !url.isEmpty else { return .parse("") }
      let main = try await request(url, referer: "https://app.c.nf.migu.cn/")
      let translated =
        translation.isEmpty
        ? nil : try? await request(translation, referer: "https://app.c.nf.migu.cn/")
      return .parse(
        String(decoding: main, as: UTF8.self),
        translation: translated.map { String(decoding: $0, as: UTF8.self) } ?? "")
    }
  }
  private func object(_ base: String, _ params: [String: String] = [:], referer: String? = nil)
    async throws -> [String: Any]
  {
    let data = try await request(base, params, referer: referer)
    guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw unavailable()
    }
    return result
  }
  private func request(_ base: String, _ params: [String: String] = [:], referer: String? = nil)
    async throws -> Data
  {
    guard var components = URLComponents(string: base),
      ["http", "https"].contains(components.scheme?.lowercased() ?? ""), components.host != nil
    else { throw unavailable() }
    if !params.isEmpty {
      components.queryItems =
        (components.queryItems ?? [])
        + params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    guard let url = components.url else { throw unavailable() }
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    request.setValue(referer ?? base, forHTTPHeaderField: "Referer")
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode)
    else { throw unavailable() }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 2_000_000 else { throw unavailable() }
      data.append(byte)
    }
    try Task.checkCancellation()
    return data
  }
  private func unavailable() -> MusicError { .message(L10n.text("歌词暂时无法载入，请稍后重试。")) }
  private static func inflate(_ data: Data) throws -> String {
    var output = Data(count: 2_000_000)
    var count = uLongf(output.count)
    let status = output.withUnsafeMutableBytes { out in
      data.withUnsafeBytes { input in
        uncompress(
          out.bindMemory(to: Bytef.self).baseAddress, &count,
          input.bindMemory(to: Bytef.self).baseAddress, uLong(data.count))
      }
    }
    guard status == Z_OK else { throw MusicError.message(L10n.text("歌词格式无法识别。")) }
    output.count = Int(count)
    return String(decoding: output, as: UTF8.self)
  }
  private static func entities(_ text: String) -> String {
    var value = text
    let regex = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#)
    for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed()
    {
      guard let range = Range(match.range, in: value),
        let digits = Range(match.range(at: 1), in: value)
      else { continue }
      let number = String(value[digits])
      if let code = number.hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number),
        let scalar = UnicodeScalar(code)
      {
        value.replaceSubrange(range, with: String(scalar))
      }
    }
    return value.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(
      of: "&apos;", with: "'"
    ).replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
  }
}

extension JSONValue {
  fileprivate var stringValue: String? {
    if case .string(let value) = self { return value }
    return nil
  }
}
