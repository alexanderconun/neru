import SwiftUI

/// Scroll mode's keys live in config.toml's [scroll.hotkeys] table, which
/// `config set` cannot write, so they go through `editConfigText`.
extension Neru {
    /// The order the scroll keys are typed in: the h j k l order.
    static let scrollDirections = ["left", "down", "up", "right"]
    static let arrowKeys = ["Left", "Down", "Up", "Right"]

    // ponytail: mirrors defaultScroll() in internal/config/config_defaults.go;
    // needed to know which keys must be written as __disabled__ and what the
    // arrow keys go back to.
    static let defaultScrollHotkeys: [String: String] = [
        "Escape": "idle",
        "k": "action scroll_up",
        "j": "action scroll_down",
        "h": "action scroll_left",
        "l": "action scroll_right",
        "gg": "action go_top",
        "Shift+G": "action go_bottom",
        "u": "action page_up",
        "PageUp": "action page_up",
        "d": "action page_down",
        "PageDown": "action page_down",
        "Shift+L": "action left_click",
        "Shift+R": "action right_click",
        "Shift+M": "action middle_click",
        "Shift+I": "action left_click --state down",
        "Shift+U": "action left_click --state up",
        "Up": "action move_mouse_relative --dx=0 --dy=-10",
        "Down": "action move_mouse_relative --dx=0 --dy=10",
        "Left": "action move_mouse_relative --dx=-10 --dy=0",
        "Right": "action move_mouse_relative --dx=10 --dy=0",
    ]

    /// h, j, k, l: the default key of each direction.
    static let defaultScrollKeys = scrollDirections.map { dir in
        defaultScrollHotkeys.first { $0.value == "action scroll_\(dir)" }!.key
    }

    /// A mode's hotkeys as the daemon has them: key → steps.
    func hotkeys(_ mode: String) -> [String: [String]] { Self.hotkeys(mode, in: config) }

    static func hotkeys(_ mode: String, in dump: [String: Any]) -> [String: [String]] {
        value("\(mode).hotkeys", in: dump) as? [String: [String]] ?? [:]
    }

    /// The scroll keys as the window shows them, left, down, up, right: "HJKL".
    var scrollKeys: String {
        Self.directionKeys(hotkeys("scroll")).map { $0.first ?? "" }.joined().uppercased()
    }

    var arrowsScroll: Bool { Self.arrowsScroll(in: hotkeys("scroll")) }

    func setScrollKeys(_ keys: String) {
        let bindings = hotkeys("scroll")
        var local = bindings
        for key in Self.directionKeys(bindings).joined() { local[key] = nil }
        for (key, dir) in zip(keys.lowercased(), Self.scrollDirections) { local[String(key)] = ["action scroll_\(dir)"] }
        setLocal("scroll.hotkeys", local)
        editConfigText { text, fresh in
            let bindings = Self.hotkeys("scroll", in: fresh)
            if let problem = Self.scrollKeysProblem(keys, bindings: bindings) { throw ConfigEditError(errorDescription: problem) }
            return Self.rewriteScrollKeys(text, to: keys, bindings: bindings)
        }
    }

    func setArrowsScroll(_ scroll: Bool) {
        var local = hotkeys("scroll").filter { key, _ in !Self.arrowKeys.contains { $0.lowercased() == key.lowercased() } }
        for (key, dir) in zip(Self.arrowKeys, Self.scrollDirections) {
            local[key] = [scroll ? "action scroll_\(dir)" : Self.defaultScrollHotkeys[key]!]
        }
        setLocal("scroll.hotkeys", local)
        editConfigText { text, _ in Self.rewriteArrows(text, scroll: scroll) }
    }

    // MARK: pure helpers (covered by Tests/ScrollTests.swift)

    /// Every single-character key bound to each direction, in `scrollDirections` order.
    static func directionKeys(_ bindings: [String: [String]]) -> [[String]] {
        scrollDirections.map { dir in
            bindings.filter { $0.key.count == 1 && $0.value == ["action scroll_\(dir)"] }.keys.sorted()
        }
    }

    /// Named keys match case-insensitively, so the file may spell an arrow "up".
    static func arrowsScroll(in bindings: [String: [String]]) -> Bool {
        zip(arrowKeys, scrollDirections).allSatisfy { arrow, dir in
            bindings.contains { $0.key.lowercased() == arrow.lowercased() && $0.value == ["action scroll_\(dir)"] }
        }
    }

