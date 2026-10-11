import SwiftUI
import SafariServices

struct FactsView: View {
    @ObservedObject private var SnapiArticleVM: SnapiArticleViewModel
    @State private var selectedURL: URL?

    init(snapiArticleVM: SnapiArticleViewModel) {
        self.SnapiArticleVM = snapiArticleVM
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // MARK: Featured Article Hero
                    if let featured = SnapiArticleVM.snapiArticle.first {
                        Button {
                            selectedURL = URL(string: featured.url)
                        } label: {
                            FeaturedArticleCard(article: featured)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 32)
                    } else if SnapiArticleVM.errorMessage != nil {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundColor(.orange)
                            Text("Unable to load articles")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    } else {
                        HStack {
                            ProgressView()
                            Text("Loading featured article...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .padding(.bottom, 32)
                    }

                    // MARK: Section Title
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Latest Space News")
                            .font(.system(size: 20, weight: .bold, design: .default))
                        Text("Discover what's happening in space right now")
                            .font(.system(size: 14, weight: .regular, design: .default))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // MARK: News List
                    SpaceNewsSection(SnapiArticleVM: SnapiArticleVM, selectedURL: $selectedURL)
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .navigationTitle("Facts")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemBackground))
        }
        .sheet(item: $selectedURL) { url in
            SafariWebView(url: url)
                .ignoresSafeArea()
        }
        .onAppear {
            SnapiArticleVM.loadSnapiArticle()
        }
    }
}

// MARK: Featured Article Card
struct FeaturedArticleCard: View {
    let article: SnapiArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image
            ZStack {
                if let imageUrl = article.image_url, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color(.systemGray6))
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Rectangle()
                                .fill(Color(.systemGray6))
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Color(.systemGray6))
                }

                // Overlay with gradient
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.6), location: 0.7)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: 220)
            .clipped()

            // Content
            VStack(alignment: .leading, spacing: 12) {
                Text(article.title)
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .lineLimit(2)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Text(article.news_site)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundColor(.orange)

                    Spacer()

                    Text(formatDate(article.published_at))
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
        }
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let calendar = Calendar.current
            if calendar.isDateInToday(date) {
                return "Today"
            } else if calendar.isDateInYesterday(date) {
                return "Yesterday"
            } else {
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "MMM d"
                return dayFormatter.string(from: date)
            }
        }
        return "Recently"
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
