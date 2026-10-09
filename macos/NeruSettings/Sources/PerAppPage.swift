import SwiftUI

// Owned by the per-app feature: overrides for one app at a time.
struct PerAppPage: View {
    @EnvironmentObject var neru: Neru

    var body: some View {
        Form {
            Section("Per-App Settings") {
                Text("Coming soon").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
