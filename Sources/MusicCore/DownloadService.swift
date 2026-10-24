import AVFoundation
import AudioToolbox
import Foundation

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  let progress: @Sendable (Double) -> Void
  init(_ progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    if totalBytesExpectedToWrite > 0 {
      progress(min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }
  }
}
public enum DownloadService {
  public struct Result {
    public var url: URL
    public var skipped: Bool
  }
  public static func download(
    _ url: URL, track: Track, quality: String, directory: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> Result {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // Match only this stable song+quality identity; user-created files remain untouched.
    for ext in ["mp3", "flac", "m4a", "wav", "aac", "ogg"] {
      let existing = directory.appendingPathComponent(
        DownloadFiles.filename(track: track, quality: quality, extension: ext))
      if FileManager.default.fileExists(atPath: existing.path) {
        guard (try? await AVURLAsset(url: existing).load(.isPlayable)) == true else {
          throw MusicError.message(L10n.text("目标文件已存在但无法播放，请先在 Finder 检查文件"))
        }
        try validateQuality(existing, requested: quality)
        return Result(url: existing, skipped: true)
      }
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 60
    let (temporary, response) = try await URLSession.shared.download(
      for: request, delegate: DownloadProgress(progress))
    defer { try? FileManager.default.removeItem(at: temporary) }
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw MusicError.message(
        L10n.text("音频下载失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）"))
    }
    let handle = try FileHandle(forReadingFrom: temporary)
    let head = try handle.read(upToCount: 32) ?? Data()
    try handle.close()
    let ext = try audioExtension(head)
    // AVFoundation needs a recognized extension for some downloaded temporary files.
    // Stage beside the final file so the eventual move is atomic on the destination volume.
    let staging = directory.appendingPathComponent(".mymusic-\(UUID().uuidString).\(ext)")
    try FileManager.default.copyItem(at: temporary, to: staging)
    defer { try? FileManager.default.removeItem(at: staging) }
    guard try await AVURLAsset(url: staging).load(.isPlayable) else {
      throw MusicError.message(L10n.text("下载内容不是当前系统可播放的音频"))
    }
    try validateQuality(staging, requested: quality)
    try Task.checkCancellation()
    let destination = directory.appendingPathComponent(
      DownloadFiles.filename(track: track, quality: quality, extension: ext))
    // Move never replaces an existing path; this also handles concurrent/external writers.
    do { try FileManager.default.moveItem(at: staging, to: destination) } catch {
      if FileManager.default.fileExists(atPath: destination.path) {
        throw MusicError.message(L10n.text("目标文件刚被其他任务创建，已停止写入"))
      }
      throw error
    }
    return Result(url: destination, skipped: false)
  }

  /// Check the encoded file, including duplicates saved by older app versions.
  /// This detects format/bitrate downgrades, not transcoding or recording provenance.
  private static func validateQuality(_ url: URL, requested: String) throws {
    var file: AudioFileID?
    guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else {
      throw MusicError.message(L10n.text("无法验证下载文件的音质，未标记为下载成功"))
    }
    defer { AudioFileClose(file) }
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    guard AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &format) == noErr else {
      throw MusicError.message(L10n.text("无法读取下载文件的音质信息"))
    }
    let lossless = [kAudioFormatFLAC, kAudioFormatAppleLossless, kAudioFormatLinearPCM]
      .contains(format.mFormatID)
    if requested == "flac" || requested == "flac24bit" {
      guard lossless else {
        throw MusicError.message(L10n.text("音质不符：选择了 \(requested)，音乐源返回有损音频；请手动选择普通音质或更换源"))
      }
      var bitDepth = format.mBitsPerChannel
      if bitDepth == 0, format.mFormatID == kAudioFormatFLAC {
        // Core Audio reports zero bits for FLAC. Read the mandatory STREAMINFO block.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = Array(try handle.read(upToCount: 42) ?? Data())
        if bytes.count == 42, Array(bytes[0..<4]) == Array("fLaC".utf8),
          bytes[4] & 0x7f == 0, bytes[5] == 0, bytes[6] == 0, bytes[7] == 34
        {
          bitDepth = UInt32(((bytes[20] & 1) << 4) | (bytes[21] >> 4)) + 1
        }
      } else if bitDepth == 0, format.mFormatID == kAudioFormatAppleLossless {
        bitDepth = [1: 16, 2: 20, 3: 24, 4: 32][format.mFormatFlags] ?? 0
      }
      if requested == "flac24bit", bitDepth < 24 {
        throw MusicError.message(L10n.text("音质不符：选择了 24bit，音乐源返回 \(bitDepth)bit 或无法验证位深的音频"))
      }
    } else if let minimum = ["128k": 128_000.0, "320k": 320_000.0][requested], !lossless {
      var bitrate: UInt32 = 0
      size = UInt32(MemoryLayout<UInt32>.size)
      guard AudioFileGetProperty(file, kAudioFilePropertyBitRate, &size, &bitrate) == noErr,
        bitrate > 0
      else {
        throw MusicError.message(L10n.text("无法验证下载文件的音质码率"))
      }
      // Allow small encoder/container rounding differences, but reject lower quality tiers.
      guard Double(bitrate) >= minimum * 0.95 else {
        throw MusicError.message(
          L10n.text("音质不符：选择了 \(requested)，音乐源返回约 \(bitrate / 1000) kbps；请手动选择音质或更换源"))
      }
    }
  }
  public static func audioExtension(_ data: Data) throws -> String {
    let b = Array(data)
    let prefix = String(decoding: data.prefix(12), as: UTF8.self)
    if prefix.hasPrefix("fLaC") { return "flac" }
    if prefix.hasPrefix("ID3") { return "mp3" }
    if prefix.hasPrefix("OggS") { return "ogg" }
    if prefix.hasPrefix("RIFF"), b.count >= 12, String(decoding: b[8..<12], as: UTF8.self) == "WAVE"
    {
      return "wav"
    }
    if b.count >= 12, String(decoding: b[4..<8], as: UTF8.self) == "ftyp" { return "m4a" }
    if b.count > 2, b[0] == 255, b[1] & 0xE0 == 0xE0 { return b[1] & 0xF6 == 0xF0 ? "aac" : "mp3" }
    throw MusicError.message(L10n.text("服务器返回了非音频内容，未保存为歌曲"))
  }
}
