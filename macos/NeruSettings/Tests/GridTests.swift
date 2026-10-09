// Self-checks for the grid feature: characters and recursive-grid size checks.
func runGridTests() {
    let grid = ["`": ["action toggle_cursor_follow_selection"], "Space": ["action reset"], "Up": ["action move"]]

    assert(Neru.gridCharactersProblem("abcdefghijklmnpqrstuvwxyz", bound: grid) == nil)
    assert(Neru.gridCharactersProblem("ab;,", bound: grid) == nil)
    for bad in ["", "a", "aA", "abca", "ab c", "abé", "ab`"] {
        assert(Neru.gridCharactersProblem(bad, bound: grid) != nil, bad)
    }

    // Recursive grid: cells × keys must agree, at least two cells, keys distinct.
    assert(Neru.recursiveGridProblem(cols: 3, rows: 3, keys: "rtyfghvbn", bound: grid) == nil)
    assert(Neru.recursiveGridProblem(cols: 2, rows: 1, keys: "ab", bound: grid) == nil)
    assert(Neru.recursiveGridProblem(cols: 4, rows: 3, keys: "rtyfghvbn", bound: grid) != nil) // 12 cells, 9 keys
    assert(Neru.recursiveGridProblem(cols: 1, rows: 1, keys: "a", bound: grid) != nil)
    assert(Neru.recursiveGridProblem(cols: 2, rows: 2, keys: "abcA", bound: grid) != nil)
    assert(Neru.recursiveGridProblem(cols: 2, rows: 1, keys: "a`", bound: grid) != nil)
    print("grid ok")
}
