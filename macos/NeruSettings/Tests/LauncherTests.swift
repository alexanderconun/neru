// Self-checks for the hints launchers on the Clicking page.
import Foundation

func runLauncherTests() {
    func role(_ command: String) -> Neru.LauncherRole? { Neru.parseLauncher([command])?.role }

    // Every spelling of the action, flags in any order, extra spaces.
    for command in ["hints --action left_click", "hints -a left_click", "hints --action=left_click", "hints left_click", "hints  -a   left_click "] {
        assert(Neru.parseLauncher([command]) == Neru.Launcher(action: "left_click"), command)
    }
    assert(Neru.parseLauncher(["hints"]) == Neru.Launcher())
    assert(Neru.parseLauncher(["hints -r -a left_click"]) == Neru.Launcher(action: "left_click", repeats: true))
    assert(Neru.parseLauncher(["hints --hide-on-empty-search -s --repeat left_click"]) == nil) // positional only right after hints
    assert(Neru.parseLauncher(["hints left_click --hide-on-empty-search -s --repeat"])
        == Neru.Launcher(action: "left_click", repeats: true, search: true, hideOnEmpty: true))
    assert(role("hints") == .main && role("hints --repeat") == .main && role("hints -a left_click") == .main)
    assert(role("hints --search") == .search && role("hints -s --action=left_click -r") == .search)
    assert(role("hints right_click") == .rightClick && role("hints --action right_click") == .rightClick)
    assert(role("hints --action=left_click,left_click") == .doubleClick && role("hints -a left_click,left_click") == .doubleClick)
    // Not managed: other flags or actions, a missing value, a doubled action, step arrays, other modes.
    for command in ["hints --role AXButton", "hints middle_click", "hints --action", "hints -a left_click --action left_click",
                    "hints --hide-on-empty-search", "hints right_click --search", "hints right_click --repeat", "grid", "hintsx"] {
        assert(role(command) == nil, command)
    }
    assert(Neru.parseLauncher(["hints", "action search_hints"]) == nil)

    // Composition never writes a flag without the one it needs.
    var set = Neru.Launchers(autoClick: false, chain: true, hideLabels: true)
    assert(Neru.launcherCommand(.main, set) == "hints")
    assert(Neru.launcherCommand(.search, set) == "hints --search --hide-on-empty-search")
    set.autoClick = true
    assert(Neru.launcherCommand(.main, set) == "hints --action left_click --repeat")
    assert(Neru.launcherCommand(.search, set) == "hints --action left_click --repeat --search --hide-on-empty-search")
    assert(Neru.launcherCommand(.rightClick, set) == "hints --action right_click")
    assert(Neru.launcherCommand(.doubleClick, set) == "hints --action left_click,left_click")
    for each in Neru.LauncherRole.allCases { assert(Neru.parseLauncher([Neru.launcherCommand(each, set)])?.role == each) }

    // Reading the set from a dump: toggles come from the main launcher.
    let dump: [String: [String]] = [
        "Primary+Shift+Space": ["hints -a left_click -r"],
        "Ctrl+Alt+S": ["hints --search --action=left_click --hide-on-empty-search"],
        "Ctrl+Alt+R": ["hints right_click"],
        "Ctrl+Alt+H": ["hints --role AXButton"],
        "Primary+Shift+G": ["grid"],
        "Primary+Shift+S": ["scroll"],
    ]
    let (read, bound) = Neru.launchers(in: dump)
    assert(read == Neru.Launchers(combos: [.main: "Primary+Shift+Space", .search: "Ctrl+Alt+S", .rightClick: "Ctrl+Alt+R"],
                                  autoClick: true, chain: true, hideLabels: true))
    assert(Set(bound) == ["Primary+Shift+Space", "Ctrl+Alt+S", "Ctrl+Alt+R"])
    assert(Neru.launchers(in: ["Primary+Shift+Space": ["hints"]]).set.autoClick == false)

    // Conflicts: anything else bound refuses, a role's own combo does not.
    assert(Neru.launcherConflict("Primary+Shift+G", for: .search, in: dump) == "⌘⇧G is already used by \"grid\". Change or clear that one first.")
    assert(Neru.launcherConflict("Ctrl+Alt+S", for: .main, in: dump)?.contains("the search shortcut") == true)
    assert(Neru.launcherConflict("Ctrl+Alt+H", for: .main, in: dump)?.contains("hints --role AXButton") == true)
    assert(Neru.launcherConflict("ctrl+alt+r", for: .rightClick, in: dump) == nil)
    assert(Neru.launcherConflict("Cmd+Shift+J", for: .main, in: dump) == nil)
    assert(Neru.launcherConflict("Cmd+Shift+Space", for: .search, in: dump) != nil) // Primary is Cmd

    // The full rewrite: main moved, search added, right-click cleared.
    let toml = """
    [hotkeys]
    # mine
    "Primary+Shift+Space" = "hints -a left_click -r"
    "Ctrl+Alt+R" = "hints right_click"
    "Ctrl+Alt+H" = "hints --role AXButton"
    "primary+shift+j" = "__disabled__"

    [hints]
    hint_characters = "asdf"
    """
    let old = Neru.launchers(in: dump.filter { $0.key != "Ctrl+Alt+S" })
    var next = old.set
    next.combos = [.main: "Primary+Shift+J", .search: "Ctrl+Alt+S"]
    next.chain = false
    let out = Neru.rewriteLaunchers(toml, bound: old.bound, to: next)
    assert(out == """
    [hotkeys]
    "Primary+Shift+J" = "hints --action left_click"
    "Ctrl+Alt+S" = "hints --action left_click --search"
    "Primary+Shift+Space" = "__disabled__"
    # mine
    "Ctrl+Alt+H" = "hints --role AXButton"

    [hints]
    hint_characters = "asdf"
    """, out)

    // A default left in place is not disabled; the main line is written even
    // when only the default bound it (any hints line drops that default).
    let fresh = Neru.rewriteLaunchers("[general]\n", bound: ["Primary+Shift+Space"],
                                      to: Neru.Launchers(combos: [.main: "Primary+Shift+Space", .doubleClick: "Ctrl+Alt+D"]))
    assert(fresh == "[general]\n\n[hotkeys]\n\"Primary+Shift+Space\" = \"hints\"\n\"Ctrl+Alt+D\" = \"hints --action left_click,left_click\"", fresh)

    // A freed default that another role takes is not disabled.
    let swap = Neru.rewriteLaunchers(out, bound: ["Primary+Shift+J", "Ctrl+Alt+S"],
                                     to: Neru.Launchers(combos: [.main: "Primary+Shift+J", .search: "Primary+Shift+Space"]))
    assert(!swap.contains("__disabled__") && swap.contains("\"Primary+Shift+Space\" = \"hints --search\""), swap)
    assert(!swap.contains("Ctrl+Alt+S"), swap)

    // Clearing the last launcher when there is no main one keeps the default
    // main launcher away and never leaves [hotkeys] empty (that unbinds everything).
    let searchOnly = "[hotkeys]\n\"Ctrl+S\" = \"hints --search\"\n"
    let cleared = Neru.rewriteLaunchers(searchOnly, bound: ["Ctrl+S"], to: Neru.Launchers())
    assert(cleared == "[hotkeys]\n\"Primary+Shift+Space\" = \"__disabled__\"\n", cleared)
    // …but leaves a chord the file already binds alone.
    let kept = Neru.rewriteLaunchers(searchOnly + "\"Primary+Shift+Space\" = \"grid\"\n", bound: ["Ctrl+S"], to: Neru.Launchers())
    assert(kept == "[hotkeys]\n\"Primary+Shift+Space\" = \"grid\"\n", kept)

    // Cheat sheet: known commands in words, the rest as written, same action shares a row.
    assert(Neru.describeModeKey(["action cycle_hint --backward"]) == "Previous label")
    assert(Neru.describeModeKey(["action left_click --state=down"]) == "Press left button (start drag)")
    assert(Neru.describeModeKey(["action right_click"]) == "Right click")
    assert(Neru.describeModeKey(["action left_click", "idle"]) == "Left click, then Close labels")
    assert(Neru.describeModeKey(["macro click_and_exit"]) == "macro click_and_exit")
    let sheet = Neru.cheatSheet(["Escape": ["idle"], "Up": ["action move_mouse_relative --dx=0 --dy=-10"],
                                 "Down": ["action move_mouse_relative --dx=0 --dy=10"], "/": ["action search_hints"]])
    assert(sheet.map(\.what) == ["Close labels", "Nudge pointer", "Search labels"])
    assert(sheet[0].keys == "⎋" && sheet[1].keys == "↑ ↓")
    print("launcher ok")
}
