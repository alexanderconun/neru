// Core self-checks: the [hotkeys] rewrite and the config.toml text helpers.
import Foundation

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

    // Toggling automatic click swaps the command on the same combo.
    let auto = Neru.rebind(base, mode: "hints --action left_click", to: "Primary+Shift+Space", replacing: [])
    assert(auto.contains("\"Primary+Shift+Space\" = \"hints --action left_click\""))
    assert(!auto.contains("\"Primary+Shift+Space\" = \"hints\"") && !auto.contains("__disabled__"))

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

    // Waiting for permission: explicit code, or a live process with no socket.
    assert(Neru.isWaitingForAccessibility(dumpOK: false, output: "x (code: ERR_ACCESSIBILITY_DENIED)", daemonAlive: false))
    assert(Neru.isWaitingForAccessibility(dumpOK: false, output: "[IPC_SERVER_NOT_RUNNING] neru is not running", daemonAlive: true))
    assert(!Neru.isWaitingForAccessibility(dumpOK: false, output: "[IPC_SERVER_NOT_RUNNING] neru is not running", daemonAlive: false))
    assert(!Neru.isWaitingForAccessibility(dumpOK: true, output: "", daemonAlive: true))
    print("core ok")
}
