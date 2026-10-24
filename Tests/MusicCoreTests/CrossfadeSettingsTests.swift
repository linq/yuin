import Foundation
import XCTest

@testable import MusicCore

final class CrossfadeSettingsTests: XCTestCase {
  func testOldLibraryDefaultsToFiveSecondsAndDurationRoundTrips() throws {
    let encoded = try JSONEncoder().encode(LibraryState())
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json.removeValue(forKey: "crossfadeDuration")
    var state = try JSONDecoder().decode(
      LibraryState.self,
      from: JSONSerialization.data(withJSONObject: json))
    XCTAssertEqual(state.crossfadeSeconds, 5)
    state.crossfadeSeconds = 0
    XCTAssertEqual(
      try JSONDecoder().decode(
        LibraryState.self,
        from: JSONEncoder().encode(state)
      ).crossfadeSeconds, 0)
    state.crossfadeSeconds = 8
    XCTAssertEqual(
      try JSONDecoder().decode(
        LibraryState.self,
        from: JSONEncoder().encode(state)
      ).crossfadeSeconds, 8)
  }

  func testRestoredInvalidDurationsAreBounded() {
    var state = LibraryState()
    for (stored, expected) in [(-2.0, 0.0), (99, 12), (.infinity, 5), (.nan, 5)] {
      state.crossfadeDuration = stored
      XCTAssertEqual(state.crossfadeSeconds, expected)
    }
  }
}
