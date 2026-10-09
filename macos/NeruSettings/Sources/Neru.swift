import AppKit
import Carbon

/// Talks to the running daemon through the `neru` CLI: `config dump` to read,
/// `config set` to write (persisted to config.override.toml by the daemon).
/// Hotkeys are the exception — `config set` cannot rename map keys, so they
/// are edited in the [hotkeys] table of config.toml directly.
final class Neru: ObservableObject {
    @Published var config: [String: Any] = [:]
    @Published var running = false
    @Published var notRunningReason = ""
    @Published var launchAtLogin = false
    @Published var version = ""
    @Published var error: String?

    private(set) var binary: String?
    private var configPath = ""

    // ponytail: mirrors the [hotkeys] defaults in internal/config/config_defaults.go;
    // needed to know when an old binding must be written as __disabled__.
    static let defaultHotkeys: [String: String] = [
        "Primary+Shift+Space": "hints",
        "Primary+Shift+G": "grid",
        "Primary+Shift+C": "recursive_grid",
        "Primary+Shift+B": "bisect",
        "Primary+Shift+S": "scroll",
    ]

    init() { refresh() }

    /// Prefers the first binary the running daemon accepts: a CLI of another
    /// version is refused with ERR_VERSION_MISMATCH.
    static func findBinary() -> String? {
        let home = NSHomeDirectory()
        let parent = Bundle.main.bundleURL.deletingLastPathComponent()
        var candidates = [
            parent.deletingLastPathComponent().appendingPathComponent("MacOS/neru").path, // Neru.app/Contents/Helpers
            parent.appendingPathComponent("neru").path, // next to a dev build
        ]
        if let env = ProcessInfo.processInfo.environment["NERU_BIN"] { candidates.insert(env, at: 0) }
        candidates += [
            "/Applications/Neru.app/Contents/MacOS/neru", "/opt/homebrew/bin/neru", "/usr/local/bin/neru", "\(home)/.local/bin/neru",
            "\(home)/go/bin/neru", "\(home)/.nix-profile/bin/neru", "/run/current-system/sw/bin/neru",
        ]
        let found = candidates.filter { FileManager.default.isExecutableFile(atPath: $0) }
        return found.first { run($0, ["status"]).ok } ?? found.first
    }

    @discardableResult
    func run(_ args: [String]) -> (ok: Bool, out: String) {
        guard let binary else { return (false, "Could not find the neru binary") }
        return Self.run(binary, args)
    }

    static func run(_ binary: String, _ args: [String]) -> (ok: Bool, out: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (false, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus == 0, out)
    }

    /// Every CLI call runs here, off the main thread and in order, so the
    /// window never waits on a process.
    private let queue = DispatchQueue(label: "neru.settings.cli")

    /// Runs `work` in the background, then reloads the config on the main thread.
    /// `work` returns an error message, or nil.
    private func background(_ work: @escaping () -> String?) {
        queue.async {
            let failure = work()
            let dump = self.run(["config", "dump"])
            DispatchQueue.main.async {
                if let failure { self.error = failure }
                self.apply(dump)
            }
        }
    }

    func refresh() {
        queue.async {
            let binary = Self.findBinary()
            self.binary = binary
            let version = self.run(["--version"]).out
            let login = self.run(["services", "status"]).out == "Service loaded"
            let path = Self.json(self.run(["status", "--json"]).out)?["config"] as? String
            let dump = self.run(["config", "dump"])
            DispatchQueue.main.async {
                self.version = version
                self.launchAtLogin = login
                if let path { self.configPath = path }
                self.apply(dump)
            }
        }
    }

    private func apply(_ dump: (ok: Bool, out: String)) {
        running = dump.ok
        notRunningReason = dump.ok ? "" : dump.out
        if dump.ok { config = Self.json(dump.out) ?? [:] }
    }

