import SwiftUI
import SafariServices

struct SpaceNewsSection: View {
    @ObservedObject var SnapiArticleVM: SnapiArticleViewModel
    @Binding var selectedURL: URL?

    var body: some View {
        VStack(spacing: 12) {
            if let error = SnapiArticleVM.errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            } else if SnapiArticleVM.snapiArticle.isEmpty {
                ProgressView("Loading articles...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)
            } else {
                ForEach(SnapiArticleVM.snapiArticle.dropFirst().prefix(6)) { article in
                    Button {
                        selectedURL = URL(string: article.url)
                    } label: {
                        NewsArticleCard(article: article)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: News Article Card
struct NewsArticleCard: View {
    let article: SnapiArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image Container
            ZStack(alignment: .topLeading) {
                // Image
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
            }
            .frame(height: 160)
            .clipped()

            // Content
            VStack(alignment: .leading, spacing: 10) {
                Text(article.title)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .lineLimit(2)
                    .foregroundColor(.primary)

                Text(article.summary)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .lineLimit(2)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Text(article.news_site)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundColor(.orange)
                        .lineLimit(1)

                    Spacer()

                    Text(formatDate(article.published_at))
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
        }
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
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
