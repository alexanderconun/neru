import SwiftUI

// Owned by the grid feature: grid, recursive grid and bisect settings.
struct GridPage: View {
    @EnvironmentObject var neru: Neru

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent { ShortcutRecorder(mode: "grid") } label: {
                    HelpLabel("Grid", help: "Click anywhere by picking a cell, even where there are no labels.")
                }
                LabeledContent { ShortcutRecorder(mode: "recursive_grid") } label: {
                    HelpLabel("Recursive grid", help: "Narrow down a point in a few keystrokes.")
                }
                LabeledContent { ShortcutRecorder(mode: "bisect") } label: {
                    HelpLabel("Bisect", help: "Halve the screen with each keystroke.")
                }
            }
            Section("Grid") {
                SettingToggle(title: "Enabled", key: "grid.enabled",
                              help: "Turning the grid off also removes its shortcut.")
                CheckedTextRow(title: "Characters", help: "The keys cells are labeled with.",
                               saved: neru.string("grid.characters"),
                               problem: { Neru.gridCharactersProblem($0, bound: neru.hotkeys("grid")) },
                               commit: { neru.set("grid.characters", $0) })
                StepperRow(title: "Label length", help: "The most characters in one cell label.",
                           value: setting("grid.max_label_length"), range: 2...4)
                SettingToggle(title: "Hide unmatched", key: "grid.hide_unmatched",
                              help: "Hide the cells that no longer match what you typed.")
            }
            Section("Recursive grid") {
                SettingToggle(title: "Enabled", key: "recursive_grid.enabled",
                              help: "Turning the recursive grid off also removes its shortcut.")
                RecursiveGridSize()
                SettingToggle(title: "Animation", key: "recursive_grid.animation.enabled",
                              help: "Animate each step as the grid narrows.")
                StepperRow(title: "Max depth", help: "How many times the grid can narrow down.",
                           value: setting("recursive_grid.max_depth"), range: 1...20)
            }
            Section("Bisect") {
                SettingToggle(title: "Enabled", key: "bisect.enabled",
                              help: "Turning bisect off also removes its shortcut.")
            }
        }
        .formStyle(.grouped)
    }

    private func setting(_ key: String) -> Binding<Int> {
        Binding(get: { Int(neru.double(key)) }, set: { neru.set(key, String($0), local: $0) })
    }
}

struct StepperRow: View {
    let title: String
    var help: String?
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent {
            Stepper(value: $value, in: range) { Text("\(value)").monospacedDigit() }
        } label: {
            HelpLabel(title, help: help)
        }
    }
}

/// Columns, rows and keys are one setting: the loader refuses them unless
/// columns × rows is the number of keys, so the three are sent together and
/// only once they agree. Until then the problem shows and nothing is sent.
struct RecursiveGridSize: View {
    @EnvironmentObject var neru: Neru
    @State private var cols = 0
    @State private var rows = 0
    @State private var keys = ""
    @FocusState private var focused: Bool

    private var saved: (cols: Int, rows: Int, keys: String) {
        (Int(neru.double("recursive_grid.grid_cols")), Int(neru.double("recursive_grid.grid_rows")),
         neru.string("recursive_grid.keys"))
    }

    private var problem: String? {
        Neru.recursiveGridProblem(cols: cols, rows: rows, keys: keys, bound: neru.hotkeys("recursive_grid"))
    }

    var body: some View {
        StepperRow(title: "Columns", value: $cols, range: 1...9)
        StepperRow(title: "Rows", value: $rows, range: 1...9)
        LabeledContent {
            TextField("Keys", text: $keys)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .focused($focused)
                .onSubmit(send)
                .onChange(of: focused) { _, isFocused in if !isFocused { send() } }
        } label: {
            HelpLabel("Keys", help: "One key per cell, left to right, top to bottom.")
        }
        .onAppear(perform: load)
        .onChange(of: cols) { send() }
        .onChange(of: rows) { send() }
        .onChange(of: "\(saved)") { load() } // snaps back if refused
        if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
    }

    private func load() {
        (cols, rows, keys) = saved
    }

    private func send() {
        let current = saved
        guard problem == nil, (cols, rows, keys.lowercased()) != (current.cols, current.rows, current.keys) else { return }
        let lower = keys.lowercased()
        neru.setMany([("recursive_grid.grid_cols", String(cols)), ("recursive_grid.grid_rows", String(rows)),
                      ("recursive_grid.keys", lower)],
                     local: [("recursive_grid.grid_cols", cols), ("recursive_grid.grid_rows", rows),
                             ("recursive_grid.keys", lower)])
    }
}

extension Neru {
    // MARK: pure helpers (covered by Tests/GridTests.swift)

    /// Why `characters` can't label grid cells, or nil.
    static func gridCharactersProblem(_ characters: String, bound: [String: [String]]) -> String? {
        keysProblem(characters, bound: bound)
            ?? (Set(characters.lowercased()).count < 2 ? "Use at least two characters." : nil)
    }

    /// Why a `cols` × `rows` recursive grid can't be labeled by `keys`, or nil.
    static func recursiveGridProblem(cols: Int, rows: Int, keys: String, bound: [String: [String]]) -> String? {
        if cols * rows < 2 { return "The grid needs at least two cells." }
        if keys.count != cols * rows { return "\(cols) × \(rows) cells need \(cols * rows) keys, not \(keys.count)." }
        return keysProblem(keys, bound: bound)
    }
}
