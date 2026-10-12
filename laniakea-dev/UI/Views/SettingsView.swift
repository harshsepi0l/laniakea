import SwiftUI

struct SettingsView: View {
    /// Shared with the sky view, which reads the same keys.
    @AppStorage("sky.showsCamera") private var skyShowsCamera = true
    @AppStorage("sky.showsMap") private var skyShowsMap = true
    @AppStorage("sky.showsFacts") private var skyShowsFacts = true
    @AppStorage("sky.showsLock") private var skyShowsLock = true

    var body: some View
    {
        NavigationStack {
            Form {
                Section {
                    Toggle("Camera picture", isOn: $skyShowsCamera)
                    Toggle("Corner map", isOn: $skyShowsMap)
                    Toggle("Facts bubble", isOn: $skyShowsFacts)
                    Toggle("Lock button", isOn: $skyShowsLock)
                } header: {
                    Text("Sky view")
                } footer: {
                    Text("With the camera picture off, the sky view shows only the stars and planets, still following where you point. The corner map shows where the picked object is in Atlas. The lock button keeps the crosshair on what it's picked, wherever you point, until you unlock it.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