    /// Why `keys` can't become the scroll keys, or nil. `bindings` is the
    /// daemon's scroll table; the four directions themselves may be reshuffled.
    static func scrollKeysProblem(_ keys: String, bindings: [String: [String]]) -> String? {
        guard keys.count == 4 else { return "Type four keys: left, down, up, right." }
        // A lone "+" is read as a modifier combo with no modifier, which the loader refuses.
        if keys.contains("+") { return "+ joins modifier keys, so it can't be a scroll key." }
        let directions = Set(scrollDirections.map { ["action scroll_\($0)"] })
        return keysProblem(keys, bound: bindings.filter { !directions.contains($0.value) })
    }

    /// Why `keys` can't be the one-key choices of a mode, or nil. Each must be
    /// printable ASCII and used once (case is folded wherever keys are matched),
    /// and must not be, or start, one of the mode's own hotkeys in `bound`:
    /// those are matched first, so the key would never get through.
    static func keysProblem(_ keys: String, bound: [String: [String]]) -> String? {
        var seen = Set<Character>()
        for key in keys.lowercased() {
            guard let ascii = key.asciiValue, (0x21...0x7E).contains(ascii) else {
                return "Use letters, digits and punctuation only."
            }
            guard seen.insert(key).inserted else { return "\(key.uppercased()) is there twice." }
            let taken = bound.first { name, _ in
                let name = name.lowercased()
                // A two-letter sequence ("gg") starts with its first key; "Up" is a named key, not a sequence.
                let sequence = name.count == 2 && name.allSatisfy(\.isLetter) && name != "up"
                return name == String(key) || (sequence && name.first == key)
            }
            if let taken {
                return "\(key.uppercased()) is taken: \(taken.key) runs \(taken.value.joined(separator: ", ")) in this mode."
            }
        }
        return nil
    }

    /// Returns `toml` with the four directions on `keys` (left, down, up, right)
    /// in its [scroll.hotkeys] table; `bindings` is the table the daemon has now.
    /// A default key left without a direction is written as __disabled__, since
    /// a default missing from the file comes back. The table always keeps the
    /// four direction lines: an empty one would clear Escape too.
    static func rewriteScrollKeys(_ toml: String, to keys: String, bindings: [String: [String]]) -> String {
        let new = keys.lowercased().map(String.init)
        let old = directionKeys(bindings).joined().map { $0.lowercased() }
        // A default key bound by hand to something else is left alone; the dump
        // keeps the file's spelling, so "H" = … binds h.
        let bound = Set(bindings.keys.map { $0.lowercased() })
        let unused = defaultScrollKeys.filter { !new.contains($0) && (old.contains($0) || !bound.contains($0)) }
        let lines = zip(new, scrollDirections).map { tomlLine($0, "action scroll_\($1)") }
            + unused.map { tomlLine($0, "__disabled__") }
        return editTable(toml, header: "scroll.hotkeys", removing: spellings(old + new + unused), adding: lines)
    }

    /// Returns `toml` with the arrow keys scrolling, or with their lines
    /// removed so the defaults (moving the pointer) apply.
    static func rewriteArrows(_ toml: String, scroll: Bool) -> String {
        let lines = zip(arrowKeys, scrollDirections).map {
            tomlLine($0, scroll ? "action scroll_\($1)" : defaultScrollHotkeys[$0]!)
        }
        let edited = editTable(toml, header: "scroll.hotkeys", removing: spellings(arrowKeys), adding: scroll ? lines : [])
        // An empty [scroll.hotkeys] clears every scroll binding, Escape included:
        // when the arrows were all it held, spell out their defaults instead.
        return tableKeys(edited, header: "scroll.hotkeys").isEmpty
            ? editTable(toml, header: "scroll.hotkeys", removing: spellings(arrowKeys), adding: lines)
            : edited
    }

    /// Keys normalize case-insensitively, so the file may spell one any way.
    static func spellings(_ keys: [String]) -> Set<String> {
        Set(keys.flatMap { [$0, $0.lowercased(), $0.uppercased()] })
    }
}

/// A text field that commits on Return or focus loss, and only once `problem`
/// has nothing to say; otherwise it says why under the field and sends nothing.
/// Case is ignored when comparing: every key list it edits is matched folded.
struct CheckedTextRow: View {
    let title: String
    var help: String?
    let saved: String
    let problem: (String) -> String?
    let commit: (String) -> Void
    @State private var text = ""
    @State private var message: String?
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing) {
                TextField(title, text: $text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .focused($focused)
                    .onSubmit(submit)
                    .onChange(of: focused) { _, isFocused in if !isFocused { submit() } }
                if let message { Text(message).font(.caption).foregroundStyle(.red) }
            }
        } label: {
            HelpLabel(title, help: help)
        }
        .onAppear { text = saved }
        .onChange(of: saved) { _, saved in if !focused { text = saved } } // snaps back if refused
    }

    private func submit() {
        guard text.lowercased() != saved.lowercased() else { text = saved; message = nil; return }
        message = problem(text)
        if message == nil { commit(text) }
    }
}
