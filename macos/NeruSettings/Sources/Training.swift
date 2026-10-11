import AppKit
import SwiftUI

/// The Training window: a timed game of clicking the ★ button (or the dot)
/// with Homekey, ten hits a round, with the best average kept per round type.
struct TrainingView: View {
    @EnvironmentObject var neru: Neru
    @StateObject private var training: Training

    init(training: Training = Training()) {
        _training = StateObject(wrappedValue: training)
    }

    var body: some View {
        VStack(spacing: 0) {
            PracticeBanners()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Round", selection: $training.round) {
                        ForEach(TrainingRound.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Button(training.running ? "Stop" : "Start") {
                        training.running ? training.stop() : training.start()
                        training.relabel(training.round == .search)
                    }
                    .frame(minWidth: 70)
                }
                Text(stats).monospacedDigit().foregroundStyle(.secondary)
                prompt.font(.title3.weight(.semibold))
                board
            }
            .padding(20)
        }
        .frame(width: 760, height: 560)
        .onAppear {
            neru.watchModes(true)
            training.relabel = neru.relabel(search:)
        }
        .onDisappear {
            neru.watchModes(false)
            training.stop()
        }
    }

    private var stats: String {
        let score = training.score
        func seconds(_ value: TimeInterval?) -> String { value.map { String(format: "%.2f s", $0) } ?? "–" }
        return "Hits \(score.hits) · Misses \(score.misses) · Avg \(seconds(score.average)) · Best \(seconds(training.best))"
    }

    private var prompt: Text {
        if training.running {
            // Without Automatic click, Return on a search only moves the pointer.
            let keys = PracticeKeys(neru.config)
            let click = keys.launchers.autoClick ? nil : keys.hintsKey("action left_click", or: "Shift+L")
            return Text(training.round.prompt(training.board.words[training.board.target], clickKey: click))
        }
        if let average = training.finishedAverage {
            let done = Text(String(format: "Round done: avg %.2f s", average))
            return training.newBest ? Text("\(done)   \(Text("New best!").foregroundStyle(.green))") : done
        }
        return Text(training.round == .grid ? "Press Start, then use the grid to click the dot"
            : "Press Start, then use \(Neru.appName) to click the ★ button")
    }

    private var board: some View {
        GeometryReader { geometry in
            let board = training.board
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(board.words.indices, board.frames)), id: \.0) { index, frame in
                    item(index, board)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .onChange(of: geometry.size, initial: true) { _, size in training.resize(size) }
        }
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func item(_ index: Int, _ board: TrainingBoard) -> some View {
        if training.round == .grid {
            PracticeDot(enabled: training.running) { training.press(index, $0) }.accessibilityHidden(true)
        } else {
            let target = index == board.target
            PracticeButton(title: target ? "★ \(board.words[index])" : board.words[index],
                           highlighted: target && training.running, enabled: training.running) { training.press(index, $0) }
        }
    }
}

/// One training session's state; `defaults` keeps the best averages (nil
/// keeps nothing, for rendering).
final class Training: ObservableObject {
    @Published var round = TrainingRound.clicking {
        didSet {
            guard round != oldValue else { return }
            stop()
            score = TrainingScore(click: round.click)
            finishedAverage = nil
            deal()
            relabel(round == .search)
        }
    }

