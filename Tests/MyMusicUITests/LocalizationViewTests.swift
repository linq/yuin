import AppKit
import MusicCore
import XCTest

@testable import MyMusic

@MainActor final class LocalizationViewTests: XCTestCase {
  func testRetainedNativeTableChangesLanguageWithoutReplacingOrReorderingColumns() {
    let table = NSTableView()
    let titles = ["歌曲", "艺人", "专辑", "时长", ""]
    let columns = titles.enumerated().map { index, title in
      let column = NSTableColumn(identifier: .init("column-\(index)"))
      column.title = title
      table.addTableColumn(column)
      return column
    }
    // Reordered native columns must keep their meaning when their language changes.
    table.moveColumn(1, toColumn: 2)
    TrackTableAppearance.localizeColumns(in: table, language: .english)
    XCTAssertEqual(table.tableColumns.map(\.title), ["Song", "Album", "Artist", "Time", ""])
    XCTAssertTrue(table.tableColumns[0] === columns[0])
    XCTAssertTrue(table.tableColumns[1] === columns[2])
    TrackTableAppearance.localizeColumns(in: table, language: .simplifiedChinese)
    XCTAssertEqual(table.tableColumns.map(\.title), ["歌曲", "专辑", "艺人", "时长", ""])
    XCTAssertTrue(table.tableColumns[2] === columns[1])
  }
}
