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

/// The Settings window's error banner, for a practice window.
struct PracticeBanners: View {
    @EnvironmentObject var neru: Neru

    var body: some View {
        if let error = neru.error {
            Banner(text: error, action: ("Dismiss", { neru.error = nil }))
        }
    }
}

extension Neru {
    /// Follows the daemon's watch stream while a practice window is open:
    /// each window counts itself in and out, and the last one out stops it.
    /// A stream that ends by itself (the daemon is shutting down) is retried
    /// every 2 s.
    func watchModes(_ open: Bool) {
        watchers = max(watchers + (open ? 1 : -1), 0)
        if watchers > 0 {
            startWatch()
        } else {
            endWatch()
        }
    }

    /// Starts the mode a tutorial step practises, as its shortcut would.
    func runMode(_ args: [String]) {
        guard let action = args.first else { return }
        error = nil
        queue.async {
            let result = self.send(action, Array(args.dropFirst()))
            if !result.ok { DispatchQueue.main.async { self.error = result.out } }
        }
    }

    /// Reads the scroll direction the daemon uses now into scrollInverted.
    func readScrollInverted() {
        queue.async {
            let inverted = Self.json(self.send("status").out)?["scroll_inverted"] as? Bool
            DispatchQueue.main.async { self.scrollInverted = inverted }
        }
    }

    private func startWatch() {
        guard watchers > 0, stopWatch == nil, let link = Self.link else { return }
        watchID += 1
        let id = watchID
        stopWatch = link.watch { line in
            guard self.watchID == id else { return } // stopped on purpose
            guard let line else {
                self.endWatch()
                self.modeEvents.send((mode: "idle", entered: true))
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.startWatch() }
                return
            }
            if let event = Self.json(line) { self.handleWatchEvent(event) }
        }
    }

    /// Stops the watch, whose own end calls this too: the stop function
    /// frees the stream either way, and must run once.
    private func endWatch() {
        watchID += 1
        stopWatch?()
        stopWatch = nil
    }

    private func handleWatchEvent(_ event: [String: Any]) {
        switch event["event"] as? String {
        case "snapshot":
            // The first line, and the state after missed events: the mode as it is now.
            modeEvents.send((mode: (event["status"] as? [String: Any])?["mode"] as? String ?? "idle", entered: true))
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
