import Foundation
import IOKit
import IOKit.hidsystem

final class MouseSpeedIOKitBackend: MouseSpeedBackend {
    private let accelerationKey = "HIDMouseAcceleration" as CFString

    // Lazily opened and cached. The slider is `isContinuous`, so each drag tick
    // would otherwise open/close the IOHIDSystem service — a kernel round-trip
    // per tick. We hold the connection for the lifetime of the backend instead.
    private var cachedConnection: io_connect_t?

    init() {}

    deinit {
        if let connection = cachedConnection {
            IOServiceClose(connection)
        }
    }

    func readAcceleration() throws -> Double {
        var acceleration = 0.0
        var result = IOHIDGetAccelerationWithKey(try openHIDSystem(), accelerationKey, &acceleration)

        if result != KERN_SUCCESS {
            invalidateConnection()
            result = IOHIDGetAccelerationWithKey(try openHIDSystem(), accelerationKey, &acceleration)
        }

        guard result == KERN_SUCCESS else {
            throw MouseSpeedError.readFailed(kernelMessage(for: result))
        }

        return acceleration
    }

    func writeAcceleration(_ value: Double) throws {
        var result = IOHIDSetAccelerationWithKey(try openHIDSystem(), accelerationKey, value)

        if result != KERN_SUCCESS {
            invalidateConnection()
            result = IOHIDSetAccelerationWithKey(try openHIDSystem(), accelerationKey, value)
        }

        guard result == KERN_SUCCESS else {
            throw MouseSpeedError.writeFailed(kernelMessage(for: result))
        }
    }

    private func openHIDSystem() throws -> io_connect_t {
        if let connection = cachedConnection {
            return connection
        }

        let matchingDictionary = IOServiceMatching(kIOHIDSystemClass)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDictionary)
        guard service != IO_OBJECT_NULL else {
            throw MouseSpeedError.backendUnavailable("IOHIDSystem service was not found.")
        }
        defer { IOObjectRelease(service) }

        var connection = io_connect_t()
        let result = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection)
        guard result == KERN_SUCCESS else {
            throw MouseSpeedError.backendUnavailable(kernelMessage(for: result))
        }

        cachedConnection = connection
        return connection
    }

    private func invalidateConnection() {
        if let connection = cachedConnection {
            IOServiceClose(connection)
        }
        cachedConnection = nil
    }

    private func kernelMessage(for result: kern_return_t) -> String {
        if let cString = mach_error_string(result) {
            return String(cString: cString)
        }

        return "Kernel error \(result)"
    }
}
