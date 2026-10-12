import Foundation
import simd

extension GraphBuilder {
    /// The Local Group in kiloparsecs from the Sun, seen from above the supergalactic plane like
    /// Laniakea: the Milky Way at its centre (Sagittarius A*), Andromeda, Triangulum and every
    /// confirmed dwarf at its measured distance, each linked to the galaxy it orbits.
    static func localGroup(_ group: LocalGroup, colors: GalaxyColors?) -> GraphScene {
        var index: [String: Int] = [:]
        let nodes = group.members.enumerated().map { i, g -> GraphNode in
            index[g.id] = i
            let isMilkyWay = g.id == LocalGroupGalaxy.milkyWayID
            let isBig = isMilkyWay || g.id == LocalGroupGalaxy.andromedaID
            let type = GalaxyType(morphology: g.morphology)
            return GraphNode(
                id: isMilkyWay ? "milky-way" : "lg-\(g.id)", name: g.name, position: SIMD2(g.position.x, g.position.y),
                // The two big spirals biggest; dwarfs by stellar mass, from a few thousand Suns (10³)
                // up to the LMC and Triangulum (about 10¹⁰).
                size: isBig ? 1 : g.logStellarMass.map { max(0.08, min(0.85, ($0 - 3) / 7 * 0.85)) } ?? 0.08,
                subtitle: isMilkyWay ? "Our galaxy · You are here" : localGroupSubtitle(g),
                opens: isMilkyWay ? .milkyWay : nil, isHere: isMilkyWay,
                kinds: [ObjectKind.galaxy(morphology: g.morphology)],
                direction: SkyCoordinates.cartesian(longitudeDeg: g.raDeg, latitudeDeg: g.decDeg, distance: 1),
                facts: isMilkyWay ? .milkyWay : .localGroupGalaxy(g),
                // Typical of its type (we can't measure the Milky Way's own color from inside it).
                temperatureK: type.flatMap { colors?.typical[$0] }.map { StarColor.temperature(bv: $0) },
                depth: g.position.z
            )
        }
        var links = group.members.enumerated().compactMap { i, g in g.hostID.flatMap { index[$0] }.map { (i, $0) } }
        // The two halves of the Local Group.
        if let mw = index[LocalGroupGalaxy.milkyWayID], let m31 = index[LocalGroupGalaxy.andromedaID] { links.append((mw, m31)) }

        let centre = group.centre
        let flat = group.members.map { simd_distance(SIMD2($0.position.x, $0.position.y), SIMD2(centre.x, centre.y)) }
        let full = group.members.map { simd_distance($0.position, centre) }
        var scene = GraphScene(
            nodes: nodes, links: links, unit: .kiloparsecs, region: nil,
            fitRadius: (flat.max() ?? 1000) * 1.05, fitCenter: SIMD2(centre.x, centre.y),
            caption: "\(group.members.count) galaxies within \((LocalGroup.zeroVelocityRadiusKpc / 1000).formatted()) Mpc of the Local Group's centre, "
                + "each at its measured distance (Local Volume Database). Lines join each dwarf to the galaxy it orbits."
        )
        scene.fitDepth = centre.z
        scene.fitRadius3D = (full.max() ?? 1000) * 1.05
        return scene
    }

    static func localGroupSubtitle(_ g: LocalGroupGalaxy) -> String {
        let place: String
        if let host = g.hostInSentence {
            place = "Orbits \(host)"
        } else {
            switch g.side {
            case .andromeda: place = "Andromeda's side"
            case .milkyWay: place = "Milky Way's side"
            case .neither: place = "On its own"
            }
        }
        return "\(place) · \(g.distanceKpc.map(kiloparsecsText) ?? "")"
    }

    /// "49.6 kpc · 162 thousand light-years".
    static func kiloparsecsText(_ kpc: Double) -> String {
        "\(kpc.formatted(.number.precision(.fractionLength(kpc < 100 ? 1 : 0)))) kpc · \(lightYearsText(parsecs: kpc * 1000))"
    }
}
