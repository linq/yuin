import AppKit
import SwiftUI
import XCTest

@testable import MyMusic

final class PlaybackIndicatorTests: XCTestCase {
  @MainActor func testPlaybackIndicatorRendersInIsolatedTableCellHost() {
    // Native table cell hosting can rebuild outside the inherited root environment.
    // This must not require an AppModel or touch the user's library/audio player.
    for state in [(false, false), (true, false), (false, true), (false, false)] {
      let renderer = ImageRenderer(
        content:
          PlaybackStateIcon(isLoading: state.0, isPlaying: state.1).frame(width: 20, height: 20))
      XCTAssertNotNil(renderer.nsImage)
    }
  }
}
