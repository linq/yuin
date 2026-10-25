import AppKit
import MusicCore
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  weak var model: AppModel?
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    // Development builds can reuse a bundle path while Icon Services keeps the
    // previous artwork. Load this build's icon for the Dock and About panel.
    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
      let icon = NSImage(contentsOf: url)
    {
      NSApp.applicationIconImage = icon
    }
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    model?.shutdown()
    return .terminateNow
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main struct MyMusicApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var model = AppModel()
  @AppStorage(MusicLanguage.preferenceKey) private var language: MusicLanguage = .system
  @AppStorage("appearanceMode") private var appearance: MusicAppearance = .system
  var body: some Scene {
    WindowGroup(L10n.text("余音")) {
      ContentView().environment(\.locale, language.locale).environmentObject(model).tint(.pink)
        .controlSize(.small).frame(
          minWidth: 760, minHeight: 460
        )
        .onAppear {
          delegate.model = model
          appearance.apply()
        }
        .onChange(of: appearance) { _, mode in mode.apply() }
    }
    .defaultSize(width: 1220, height: 800)
    .windowToolbarStyle(.unified)
    .commands {
      CommandGroup(replacing: .appInfo) {
        Button(L10n.text("关于余音")) {
          NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: L10n.text("余音"),
            .applicationIcon: NSApp.applicationIconImage as Any,
          ])
        }
      }
      CommandGroup(after: .windowSize) {
        Button(L10n.text("调整窗口大小…")) { WindowSizing.present() }
          .keyboardShortcut("r", modifiers: [.command, .option])
      }
      CommandGroup(after: .textEditing) {
        Button(L10n.text("搜索音乐…")) {
          NotificationCenter.default.post(name: .focusMusicSearch, object: nil)
        }.keyboardShortcut("f")
      }
      CommandGroup(after: .newItem) {
        Button(L10n.text("新建列表")) { model.createPlaylist(L10n.text("新建列表")) }.keyboardShortcut("n")
        Button(L10n.text("导入音乐源…")) { model.importLocal() }.keyboardShortcut(
          "i", modifiers: [.command, .shift])
      }
      CommandMenu(L10n.text("外观")) {
        Picker(L10n.text("外观模式"), selection: $appearance) {
          ForEach(MusicAppearance.allCases) { Text($0.name).tag($0) }
        }
      }
      CommandMenu(L10n.text("语言")) {
        Picker(L10n.text("应用语言"), selection: $language) {
          ForEach(MusicLanguage.allCases) { Text($0.name).tag($0) }
        }
      }
      CommandMenu(L10n.text("播放")) {
        Button(model.isPlaying ? L10n.text("暂停") : L10n.text("播放")) { model.togglePlayback() }
          .keyboardShortcut(
            .space, modifiers: [])
        Button(L10n.text("下一首")) { model.next() }.keyboardShortcut(
          .rightArrow, modifiers: [.command])
        Button(L10n.text("上一首")) { model.next(backward: true) }.keyboardShortcut(
          .leftArrow, modifiers: [.command])
        Button(L10n.text("待播队列")) { model.showQueue.toggle() }.keyboardShortcut(
          "u", modifiers: [.command])
      }
    }
    Settings {
      SettingsView().environment(\.locale, language.locale).environmentObject(model)
        .onChange(of: appearance) { _, mode in mode.apply() }
    }
  }
}

extension Notification.Name {
  static let backInMusicCatalog = Notification.Name("MyMusic.backInCatalog")
  static let focusMusicSearch = Notification.Name("MyMusic.focusSearch")
}
