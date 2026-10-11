import AppKit
if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTests())
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
