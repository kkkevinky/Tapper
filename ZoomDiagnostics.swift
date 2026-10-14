import Foundation

enum ZoomDiagnostics {
    static let enabled = ProcessInfo.processInfo.environment["TAPPER_ZOOM_DIAGNOSTICS"] == "1"

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        NSLog("[Zoom %.6f] %@", ProcessInfo.processInfo.systemUptime, message())
    }
}
