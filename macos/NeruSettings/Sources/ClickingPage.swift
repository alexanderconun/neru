import SwiftUI

struct ClickingPage: View {
    @EnvironmentObject var neru: Neru
    private let mission = "hints.detect_mission_control"
    private let dock = "hints.include_dock_hints"

    var body: some View {
        Form {
            Section("Clicking") {
                LabeledContent("Shortcut") { ShortcutRecorder(mode: neru.hintsCommand) }
                Toggle(isOn: Binding(get: { neru.hintsCommand == Neru.autoClickHints }, set: neru.setAutoClick)) {
                    HelpLabel("Automatic click", help: "Click as soon as a label is typed. Off, typing a label only moves the mouse there; Shift+L clicks.")
                }
                .toggleStyle(.switch)
                // Neru refuses Mission Control without Dock labels, so the two move together.
                Toggle(isOn: Binding(get: { neru.bool(mission) }, set: { on in
                    neru.setMany(on ? [(dock, "true"), (mission, "true")] : [(mission, "false")],
                                 local: on ? [(dock, true), (mission, true)] : [(mission, false)])
                })) {
                    HelpLabel("Mission Control", help: "Show labels on windows and desktops while Mission Control is open. Turns on Dock labels too.")
                }
                .toggleStyle(.switch)
                SettingToggle(title: "Menu bar labels", key: "hints.include_menubar_hints",
                              help: "Also label items in the menu bar.")
                Toggle(isOn: Binding(get: { neru.bool(dock) }, set: { on in
                    neru.setMany(on ? [(dock, "true")] : [(mission, "false"), (dock, "false")],
                                 local: on ? [(dock, true)] : [(mission, false), (dock, false)])
                })) {
                    HelpLabel("Dock labels", help: "Also label items in the Dock. Turning this off turns off Mission Control.")
                }
                .toggleStyle(.switch)
            }
            Section("Labels") {
                TextRow(title: "Label characters", key: "hints.hint_characters")
            }
        }
        .formStyle(.grouped)
    }
}
