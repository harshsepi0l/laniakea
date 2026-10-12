import Combine
import CoreLocation
import CoreMotion
import Foundation
import simd

/// Where the device points, updated up to 60 times a second. Read by the drawing every frame
/// rather than published, so SwiftUI doesn't rebuild views at that rate.
final class SkyPointing {
    /// Directions in the local sky frame (x north, y west, z up).
    var look = SIMD3<Double>(1, 0, 0)
    var up = SIMD3<Double>(0, 0, 1)
    var right = SIMD3<Double>(0, -1, 0)
    /// Pinch zoom on top of the camera's own field of view.
    var zoom = 1.0
}

/// One thing in the sky the overlay can draw and the crosshair can pick.
struct SkyObject: Identifiable {
    enum Kind {
        case star(NakedEyeStar, host: StarSystem?)
        case planet(Planet)
        case sun
    }

    let id: String
    let name: String
    let kind: Kind
    /// J2000 equatorial unit vector.
    let equatorial: SIMD3<Double>
    let magnitude: Double
    let temperatureK: Double?
    var composition: PlanetComposition?
}

/// The camera sky view's data and sensors: the naked-eye stars, the planets and the Sun at today's
/// positions, your location, and the device's orientation.
@MainActor
final class SkyViewModel: NSObject, ObservableObject {
    enum LocationState { case waiting, ready, denied }

    @Published private(set) var objects: [SkyObject] = []
    @Published private(set) var location: CLLocation?
    @Published private(set) var locationState: LocationState = .waiting
    /// True when the motion sensors drive the view; false means drag to look around.
    @Published private(set) var usesMotion = false
    /// Whether north comes from true north (needs location) or the magnetic compass.
    @Published private(set) var isTrueNorth = false
    /// The view was dragged away from where the device points; it snaps back after a pause.
    @Published private(set) var isDragged = false
    @Published private(set) var error: String?
    @Published private(set) var boundaries: ConstellationBoundaries?
    @Published private(set) var nakedEye: [NakedEyeStar] = []
    @Published private(set) var planets: [Planet] = []

    let pointing = SkyPointing()
    /// Screen orientation relative to the device, so screen up and right map onto device axes.
    var interfaceOrientation: Int = 1

    private let repo: CosmicRepo & PlanetRepo
    private let locationManager = CLLocationManager()
    private let motion = CMMotionManager()

    // Drag to look around: altitude and azimuth of the view centre, in degrees.
    private(set) var manualAzimuth = 180.0
    private(set) var manualAltitude = 30.0
    private var lastTouch = Date.distantPast
    /// When snapping back began, and where the view and zoom were then.
    private var snap: (start: Date, look: SIMD3<Double>, up: SIMD3<Double>, zoom: Double)?
    private static let snapDelay = 5.0, snapDuration = 0.6

    init(repo: CosmicRepo & PlanetRepo = CosmicCatalog.shared) {
        self.repo = repo
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        updateManualPointing()
    }

    func start() {
        switch locationManager.authorizationStatus {
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted: locationState = .denied
        default: locationManager.requestLocation()
        }
        startMotion()
        Task { await load() }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }

    private func load() async {
        do {
            async let starsTask = repo.nakedEyeStars()
            async let planetsTask = repo.loadPlanets()
            async let systemsTask = try? repo.starSystems()
            async let boundariesTask = try? repo.constellations()
            let (stars, planets, systems, boundaries) = try await (starsTask, planetsTask, systemsTask, boundariesTask)
            self.boundaries = boundaries
            nakedEye = stars
            self.planets = planets
            var hostByHD: [Int: StarSystem] = [:]
            for s in systems ?? [] { if let hd = s.hd { hostByHD[hd] = s } }
            objects = stars.map { star in
                SkyObject(
                    id: "star-\(star.id)", name: star.name, kind: .star(star, host: star.hd.flatMap { hostByHD[$0] }),
                    equatorial: SkyCoordinates.cartesian(longitudeDeg: star.raDeg, latitudeDeg: star.decDeg, distance: 1),
                    magnitude: star.magnitude, temperatureK: star.temperatureK
                )
            }
            updateSolarSystem(date: Date())
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "The sky couldn't be loaded. Check your connection and try again."
        }
    }

    /// The Sun and planets as seen from Earth on a date (they move against the stars day to day).
    func updateSolarSystem(date: Date) {
        guard let earth = planets.first(where: { $0.id == Planet.earthID }) else { return }
        let earthAt = earth.orbit.position(at: date)
        var solar: [SkyObject] = [SkyObject(
            id: "sun", name: "Sun", kind: .sun, equatorial: SkyCoordinates.equatorial(ecliptic: -earthAt),
            magnitude: -26.7, temperatureK: 5772
        )]
        for planet in planets where planet.id != Planet.earthID {
            let planetAt = planet.orbit.position(at: date)
            solar.append(SkyObject(
                id: "planet-\(planet.id)", name: planet.name, kind: .planet(planet),
                equatorial: SkyCoordinates.equatorial(ecliptic: planetAt - earthAt),
                // Real brightness tonight, so Neptune doesn't outshine the stars around it.
                magnitude: PlanetMagnitude.apparent(planetID: planet.id, heliocentric: planetAt, earth: earthAt) ?? 0,
                temperatureK: nil, composition: planet.composition
            ))
        }
        objects = objects.filter { if case .star = $0.kind { return true } else { return false } } + solar
    }

