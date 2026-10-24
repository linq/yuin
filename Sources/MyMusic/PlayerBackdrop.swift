import AppKit
import ImageIO
import SwiftUI

struct ArtworkTone: Equatable, Sendable {
  let red: Double
  let green: Double
  let blue: Double
  func distance(to other: Self) -> Double {
    abs(red - other.red) + abs(green - other.green) + abs(blue - other.blue)
  }
  func playerColor(dark _: Bool, depth: Double = 0) -> Color {
    let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
    // Preserve the artwork's hue. Neutral covers stay neutral, rather than gaining
    // an unrelated fallback tint. Bound brightness so white text stays readable.
    // The immersive player keeps the same album lighting in both system modes.
    // Avoid boosting saturation: it made blue/green sleeves look uniformly cyan.
    let adjustedSaturation = min(0.80, saturation * 0.96)
    var adjustedBrightness = min(
      0.56, max(0.20, 0.14 + brightness * 0.55 + depth))
    var result = NSColor(
      hue: hue, saturation: adjustedSaturation, brightness: adjustedBrightness, alpha: 1)
    func linear(_ value: CGFloat) -> CGFloat {
      value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    for _ in 0..<8 {
      let rgb = result.usingColorSpace(.deviceRGB)!
      let luminance =
        0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722
        * linear(rgb.blueComponent)
      if luminance <= 0.18 { break }
      adjustedBrightness *= 0.92
      result = NSColor(
        hue: hue, saturation: adjustedSaturation, brightness: adjustedBrightness, alpha: 1)
    }
    return Color(nsColor: result)
  }
}

struct ArtworkPalette: Equatable, Sendable {
  let primary: ArtworkTone
  let secondary: ArtworkTone
  let accent: ArtworkTone
  let upper: ArtworkTone
  let lowerLeft: ArtworkTone
  let lowerRight: ArtworkTone
  init(
    primary: ArtworkTone, secondary: ArtworkTone, accent: ArtworkTone,
    upper: ArtworkTone? = nil, lowerLeft: ArtworkTone? = nil, lowerRight: ArtworkTone? = nil
  ) {
    self.primary = primary
    self.secondary = secondary
    self.accent = accent
    self.upper = upper ?? accent
    self.lowerLeft = lowerLeft ?? primary
    self.lowerRight = lowerRight ?? secondary
  }
  static let neutral = Self(
    primary: .init(red: 0.36, green: 0.36, blue: 0.36),
    secondary: .init(red: 0.22, green: 0.22, blue: 0.22),
    accent: .init(red: 0.48, green: 0.48, blue: 0.48))

  static func extract(from image: CGImage) -> Self {
    let size = 48
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    guard
      let context = CGContext(
        data: &pixels, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return .neutral }
    context.interpolationQuality = .low
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    struct Cluster {
      var count = 0.0
      var red = 0.0
      var green = 0.0
      var blue = 0.0
    }
    var clusters: [Int: Cluster] = [:]
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let alpha = Double(pixels[index + 3]) / 255
      guard alpha > 0.5 else { continue }
      let r = min(1, Double(pixels[index]) / 255 / alpha)
      let g = min(1, Double(pixels[index + 1]) / 255 / alpha)
      let b = min(1, Double(pixels[index + 2]) / 255 / alpha)
      let high = max(r, g, b)
      let low = min(r, g, b)
      // White typography and black borders should not overwhelm the album colors.
      guard high > 0.08, low < 0.92 else { continue }
      let key = (Int(r * 7) << 6) | (Int(g * 7) << 3) | Int(b * 7)
      let weight = 0.5 + (high - low) * 0.8
      var cluster = clusters[key] ?? Cluster()
      cluster.count += weight
      cluster.red += r * weight
      cluster.green += g * weight
      cluster.blue += b * weight
      clusters[key] = cluster
    }
    let ranked = clusters.values.sorted { $0.count > $1.count }.map {
      ArtworkTone(red: $0.red / $0.count, green: $0.green / $0.count, blue: $0.blue / $0.count)
    }
    guard let primary = ranked.first else {
      // A monochrome sleeve needs a quiet neutral field rather than a fabricated hue.
      return .neutral
    }
    let secondary = ranked.first { $0.distance(to: primary) > 0.30 } ?? primary
    let accent =
      ranked.first { $0.distance(to: primary) > 0.48 && $0.distance(to: secondary) > 0.25 }
      ?? secondary
    // Preserve the sleeve's spatial colors instead of placing the three most
    // frequent RGB bins at fixed, unrelated corners. In the lower regions, give
    // colorful subjects more weight than dark shadows. Exclude the title strip.
    func regional(_ xRange: Range<Int>, _ yRange: Range<Int>, colorful: Bool) -> ArtworkTone {
      var chosen = Cluster()
      for y in yRange {
        for x in xRange {
          let index = (y * size + x) * 4
          let alpha = Double(pixels[index + 3]) / 255
          guard alpha > 0.5 else { continue }
          let r = min(1, Double(pixels[index]) / 255 / alpha)
          let g = min(1, Double(pixels[index + 1]) / 255 / alpha)
          let b = min(1, Double(pixels[index + 2]) / 255 / alpha)
          let high = max(r, g, b)
          let low = min(r, g, b)
          guard high > 0.10, low < 0.92 else { continue }
          let saturation = (high - low) / high
          let weight =
            colorful
            ? 0.003 + pow(saturation, 4) * pow(high, 1.3)
            : (0.35 + saturation * 0.65) * max(0.15, high)
          chosen.count += weight
          chosen.red += r * weight
          chosen.green += g * weight
          chosen.blue += b * weight
        }
      }
      guard chosen.count > 0 else {
        return primary
      }
      return ArtworkTone(
        red: chosen.red / chosen.count, green: chosen.green / chosen.count,
        blue: chosen.blue / chosen.count)
    }
    return Self(
      primary: primary, secondary: secondary, accent: accent,
      upper: regional(0..<size, 0..<20, colorful: false),
      lowerLeft: regional(0..<27, 20..<42, colorful: true),
      lowerRight: regional(21..<size, 28..<44, colorful: true))
  }
}

