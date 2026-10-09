import AppKit
import SwiftUI

/// Neru's hotkey spelling ("Primary+Shift+Space") to and from key events.
enum Shortcut {
    static let namedKeys: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 117: "Delete",
        123: "Left", 124: "Right", 125: "Down", 126: "Up",
        115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// nil when the event has no modifier or no usable key: a global hotkey
    /// without a modifier would steal the key from every app. Shift alone
    /// counts as none (capitals, selecting, Shift+Tab), except on F-keys.
    static func from(_ event: NSEvent) -> String? {
        let flags = event.modifierFlags
        var parts: [String] = []
        // "Primary" is Cmd on macOS and matches how the defaults are written,
        // so re-recording a default replaces it rather than duplicating it.
        if flags.contains(.command) { parts.append("Primary") }
        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.option) { parts.append("Alt") }
        if flags.contains(.shift) { parts.append("Shift") }
        guard !parts.isEmpty, parts != ["Shift"] || namedKeys[event.keyCode]?.first == "F" else { return nil }

        let key = namedKeys[event.keyCode]
            ?? event.characters(byApplyingModifiers: [])?.uppercased()
        guard let key, key.count == 1 || namedKeys.values.contains(key),
              key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0 != " " })
        else { return nil }
        return (parts + [key]).joined(separator: "+")
    }

    /// Mode tables spell keys in any case ("escape", "Shift+Tab").
    static func display(_ combo: String) -> String {
        let symbols = ["primary": "⌘", "cmd": "⌘", "ctrl": "⌃", "alt": "⌥", "shift": "⇧",
                       "up": "↑", "down": "↓", "left": "←", "right": "→", "escape": "⎋",
                       "tab": "⇥", "return": "↩", "enter": "↩", "backspace": "⌫", "delete": "⌫"]
        return combo.split(separator: "+").map { symbols[$0.lowercased()] ?? String($0) }.joined()
    }
}

/// Records a global shortcut. `ShortcutRecorder(mode:)` binds a mode command
/// directly; the `combo:` form leaves the writing to `onRecord` and shows a
/// clear button when `onClear` is given and a combo is set.
struct ShortcutRecorder: View {
    @EnvironmentObject var neru: Neru
    private var mode: String?
    private var combo: String?
    private var onRecord: ((String) -> Void)?
    private var onClear: (() -> Void)?
    @State private var recording = false
    @State private var monitor: Any?

    init(mode: String) { self.mode = mode }

    init(combo: String?, onRecord: @escaping (String) -> Void, onClear: (() -> Void)? = nil) {
        self.combo = combo
        self.onRecord = onRecord
        self.onClear = onClear
    }

    private var current: String? { mode.flatMap(neru.shortcut(for:)) ?? combo }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type shortcut…" : current.map(Shortcut.display) ?? "Record Shortcut")
                    .frame(minWidth: 120)
            }
            if let onClear, current != nil, !recording {
                Button(action: onClear) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless)
                    .help("Remove this shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        neru.pause(true)
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Escape cancels
            guard let combo = Shortcut.from(event) else { NSSound.beep(); return nil }
            stop()
            if let mode { neru.setShortcut(combo, for: mode) } else { onRecord?(combo) }
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        neru.pause(false)
    }
}
