import Foundation
import simd

/// A place in Atlas, from the outside in: Laniakea, then a galaxy group or the Local Group, then the
/// Milky Way, then a star system.
enum AtlasPlace: Hashable {
    case laniakea
    case group(GalaxyGroup)
    case localGroup
    case milkyWay
    case starSystem(StarSystem)
    case solarSystem

    var title: String {
        switch self {
        case .laniakea: return "Laniakea"
        case .group(let group): return group.name
        case .localGroup: return "Local Group"
        case .milkyWay: return "Milky Way"
        case .starSystem(let system): return system.name
        case .solarSystem: return "Solar System"
        }
    }
}

/// One dot in a graph: a group, a galaxy or a star system, at its real position seen from above.
struct GraphNode: Identifiable {
    let id: String
    let name: String
    /// Layout position in the scene's unit (Mpc or parsecs).
    let position: SIMD2<Double>
    /// 0…1, sets the dot size.
    let size: Double
    var subtitle: String
    /// Where tapping "Open" goes, if this node has an inside view.
    let opens: AtlasPlace?
    var isHere = false
    /// Drawn fainter, e.g. groups whose membership in Laniakea is uncertain.
    var isMuted = false
    /// What this node is, for filtering: a type, and for stars which set it belongs to.
    var kinds: [ObjectKind] = []
    /// Direction on the sky (equatorial J2000 unit vector), for finding its constellation.
    var direction: SIMD3<Double>?
    var facts: FactSubject?
    /// Sets the dot's color on the star color scale: a star's surface temperature, or for a galaxy
    /// or group, the color temperature of its B−V.
    var temperatureK: Double?
    /// Height above the layout plane, in the same unit as `position` (shown in 3D).
    var depth: Double = 0
    /// Measured motion in layout units per year, for running time; nil where none is measured.
    var velocity: SIMD3<Double>?
    /// Drawn as a black hole (a black disc with white swirls) rather than a glowing dot.
    var isBlackHole = false
    /// Carries a small black-hole badge beside its dot: a galaxy with a measured central black hole.
    var hasBlackHole = false
    /// Other names search finds it by, besides `name`.
    var searchTerms: [String] = []
    /// Named at any zoom, like where you are (the Galactic Centre on the star map).
    var isLandmark = false

    /// Where it is `years` from now (straight-line motion).
    func position(atYears years: Double) -> SIMD3<Double> {
        SIMD3(position.x, position.y, depth) + (velocity ?? .zero) * years
    }
}

/// Everything a graph view draws for one place.
struct GraphScene {
    var nodes: [GraphNode]
    /// Pairs of node indices, Obsidian-style links.
    let links: [(Int, Int)]
    /// Unit of `position`, for the scale bar.
    let unit: Unit
    /// Optional filled region drawn behind everything (Laniakea's outline): cell centres and cell size.
    var region: (cells: [SIMD2<Double>], cellSize: Double)?
    /// The region's edge as line segments, drawn as an orange outline.
    var regionOutline: [(SIMD2<Double>, SIMD2<Double>)] = []
    /// The region's true 3D boundary as contour lines, one ring per layer of cells (shown in 3D,
    /// where the flat outline above would mislead).
    var regionContours: [(SIMD3<Double>, SIMD3<Double>)] = []
    /// How matter flows, as lines running downstream: through the region in 3D, and across the
    /// layout plane for the flat map.
    var flowLines: [[SIMD3<Double>]] = []
    var planeFlowLines: [[SIMD3<Double>]] = []
    /// The cosmic web's densest cells, with their density contrast; `planeWeb` is those near the
    /// layout plane, for the flat map.
    var web: [(position: SIMD3<Double>, density: Double)] = []
    var planeWeb: [(position: SIMD3<Double>, density: Double)] = []
    /// Radius in layout units that the first view fits on screen, around `fitCenter`.
    let fitRadius: Double
    var fitCenter: SIMD2<Double> = .zero
    /// For the 3D view: the height of the place's middle above the layout plane, and the radius
    /// that holds all of it, when it's more than the flat map's.
    var fitDepth: Double = 0
    var fitRadius3D: Double?
    let caption: String
    /// Each node's linked neighbours, built on first use (selection asks every frame).
    let adjacency = AdjacencyCache()
    /// How this place can be run through time, or nil when nothing here has measured motion.
    var motion: Motion?
    /// How fast the shaded region grows with the expansion of space, per year, about the origin
    /// (the Milky Way); 0 for none.
    var regionExpansionPerYear: Double = 0
    /// How far out a pinch may zoom; below 0.5 where something worth finding lies far beyond the
    /// first view (the Galactic Centre, 8 kpc from the Sun, on the star map).
    var minZoom: Double = 0.5

