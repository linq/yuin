import Combine
import MusicCore
import XCTest

@testable import MyMusic

@MainActor final class PlaybackUpdateTests: XCTestCase {
  func testScrollBackdropCoalescesGeometryUpdates() async {
    let backdrop = SidebarBackdropState()
    var updates = 0
    let observer = backdrop.objectWillChange.sink { updates += 1 }
    for index in 0..<200 {
      backdrop.submit([SidebarArtworkSample(id: "cover", url: nil,
        frame: CGRect(x: 0, y: index, width: 200, height: 200))])
    }
    XCTAssertEqual(updates, 0)
    try? await Task.sleep(for: .milliseconds(160))
    XCTAssertEqual(updates, 1)
    XCTAssertEqual(backdrop.samples.first?.frame.minY, 199)
    withExtendedLifetime(observer) {}
  }

  func testClockTicksDoNotInvalidateCatalogAndPersistLatestPosition() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LibraryStore(url: directory.appendingPathComponent("library.json"))
    let model = AppModel(store: store, startServices: false)
    var updates = 0
    let observer = model.objectWillChange.sink { updates += 1 }
    for tick in 1...100 {
      model.updatePlaybackTime(position: Double(tick) / 2, duration: 240)
    }
    XCTAssertEqual(updates, 0, "Progress ticks must not redraw the entire app")
    XCTAssertEqual(model.position, 50)
    XCTAssertEqual(model.state.queue.position, 50)
    model.state.queue.replace(
      [Track(platform: .wy, songID: "1", title: "Test", artist: "Test")], start: 0)
    model.updatePlaybackTime(position: 50, duration: 240)
    model.persist()
    XCTAssertEqual(try store.load().queue.position, 50)
    withExtendedLifetime(observer) {}
  }
}
