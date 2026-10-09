import Foundation

/// Edits to config.toml itself, for what `config set` cannot write: hotkey
/// tables ([hotkeys], [scroll.hotkeys], …) and per-app arrays of tables
/// ([[hints.app_configs]], …). The daemon ignores those in the override file,
/// so they have to live in config.toml.
///
/// Every edit goes through `editConfigText`, which validates the result with
/// the real loader before writing it. A refused config.toml makes the daemon
/// run on all defaults at its next start, so nothing unvalidated is written.
extension Neru {
    /// Applies `transform` to config.toml in the background: validate the new
    /// text, write it, reload. On failure (or when `transform` throws) the file
    /// is left untouched and the error is shown. The caller updates the window
    /// first with `setLocal`.
    ///
    /// `transform` gets the file and a fresh `config dump` of it, and works out
    /// its change from that dump, never from what the window showed: the
    /// daemon reads config.toml only when told to, so it reloads first, and
    /// lines written by hand since are kept. A file it refuses stops the edit.
    func editConfigText(_ transform: @escaping (String, [String: Any]) throws -> String) {
        // Still reloads, so the caller's setLocal does not stay on screen.
        guard !configPath.isEmpty else { background { "\(Self.appName) is running without a config file" }; return }
        let path = configPath
        // A symlinked config.toml (stow, home-manager) is edited where it
        // points; replacing the link would cut it off from its dotfiles copy.
        let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        error = nil
        background {
            let reload = self.run(["config", "reload"])
            guard reload.ok else { return reload.out }
            let dump = self.run(["config", "dump"])
            guard dump.ok, let fresh = Self.json(dump.out) else { return dump.out }
            let text: String
            do { text = try String(contentsOfFile: target, encoding: .utf8) } catch {
                return "Could not read \(path): \(error.localizedDescription)"
            }
            let updated: String
            do { updated = try transform(text, fresh) } catch { return error.localizedDescription }
            if updated == text { return nil }
            // Beside `path`, not `target`: the daemon reads the override next to the link.
            if let problem = self.validate(updated, beside: path) { return problem }
            do {
                try updated.write(toFile: target, atomically: true, encoding: .utf8)
            } catch {
                return error.localizedDescription
            }
            let result = self.run(["config", "reload"])
            return result.ok ? nil : result.out
        }
    }

    /// Runs `neru config validate` on `text` as if it were the config file at
    /// `path`, with that file's override layered on top. Returns the error, or nil.
    func validate(_ text: String, beside path: String) -> String? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("homekey-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let candidate = dir.appendingPathComponent("config.toml")
            try text.write(to: candidate, atomically: true, encoding: .utf8)
            let override = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("override.toml")
            if FileManager.default.fileExists(atPath: override.path) {
                try FileManager.default.copyItem(at: override, to: dir.appendingPathComponent("config.override.toml"))
            }
            let result = run(["config", "validate", "--config", candidate.path])
            return result.ok ? nil : result.out
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: pure text helpers (covered by Tests/CoreTests.swift)

    /// Returns `toml` with the lines keyed by `removing` dropped from the
    /// `[header]` table and `adding` inserted at its top. The table is appended
    /// when missing. Comments and every other line are kept as they are.
    static func editTable(_ toml: String, header: String, removing keys: Set<String>, adding lines: [String]) -> String {
        var all = toml.components(separatedBy: "\n")
        var headerIndex = all.firstIndex { tableName($0) == header }
        if headerIndex == nil {
            if all.last?.isEmpty == false { all.append("") }
            all.append("[\(header)]")
            headerIndex = all.count - 1
        }
        let start = headerIndex! + 1
        let end = all[start...].firstIndex { tableName($0) != nil } ?? all.count
        var section: [String] = []
        var open = 0 // brackets a removed key's multi-line array still has open
        for line in all[start..<end] {
            if open > 0 { open += bracketBalance(line); continue }
            if let key = tomlKey(line), keys.contains(key) { open = bracketBalance(line); continue }
            section.append(line)
        }
        section.insert(contentsOf: lines, at: 0)
        all.replaceSubrange(start..<end, with: section)
        return all.joined(separator: "\n")
    }

    /// The keys of the `[header]` table, empty when it is missing.
    static func tableKeys(_ toml: String, header: String) -> [String] {
        let lines = toml.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { tableName($0) == header }) else { return [] }
        return lines[(start + 1)...].prefix { tableName($0) == nil }.compactMap(tomlKey)
    }

