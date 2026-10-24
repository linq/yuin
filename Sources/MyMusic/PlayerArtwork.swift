import AppKit
import ImageIO
import MusicCore
import SwiftUI

actor PlayerArtworkLoader {
  static let shared = PlayerArtworkLoader()
  private var cache: [String: CGImage] = [:]
  func image(for string: String) async throws -> CGImage {
    if let image = cache[string] { return image }
    guard let url = URL(string: string),
      ["https", "http", "file"].contains(url.scheme?.lowercased() ?? "")
    else { throw URLError(.badURL) }
    let data: Data
    if url.isFileURL {
      guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 15_000_000 else {
        throw URLError(.dataLengthExceedsMaximum)
      }
      data = try Data(contentsOf: url)
    } else {
      var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 12)
      request.setValue("image/*", forHTTPHeaderField: "Accept")
      let (bytes, response) = try await URLSession.shared.bytes(for: request)
      guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode)
      else {
        throw URLError(.badServerResponse)
      }
      var buffer = Data()
      for try await byte in bytes {
        guard buffer.count < 15_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        buffer.append(byte)
      }
      data = buffer
    }
    let image = try await Task.detached(priority: .utility) {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary)
      else { throw URLError(.cannotDecodeContentData) }
      return image
    }.value
    try Task.checkCancellation()
    if cache.count >= 12 { cache.removeAll() }
    cache[string] = image
    return image
  }
}

/// The hero keeps its previous image during loading, then dissolves between covers.
/// Its container remains stable so expanding/returning still uses the same anchor.
struct PlayerArtwork: View {
  let url: String?
  let size: CGFloat
  let radius: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var image: CGImage?
  @State private var displayedURL: String?
  var body: some View {
    ZStack {
      if let image {
        Image(decorative: image, scale: 1).resizable().scaledToFill()
          .id(displayedURL).transition(.opacity)
      } else {
        Artwork(url: nil, size: size, radius: radius)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: radius))
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: displayedURL)
    .accessibilityHidden(true)
    .task(id: url) {
      guard !Task.isCancelled else { return }
      guard let url, !url.isEmpty else {
        image = nil
        displayedURL = nil
        return
      }
      do {
        let loaded = try await PlayerArtworkLoader.shared.image(for: url)
        try Task.checkCancellation()
        image = loaded
        displayedURL = url
      } catch {
        guard !Task.isCancelled else { return }
        image = nil
        displayedURL = url
      }
    }
  }
}

struct PlayerTrackMetadata: View {
  let track: Track?
  var large = false
  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    ZStack(alignment: .leading) {
      VStack(alignment: .leading, spacing: large ? 2 : 1) {
        Text(track?.title ?? L10n.text("尚未播放"))
          .font(.system(size: large ? 17 : 13, weight: large ? .semibold : .medium))
          .help(track?.title ?? "")
        Text(
          track.map { [$0.artist, $0.album].filter { !$0.isEmpty }.joined(separator: " — ") }
            ?? L10n.text("选择一首歌曲，开始聆听")
        )
        .font(.system(size: large ? 15 : 11))
        .foregroundStyle(.primary.opacity(large ? 0.65 : 0.72))
      }.lineLimit(1).id(track?.id).transition(.opacity)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: track?.id)
  }
}
