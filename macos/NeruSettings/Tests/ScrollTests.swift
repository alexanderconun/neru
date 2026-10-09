// Self-checks for the scroll feature: scroll-key checks and the [scroll.hotkeys] rewrites.
func runScrollTests() {
    let defaults = Neru.defaultScrollHotkeys.mapValues { [$0] }
    assert(Neru.defaultScrollKeys == ["h", "j", "k", "l"])
    assert(Neru.directionKeys(defaults) == [["h"], ["j"], ["k"], ["l"]])

    // Checks: four distinct printable keys, case folded, directions may be reshuffled.
    for ok in ["hjkl", "HJKL", "lkjh", "hnei", "zxcv", ";,./"] {
        assert(Neru.scrollKeysProblem(ok, bindings: defaults) == nil, ok)
    }
    for bad in ["hjk", "hjklm", "hjkh", "hjkH", "hjk ", "hjké", "hjkg", "hjku", "dhjk"] {
        assert(Neru.scrollKeysProblem(bad, bindings: defaults) != nil, bad)
    }
    // "g" is only refused while "gg" is bound; "Up" is no sequence, so a free "u" passes.
    assert(Neru.scrollKeysProblem("hjkg", bindings: defaults.filter { $0.key != "gg" }) == nil)
    assert(Neru.scrollKeysProblem("hjku", bindings: defaults.filter { $0.key != "u" }) == nil)

    let table = """
    [scroll]
    scroll_step = 50

    [scroll.hotkeys]
    "Escape" = "idle"
    "k" = "action scroll_up"
    "j" = "action scroll_down"
    "h" = "action scroll_left"
    "l" = "action scroll_right"
    "u" = "action page_up"
    "Up" = "action move_mouse_relative --dx=0 --dy=-10"
    "Down" = "action move_mouse_relative --dx=0 --dy=10"
    "Left" = "action move_mouse_relative --dx=-10 --dy=0"
    "Right" = "action move_mouse_relative --dx=10 --dy=0"

    [mode_indicator]
    """

    // Colemak positions: h stays, j k l are disabled, everything else stays.
    let colemak = Neru.rewriteScrollKeys(table, to: "HNEI", bindings: defaults)
    let scroll = Neru.tableKeys(colemak, header: "scroll.hotkeys")
    assert(colemak.contains("\"h\" = \"action scroll_left\"") && colemak.contains("\"n\" = \"action scroll_down\""))
    assert(colemak.contains("\"e\" = \"action scroll_up\"") && colemak.contains("\"i\" = \"action scroll_right\""))
    for key in ["j", "k", "l"] { assert(colemak.contains("\"\(key)\" = \"__disabled__\"")) }
    assert(scroll.count == Set(scroll).count && scroll.contains("Escape") && scroll.contains("u") && scroll.contains("Up"))
    assert(colemak.contains("scroll_step = 50") && colemak.contains("[mode_indicator]"))

    // Back to the defaults: the remapped and disabled lines go.
    var after = defaults
    for key in ["j", "k", "l"] { after[key] = nil }
    for (key, dir) in zip(["n", "e", "i"], ["down", "up", "right"]) { after[key] = ["action scroll_\(dir)"] }
    let back = Neru.rewriteScrollKeys(colemak, to: "hjkl", bindings: after)
    assert(!back.contains("__disabled__") && !back.contains("\"n\"") && !back.contains("\"e\"") && !back.contains("\"i\""))
    assert(back.contains("\"j\" = \"action scroll_down\"") && back.contains("\"l\" = \"action scroll_right\""))

    // Swapping directions reuses the defaults, so nothing is disabled.
    let swapped = Neru.rewriteScrollKeys(table, to: "lkjh", bindings: defaults)
    assert(swapped.contains("\"l\" = \"action scroll_left\"") && !swapped.contains("__disabled__"))
    assert(Neru.tableKeys(swapped, header: "scroll.hotkeys").filter { $0.count == 1 }.count == 5) // h j k l u

    // No table yet: one is added with the four directions and the disabled defaults.
    let fresh = Neru.rewriteScrollKeys("[general]\n", to: "hnei", bindings: defaults)
    assert(Neru.tableKeys(fresh, header: "scroll.hotkeys") == ["h", "n", "e", "i", "j", "k", "l"])

    // Arrow keys: scroll replaces the pointer moves; move pointer drops the lines again.
    let arrows = Neru.rewriteArrows(table, scroll: true)
    assert(arrows.contains("\"Up\" = \"action scroll_up\"") && !arrows.contains("move_mouse_relative"))
    var arrowBindings = defaults
    for (key, dir) in zip(Neru.arrowKeys, Neru.scrollDirections) { arrowBindings[key] = ["action scroll_\(dir)"] }
    assert(Neru.arrowsScroll(in: arrowBindings) && !Neru.arrowsScroll(in: defaults))
    let pointer = Neru.rewriteArrows(arrows, scroll: false)
    assert(!pointer.contains("\"Up\"") && pointer.contains("\"Escape\" = \"idle\""))

    // The arrows alone in the table: dropping them would leave it empty and
    // clear Escape, so their defaults are written out instead.
    let only = Neru.rewriteArrows("[general]\n", scroll: true)
    assert(Neru.tableKeys(only, header: "scroll.hotkeys") == Neru.arrowKeys)
    let restored = Neru.rewriteArrows(only, scroll: false)
    assert(Neru.tableKeys(restored, header: "scroll.hotkeys") == Neru.arrowKeys)
    assert(restored.contains("\"Up\" = \"action move_mouse_relative --dx=0 --dy=-10\""))
    assert(!Neru.tableKeys(Neru.rewriteArrows("[general]\n", scroll: false), header: "scroll.hotkeys").isEmpty)
    print("scroll ok")
}