    /// A place's simulation: what it runs, how far it stays accurate, and its speeds.
    struct Motion {
        /// Shown with the time control, such as "Measured space motion".
        let model: String
        /// What the model leaves out, for the caption while it runs.
        let note: String
        /// Years either side of now that the straight-line motion stays right. Beyond it time
        /// keeps running, marked as a prediction, with `predictionNote` saying why.
        let reliableYears: Double
        let predictionNote: String
        /// Where time stops: the past can't go back further than the universe is old.
        let maxPastYears: Double
        let maxFutureYears: Double
        /// Years per second, with labels.
        let speeds: [(yearsPerSecond: Double, label: String)]
        /// The speed a place starts at: one where motion is visible at its scale.
        var defaultSpeedIndex = 1

        func isPrediction(_ years: Double) -> Bool { abs(years) > reliableYears }
    }

    enum Unit {
        case megaparsecs, kiloparsecs, parsecs

        var parsecs: Double {
            switch self {
            case .megaparsecs: return 1e6
            case .kiloparsecs: return 1e3
            case .parsecs: return 1
            }
        }
        var lightYears: Double { parsecs * 3.2616 }
        var symbol: String {
            switch self {
            case .megaparsecs: return "Mpc"
            case .kiloparsecs: return "kpc"
            case .parsecs: return "pc"
            }
        }
    }

    /// Indices of the nodes linked to `index`.
    func neighbors(of index: Int) -> Set<Int> {
        adjacency.neighbors(of: index, nodeCount: nodes.count, links: links)
    }
}

/// Neighbour lists for a scene, so a lookup doesn't scan every link. A class so the immutable scene
/// can fill it in lazily.
final class AdjacencyCache {
    private var lists: [[Int]]?

    func neighbors(of index: Int, nodeCount: Int, links: [(Int, Int)]) -> Set<Int> {
        if lists == nil {
            var built = [[Int]](repeating: [], count: nodeCount)
            for (a, b) in links where a < nodeCount && b < nodeCount {
                built[a].append(b)
                built[b].append(a)
            }
            lists = built
        }
        guard let lists, lists.indices.contains(index) else { return [] }
        return Set(lists[index])
    }
}

