import SwiftUI

struct StoryViewer: View {
    let stories: [ArticleListing]
    @ObservedObject var viewModel: StoriesViewModel

    @State private var index = 0
    @State private var progress: Double = 0
    @State private var isHolding = false
    @State private var isFinished = false
    @State private var replays = 0
    @State private var openArticle: ArticleListing?

    private static let storyDuration: Double = 7
    private static let tick: Double = 0.05

    private var story: ArticleListing { stories[min(index, stories.count - 1)] }
    private var isPaused: Bool { isHolding || openArticle != nil || isFinished }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                    .overlay {
                        AsyncImage(url: story.imageURL.flatMap(URL.init(string:))) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                Color(white: 0.12)
                            }
                        }
                    }
                    .clipped()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.2),
                        .init(color: .clear, location: 0.45),
                        .init(color: .black.opacity(0.85), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer()
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)

                if isFinished {
                    caughtUp
                }
            }
            .contentShape(Rectangle())
            .gesture(storyGesture(width: geo.size.width))
        }
        .task(id: "\(index)-\(replays)") { await runTimer() }
        .onAppear { prepare() }
        .onChange(of: index) { prepare() }
        .onChange(of: stories.map(\.generatedPath)) {
            index = 0
            isFinished = false
            prepare()
        }
        .sheet(item: $openArticle) { listing in
            NavigationStack {
                ArticleDetailView(listing: listing)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { openArticle = nil }
                        }
                    }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Next story") { goForward() }
        .accessibilityAction(named: "Previous story") { goBack() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 3) {
                ForEach(stories.indices, id: \.self) { i in
                    GeometryReader { bar in
                        Capsule().fill(.white.opacity(0.35))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white)
                                    .frame(width: bar.size.width * fill(for: i))
                            }
                    }
                    .frame(height: 3)
                }
            }
            .accessibilityHidden(true)

            HStack(spacing: 8) {
                Text(story.sourceName)
                    .font(.system(size: 14, weight: .semibold))
                if let date = story.publishedAt {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Text("\(index + 1) of \(stories.count)")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundColor(.white.opacity(0.7))
            }
            .foregroundColor(.white)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(story.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(viewModel.summary(for: story))
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(5)

            Button {
                openArticle = story
            } label: {
                HStack(spacing: 6) {
                    Text("Read article")
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Capsule().fill(.white))
            }
            .padding(.top, 4)
        }
    }

    private var caughtUp: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 44))
                    .foregroundColor(.orange)
                Text("You're all caught up")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Text("That's every recent story from NASA and ESA.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.75))
                Button {
                    isFinished = false
                    index = 0
                    progress = 0
                    replays += 1
                } label: {
                    Text("Watch again")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.white))
                }
            }
            .padding(24)
        }
    }

    private func fill(for i: Int) -> Double {
        i < index ? 1 : (i == index ? progress : 0)
    }

    // One gesture handles both tap zones and hold-to-pause so they don't fight.
    private func storyGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in isHolding = true }
            .onEnded { value in
                isHolding = false
                let moved = abs(value.translation.width) + abs(value.translation.height)
                guard moved < 10 else { return }
                if value.location.x < width / 3 {
                    goBack()
                } else {
                    goForward()
                }
            }
    }

    private func goForward() {
        if isFinished { return }
        if index < stories.count - 1 {
            index += 1
        } else {
            progress = 1
            isFinished = true
        }
    }

    private func goBack() {
        if isFinished {
            isFinished = false
            progress = 0
        } else if index > 0 {
            index -= 1
        } else {
            progress = 0
        }
    }

    private func prepare() {
        guard !stories.isEmpty else { return }
        progress = 0
        viewModel.loadSummary(for: story)
        if index + 1 < stories.count {
            viewModel.loadSummary(for: stories[index + 1])
        }
    }

    private func runTimer() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.tick))
            guard !Task.isCancelled else { return }
            if isPaused { continue }
            progress = min(1, progress + Self.tick / Self.storyDuration)
            if progress >= 1 {
                goForward()
                if isFinished { return }
            }
        }
    }
}

extension ArticleListing: Identifiable {
    var id: String { generatedPath }
}
