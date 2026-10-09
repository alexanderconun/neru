import Foundation

/// The hints launchers in [hotkeys], by role. Every toggle on the Clicking
/// page is a flag on one of these command strings, so no config option exists
/// for them: the page reads the flags back out of the dump and rewrites the
/// whole managed set at once.
///
/// A launcher is managed only when its command is `hints` with flags from the
/// short list below; anything else (`--role`, a step array, a macro) is the
/// user's own and is never touched or shown.
extension Neru {
    enum LauncherRole: CaseIterable {
        case main, search, rightClick, doubleClick

        var title: String {
            switch self {
            case .main: "Shortcut"
            case .search: "Search shortcut"
            case .rightClick: "Right-click shortcut"
            case .doubleClick: "Double-click shortcut"
            }
        }
    }

    /// One `hints …` command, read token by token: the dump keeps the user's
    /// spelling (`-a`, `--action=`, flag order), so strings are never compared.
    struct Launcher: Equatable {
        var action: String?
        var repeats = false
        var search = false
        var hideOnEmpty = false

        /// Right- and double-click launchers are one-shot: chaining a
        /// right-click would right-click the menu it opened. A user's
        /// `--repeat` on one is left alone as an unmanaged line.
        var role: LauncherRole? {
            if hideOnEmpty && !search { return nil }
            switch (action, search) {
            case (nil, true), ("left_click", true): return .search
            case (nil, false), ("left_click", false): return .main
            case ("right_click", false): return repeats ? nil : .rightClick
            case ("left_click,left_click", false): return repeats ? nil : .doubleClick
            default: return nil
            }
        }
    }

    /// The launcher set the page edits: one combo per role, plus the toggles.
    struct Launchers: Equatable {
        var combos: [LauncherRole: String] = [:]
        var autoClick = false
        var chain = false
        var hideLabels = false
    }

    /// nil unless `steps` is a single `hints` command made only of the flags
    /// this page manages.
    static func parseLauncher(_ steps: [String]) -> Launcher? {
        guard steps.count == 1 else { return nil }
        var words = steps[0].split(whereSeparator: \.isWhitespace).map(String.init)[...]
        guard words.popFirst() == "hints" else { return nil }
        var launcher = Launcher()
        if let first = words.first, !first.hasPrefix("-") { launcher.action = words.popFirst() }
        while let word = words.popFirst() {
            switch word {
            case "--action", "-a":
                guard launcher.action == nil, let value = words.popFirst() else { return nil }
                launcher.action = value
            case _ where word.hasPrefix("--action="):
                guard launcher.action == nil else { return nil }
                launcher.action = String(word.dropFirst("--action=".count))
            case "--repeat", "-r": launcher.repeats = true
            case "--search", "-s": launcher.search = true
            case "--hide-on-empty-search": launcher.hideOnEmpty = true
            default: return nil
            }
        }
        return launcher
    }

    /// The managed launchers in `bindings`, and every combo bound to one of
    /// them (more than one per role when the user doubled up). The toggles
    /// are read from the main launcher, or the search one when there is none.
    static func launchers(in bindings: [String: [String]]) -> (set: Launchers, bound: [String]) {
        var set = Launchers()
        var bound: [String] = []
        var first: [LauncherRole: Launcher] = [:]
        for combo in bindings.keys.sorted() {
            guard let launcher = parseLauncher(bindings[combo]!), let role = launcher.role else { continue }
            bound.append(combo)
            if first[role] == nil { first[role] = launcher; set.combos[role] = combo }
        }
        let clicker = first[.main] ?? first[.search]
        set.autoClick = clicker?.action != nil
        set.chain = set.autoClick && clicker?.repeats == true
        set.hideLabels = first[.search]?.hideOnEmpty ?? false
        return (set, bound)
    }

    /// The command `role` runs. Only ever writes an action name the daemon
    /// knows (a bad one makes it refuse the whole config), and never a flag
    /// whose companion is missing (`--repeat` needs `--action`,
    /// `--hide-on-empty-search` needs `--search`).
    static func launcherCommand(_ role: LauncherRole, _ set: Launchers) -> String {
        var words = ["hints"]
        switch role {
        case .main, .search:
            if set.autoClick { words += ["--action", "left_click"] }
            if set.autoClick && set.chain { words.append("--repeat") }
        case .rightClick: words += ["--action", "right_click"]
        case .doubleClick: words += ["--action", "left_click,left_click"]
        }
        if role == .search {
            words.append("--search")
            if set.hideLabels { words.append("--hide-on-empty-search") }
        }
        return words.joined(separator: " ")
    }

