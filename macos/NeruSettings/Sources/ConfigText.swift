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
    /// text, write it, reload. On failure the file is left untouched and the
    /// error is shown. The caller updates the window first with `setLocal`.
    func editConfigText(_ transform: @escaping (String) -> String) {
        // Still reloads, so the caller's setLocal does not stay on screen.
        guard !configPath.isEmpty else { background { "\(Self.appName) is running without a config file" }; return }
        let path = configPath
        error = nil
        background {
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let updated = transform(text)
            if updated == text { return nil }
            if let problem = self.validate(updated, beside: path) { return problem }
            do {
                try updated.write(toFile: path, atomically: true, encoding: .utf8)
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
        var headerIndex = all.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "[\(header)]" }
        if headerIndex == nil {
            if all.last?.isEmpty == false { all.append("") }
            all.append("[\(header)]")
            headerIndex = all.count - 1
        }
        let start = headerIndex! + 1
        let end = all[start...].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? all.count
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

    /// Returns `toml` with every `[[name]]` block (and any `[name.*]` sub-table)
    /// removed and `blocks` appended at the end, each one a full block of
    /// lines starting with its `[[name]]` header.
    static func replaceArrayTables(_ toml: String, name: String, blocks: [[String]]) -> String {
        var kept: [String] = []
        var skipping = false
        for line in toml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                let headerName = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                skipping = headerName == name || headerName.hasPrefix(name + ".")
            }
            if !skipping { kept.append(line) }
        }
        while kept.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { kept.removeLast() }
        for block in blocks { kept += [""] + block }
        return kept.joined(separator: "\n") + "\n"
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