    @Published private(set) var running = false
    @Published var score = TrainingScore(click: .left)
    @Published private(set) var board = TrainingBoard()
    /// The last round's average once it is done, until the next one starts.
    @Published private(set) var finishedAverage: TimeInterval?
    @Published private(set) var newBest = false
    private var size = CGSize(width: 720, height: 400)
    private let defaults: UserDefaults?
    /// Has labels that are up read the board again after it changed under
    /// them (a hit, Start or Stop, another round), `search` reopening a
    /// search in the Search round; set by the view.
    var relabel: (_ search: Bool) -> Void = { _ in }

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        deal()
    }

    var best: TimeInterval? { defaults?.object(forKey: round.bestKey) as? TimeInterval }

    /// Keeps the board's deal and starts the clock on it.
    func start() {
        score = TrainingScore(click: round.click)
        finishedAverage = nil
        newBest = false
        board.shownAt = Date()
        running = true
    }

    /// Ends the round without keeping its score.
    func stop() { running = false }

    func press(_ index: Int, _ kind: ClickKind, at now: Date = Date()) {
        guard running else { return }
        let hit = score.press(onTarget: index == board.target, kind, after: now.timeIntervalSince(board.shownAt))
        if let average = score.average, score.finished {
            running = false
            newBest = TrainingScore.isNewBest(average, than: best)
            if newBest { defaults?.set(average, forKey: round.bestKey) }
            finishedAverage = average
        }
        if hit {
            deal()
            relabel(round == .search)
        }
    }

    /// Lays the board out again for its real size, keeping the words and target.
    func resize(_ size: CGSize) {
        guard size != self.size, size.width > 0 else { return }
        self.size = size
        board.frames = defaults == nil ? TrainingBoard.fixed(round, in: size).frames
            : TrainingBoard.place(board.words.count, size: round == .grid ? TrainingBoard.dotSize : TrainingBoard.buttonSize, in: size)
    }

    /// A render (no defaults) deals the same board every time.
    private func deal() {
        board = defaults == nil ? .fixed(round, in: size)
            : .deal(round, in: size, avoiding: board.words.indices.contains(board.target) ? board.words[board.target] : nil)
    }
}

// MARK: pure logic (covered by Tests/PracticeTests.swift)

enum TrainingRound: String, CaseIterable, Identifiable {
    case clicking = "Clicking", rightClick = "Right-click", search = "Search", grid = "Grid"
    var id: Self { self }

    /// Buttons on the board: more to search through in a search round. The
    /// grid round has only its dot.
    var buttons: Int {
        switch self {
        case .clicking, .rightClick: 12
        case .search: 24
        case .grid: 0
        }
    }

    var click: ClickKind { self == .rightClick ? .right : .left }

    /// The UserDefaults key of this round type's best average.
    var bestKey: String { "trainingBest.\(self)" }

    /// `clickKey` is the key that clicks after a search's Return, when
    /// Return only moves the pointer there (Automatic click off).
    func prompt(_ word: String, clickKey: String? = nil) -> String {
        switch self {
        case .clicking: "Click ★ \(word)"
        case .rightClick: "Right-click ★ \(word)"
        case .search: clickKey.map { "Search for \(word), press Return, then \($0)" } ?? "Search for \(word) and press Return"
        case .grid: "Click the dot with the grid"
        }
    }
}

/// One round's score.
struct TrainingScore {
    static let hitsPerRound = 10
    let click: ClickKind
    private(set) var hits = 0
    private(set) var misses = 0
    private(set) var total: TimeInterval = 0

    var average: TimeInterval? { hits > 0 ? total / Double(hits) : nil }
    var finished: Bool { hits >= Self.hitsPerRound }

    /// Scores a press on a board item, `seconds` after the target appeared.
    /// A hit is the round's click on the target; anything else on the board
    /// is a miss, except a left click on a right-click round's target, which
    /// is neither: typing its label is the way there (labels click, then
    /// Shift+R right-clicks at the pointer). True on a hit; a press after
    /// the round counts for nothing.
    mutating func press(onTarget: Bool, _ kind: ClickKind, after seconds: TimeInterval) -> Bool {
        guard !finished else { return false }
        guard onTarget, kind == click else {
            if !(onTarget && click == .right && kind == .left) { misses += 1 }
            return false
        }
        hits += 1
        total += seconds
        return true
    }

    /// Lower is better; with no best stored, any average is one.
    static func isNewBest(_ average: TimeInterval, than best: TimeInterval?) -> Bool {
        best.map { average < $0 } ?? true
    }
}

