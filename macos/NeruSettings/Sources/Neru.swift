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
        var candidates = [Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("neru").path]
        if let env = ProcessInfo.processInfo.environment["NERU_BIN"] { candidates.insert(env, at: 0) }
        candidates += [
            "/Applications/Neru.app/Contents/MacOS/neru", "/opt/homebrew/bin/neru", "/usr/local/bin/neru", "\(home)/.local/bin/neru",
            "\(home)/go/bin/neru", "\(home)/.nix-profile/bin/neru", "/run/current-system/sw/bin/neru",
        ]
        let found = candidates.filter { FileManager.default.isExecutableFile(atPath: $0) }
        return found.first { run($0, ["status"]).ok } ?? found.first
    }

    // ponytail: runs synchronously on the main thread; each call is one local IPC
    // round trip. Move to a Task if the window ever feels sluggish.
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

    func refresh() {
        binary = Self.findBinary()
        version = run(["--version"]).out
        launchAtLogin = run(["services", "status"]).out == "Service loaded"
        if let status = Self.json(run(["status", "--json"]).out) {
            configPath = status["config"] as? String ?? ""
        }
        reloadConfig()
    }

    func reloadConfig() {
        let dump = run(["config", "dump"])
        running = dump.ok
        notRunningReason = dump.ok ? "" : dump.out
        config = Self.json(dump.out) ?? [:]
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

    // MARK: writing

    func set(_ key: String, _ value: String) {
        let result = run(["config", "set", key, value])
        error = result.ok ? nil : result.out
        reloadConfig()
    }

    func set(_ key: String, _ value: Bool) { set(key, value ? "true" : "false") }

    func set(_ key: String, _ values: [String]) {
        let data = try? JSONSerialization.data(withJSONObject: values)
        set(key, String(decoding: data ?? Data("[]".utf8), as: UTF8.self))
    }

    /// Sets several fields, then applies them with one reload.
    func setMany(_ pairs: [(String, String)]) {
        for (key, value) in pairs {
            let result = run(["config", "set", "--no-reload", key, value])
            if !result.ok { error = result.out; return }
        }
        let result = run(["config", "reload"])
        error = result.ok ? nil : result.out
        reloadConfig()
    }

    func setLaunchAtLogin(_ on: Bool) {
        let result = run(["services", on ? "install" : "uninstall"])
        error = result.ok ? nil : result.out
        launchAtLogin = run(["services", "status"]).out == "Service loaded"
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
        let text = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        let updated = Self.rebind(text, mode: mode, to: combo, replacing: combos(for: mode))
        do {
            try updated.write(toFile: configPath, atomically: true, encoding: .utf8)
        } catch {
            self.error = error.localizedDescription
            return
        }
        let result = run(["config", "reload"])
        error = result.ok ? nil : result.out
        reloadConfig()
    }

    /// Pauses Neru so its own hotkeys don't swallow the keys being recorded.
    /// Leaves Neru paused afterwards if the user had paused it themselves.
    func pause(_ paused: Bool) {
        if paused {
            pausedForRecording = Self.json(run(["status", "--json"]).out)?["enabled"] as? Bool ?? false
            if pausedForRecording { run(["stop"]) }
        } else if pausedForRecording {
            run(["start"])
            pausedForRecording = false
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
