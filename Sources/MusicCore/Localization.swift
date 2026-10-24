import Foundation

public enum MusicLanguage: String, CaseIterable, Identifiable {
  case system
  case simplifiedChinese = "zh-Hans"
  case english = "en"
  public static let preferenceKey = "appLanguage"
  public var id: String { rawValue }
  public var name: String {
    switch self {
    case .system: return L10n.text("跟随系统")
    case .simplifiedChinese: return "简体中文"
    case .english: return "English"
    }
  }
  public func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String
  {
    switch self {
    case .simplifiedChinese: return "zh-Hans"
    case .english: return "en"
    case .system:
      // Skip unsupported preferences, as macOS does when choosing a bundle localization.
      for language in preferredLanguages {
        let code = Locale(identifier: language).language.languageCode?.identifier
        if code == "zh" { return "zh-Hans" }
        if code == "en" { return "en" }
      }
      return "en"
    }
  }
  public var locale: Locale { Locale(identifier: resolvedIdentifier()) }
  public static func selected(in defaults: UserDefaults = .standard) -> Self {
    Self(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .system
  }
}

/// Keep substitutions separate from translation keys: track titles, source metadata and
/// user-created playlist names are content, and must never be translated as UI labels.
public struct MusicLocalizedText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
  public let key: String
  public let arguments: [String]
  public init(stringLiteral value: String) {
    key = value.replacingOccurrences(of: "%", with: "%%")
    arguments = []
  }
  public init(stringInterpolation: StringInterpolation) {
    key = stringInterpolation.key
    arguments = stringInterpolation.arguments
  }
  public struct StringInterpolation: StringInterpolationProtocol {
    var key = ""
    var arguments: [String] = []
    public init(literalCapacity: Int, interpolationCount: Int) {
      key.reserveCapacity(literalCapacity)
      arguments.reserveCapacity(interpolationCount)
    }
    public mutating func appendLiteral(_ literal: String) {
      key += literal.replacingOccurrences(of: "%", with: "%%")
    }
    public mutating func appendInterpolation<T>(_ value: T) {
      key += "%@"
      arguments.append(String(describing: value))
    }
  }
}

public enum L10n {
  private static let bundles: [String: Bundle] = {
    Dictionary(
      uniqueKeysWithValues: ["en", "zh-Hans"].compactMap { language in
        Bundle.module.path(forResource: language, ofType: "lproj")
          .flatMap(Bundle.init(path:)).map { (language, $0) }
      })
  }()
  public static func text(_ value: MusicLocalizedText) -> String {
    text(value, language: MusicLanguage.selected())
  }
  public static func text(
    _ value: MusicLocalizedText, language: MusicLanguage,
    preferredLanguages: [String] = Locale.preferredLanguages
  ) -> String {
    let identifier = language.resolvedIdentifier(preferredLanguages: preferredLanguages)
    let format =
      bundles[identifier]?.localizedString(forKey: value.key, value: value.key, table: nil)
      ?? value.key
    return String(
      format: format, locale: Locale(identifier: identifier), arguments: value.arguments)
  }
}