enum GraphBuilder {
    /// Groups in Laniakea, seen from above the supergalactic plane, with the Milky Way at the centre.
    /// Cosmicflows-4's pieces of the Local Group (Andromeda's group, the Milky Way's, the Magellanic
    /// Clouds and lone dwarfs) are folded into one Local Group node where we are.
    static func laniakea(_ map: LaniakeaMap, flow: LaniakeaFlow? = nil, localGroup: LocalGroup? = nil) -> GraphScene {
        let groups = map.groups.filter { g in
            if let localGroup { return !localGroup.includes(g) }
            // Without the Local Volume Database, fold the two halves Cosmicflows-4 names, and anything
            // within the Milky Way's halo (about 300 kpc).
            return g.id != GalaxyGroup.andromedaGroupID && g.id != GalaxyGroup.milkyWayGroupID && g.distanceMpc > 0.3
        }
        let largest = Double(groups.map(\.galaxyCount).max() ?? 1)
        var nodes = groups.map { g in
            GraphNode(
                id: "group-\(g.id)", name: g.name, position: SIMD2(g.position.x, g.position.y),
                size: log(Double(g.galaxyCount) + 1) / log(largest + 1),
                subtitle: groupSubtitle(g), opens: .group(g), isMuted: g.isOnBoundary,
                kinds: [g.isCluster ? .cluster : (g.galaxyCount > 1 ? .group : .loneGalaxy)],
                direction: SkyCoordinates.equatorial(supergalactic: g.position), facts: .group(g),
                temperatureK: colorTemperature(g.color), depth: g.position.z,
                // Measured line-of-sight velocity, expansion included, along the line from us.
                velocity: g.velocityKmS.map { simd_normalize(g.position) * $0 * SpaceMotion.megaparsecsPerYearPerKmS }
            )
        }
        nodes.append(GraphNode(
            id: "local-group", name: "Local Group", position: .zero, size: 0.35,
            subtitle: localGroup.map { "\($0.members.count) galaxies · You are here" } ?? "Our galaxy's group · You are here",
            opens: .localGroup, isHere: true, kinds: [.group], facts: .localGroup,
            temperatureK: colorTemperature(map.milkyWayColor)
        ))
        var points = groups.map(\.position)
        points.append(.zero)
        // Frame Laniakea itself; the Milky Way sits near its edge, not its middle.
        let xs = map.outlineCells.map(\.x), ys = map.outlineCells.map(\.y)
        let centre = SIMD2(((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2)
        let fit = map.outlineCells.map { simd_distance($0, centre) }.max().map { $0 + map.cellSizeMpc / 2 } ?? 150
        var scene = GraphScene(
            nodes: nodes, links: nearestNeighbors(points, k: 2, within: 12), unit: .megaparsecs,
            region: (map.outlineCells, map.cellSizeMpc), regionOutline: outline(cells: map.outlineCells, size: map.cellSizeMpc),
            fitRadius: fit, fitCenter: centre,
            caption: "\((groups.filter { !$0.isOnBoundary }.count + 1).formatted()) galaxy groups inside, faint ones on the edge. "
                + (flow == nil ? "Shading is Laniakea; empty parts haven't had galaxy distances measured, mostly behind the Milky Way's disc."
                   : "White lines show how matter flows and soft points mark the cosmic web (Cosmicflows-4), even where no galaxy has been measured. Flat, they're the slice through the supergalactic plane.")
        )
        scene.motion = GraphScene.Motion(
            model: "Measured velocity toward or away from us",
            note: "Each group moves along our line of sight at its measured velocity, which includes the expansion of space. Sideways motion isn't measured, so it isn't shown.",
            reliableYears: 1e9,
            predictionNote: "Predicted: past a billion years, straight lines drift from the truth. Gravity slows and bends each group's path, and the expansion speeds up over time.",
            // The universe is about 13.8 billion years old.
            maxPastYears: 1.3e10, maxFutureYears: 2e10,
            speeds: [(1e8, "100 million yr/s"), (1e9, "1 billion yr/s"), (5e9, "5 billion yr/s")],
            // Groups move a few thousand km/s across hundreds of Mpc: a billion years a second
            // shows it.
            defaultSpeedIndex: 1
        )
        scene.regionExpansionPerYear = SpaceMotion.expansionPerYear
        scene.regionContours = contours(cells: map.cells ?? [], size: map.cellSizeMpc)
        // Laniakea rises well above and below the flat map's plane: in 3D, frame all of it.
        if let cells = map.cells, !cells.isEmpty {
            let middle = SIMD3(centre.x, centre.y, cells.map(\.z).reduce(0, +) / Double(cells.count))
            scene.fitDepth = middle.z
            scene.fitRadius3D = cells.map { simd_distance($0, middle) }.max().map { $0 + map.cellSizeMpc / 2 }
        }
        if let flow {
            func d3(_ p: SIMD3<Float>) -> SIMD3<Double> { SIMD3(Double(p.x), Double(p.y), Double(p.z)) }
            scene.flowLines = flow.lines.map { $0.map(d3) }
            scene.planeFlowLines = flow.planeLines.map { $0.map { SIMD3(Double($0.x), Double($0.y), 0) } }
            let cells = flow.web.map { (position: d3($0.position), density: Double($0.density), inPlane: $0.inPlane) }
            scene.web = cells.map { ($0.position, $0.density) }
            scene.planeWeb = cells.filter(\.inPlane).map { (SIMD3($0.position.x, $0.position.y, 0), $0.density) }
        }
        return scene
    }

    /// Galaxies and groups go on the same color scale as stars through their B−V.
    static func colorTemperature(_ color: GalaxyColor?) -> Double? {
        color.map { StarColor.temperature(bv: $0.bMinusV) }
    }

    static func groupSubtitle(_ g: GalaxyGroup) -> String {
        let kind = g.isCluster ? "Cluster · " : ""
        let count = g.galaxyCount == 1 ? "1 galaxy" : "\(g.galaxyCount) galaxies"
        let place = g.isOnBoundary ? " · On Laniakea's edge" : ""
        return "\(kind)\(count) · \(distanceText(mpc: g.distanceMpc))\(place)"
    }

    /// A group's galaxies around its brightest member. Nearby groups use each galaxy's own distance;
    /// farther out the distances are too uncertain, so galaxies are shown where they sit on the sky.
    static func group(_ group: GalaxyGroup, galaxies: [Galaxy]) -> GraphScene {
        let centre = group.position
        let axis = simd_normalize(centre)
        // Two directions across the line of sight for the sky-plane layout: toward increasing
        // supergalactic longitude and toward the supergalactic pole.
        let across = simd_normalize(simd_cross(SIMD3(0, 0, 1), axis) == .zero ? SIMD3(1, 0, 0) : simd_cross(SIMD3(0, 0, 1), axis))
        let up = simd_cross(axis, across)
        let useDistances = group.distanceMpc < 5

        let nodes = galaxies.map { g -> GraphNode in
            let position: SIMD2<Double>
            if useDistances {
                let offset = g.position - centre
                position = SIMD2(offset.x, offset.y)
            } else {
                let direction = simd_normalize(g.position)
                // Seen from inside the sky, as on a sky chart, longitude increases to the left.
                position = SIMD2(-simd_dot(direction, across), simd_dot(direction, up)) * group.distanceMpc
            }
            let error = g.distanceErrorMpc.map { " ± \(distanceNumber($0))" } ?? ""
            return GraphNode(
                id: "galaxy-\(g.id)", name: g.name, position: position, size: g.id == group.id ? 1 : 0.45,
                subtitle: "\(g.morphology.map { "\($0) · " } ?? "")\(distanceNumber(g.distanceMpc))\(error) Mpc away", opens: nil,
                kinds: [ObjectKind.galaxy(morphology: g.morphology)],
                direction: SkyCoordinates.equatorial(supergalactic: g.position), facts: .galaxy(g, groupName: group.name),
                temperatureK: colorTemperature(g.color),
                // Depth only where each galaxy's own distance places it; on the sky layout there is none.
                depth: useDistances ? (g.position - centre).z : 0
            )
        }
        let hub = galaxies.firstIndex { $0.id == group.id }
        let links = hub.map { h in nodes.indices.filter { $0 != h }.map { (h, $0) } } ?? []
        // Fit most of the group; a few outlying members would otherwise shrink the rest to a dot.
        let spread = nodes.map { simd_length($0.position) }.sorted()
        // ...but always keep the brightest galaxy in view.
        let anchors = nodes.filter { $0.id == "galaxy-\(group.id)" }.map { simd_length($0.position) }
        let fit = max(spread.isEmpty ? 1 : spread[Int(Double(spread.count - 1) * 0.85)], anchors.max() ?? 0, 0.2) * 1.2
        return GraphScene(
            nodes: nodes, links: links, unit: .megaparsecs, region: nil, fitRadius: fit,
            caption: useDistances ? "Positions from each galaxy's distance" : "Positions on the sky; distances within the group are too uncertain to show depth"
        )
    }

    /// Stars with planets and the stars you can see with your eyes, seen from above the Milky Way's
    /// disc, with the Sun at the centre. A naked-eye star with planets appears once, under its own name.
    static func milkyWay(_ systems: [StarSystem], nakedEye: [NakedEyeStar] = [], sunTemperatureK: Double? = nil) -> GraphScene {
        let most = Double(systems.map(\.planetCount).max() ?? 1)
        var brightByHD: [Int: NakedEyeStar] = [:]
        for star in nakedEye { if let hd = star.hd { brightByHD[hd] = star } }
        var nodes = systems.map { s in
            let bright = s.hd.flatMap { brightByHD[$0] }
            let planets = s.planetCount == 1 ? "1 planet" : "\(s.planetCount) planets"
            return GraphNode(
                id: "star-\(s.id)", name: bright?.properName ?? s.name, position: SIMD2(s.position.x, s.position.y),
                size: 0.15 + 0.85 * Double(s.planetCount - 1) / max(most - 1, 1),
                subtitle: "\(bright?.properName != nil ? "\(s.name) · " : "")\(planets) · \(lightYearsText(parsecs: s.distanceParsecs))",
                opens: .starSystem(s),
                kinds: [ObjectKind.star(spectralType: s.spectralType, temperatureK: s.temperatureK), .withPlanets] + (bright != nil ? [.nakedEye] : []),
                direction: SkyCoordinates.equatorial(galactic: s.position), facts: .starSystem(s),
                temperatureK: s.temperatureK, depth: s.position.z,
                velocity: (s.velocityKmS ?? bright?.velocityKmS).map { $0 * SpaceMotion.parsecsPerYearPerKmS }
            )
        }
        let hostHDs = Set(systems.compactMap(\.hd))
        let visible = nakedEye.filter { star in star.position != nil && !(star.hd.map(hostHDs.contains) ?? false) }
        for star in visible {
            guard let p = star.position else { continue }
            nodes.append(GraphNode(
                id: "naked-\(star.id)", name: star.name, position: SIMD2(p.x, p.y),
                // Brighter stars draw bigger: magnitude −1.5 (Sirius) to 6 (the faintest you can see).
                size: max(0.05, min(1, (6 - star.magnitude) / 7.5)) * 0.8,
                subtitle: "\(star.designation.map { star.properName != nil ? "\($0) · " : "" } ?? "")Naked-eye star · \(lightYearsText(parsecs: star.distanceParsecs ?? 0))",
                opens: nil,
                kinds: [ObjectKind.star(spectralType: star.spectralType, temperatureK: star.temperatureK), .nakedEye],
                direction: SkyCoordinates.cartesian(longitudeDeg: star.raDeg, latitudeDeg: star.decDeg, distance: 1),
                facts: .nakedEyeStar(star), temperatureK: star.temperatureK, depth: p.z,
                velocity: star.velocityKmS.map { $0 * SpaceMotion.parsecsPerYearPerKmS }
            ))
        }
        nodes.append(GraphNode(
            id: "sun", name: "Sun", position: .zero, size: 0.6,
            subtitle: "Solar System · You are here", opens: .solarSystem, isHere: true, facts: .sun,
            temperatureK: sunTemperatureK
        ))
        var points = systems.map(\.position) + visible.compactMap(\.position)
        points.append(.zero)
        // Fit most systems; a few microlensing finds sit thousands of parsecs away.
        let distances = systems.map(\.distanceParsecs).sorted()
        let fit = distances.isEmpty ? 100 : distances[Int(Double(distances.count - 1) * 0.6)]
        var scene = GraphScene(
            nodes: nodes, links: nearestNeighbors(points, k: 2, within: 40), unit: .parsecs, region: nil,
            fitRadius: fit,
            caption: "\(systems.count.formatted()) stars with confirmed planets and \(visible.count.formatted()) more you can see with your eyes"
        )
        scene.motion = GraphScene.Motion(
            model: "Measured space motion",
            note: "Stars move along their measured paths relative to the Sun: proper motion across the sky and, where measured, radial velocity. Straight-line paths hold for about a million years.",
            reliableYears: 1e6,
            predictionNote: "Predicted: past a million years, straight lines drift from the truth. Real paths curve as each star, and the Sun, orbit the Galaxy every 230 million years.",
            maxPastYears: 1e9, maxFutureYears: 1e9,
            speeds: [(100, "100 yr/s"), (1000, "1,000 yr/s"), (10000, "10,000 yr/s"), (100_000, "100,000 yr/s"), (1_000_000, "1 million yr/s")]
        )
        return scene
    }

    /// The edge of a region of grid cells (given by their centres) as segments, by marching squares:
    /// corners of each square are cell centres, and the edge cuts across a square diagonally where
    /// one corner is in and its neighbours are out, so it isn't drawn as stair steps.
    static func outline(cells: [SIMD2<Double>], size: Double) -> [(SIMD2<Double>, SIMD2<Double>)] {
        let keys = Set(cells.map { SIMD2(Int(floor($0.x / size)), Int(floor($0.y / size))) })
        guard let minX = keys.map(\.x).min(), let maxX = keys.map(\.x).max(),
              let minY = keys.map(\.y).min(), let maxY = keys.map(\.y).max()
        else { return [] }
        func on(_ i: Int, _ j: Int) -> Bool { keys.contains(SIMD2(i, j)) }
        func point(_ i: Double, _ j: Double) -> SIMD2<Double> { SIMD2((i + 0.5) * size, (j + 0.5) * size) }
        var segments: [(SIMD2<Double>, SIMD2<Double>)] = []
        for i in (minX - 1)...maxX {
            for j in (minY - 1)...maxY {
                let (x, y) = (Double(i), Double(j))
                let bottom = point(x + 0.5, y), right = point(x + 1, y + 0.5), top = point(x + 0.5, y + 1), left = point(x, y + 0.5)
                let code = (on(i, j) ? 1 : 0) | (on(i + 1, j) ? 2 : 0) | (on(i + 1, j + 1) ? 4 : 0) | (on(i, j + 1) ? 8 : 0)
                switch code {
                case 1, 14: segments.append((left, bottom))
                case 2, 13: segments.append((bottom, right))
                case 3, 12: segments.append((left, right))
                case 4, 11: segments.append((right, top))
                case 6, 9: segments.append((bottom, top))
                case 7, 8: segments.append((left, top))
                case 5: segments += [(left, top), (bottom, right)]
                case 10: segments += [(left, bottom), (right, top)]
                default: break
                }
            }
        }
        return segments
    }

    /// A 3D region of cells as a stack of outlines, one through the middle of each layer of cells,
    /// like contour lines on a map but around the shape's edge at every height.
    static func contours(cells: [SIMD3<Double>], size: Double) -> [(SIMD3<Double>, SIMD3<Double>)] {
        var layers: [Int: [SIMD2<Double>]] = [:]
        for c in cells { layers[Int(floor(c.z / size)), default: []].append(SIMD2(c.x, c.y)) }
        var segments: [(SIMD3<Double>, SIMD3<Double>)] = []
        for (layer, flat) in layers {
            let z = (Double(layer) + 0.5) * size
            for (a, b) in outline(cells: flat, size: size) {
                segments.append((SIMD3(a.x, a.y, z), SIMD3(b.x, b.y, z)))
            }
        }
        return segments
    }

    /// Links each point to its `k` nearest neighbours closer than `within`, using a spatial hash.
    static func nearestNeighbors(_ points: [SIMD3<Double>], k: Int, within limit: Double) -> [(Int, Int)] {
        var buckets: [SIMD3<Int>: [Int]] = [:]
        func key(_ p: SIMD3<Double>) -> SIMD3<Int> { SIMD3(Int(floor(p.x / limit)), Int(floor(p.y / limit)), Int(floor(p.z / limit))) }
        for (i, p) in points.enumerated() { buckets[key(p), default: []].append(i) }

        var pairs = Set<SIMD2<Int>>()
        for (i, p) in points.enumerated() {
            let c = key(p)
            var near: [(Int, Double)] = []
            for dx in -1...1 { for dy in -1...1 { for dz in -1...1 {
                for j in buckets[c &+ SIMD3(dx, dy, dz)] ?? [] where j != i {
                    let d = simd_distance(p, points[j])
                    if d < limit { near.append((j, d)) }
                }
            } } }
            for (j, _) in near.sorted(by: { $0.1 < $1.1 }).prefix(k) {
                pairs.insert(SIMD2(min(i, j), max(i, j)))
            }
        }
        return pairs.map { ($0.x, $0.y) }
    }

    static func distanceText(mpc: Double) -> String {
        "\(distanceNumber(mpc)) Mpc · \(lightYearsText(parsecs: mpc * 1e6))"
    }

    static func distanceNumber(_ mpc: Double) -> String {
        mpc.formatted(.number.precision(.fractionLength(mpc < 10 ? 1 : 0)))
    }

    static func lightYearsText(parsecs: Double) -> String {
        let ly = parsecs * 3.2616
        switch ly {
        case 1e9...: return "\((ly / 1e9).formatted(.number.precision(.fractionLength(1)))) billion light-years"
        case 1e6...: return "\((ly / 1e6).formatted(.number.precision(.fractionLength(ly < 1e7 ? 1 : 0)))) million light-years"
        case 1e4...: return "\((ly / 1e3).formatted(.number.precision(.fractionLength(0)))) thousand light-years"
        default: return "\(ly.formatted(.number.precision(.fractionLength(ly < 100 ? 1 : 0)))) light-years"
        }
    }
}
