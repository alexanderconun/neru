// Self-checks for the per-app page: [[hints/scroll.app_configs]] round-trip.
import Foundation

func runPerAppTests() {
    // Entries as `config dump` has them: camelCase, null for unset, hotkeys as arrays.
    let dump = Neru.json("""
    {"hints": {"appConfigs": [
      {"bundleId": "com.apple.Safari", "strategy": "vision", "captureScope": "window", "labelDirection": "reverse",
       "additionalClickable": ["ax:AXCell", "row"], "ignoreClickableCheck": true, "visibleCheckEnabled": null,
       "scrollStep": null, "scrollStepHalf": null, "scrollStepFull": null,
       "hotkeys": {"Shift+G": ["__disabled__"], "x": ["action left_click", "idle"]}},
      {"bundleId": "com.Only.Hints", "strategy": "", "captureScope": "", "labelDirection": "",
       "additionalClickable": null, "ignoreClickableCheck": false, "visibleCheckEnabled": null, "hotkeys": null}
    ]},
    "scroll": {"appConfigs": [
      {"bundleId": "com.only.hints", "strategy": "", "scrollStep": 80, "scrollStepHalf": null, "scrollStepFull": 900,
       "ignoreClickableCheck": null, "hotkeys": {"j": ["action page_down"]}}
    ]}}
    """)!
    let hints = (dump["hints"] as! [String: Any])["appConfigs"] as! [[String: Any]]
    let scroll = (dump["scroll"] as! [String: Any])["appConfigs"] as! [[String: Any]]

    // Every set field round-trips, in a fixed order; nulls and empty strings are left out.
    let blocks = Neru.appConfigBlocks("hints", hints)
    assert(blocks[0] == [
        "[[hints.app_configs]]", "bundle_id = \"com.apple.Safari\"", "strategy = \"vision\"",
        "capture_scope = \"window\"", "label_direction = \"reverse\"",
        "additional_clickable_roles = [\"ax:AXCell\", \"row\"]", "ignore_clickable_check = true",
        "hotkeys = { \"Shift+G\" = \"__disabled__\", \"x\" = [\"action left_click\", \"idle\"] }",
    ], "\(blocks[0])")
    // A JSON false is a bool, not 0.
    assert(blocks[1] == ["[[hints.app_configs]]", "bundle_id = \"com.Only.Hints\"", "ignore_clickable_check = false"])
    let scrollBlock = Neru.appConfigBlocks("scroll", scroll)[0]
    assert(scrollBlock == ["[[scroll.app_configs]]", "bundle_id = \"com.only.hints\"", "scroll_step = 80",
                           "scroll_step_full = 900", "hotkeys = { \"j\" = \"action page_down\" }"], "\(scrollBlock)")

    // The list is the union of both sections, case-insensitive, first seen first.
    assert(Neru.bundleIDs(hints + scroll) == ["com.apple.Safari", "com.Only.Hints"])

    // Tri-states: Default (nil) removes the key, On/Off write Swift Bools as bools.
    var edited = Neru.setting(hints, id: "com.only.hints", key: "ignoreClickableCheck", to: nil)
    assert(Neru.setting(edited, "COM.ONLY.HINTS", "ignoreClickableCheck") == nil)
    edited = Neru.setting(edited, id: "com.apple.safari", key: "visibleCheckEnabled", to: false as Bool?)
    assert(Neru.appConfigBlocks("hints", edited)[0].contains("visible_check_enabled = false"))
    // An entry left with only bundle_id is dropped; case-insensitive lookup edited it, not a new one.
    assert(edited.count == 2 && Neru.appConfigBlocks("hints", edited).count == 1)

    // Picking Default for an app with no entry adds nothing.
    assert(Neru.setting(hints, id: "com.unknown", key: "strategy", to: nil).count == hints.count)

    // A new app gets an entry; Swift Ints write as TOML integers.
    var newScroll = Neru.setting(scroll, id: "com.new.App", key: "scrollStepHalf", to: 400)
    newScroll = Neru.setting(newScroll, id: "com.new.App", key: "scrollStep", to: 120)
    assert(Neru.appConfigBlocks("scroll", newScroll)[1] == [
        "[[scroll.app_configs]]", "bundle_id = \"com.new.App\"", "scroll_step = 120", "scroll_step_half = 400",
    ])

    // Two entries for one app in different case: the first wins.
    let twice: [[String: Any]] = [["bundleId": "com.dup", "strategy": "axtree"], ["bundleId": "COM.DUP", "strategy": "vision"]]
    assert(Neru.appConfigBlocks("hints", twice).count == 1 && Neru.appConfigBlocks("hints", twice)[0][2] == "strategy = \"axtree\"")

    // The rewrite drops old blocks and their [x.hotkeys] sub-tables, keeps every other table.
    let toml = """
    [general]
    excluded_apps = []

    [[hints.app_configs]]
    bundle_id = "com.apple.Safari"
    strategy = "vision"

    [hints.app_configs.hotkeys]
    "Shift+G" = "__disabled__"

    [[grid.app_configs]]
    bundle_id = "com.keep.me"
    capture_scope = "window"

    [[scroll.app_configs]]
    bundle_id = "com.only.hints"
    scroll_step = 80
    """
    let written = Neru.writeAppConfigs(toml, hints: Neru.removing(hints, "COM.APPLE.SAFARI"), scroll: scroll)
    assert(!written.contains("com.apple.Safari") && !written.contains("[hints.app_configs.hotkeys]"))
    assert(written.contains("[[grid.app_configs]]\nbundle_id = \"com.keep.me\"") && written.contains("excluded_apps = []"))
    assert(written.components(separatedBy: "[[scroll.app_configs]]").count == 2)
    assert(written.hasSuffix("scroll_step_full = 900\nhotkeys = { \"j\" = \"action page_down\" }\n"), written)

    // Removing the last app leaves no per-app tables at all.
    let empty = Neru.writeAppConfigs(toml, hints: [], scroll: [])
    assert(!empty.contains("hints.app_configs") && !empty.contains("scroll.app_configs") && empty.contains("[[grid.app_configs]]"))

    // Edits start from the dump's arrays, read the same way from any dump.
    assert(Neru.bundleIDs(Neru.appConfigs(dump, "hints")) == ["com.apple.Safari", "com.Only.Hints"])
    assert(Neru.appConfigs(dump, "grid").isEmpty)

    // Comments above the table after a removed block stay with that table.
    let middle = "a = 1\n\n[[hints.app_configs]]\nbundle_id = \"x\"\n# inside\nstrategy = \"vision\"\n\n# Scroll mode\n\n# See docs\n[scroll]\nb = 2"
    let moved = Neru.writeAppConfigs(middle, hints: [], scroll: [])
    assert(moved == "a = 1\n\n# Scroll mode\n\n# See docs\n[scroll]\nb = 2\n", moved)

    // Headers with a trailing comment or a CRLF line end are still replaced.
    for header in ["[[hints.app_configs]] # Safari needs OCR", "[[hints.app_configs]]\r"] {
        let odd = "[general]\n\(header)\nbundle_id = \"com.apple.Safari\"\n"
        let fixed = Neru.writeAppConfigs(odd, hints: Neru.removing(hints, "com.apple.safari"), scroll: [])
        assert(!fixed.contains("Safari") && fixed.hasPrefix("[general]\n\n[[hints.app_configs]]\nbundle_id = \"com.Only.Hints\""), fixed)
    }
    print("perapp ok")
}
