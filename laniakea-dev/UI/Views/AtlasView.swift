import SwiftUI

struct AtlasView: View {
    @StateObject private var solarSystemVM = SolarSystemViewModel(repo: BundlePlanetRepo())
    @State private var searchText = ""
    @State private var selectedCategory = "Planets"

    private let categories = ["Planets", "Stars", "Constellations", "Galaxies"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            Button {
                                selectedCategory = category
                            } label: {
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
                .padding(.vertical, 12)

                content
            }
            .navigationTitle("Atlas")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        searchResults
                    }
                    AtlasSearchField(text: $searchText)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .sheet(item: $solarSystemVM.selectedPlanet) { planet in
                PlanetDetailSheet(
                    planet: planet,
                    distanceFromSunAU: solarSystemVM.distanceFromSun(planet),
                    distanceFromEarthAU: solarSystemVM.distanceFromEarth(planet),
                    distanceDateLabel: solarSystemVM.selectionDateLabel
                )
            }
        }
        .onAppear { solarSystemVM.load() }
    }

    @ViewBuilder
    private var content: some View {
        if selectedCategory == "Planets" {
            if let error = solarSystemVM.errorMessage {
                placeholder(icon: "exclamationmark.triangle", title: "Planets unavailable", message: error)
            } else if solarSystemVM.planets.isEmpty {
                ProgressView().frame(maxHeight: .infinity)
            } else {
                ZStack(alignment: .top) {
                    SolarSystemView(
                        planets: solarSystemVM.planets,
                        clock: solarSystemVM.clock,
                        selectedPlanetID: solarSystemVM.selectedPlanet?.id
                    ) { planet in
                        solarSystemVM.select(planet)
                    }
                    SimulationControls(clock: solarSystemVM.clock)
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                }
                .background(Color(.systemBackground))
            }
        } else {
            placeholder(
                icon: "sparkles",
                title: "\(selectedCategory) are coming soon",
                message: "They'll arrive with the live sky map. For now, explore the planets."
            )
        }
    }

    private var searchResults: some View {
        let matches = solarSystemVM.planets(matching: searchText)
        return VStack(alignment: .leading, spacing: 0) {
            if matches.isEmpty {
                Text("No planets match \"\(searchText)\". Stars and constellations are coming with the sky map.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(14)
            } else {
                ForEach(matches) { planet in
                    Button {
                        selectedCategory = "Planets"
                        searchText = ""
                        solarSystemVM.select(planet)
                    } label: {
                        HStack {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                            Text(planet.name)
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Text("Planet")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func placeholder(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(title)
                .font(.system(size: 18, weight: .bold))
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SimulationControls: View {
    @ObservedObject var clock: SimulationClock

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    Text(clock.simulatedDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Text("Not to scale")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Button {
                    clock.isPlaying.toggle()
                } label: {
                    Text(clock.isPlaying ? "Pause" : "Play")
                        .frame(minWidth: 52)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Color(.systemBackground), in: Capsule())
                }

                Menu {
                    Picker("Speed", selection: $clock.speed) {
                        ForEach(SimulationClock.Speed.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    Text(clock.speed.label)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                }

                Button {
                    clock.reset()
                } label: {
                    Text("Today")
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.primary)
            .lineLimit(1)
            .padding(4)
            .background(Color(.systemGray6), in: Capsule())
            .fixedSize()
        }
    }
}

struct AtlasSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search stars, planets...", text: $text)
                .font(.system(size: 16))
                .focused($isFocused)
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .modifier(SearchFieldBackground())
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
    }
}

private struct SearchFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color(.separator).opacity(0.4), lineWidth: 0.5))
        }
    }
}
