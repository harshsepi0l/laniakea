import Foundation
import simd

extension GraphBuilder {
    /// Adds the Milky Way's black holes that have distances to the star map. They go after every
    /// other node, so the scene's links still point at the right ones, and aren't linked: their
    /// neighbours on the map aren't related to them.
    static func addBlackHoles(_ holes: [BlackHole], to scene: inout GraphScene) {
        var farthest = 0.0
        for hole in holes {
            guard let p = hole.galacticPosition, let d = hole.distanceParsecs else { continue }
            farthest = max(farthest, d)
            let isCentre = hole.setting == .galacticCentre
            scene.nodes.append(GraphNode(
                id: "black-hole-\(hole.id)", name: hole.name, position: SIMD2(p.x, p.y),
                size: isCentre ? 0.9 : 0.45,
                subtitle: BlackHoleText.subtitle(hole), opens: nil,
                kinds: [.blackHole],
                direction: SkyCoordinates.cartesian(longitudeDeg: hole.raDeg, latitudeDeg: hole.decDeg, distance: 1),
                facts: .blackHole(hole), depth: p.z, isBlackHole: true,
                searchTerms: hole.aliases + ["black hole"], isLandmark: isCentre
            ))
        }
        // Most stars here are within a few thousand light-years, but the Galactic Centre is 27,000
        // away and some black holes farther still: let a pinch zoom out far enough to reach them,
        // without changing the first view.
        if farthest > 0 { scene.minZoom = min(scene.minZoom, scene.fitRadius / (farthest * 1.15)) }
    }

    /// Marks the galaxies on a group's map that have a measured central black hole with a badge,
    /// the black-hole filter, and its names for search.
    static func markBlackHoles(_ holes: [Int: BlackHole], in scene: inout GraphScene) {
        for i in scene.nodes.indices {
            let id = scene.nodes[i].id
            guard id.hasPrefix("galaxy-"), let pgc = Int(id.dropFirst("galaxy-".count)), let hole = holes[pgc] else { continue }
            scene.nodes[i].hasBlackHole = true
            scene.nodes[i].kinds.append(.blackHole)
            scene.nodes[i].searchTerms += [hole.name, "black hole"] + hole.aliases
            if let mass = hole.leadingMass {
                scene.nodes[i].subtitle += " · Black hole \(BlackHoleText.mass(mass, errors: false))"
            }
        }
    }
}

/// Words and numbers for black holes, shared by the map and the fact sheets.
enum BlackHoleText {
    /// "Black hole · 9.6 Suns · 1,600 light-years".
    static func subtitle(_ hole: BlackHole) -> String {
        var parts = [hole.isConfirmed ? "Black hole" : "Black hole candidate"]
        if let mass = hole.masses.first { parts.append(BlackHoleText.mass(mass, errors: false)) }
        if let d = distance(hole) { parts.append(d) }
        return parts.joined(separator: " · ")
    }

    /// "4.30 ± 0.04 million Suns", "6.9–8.2 Suns", "≥ 7.6 Suns", "4.0 +1.1 −0.6 million Suns".
    static func mass(_ m: BlackHole.Mass, errors: Bool = true) -> String {
        let (scale, word): (Double, String) = m.suns >= 1e9 ? (1e9, " billion") : m.suns >= 1e6 ? (1e6, " million") : (1, "")
        func number(_ x: Double) -> String { (x / scale).formatted(.number.precision(.significantDigits(x / scale < 10 ? 2 : 3))) }
        // Errors set the decimals, so "4.297 ± 0.042" reads as 4.30 ± 0.04.
        let digits: Int = {
            guard errors, let e = [m.plus, m.minus].compactMap({ $0 }).filter({ $0 > 0 }).min() else { return -1 }
            return max(0, -Int(floor(log10(e / scale))))
        }()
        func fixed(_ x: Double) -> String { (x / scale).formatted(.number.precision(.fractionLength(digits))) }
        var text: String
        if let top = m.rangeTop {
            text = "\(number(m.suns))–\(number(top))"
        } else if digits >= 0, let plus = m.plus {
            let minus = m.minus ?? plus
            text = abs(plus - minus) < 0.05 * max(plus, minus)
                ? "\(fixed(m.suns)) ± \(fixed(plus))"
                : "\(fixed(m.suns)) +\(fixed(plus)) −\(fixed(minus))"
        } else {
            text = number(m.suns)
        }
        return "\(m.limit.symbol)\(text)\(word) Suns"
    }

    /// "7,800 ± 460 light-years", "≥ 20,000 light-years".
    static func distance(_ hole: BlackHole) -> String? {
        guard let d = hole.distanceParsecs else { return nil }
        let ly = d * 3.2616
        if let e = hole.distanceErrorParsecs, e > 0, hole.distanceLimit == .none || hole.distanceLimit == .approximate {
            let error = e * 3.2616
            let rounded = { (x: Double) in x.formatted(.number.precision(.significantDigits(2))) }
            return "\(hole.distanceLimit.symbol)\(rounded(ly)) ± \(rounded(error)) light-years"
        }
        return hole.distanceLimit.symbol + GraphBuilder.lightYearsText(parsecs: d)
    }
}
