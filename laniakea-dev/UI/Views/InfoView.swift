import SwiftUI

struct InfoView: View {
    @State private var searchText: String = ""
    
    var body: some View
    {
        NavigationStack {
            VStack {
                Text("Info View")
                    .font(.title)
            }
        }
        .navigationViewStyle(.stack)
    }
}
