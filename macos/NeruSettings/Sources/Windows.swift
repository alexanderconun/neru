import AppKit
import SwiftUI

/// The Settings, Tutorial and Training windows, which the daemon shows in its
/// own process (App.swift). Plain AppKit windows hosting SwiftUI, one per
/// name, made on first use and kept: the daemon owns NSApp, so there are no
/// SwiftUI scenes, and closing the last window never quits it.
@MainActor
enum Windows {
    static let neru = Neru()
    private static var windows: [String: NSWindow] = [:]
    /// The app that was in front before ours, to hand focus back to.
    private static var previous: NSRunningApplication?

    static func show(_ name: String) {
        if windows.isEmpty {
            installEditMenu()
            migrateDefaults()
        }
        let window = windows[name] ?? make(name)
        windows[name] = window
        // The Tutorial and Training start over at each opening; their view
        // goes when they close, which also ends their watch (onDisappear).
        if window.contentViewController == nil {
            window.contentViewController = hosting(name)
        }
        neru.exitMode()
        neru.refresh()
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { previous = front }
        // Plain activate() is refused without a click of ours to answer: the
        // menu click reaches here through a goroutine, the first-run Tutorial
        // with no input at all.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func close(_ name: String) {
        windows[name]?.performClose(nil)
    }

    private static func make(_ name: String) -> NSWindow {
        let settings = name == "settings"
        let window = NSWindow(contentViewController: hosting(name))
        window.styleMask = settings
            ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            : [.titled, .closable, .miniaturizable]
        window.title = "\(Neru.appName) \(settings ? "Settings" : name == "tutorial" ? "Tutorial" : "Training")"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        window.setFrameAutosaveName(name)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { closed(name) }
        }
        return window
    }

    private static func hosting(_ name: String) -> NSViewController {
        switch name {
        case "tutorial": return NSHostingController(rootView: TutorialView().environmentObject(neru))
        case "training": return NSHostingController(rootView: TrainingView().environmentObject(neru))
        default:
            let controller = NSHostingController(rootView: ContentView().environmentObject(neru).frame(minWidth: 720, minHeight: 520))
            // The page title and the sidebar's toolbar go to the window, as a scene's do.
            controller.sceneBridgingOptions = .all
            return controller
        }
    }

    private static func closed(_ name: String) {
        let window = windows[name]
        if name != "settings" {
            // After the close: the window still draws its content until then.
            DispatchQueue.main.async { window?.contentViewController = nil }
        }
        let othersOpen = windows.values.contains { $0 !== window && $0.isVisible && $0.isOnActiveSpace }
        if !othersOpen {
            previous?.activate()
            previous = nil
        }
    }

    /// An accessory app has no menu bar, but its main menu still answers key
    /// equivalents: this one gives text fields ⌘C, ⌘V and the rest, and ⌘W.
    /// No Quit: that would quit the daemon.
    private static func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        for (title, action, key, shift) in [
            ("Undo", "undo:", "z", false), ("Redo", "redo:", "z", true),
            ("Cut", "cut:", "x", false), ("Copy", "copy:", "c", false), ("Paste", "paste:", "v", false),
            ("Select All", "selectAll:", "a", false), ("Close", "performClose:", "w", false),
        ] {
            let item = edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
            if shift { item.keyEquivalentModifierMask = [.command, .shift] }
        }
        let item = NSMenuItem()
        item.submenu = edit
        let menu = NSMenu()
        menu.addItem(item)
        NSApp.mainMenu = menu
    }

    /// The settings app kept its preferences in its own domain; bring over
    /// the ones the daemon's domain lacks. Window frames start afresh.
    private static func migrateDefaults() {
        guard let old = UserDefaults(suiteName: "com.alexanderconun.neru.settings") else { return }
        let keys = [UpdateChecker.autoCheckKey, UpdateChecker.lastCheckKey] + TrainingRound.allCases.map(\.bestKey)
        for key in keys where UserDefaults.standard.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { UserDefaults.standard.set(value, forKey: key) }
        }
    }
}
