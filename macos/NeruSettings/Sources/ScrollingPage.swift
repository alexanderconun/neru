import SwiftUI

struct ScrollingPage: View {
    @EnvironmentObject var neru: Neru

    var body: some View {
        Form {
            Section("Scrolling") {
                LabeledContent("Shortcut") { ShortcutRecorder(mode: "scroll") }
                SettingToggle(title: "Invert scrolling", key: "scroll.invert_scroll",
                              help: "Swap the direction of the scroll keys.")
            }
            Section("Keys") {
                CheckedTextRow(title: "Scroll keys", help: "Four keys for left, down, up and right, in that order.",
                               saved: neru.scrollKeys,
                               problem: { Neru.scrollKeysProblem($0, bindings: neru.hotkeys("scroll")) },
                               commit: neru.setScrollKeys)
                Picker(selection: Binding(get: { neru.arrowsScroll }, set: neru.setArrowsScroll)) {
                    Text("Move pointer").tag(false)
                    Text("Scroll").tag(true)
                } label: {
                    HelpLabel("Arrow keys", help: "While scrolling, the arrow keys either nudge the pointer or scroll like the scroll keys.")
                }
                .pickerStyle(.segmented)
            }
            Section("Speed") {
                SliderRow(title: "Scroll speed", key: "scroll.scroll_step", range: 10...300, step: 10,
                          low: Image(systemName: "tortoise"), high: Image(systemName: "hare"))
                SliderRow(title: "Dash speed", key: "scroll.scroll_step_half", range: 100...2000, step: 50,
                          low: Image(systemName: "tortoise"), high: Image(systemName: "hare"),
                          help: "How far half-page scrolls (d / u) move.")
            }
        }
        .formStyle(.grouped)
    }
}
