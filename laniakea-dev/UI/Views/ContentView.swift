import SwiftUI

struct ContentView: View {
    @StateObject private var snapiArticleVM = SnapiArticleViewModel(
        fetchSnapiArticleUseCase: FetchSnapiArticleUseCase(repository: SnapiArticleAPIService())
    )
    @StateObject private var picOfDayVM = PicOfDayViewModel(
        fetchPicOfDayUseCase: FetchPicOfDayUseCase(repository: PicOfDayAPIService())
    )

    var body: some View {
        TabView {
            FactsView(snapiArticleVM: snapiArticleVM)
                .tabItem { Label("Facts", systemImage: "star.fill") }

            AtlasView()
                .tabItem { Label("Atlas", systemImage: "globe") }

            HomeView(picOfDayVM: picOfDayVM)
                .tabItem { Label("Home", systemImage: "house.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }

            InfoView()
                .tabItem { Label("Info", systemImage: "info.circle.fill") }
        }
        .tint(.orange)
    }
}
