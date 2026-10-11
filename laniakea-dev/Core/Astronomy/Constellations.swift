import Foundation
import simd

/// The IAU constellation boundaries (Delporte 1930) as Roman (1987) arranged them for finding the
/// constellation at a position: the southern edge of each constellation, from north to south.
struct ConstellationBoundaries: Codable {
    struct Edge: Codable {
        let raLowHours: Double
        let raHighHours: Double
        let decLowDeg: Double
        let abbreviation: String
    }

    /// In the catalog's order; the first edge south of a position is its constellation.
    let edges: [Edge]

    /// The IAU abbreviation (such as "Vir") of the constellation in a J2000 equatorial direction.
    func constellation(of equatorial: SIMD3<Double>) -> String? {
        let p = SkyCoordinates.spherical(SkyCoordinates.precessToB1875(equatorial))
        let ra = p.l / 15
        return edges.first { p.b >= $0.decLowDeg && ra >= $0.raLowHours && ra < $0.raHighHours }?.abbreviation
    }

    /// Reads Roman's `data.dat`: lower RA, upper RA (hours), lower Dec (degrees), abbreviation.
    static func parse(_ text: String) -> ConstellationBoundaries {
        let edges = text.split(whereSeparator: \.isNewline).compactMap { line -> Edge? in
            let parts = line.split(separator: " ")
            guard parts.count == 4, let low = Double(parts[0]), let high = Double(parts[1]), let dec = Double(parts[2]) else { return nil }
            return Edge(raLowHours: low, raHighHours: high, decLowDeg: dec, abbreviation: String(parts[3]))
        }
        return ConstellationBoundaries(edges: edges)
    }
}

enum Constellation {
    /// The 88 constellations' official IAU names, by abbreviation.
    static let names: [String: String] = [
        "And": "Andromeda", "Ant": "Antlia", "Aps": "Apus", "Aqr": "Aquarius", "Aql": "Aquila", "Ara": "Ara",
        "Ari": "Aries", "Aur": "Auriga", "Boo": "Boötes", "Cae": "Caelum", "Cam": "Camelopardalis", "Cnc": "Cancer",
        "CVn": "Canes Venatici", "CMa": "Canis Major", "CMi": "Canis Minor", "Cap": "Capricornus", "Car": "Carina",
        "Cas": "Cassiopeia", "Cen": "Centaurus", "Cep": "Cepheus", "Cet": "Cetus", "Cha": "Chamaeleon",
        "Cir": "Circinus", "Col": "Columba", "Com": "Coma Berenices", "CrA": "Corona Australis",
        "CrB": "Corona Borealis", "Crv": "Corvus", "Crt": "Crater", "Cru": "Crux", "Cyg": "Cygnus",
        "Del": "Delphinus", "Dor": "Dorado", "Dra": "Draco", "Equ": "Equuleus", "Eri": "Eridanus", "For": "Fornax",
        "Gem": "Gemini", "Gru": "Grus", "Her": "Hercules", "Hor": "Horologium", "Hya": "Hydra", "Hyi": "Hydrus",
        "Ind": "Indus", "Lac": "Lacerta", "Leo": "Leo", "LMi": "Leo Minor", "Lep": "Lepus", "Lib": "Libra",
        "Lup": "Lupus", "Lyn": "Lynx", "Lyr": "Lyra", "Men": "Mensa", "Mic": "Microscopium", "Mon": "Monoceros",
        "Mus": "Musca", "Nor": "Norma", "Oct": "Octans", "Oph": "Ophiuchus", "Ori": "Orion", "Pav": "Pavo",
        "Peg": "Pegasus", "Per": "Perseus", "Phe": "Phoenix", "Pic": "Pictor", "Psc": "Pisces",
        "PsA": "Piscis Austrinus", "Pup": "Puppis", "Pyx": "Pyxis", "Ret": "Reticulum", "Sge": "Sagitta",
        "Sgr": "Sagittarius", "Sco": "Scorpius", "Scl": "Sculptor", "Sct": "Scutum", "Ser": "Serpens",
        "Sex": "Sextans", "Tau": "Taurus", "Tel": "Telescopium", "Tri": "Triangulum", "TrA": "Triangulum Australe",
        "Tuc": "Tucana", "UMa": "Ursa Major", "UMi": "Ursa Minor", "Vel": "Vela", "Vir": "Virgo", "Vol": "Volans",
        "Vul": "Vulpecula",
    ]

    static func name(_ abbreviation: String) -> String { names[abbreviation] ?? abbreviation }
}
