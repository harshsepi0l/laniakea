import SwiftUI

struct ArticleDetailView: View {
    @StateObject private var viewModel: ArticleDetailViewModel
    @State private var showOriginal = false

    init(listing: ArticleListing) {
        _viewModel = StateObject(wrappedValue: ArticleDetailViewModel(
            listing: listing,
            fetchGeneratedArticleUseCase: FetchGeneratedArticleUseCase(repository: GeneratedArticleAPIService())
        ))
    }

    private var article: ArticleListing { viewModel.listing }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heroImage

                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(article.sourceName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.orange)
                        Spacer()
                        Text(article.publishedAt?.formatted(date: .long, time: .omitted) ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    content

                    sourceCard
                }
                .padding(16)
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(article.sourceName)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showOriginal) {
            if let url = URL(string: article.sourceURL) {
                SafariWebView(url: url)
                    .ignoresSafeArea()
            }
        }
        .onAppear { viewModel.load() }
    }

    @ViewBuilder
    private var heroImage: some View {
        if let imageUrl = article.imageURL, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color(.systemGray6))
                }
            }
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            Text(article.title)
                .font(.system(size: 26, weight: .bold))
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading article...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .generated(let generated):
            Text(generated.title)
                .font(.system(size: 26, weight: .bold))

            aiNotice

            Text(generated.summary)
                .font(.system(size: 17, weight: .medium))

            ForEach(Array(generated.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.heading)
                        .font(.system(size: 20, weight: .bold))
                    Text(section.body)
                        .font(.system(size: 16))
                        .lineSpacing(4)
                }
            }

        case .notGenerated, .failed:
            Text(article.title)
                .font(.system(size: 26, weight: .bold))

            Text(article.summary)
                .font(.system(size: 16))
                .lineSpacing(4)

            Text(viewModel.state == .notGenerated
                 ? "The full write-up for this story isn't ready yet. Check back soon, or read the original below."
                 : "The full write-up couldn't be loaded. Check your connection, or read the original below.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    private var aiNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundColor(.orange)
            Text("This article was written by AI from the original \(article.sourceName) post. It may contain mistakes, so check the source for details.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Source")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            Text(article.title)
                .font(.system(size: 15, weight: .semibold))
            Button {
                showOriginal = true
            } label: {
                HStack(spacing: 4) {
                    Text("Read the original on \(article.sourceName)")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .padding(.top, 8)
    }
}
