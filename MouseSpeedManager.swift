import Foundation

protocol MouseSpeedBackend {
    func readAcceleration() throws -> Double
    func writeAcceleration(_ value: Double) throws
}

enum MouseSpeedError: LocalizedError, Equatable {
    case backendUnavailable(String)
    case readFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .backendUnavailable(let message):
            return "Mouse speed service is unavailable: \(message)"
        case .readFailed(let message):
            return "Failed to read mouse speed: \(message)"
        case .writeFailed(let message):
            return "Failed to set mouse speed: \(message)"
        }
    }
}

final class MouseSpeedManager {
    static let minimumSpeed = 0.0
    static let maximumSpeed = 8.0
    static let fallbackSpeed = 1.0

    private let backend: MouseSpeedBackend
    private let defaults: UserDefaults
    private let baselineKey = "io.github.kkkevinky.tapper.pointerSpeed.baseline"
    private let lastSpeedKey = "io.github.kkkevinky.tapper.pointerSpeed.last"

    private(set) var currentSpeed: Double

    init(defaults: UserDefaults = .standard, backend: MouseSpeedBackend) {
        self.defaults = defaults
        self.backend = backend

        if defaults.object(forKey: lastSpeedKey) != nil {
            currentSpeed = Self.clamp(defaults.double(forKey: lastSpeedKey))
        } else if defaults.object(forKey: baselineKey) != nil {
            currentSpeed = Self.clamp(defaults.double(forKey: baselineKey))
        } else {
            currentSpeed = Self.fallbackSpeed
        }
    }

    @discardableResult
    func prepare() throws -> Double {
        if defaults.object(forKey: baselineKey) == nil {
            let baseline = Self.clamp(try backend.readAcceleration())
            defaults.set(baseline, forKey: baselineKey)

            if defaults.object(forKey: lastSpeedKey) == nil {
                currentSpeed = baseline
            }
        }

        if defaults.object(forKey: lastSpeedKey) != nil {
            try setSpeed(defaults.double(forKey: lastSpeedKey))
        }

        return currentSpeed
    }

    @discardableResult
    func setSpeed(_ value: Double) throws -> Double {
        let clampedValue = Self.clamp(value)
        try backend.writeAcceleration(clampedValue)
        defaults.set(clampedValue, forKey: lastSpeedKey)
        currentSpeed = clampedValue
        return clampedValue
    }

    @discardableResult
    func restoreSystemDefault() throws -> Double {
        let baseline: Double
        if defaults.object(forKey: baselineKey) != nil {
            baseline = defaults.double(forKey: baselineKey)
        } else {
            baseline = try backend.readAcceleration()
            defaults.set(Self.clamp(baseline), forKey: baselineKey)
        }

        let clampedBaseline = Self.clamp(baseline)
        try backend.writeAcceleration(clampedBaseline)
        defaults.removeObject(forKey: lastSpeedKey)
        currentSpeed = clampedBaseline
        return clampedBaseline
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, minimumSpeed), maximumSpeed)
    }
}
