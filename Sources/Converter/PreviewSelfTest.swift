import Foundation

@MainActor func runPreviewSelfTests() async -> Int32 {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dropform-preview-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = Store()
    defer { store.stopPreviews() }
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let input = folder.appendingPathComponent("gradient.png")
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable("magick")!)
        process.arguments = ["-size", "1200x800", "gradient:navy-orange", input.path]
        try process.run(); process.waitUntilExit()
        store.add([input]); store.jobs[0].format = "jpg"
        store.jobs[0].quality = 90; store.schedulePreviews()
        try await Task.sleep(nanoseconds: 400_000_000)
        store.jobs[0].quality = 45; store.schedulePreviews()
        for _ in 0..<200 {
            if store.jobs[0].previewBytes != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let expected = try ConversionEngine().run(input: input, format: "jpg", directory: folder, quality: 45)
        guard store.jobs[0].previewBytes == outputSize(expected), store.jobs[0].output == nil else {
            throw ConversionFailure(message: "Preview did not match the latest settings, or published a final output")
        }
        print("PASS Live preview matches actual conversion with latest quality")
        guard let artifact = store.previewArtifacts[store.jobs[0].id], FileManager.default.fileExists(atPath: artifact.output.path), outputSize(artifact.output) == store.jobs[0].previewBytes else {
            throw ConversionFailure(message: "Viewable preview was not retained")
        }
        let previewFolder = artifact.folder
        store.jobs[0].quality = 80; store.schedulePreviews()
        guard !FileManager.default.fileExists(atPath: previewFolder.path) else { throw ConversionFailure(message: "Old preview was not cleaned up") }
        print("PASS Viewable output retained until invalidation and cleaned up")
        guard store.jobs[0].previewBytes == nil else { throw ConversionFailure(message: "Stale preview remained visible") }
        store.jobs.removeAll(); store.schedulePreviews()
        try await Task.sleep(nanoseconds: 500_000_000)
        guard store.jobs.isEmpty else { throw ConversionFailure(message: "Removed job returned") }
        print("PASS Settings invalidate old previews and removed jobs stay removed")
        store.compress = true
        store.add([expected])
        for _ in 0..<200 {
            if store.jobs[0].previewBytes != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let recompressed = try ConversionEngine().run(input: expected, format: "jpg", directory: folder, quality: 90)
        guard store.jobs[0].previewBytes == outputSize(recompressed) else {
            throw ConversionFailure(message: "Compression preview discarded actual output size")
        }
        if outputSize(recompressed) >= outputSize(expected) && store.jobs[0].previewState != "No reduction at this quality" {
            throw ConversionFailure(message: "Non-shrinking preview was not explained")
        }
        print("PASS Compression previews retain actual size even without a reduction")
        return 0
    } catch { print("FAIL Preview: \(error)"); return 1 }
}