/// The board's buttons (or the grid round's dot), where they sit and which is
/// the target.
struct TrainingBoard {
    /// No word holds another, or is held by a control of the window or a
    /// common Dock or menu bar title: a search must find exactly one match
    /// (see the test).
    static let words = ["Save", "Open", "Send", "Cancel", "Copy", "Delete", "Print", "Share", "Undo", "Paste", "Clear", "Rename",
                        "Export", "Import", "Reload", "Filter", "Upload", "Archive", "Redo", "Merge", "Sort", "Rotate", "Crop", "Mute"]
    static let buttonSize = CGSize(width: 100, height: 28)
    /// The dot's view, around the 18 pt dot drawn in it.
    static let dotSize = CGSize(width: DotView.side, height: DotView.side)

    var words: [String] = []
    var frames: [CGRect] = []
    var target = 0
    var shownAt = Date()

    /// New words, spots and target for `round` on a board of `size`; the
    /// target is never the word `avoiding` (the last one).
    static func deal(_ round: TrainingRound, in size: CGSize, avoiding last: String?) -> TrainingBoard {
        guard round != .grid else { return TrainingBoard(words: ["dot"], frames: place(1, size: dotSize, in: size)) }
        let words = Array(Self.words.shuffled().prefix(round.buttons))
        let frames = place(words.count, size: buttonSize, in: size)
        let target = frames.indices.filter { words[$0] != last }.randomElement() ?? 0
        return TrainingBoard(words: Array(words.prefix(frames.count)), frames: frames, target: target)
    }

    /// The same board every time, for renders: the round's first words in a
    /// loose grid, the fifth the target. homekey-rs renders deal the very same.
    static func fixed(_ round: TrainingRound, in size: CGSize) -> TrainingBoard {
        let grid = round == .grid, count = max(round.buttons, 1), item = grid ? dotSize : buttonSize
        let cols = count == 1 ? 1 : count > 12 ? 6 : 4, rows = (count + cols - 1) / cols
        let cell = CGSize(width: (size.width - 32) / CGFloat(cols), height: (size.height - 32) / CGFloat(rows))
        let frames = (0 ..< count).map { i in
            CGRect(x: 16 + CGFloat(i % cols) * cell.width + ((cell.width - item.width - 12) * CGFloat((i + 1) * 7 % 10) / 9).rounded(.down),
                   y: 16 + CGFloat(i / cols) * cell.height + ((cell.height - item.height - 12) * CGFloat((i + 1) * 3 % 10) / 9).rounded(.down),
                   width: item.width, height: item.height)
        }
        return TrainingBoard(words: grid ? ["dot"] : Array(words.prefix(count)), frames: frames, target: grid ? 0 : 4)
    }

    /// Up to `count` rects of `size` at random spots inside `board`, `margin`
    /// from its edges and at least `gap` apart: each gets its own cell of a
    /// grid laid over the board and a random spot inside it. A board too
    /// small for `count` gets as many as fit.
    static func place(_ count: Int, size: CGSize, in board: CGSize, margin: CGFloat = 16, gap: CGFloat = 10) -> [CGRect] {
        let width = board.width - 2 * margin + gap, height = board.height - 2 * margin + gap
        let cols = max(Int(width / (size.width + gap)), 0), rows = max(Int(height / (size.height + gap)), 0)
        guard cols > 0, rows > 0 else { return [] }
        let pitch = CGSize(width: width / CGFloat(cols), height: height / CGFloat(rows))
        return (0 ..< cols * rows).shuffled().prefix(count).map { cell in
            CGRect(x: margin + CGFloat(cell % cols) * pitch.width + .random(in: 0 ... pitch.width - size.width - gap),
                   y: margin + CGFloat(cell / cols) * pitch.height + .random(in: 0 ... pitch.height - size.height - gap),
                   width: size.width, height: size.height)
        }
    }
}
