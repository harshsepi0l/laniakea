import SwiftUI

/// Sizes the map views share with Atlas's floating controls, so nothing sits under them.
enum AtlasChrome {
    /// Round buttons: back, the right-hand column, search.
    static let cornerButton: CGFloat = 44
    /// Room at the bottom for the search button and the time controls.
    static let bottomInset: CGFloat = 64
    /// Gap between the bottom controls and the tab bar.
    static let bottomGap: CGFloat = 10
    /// The open search field, with the gap above it.
    static let searchFieldHeight: CGFloat = 56
    /// Where pull-out lists start and stop: below the place name, above the bottom controls.
    static let panelTop: CGFloat = 60
    static let panelBottom: CGFloat = 64
}

/// The atlas: the map fills the screen, and the controls float over it. Top left is where you are
/// (back, and the whole path in a menu); down the right are facts, the sky view, filters, the
/// list of what's here and, in the Solar System, 3D; along the bottom are time and search.
struct AtlasView: View {
    @StateObject private var solarSystemVM = SolarSystemViewModel(repo: CosmicCatalog.shared)
    @StateObject private var cosmos = CosmosViewModel(repo: CosmicCatalog.shared)
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var focusID: String?
    @State private var factSubject: FactSubject?
    @State private var showSky = false
    @State private var showFilters = false
    @State private var showList = false
    @State private var solar3D = false
    /// The star and galaxy maps' 3D view; it stays on as you move between places.
    @State private var graph3D = false
    /// Set in Settings; off by default. Off, everything stays where it is today and no time controls show.
    @AppStorage("atlas.simulations") private var simulationsOn = false

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .overlay(alignment: .top) { topControls }
                .overlay(alignment: .bottom) { bottomControls }
                .toolbar(.hidden, for: .navigationBar)
                .sheet(item: $factSubject) { FactSheetView(subject: $0) }
                .sheet(isPresented: $showFilters) { filterSheet }
                .sheet(item: $solarSystemVM.selectedPlanet) { planet in
                    PlanetDetailSheet(
                        planet: planet,
                        distanceFromSunAU: solarSystemVM.distanceFromSun(planet),
                        distanceFromEarthAU: solarSystemVM.distanceFromEarth(planet),
                        distanceDateLabel: solarSystemVM.selectionDateLabel,
                        dwarf: solarSystemVM.dwarf(planet),
                        moons: solarSystemVM.moons
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
        .onChange(of: cosmos.current) { _, _ in
            showList = false
            closeSearch()
            cosmos.deepClock.reset(for: cosmos.scenes[cosmos.current]?.motion)
        }
        // A place's scene can arrive after you get there.
        .onChange(of: cosmos.scenes[cosmos.current] != nil) { _, loaded in
            if loaded { cosmos.deepClock.reset(for: cosmos.scenes[cosmos.current]?.motion) }
        }
        .onChange(of: simulationsOn) { _, _ in applySimulationSetting() }
        .onAppear {
            applySimulationSetting()
            solarSystemVM.load()
            cosmos.load(cosmos.current)
            cosmos.loadConstellations()
            cosmos.loadSun()
        }
    }

    // MARK: Floating controls

    private var topControls: some View {
        HStack(alignment: .top, spacing: 8) {
            PlaceControl(path: cosmos.path) { cosmos.goBack(to: $0) }
            Spacer(minLength: 8)
            // The list slides in on the right and has its own close button.
            if !showList { rail.transition(.opacity) }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .animation(.easeInOut(duration: 0.2), value: showList)
    }

    private var rail: some View {
        VStack(spacing: 10) {
            RoundButton(systemImage: "info", label: "Facts about \(cosmos.current == .solarSystem ? "the Sun" : cosmos.current.title)") {
                factSubject = FactSubject(cosmos.current)
            }
            RoundButton(systemImage: "camera.viewfinder", label: "Sky view") { showSky = true }
                .accessibilityHint("Point your device at the sky to find stars and planets")
            RoundButton(systemImage: "line.3.horizontal.decrease", label: "Filter", badge: filterCount) { showFilters = true }
            RoundButton(systemImage: "list.bullet", label: listLabel) { showList = true }
            switch cosmos.current {
            case .solarSystem:
                RoundButton(text: solar3D ? "2D" : "3D", label: solar3D ? "Switch to flat view" : "Switch to 3D view") { solar3D.toggle() }
            case .starSystem:
                EmptyView()
            default:
                RoundButton(text: graph3D ? "2D" : "3D", label: graph3D ? "Switch to flat view" : "Switch to 3D view") { graph3D.toggle() }
            }
        }
    }

    private var listLabel: String {
        if case .starSystem = cosmos.current { return "Show planets" }
        return "Show objects"
    }

    /// How many filter choices are on, shown on the filter button.
    private var filterCount: Int {
        cosmos.filter.kinds.count + (cosmos.filter.constellation == nil ? 0 : 1)
    }

    private var bottomControls: some View {
        VStack(spacing: 8) {
            if isSearching {
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { searchResults }
                HStack(spacing: 8) {
                    AtlasSearchField(text: $searchText, prompt: "Search \(cosmos.current.title)", focusOnAppear: true)
                    Button("Cancel") { closeSearch() }
                        .font(.system(size: 16, weight: .medium))
                        .tint(.orange)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    if let clock = timeClock {
                        TimeControls(clock: clock)
                    } else if simulationsOn, let motion = cosmos.scenes[cosmos.current]?.motion {
                        DeepTimeControls(clock: cosmos.deepClock, motion: motion)
                    }
                    Spacer(minLength: 0)
                    if canSearch {
                        RoundButton(systemImage: "magnifyingglass", label: "Search \(cosmos.current.title)") {
                            withAnimation(.easeInOut(duration: 0.2)) { isSearching = true }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, AtlasChrome.bottomGap)
    }

    /// The clock that runs the current place, if it has orbits and simulations are on.
    private var timeClock: SimulationClock? {
        guard simulationsOn else { return nil }
        switch cosmos.current {
        case .solarSystem: return solarSystemVM.planets.isEmpty ? nil : solarSystemVM.clock
        case .starSystem(let system): return cosmos.exoplanets[system] == nil ? nil : cosmos.exoplanetClock
        default: return nil
        }
    }

    /// With simulations off, the planets stay where they are today.
    private func applySimulationSetting() {
        guard !simulationsOn else { return }
        for clock in [solarSystemVM.clock, cosmos.exoplanetClock] {
            clock.isPlaying = false
            clock.reset()
        }
        cosmos.deepClock.reset()
    }

    private var canSearch: Bool {
        if case .starSystem = cosmos.current { return false }
        return true
    }

    private func closeSearch() {
        searchText = ""
        withAnimation(.easeInOut(duration: 0.2)) { isSearching = false }
    }

    private var filterSheet: some View {
        // Planets move between constellations while the clock plays, so the counts refresh each second.
        TimelineView(.periodic(from: .now, by: cosmos.current == .solarSystem ? 1 : 3600)) { _ in
            FilterSheet(place: cosmos.current.title, kinds: filterKinds, constellations: filterConstellations, filter: $cosmos.filter)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Maps

    @ViewBuilder
    private var content: some View {
        switch cosmos.current {
        case .solarSystem:
            solarSystem
        case .starSystem(let system):
            if let planets = cosmos.exoplanets[system] {
                ExoplanetSystemView(
                    system: system,
                    // All of a star's planets lie in its constellation, so only the kind filter applies here.
                    planets: planets.filter { cosmos.filter.kinds.isEmpty || cosmos.filter.kinds.contains(ObjectKind.planet(radiusEarths: $0.radiusEarths)) },
                    clock: cosmos.exoplanetClock,
                    showPlanets: $showList
                )
            } else {
                loadingOrError(cosmos.current, loading: "Loading \(system.name)'s planets…")
            }
        default:
            if let scene = cosmos.scenes[cosmos.current] {
                CosmicGraphView(
                    scene: scene, focusID: $focusID, visible: cosmos.visibility(for: cosmos.current),
                    onOpen: { cosmos.open($0) }, onFacts: { factSubject = $0 }, showObjects: $showList,
                    is3D: $graph3D, clock: cosmos.deepClock, runsTime: simulationsOn,
                    // The scale and caption sit beside the search button, and move up over the open field.
                    bottomInset: AtlasChrome.bottomGap + (isSearching ? AtlasChrome.searchFieldHeight : 0)
                        // Above the time control when it shows.
                        + (simulationsOn && scene.motion != nil && !isSearching ? AtlasChrome.searchFieldHeight : 0)
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
            SolarSystemView(
                planets: solarSystemVM.bodies,
                clock: solarSystemVM.clock,
                selectedPlanetID: solarSystemVM.selectedPlanet?.id,
                sunTemperatureK: cosmos.sunTemperatureK,
                isShown: { planet, date in
                    planet.id == Planet.earthID || cosmos.filter.allows(
                        kind: solarKind(planet),
                        constellation: constellation(of: planet, at: date)
                    )
                },
                dwarfIDs: Set(solarSystemVM.dwarfPlanets.map(\.id)),
                onSelect: { solarSystemVM.select($0) },
                showObjects: $showList,
                is3DOn: $solar3D
            )
        }
    }

    // MARK: Filters

    private var filterKinds: [(kind: ObjectKind, count: Int)] {
        guard cosmos.current == .solarSystem else { return cosmos.kindCounts(for: cosmos.current) }
        let date = solarSystemVM.clock.simulatedDate
        return ObjectKind.counts(solarSystemVM.bodies.compactMap { planet in
            guard cosmos.filter.constellation == nil || constellation(of: planet, at: date) == cosmos.filter.constellation else { return nil }
            return solarKind(planet)
        })
    }

    /// Rocky or giant for a planet (by density); dwarf planets are their own kind.
    private func solarKind(_ planet: Planet) -> ObjectKind? {
        DwarfPlanets.isDwarf(planet.id) ? .dwarfPlanet : ObjectKind.solarSystem(densityGramsPerCm3: planet.densityGramsPerCm3)
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
            for planet in solarSystemVM.bodies {
                guard let c = constellation(of: planet, at: date),
                      cosmos.filter.kinds.isEmpty || solarKind(planet).map(cosmos.filter.kinds.contains) == true
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
        case .localGroup: return "Loading the Local Group from the Local Volume Database…"
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
                SearchMatch(id: planet.id, name: planet.name, kind: DwarfPlanets.isDwarf(planet.id) ? "Dwarf planet" : "Planet") { solarSystemVM.select(planet) }
            }
        case .starSystem:
            return []
        default:
            guard let scene = cosmos.scenes[cosmos.current] else { return [] }
            let visible = cosmos.visibility(for: cosmos.current)
            return scene.nodes.indices
                .filter { i in
                    let n = scene.nodes[i]
                    return (visible?[i] ?? true) && (n.name.localizedCaseInsensitiveContains(query)
                        || n.searchTerms.contains { $0.localizedCaseInsensitiveContains(query) })
                }
                .map { scene.nodes[$0] }
                // Name matches first, then other names (such as "black hole").
                .sorted { a, b in
                    let na = a.name.localizedCaseInsensitiveContains(query), nb = b.name.localizedCaseInsensitiveContains(query)
                    return na != nb ? na : a.size > b.size
                }
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

/// Where you are, top left: a back button one step out, and the place's name over the place it's
/// in. Tapping the name lists the whole path to jump to any step.
struct PlaceControl: View {
    let path: [AtlasPlace]
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if path.count > 1 {
                Button { onSelect(path.count - 2) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Back to \(path[path.count - 2].title)")
            }
            Menu {
                ForEach(Array(path.indices.reversed()), id: \.self) { i in
                    Button { onSelect(i) } label: {
                        if i == path.count - 1 {
                            Label(path[i].title, systemImage: "checkmark")
                        } else {
                            Text(path[i].title)
                        }
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    if path.count > 1 {
                        Text(path[path.count - 2].title)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text(path.last?.title ?? "")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .lineLimit(1)
                .padding(.leading, path.count > 1 ? 0 : 8)
                .padding(.trailing, 8)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("You are in \(path.last?.title ?? ""). Show the path")
        }
        .padding(4)
        .atlasGlass(Capsule())
    }
}

/// A round floating button with an icon or a short word, and an optional count badge.
struct RoundButton: View {
    var systemImage: String? = nil
    var text: String? = nil
    let label: String
    var badge = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                } else {
                    Text(text ?? "").font(.system(size: 13, weight: .bold))
                }
            }
            .foregroundColor(.primary)
            .frame(width: AtlasChrome.cornerButton, height: AtlasChrome.cornerButton)
            // The whole circle takes the tap, not just the glyph: a fingertip often lands beside
            // a short label like "3D". The glass isn't interactive here because interactive glass
            // inside a button can take the touch itself; the button style gives the press instead.
            .atlasGlass(Circle(), interactive: false)
            .contentShape(Circle())
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundColor(.black)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.orange, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(badge > 0 ? "\(label), \(badge) on" : label)
    }
}

/// Time in years for the star and galaxy maps: play and pause, how far from now, speed and
/// direction, and a jump back to now. The menu says what the motion is based on.
struct DeepTimeControls: View {
    @ObservedObject var clock: DeepTimeClock
    let motion: GraphScene.Motion

    var body: some View {
        HStack(spacing: 2) {
            Button { clock.isPlaying.toggle() } label: {
                Image(systemName: clock.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .accessibilityLabel(clock.isPlaying ? "Pause" : "Play")
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    Text(DeepTimeClock.label(years: clock.years))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    // Past where straight-line motion stays right; the caption says why.
                    if motion.isPrediction(clock.years) {
                        Text("Predicted")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 8)
            }
            Menu {
                Section(motion.model) {
                    Picker("Speed", selection: $clock.speedIndex) {
                        ForEach(motion.speeds.indices, id: \.self) { i in
                            Text(motion.speeds[i].label).tag(i)
                        }
                    }
                    Toggle("Run backward", isOn: $clock.runsBackward)
                }
            } label: {
                HStack(spacing: 3) {
                    if clock.runsBackward { Image(systemName: "backward.fill").font(.system(size: 9)) }
                    Text(motion.speeds.indices.contains(clock.speedIndex) ? motion.speeds[clock.speedIndex].label : "")
                }
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .frame(height: 36)
            }
            .accessibilityLabel("Speed and direction")
            Button { clock.reset() } label: {
                Text("Now")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
            }
        }
        .foregroundColor(.primary)
        .lineLimit(1)
        .padding(4)
        .atlasGlass(Capsule())
        .fixedSize()
    }
}

/// The date, play and pause, speed and a jump back to today, in one pill.
struct TimeControls: View {
    @ObservedObject var clock: SimulationClock

    var body: some View {
        HStack(spacing: 2) {
            Button { clock.isPlaying.toggle() } label: {
                Image(systemName: clock.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .accessibilityLabel(clock.isPlaying ? "Pause" : "Play")
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                Text(clock.simulatedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 8)
            }
            Menu {
                Picker("Speed", selection: $clock.speed) {
                    ForEach(SimulationClock.Speed.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                Text(clock.speed.label)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .frame(height: 36)
            }
            .accessibilityLabel("Speed, \(clock.speed.label)")
            Button { clock.reset() } label: {
                Text("Today")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
            }
        }
        .foregroundColor(.primary)
        .lineLimit(1)
        .padding(4)
        .atlasGlass(Capsule())
        .fixedSize()
    }
}

struct AtlasSearchField: View {
    @Binding var text: String
    var prompt = "Search"
    var focusOnAppear = false
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
        .atlasGlass(Capsule())
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
        .onAppear { if focusOnAppear { isFocused = true } }
    }
}

extension View {
    /// The floating controls' background: Liquid Glass where available, else a blurred material.
    func atlasGlass<S: Shape>(_ shape: S, interactive: Bool = true) -> some View {
        modifier(AtlasGlass(shape: shape, interactive: interactive))
    }
}

/// A button that shrinks a little while pressed.
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct AtlasGlass<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color(.separator).opacity(0.4), lineWidth: 0.5))
        }
    }
}

/// Filters for the current place, in a sheet: the kinds of object found here, and a constellation.
struct FilterSheet: View {
    let place: String
    let kinds: [(kind: ObjectKind, count: Int)]
    /// Nil hides constellations; empty shows them as loading.
    let constellations: [(abbreviation: String, count: Int)]?
    @Binding var filter: AtlasFilter

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var facts: FactSubject?

    var body: some View {
        NavigationStack {
            List {
                if kinds.count > 1 || !filter.kinds.isEmpty {
                    Section {
                        ForEach(kinds, id: \.kind) { item in
                            row(selected: filter.kinds.contains(item.kind)) {
                                if filter.kinds.contains(item.kind) { filter.kinds.remove(item.kind) } else { filter.kinds.insert(item.kind) }
                            } content: {
                                if let swatch = swatch(item.kind) { Circle().fill(swatch).frame(width: 10, height: 10) }
                                Text(item.kind.label)
                                Spacer()
                                Text(item.count.formatted()).foregroundColor(.secondary).monospacedDigit()
                            }
                        }
                    } header: {
                        Text("Show")
                    } footer: {
                        Text("Pick none to show everything.")
                    }
                }
                if let constellations {
                    Section("Constellation") {
                        if constellations.isEmpty && filter.constellation == nil {
                            HStack { ProgressView(); Text("Loading the constellations…").foregroundColor(.secondary) }
                        } else {
                            row(selected: filter.constellation == nil) { filter.constellation = nil } content: {
                                Text("All constellations")
                                Spacer()
                            }
                            ForEach(constellations, id: \.abbreviation) { item in
                                row(selected: filter.constellation == item.abbreviation) { filter.constellation = item.abbreviation } content: {
                                    Text(Constellation.name(item.abbreviation))
                                    Spacer()
                                    Text(item.count.formatted()).foregroundColor(.secondary).monospacedDigit()
                                    Button { facts = .constellation(item.abbreviation) } label: {
                                        Image(systemName: "info.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .tint(.orange)
                                    .accessibilityLabel("Facts about \(Constellation.name(item.abbreviation))")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter \(place)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { filter = AtlasFilter() }
                        .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .tint(.orange)
            .sheet(item: $facts) { FactSheetView(subject: $0) }
        }
    }

    /// A tappable row with a checkmark when chosen.
    private func row<Content: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                content()
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                    .opacity(selected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .foregroundColor(.primary)
    }

    private func swatch(_ kind: ObjectKind) -> Color? {
        let dark = colorScheme == .dark
        if let t = kind.swatchTemperature { return StarColor.swiftUI(temperature: t, dark: dark) }
        return kind.swatchComposition?.swiftUI(dark: dark)
    }
}
