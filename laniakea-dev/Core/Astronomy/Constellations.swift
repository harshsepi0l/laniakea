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

    /// The 88 constellations' official IAU genitive forms, used in star names ("β Geminorum").
    static let genitives: [String: String] = [
        "And": "Andromedae", "Ant": "Antliae", "Aps": "Apodis", "Aqr": "Aquarii", "Aql": "Aquilae", "Ara": "Arae",
        "Ari": "Arietis", "Aur": "Aurigae", "Boo": "Boötis", "Cae": "Caeli", "Cam": "Camelopardalis", "Cnc": "Cancri",
        "CVn": "Canum Venaticorum", "CMa": "Canis Majoris", "CMi": "Canis Minoris", "Cap": "Capricorni",
        "Car": "Carinae", "Cas": "Cassiopeiae", "Cen": "Centauri", "Cep": "Cephei", "Cet": "Ceti",
        "Cha": "Chamaeleontis", "Cir": "Circini", "Col": "Columbae", "Com": "Comae Berenices",
        "CrA": "Coronae Australis", "CrB": "Coronae Borealis", "Crv": "Corvi", "Crt": "Crateris", "Cru": "Crucis",
        "Cyg": "Cygni", "Del": "Delphini", "Dor": "Doradus", "Dra": "Draconis", "Equ": "Equulei", "Eri": "Eridani",
        "For": "Fornacis", "Gem": "Geminorum", "Gru": "Gruis", "Her": "Herculis", "Hor": "Horologii", "Hya": "Hydrae",
        "Hyi": "Hydri", "Ind": "Indi", "Lac": "Lacertae", "Leo": "Leonis", "LMi": "Leonis Minoris", "Lep": "Leporis",
        "Lib": "Librae", "Lup": "Lupi", "Lyn": "Lyncis", "Lyr": "Lyrae", "Men": "Mensae", "Mic": "Microscopii",
        "Mon": "Monocerotis", "Mus": "Muscae", "Nor": "Normae", "Oct": "Octantis", "Oph": "Ophiuchi", "Ori": "Orionis",
        "Pav": "Pavonis", "Peg": "Pegasi", "Per": "Persei", "Phe": "Phoenicis", "Pic": "Pictoris", "Psc": "Piscium",
        "PsA": "Piscis Austrini", "Pup": "Puppis", "Pyx": "Pyxidis", "Ret": "Reticuli", "Sge": "Sagittae",
        "Sgr": "Sagittarii", "Sco": "Scorpii", "Scl": "Sculptoris", "Sct": "Scuti", "Ser": "Serpentis",
        "Sex": "Sextantis", "Tau": "Tauri", "Tel": "Telescopii", "Tri": "Trianguli", "TrA": "Trianguli Australis",
        "Tuc": "Tucanae", "UMa": "Ursae Majoris", "UMi": "Ursae Minoris", "Vel": "Velorum", "Vir": "Virginis",
        "Vol": "Volantis", "Vul": "Vulpeculae",
    ]

    /// A star's traditional designation from the Bright Star Catalogue's name field, such as
    /// "78Bet Gem" → "β Geminorum", "73Xi 2Cet" → "ξ² Ceti", "41    And" → "41 Andromedae".
    static func designation(brightStarName raw: String) -> String? {
        guard let match = raw.firstMatch(of: #/^\s*(\d*)\s*([A-Z][a-z]{1,2})?\s*(\d)?\s*([A-Z][A-Za-z]{2})\s*$/#),
              let genitive = genitives[String(match.4)]
        else { return nil }
        if let greek = match.2.flatMap({ greekLetters[String($0)] }) {
            let index = match.3.map { String($0).compactMap { superscripts[$0] } }.map { String($0) } ?? ""
            return "\(greek)\(index) \(genitive)"
        }
        let number = String(match.1)
        return number.isEmpty ? nil : "\(number) \(genitive)"
    }

    private static let greekLetters: [String: String] = [
        "Alp": "α", "Bet": "β", "Gam": "γ", "Del": "δ", "Eps": "ε", "Zet": "ζ", "Eta": "η", "The": "θ", "Iot": "ι",
        "Kap": "κ", "Lam": "λ", "Mu": "μ", "Nu": "ν", "Xi": "ξ", "Omi": "ο", "Pi": "π", "Rho": "ρ", "Sig": "σ",
        "Tau": "τ", "Ups": "υ", "Phi": "φ", "Chi": "χ", "Psi": "ψ", "Ome": "ω",
    ]
    private static let superscripts: [Character: Character] = ["1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"]
}
