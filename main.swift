import Cocoa

// Before AppDelegate(): its managers read their settings on construction.
DefaultsMigration.run()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate

    // NSApplicationMain starts on the process main thread.
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
