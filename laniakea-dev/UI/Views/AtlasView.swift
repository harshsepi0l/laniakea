import SwiftUI

struct AtlasView: View {
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "Constellations"

    let categories = ["Constellations", "Planets", "Stars", "Galaxies"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search stars, planets...", text: $searchText)
                        .font(.system(size: 16))

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(16)

                // Category Tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            Button(action: { selectedCategory = category }) {
                                Text(category)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(selectedCategory == category ? .white : .primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(selectedCategory == category ? Color.orange : Color(.systemGray6))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)

                // Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        if searchText.isEmpty {
                            // Placeholder content
                            VStack(alignment: .center, spacing: 24) {
                                Image(systemName: "globe.view")
                                    .font(.system(size: 48))
                                    .foregroundColor(.orange)

                                VStack(alignment: .center, spacing: 8) {
                                    Text("Explore the Cosmos")
                                        .font(.system(size: 18, weight: .bold))
                                    Text("Search for stars, planets, and constellations to discover more")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(48)
                        } else {
                            // Search results placeholder
                            ForEach(0..<5, id: \.self) { _ in
                                CelestialObjectCard()
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Atlas")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemBackground))
        }
    }
}

struct CelestialObjectCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                    .frame(width: 50, height: 50)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Celestial Object")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Distance: 100 ly • Magnitude: 5.2")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }

            Text("A brief description of this celestial object and why it's interesting to observe.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

#Preview {
    AtlasView()
}
