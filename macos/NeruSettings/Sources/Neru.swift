import AppKit
import Carbon
import Combine

/// The daemon's side of the windows. They run inside it (App.swift) and reach
/// it through `link`, with the requests `neru` would send over its socket:
/// `config` to read, `config-set` to write (persisted to config.override.toml
/// by the daemon). Tables (hotkeys, per-app settings) are the exception —
/// `config-set` cannot write them, so they are edited in config.toml directly
/// (ConfigText.swift).
///
/// Feature files extend this class; they reach the daemon only through
/// `set`/`setMany`, `editConfigText`, `send` on `queue` and `background`.
final class Neru: ObservableObject {
    @Published var config: [String: Any] = [:]
    @Published var launchAtLogin = false
    @Published var version = ""
    @Published var error: String?

    /// Each mode_enter (`entered`) and mode_exit from the watch stream, while
    /// a practice window keeps it running (Practice.swift).
    let modeEvents = PassthroughSubject<(mode: String, entered: Bool), Never>()
    var stopWatch: (() -> Void)?
    var watchID = 0
    var watchers = 0
    /// Whether the daemon scrolls inverted now, from `status`; the menu bar
    /// flips it without a config change. nil until read.
    @Published var scrollInverted: Bool?

    private(set) var configPath = ""

    /// The daemon in this process; nil where there is none (check-settings,
    /// render-settings), and then every request fails.
    static var link: DaemonLink?

    /// The display name shown everywhere the app names itself.
    static let appName = "Homekey"

    // ponytail: mirrors the [hotkeys] defaults in internal/config/config_defaults.go;
    // needed to know when an old binding must be written as __disabled__.
    static let defaultHotkeys: [String: String] = [
        "Primary+Shift+Space": "hints",
        "Primary+Shift+G": "grid",
        "Primary+Shift+C": "recursive_grid",
        "Primary+Shift+B": "bisect",
        "Primary+Shift+S": "scroll",
    ]

    init() {}

    /// Shows `config` and never asks the daemon: for rendering the windows offscreen.
    init(config: [String: Any]) {
        self.config = config
    }

    /// One request, as docs/reference/ipc.md describes it: the reply's data
    /// as JSON (a string as is), or the daemon's error. It blocks: call it on `queue`.
    @discardableResult
    func send(_ action: String, _ args: [String] = []) -> (ok: Bool, out: String) {
        Self.link?.send(action, args) ?? (false, "No \(Self.appName) daemon here")
    }

    /// Every request runs here, off the main thread and in order, so the
    /// window never waits on the daemon and the daemon never waits on a main
    /// thread that waits on it.
    let queue = DispatchQueue(label: "neru.settings.daemon")

    /// Runs `work` in the background, then reloads the config on the main thread.
    /// `work` returns an error message, or nil.
    func background(_ work: @escaping () -> String?) {
        queue.async {
            let failure = work()
            let dump = self.send("config")
            DispatchQueue.main.async {
                if let failure { self.error = failure }
                self.apply(dump)
            }
        }
    }

    func refresh() {
        queue.async {
            let version = self.send("version").out
            let login = self.send("login-item", ["status"]).out == "true"
            let path = Self.json(self.send("status").out)?["config"] as? String
            let dump = self.send("config")
            DispatchQueue.main.async {
                self.version = version
                self.launchAtLogin = login
                // Without a file the daemon says "using default config" here.
                if let path { self.configPath = path.hasPrefix("/") ? path : "" }
                self.apply(dump)
            }
        }
    }

    private func apply(_ dump: (ok: Bool, out: String)) {
        if dump.ok { config = Self.json(dump.out) ?? [:] } else { error = dump.out }
    }

    /// Exits the open mode, if any: a window opening is not a click for it.
    func exitMode() {
        queue.async { self.send("idle") }
    }

    // MARK: reading

    /// Reads a dotted TOML path ("hints.ui.font_size") from the camelCase dump.
    func value(_ key: String) -> Any? { Self.value(key, in: config) }

    static func value(_ key: String, in dump: [String: Any]) -> Any? {
        var node: Any? = dump
        for part in key.split(separator: ".") {
            node = (node as? [String: Any])?[camel(String(part))]
        }
        return node
    }

    func bool(_ key: String) -> Bool { value(key) as? Bool ?? false }
    func string(_ key: String) -> String { value(key) as? String ?? "" }
    func double(_ key: String) -> Double { (value(key) as? NSNumber)?.doubleValue ?? 0 }
    func strings(_ key: String) -> [String] { value(key) as? [String] ?? [] }

    /// Writes into the local copy of the dump so the window shows a change
    /// before the daemon has it. The next dump replaces it with the truth.
    func setLocal(_ key: String, _ value: Any) {
        func put(_ node: [String: Any], _ parts: ArraySlice<String>) -> [String: Any] {
            var node = node
            let head = Self.camel(parts.first!)
            node[head] = parts.count == 1 ? value : put(node[head] as? [String: Any] ?? [:], parts.dropFirst())
            return node
        }
        config = put(config, ArraySlice(key.split(separator: ".").map(String.init)))
    }

    // MARK: writing

    func set(_ key: String, _ value: String, local: Any? = nil) {
        setMany([(key, value)], local: [(key, local ?? value)])
    }

    func set(_ key: String, _ value: Bool) { set(key, value ? "true" : "false", local: value) }

    func set(_ key: String, _ values: [String]) {
        let data = try? JSONSerialization.data(withJSONObject: values)
        set(key, String(decoding: data ?? Data("[]".utf8), as: UTF8.self), local: values)
    }

