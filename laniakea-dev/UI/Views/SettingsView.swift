import SwiftUI

struct SettingsView: View {
    @State private var searchText: String = ""
    
    var body: some View
    {
        NavigationStack {
            VStack {
                Text("Settings View")
                    .font(.title)
            }
        }
        .navigationViewStyle(.stack)
        .navigationBarTitle("Settings", displayMode: .inline)
    }
}
