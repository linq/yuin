import Foundation
import XCTest

@testable import MusicCore

final class LocalizationTests: XCTestCase {
  func testSystemLanguageUsesSupportedPreferredOrder() {
    XCTAssertEqual(
      MusicLanguage.system.resolvedIdentifier(preferredLanguages: ["zh-CN", "en-US"]), "zh-Hans")
    XCTAssertEqual(
      MusicLanguage.system.resolvedIdentifier(preferredLanguages: ["en-GB", "zh-Hans-CN"]), "en")
    XCTAssertEqual(
      MusicLanguage.system.resolvedIdentifier(preferredLanguages: ["fr-FR", "zh-TW"]), "zh-Hans")
    XCTAssertEqual(MusicLanguage.system.resolvedIdentifier(preferredLanguages: ["ja-JP"]), "en")
    XCTAssertEqual(MusicLanguage.english.resolvedIdentifier(preferredLanguages: ["zh-CN"]), "en")
    XCTAssertEqual(
      MusicLanguage.simplifiedChinese.resolvedIdentifier(preferredLanguages: ["en-US"]), "zh-Hans")
  }

  func testPreferenceDefaultsToSystemAndPersistsExplicitSelection() throws {
    let suite = "MyMusic.LanguageTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    XCTAssertEqual(MusicLanguage.selected(in: defaults), .system)
    defaults.set(MusicLanguage.english.rawValue, forKey: MusicLanguage.preferenceKey)
    XCTAssertEqual(
      MusicLanguage.selected(in: try XCTUnwrap(UserDefaults(suiteName: suite))), .english)
    defaults.set("unknown", forKey: MusicLanguage.preferenceKey)
    XCTAssertEqual(MusicLanguage.selected(in: defaults), .system)
  }

  func testBundledTranslationsAndSystemResolution() {
    XCTAssertEqual(L10n.text("资料库", language: .english), "Library")
    XCTAssertEqual(L10n.text("资料库", language: .simplifiedChinese), "资料库")
    XCTAssertEqual(
      L10n.text("跟随系统", language: .system, preferredLanguages: ["en-US"]), "Follow System")
    XCTAssertEqual(L10n.text("跟随系统", language: .system, preferredLanguages: ["zh-Hans"]), "跟随系统")
    XCTAssertEqual(L10n.text("播放进度", language: .english), "Playback Progress")
  }

  func testInterpolationPreservesUserContentAndPercentCharacters() {
    let title = "歌单 100% %@ 🎵"
    XCTAssertEqual(L10n.text("删除“\(title)”？", language: .english), "Delete “歌单 100% %@ 🎵”?")
    XCTAssertEqual(L10n.text("已显示 \(30) / \(100) 首", language: .english), "Showing 30 / 100 songs")
    XCTAssertEqual(
      L10n.text("已显示 \(30) / \(100) 首", language: .simplifiedChinese), "已显示 30 / 100 首")
    XCTAssertEqual(L10n.text("100%", language: .english), "100%")
  }

  func testTranslationTablesCoverTheSameKeysAndSubstitutions() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Sources/MusicCore/Resources")
    func table(_ language: String) throws -> [String: String] {
      let data = try Data(
        contentsOf: root.appendingPathComponent("\(language).lproj/Localizable.strings"))
      return try XCTUnwrap(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }
    let chinese = try table("zh-Hans")
    let english = try table("en")
    XCTAssertGreaterThan(chinese.count, 250)
    XCTAssertEqual(Set(chinese.keys), Set(english.keys))
    for (key, translation) in english {
      XCTAssertEqual(
        key.components(separatedBy: "%@").count, translation.components(separatedBy: "%@").count,
        key)
      XCTAssertFalse(translation.isEmpty, key)
    }
  }
}