    func localSky(at date: Date) -> LocalSky? {
        guard let location else { return nil }
        return LocalSky(latitudeDeg: location.coordinate.latitude, longitudeDeg: location.coordinate.longitude, date: date)
    }

    // MARK: Motion

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { usesMotion = false; return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        guard frames.contains(frame) else { usesMotion = false; return }
        isTrueNorth = frame == .xTrueNorthZVertical
        usesMotion = true
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] data, _ in
            guard let self, let q = data?.attitude.quaternion else { return }
            self.apply(simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w))
        }
    }

    /// The attitude quaternion turns the reference frame onto the device, so device axes in the
    /// reference frame are `q.act(axis)`. The back camera looks along the device's −z.
    private func apply(_ q: simd_quatd) {
        let (screenUp, screenRight): (SIMD3<Double>, SIMD3<Double>)
        switch interfaceOrientation {
        case 3: (screenUp, screenRight) = (SIMD3(1, 0, 0), SIMD3(0, -1, 0))   // landscape right: device top points left
        case 4: (screenUp, screenRight) = (SIMD3(-1, 0, 0), SIMD3(0, 1, 0))   // landscape left: device top points right
        case 2: (screenUp, screenRight) = (SIMD3(0, -1, 0), SIMD3(-1, 0, 0))  // upside down
        default: (screenUp, screenRight) = (SIMD3(0, 1, 0), SIMD3(1, 0, 0))   // portrait
        }
        let device = (look: q.act(SIMD3(0, 0, -1)), up: q.act(screenUp), right: q.act(screenRight))
        guard isDragged else {
            pointing.look = device.look
            pointing.up = device.up
            pointing.right = device.right
            return
        }
        let now = Date()
        if snap == nil, now.timeIntervalSince(lastTouch) > Self.snapDelay {
            snap = (now, pointing.look, pointing.up, pointing.zoom)
        }
        guard let snap else { return }
        // Glide from the dragged view back to the device's, easing out.
        let t = min(now.timeIntervalSince(snap.start) / Self.snapDuration, 1)
        let e = 1 - pow(1 - t, 3)
        let look = simd_normalize(snap.look + (device.look - snap.look) * e)
        var up = snap.up + (device.up - snap.up) * e
        up = simd_normalize(up - simd_dot(up, look) * look)
        pointing.look = look
        pointing.up = up
        pointing.right = simd_cross(look, up)
        pointing.zoom = snap.zoom + (1 - snap.zoom) * e
        if t >= 1 {
            self.snap = nil
            isDragged = false
        }
    }

    // MARK: Drag to look around

    /// Moves the view with a finger. With the motion sensors on, this takes the view away from where
    /// the device points until five seconds pass without a touch.
    func drag(by translation: CGSize, degreesPerPoint: Double) {
        takeOverFromDevice()
        manualAzimuth = (manualAzimuth - Double(translation.width) * degreesPerPoint).truncatingRemainder(dividingBy: 360)
        if manualAzimuth < 0 { manualAzimuth += 360 }
        manualAltitude = min(max(manualAltitude + Double(translation.height) * degreesPerPoint, -30), 89)
        updateManualPointing()
    }

    func pinch(to zoom: Double) {
        takeOverFromDevice()
        pointing.zoom = min(max(zoom, 1), 8)
    }

    /// Starts (or keeps) a dragged view from wherever the view is now, cancelling a snap back.
    private func takeOverFromDevice() {
        lastTouch = Date()
        guard usesMotion, !isDragged || snap != nil else { return }
        let here = LocalSky.altitudeAzimuth(pointing.look)
        manualAzimuth = here.azimuth
        manualAltitude = min(max(here.altitude, -30), 89)
        snap = nil
        isDragged = true
        updateManualPointing()
    }

    private func updateManualPointing() {
        let az = manualAzimuth * .pi / 180, alt = manualAltitude * .pi / 180
        let look = LocalSky.direction(altitude: alt, azimuth: az)
        let right = LocalSky.direction(altitude: 0, azimuth: az + .pi / 2)
        pointing.look = look
        pointing.right = right
        pointing.up = simd_cross(right, look)
    }
}

extension SkyViewModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted: locationState = .denied
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
                // True north needs location, so restart motion with it now allowed.
                motion.stopDeviceMotionUpdates()
                startMotion()
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            location = latest
            locationState = .ready
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if location == nil, manager.authorizationStatus == .denied { locationState = .denied }
        }
    }
}