    /// Sets several fields; more than one is applied with a single reload.
    func setMany(_ pairs: [(String, String)], local: [(String, Any)]? = nil) {
        for (key, value) in local ?? pairs.map({ ($0.0, $0.1 as Any) }) { setLocal(key, value) }
        error = nil
        background {
            if pairs.count == 1 {
                let result = self.send("config-set", [pairs[0].0, pairs[0].1])
                return result.ok ? nil : result.out
            }
            for (key, value) in pairs {
                let result = self.send("config-set", [key, value, "--no-reload"])
                if !result.ok { return result.out }
            }
            let result = self.send("reload")
            return result.ok ? nil : result.out
        }
    }

    /// Installs or removes the login item. The daemon never boots its own
    /// launchd job out from here (cli.LoginItem), so nothing restarts.
    func setLaunchAtLogin(_ on: Bool) {
        launchAtLogin = on
        queue.async {
            let result = self.send("login-item", [on ? "install" : "uninstall"])
            let login = self.send("login-item", ["status"]).out == "true"
            DispatchQueue.main.async {
                if !result.ok { self.error = result.out }
                self.launchAtLogin = login
            }
        }
    }

    // MARK: hotkeys

    func shortcut(for mode: String) -> String? {
        hotkeyBindings.filter { $0.value == [mode] }.keys.min()
    }

    /// Rebinds `mode` to `combo` in the [hotkeys] table of config.toml. A
    /// combo bound to anything else is refused rather than overwritten, as on
    /// the Clicking page.
    func setShortcut(_ combo: String, for mode: String) {
        let owns: ([String]) -> Bool = { $0 == [mode] }
        var bindings = hotkeyBindings
        if let conflict = Self.shortcutConflict(combo, in: bindings, owns: owns) { error = conflict; return }
        bindings = bindings.filter { $0.value != [mode] }
        bindings[combo] = [mode]
        setLocal("hotkeys.bindings", bindings)
        editConfigText { text, fresh in
            let bindings = Self.hotkeyBindings(in: fresh)
            if let conflict = Self.shortcutConflict(combo, in: bindings, owns: owns) { throw ConfigEditError(errorDescription: conflict) }
            return Self.rebind(text, mode: mode, to: combo, in: bindings)
        }
    }

    /// Pauses Neru so its own hotkeys don't swallow the keys being recorded.
    /// Leaves Neru paused afterwards if the user had paused it themselves.
    /// Counted: with two recorders open at once, only the first pause reads
    /// whether Neru was running and only the last resume restarts it.
    func pause(_ paused: Bool) {
        queue.async {
            if paused {
                self.pauseDepth += 1
                guard self.pauseDepth == 1 else { return }
                self.pausedForRecording = Self.json(self.send("status").out)?["enabled"] as? Bool ?? false
                if self.pausedForRecording { self.send("stop") }
            } else if self.pauseDepth > 0 {
                self.pauseDepth -= 1
                if self.pauseDepth == 0, self.pausedForRecording {
                    self.send("start")
                    self.pausedForRecording = false
                }
            }
        }
    }

    private var pausedForRecording = false
    private var pauseDepth = 0

    // MARK: helpers

    /// Returns `toml` with `mode` bound to `combo` in its [hotkeys] table.
    /// `bindings` is the daemon's [hotkeys] as dumped; every combo it binds to
    /// `mode` is given up. A default given up is disabled, or it would come
    /// back. The caller has refused a `combo` bound to anything else.
    static func rebind(_ toml: String, mode: String, to combo: String, in bindings: [String: [String]]) -> String {
        var freed = Set(bindings.filter { $0.value == [mode] }.keys.map(comboKey))
        // Nothing bound: an empty [hotkeys] table unbinds every shortcut (the
        // skhd setup), and any line written brings the defaults back.
        if bindings.isEmpty { freed.formUnion(defaultHotkeys.keys.map(comboKey)) }
        freed.remove(comboKey(combo))
        let disabled = defaultHotkeys.keys.sorted().filter { freed.contains(comboKey($0)) }
        // Matched by chord, not spelling, so a stale "__disabled__" or another
        // spelling of a combo being written is replaced rather than duplicated.
        let touched = freed.union([comboKey(combo)])
        return editTable(toml, header: "hotkeys",
                         removing: Set(tableKeys(toml, header: "hotkeys").filter { touched.contains(comboKey($0)) }),
                         adding: [tomlLine(combo, mode)] + disabled.map { tomlLine($0, "__disabled__") })
    }

    static func camel(_ snake: String) -> String {
        let parts = snake.split(separator: "_")
        return parts.enumerated().map { $0 == 0 ? String($1) : $1.prefix(1).uppercased() + $1.dropFirst() }.joined()
    }

    static func json(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    /// Keyboard layouts as (input source ID, display name).
    static func keyboardLayouts() -> [(id: String, name: String)] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        func prop(_ source: TISInputSource, _ key: CFString) -> String? {
            guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
            return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }
        return list.compactMap { source in
            guard let id = prop(source, kTISPropertyInputSourceID) else { return nil }
            return (id, prop(source, kTISPropertyLocalizedName) ?? id)
        }.sorted { $0.name < $1.name }
    }
}

/// The daemon a window talks to: App.swift's in-process one in the app build.
protocol DaemonLink {
    /// One request; see Neru.send. Never on the main thread.
    func send(_ action: String, _ args: [String]) -> (ok: Bool, out: String)
    /// Streams `neru watch` lines to `line` on the main queue, then nil once
    /// when the stream ends. Returns the stop function, to call once.
    func watch(_ line: @escaping (String?) -> Void) -> () -> Void
}
