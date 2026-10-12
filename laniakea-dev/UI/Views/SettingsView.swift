import SwiftUI

struct SettingsView: View {
    /// Shared with the sky view, which reads the same keys.
    @AppStorage("sky.showsCamera") private var skyShowsCamera = true
    @AppStorage("sky.showsMap") private var skyShowsMap = true
    @AppStorage("sky.showsFacts") private var skyShowsFacts = true
    @AppStorage("sky.showsLock") private var skyShowsLock = true
    @AppStorage("atlas.simulations") private var atlasSimulations = false
    @AppStorage("atlas.showsFlow") private var atlasShowsFlow = true
    @AppStorage("atlas.showsWeb") private var atlasShowsWeb = true
    @AppStorage("atlas.showsBoundary") private var atlasShowsBoundary = true

    var body: some View
    {
        NavigationStack {
            Form {
                Section {
                    Toggle("Simulations", isOn: $atlasSimulations)
                } header: {
                    Text("Atlas")
                } footer: {
                    Text("Runs time on every Atlas map: planets on their orbits, stars along their measured paths, and galaxy groups at their measured velocities. Speed and direction are set on each map.")
                }
                Section {
                    Toggle("Flow lines", isOn: $atlasShowsFlow)
                    Toggle("Cosmic web", isOn: $atlasShowsWeb)
                    Toggle("Laniakea boundary", isOn: $atlasShowsBoundary)
                } header: {
                    Text("Laniakea overlays")
                } footer: {
                    Text("Flow lines show how matter moves and the cosmic web where it gathers, from the Cosmicflows-4 reconstruction. The boundary is the edge of Laniakea's basin: an outline when flat, rings through its shape in 3D.")
                }
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
