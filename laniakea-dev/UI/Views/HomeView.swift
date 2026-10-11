import SwiftUI

struct HomeView: View {
    @ObservedObject var PicOfDayVM: PicOfDayViewModel
    @State private var selectedURL: URL?

    init(picOfDayVM: PicOfDayViewModel) {
        self.PicOfDayVM = picOfDayVM
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome, Explorer")
                            .font(.system(size: 28, weight: .bold))
                        Text("Your personalized space exploration hub")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)

                    // Picture of the Day Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Astronomy Picture of the Day")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 16)

                        if let picOfDay = PicOfDayVM.picOfDay {
                            Button {
                                selectedURL = picOfDay.pageURL
                            } label: {
                                PicOfDayCard(picOfDay: picOfDay)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                        } else if let error = PicOfDayVM.errorMessage {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.orange)
                                Text("Unable to load today's picture")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Try again") {
                                    PicOfDayVM.loadPicOfDay()
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.orange)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                        } else {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Loading today's picture...")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                        }
                    }

                    // Favorite Objects Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your Favorite Objects")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(0..<4, id: \.self) { _ in
                                    VStack(alignment: .center, spacing: 12) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.orange)
                                            .frame(width: 60, height: 60)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(8)

                                        Text("Object")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("Save objects to track")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(width: 100)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // Saved Articles Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Saved Articles")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 16)

                        VStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "bookmark.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.orange)
                                            .frame(width: 40, height: 40)
                                            .background(Color(.systemGray6))
                                            .cornerRadius(6)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Article Title")
                                                .font(.system(size: 14, weight: .semibold))
                                            Text("Saved articles appear here")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(12)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Sign-up CTA Section
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Stay Updated")
                                        .font(.system(size: 16, weight: .bold))
                                    Text("Get alerts for cosmic events")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "bell.badge")
                                    .font(.system(size: 24))
                                    .foregroundColor(.orange)
                            }

                            Button(action: {}) {
                                Text("Enable Notifications")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(16)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                    }

                    Spacer()
                }
                .padding(.vertical, 20)
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemBackground))
        }
        .sheet(item: $selectedURL) { url in
            SafariWebView(url: url)
                .ignoresSafeArea()
        }
        .onAppear {
            PicOfDayVM.loadPicOfDay()
        }
    }
}

struct PicOfDayCard: View {
    let picOfDay: PicOfDay

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AsyncImage(url: picOfDay.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay(
                            VStack {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 32))
                                Text("Image failed to load")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        )
                default:
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .overlay(ProgressView())
                }
            }
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(picOfDay.altText)

            VStack(alignment: .leading, spacing: 12) {
                Text(picOfDay.date.formatted(date: .long, time: .omitted))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Text(picOfDay.title)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(2)

                Text(picOfDay.explanation)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(4)

                if !picOfDay.credit.isEmpty {
                    Text("Credit: \(picOfDay.credit)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    Text("Read more on NASA Science")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.orange)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HomeView(picOfDayVM: PicOfDayViewModel(
        fetchPicOfDayUseCase: FetchPicOfDayUseCase(repository: PicOfDayAPIService())
    ))
}
