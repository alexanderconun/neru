import AppKit
import SwiftUI

// What the Tutorial and Training windows share: targets that report how they
// were clicked, and the daemon's mode from `neru watch`.

enum ClickKind { case left, right, middle }

/// A real NSButton titled `title`, so it is an AXButton that labels and search
/// find, which reports the mouse button that pressed it: a SwiftUI Button
/// never sees a right-click. `highlighted` tints it in the accent colour.
struct PracticeButton: View {
    let title: String
    var highlighted = false
    var enabled = true
    let onClick: (ClickKind) -> Void

    var body: some View {
        ClickButtonView(title: title, enabled: enabled, onClick: onClick)
            .background {
                if highlighted { RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.35)).padding(-4) }
            }
    }
}

private struct ClickButtonView: NSViewRepresentable {
    let title: String
    let enabled: Bool
    let onClick: (ClickKind) -> Void

    func makeNSView(context: Context) -> ClickButton { ClickButton() }

    func updateNSView(_ button: ClickButton, context: Context) {
        button.title = title
        button.isEnabled = enabled
        button.onClick = onClick
    }
}

final class ClickButton: NSButton {
    var onClick: ((ClickKind) -> Void)?

    init() {
        super.init(frame: .zero)
        bezelStyle = .push
        target = self
        action = #selector(leftClick)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func leftClick() { onClick?(.left) }

    // A disabled control still gets these; only the left click checks itself.
    override func rightMouseDown(with event: NSEvent) { if isEnabled { onClick?(.right) } }
    override func otherMouseDown(with event: NSEvent) { if isEnabled { onClick?(.middle) } }
}

/// A clickable dot `size` across that is deliberately not a button: no
/// accessibility role, so labels never land on it and only the grid can
/// reach it. Its view is DotView.side across around the drawn dot: a grid's
/// subgrid square (up to 40 pt) clicks its middle, which may be off the dot.
struct PracticeDot: NSViewRepresentable {
    var enabled = true
    var size: CGFloat = 18
    let onClick: (ClickKind) -> Void

    func makeNSView(context: Context) -> DotView { DotView() }

    func updateNSView(_ dot: DotView, context: Context) {
        dot.enabled = enabled
        dot.size = size
        dot.onClick = onClick
        dot.needsDisplay = true
    }
}

final class DotView: NSView {
    static let side: CGFloat = 44
    var enabled = true
    var size: CGFloat = 18
    var onClick: ((ClickKind) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        (enabled ? NSColor.controlAccentColor : .tertiaryLabelColor).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2, width: size, height: size)).fill()
    }

    override func isAccessibilityElement() -> Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { if enabled { onClick?(.left) } }
    override func rightMouseDown(with event: NSEvent) { if enabled { onClick?(.right) } }
    override func otherMouseDown(with event: NSEvent) { if enabled { onClick?(.middle) } }
}

/// An empty AppKit view to put behind a SwiftUI one, to find it on screen.
/// It is never hit, so the view in front gets every event.
final class AnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct ViewAnchor: NSViewRepresentable {
    let view: AnchorView
    func makeNSView(context: Context) -> AnchorView { view }
    func updateNSView(_ nsView: AnchorView, context: Context) {}
}

/// A rounded section like a grouped Form's.
struct PracticeCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// The Settings window's banners, for a practice window: it does nothing
/// while the daemon is down.
struct PracticeBanners: View {
    @EnvironmentObject var neru: Neru

    var body: some View {
        if neru.needsAccessibility {
            Banner(text: "\(Neru.appName) needs Accessibility permission. Turn \(Neru.appName) on in System Settings; it starts on its own once you do.",
                   action: ("Open System Settings", { NSWorkspace.shared.open(Neru.accessibilitySettingsURL) }))
        } else if !neru.running, neru.binary == nil {
            Banner(text: "Could not find \(Neru.appName). Install it in Applications, or set NERU_BIN.")
        } else if !neru.running {
            Banner(text: neru.notRunningReason, action: ("Start \(Neru.appName)", neru.start))
        }
        if let error = neru.error {
            Banner(text: error, action: ("Dismiss", { neru.error = nil }))
        }
    }
}

extension Neru {
    /// Follows `neru watch` while a practice window is open: each window
    /// counts itself in and out, and the last one out stops it. A watch that
    /// ends (the daemon quit, or is not up yet) is retried every 2 s.
    func watchModes(_ open: Bool) {
        watchers = max(watchers + (open ? 1 : -1), 0)
        if watchers > 0 {
            startWatch()
        } else {
            watcher?.terminate()
            watcher = nil
        }
    }

    /// Starts the mode a tutorial step practises, as its shortcut would.
    func runMode(_ args: [String]) {
        error = nil
        queue.async {
            let result = self.run(args)
            if !result.ok { DispatchQueue.main.async { self.error = result.out } }
        }
    }

    /// Has labels that are up read the window again, after a practice board
    /// changed under them: `hints` while hints is open scans again in place
    /// and keeps the flags it was opened with. That drops a search, so
    /// `search` (the Search round) opens it again.
    func relabel(search: Bool) {
        // ponytail: a fixed pause for the new board to be drawn and for a
        // label's own click to close its mode first. Not atomic, as the CLI
        // has no "scan again only while open" and status reports neither a
        // search in progress nor the flags labels were opened with: labels
        // closed in the few ms between the status read and `hints` open
        // again, and a search opened outside the Search round is dropped.
        // A daemon flag would close both; homekey-rs does it in-process.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.queue.async {
                guard Self.json(self.run(["status", "--json"]).out)?["mode"] as? String == "hints" else { return }
                _ = self.run(search ? ["hints", "--search"] : ["hints"])
            }
        }
    }

    /// Reads the scroll direction the daemon uses now into scrollInverted.
    func readScrollInverted() {
        queue.async {
            let inverted = Self.json(self.run(["status", "--json"]).out)?["scroll_inverted"] as? Bool
            DispatchQueue.main.async { self.scrollInverted = inverted }
        }
    }

    private func startWatch() {
        guard watchers > 0, watcher == nil else { return }
        guard let binary else { return retryWatch() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["watch"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var pending = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            pending.append(data)
            while let end = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let event = Self.json(String(decoding: pending[..<end], as: UTF8.self))
                pending.removeSubrange(...end)
                if let event { DispatchQueue.main.async { self.handleWatchEvent(event) } }
            }
        }
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                guard self.watcher === process else { return } // stopped on purpose
                self.watcher = nil
                self.modeEvents.send((mode: "idle", entered: true))
                if self.running { self.refresh() } // the daemon went away
                self.retryWatch()
            }
        }
        do {
            try process.run()
            watcher = process
        } catch {
            retryWatch()
        }
    }

    private func retryWatch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.startWatch() }
    }

    private func handleWatchEvent(_ event: [String: Any]) {
        switch event["event"] as? String {
        case "snapshot":
            // The first line, and the state after missed events: the mode as it is now.
            modeEvents.send((mode: (event["status"] as? [String: Any])?["mode"] as? String ?? "idle", entered: true))
            if !running { refresh() } // the daemon came (back) up, maybe on another config
        case "mode_enter":
            modeEvents.send((mode: event["mode"] as? String ?? "", entered: true))
        case "mode_exit":
            modeEvents.send((mode: event["mode"] as? String ?? "", entered: false))
        case "config_reload":
            background { nil } // re-reads the dump, so the instructions follow
            readScrollInverted() // a reload puts the config's direction back
        default:
            break
        }
    }
}