actor ArtworkPaletteLoader {
  static let shared = ArtworkPaletteLoader()
  private var cache: [String: ArtworkPalette] = [:]
  func palette(for string: String) async throws -> ArtworkPalette {
    if let cached = cache[string] { return cached }
    guard let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    else { return .neutral }
    var request = URLRequest(url: url)
    request.timeoutInterval = 12
    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode)
    else { return .neutral }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 15_000_000 else { return .neutral }
      data.append(byte)
    }
    let palette = await Task.detached(priority: .utility) {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 96, kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary)
      else { return ArtworkPalette.neutral }
      return ArtworkPalette.extract(from: image)
    }.value
    try Task.checkCancellation()
    if cache.count >= 40 { cache.removeAll() }
    cache[string] = palette
    return palette
  }
}

struct PlayerBackdrop: View {
  let artwork: String?
  let active: Bool
  let dark: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var palette = ArtworkPalette.neutral
  var body: some View {
    GeometryReader { geometry in
      ZStack {
        LinearGradient(
          colors: [
            palette.upper.playerColor(dark: dark, depth: 0.02),
            palette.lowerRight.playerColor(dark: dark, depth: -0.04),
          ], startPoint: .top, endPoint: .bottom)
        RadialGradient(
          colors: [palette.lowerLeft.playerColor(dark: dark, depth: 0.01).opacity(0.85), .clear],
          center: UnitPoint(x: 0, y: 0.65), startRadius: 0, endRadius: geometry.size.width * 0.65)
        RadialGradient(
          colors: [palette.lowerRight.playerColor(dark: dark, depth: -0.02).opacity(0.8), .clear],
          center: UnitPoint(x: 1, y: 0.85), startRadius: 0, endRadius: geometry.size.width * 0.65)
      }
      .animation(reduceMotion ? nil : .easeInOut(duration: 1.0), value: palette)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: dark)
    }
    .allowsHitTesting(false).accessibilityHidden(true)
    .task(id: active ? artwork : nil) {
      guard active else { return }
      guard let artwork, !artwork.isEmpty else {
        palette = .neutral
        return
      }
      do {
        let result = try await ArtworkPaletteLoader.shared.palette(for: artwork)
        try Task.checkCancellation()
        palette = result
      } catch { if !Task.isCancelled { palette = .neutral } }
    }
  }
}

/// Measurements are in points and use the whole player canvas, including the titlebar.
struct NowPlayingMetrics {
  let columnWidth: CGFloat
  let artworkSize: CGFloat
  let leading: CGFloat
  let top: CGFloat
  let artworkGap: CGFloat
  init(size: CGSize) {
    columnWidth = min(360, max(250, size.width * 0.291))
    leading = max(28, size.width * 0.25 - columnWidth / 2)
    top = max(66, size.height * 0.15)
    // At 1239 × 600: a 360 pt column centered at x=310, full cover 264 pt,
    // paused cover 232 pt. Leave enough room for long titles and transport controls.
    artworkSize = min(columnWidth - 24, max(130, size.height * 0.44))
    artworkGap = min(52, max(24, size.height * 0.082))
  }
}
