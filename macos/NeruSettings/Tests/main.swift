// Self-check for the [hotkeys] rewrite. Run: just check-settings (Tests/main.swift)
import Foundation

let base = """
[general]
excluded_apps = []

[hotkeys]
# comment stays
"Primary+Shift+Space" = "hints"
"Primary+Shift+S" = "scroll"

[scroll]
scroll_step = 50
"""

// Moving a default: old line goes, default is disabled, other bindings and sections stay.
let moved = Neru.rebind(base, mode: "hints", to: "Primary+Shift+J", replacing: ["Primary+Shift+Space"])
assert(moved.contains("\"Primary+Shift+J\" = \"hints\""))
assert(moved.contains("\"Primary+Shift+Space\" = \"__disabled__\""))
assert(!moved.contains("\"Primary+Shift+Space\" = \"hints\""))
assert(moved.contains("# comment stays") && moved.contains("\"Primary+Shift+S\" = \"scroll\"") && moved.contains("scroll_step = 50"))

// Moving back to the default drops the __disabled__ line; a custom old combo is just removed.
let back = Neru.rebind(moved, mode: "hints", to: "Primary+Shift+Space", replacing: ["Primary+Shift+J"])
assert(back.contains("\"Primary+Shift+Space\" = \"hints\""))
assert(!back.contains("__disabled__") && !back.contains("Primary+Shift+J"))

// No [hotkeys] table yet: one is appended.
let fresh = Neru.rebind("[general]\n", mode: "grid", to: "Ctrl+Alt+G", replacing: ["Primary+Shift+G"])
assert(fresh.hasSuffix("[hotkeys]\n\"Ctrl+Alt+G\" = \"grid\"\n\"Primary+Shift+G\" = \"__disabled__\""))

// Hand outputs to the real loader if a directory is given.
if CommandLine.arguments.count > 1 {
    let dir = CommandLine.arguments[1]
    for (name, text) in [("moved", moved), ("back", back), ("fresh", fresh)] {
        try! text.write(toFile: "\(dir)/\(name).toml", atomically: true, encoding: .utf8)
    }
}
print("ok")

// Toggling automatic click swaps the command on the same combo.
let auto = Neru.rebind(base, mode: Neru.autoClickHints, to: "Primary+Shift+Space", replacing: [])
assert(auto.contains("\"Primary+Shift+Space\" = \"hints --action left_click\""))
assert(!auto.contains("\"Primary+Shift+Space\" = \"hints\"") && !auto.contains("__disabled__"))
print("auto-click ok")