    func start() {
        guard let binary else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["launch"]
        try? process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.refresh() }
    }

    // MARK: reading

    /// Reads a dotted TOML path ("hints.ui.font_size") from the camelCase dump.
    func value(_ key: String) -> Any? {
        var node: Any? = config
        for part in key.split(separator: ".") {
            node = (node as? [String: Any])?[Self.camel(String(part))]
        }
        return node
    }

    func bool(_ key: String) -> Bool { value(key) as? Bool ?? false }
    func string(_ key: String) -> String { value(key) as? String ?? "" }
    func double(_ key: String) -> Double { (value(key) as? NSNumber)?.doubleValue ?? 0 }
    func strings(_ key: String) -> [String] { value(key) as? [String] ?? [] }

    /// Writes into the local copy of the dump so the window shows a change
    /// before the daemon has it. The next dump replaces it with the truth.
    private func setLocal(_ key: String, _ value: Any) {
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
                let result = self.run(["config", "set", pairs[0].0, pairs[0].1])
                return result.ok ? nil : result.out
            }
            for (key, value) in pairs {
                let result = self.run(["config", "set", "--no-reload", key, value])
                if !result.ok { return result.out }
            }
            let result = self.run(["config", "reload"])
            return result.ok ? nil : result.out
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        launchAtLogin = on
        queue.async {
            let result = self.run(["services", on ? "install" : "uninstall"])
            let login = self.run(["services", "status"]).out == "Service loaded"
            DispatchQueue.main.async {
                if !result.ok { self.error = result.out }
                self.launchAtLogin = login
            }
        }
    }

    // MARK: hotkeys

    func shortcut(for mode: String) -> String? {
        combos(for: mode).first
    }

    private func combos(for mode: String) -> [String] {
        let bindings = value("hotkeys.bindings") as? [String: Any] ?? [:]
        return bindings.filter { ($0.value as? [String]) == [mode] }.keys.sorted()
    }

    static let autoClickHints = "hints --action left_click"

    /// The command the hints shortcut runs: plain "hints" only moves the
    /// cursor to the picked label, the --action form clicks it too.
    var hintsCommand: String {
        combos(for: Self.autoClickHints).isEmpty ? "hints" : Self.autoClickHints
    }

    func setAutoClick(_ on: Bool) {
        let current = hintsCommand
        let combo = combos(for: current).first ?? "Primary+Shift+Space"
        setShortcut(combo, for: on ? Self.autoClickHints : "hints")
    }

    /// Rebinds `mode` to `combo` in the [hotkeys] table of config.toml.
    func setShortcut(_ combo: String, for mode: String) {
        guard !configPath.isEmpty else { error = "Neru is running without a config file"; return }
        let current = combos(for: mode)
        var bindings = value("hotkeys.bindings") as? [String: Any] ?? [:]
        for old in current { bindings[old] = nil }
        bindings[combo] = [mode]
        setLocal("hotkeys.bindings", bindings)

        let path = configPath
        error = nil
        background {
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let updated = Self.rebind(text, mode: mode, to: combo, replacing: current)
            do {
                try updated.write(toFile: path, atomically: true, encoding: .utf8)
            } catch {
                return error.localizedDescription
            }
            let result = self.run(["config", "reload"])
            return result.ok ? nil : result.out
        }
    }

    /// Pauses Neru so its own hotkeys don't swallow the keys being recorded.
    /// Leaves Neru paused afterwards if the user had paused it themselves.
    func pause(_ paused: Bool) {
        queue.async {
            if paused {
                self.pausedForRecording = Self.json(self.run(["status", "--json"]).out)?["enabled"] as? Bool ?? false
                if self.pausedForRecording { self.run(["stop"]) }
            } else if self.pausedForRecording {
                self.run(["start"])
                self.pausedForRecording = false
            }
        }
    }

    private var pausedForRecording = false

    // MARK: helpers

    /// Returns `toml` with `mode` bound to `combo` in its [hotkeys] table.
    /// `current` is every combo the daemon has bound to `mode` right now.
    static func rebind(_ toml: String, mode: String, to combo: String, replacing current: [String]) -> String {
        let old = current.filter { $0 != combo }
        var lines = toml.components(separatedBy: "\n")

        var header = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "[hotkeys]" }
        if header == nil {
            lines += ["", "[hotkeys]"]
            header = lines.count - 1
        }
        let start = header! + 1
        let end = lines[start...].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count

        let replaced = Set(old + [combo])
        var section = lines[start..<end].filter { line in
            guard let key = tomlKey(line) else { return true }
            return !replaced.contains(key)
        }
        // A default left out of the file comes back, so it has to be disabled.
        let disabled = old.filter { defaultHotkeys[$0] != nil }.map { "\"\($0)\" = \"__disabled__\"" }
        section.insert(contentsOf: ["\"\(combo)\" = \"\(mode)\""] + disabled, at: 0)
        lines.replaceSubrange(start..<end, with: section)
        return lines.joined(separator: "\n")
    }

    static func tomlKey(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { return nil }
        return trimmed[..<eq].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
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
