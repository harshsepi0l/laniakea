import Foundation
import simd

/// A place in Atlas, from the outside in: Laniakea, then a galaxy group or the Milky Way, then a star system.
enum AtlasPlace: Hashable {
    case laniakea
    case group(GalaxyGroup)
    case milkyWay
    case starSystem(StarSystem)
    case solarSystem

    var title: String {
        switch self {
        case .laniakea: return "Laniakea"
        case .group(let group): return group.name
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
    let subtitle: String
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
}

/// Everything a graph view draws for one place.
struct GraphScene {
    let nodes: [GraphNode]
    /// Pairs of node indices, Obsidian-style links.
    let links: [(Int, Int)]
    /// Unit of `position`, for the scale bar.
    let unit: Unit
    /// Optional filled region drawn behind everything (Laniakea's outline): cell centres and cell size.
    var region: (cells: [SIMD2<Double>], cellSize: Double)?
    /// The region's edge as line segments, drawn as an orange outline.
    var regionOutline: [(SIMD2<Double>, SIMD2<Double>)] = []
    /// Radius in layout units that the first view fits on screen, around `fitCenter`.
    let fitRadius: Double
    var fitCenter: SIMD2<Double> = .zero
    let caption: String
    /// Each node's linked neighbours, built on first use (selection asks every frame).
    let adjacency = AdjacencyCache()

    enum Unit {
        case megaparsecs, parsecs

        var lightYears: Double { self == .megaparsecs ? 3.2616e6 : 3.2616 }
        var symbol: String { self == .megaparsecs ? "Mpc" : "pc" }
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
    static func laniakea(_ map: LaniakeaMap) -> GraphScene {
        let largest = Double(map.groups.map(\.galaxyCount).max() ?? 1)
        var nodes = map.groups.map { g in
            GraphNode(
                id: "group-\(g.id)", name: g.name, position: SIMD2(g.position.x, g.position.y),
                size: log(Double(g.galaxyCount) + 1) / log(largest + 1),
                subtitle: groupSubtitle(g), opens: .group(g), isMuted: g.isOnBoundary,
                kinds: [g.isCluster ? .cluster : (g.galaxyCount > 1 ? .group : .loneGalaxy)],
                direction: SkyCoordinates.equatorial(supergalactic: g.position), facts: .group(g),
                temperatureK: colorTemperature(g.color)
            )
        }
        nodes.append(GraphNode(
            id: "milky-way", name: "Milky Way", position: .zero, size: 0.35,
            subtitle: "Our galaxy · You are here", opens: .milkyWay, isHere: true, facts: .milkyWay,
            temperatureK: colorTemperature(map.milkyWayColor)
        ))
        var points = map.groups.map(\.position)
        points.append(.zero)
        // Frame Laniakea itself; the Milky Way sits near its edge, not its middle.
        let xs = map.outlineCells.map(\.x), ys = map.outlineCells.map(\.y)
        let centre = SIMD2(((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2)
        let fit = map.outlineCells.map { simd_distance($0, centre) }.max().map { $0 + map.cellSizeMpc / 2 } ?? 150
        return GraphScene(
            nodes: nodes, links: nearestNeighbors(points, k: 2, within: 12), unit: .megaparsecs,
            region: (map.outlineCells, map.cellSizeMpc), regionOutline: outline(cells: map.outlineCells, size: map.cellSizeMpc),
            fitRadius: fit, fitCenter: centre,
            caption: "\(map.groups.filter { !$0.isOnBoundary }.count.formatted()) galaxy groups inside, faint ones on the edge. "
                + "Shading is Laniakea; empty parts haven't had galaxy distances measured, mostly behind the Milky Way's disc."
        )
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
    static func group(_ group: GalaxyGroup, galaxies: [Galaxy], milkyWayColor: GalaxyColor? = nil) -> GraphScene {
        let centre = group.position
        let axis = simd_normalize(centre)
        // Two directions across the line of sight for the sky-plane layout: toward increasing
        // supergalactic longitude and toward the supergalactic pole.
        let across = simd_normalize(simd_cross(SIMD3(0, 0, 1), axis) == .zero ? SIMD3(1, 0, 0) : simd_cross(SIMD3(0, 0, 1), axis))
        let up = simd_cross(axis, across)
        let useDistances = group.distanceMpc < 5

        var nodes = galaxies.map { g -> GraphNode in
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
                temperatureK: colorTemperature(g.color)
            )
        }
        let hub = galaxies.firstIndex { $0.id == group.id }
        var links = hub.map { h in nodes.indices.filter { $0 != h }.map { (h, $0) } } ?? []
        // Cosmicflows-4 has no entry for our own galaxy, so add it to the group it belongs to: the
        // Local Group, led by Andromeda (PGC 2557).
        if group.id == GalaxyGroup.localGroupID {
            let here = -centre
            nodes.append(GraphNode(
                id: "milky-way", name: "Milky Way", position: SIMD2(here.x, here.y), size: 0.8,
                subtitle: "Our galaxy · You are here", opens: .milkyWay, isHere: true, facts: .milkyWay,
                temperatureK: colorTemperature(milkyWayColor)
            ))
            if let hub { links.append((hub, nodes.count - 1)) }
        }
        // Fit most of the group; a few outlying members would otherwise shrink the rest to a dot.
        let spread = nodes.map { simd_length($0.position) }.sorted()
        // ...but always keep the brightest galaxy and, in the Local Group, the Milky Way in view.
        let anchors = nodes.filter { $0.isHere || $0.id == "galaxy-\(group.id)" }.map { simd_length($0.position) }
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
                temperatureK: s.temperatureK
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
                facts: .nakedEyeStar(star), temperatureK: star.temperatureK
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
        return GraphScene(
            nodes: nodes, links: nearestNeighbors(points, k: 2, within: 40), unit: .parsecs, region: nil,
            fitRadius: fit,
            caption: "\(systems.count.formatted()) stars with confirmed planets and \(visible.count.formatted()) more you can see with your eyes"
        )
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
