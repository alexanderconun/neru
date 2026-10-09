import SwiftUI

struct ClickingPage: View {
    @EnvironmentObject var neru: Neru
    private let mission = "hints.detect_mission_control"
    private let dock = "hints.include_dock_hints"

    var body: some View {
        let launchers = neru.launchers
        Form {
            Section("Clicking") {
                LabeledContent("Shortcut") { recorder(.main, clearable: false) }
                launcherToggle("Automatic click", \.autoClick,
                               help: "Click as soon as a label is typed. Off, typing a label only moves the mouse there; Shift+L clicks.")
                launcherToggle("Chain clicks", \.chain,
                               help: "After each click, show labels again for the next one until you press Escape. Needs Automatic click.")
                    .disabled(!launchers.autoClick)
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
            Section("Search") {
                LabeledContent {
                    recorder(.search)
                } label: {
                    HelpLabel("Search shortcut", help: "Show labels with a search field: type part of an item's text to narrow them down. Follows Automatic click and Chain clicks.")
                }
                launcherToggle("Hide labels before search", \.hideLabels,
                               help: "Show no labels until you type. Needs a search shortcut.")
                    .disabled(launchers.combos[.search] == nil)
            }
            Section("More clicks") {
                LabeledContent {
                    recorder(.rightClick)
                } label: {
                    HelpLabel("Right-click shortcut", help: "Right-click the label you type. Always one click: Chain clicks does not apply, so you can pick from the menu it opens.")
                }
                LabeledContent {
                    recorder(.doubleClick)
                } label: {
                    HelpLabel("Double-click shortcut", help: "Double-click the label you type. Always one double-click: Chain clicks does not apply.")
                }
            }
            Section("Labels") {
                TextRow(title: "Label characters", key: "hints.hint_characters")
            }
            Section("While labels are showing") {
                let table = (neru.value("hints.hotkeys") as? [String: Any] ?? [:]).compactMapValues { $0 as? [String] }
                ForEach(Neru.cheatSheet(table), id: \.what) { row in keyRow(row.keys, row.what) }
            }
            Section("While searching") {
                keyRow("Type", "Narrow the labels to matching text")
                keyRow(Shortcut.display("Return"), "Pick the first match")
                keyRow(Shortcut.display("Escape"), "Cancel the search")
            }
        }
        .formStyle(.grouped)
    }

    private func recorder(_ role: Neru.LauncherRole, clearable: Bool = true) -> some View {
        ShortcutRecorder(combo: neru.launchers.combos[role], onRecord: { neru.setLauncher(role, to: $0) },
                         onClear: clearable ? { neru.setLauncher(role, to: nil) } : nil)
    }

    private func launcherToggle(_ title: String, _ flag: WritableKeyPath<Neru.Launchers, Bool>, help: String) -> some View {
        Toggle(isOn: Binding(get: { neru.launchers[keyPath: flag] }, set: { on in
            var set = neru.launchers
            set[keyPath: flag] = on
            neru.setLaunchers(set)
        })) {
            HelpLabel(title, help: help)
        }
        .toggleStyle(.switch)
    }

    private func keyRow(_ keys: String, _ what: String) -> some View {
        LabeledContent(what) { Text(keys).font(.body.monospaced()).foregroundStyle(.secondary) }
    }
}
