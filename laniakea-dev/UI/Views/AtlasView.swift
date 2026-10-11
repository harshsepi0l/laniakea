import SwiftUI

struct AtlasView: View {
    @StateObject private var solarSystemVM = SolarSystemViewModel(repo: CosmicCatalog.shared)
    @StateObject private var cosmos = CosmosViewModel(repo: CosmicCatalog.shared)
    @State private var searchText = ""
    @State private var focusID: String?
    @State private var factSubject: FactSubject?
    @State private var showSky = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        cosmos.showLaniakea()
                    } label: {
                        Label("Laniakea", systemImage: "circle.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(Color(.systemGray6), in: Capsule())
                    }
                    .accessibilityHint("Zooms out to the Laniakea supercluster")
                    Button {
                        factSubject = FactSubject(cosmos.current)
                    } label: {
                        Image(systemName: "info")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                            .background(Color(.systemGray6), in: Circle())
                    }
                    .accessibilityLabel("Facts about \(cosmos.current == .solarSystem ? "the Sun" : cosmos.current.title)")
                    Button {
                        showSky = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 40)
                            .background(Color(.systemGray6), in: Circle())
                    }
                    .accessibilityLabel("Sky view")
                    .accessibilityHint("Point your device at the sky to find stars and planets")
                    Spacer(minLength: 8)
                    Breadcrumb(path: cosmos.path) { cosmos.goBack(to: $0) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // Planets move between constellations while the clock plays, so the Solar System's
                // counts refresh each second.
                TimelineView(.periodic(from: .now, by: cosmos.current == .solarSystem ? 1 : 3600)) { _ in
                    FilterBar(kinds: filterKinds, constellations: filterConstellations, filter: $cosmos.filter) {
                        factSubject = .constellation($0)
                    }
                }
                .padding(.vertical, 8)

                content
                    .sheet(item: $factSubject) { FactSheetView(subject: $0) }
            }
            .navigationTitle("Atlas")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        searchResults
                    }
                    AtlasSearchField(text: $searchText, prompt: "Search \(cosmos.current.title)")
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
        .fullScreenCover(isPresented: $showSky) {
            SkyView(
                onOpenInAtlas: { place, focus in
                    showSky = false
                    cosmos.open(place)
                    focusID = focus
                },
                onOpenPlanet: { planet in
                    showSky = false
                    cosmos.open(.solarSystem)
                    solarSystemVM.select(planet)
                }
            )
        }
        .onAppear {
            solarSystemVM.load()
            cosmos.load(cosmos.current)
            cosmos.loadConstellations()
            cosmos.loadSun()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch cosmos.current {
        case .solarSystem:
            solarSystem
        case .starSystem(let system):
            if let planets = cosmos.exoplanets[system] {
                ZStack(alignment: .top) {
                    ExoplanetSystemView(
                        system: system,
                        // All of a star's planets lie in its constellation, so only the kind filter applies here.
                        planets: planets.filter { cosmos.filter.kinds.isEmpty || cosmos.filter.kinds.contains(ObjectKind.planet(radiusEarths: $0.radiusEarths)) },
                        clock: cosmos.exoplanetClock
                    )
                    SimulationControls(clock: cosmos.exoplanetClock)
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                }
            } else {
                loadingOrError(cosmos.current, loading: "Loading \(system.name)'s planets…")
            }
        default:
            if let scene = cosmos.scenes[cosmos.current] {
                CosmicGraphView(
                    scene: scene, focusID: $focusID, visible: cosmos.visibility(for: cosmos.current),
                    onOpen: { cosmos.open($0) }, onFacts: { factSubject = $0 }
                )
                .id(cosmos.current)
            } else {
                loadingOrError(cosmos.current, loading: loadingMessage(cosmos.current))
            }
        }
    }

    @ViewBuilder
    private var solarSystem: some View {
        if let error = solarSystemVM.errorMessage {
            placeholder(icon: "exclamationmark.triangle", title: "Planets unavailable", message: error) {
                solarSystemVM.load()
            }
        } else if solarSystemVM.planets.isEmpty {
            ProgressView().frame(maxHeight: .infinity)
        } else {
            ZStack(alignment: .top) {
                SolarSystemView(
                    planets: solarSystemVM.planets,
                    clock: solarSystemVM.clock,
                    selectedPlanetID: solarSystemVM.selectedPlanet?.id,
                    sunTemperatureK: cosmos.sunTemperatureK,
                    isShown: { planet, date in
                        planet.id == Planet.earthID || cosmos.filter.allows(
                            kind: ObjectKind.solarSystem(densityGramsPerCm3: planet.densityGramsPerCm3),
                            constellation: constellation(of: planet, at: date)
                        )
                    }
                ) { planet in
                    solarSystemVM.select(planet)
                }
                SimulationControls(clock: solarSystemVM.clock)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
            }
            .background(Color(.systemBackground))
        }
    }

    // MARK: Filters

    private var filterKinds: [(kind: ObjectKind, count: Int)] {
        guard cosmos.current == .solarSystem else { return cosmos.kindCounts(for: cosmos.current) }
        let date = solarSystemVM.clock.simulatedDate
        return ObjectKind.counts(solarSystemVM.planets.compactMap { planet in
            guard cosmos.filter.constellation == nil || constellation(of: planet, at: date) == cosmos.filter.constellation else { return nil }
            return ObjectKind.solarSystem(densityGramsPerCm3: planet.densityGramsPerCm3)
        })
    }

    /// Constellations to filter by here; nil where it doesn't apply (all of a star's planets share its constellation).
    private var filterConstellations: [(abbreviation: String, count: Int)]? {
        switch cosmos.current {
        case .starSystem:
            return nil
        case .solarSystem:
            guard cosmos.boundaries != nil else { return [] }
            let date = solarSystemVM.clock.simulatedDate
            var counts: [String: Int] = [:]
            for planet in solarSystemVM.planets {
                guard let c = constellation(of: planet, at: date),
                      cosmos.filter.kinds.isEmpty || ObjectKind.solarSystem(densityGramsPerCm3: planet.densityGramsPerCm3).map(cosmos.filter.kinds.contains) == true
                else { continue }
                counts[c, default: 0] += 1
            }
            return counts.map { ($0.key, $0.value) }.sorted { Constellation.name($0.0) < Constellation.name($1.0) }
        default:
            return cosmos.constellationCounts(for: cosmos.current)
        }
    }

    /// The constellation a planet is in as seen from Earth on a date.
    private func constellation(of planet: Planet, at date: Date) -> String? {
        guard planet.id != Planet.earthID, let boundaries = cosmos.boundaries,
              let earth = solarSystemVM.planets.first(where: { $0.id == Planet.earthID })
        else { return nil }
        let fromEarth = planet.orbit.position(at: date) - earth.orbit.position(at: date)
        return boundaries.constellation(of: SkyCoordinates.equatorial(ecliptic: fromEarth))
    }

    private func loadingMessage(_ place: AtlasPlace) -> String {
        switch place {
        case .laniakea: return "Mapping Laniakea from Cosmicflows-4. The first time, this downloads about 17 MB."
        case .milkyWay: return "Loading stars with planets from the NASA Exoplanet Archive…"
        default: return "Loading \(place.title)…"
        }
    }

    @ViewBuilder
    private func loadingOrError(_ place: AtlasPlace, loading: String) -> some View {
        if let error = cosmos.errors[place] {
            placeholder(icon: "exclamationmark.triangle", title: "\(place.title) unavailable", message: error) {
                cosmos.retry()
            }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text(loading)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private struct SearchMatch: Identifiable {
        let id: String
        let name: String
        let kind: String
        let action: () -> Void
    }

    private var matches: [SearchMatch] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        switch cosmos.current {
        case .solarSystem:
            return solarSystemVM.planets(matching: query).map { planet in
                SearchMatch(id: planet.id, name: planet.name, kind: "Planet") { solarSystemVM.select(planet) }
            }
        case .starSystem:
            return []
        default:
            guard let scene = cosmos.scenes[cosmos.current] else { return [] }
            let visible = cosmos.visibility(for: cosmos.current)
            return scene.nodes.indices
                .filter { (visible?[$0] ?? true) && scene.nodes[$0].name.localizedCaseInsensitiveContains(query) }
                .map { scene.nodes[$0] }
                .sorted { $0.size > $1.size }
                .prefix(8)
                .map { node in
                    SearchMatch(id: node.id, name: node.name, kind: node.subtitle) { focusID = node.id }
                }
        }
    }

    private var searchResults: some View {
        let matches = matches
        return VStack(alignment: .leading, spacing: 0) {
            if matches.isEmpty {
                Text("Nothing in \(cosmos.current.title) matches \"\(searchText)\".")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(14)
            } else {
                ForEach(matches) { match in
                    Button {
                        searchText = ""
                        match.action()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                            Text(match.name)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(match.kind)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
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

    private func placeholder(icon: String, title: String, message: String, retry: (() -> Void)? = nil) -> some View {
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
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.bordered)
                    .tint(.orange)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Where you are: each step back out is tappable. Long paths drop their middle steps to fit.
struct Breadcrumb: View {
    let path: [AtlasPlace]
    let onSelect: (Int) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            trail(Array(path.indices))
            if path.count > 2 { trail([0, -1, path.count - 1]) }
            trail([path.count - 1])
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color(.systemGray6), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("You are in \(path.last?.title ?? "")")
    }

    /// Indices into `path`; -1 stands for the collapsed middle.
    private func trail(_ indices: [Int]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(indices.enumerated()), id: \.offset) { position, index in
                if position > 0 {
                    Text("›").foregroundColor(.secondary)
                }
                if index < 0 {
                    Text("…").foregroundColor(.secondary)
                } else if index == path.count - 1 {
                    Text(path[index].title)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                } else {
                    Button(path[index].title) { onSelect(index) }
                        .foregroundColor(.secondary)
                        .buttonStyle(.plain)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
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
    var prompt = "Search"
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(prompt, text: $text)
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

/// Filter chips for the current place: a constellation menu and the kinds of object found here.
struct FilterBar: View {
    let kinds: [(kind: ObjectKind, count: Int)]
    /// Nil hides the constellation menu; empty shows it disabled while the boundaries load.
    let constellations: [(abbreviation: String, count: Int)]?
    @Binding var filter: AtlasFilter
    /// Opens the selected constellation's fact sheet.
    var onConstellationFacts: (String) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let constellations {
                    Menu {
                        if filter.constellation != nil {
                            Button("All constellations") { filter.constellation = nil }
                        }
                        ForEach(constellations, id: \.abbreviation) { item in
                            Button("\(Constellation.name(item.abbreviation))  \(item.count.formatted())") {
                                filter.constellation = item.abbreviation
                            }
                        }
                    } label: {
                        chip(filter.constellation.map(Constellation.name) ?? "Constellation", icon: "sparkles",
                             selected: filter.constellation != nil)
                    }
                    .disabled(constellations.isEmpty && filter.constellation == nil)
                    if let abbreviation = filter.constellation {
                        Button { onConstellationFacts(abbreviation) } label: {
                            Image(systemName: "info").font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary).frame(width: 34, height: 34)
                                .background(Color(.systemGray6), in: Circle())
                        }
                        .accessibilityLabel("Facts about \(Constellation.name(abbreviation))")
                    }
                }
                if kinds.count > 1 || !filter.kinds.isEmpty {
                    ForEach(kinds, id: \.kind) { item in
                        Button {
                            if filter.kinds.contains(item.kind) { filter.kinds.remove(item.kind) } else { filter.kinds.insert(item.kind) }
                        } label: {
                            chip("\(item.kind.label)  \(item.count.formatted())", swatch: swatch(item.kind),
                                 selected: filter.kinds.contains(item.kind))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if filter.isActive {
                    Button("Clear") { filter = AtlasFilter() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .frame(height: 34)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private func swatch(_ kind: ObjectKind) -> Color? {
        let dark = colorScheme == .dark
        if let t = kind.swatchTemperature { return StarColor.swiftUI(temperature: t, dark: dark) }
        return kind.swatchComposition?.swiftUI(dark: dark)
    }

    private func chip(_ text: String, icon: String? = nil, swatch: Color? = nil, selected: Bool) -> some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 12)) }
            if let swatch {
                Circle().fill(swatch).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.white.opacity(selected ? 0.8 : 0), lineWidth: 1))
            }
            Text(text).font(.system(size: 14, weight: selected ? .semibold : .regular)).monospacedDigit()
        }
        .foregroundColor(selected ? .white : .primary)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(selected ? Color.orange : Color(.systemGray6), in: Capsule())
        .contentShape(Capsule())
    }
}
