import AppKit
import SwiftUI

/// The Tutorial window: seven steps that each practise one way of using
/// labels, on targets in the window itself, with instructions written from
/// the user's own shortcuts.
struct TutorialView: View {
    @EnvironmentObject var neru: Neru
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var progress: TutorialProgress
    @State private var listAnchor = AnchorView()
    @State private var listOffset: CGFloat?

    init(progress: TutorialProgress = TutorialProgress()) {
        _progress = State(initialValue: progress)
    }

    var body: some View {
        VStack(spacing: 0) {
            PracticeBanners()
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Neru.appName) Tutorial").font(.title2.bold())
                    Spacer()
                    Text(progress.step.map { "Step \($0.rawValue + 1) of \(TutorialStep.allCases.count)" } ?? "Finished")
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 16) {
                    stepList
                    if let step = progress.step { stepPage(step) } else { finished }
                }
            }
            .padding(20)
        }
        .frame(width: 760, height: 560)
        .onAppear { neru.watchModes(true) }
        .onDisappear { neru.watchModes(false) }
        .onReceive(neru.modeEvents) { event in
            progress.modeChanged(event.mode, entered: event.entered, windowIsKey: activeState == .key, at: Date())
            if event.entered, event.mode == "scroll" { neru.readScrollInverted() }
        }
        // The menu bar flips scrolling without a config change or an event:
        // read it again whenever the scroll step may be read.
        .onChange(of: activeState, initial: true) { _, state in if state == .key { neru.readScrollInverted() } }
        .onChange(of: progress.step) { _, step in if step == .scroll { neru.readScrollInverted() } }
    }

    private var stepList: some View {
        PracticeCard {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(TutorialStep.allCases) { step in
                    let current = step == progress.step
                    Button { progress.step = step } label: {
                        HStack(spacing: 8) {
                            if progress.done.contains(step) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if current {
                                Image(systemName: "play.circle.fill").foregroundStyle(Color.accentColor)
                            } else {
                                Image(systemName: "circle").foregroundStyle(.tertiary)
                            }
                            Text(step.title).fontWeight(current ? .semibold : .regular)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .contentShape(Rectangle())
                        .background(current ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 200)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func stepPage(_ step: TutorialStep) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.title).font(.headline)
            Text(Neru.tutorialText(step, in: neru.config, inverted: neru.scrollInverted))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            PracticeCard { practice(step).frame(maxWidth: .infinity, maxHeight: .infinity) }
                .overlay(alignment: .topTrailing) {
                    if progress.done.contains(step) {
                        Label("Nice!", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(.green).padding(12)
                    }
                }
            HStack {
                Button("Try it here") { tryIt(step) }
                Spacer()
                Button("Back") { progress.back() }.disabled(step == .showLabels)
                Button("Skip") { progress.next() }
                let next = step == .chain ? "Done" : "Next →"
                if progress.done.contains(step) {
                    Button(next) { progress.next() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button(next) { progress.next() }
                }
            }
        }
    }

    @ViewBuilder private func practice(_ step: TutorialStep) -> some View {
        switch step {
        case .showLabels:
            HStack(spacing: 12) {
                ForEach(["Apple", "Banana", "Cherry"], id: \.self) { PracticeButton(title: $0) { _ in }.frame(width: 96) }
            }
        case .click:
            target("Click me").fixedSize()
        case .rightClick:
            target("Right-click me").fixedSize()
        case .search:
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach([TutorialProgress.places.prefix(4), TutorialProgress.places.suffix(4)], id: \.self) { row in
                    GridRow { ForEach(row, id: \.self) { target($0).frame(width: 96) } }
                }
            }
        case .scroll:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(1...40, id: \.self) { row in
                        Text("Row \(row)").padding(.vertical, 5).padding(.horizontal, 10)
                        Divider()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ScrollOffsetKey.self, value: geometry.frame(in: .named("list")).minY)
                })
            }
            .coordinateSpace(name: "list")
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                // Only a change counts: the first value is the list being laid out.
                if let listOffset, listOffset != offset { progress.scrolled() }
                listOffset = offset
            }
            .onDisappear { listOffset = nil }
            .background(ViewAnchor(view: listAnchor))
            .frame(width: 280)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        case .grid:
            PracticeDot(size: 22) { progress.clicked(TutorialProgress.dot, $0, at: Date()) }
                .frame(width: DotView.side, height: DotView.side)
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 79) // its middle 115 pt in from the card's edge
        case .chain:
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Toggle("Chain clicks", isOn: Binding(get: { neru.launchers.chain }, set: { on in
                        neru.setLaunchers { set, _ in set.chain = on }
                    }))
                    .toggleStyle(.switch)
                    .disabled(!neru.launchers.autoClick)
                    if neru.launchers.autoClick {
                        Text("You can turn it off again here or in Settings").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) { ForEach(["1", "2", "3"], id: \.self) { target($0).frame(width: 56) } }
            }
        }
    }

    private func target(_ title: String) -> PracticeButton {
        PracticeButton(title: title) { progress.clicked(title, $0, at: Date()) }
    }

    private var finished: some View {
        let shortcuts = Neru.tutorialSummary(in: neru.config)
        return VStack(alignment: .leading, spacing: 14) {
            Text("You're all set.").font(.headline)
            PracticeCard {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    ForEach(shortcuts, id: \.what) { row in
                        GridRow {
                            Text(row.what)
                            Text(row.keys).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("Open Training") { openWindow(id: "training") }
                Button("Done") { dismissWindow(id: "tutorial") }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Starts the step's mode as its shortcut would. For scrolling, the
    /// pointer goes over the list first: scroll mode scrolls under it.
    private func tryIt(_ step: TutorialStep) {
        NSApp.activate()
        if step == .scroll, let window = listAnchor.window {
            let rect = window.convertToScreen(listAnchor.convert(listAnchor.bounds, to: nil))
            // CoreGraphics counts down from the top of the main screen.
            CGWarpMouseCursorPosition(CGPoint(x: rect.midX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - rect.midY))
        }
        let command = Neru.tutorialCommand(step, in: neru.config)
        // ponytail: a fixed pause for the click on this button to finish (a
        // label's click ends its mode first) and for this window to be the
        // focused one the mode scans; wait for didBecomeActive if it proves short.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { neru.runMode(command) }
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: pure logic (covered by Tests/PracticeTests.swift)

enum TutorialStep: Int, CaseIterable, Identifiable {
    case showLabels, click, rightClick, search, scroll, grid, chain
    var id: Self { self }

    var title: String {
        switch self {
        case .showLabels: "Show labels"
        case .click: "Click with a label"
        case .rightClick: "Right-click"
        case .search: "Search"
        case .scroll: "Scroll"
        case .grid: "Grid"
        case .chain: "Chain clicks"
        }
    }
}

/// Where the tutorial is and what it has seen. Only the current step can be
/// completed; the daemon's mode comes from `neru watch`, and clicks from the
/// practice targets, named by their titles.
struct TutorialProgress {
    /// The search step's targets.
    static let places = ["Anchor", "Bridge", "Castle", "Desert", "Rocket", "Forest", "Garden", "Harbor"]
    /// The grid step's target, which has no title.
    static let dot = "dot"
    /// The modes that point with a grid.
    static let gridModes: Set = ["grid", "recursive_grid", "bisect"]

    /// nil past the last step: the finished screen. Every step shown starts
    /// from scratch: a grid or chain from before does not carry over.
    var step: TutorialStep? = .showLabels {
        didSet {
            gridLeft = .distantPast
            chained = []
        }
    }
    var done: Set<TutorialStep> = []
    private(set) var mode = "idle"
    private var gridLeft = Date.distantPast
    private var chained: Set<String> = []

    mutating func next() { step = step.flatMap { TutorialStep(rawValue: $0.rawValue + 1) } }

    mutating func back() { step = TutorialStep(rawValue: (step?.rawValue ?? TutorialStep.allCases.count) - 1) ?? .showLabels }

    /// A mode_enter (`entered`) or mode_exit. Labels count as shown only
    /// while this window was key, so it was the window they labelled.
    mutating func modeChanged(_ name: String, entered: Bool, windowIsKey: Bool, at now: Date) {
        if entered {
            mode = name
        } else if mode == name {
            mode = "idle"
        }
        if !entered, Self.gridModes.contains(name) { gridLeft = now }
        // A chain is one labels session: it starts empty and ends at the exit.
        if name == "hints" { chained = [] }
        if entered, name == "hints", windowIsKey { complete(.showLabels) }
    }

    mutating func clicked(_ target: String, _ kind: ClickKind, at now: Date) {
        switch (target, kind) {
        case ("Click me", .left): complete(.click)
        case ("Right-click me", .right): complete(.rightClick)
        // Search state is not watchable; a click on Rocket is the proof.
        case ("Rocket", .left): complete(.search)
        // A grid with an action clicks as it ends, and its exit may arrive
        // first; any button, as the grid shortcut may right-click.
        case (Self.dot, _) where Self.gridModes.contains(mode) || now.timeIntervalSince(gridLeft) < 2:
            complete(.grid)
        case (_, .left) where ["1", "2", "3"].contains(target) && mode == "hints":
            chained.insert(target)
            if chained.count == 3 { complete(.chain) }
        default:
            break
        }
    }

    mutating func scrolled() {
        if mode == "scroll" { complete(.scroll) }
    }

    private mutating func complete(_ step: TutorialStep) {
        if step == self.step { done.insert(step) }
    }
}

extension Neru {
    /// The instructions for `step`, written from the shortcuts and in-mode
    /// keys in `dump`, the way they really behave with its click settings.
    /// `inverted` is the daemon's scroll direction when known (see PracticeKeys).
    static func tutorialText(_ step: TutorialStep, in dump: [String: Any], inverted: Bool? = nil) -> String {
        let keys = PracticeKeys(dump, inverted: inverted)
        let hints = keys.shortcut(.main)
        let escape = keys.hintsKey("idle", or: "Escape")
        let leftClick = keys.hintsKey("action left_click", or: "Shift+L")
        let rightClick = keys.hintsKey("action right_click", or: "Shift+R")
        // The menu bar's labels only move the pointer: with Automatic click on
        // they would not do what the text says (Try it here does).
        let noHints = keys.missing("Labels have", page: "Clicking", menuBar: !keys.launchers.autoClick)
        let show = hints.map { "Press \($0)" } ?? "\(noHints) Show the labels"
        // Typing a label clicks with Automatic click, and Chain clicks brings the labels back.
        let afterClick = !keys.launchers.autoClick
            ? " The pointer moves there; press \(leftClick) to click, then \(escape) to hide the labels."
            : keys.launchers.chain ? " The labels come back after the click; press \(escape) to hide them." : ""
        switch step {
        case .showLabels:
            return "\(hints.map { "Press \($0) to show labels." } ?? noHints) Letters appear on every button you can click. Press \(escape) to hide them."
        case .click:
            return "\(show), then type the letters on Click me.\(afterClick)"
        case .rightClick:
            if let shortcut = keys.shortcut(.rightClick) { return "Press \(shortcut) and type the label on Right-click me." }
            // Pointer keys act where the pointer is: hints keep no selection.
            let rightClickThere = "Press \(rightClick): it right-clicks where the pointer is. Then press \(escape) to hide the labels."
            if !keys.launchers.autoClick {
                return "\(show) and type the label on Right-click me: the pointer moves there. \(rightClickThere)"
            }
            if keys.launchers.chain {
                return "\(show) and type the label on Right-click me: it is clicked, the pointer stays on it and the labels come back. \(rightClickThere)"
            }
            // Showing the labels again without a shortcut takes a click, which
            // moves the pointer: Tab (cycle_hint) moves it back without clicking.
            guard let hints else {
                return "\(noHints) Show the labels, press \(keys.hintsKey("action cycle_hint", or: "Tab")) until the pointer is on Right-click me, then press \(rightClick): it right-clicks where the pointer is. Then press \(escape) to hide the labels."
            }
            return "Press \(hints) and type the label on Right-click me — the pointer is now on it. Press \(hints) again and then \(rightClick): it right-clicks where the pointer is. Then press \(escape) to hide the labels."
        case .search:
            let shortcut = keys.shortcut(.search)
            let search = shortcut.map { "Press \($0)" } ?? "\(show), then \(keys.hintsKey("action search_hints", or: "/"))"
            // Return with one match: clicks it with Automatic click, else only moves the pointer there.
            let afterReturn = !keys.launchers.autoClick
                ? " The pointer moves to Rocket; press \(leftClick) to click it, then \(escape) to hide the labels."
                // A chained search launcher reopens with its search, and only Escape cancels a search.
                : shortcut != nil && keys.launchers.chain
                ? " The labels and the search come back after the click; press Escape to close the search, then \(escape) to hide the labels."
                : afterClick
            return "\(search), type rocket and press Return.\(afterReturn)"
        case .scroll:
            let start = keys.shortcut(mode: "scroll").map { "Put the pointer over the list and press \($0)." }
                ?? keys.missing("Scroll mode has", page: "Scrolling", menuBar: false)
            // Inverted scrolling flips every direction, the jumps included.
            let (down, up, top, bottom) = keys.inverted ? ("up", "down", "bottom", "top") : ("down", "up", "top", "bottom")
            func key(_ action: String, _ fallback: String) -> String { keys.scrollKey("action \(action)", or: fallback) }
            return "\(start) \(key("scroll_\(down)", "J")) and \(key("scroll_\(up)", "K")) scroll down and up, "
                + "\(key("page_\(down)", "D")) and \(key("page_\(up)", "U")) by half a page, "
                + "\(key("go_\(top)", "gg")) goes to the top and \(key("go_\(bottom)", "Shift+G")) to the bottom. "
                + "\(keys.scrollKey("idle", or: "Escape")) stops."
        case .grid:
            let pick = "the letters of the cell with the dot, then the letter of the small square on the dot."
            let start = keys.shortcut(mode: "grid").map { "Press \($0), type \(pick)" }
                ?? "\(keys.missing("The grid has", page: "Grid", menuBar: true)) Type \(pick)"
            // A grid with an action clicks as it picks; otherwise the pick only
            // sets the point, and the grid stays up until Escape.
            if keys.gridClicks { return "\(start) The grid clicks there." }
            return "\(start) Press \(keys.gridKey("action left_click", or: "Shift+L")) to click, then \(keys.gridKey("idle", or: "Escape")) to close the grid."
        case .chain:
            let without = hints.map { "without pressing \($0) again" } ?? "without showing the labels again"
            let text = "With Chain clicks on, labels come back after every click until you press \(escape). Turn it on, then click 1, 2 and 3 \(without)."
            let lead = hints == nil ? "\(noHints) " : ""
            // The switch edits the Clicking page's own launchers, which a
            // user's launcher with other flags is not: it needs one of those.
            let needs = Neru.launchers(in: keys.bindings).autoClick ? ""
                : keys.launchers.autoClick ? " Chain clicks needs a Clicking shortcut with Automatic click: set one up in Settings › Clicking first."
                : " Chain clicks needs Automatic click: turn that on in Settings › Clicking first."
            return lead + text + needs
        }
    }

    /// The finished screen's reminder of each shortcut.
    static func tutorialSummary(in dump: [String: Any]) -> [(what: String, keys: String)] {
        let keys = PracticeKeys(dump)
        let hints = keys.shortcut(.main)
        let none = "No shortcut"
        return [
            ("Show labels", hints ?? none),
            ("Search", keys.shortcut(.search) ?? hints.map { "\($0), then \(keys.hintsKey("action search_hints", or: "/"))" } ?? none),
            ("Scroll", keys.shortcut(mode: "scroll") ?? none),
            ("Grid", keys.shortcut(mode: "grid") ?? none),
        ]
    }

    /// What Try it here runs for `step`: the command of the shortcut its
    /// instructions name, so the mode behaves just as that shortcut's would.
    static func tutorialCommand(_ step: TutorialStep, in dump: [String: Any]) -> [String] {
        let keys = PracticeKeys(dump)
        let combos = keys.launchers.combos
        let role: LauncherRole = switch step {
        case .rightClick where combos[.rightClick] != nil: .rightClick
        case .search where combos[.search] != nil: .search
        default: .main
        }
        // No labels shortcut: the search one without its search clicks as the text says.
        let searchless = combos[.search].flatMap { keys.bindings[$0]?.first }.map {
            $0.split(whereSeparator: \.isWhitespace).filter { !["--search", "-s", "--hide-on-empty-search"].contains($0) }.joined(separator: " ")
        }
        let command = switch step {
        case .scroll: keys.binding(mode: "scroll")?.command ?? "scroll"
        case .grid: keys.binding(mode: "grid")?.command ?? "grid"
        default: combos[role].flatMap { keys.bindings[$0]?.first } ?? searchless ?? "hints"
        }
        return command.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

/// The shortcuts and in-mode keys the tutorial names, read from a config dump.
struct PracticeKeys {
    let bindings: [String: [String]]
    /// Read leniently: a launcher with flags the Clicking page leaves alone
    /// still has a shortcut, and its --action and --repeat still count.
    let launchers: Neru.Launchers
    let hints: [String: [String]]
    let scroll: [String: [String]]
    let grid: [String: [String]]
    let inverted: Bool
    let menuBar: Bool

    /// `inverted` is the daemon's own scroll direction (`status --json`),
    /// which the menu bar flips without touching the config; nil reads the config.
    init(_ dump: [String: Any], inverted: Bool? = nil) {
        bindings = Neru.hotkeyBindings(in: dump)
        launchers = Neru.launchers(in: bindings, lenient: true)
        hints = Neru.hotkeys("hints", in: dump)
        scroll = Neru.hotkeys("scroll", in: dump)
        grid = Neru.hotkeys("grid", in: dump)
        self.inverted = inverted ?? Neru.value("scroll.invert_scroll", in: dump) as? Bool ?? false
        menuBar = Neru.value("systray.enabled", in: dump) as? Bool ?? true
    }

    /// A launcher's shortcut as the window shows it ("⇧⌘Space"), or nil.
    func shortcut(_ role: Neru.LauncherRole) -> String? { launchers.combos[role].map(Shortcut.display) }

    /// The shortcut that starts `mode`, or nil: the one bound to just `mode`,
    /// as Settings shows it, else the first `mode …` command with flags.
    func binding(mode: String) -> (combo: String, command: String)? {
        let bound = bindings.filter { $0.value.count == 1 && $0.value[0].split(whereSeparator: \.isWhitespace).first.map(String.init) == mode }
        guard let combo = bound.filter({ $0.value == [mode] }).keys.min() ?? bound.keys.min() else { return nil }
        return (combo, bound[combo]![0])
    }

    func shortcut(mode: String) -> String? { binding(mode: mode).map { Shortcut.display($0.combo) } }

    /// The grid shortcut clicks as it picks (`grid --action left_click`, or
    /// a right, middle or double click), rather than only moving the pointer.
    var gridClicks: Bool {
        let action = binding(mode: "grid").flatMap { Neru.parseLauncher([$0.command], mode: "grid", lenient: true) }?.action
        return action?.split(separator: ",").allSatisfy(["left_click", "right_click", "middle_click"].contains) ?? false
    }

    func hintsKey(_ steps: String, or fallback: String) -> String { Self.key(steps, in: hints, or: fallback) }
    func scrollKey(_ steps: String, or fallback: String) -> String { Self.key(steps, in: scroll, or: fallback) }
    func gridKey(_ steps: String, or fallback: String) -> String { Self.key(steps, in: grid, or: fallback) }

    /// The key `table` binds to `steps`, the shortest when there are several
    /// ("d" over "PageDown"), as the config spells it but a single letter
    /// capitalised ("J"; "gg" stays as typed).
    // ponytail: falls back to the default key when it is unbound or the dump
    // is not in yet; a user who unbound one reads its default here.
    static func key(_ steps: String, in table: [String: [String]], or fallback: String) -> String {
        let keys = table.filter { $0.value == [steps] }.keys
        guard let key = keys.min(by: { ($0.count, $0) < ($1.count, $1) }) else { return fallback }
        return key.count == 1 ? key.uppercased() : key
    }

    /// Says a mode has no shortcut and where to get one. The menu bar icon
    /// has the labels and the grid, not scrolling, and only while it shows.
    func missing(_ subject: String, page: String, menuBar listed: Bool) -> String {
        let menu = listed && menuBar ? ", the menu bar icon," : ","
        return "\(subject) no shortcut yet. Use Try it here\(menu) or set one in Settings › \(page)."
    }
}
