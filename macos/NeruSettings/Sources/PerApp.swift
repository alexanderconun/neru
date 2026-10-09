import Foundation

/// Per-app overrides: one app's [[hints.app_configs]] and [[scroll.app_configs]]
/// entries, edited together. `config set` cannot write arrays of tables, and
/// the override file merges them by index into config.toml's, so every change
/// regenerates both arrays in config.toml from the dump.
///
/// Entries stay as the dump has them (camelCase keys, NSNull when unset), so
/// the fields this window does not edit (capture_scope, label_direction,
/// scroll_step_full, hotkeys) are written back as they were.
extension Neru {
    /// Dump key to TOML key, in the order fields are written after bundle_id.
    /// The dump says additionalClickable, which camel() cannot derive.
    static let appConfigFields: [(json: String, toml: String)] = [
        ("strategy", "strategy"), ("captureScope", "capture_scope"), ("labelDirection", "label_direction"),
        ("additionalClickable", "additional_clickable_roles"),
        ("ignoreClickableCheck", "ignore_clickable_check"), ("visibleCheckEnabled", "visible_check_enabled"),
        ("scrollStep", "scroll_step"), ("scrollStepHalf", "scroll_step_half"), ("scrollStepFull", "scroll_step_full"),
        ("hotkeys", "hotkeys"),
    ]
    /// JSON numbers and booleans both arrive as NSNumber, so the key says which.
    static let appConfigBools: Set = ["ignoreClickableCheck", "visibleCheckEnabled"]

    func appConfigs(_ section: String) -> [[String: Any]] {
        value("\(section).app_configs") as? [[String: Any]] ?? []
    }

    /// Every app with an override in either section, first seen first.
    var perAppIDs: [String] { Self.bundleIDs(appConfigs("hints") + appConfigs("scroll")) }

    /// One field of `id`'s entry in `section` ("hints" or "scroll"), nil when unset.
    func appSetting(_ section: String, _ id: String, _ key: String) -> Any? {
        Self.setting(appConfigs(section), id, key)
    }

    /// Sets one field (nil restores the default) and rewrites both arrays.
    func setAppSetting(_ section: String, _ id: String, _ key: String, _ value: Any?) {
        var hints = appConfigs("hints"), scroll = appConfigs("scroll")
        if section == "hints" {
            hints = Self.setting(hints, id: id, key: key, to: value)
        } else {
            scroll = Self.setting(scroll, id: id, key: key, to: value)
        }
        saveAppConfigs(hints: hints, scroll: scroll)
    }

    func removeAppConfigs(_ id: String) {
        saveAppConfigs(hints: Self.removing(appConfigs("hints"), id), scroll: Self.removing(appConfigs("scroll"), id))
    }

    private func saveAppConfigs(hints: [[String: Any]], scroll: [[String: Any]]) {
        setLocal("hints.app_configs", hints)
        setLocal("scroll.app_configs", scroll)
        editConfigText { Self.writeAppConfigs($0, hints: hints, scroll: scroll) }
    }

    // MARK: pure helpers (covered by Tests/PerAppTests.swift)

    /// The daemon matches bundle ids case-insensitively.
    static func isApp(_ entry: [String: Any], _ id: String) -> Bool {
        (entry["bundleId"] as? String)?.lowercased() == id.lowercased()
    }

    static func bundleIDs(_ entries: [[String: Any]]) -> [String] {
        var seen = Set<String>()
        return entries.compactMap { $0["bundleId"] as? String }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func setting(_ entries: [[String: Any]], _ id: String, _ key: String) -> Any? {
        let value = entries.first { isApp($0, id) }?[key]
        return value is NSNull ? nil : value
    }

    /// `entries` with `key` of `id`'s entry set to `value` (nil removes it).
    /// An app without an entry gets one, unless there is nothing to set.
    static func setting(_ entries: [[String: Any]], id: String, key: String, to value: Any?) -> [[String: Any]] {
        var entries = entries
        if let index = entries.firstIndex(where: { isApp($0, id) }) {
            entries[index][key] = value
        } else if let value {
            entries.append(["bundleId": id, key: value])
        }
        return entries
    }

    static func removing(_ entries: [[String: Any]], _ id: String) -> [[String: Any]] {
        entries.filter { !isApp($0, id) }
    }

    /// config.toml with both arrays regenerated from `hints` and `scroll`.
    // ponytail: comments inside the old blocks (and any right above the next
    // table header) are lost; keeping them needs a comment-aware TOML editor.
    static func writeAppConfigs(_ toml: String, hints: [[String: Any]], scroll: [[String: Any]]) -> String {
        let withHints = replaceArrayTables(toml, name: "hints.app_configs", blocks: appConfigBlocks("hints", hints))
        return replaceArrayTables(withHints, name: "scroll.app_configs", blocks: appConfigBlocks("scroll", scroll))
    }

    /// One `[[<section>.app_configs]]` block per app. A bundle id repeated in
    /// another case keeps its first entry (the loader refuses duplicates), and
    /// an entry that sets nothing but bundle_id is dropped.
    static func appConfigBlocks(_ section: String, _ entries: [[String: Any]]) -> [[String]] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard let id = entry["bundleId"] as? String, !id.trimmingCharacters(in: .whitespaces).isEmpty,
                  seen.insert(id.lowercased()).inserted else { return nil }
            let fields = appConfigFields.compactMap { field in
                tomlValue(entry[field.json], bool: appConfigBools.contains(field.json)).map { "\(field.toml) = \($0)" }
            }
            return fields.isEmpty ? nil : ["[[\(section).app_configs]]", "bundle_id = \(tomlString(id))"] + fields
        }
    }

    /// A dump value as TOML, nil when unset or empty. Hotkeys become one
    /// inline table; a single-step binding is written as a plain string.
    static func tomlValue(_ value: Any?, bool: Bool) -> String? {
        switch value {
        case let text as String:
            return text.isEmpty ? nil : tomlString(text)
        case let list as [String]:
            return list.isEmpty ? nil : tomlArray(list)
        case let table as [String: Any]:
            guard !table.isEmpty else { return nil }
            let pairs = table.keys.sorted().map { key in
                let steps = table[key] as? [String] ?? [table[key] as? String ?? ""]
                return "\(tomlString(key)) = \(steps.count == 1 ? tomlString(steps[0]) : tomlArray(steps))"
            }
            return "{ " + pairs.joined(separator: ", ") + " }"
        case let number as NSNumber:
            return bool ? "\(number.boolValue)" : "\(number.intValue)"
        default:
            return nil
        }
    }

    static func tomlArray(_ list: [String]) -> String {
        "[" + list.map(tomlString).joined(separator: ", ") + "]"
    }
}
