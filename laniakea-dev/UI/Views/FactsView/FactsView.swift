import SwiftUI
import SafariServices

struct FactsView: View {
    @ObservedObject private var SnapiArticleVM: SnapiArticleViewModel
    @StateObject private var storiesVM = StoriesViewModel(
        fetchGeneratedArticleUseCase: FetchGeneratedArticleUseCase(repository: GeneratedArticleAPIService())
    )

    init(snapiArticleVM: SnapiArticleViewModel) {
        self.SnapiArticleVM = snapiArticleVM
    }

    var body: some View {
        Group {
            if !SnapiArticleVM.snapiArticle.isEmpty {
                StoryViewer(stories: SnapiArticleVM.snapiArticle.map(\.listing), viewModel: storiesVM)
            } else if let error = SnapiArticleVM.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text("Unable to load stories")
                        .font(.headline)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        SnapiArticleVM.loadSnapiArticle()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                }
                .padding(32)
            } else {
                ProgressView("Loading stories...")
            }
        }
        .onAppear {
            SnapiArticleVM.loadSnapiArticle()
        }
    }
}

// MARK: Safari Web View
struct SafariWebView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredBarTintColor = UIColor.systemBackground
        vc.preferredControlTintColor = UIColor.systemOrange
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
