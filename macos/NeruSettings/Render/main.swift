import AppKit
import SwiftUI

/// `render-settings <dir> [dump.json]` (`just render-settings`) draws every
/// Settings page, the Tutorial (every step and the finished screen) and
/// Training (each round before Start and mid-round) offscreen, light and dark,
/// into <dir> as PNGs. For checking the layout without screen recording or a
/// daemon. It never asks a daemon and never writes UserDefaults; `dump.json`,
/// a saved `neru config dump`, stands in for the daemon's config (the default
/// shortcuts without one).
enum Render {
    static func run(_ arguments: [String]) {
        guard arguments.count > 1 else {
            FileHandle.standardError.write(Data("usage: render-settings <dir> [dump.json]\n".utf8))
            exit(2)
        }
        let dir = URL(fileURLWithPath: arguments[1])
        let dump = arguments.count > 2
            ? (try? String(contentsOfFile: arguments[2], encoding: .utf8)).flatMap(Neru.json) : nil
        NSApplication.shared.setActivationPolicy(.prohibited)
        let neru = Neru(config: dump ?? ["hotkeys": ["bindings": Neru.defaultHotkeys.mapValues { [$0] }],
                                         "scroll": ["hotkeys": Neru.defaultScrollHotkeys.mapValues { [$0] }]])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            func draw(_ name: String, _ view: some View) {
                let url = dir.appendingPathComponent("\(name)-\(scheme).png")
                snapshot(view.environmentObject(neru), appearance: appearance, to: url)
            }
            for page in Page.allCases {
                draw("settings-\(page)", ContentView(page: page).frame(width: 720, height: 520))
            }
            for step in TutorialStep.allCases {
                var progress = TutorialProgress()
                progress.step = step
                progress.done = Set(TutorialStep.allCases.prefix(step.rawValue))
                draw("tutorial-\(step.rawValue + 1)", TutorialView(progress: progress))
            }
            var progress = TutorialProgress()
            progress.done = [.showLabels]
            draw("tutorial-1-done", TutorialView(progress: progress))
            progress.step = nil
            progress.done = Set(TutorialStep.allCases)
            draw("tutorial-finished", TutorialView(progress: progress))

            for round in TrainingRound.allCases {
                let name = "training-\(round)"
                let training = Training(defaults: nil)
                training.round = round
                draw("\(name)-before", TrainingView(training: training))
                let playing = Training(defaults: nil)
                playing.round = round
                playing.start()
                for hit in [true, true, false, true, true] {
                    _ = playing.score.press(onTarget: hit, round.click, after: 1.37)
                }
                draw("\(name)-playing", TrainingView(training: playing))
            }
            let done = Training(defaults: nil)
            done.start()
            for miss in [0, 1] { done.press(miss, .left) }
            for _ in 0 ..< TrainingScore.hitsPerRound { done.press(done.board.target, .left, at: done.board.shownAt + 1.23) }
            draw("training-done", TrainingView(training: done))
        }
        exit(0)
    }

    /// Lays `view` out in a window that is never shown and saves what it draws.
    private static func snapshot(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view
            .environment(\.controlActiveState, .key) // as if focused, not greyed
            .scrollIndicators(.never) // a legacy scroller's gutter offscreen; overlay ones draw nothing
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Lets onAppear and onChange run and the board take its real size.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}

Render.run(CommandLine.arguments)