    /// Returns `toml` with the managed launchers in [hotkeys] replaced by
    /// `set`. `bound` is every combo the daemon has bound to a managed role.
    /// The main launcher is always written: any `hints` line in the file
    /// drops the default one, so leaving it implicit would lose it. A default
    /// combo given up is disabled, or its default binding would come back.
    static func rewriteLaunchers(_ toml: String, bound: [String], to set: Launchers) -> String {
        let lines = LauncherRole.allCases.compactMap { role in set.combos[role].map { ($0, launcherCommand(role, set)) } }
        let keys = toml.components(separatedBy: "\n").compactMap(tomlKey)
        let taken = Set(lines.map { comboKey($0.0) })
        var freed = Set(bound.map(comboKey)).subtracting(taken)
        // No main launcher: once no hints line is left the default one comes
        // back (and a [hotkeys] table left empty unbinds every shortcut), so
        // its chord is disabled unless the file already binds it.
        let mainDefault = comboKey(defaultHotkeys.first { $0.value == "hints" }!.key)
        if set.combos[.main] == nil, !taken.contains(mainDefault), !keys.contains(where: { comboKey($0) == mainDefault }) {
            freed.insert(mainDefault)
        }
        let disabled = defaultHotkeys.keys.sorted().filter { freed.contains(comboKey($0)) }
        // Matched by chord, not spelling, so a stale "__disabled__" or another
        // casing of a combo being written is replaced rather than duplicated.
        let touched = taken.union(freed)
        let stale = keys.filter { touched.contains(comboKey($0)) }
        return editTable(toml, header: "hotkeys", removing: Set(bound + stale),
                         adding: lines.map { tomlLine($0.0, $0.1) } + disabled.map { tomlLine($0, "__disabled__") })
    }

    /// Why `combo` cannot become `role`'s shortcut, or nil when it is free
    /// (or already one of `role`'s own).
    static func launcherConflict(_ combo: String, for role: LauncherRole, in bindings: [String: [String]]) -> String? {
        guard let hit = bindings.first(where: { comboKey($0.key) == comboKey(combo) }) else { return nil }
        let owner = parseLauncher(hit.value)?.role
        if owner == role { return nil }
        let user = owner.map { "the \($0.title.lowercased())" } ?? "\"\(hit.value.joined(separator: "\", \""))\""
        return "\(Shortcut.display(hit.key)) is already used by \(user). Change or clear that one first."
    }

    /// A combo as the loader compares them: case-insensitive, Primary is Cmd.
    // ponytail: only Primary is aliased; the loader's other aliases (Option, Control, …) compare as different.
    static func comboKey(_ combo: String) -> String {
        combo.lowercased().split(separator: "+").map { $0 == "primary" ? "cmd" : String($0) }.joined(separator: "+")
    }

    // MARK: in-mode keys

    /// What a [hints.hotkeys] binding does, in words; unknown steps read as written.
    static func describeModeKey(_ steps: [String]) -> String {
        steps.map(describeModeStep).joined(separator: ", then ")
    }

    static func describeModeStep(_ step: String) -> String {
        let words = step.split { $0.isWhitespace || $0 == "=" }.map(String.init)
        if words == ["idle"] { return "Close labels" }
        guard words.count >= 2, words[0] == "action" else { return step }
        let flags = Array(words.dropFirst(2))
        if let button = ["left_click": "left", "right_click": "right", "middle_click": "middle"][words[1]] {
            switch flags {
            case []: return button.capitalized + " click"
            case ["--state", "down"]: return "Press \(button) button (start drag)"
            case ["--state", "up"]: return "Release \(button) button (end drag)"
            default: return step
            }
        }
        switch (words[1], flags) {
        case ("search_hints", []): return "Search labels"
        case ("backspace", []): return "Delete last typed letter"
        case ("cycle_hint", []): return "Next label"
        case ("cycle_hint", ["--backward"]): return "Previous label"
        case ("move_mouse_relative", _): return "Nudge pointer"
        default: return step
        }
    }

    /// Cheat-sheet rows for a mode's hotkey table: keys that do the same
    /// thing share a row (the four arrows are one "Nudge pointer").
    static func cheatSheet(_ table: [String: [String]]) -> [(keys: String, what: String)] {
        Dictionary(grouping: table.keys) { describeModeKey(table[$0]!) }
            .map { (keys: $0.value.map(Shortcut.display).sorted().joined(separator: " "), what: $0.key) }
            .sorted { $0.what < $1.what }
    }

    // MARK: reading and writing

    var hotkeyBindings: [String: [String]] {
        (value("hotkeys.bindings") as? [String: Any] ?? [:]).compactMapValues { $0 as? [String] }
    }

    var launchers: Launchers { Self.launchers(in: hotkeyBindings).set }

    /// Rewrites the whole managed launcher set as `set`.
    func setLaunchers(_ set: Launchers) {
        var bindings = hotkeyBindings
        let (current, bound) = Self.launchers(in: bindings)
        guard set != current else { return }
        for combo in bound { bindings[combo] = nil }
        for (role, combo) in set.combos { bindings[combo] = [Self.launcherCommand(role, set)] }
        setLocal("hotkeys.bindings", bindings)
        editConfigText { Self.rewriteLaunchers($0, bound: bound, to: set) }
    }

    /// Moves `role` to `combo`, or removes it when nil. A combo bound to
    /// anything else is refused rather than overwritten.
    func setLauncher(_ role: LauncherRole, to combo: String?) {
        if let combo, let conflict = Self.launcherConflict(combo, for: role, in: hotkeyBindings) {
            error = conflict
            return
        }
        var set = launchers
        set.combos[role] = combo
        setLaunchers(set)
    }
}