    /// Returns `toml` with every `[[name]]` block (and any `[name.*]` sub-table)
    /// removed and `blocks` appended at the end, each one a full block of
    /// lines starting with its `[[name]]` header. Comments right above the
    /// table that follows a removed block belong to that table and are kept.
    static func replaceArrayTables(_ toml: String, name: String, blocks: [[String]]) -> String {
        var kept: [String] = []
        var gap: [String] = [] // comment lines (and blanks after them) since a removed block's last key
        var skipping = false
        for line in toml.components(separatedBy: "\n") {
            if let header = tableName(line) {
                let ours = header == name || header.hasPrefix(name + ".")
                if skipping, !ours { kept += gap }
                skipping = ours
                gap = []
            }
            if !skipping { kept.append(line); continue }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") || (trimmed.isEmpty && !gap.isEmpty) {
                gap.append(line)
            } else if !trimmed.isEmpty {
                gap = []
            }
        }
        while kept.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { kept.removeLast() }
        for block in blocks { kept += [""] + block }
        return kept.joined(separator: "\n") + "\n"
    }

    /// The name in a `[name]` or `[[name]]` header line, nil for any other
    /// line. A trailing comment and a CRLF line end are ignored.
    // ponytail: cuts at the first #, so a quoted name containing # comes out
    // wrong; fine for matching our own unquoted table names.
    static func tableName(_ line: String) -> String? {
        let header = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard header.hasPrefix("[") else { return nil }
        return header.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
    }

    /// The key of a `key = value` line, unquoted, or nil for anything else.
    /// A quoted key is read to its closing quote: `"Primary+="` holds an `=`.
    static func tomlKey(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let quote = trimmed.first, quote == "\"" || quote == "'" else {
            guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("["), let eq = trimmed.firstIndex(of: "=") else { return nil }
            return trimmed[..<eq].trimmingCharacters(in: .whitespaces)
        }
        var key = ""
        var rest = trimmed.dropFirst()
        while let char = rest.popFirst() {
            if char == quote { return rest.drop(while: \.isWhitespace).first == "=" ? key : nil }
            // ponytail: \n, \t and \u escapes read as the bare letter; no hotkey has one.
            key.append(char == "\\" && quote == "\"" ? rest.popFirst() ?? char : char)
        }
        return nil
    }

    /// `[` minus `]` on a line, outside strings and comments: above zero,
    /// the line opens a multi-line array.
    static func bracketBalance(_ line: String) -> Int {
        var balance = 0
        var quote: Character?
        var escaped = false
        for char in line {
            if let open = quote {
                if escaped { escaped = false } else if char == "\\" && open == "\"" { escaped = true } else if char == open { quote = nil }
            } else if char == "\"" || char == "'" {
                quote = char
            } else if char == "#" {
                break
            } else if char == "[" || char == "]" {
                balance += char == "[" ? 1 : -1
            }
        }
        return balance
    }

    /// A `"key" = "value"` line with both sides escaped.
    static func tomlLine(_ key: String, _ value: String) -> String {
        "\(tomlString(key)) = \(tomlString(value))"
    }

    /// A TOML basic string.
    static func tomlString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}

/// A refusal from inside an `editConfigText` transform, shown as the error.
struct ConfigEditError: LocalizedError {
    let errorDescription: String?
}
