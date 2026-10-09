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
