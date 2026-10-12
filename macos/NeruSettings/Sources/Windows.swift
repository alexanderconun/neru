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
    /// The last other app to come to the front, to hand focus back to.
    private static var previous: NSRunningApplication?
    private static let hider = Hider()

    static func show(_ name: String) {
        if windows.isEmpty {
            installMainMenu()
            migrateDefaults()
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { if let app, app != .current { previous = app } }
            }
        }
        let window = windows[name] ?? make(name)
        windows[name] = window
        // A banner left up when the windows closed is old news.
        if !window.isVisible { neru.error = nil }
        // The Tutorial and Training start over at each opening; their view
        // goes when they close, which also ends their watch (onDisappear).
        if window.contentViewController == nil {
            // A new view shrinks the window to its unlaid-out size, and the
            // window then grows back from wherever that left it: keep the frame.
            let frame = window.frame
            window.contentViewController = hosting(name)
            window.setFrame(frame, display: false)
        }
        // Not right over another of ours, which it would hide: Training opens
        // from the Tutorial, both centred at the same size.
        if !window.isVisible, let under = windows.values.first(where: {
            $0 !== window && $0.isVisible && $0.isOnActiveSpace && window.frame.contains($0.frame)
        }) {
            window.cascadeTopLeft(from: under.cascadeTopLeft(from: .zero))
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
        let controller = hosting(name)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = settings
            ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            : [.titled, .closable, .miniaturizable]
        window.title = "\(Neru.appName) \(settings ? "Settings" : name == "tutorial" ? "Tutorial" : "Training")"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        // The window is 1 pt wide until SwiftUI first lays out; centred like
        // that, it would grow rightwards from the middle of the screen.
        window.setContentSize(controller.view.fittingSize)
        window.center()
        window.setFrameAutosaveName(name)
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { closed(name) }
        }
        // Read the config again whenever the user comes back to a window, not
        // when the daemon activates for anything else (hint search does).
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { neru.refresh() }
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
        if !othersOpen { giveFocusBack() }
    }

    /// Orders every window out, for ⌘H. Hiding the app instead would not
    /// last: the next hint overlay to come up unhides it, windows and all.
    fileprivate static func hideAll() {
        for window in windows.values { window.orderOut(nil) }
        giveFocusBack()
    }

    /// Hands the focus on, as quitting the old settings app did. Only while
    /// ours: a window closed in the background takes nothing from anyone.
    private static func giveFocusBack() {
        guard NSApp.isActive else { return }
        if let previous, !previous.isTerminated { previous.activate() } else { NSApp.hide(nil) }
    }

    /// An accessory app has no menu bar, but its main menu still answers key
    /// equivalents: this one gives text fields ⌘C, ⌘V and the rest, and the
    /// windows ⌘W, ⌘M and ⌘H. Its first item is the app menu while an alert
    /// makes the app regular. No Quit: that would quit the daemon.
    private static func installMainMenu() {
        let menu = NSMenu()
        for (title, items) in [
            (Neru.appName, [("Hide \(Neru.appName)", "hideWindows:", "h", false)]),
            ("Edit", [
                ("Undo", "undo:", "z", false), ("Redo", "redo:", "z", true),
                ("Cut", "cut:", "x", false), ("Copy", "copy:", "c", false), ("Paste", "paste:", "v", false),
                ("Select All", "selectAll:", "a", false),
            ]),
            ("Window", [("Minimize", "performMiniaturize:", "m", false), ("Close", "performClose:", "w", false)]),
        ] {
            let submenu = NSMenu(title: title)
            for (title, action, key, shift) in items {
                let item = submenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
                if shift { item.keyEquivalentModifierMask = [.command, .shift] }
                if action == "hideWindows:" { item.target = hider }
            }
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
        }
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

/// The target of Hide: no responder in the chain knows hideWindows:.
@MainActor
private final class Hider: NSObject {
    @objc func hideWindows(_: Any?) { Windows.hideAll() }
}
