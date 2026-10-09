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
        }
        .formStyle(.grouped)
    }
}
