import Foundation

/// Each source runs in a disposable process. A timeout can terminate a stuck JS VM without blocking the UI.
@MainActor public final class SourceRuntime {
  public private(set) var capabilities: [String: SourceCapability] = [:]
  public var onUpdate: ((String) -> Void)?
  private let process = Process()
  private let input = Pipe(), output = Pipe()
  private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
  private var deadlines: [String: Task<Void, Never>] = [:]
  private var buffer = Data()
  private var closed = false
  public init() {}
  public static func hostURL() throws -> URL {
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    let candidate = executable.deletingLastPathComponent().appendingPathComponent("MusicSourceHost")
    guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
      throw MusicError.message(L10n.text("缺少 MusicSourceHost，请通过 scripts/build-app.sh 构建完整应用"))
    }
    return candidate
  }
  public func start(_ source: SourceRecord, executable: URL? = nil, startupTimeout: Double = 15)
    async throws
  {
    process.executableURL = try executable ?? Self.hostURL()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      Task { @MainActor [weak self] in self?.receive(data) }
    }
    process.terminationHandler = { [weak self] _ in
      Task { @MainActor [weak self] in self?.stop(reason: L10n.text("音乐源进程已退出，请重新启用或切换源")) }
    }
    do { try process.run() } catch {
      stop()
      throw error
    }
    let result = try await call(
      [
        "op": "init", "script": source.script,
        "meta": [
          "name": source.name, "version": source.version, "author": source.author,
          "description": source.description, "homepage": source.homepage,
          "rawScript": source.script,
        ],
      ], timeout: startupTimeout)
    guard let sources = result["sources"] as? [String: Any] else {
      stop()
      throw MusicError.message(L10n.text("音乐源未声明支持能力"))
    }
    capabilities = try JSONDecoder().decode(
      [String: SourceCapability].self, from: JSONSerialization.data(withJSONObject: sources))
  }
  public func resolve(_ track: Track, quality: String) async throws -> URL {
    guard let capability = capabilities[track.platform.rawValue],
      capability.actions.contains("musicUrl"), capability.qualitys.contains(quality)
    else {
      throw MusicError.message(L10n.text("当前音乐源不支持\(track.platform.name)的 \(quality)，请手动切源或选择音质"))
    }
    let info = try JSONSerialization.jsonObject(with: JSONEncoder().encode(track.lxInfo))
    let response = try await call(
      [
        "op": "resolve", "source": track.platform.rawValue, "action": "musicUrl",
        "info": ["type": quality, "musicInfo": info],
      ], timeout: 65)
    guard let string = response["url"] as? String, string.utf8.count <= 2048,
      let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
      url.host != nil
    else { throw MusicError.message(L10n.text("音乐源返回了无效的播放地址")) }
    return url
  }
  public func stop(reason: String = L10n.text("音乐源已停止")) {
    guard !closed else { return }
    closed = true
    output.fileHandleForReading.readabilityHandler = nil
    process.terminationHandler = nil
    if process.isRunning {
      process.terminate()
      let running = process
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
        if running.isRunning { kill(running.processIdentifier, SIGKILL) }
      }
    }
    try? input.fileHandleForWriting.close()
    try? output.fileHandleForReading.close()
    let waits = pending
    pending.removeAll()
    deadlines.values.forEach { $0.cancel() }
    deadlines.removeAll()
    for continuation in waits.values { continuation.resume(throwing: MusicError.message(reason)) }
    capabilities = [:]
  }
  private func call(_ command: [String: Any], timeout: Double) async throws -> [String: Any] {
    let id = UUID().uuidString
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        guard !closed, process.isRunning else {
          continuation.resume(throwing: MusicError.message(L10n.text("音乐源未运行")))
          return
        }
        pending[id] = continuation
        deadlines[id] = Task { [weak self] in
          do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) } catch { return }
          self?.stop(reason: L10n.text("音乐源响应超时，已停止脚本；请重新启用或切换源"))
        }
        var command = command
        command["id"] = id
        do {
          var data = try JSONSerialization.data(withJSONObject: command)
          data.append(10)
          try input.fileHandleForWriting.write(contentsOf: data)
        } catch { finish(id, .failure(error)) }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.finish(id, .failure(CancellationError())) }
    }
  }
  private func finish(_ id: String, _ result: Result<[String: Any], Error>) {
    deadlines.removeValue(forKey: id)?.cancel()
    pending.removeValue(forKey: id)?.resume(with: result)
  }
  private func receive(_ data: Data) {
    guard !closed else { return }
    guard !data.isEmpty else {
      stop(reason: L10n.text("音乐源进程已退出"))
      return
    }
    buffer.append(data)
    guard buffer.count <= 12_000_000 else {
      stop(reason: L10n.text("音乐源输出超过上限"))
      return
    }
    while let end = buffer.firstIndex(of: 10) {
      let line = buffer[..<end]
      buffer.removeSubrange(...end)
      guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
        continue
      }
      if let update = message["update"] as? String {
        onUpdate?(String(update.prefix(1024)))
        continue
      }
      guard let id = message["id"] as? String else { continue }
      if let error = message["error"] as? String {
        finish(id, .failure(MusicError.message(error)))
      } else {
        finish(id, .success(message["result"] as? [String: Any] ?? [:]))
      }
    }
  }
}

public enum SourceImport {
  public static func local(_ url: URL) throws -> SourceRecord {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 9_000_000 else { throw MusicError.message(L10n.text("源文件超过 9 MB")) }
    return try SourceRecord(
      script: String(contentsOf: url, encoding: .utf8),
      fallbackName: url.deletingPathExtension().lastPathComponent)
  }
  public static func online(_ string: String) async throws -> SourceRecord {
    guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil
    else { throw MusicError.message(L10n.text("请输入有效的 HTTP(S) 音乐源链接")) }
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw MusicError.message(L10n.text("音乐源链接请求失败"))
    }
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
      if data.count > 9_000_000 { throw MusicError.message(L10n.text("在线音乐源超过 9 MB")) }
    }
    guard let script = String(data: data, encoding: .utf8) else {
      throw MusicError.message(L10n.text("音乐源必须是 UTF-8 JavaScript 文件"))
    }
    return try SourceRecord(
      script: script, origin: url.absoluteString,
      fallbackName: url.deletingPathExtension().lastPathComponent)
  }
}
