import Foundation

struct Signal: Codable {
    let size: Double
    let pressure: Double
    let depth: Double

    static let zero = Signal(size: 0, pressure: 0, depth: 0)
    var values: [Double] { [size, pressure, depth] }

    func combined(with other: Signal, using operation: (Double, Double) -> Double) -> Signal {
        Signal(size: operation(size, other.size),
               pressure: operation(pressure, other.pressure),
               depth: operation(depth, other.depth))
    }
}

struct ContactFrame {
    let time: TimeInterval
    let count: Int32
    let id: Int32
    let signal: Signal
}

enum Sensitivity: Int, CaseIterable {
    case higher = 10
    case baseline = 0
    case lower = -10

    var title: String {
        switch self {
        case .higher: "+10% от базовой"
        case .baseline: "Базовая"
        case .lower: "−10% от базовой"
        }
    }

    var thresholdMultiplier: Double { Double(110 - rawValue) / 100 }
}

struct Calibration: Codable {
    let channel: Int
    let threshold: Double

    static func fit(ordinary: [Signal], sharp: [Signal]) -> Calibration? {
        guard !ordinary.isEmpty, !sharp.isEmpty else { return nil }
        var best: (margin: Double, result: Calibration)?
        for channel in [1, 0, 2] {
            let low = ordinary.map { $0.values[channel] }.max() ?? 0
            let high = sharp.map { $0.values[channel] }.min() ?? 0
            guard high > 0 else { continue }
            let margin = (high - low) / high
            if margin >= 0.12, margin > (best?.margin ?? 0) {
                best = (margin, Calibration(channel: channel, threshold: (low + high) / 2))
            }
        }
        return best?.result
    }
}

struct ContactHistory {
    private static let window = 0.060
    private var samples: [(time: TimeInterval, signal: Signal)] = []
    private(set) var id: Int32?

    mutating func reset() {
        id = nil
        samples.removeAll(keepingCapacity: true)
    }

    mutating func measure(_ frame: ContactFrame) -> Signal {
        if id != frame.id {
            reset()
            id = frame.id
            samples.append((frame.time, .zero))
        }
        samples.removeAll { frame.time - $0.time > Self.window }
        let minimum = samples.reduce(frame.signal) { $0.combined(with: $1.signal, using: min) }
        samples.append((frame.time, frame.signal))
        return frame.signal.combined(with: minimum, using: -)
    }
}

struct PressDetector {
    private var history = ContactHistory()
    private var lastTime: TimeInterval?
    private var quietSince: TimeInterval?
    private var latched = false
    private var multipleContacts = false

    mutating func reset() {
        self = PressDetector()
    }

    mutating func consume(_ frame: ContactFrame, calibration: Calibration,
                          sensitivity: Sensitivity) -> Bool {
        if let lastTime, frame.time - lastTime > 0.18 { reset() }
        lastTime = frame.time
        if frame.count == 0 {
            reset()
            return false
        }
        if frame.count > 1 { multipleContacts = true }
        guard !multipleContacts else { return false }

        if history.id != frame.id {
            quietSince = nil
            latched = false
        }
        let score = history.measure(frame).values[calibration.channel]
        let threshold = calibration.threshold * sensitivity.thresholdMultiplier
        if score < threshold / 2 {
            let start = quietSince ?? frame.time
            quietSince = start
            if frame.time - start >= 0.10 { latched = false }
        } else {
            quietSince = nil
        }
        guard score >= threshold, !latched else { return false }
        latched = true
        return true
    }
}
