import Combine
import Foundation

/// Simulated time for the solar system, advanced once per rendered frame while playing.
final class SimulationClock: ObservableObject {
    enum Speed: Double, CaseIterable, Identifiable {
        case day = 1, week = 7, month = 30, year = 365

        var id: Double { rawValue }
        var label: String {
            switch self {
            case .day: return "1 day/s"
            case .week: return "1 week/s"
            case .month: return "1 month/s"
            case .year: return "1 year/s"
            }
        }
    }

    let startDate: Date
    private(set) var simulatedDate: Date
    @Published var speed: Speed = .week
    @Published var isPlaying = true {
        didSet { lastTick = nil }
    }
    private var lastTick: Date?

    init(startDate: Date = Date()) {
        self.startDate = startDate
        simulatedDate = startDate
    }

    func tick(now: Date) {
        defer { lastTick = now }
        guard isPlaying, let last = lastTick else { return }
        let elapsed = now.timeIntervalSince(last)
        // Skip big gaps (tab switches, backgrounding) instead of jumping ahead.
        guard elapsed > 0, elapsed < 0.25 else { return }
        simulatedDate.addTimeInterval(elapsed * speed.rawValue * 86_400)
    }

    func reset() {
        simulatedDate = startDate
        objectWillChange.send()
    }
}
