import Foundation

/// The picture at the top of a fact sheet: a real photo when one exists, else the object drawn to
/// scale from its measurements. Nothing here is an artist's impression.
indirect enum FactHeader: Hashable {
    case photo(Photo)
    case toScale([ScaleBody])
    /// A galaxy drawn from its measured shape, tilt and color and the structure typical of its type.
    case galaxyModel(GalaxyModel)
    /// A patch of sky drawn from the star catalog: a constellation's stars and its IAU boundary.
    case skyChart(SkyChart)

    struct Photo: Hashable {
        let url: URL
        let credit: String
        /// What the frame shows, such as "2° of sky".
        var caption: String?
        /// Show only the left half (a NASA image with two views side by side).
        var showsLeftHalf = false
        /// Drawn on top of the photo, in the photo's own projection (a constellation's boundary).
        var overlay: SkyChart?
        /// Shown instead when the photo can't be loaded.
        var fallback: FactHeader?
    }

    /// A galaxy's look from data. The arms of a spiral are the typical pattern for its Hubble stage,
    /// not this galaxy's own, which no catalog records.
    struct GalaxyModel: Hashable {
        let type: GalaxyType?
        /// Hubble stage letter after "S" (a, b, c, d), which sets how open spiral arms are.
        let stage: Character?
        /// Minor over major axis as seen on the sky; 1 is face-on or round.
        let axisRatio: Double
        /// Position angle of the major axis, degrees from north toward east.
        let positionAngleDeg: Double
        let bMinusV: Double?
        /// Seeds the irregular clumps so each galaxy always looks the same.
        let seed: Int
    }

    /// A map of a patch of sky in the zenithal equidistant (ARC) projection, north up and east left,
    /// matching a hips2fits image made with the same centre, width and projection.
    /// Coordinates are fractions of the width from the centre: x right, y up.
    struct SkyChart: Hashable {
        struct Star: Hashable {
            let x: Double, y: Double
            let magnitude: Double
            let temperatureK: Double?
            let label: String?
        }
        struct Segment: Hashable {
            let x1: Double, y1: Double, x2: Double, y2: Double
        }
        let stars: [Star]
        let outline: [Segment]
        /// Height over width of the frame.
        let aspect: Double
    }

    /// One sphere in a to-scale drawing.
    struct ScaleBody: Hashable {
        let name: String
        /// In any unit shared by the bodies in one drawing.
        let radius: Double
        let look: Look
        /// The size is estimated rather than measured; drawn with a dashed edge.
        var isEstimate = false

        enum Look: Hashable {
            case star(temperatureK: Double?)
            case planet(PlanetComposition?)
        }
    }
}

enum CelestialPhotos {
    /// Full-disk photos of the Sun and planets from NASA's image library (public domain), by JPL
    /// Horizons ID. Credits are NASA's own.
    static let solarSystem: [String: FactHeader.Photo] = [
        "10": nasa("PIA21582", credit: "NASA/SDO", caption: "Solar Dynamics Observatory, 2017"),
        "199": nasa("PIA15160", credit: "NASA/Johns Hopkins University Applied Physics Laboratory/Carnegie Institution of Washington", caption: "MESSENGER"),
        "299": nasa("PIA23791", size: "orig", credit: "NASA/JPL-Caltech", caption: "Mariner 10, 1974", showsLeftHalf: true),
        "399": nasa("as17-148-22727", credit: "NASA", caption: "Apollo 17, 1972"),
        "499": nasa("PIA04591", size: "orig", credit: "NASA/JPL/Malin Space Science Systems", caption: "Mars Global Surveyor, 2003"),
        "599": nasa("PIA04866", credit: "NASA/JPL/Space Science Institute", caption: "Cassini, 2000"),
        "699": nasa("PIA11141", credit: "NASA/JPL/Space Science Institute", caption: "Cassini, 2008"),
        "799": nasa("PIA18182", credit: "NASA/JPL-Caltech", caption: "Voyager 2, 1986"),
        "899": nasa("PIA01492", credit: "NASA/JPL", caption: "Voyager 2, 1989"),
    ]

    /// `size` is one NASA actually publishes for that image; not every image has every size
    /// (Venus and Mars here only have the original).
    private static func nasa(_ id: String, size: String = "medium", credit: String, caption: String, showsLeftHalf: Bool = false) -> FactHeader.Photo {
        FactHeader.Photo(url: URL(string: "https://images-assets.nasa.gov/image/\(id)/\(id)~\(size).jpg")!,
                         credit: credit, caption: caption, showsLeftHalf: showsLeftHalf)
    }

    /// A real color photo of a patch of sky from the Digitized Sky Survey (DSS2), cut out by CDS's
    /// hips2fits service. `fovDegrees` is the width of the frame on the sky.
    static func sky(raDeg: Double, decDeg: Double, fovDegrees: Double, projection: String = "TAN") -> FactHeader.Photo {
        var components = URLComponents(string: "https://alasky.cds.unistra.fr/hips-image-services/hips2fits")!
        components.queryItems = [
            URLQueryItem(name: "hips", value: "CDS/P/DSS2/color"),
            URLQueryItem(name: "ra", value: String(format: "%.5f", raDeg)),
            URLQueryItem(name: "dec", value: String(format: "%.5f", decDeg)),
            URLQueryItem(name: "fov", value: String(format: "%.4f", fovDegrees)),
            URLQueryItem(name: "width", value: "900"),
            URLQueryItem(name: "height", value: "640"),
            URLQueryItem(name: "projection", value: projection),
            URLQueryItem(name: "format", value: "jpg"),
        ]
        let width = fovDegrees >= 1 ? "\(fovDegrees.formatted(.number.precision(.significantDigits(2))))°"
            : "\((fovDegrees * 60).formatted(.number.precision(.significantDigits(2))))′"
        return FactHeader.Photo(url: components.url!, credit: "Digitized Sky Survey (DSS2) via CDS", caption: "\(width) of sky across")
    }
}
