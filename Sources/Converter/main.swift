import AppKit
if CommandLine.arguments.contains("--preview-self-test") {
    Task { @MainActor in exit(await runPreviewSelfTests()) }
    RunLoop.main.run()
} else if CommandLine.arguments.contains("--self-test") {
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
