// Self-checks for the Tutorial and Training windows: step completion, the
// instructions, scoring and the board layout.
import Foundation

func runPracticeTests() {
    let now = Date()

    // Each step completes on its own rule, and only while it is the current one.
    func progress(at step: TutorialStep) -> TutorialProgress {
        var progress = TutorialProgress()
        progress.step = step
        return progress
    }
    var labels = progress(at: .showLabels)
    labels.modeChanged("hints", entered: true, windowIsKey: false, at: now) // labelled another window
    labels.modeChanged("grid", entered: true, windowIsKey: true, at: now)
    assert(labels.done.isEmpty)
    labels.modeChanged("hints", entered: true, windowIsKey: true, at: now)
    assert(labels.done == [.showLabels])

    var click = progress(at: .click)
    click.clicked("Click me", .right, at: now)
    click.clicked("Right-click me", .left, at: now)
    assert(click.done.isEmpty)
    click.clicked("Click me", .left, at: now)
    assert(click.done == [.click])

    var right = progress(at: .rightClick)
    right.clicked("Right-click me", .left, at: now)
    right.clicked("Click me", .left, at: now) // not this step's
    assert(right.done.isEmpty)
    right.clicked("Right-click me", .right, at: now)
    assert(right.done == [.rightClick])

    var search = progress(at: .search)
    search.clicked("Harbor", .left, at: now)
    search.clicked("Rocket", .right, at: now)
    assert(search.done.isEmpty)
    search.clicked("Rocket", .left, at: now)
    assert(search.done == [.search])

    var scroll = progress(at: .scroll)
    scroll.scrolled() // by hand
    assert(scroll.done.isEmpty)
    scroll.modeChanged("scroll", entered: true, windowIsKey: true, at: now)
    scroll.scrolled()
    assert(scroll.done == [.scroll])

    // The grid step needs a grid-type mode, or one that just ended (its click
    // can arrive after its exit).
    var grid = progress(at: .grid)
    grid.clicked(TutorialProgress.dot, .left, at: now)
    assert(grid.done.isEmpty)
    grid.modeChanged("bisect", entered: true, windowIsKey: true, at: now)
    grid.modeChanged("bisect", entered: false, windowIsKey: true, at: now)
    grid.clicked(TutorialProgress.dot, .left, at: now.addingTimeInterval(5))
    assert(grid.done.isEmpty)
    grid.clicked(TutorialProgress.dot, .left, at: now.addingTimeInterval(1))
    assert(grid.done == [.grid])
    var recursive = progress(at: .grid)
    recursive.modeChanged("recursive_grid", entered: true, windowIsKey: true, at: now)
    recursive.clicked("Click me", .left, at: now)
    assert(recursive.done.isEmpty)
    // Any button: a grid shortcut may right-click as it picks.
    recursive.clicked(TutorialProgress.dot, .right, at: now)
    assert(recursive.done == [.grid])
    // Showing a step starts it over: a grid that just ended on another
    // step (or before the step was picked again) does not carry over.
    var again = progress(at: .chain)
    again.modeChanged("grid", entered: true, windowIsKey: true, at: now)
    again.modeChanged("grid", entered: false, windowIsKey: true, at: now)
    again.step = .grid
    again.clicked(TutorialProgress.dot, .left, at: now)
    assert(again.done.isEmpty)

    // Chain clicks: all three in one labels session; an exit in between
    // starts over, and clicks without labels do not count.
    var chain = progress(at: .chain)
    for target in ["1", "2", "3"] { chain.clicked(target, .left, at: now) }
    assert(chain.done.isEmpty)
    chain.modeChanged("hints", entered: true, windowIsKey: true, at: now)
    chain.clicked("1", .left, at: now)
    chain.clicked("2", .left, at: now)
    chain.modeChanged("hints", entered: false, windowIsKey: true, at: now)
    chain.modeChanged("hints", entered: true, windowIsKey: true, at: now)
    chain.clicked("3", .left, at: now)
    assert(chain.done.isEmpty)
    chain.clicked("1", .left, at: now)
    chain.clicked("2", .right, at: now)
    assert(chain.done.isEmpty)
    chain.clicked("2", .left, at: now)
    assert(chain.done == [.chain])

    // Next runs off the end into the finished screen; Back comes back from it.
    var steps = progress(at: .chain)
    steps.next()
    assert(steps.step == nil)
    steps.back()
    assert(steps.step == .chain)
    steps.step = .showLabels
    steps.back()
    assert(steps.step == .showLabels)

    // Instructions follow the real shortcuts and click settings.
    let user: [String: Any] = ["hotkeys": ["bindings": ["Primary+Shift+Space": ["hints --action left_click"],
                                                        "Primary+Shift+S": ["scroll"], "Primary+Shift+G": ["grid"]]],
                               "hints": ["hotkeys": ["Escape": ["idle"], "/": ["action search_hints"],
                                                     "Shift+L": ["action left_click"], "Shift+R": ["action right_click"]]],
                               "scroll": ["hotkeys": Neru.defaultScrollHotkeys.mapValues { [$0] }]]
    assert(Neru.tutorialText(.showLabels, in: user)
        == "Press ⇧⌘Space to show labels. Letters appear on every button you can click. Press Escape to hide them.")
    assert(Neru.tutorialText(.click, in: user) == "Press ⇧⌘Space, then type the letters on Click me.")
    assert(Neru.tutorialText(.rightClick, in: user) == "Press ⇧⌘Space and type the label on Right-click me — the pointer is now on it. "
        + "Press ⇧⌘Space again and then Shift+R: it right-clicks where the pointer is. Then press Escape to hide the labels.")
    assert(Neru.tutorialText(.search, in: user) == "Press ⇧⌘Space, then /, type rocket and press Return.")
    assert(Neru.tutorialText(.scroll, in: user) == "Put the pointer over the list and press ⇧⌘S. J and K scroll down and up, "
        + "D and U by half a page, gg goes to the top and Shift+G to the bottom. Escape stops.")
    assert(Neru.tutorialText(.grid, in: user) == "Press ⇧⌘G, type the letters of the cell with the dot, then the letter of the small square "
        + "on the dot. Press Shift+L to click, then Escape to close the grid.")
    assert(Neru.tutorialCommand(.click, in: user) == ["hints", "--action", "left_click"])
    assert(Neru.tutorialCommand(.rightClick, in: user) == ["hints", "--action", "left_click"])
    assert(Neru.tutorialCommand(.scroll, in: user) == ["scroll"])
    assert(Neru.tutorialCommand(.grid, in: user) == ["grid"])

    // Move-only labels: typing a label moves the pointer, Shift+L/R click there.
    let moveOnly = ["hotkeys": ["bindings": ["Primary+Shift+Space": ["hints"],
                                             "Ctrl+R": ["hints --action right_click"], "Ctrl+F": ["hints --search"]]]]
    assert(Neru.tutorialText(.click, in: moveOnly).hasSuffix("The pointer moves there; press Shift+L to click, then Escape to hide the labels."))
    assert(Neru.tutorialText(.rightClick, in: moveOnly) == "Press ⌃R and type the label on Right-click me.")
    assert(Neru.tutorialText(.search, in: moveOnly).hasPrefix("Press ⌃F, type rocket and press Return. The pointer moves to Rocket"))
    assert(Neru.tutorialText(.chain, in: moveOnly).hasSuffix("Chain clicks needs Automatic click: turn that on in Settings › Clicking first."))
    assert(Neru.tutorialCommand(.rightClick, in: moveOnly) == ["hints", "--action", "right_click"])
    assert(Neru.tutorialCommand(.search, in: moveOnly) == ["hints", "--search"])
    let moveOnlyRight = ["hotkeys": ["bindings": ["Primary+Shift+Space": ["hints"]]]]
    assert(Neru.tutorialText(.rightClick, in: moveOnlyRight).contains("the pointer moves there. Press Shift+R"))

    // Chain clicks: the labels come back after the click.
    let chained = ["hotkeys": ["bindings": ["Primary+Shift+Space": ["hints --action left_click --repeat"]]]]
    assert(Neru.tutorialText(.click, in: chained).hasSuffix("The labels come back after the click; press Escape to hide them."))
    assert(Neru.tutorialText(.rightClick, in: chained).contains("it is clicked, the pointer stays on it and the labels come back. Press Shift+R"))
    // A chained search launcher reopens searching: Escape closes the search first.
    let searchChained = ["hotkeys": ["bindings": ["Primary+Shift+Space": ["hints --action left_click --repeat"],
                                                  "Ctrl+Alt+F": ["hints --action left_click --repeat --search"]]]]
    assert(Neru.tutorialText(.search, in: searchChained) == "Press ⌃⌥F, type rocket and press Return. The labels and the search come back "
        + "after the click; press Escape to close the search, then Escape to hide the labels.")
    assert(Neru.tutorialText(.search, in: chained).hasSuffix("The labels come back after the click; press Escape to hide them."))

    // Launchers with flags the Clicking page leaves alone still have their
    // shortcut, click as they do, and Try it here runs them as bound. A
    // managed launcher wins over one bound earlier with other flags.
    let unmanaged = ["hotkeys": ["bindings": ["Primary+Shift+Space": ["hints --action left_click --exit-on-unmatched"],
                                              "Primary+Shift+G": ["grid --action left_click"], "Primary+Shift+S": ["scroll"]]]]
    assert(Neru.tutorialText(.click, in: unmanaged) == "Press ⇧⌘Space, then type the letters on Click me.")
    assert(Neru.tutorialCommand(.click, in: unmanaged) == ["hints", "--action", "left_click", "--exit-on-unmatched"])
    assert(Neru.tutorialText(.grid, in: unmanaged)
        == "Press ⇧⌘G, type the letters of the cell with the dot, then the letter of the small square on the dot. The grid clicks there.")
    assert(Neru.tutorialCommand(.grid, in: unmanaged) == ["grid", "--action", "left_click"])
    assert(Neru.tutorialSummary(in: unmanaged).map(\.keys) == ["⇧⌘Space", "⇧⌘Space, then /", "⇧⌘S", "⇧⌘G"])
    // Its clicks still count, but the Chain clicks switch edits the Clicking
    // page's own launchers, and there is none: the text says to set one up.
    assert(Neru.tutorialText(.chain, in: unmanaged).hasSuffix("without pressing ⇧⌘Space again. Chain clicks needs a Clicking shortcut "
        + "with Automatic click: set one up in Settings › Clicking first."))
    assert(Neru.tutorialText(.chain, in: chained).hasSuffix("without pressing ⇧⌘Space again."))
    // A grid shortcut that right-clicks as it picks clicks there too.
    let rightClickGrid = ["hotkeys": ["bindings": ["Ctrl+G": ["grid --action right_click"]]]]
    assert(Neru.tutorialText(.grid, in: rightClickGrid).hasSuffix("on the dot. The grid clicks there."))
    let both = ["hotkeys": ["bindings": ["Ctrl+H": ["hints --role link"], "Primary+Shift+Space": ["hints --action left_click"],
                                         "Ctrl+G": ["grid --action right_click"], "Primary+Shift+G": ["grid"]]]]
    assert(Neru.tutorialCommand(.click, in: both) == ["hints", "--action", "left_click"])
    assert(Neru.tutorialCommand(.grid, in: both) == ["grid"])

    // Only a search shortcut: Try it here runs it without its search, so
    // typing a label clicks as the text says; the menu bar's labels would not.
    let searchOnly = ["hotkeys": ["bindings": ["Ctrl+F": ["hints --action left_click --search --hide-on-empty-search"]]]]
    assert(Neru.tutorialCommand(.click, in: searchOnly) == ["hints", "--action", "left_click"])
    assert(Neru.tutorialCommand(.search, in: searchOnly) == ["hints", "--action", "left_click", "--search", "--hide-on-empty-search"])
    assert(Neru.tutorialText(.click, in: searchOnly)
        == "Labels have no shortcut yet. Use Try it here, or set one in Settings › Clicking. Show the labels, then type the letters on Click me.")
    // Showing the labels again takes a click, which moves the pointer: Tab moves it back.
    assert(Neru.tutorialText(.rightClick, in: searchOnly) == "Labels have no shortcut yet. Use Try it here, or set one in Settings › Clicking. "
        + "Show the labels, press Tab until the pointer is on Right-click me, then press Shift+R: it right-clicks where the pointer is. "
        + "Then press Escape to hide the labels.")

    // No shortcuts at all: say so and point to Try it here and Settings.
    let none = ["hotkeys": ["bindings": [String: [String]]()], "systray": ["enabled": false]]
    assert(Neru.tutorialText(.scroll, in: none)
        .hasPrefix("Scroll mode has no shortcut yet. Use Try it here, or set one in Settings › Scrolling. J and K"))
    assert(Neru.tutorialText(.showLabels, in: none).hasPrefix("Labels have no shortcut yet. Use Try it here, or set one in Settings › Clicking."))
    assert(Neru.tutorialText(.grid, in: ["hotkeys": ["bindings": [String: [String]]()]])
        .hasPrefix("The grid has no shortcut yet. Use Try it here, the menu bar icon, or set one in Settings › Grid. Type the letters"))
    assert(Neru.tutorialCommand(.click, in: none) == ["hints"])
    assert(Neru.tutorialSummary(in: none).allSatisfy { $0.keys == "No shortcut" })
    // No Clicking or search shortcut: Automatic click cannot stay on until there is one.
    assert(Neru.tutorialText(.chain, in: none).hasSuffix("Chain clicks needs a Clicking shortcut with Automatic click: set one up in Settings › Clicking first."))
    let ownLabels = ["hotkeys": ["bindings": ["Ctrl+H": ["hints --role link"]]]]
    assert(Neru.tutorialText(.chain, in: ownLabels).hasSuffix("set one up in Settings › Clicking first."))

    // Inverted scrolling turns every scroll key around.
    var inverted = user
    inverted["scroll"] = ["hotkeys": Neru.defaultScrollHotkeys.mapValues { [$0] }, "invertScroll": true]
    assert(Neru.tutorialText(.scroll, in: inverted).contains("K and J scroll down and up, U and D by half a page, Shift+G goes to the top and gg"))
    // The daemon's own direction wins over the config's: the menu bar flips it.
    assert(Neru.tutorialText(.scroll, in: user, inverted: true).contains("K and J scroll down and up"))
    assert(Neru.tutorialText(.scroll, in: inverted, inverted: false).contains("J and K scroll down and up"))

    // Without Automatic click, Return on a search only moves the pointer.
    assert(TrainingRound.search.prompt("Redo") == "Search for Redo and press Return")
    assert(TrainingRound.search.prompt("Redo", clickKey: "Shift+L") == "Search for Redo, press Return, then Shift+L")

    // Scoring: a hit is the round's click on the target, anything else a
    // miss; a round is ten hits, and a press after it counts for nothing.
    var score = TrainingScore(click: .right)
    assert(!score.press(onTarget: true, .left, after: 1) && score.misses == 0, "a label's left click on the way: neither")
    assert(!score.press(onTarget: false, .left, after: 1))
    assert(!score.press(onTarget: true, .middle, after: 1))
    assert(score.press(onTarget: true, .right, after: 1))
    assert(score.press(onTarget: true, .right, after: 2))
    assert(score.hits == 2 && score.misses == 2 && score.average == 1.5)
    var clicking = TrainingScore(click: .left)
    _ = clicking.press(onTarget: true, .right, after: 1)
    assert(clicking.misses == 1, "the wrong button")
    for _ in 0 ..< 7 { _ = score.press(onTarget: true, .right, after: 1.5) }
    assert(!score.finished)
    assert(score.press(onTarget: true, .right, after: 1.5))
    assert(score.finished && score.hits == TrainingScore.hitsPerRound && score.average == 1.5)
    assert(!score.press(onTarget: true, .right, after: 1) && score.hits == 10 && score.misses == 2)
    assert(TrainingScore(click: .left).average == nil)

    // A best is only beaten by a lower average.
    assert(TrainingScore.isNewBest(1.2, than: nil))
    assert(TrainingScore.isNewBest(1.2, than: 1.3))
    assert(!TrainingScore.isNewBest(1.3, than: 1.3))
    assert(!TrainingScore.isNewBest(1.4, than: 1.3))
    // A new best shows as the best at once, even where nothing is kept.
    let played = Training(defaults: nil)
    played.start()
    for _ in 0 ..< TrainingScore.hitsPerRound { played.press(played.board.target, .left, at: played.board.shownAt + 1.25) }
    assert(played.newBest && played.best == 1.25)
    played.round = .grid
    assert(played.best == nil)

    // Placement: in bounds with the margin, at least 10 pt apart, on whole
    // points, as many as asked (as homekey-rs's placement_never_overlaps…).
    let board = CGSize(width: 720, height: 380)
    let inside = CGRect(origin: .zero, size: board).insetBy(dx: 16, dy: 16)
    for (count, size) in [(12, TrainingBoard.buttonSize), (24, TrainingBoard.buttonSize), (1, TrainingBoard.dotSize)] {
        for _ in 0 ..< 200 {
            let frames = TrainingBoard.place(count, size: size, in: board)
            assert(frames.count == count)
            for (index, frame) in frames.enumerated() {
                assert(inside.contains(frame) && frame.minX == frame.minX.rounded() && frame.minY == frame.minY.rounded(), "\(frame)")
                for other in frames[(index + 1)...] { assert(!frame.insetBy(dx: -9.5, dy: -9.5).intersects(other), "\(frame) \(other)") }
            }
        }
    }
    assert(TrainingBoard.place(24, size: TrainingBoard.buttonSize, in: CGSize(width: 300, height: 100)).count < 24)
    assert(TrainingBoard.place(3, size: TrainingBoard.buttonSize, in: CGSize(width: 50, height: 50)).isEmpty)

    // Deals: the round's number of buttons, a target other than the last one,
    // and words a search tells apart (none inside another).
    for round in TrainingRound.allCases {
        let deal = TrainingBoard.deal(round, in: board, avoiding: nil)
        assert(deal.words.count == max(round.buttons, 1) && deal.frames.count == deal.words.count)
    }
    for _ in 0 ..< 100 {
        let deal = TrainingBoard.deal(.clicking, in: board, avoiding: "Save")
        assert(deal.words[deal.target] != "Save")
    }
    // A search finds one word only: none holds another, or is held by the
    // window's controls or a Dock or menu bar title there by default.
    let words = TrainingBoard.words.map { $0.lowercased() }
    assert(Set(words).count == 24)
    let others = ["clicking", "right-click", "search", "grid", "start", "stop", "finder", "downloads", "trash", "clock",
                  "settings", "safari", "mail", "notes", "music", "photos", "calendar", "control center", "spotlight",
                  "wi-fi", "battery", "launchpad", "now playing"]
    for word in words {
        func holds(_ text: String) -> Bool { text.contains(word) || word.contains(text) }
        assert(words.filter(holds) == [word] && !others.contains(where: holds), word)
    }
    print("practice ok")
}
