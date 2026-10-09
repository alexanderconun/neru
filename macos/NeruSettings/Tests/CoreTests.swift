// Core self-checks: the [hotkeys] rewrite and the config.toml text helpers.
import AppKit

func runCoreTests() {
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

    let defaults = Neru.defaultHotkeys.mapValues { [$0] }

    // Moving a default: old line goes, default is disabled, other bindings and sections stay.
    let moved = Neru.rebind(base, mode: "hints", to: "Primary+Shift+J", in: defaults)
    assert(moved.contains("\"Primary+Shift+J\" = \"hints\""))
    assert(moved.contains("\"Primary+Shift+Space\" = \"__disabled__\""))
    assert(!moved.contains("\"Primary+Shift+Space\" = \"hints\""))
    assert(moved.contains("# comment stays") && moved.contains("\"Primary+Shift+S\" = \"scroll\"") && moved.contains("scroll_step = 50"))

    // Moving back to the default drops the __disabled__ line; a custom old combo is just removed.
    let back = Neru.rebind(moved, mode: "hints", to: "Primary+Shift+Space",
                           in: defaults.filter { $0.value != ["hints"] }.merging(["Primary+Shift+J": ["hints"]]) { $1 })
    assert(back.contains("\"Primary+Shift+Space\" = \"hints\""))
    assert(!back.contains("__disabled__") && !back.contains("Primary+Shift+J"))

    // No [hotkeys] table yet: one is appended.
    let fresh = Neru.rebind("[general]\n", mode: "grid", to: "Ctrl+Alt+G", in: defaults)
    assert(fresh.hasSuffix("[hotkeys]\n\"Ctrl+Alt+G\" = \"grid\"\n\"Primary+Shift+G\" = \"__disabled__\""))

    // Only the mode's own combos are given up: a line rebound by hand since
    // (it is in the fresh dump) stays, and its default is not disabled.
    let byHand = "[hotkeys]\n\"Primary+Shift+G\" = \"exec open -a Ghostty\"\n"
    let kept = Neru.rebind(byHand, mode: "grid", to: "Ctrl+Alt+G",
                           in: defaults.merging(["Primary+Shift+G": ["exec open -a Ghostty"]]) { $1 })
    assert(kept == "[hotkeys]\n\"Ctrl+Alt+G\" = \"grid\"\n\"Primary+Shift+G\" = \"exec open -a Ghostty\"\n", kept)

    // An empty [hotkeys] (nothing bound, the skhd setup) stays all-off: the
    // other defaults are disabled, and lines already disabling them are not doubled.
    let skhd = Neru.rebind("[hotkeys]\n", mode: "grid", to: "Ctrl+Alt+G", in: [:])
    assert(Neru.tableKeys(skhd, header: "hotkeys") == ["Ctrl+Alt+G"] + Neru.defaultHotkeys.keys.sorted(), skhd)
    let allOff = "[hotkeys]\n" + Neru.defaultHotkeys.keys.sorted().map { Neru.tomlLine($0, "__disabled__") + "\n" }.joined()
    let onDefault = Neru.tableKeys(Neru.rebind(allOff, mode: "grid", to: "Primary+Shift+G", in: [:]), header: "hotkeys")
    assert(onDefault.count == 5 && Set(onDefault) == Set(Neru.defaultHotkeys.keys), "\(onDefault)")

    // Every recorder refuses a combo bound to something else, a launcher
    // included; its own combo, in any spelling, is not refused.
    let launcher = ["Primary+Shift+Space": ["hints --action left_click"], "Primary+Shift+G": ["grid"]]
    assert(Neru.shortcutConflict("Primary+Shift+Space", in: launcher) { $0 == ["grid"] }
        == "⌘⇧Space is already used by the clicking shortcut. Change that one first.")
    assert(Neru.shortcutConflict("Shift+Cmd+G", in: launcher) { $0 == ["grid"] } == nil)
    assert(Neru.shortcutConflict("Primary+Shift+G", in: launcher) { $0 == ["scroll"] }
        == "⌘⇧G is already used by \"grid\". Change that one first.")

    // Table headers are found with a trailing comment or a CRLF line end,
    // so an edit never appends a second [hotkeys] the loader refuses.
    for header in ["[hotkeys] # mine", "[hotkeys]\r"] {
        let edited = Neru.editTable("\(header)\n\"Ctrl+X\" = \"grid\"\n", header: "hotkeys", removing: ["Ctrl+X"], adding: ["\"Ctrl+Y\" = \"grid\""])
        assert(edited.components(separatedBy: "[hotkeys]").count == 2 && !edited.contains("Ctrl+X"), edited)
        assert(Neru.tableKeys(edited, header: "hotkeys") == ["Ctrl+Y"], edited)
    }

    // editTable keeps other tables and comments, appends a missing table.
    let scroll = Neru.editTable(base, header: "scroll.hotkeys", removing: ["j"], adding: [Neru.tomlLine("n", "action scroll_down")])
    assert(scroll.hasSuffix("[scroll.hotkeys]\n\"n\" = \"action scroll_down\""))
    assert(scroll.contains("# comment stays") && scroll.contains("scroll_step = 50"))

    // replaceArrayTables swaps every block of one array and its sub-tables only.
    let apps = """
    [general]
    a = 1

    [[hints.app_configs]]
    bundle_id = "old"

    [hints.app_configs.hotkeys]
    "x" = "idle"

    [[scroll.app_configs]]
    bundle_id = "keep"
    """
    let swapped = Neru.replaceArrayTables(apps, name: "hints.app_configs",
                                          blocks: [["[[hints.app_configs]]", Neru.tomlLine("bundle_id", "new")]])
    assert(!swapped.contains("\"old\"") && !swapped.contains("\"x\" = \"idle\""))
    assert(swapped.contains("bundle_id = \"keep\"") && swapped.contains("\"bundle_id\" = \"new\""))

    // tomlString escapes quotes and backslashes.
    assert(Neru.tomlString("a\"b\\c") == "\"a\\\"b\\\\c\"")

    // Waiting for permission only on the daemon's own code: a daemon with no
    // socket may be at its invalid-config alert instead.
    assert(Neru.isWaitingForAccessibility(dumpOK: false, output: "x (code: ERR_ACCESSIBILITY_DENIED)"))
    assert(!Neru.isWaitingForAccessibility(dumpOK: false, output: "[IPC_SERVER_NOT_RUNNING] neru is not running"))
    assert(!Neru.isWaitingForAccessibility(dumpOK: true, output: ""))
    assert(Neru.notRunningReason("[IPC_SERVER_NOT_RUNNING] neru is not running. Start it first") == "Homekey isn't running.")
    assert(Neru.notRunningReason("version mismatch (code: ERR_VERSION_MISMATCH)").hasPrefix("Another version of Homekey"))
    assert(Neru.notRunningReason("boom") == "Can't reach Homekey: boom")

    // Recorded chords: Shift alone is typing, so only the F-keys may take it.
    func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }
    assert(Shortcut.from(key(15, "R", .shift)) == nil) // R
    assert(Shortcut.from(key(48, "\t", .shift)) == nil) // Tab
    assert(Shortcut.from(key(96, "", .shift)) == "Shift+F5")
    assert(Shortcut.from(key(15, "r", [.command, .shift])) == "Primary+Shift+R")
    print("core ok")
}
