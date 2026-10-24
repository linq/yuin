import AppKit
import SwiftUI
import XCTest

@testable import MyMusic

@MainActor final class PlayerDesignTests: XCTestCase {
  private func image(_ paint: (CGContext) -> Void) -> CGImage {
    let context = CGContext(
      data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    paint(context)
    return context.makeImage()!
  }
  func testAlbumPaletteRetainsDominantAndSecondaryHuesWithoutWhiteTypeOverwhelmingThem() {
    let palette = ArtworkPalette.extract(
      from: image { context in
        context.setFillColor(CGColor(red: 0.8, green: 0.12, blue: 0.08, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 100))
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 60, y: 0, width: 25, height: 100))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 85, y: 0, width: 15, height: 100))
      })
    XCTAssertGreaterThan(palette.primary.red, palette.primary.blue * 3)
    XCTAssertGreaterThan(palette.secondary.blue, palette.secondary.red * 3)
  }
  func testMonochromeArtworkDoesNotInventAColoredHue() {
    let palette = ArtworkPalette.extract(
      from: image { context in
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
      })
    XCTAssertEqual(palette.primary.red, palette.primary.blue, accuracy: 0.001)
    XCTAssertEqual(palette.primary.red, palette.primary.green, accuracy: 0.001)
  }
  func testSpatialPaletteKeepsSkyAboveSeparateTerrainColors() {
    let palette = ArtworkPalette.extract(
      from: image { context in
        context.setFillColor(CGColor(red: 0.35, green: 0.5, blue: 0.65, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.12, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: 50, height: 58))
        context.setFillColor(CGColor(red: 0.12, green: 0.35, blue: 0.22, alpha: 1))
      context.fill(CGRect(x: 50, y: 0, width: 50, height: 58))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: 100, height: 8))
      })
    XCTAssertGreaterThan(palette.upper.blue, palette.upper.green)
    XCTAssertGreaterThan(palette.lowerLeft.green, palette.lowerLeft.blue * 2)
    XCTAssertGreaterThan(palette.lowerRight.green, palette.lowerRight.red * 2)
    XCTAssertGreaterThan(palette.lowerRight.blue, palette.lowerLeft.blue)
    let light = NSColor(palette.lowerLeft.playerColor(dark: false)).usingColorSpace(.sRGB)!
    let dark = NSColor(palette.lowerLeft.playerColor(dark: true)).usingColorSpace(.sRGB)!
    XCTAssertEqual(light.greenComponent, dark.greenComponent, accuracy: 0.001)
  }
  func testBrightArtworkTonesRemainReadableBehindLightText() {
    for tone in [
      ArtworkTone(red: 1, green: 1, blue: 0), .init(red: 0, green: 1, blue: 1),
      .init(red: 1, green: 0.1, blue: 0.1), .init(red: 0.9, green: 0.9, blue: 0.9),
    ] {
      for dark in [true, false] {
        let rgb = NSColor(tone.playerColor(dark: dark, depth: 0.06)).usingColorSpace(.deviceRGB)!
        func linear(_ v: CGFloat) -> CGFloat {
          v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let luminance =
          0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722
          * linear(rgb.blueComponent)
        XCTAssertGreaterThanOrEqual(1.05 / (luminance + 0.05), 4.5)
      }
    }
  }
  func testPlayerMeasurementsMatchReferenceAndFitShortWindows() {
    let reference = NowPlayingMetrics(size: CGSize(width: 1239, height: 600))
    XCTAssertEqual(reference.columnWidth, 360, accuracy: 1)
    XCTAssertEqual(reference.leading, 130, accuracy: 1)
    XCTAssertEqual(reference.artworkSize * 0.88, 232, accuracy: 1)
    XCTAssertEqual(reference.top + reference.artworkSize + reference.artworkGap, 403, accuracy: 2)
    for size in [
      CGSize(width: 760, height: 460), CGSize(width: 1239, height: 600),
      CGSize(width: 1500, height: 800),
    ] {
      let metrics = NowPlayingMetrics(size: size)
      let bottom = metrics.top + metrics.artworkSize + metrics.artworkGap + 40 + 12 + 30 + 12 + 44
      XCTAssertLessThan(bottom, size.height)
      XCTAssertGreaterThanOrEqual(metrics.leading, 28)
    }
  }
}
