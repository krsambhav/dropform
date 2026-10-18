import AppKit
import PDFKit

func runSelfTests() -> Int32 {
    setbuf(stdout, nil)
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("dropform-tests-" + UUID().uuidString)
    var passed = 0, failed = 0
    func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw ConversionFailure(message: message) }
    }
    func test(_ name: String, _ body: () throws -> Void) {
        do { try body(); passed += 1; print("PASS \(name)") }
        catch { failed += 1; print("FAIL \(name): \(error.localizedDescription)") }
    }
    func process(_ executable: String, _ arguments: [String]) throws {
        let task = Process(); task.environment = engineEnvironment(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        try task.run(); task.waitUntilExit(); try check(task.terminationStatus == 0, "Fixture generation failed")
    }
    func exists(_ url: URL) throws {
        try check(fm.fileExists(atPath: url.path), "Missing output")
        let size = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        try check(size > 0, "Empty output")
    }
    do { try fm.createDirectory(at: root, withIntermediateDirectories: true) } catch { print(error); return 1 }
    defer { try? fm.removeItem(at: root) }
    let engine = ConversionEngine()
    let svg = root.appendingPathComponent("source.svg")
    let png = root.appendingPathComponent("source.png")
    let wav = root.appendingPathComponent("source.wav")
    let mov = root.appendingPathComponent("source.mov")
    let srt = root.appendingPathComponent("source.srt")
    let rtf = root.appendingPathComponent("source.rtf")
    let csv = root.appendingPathComponent("source.csv")
    let email = root.appendingPathComponent("source.eml")
    let markdown = root.appendingPathComponent("source.md")
    test("Generate fixtures") {
        try "Subject: Test message\r\nFrom: example@example.com\r\nTo: test@example.com\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\nSGVsbG8gRHJvcGZvcm0=\r\n".write(to: email, atomically: true, encoding: .utf8)
        try "# Hello Dropform\n\nA **formatted** document.".write(to: markdown, atomically: true, encoding: .utf8)
        try "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"128\" height=\"96\"><rect width=\"128\" height=\"96\" fill=\"green\"/></svg>".write(to: svg, atomically: true, encoding: .utf8)
        try exists(engine.run(input: svg, format: "png", directory: root, quality: 80))
        try process(executable("ffmpeg")!, ["-v","error","-f","lavfi","-i","sine=frequency=440:duration=0.3",wav.path])
        try process(executable("ffmpeg")!, ["-v","error","-f","lavfi","-i","color=c=green:s=128x96:d=0.3","-f","lavfi","-i","sine=frequency=440:duration=0.3","-c:a","aac","-shortest",mov.path])
        try "1\n00:00:00,000 --> 00:00:01,000\nHello Dropform\n".write(to: srt, atomically: true, encoding: .utf8)
        try "{\\rtf1\\ansi Hello Dropform.}".write(to: rtf, atomically: true, encoding: .utf8)
        try "Name,Count\nApples,3\nPears,5\n".write(to: csv, atomically: true, encoding: .utf8)
    }
    test("SVG quadratic paths preserve transparency and resize") {
        let input = root.appendingPathComponent("quadratic.svg")
        let source = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><path fill="#000" transform="translate(60.53333 158.07407) scale(0.1135802 -0.1135802)" d="M602 -510Q510 -510 427.0 -480.5Q344 -451 278.5 -398.5Q213 -346 172 -276L424 -154Q450 -202 498.5 -227.0Q547 -252 604 -252Q665 -252 719.0 -231.5Q773 -211 805.5 -170.5Q838 -130 836 -70V244H870V1080H1108V-74Q1108 -114 1104.5 -149.5Q1101 -185 1092 -220Q1066 -319 995.5 -383.0Q925 -447 823.0 -478.5Q721 -510 602 -510ZM578 -30Q429 -30 317.0 45.0Q205 120 142.5 249.0Q80 378 80 540Q80 705 143.5 833.5Q207 962 322.0 1036.0Q437 1110 592 1110Q746 1110 851.0 1035.0Q956 960 1010.0 831.0Q1064 702 1064 540Q1064 378 1009.5 249.0Q955 120 847.0 45.0Q739 -30 578 -30ZM622 212Q713 212 767.5 253.0Q822 294 846.0 368.0Q870 442 870 540Q870 638 846.0 712.0Q822 786 769.5 827.0Q717 868 632 868Q541 868 482.5 823.5Q424 779 396.0 704.5Q368 630 368 540Q368 449 395.0 374.5Q422 300 478.0 256.0Q534 212 622 212Z"/></svg>
        """
        try source.write(to: input, atomically: true, encoding: .utf8)
        try check(routeEngines(input: input, format: "png") == ["rsvg-convert", "magick"], "SVG route omits renderer")
        try check(routeEngines(input: input, format: "docx") == ["rsvg-convert", "magick", "soffice"], "SVG document route omits renderer")
        let original = try Data(contentsOf: input)
        let output = try engine.run(input: input, format: "png", directory: root, quality: 90, maxDimension: 64)
        guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: output)) else { throw ConversionFailure(message: "Unreadable SVG render") }
        try check(bitmap.pixelsWide == 64 && bitmap.pixelsHigh == 64, "SVG resize ignored")
        try check(bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0, "SVG transparency lost")
        let hasVisiblePath = (0..<bitmap.pixelsHigh).contains { y in
            (0..<bitmap.pixelsWide).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
        }
        try check(hasVisiblePath, "SVG path disappeared")
        try check(try Data(contentsOf: input) == original, "SVG source changed")
        try exists(engine.run(input: input, format: "jpg", directory: root, quality: 80))
    }
    test("Malformed SVG is recoverable and leaves no staged files") {
        let input = root.appendingPathComponent("broken.svg")
        try "<svg><path".write(to: input, atomically: true, encoding: .utf8)
        do {
            _ = try engine.run(input: input, format: "png", directory: root, quality: 80)
            throw ConversionFailure(message: "Malformed SVG accepted")
        } catch let error as ConversionFailure where error.message == "Malformed SVG accepted" { throw error }
        catch { try check(error.localizedDescription.contains("SVG"), "Unexpected SVG failure") }
        try check(try fm.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".dropform-") }, "SVG staging files leaked")
        try exists(engine.run(input: svg, format: "png", directory: root, quality: 80))
        try exists(engine.run(input: png, format: "webp", directory: root, quality: 80))
    }
    for input in [png, wav, mov, srt, rtf, csv, markdown, email] {
        guard let group = family(for: input) else { continue }
        for format in group.outputs {
            test("\(group.name): \(input.pathExtension) → \(format)") {
                let output = try engine.run(input: input, format: format, directory: root, quality: 80)
                try exists(output)
                if group.engine == "ffmpeg" && group.name != "Subtitles" && format != "gif" {
                    try process(executable("ffmpeg")!, ["-v","error","-i",output.path,"-f","null","-"])
                }
                if group.name == "Images" && !["pdf", "docx", "doc", "odt", "html"].contains(format) {
                    try process(executable("magick")!, ["identify",output.path])
                }
                if group.name == "Subtitles" && ["srt", "vtt", "ass", "txt"].contains(format) { try check(try String(contentsOf: output).contains("Hello Dropform"), "Subtitle text missing") }
                if group.name == "Images" && ["docx", "odt", "html"].contains(format) {
                    let marker = format == "docx" ? "word/media/" : format == "odt" ? "Pictures/" : "data:image/png;base64"
                    try check(try Data(contentsOf: output).range(of: Data(marker.utf8)) != nil, "Image missing from document")
                }
                if ["Email", "Ebooks & markup"].contains(group.name) && format == "txt" {
                    try check(try String(contentsOf: output).contains("Hello Dropform"), "Lost message or document text")
                }
                if format == "pdf" { try check(PDFDocument(url: output)?.pageCount ?? 0 > 0, "Unreadable PDF") }
            }
        }
    }
    test("EPUB → Word preserves readable text") {
        let epub = try engine.run(input: markdown, format: "epub", directory: root, quality: 80)
        let docx = try engine.run(input: epub, format: "docx", directory: root, quality: 80)
        let text = try engine.run(input: docx, format: "txt", directory: root, quality: 80)
        try check(try String(contentsOf: text).contains("Hello Dropform"), "Lost ebook text")
    }
    test("Presentations: FODP → PPTX → PDF and ODP") {
        let input = root.appendingPathComponent("slide.fodp")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2" office:mimetype="application/vnd.oasis.opendocument.presentation"><office:body><office:presentation><draw:page draw:name="Slide 1"><draw:frame presentation:class="title"><draw:text-box><text:p>Dropform test</text:p></draw:text-box></draw:frame></draw:page></office:presentation></office:body></office:document>
        """.write(to: input, atomically: true, encoding: .utf8)
        let pptx = try engine.run(input: input, format: "pptx", directory: root, quality: 80)
        for format in ["pdf", "odp", "pptx", "ppt", "png", "jpg", "webp"] { try exists(engine.run(input: pptx, format: format, directory: root, quality: 80)) }
    }
    test("Compression produces a smaller valid image") {
        let input = root.appendingPathComponent("large.jpg")
        try process(executable("magick")!, ["-size", "512x512", "plasma:fractal", "-quality", "100", input.path])
        let output = try engine.run(input: input, format: "jpg", directory: root, quality: 50, compress: true, maxDimension: 128)
        try check(try Data(contentsOf: output).count < Data(contentsOf: input).count, "Compression increased size")
        try check(NSImage(contentsOf: output) != nil, "Invalid compressed image")
    }
    test("Compression refuses larger results") {
        do {
            _ = try engine.run(input: png, format: "bmp", directory: root, quality: 100, compress: true)
            throw ConversionFailure(message: "Larger output accepted")
        } catch let error as ConversionFailure where error.message == "Larger output accepted" { throw error }
        catch { try check(error.localizedDescription.contains("already efficient"), "Unexpected compression error") }
    }
    test("Invalid output folder returns a recoverable error") {
        do { _ = try engine.run(input: png, format: "jpg", directory: png, quality: 80); throw ConversionFailure(message: "Invalid destination accepted") }
        catch let error as ConversionFailure where error.message == "Invalid destination accepted" { throw error }
        catch { }
    }
    var pdf: URL?
    test("Images to PDF") {
        let result = try FileTools.perform("Images to PDF", inputs: [png, png], destination: root)
        pdf = result.appendingPathComponent("Images.pdf")
        try check(PDFDocument(url: pdf!)?.pageCount == 2, "Page count")
    }
    if let pdf = pdf {
        test("Merge PDFs") {
            let output = try FileTools.perform("Merge PDFs", inputs: [pdf, pdf], destination: root)
            try check(PDFDocument(url: output.appendingPathComponent("Merged.pdf"))?.pageCount == 4, "Page count")
        }
        for tool in ["Split PDF pages", "PDF to images"] {
            test(tool) {
                let output = try FileTools.perform(tool, inputs: [pdf], destination: root)
                let files = try fm.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
                try check(files.count == 2, "Expected all pages")
                for file in files { try exists(file) }
            }
        }
        test("PDF compression engine") { try exists(engine.run(input: pdf, format: "pdf", directory: root, quality: 70)) }
    }
    if let pdf = pdf {
        for format in ["png", "jpg", "webp", "tiff", "bmp"] {
            test("PDF → \(format): all pages and live size") {
                var reported: Int64 = 0
                let output = try engine.run(input: pdf, format: format, directory: root, quality: 80, maxDimension: 640, onSize: { reported = $0 })
                let pages = try fm.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
                try check(pages.count == 2, "Missing PDF pages")
                for page in pages {
                    guard let image = NSImage(contentsOf: page) else { throw ConversionFailure(message: "Unreadable exported page") }
                    try check(max(image.size.width, image.size.height) <= 640, "Resize exceeded limit")
                }
                try check(reported == outputSize(output) && reported > 0, "Incorrect live/final output size")
            }
        }
        test("Scanned PDF text export fails clearly") {
            do { _ = try engine.run(input: pdf, format: "docx", directory: root, quality: 80); throw ConversionFailure(message: "Accepted image-only PDF") }
            catch { try check(error.localizedDescription.contains("no selectable text"), "Wrong scanned-PDF error") }
        }
    }
    for format in ["txt", "rtf", "docx", "doc", "odt", "html"] {
        test("PDF → \(format): readable text") {
            let source = try engine.run(input: rtf, format: "pdf", directory: root, quality: 80)
            let output = try engine.run(input: source, format: format, directory: root, quality: 80)
            try exists(output)
            let plain = format == "txt" ? output : try engine.run(input: output, format: "txt", directory: root, quality: 80)
            try check(try String(contentsOf: plain).contains("Hello Dropform"), "Lost PDF text")
        }
    }
    test("PDF text extraction") {
        let output = try engine.run(input: rtf, format: "pdf", directory: root, quality: 80)
        let folder = try FileTools.perform("Extract PDF text", inputs: [output], destination: root)
        let file = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)[0]
        try check(try String(contentsOf: file).contains("Hello Dropform"), "Missing text")
    }
    test("ZIP archive round trip") {
        let output = try FileTools.perform("Create ZIP", inputs: [png, wav], destination: root)
        let extracted = root.appendingPathComponent("extracted")
        try process("/usr/bin/ditto", ["-x","-k",output.appendingPathComponent("Archive.zip").path,extracted.path])
        try check(try Data(contentsOf: extracted.appendingPathComponent("Files/source.png")) == Data(contentsOf: png), "Archive content changed")
    }
    test("Filename collision and source preservation") {
        let original = try Data(contentsOf: png)
        let first = try engine.run(input: png, format: "png", directory: root, quality: 80)
        let second = try engine.run(input: png, format: "png", directory: root, quality: 80)
        try check(first != second && first != png, "Overwrote an existing file")
        try check(try Data(contentsOf: png) == original, "Original changed")
    }
    test("Unicode and shell characters in paths") {
        let special = root.appendingPathComponent("hello ' 世界 $(literal).png")
        try fm.copyItem(at: png, to: special)
        try exists(engine.run(input: special, format: "jpg", directory: root, quality: 80))
    }
    test("Resize and metadata removal") {
        let output = try engine.run(input: png, format: "jpg", directory: root, quality: 80, maxDimension: 32, stripMetadata: true)
        let image = NSImage(contentsOf: output)!
        try check(image.size.width == 32 && image.size.height == 24, "Incorrect dimensions")
    }
    test("Video resize") {
        try exists(engine.run(input: mov, format: "mp4", directory: root, quality: 80, maxDimension: 32, stripMetadata: true))
    }
    test("Reject invalid input without leaving temporary files") {
        let broken = root.appendingPathComponent("broken.png")
        try Data("Not an image".utf8).write(to: broken)
        do { _ = try engine.run(input: broken, format: "jpg", directory: root, quality: 80); throw ConversionFailure(message: "Invalid input accepted") }
        catch let error as ConversionFailure where error.message == "Invalid input accepted" { throw error }
        catch { }
        try check(try !fm.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".dropform-") }, "Temporary files leaked")
    }
    test("Reject unsupported format") {
        do { _ = try engine.run(input: png, format: "exe", directory: root, quality: 80); throw ConversionFailure(message: "Unsupported output accepted") }
        catch let error as ConversionFailure where error.message == "Unsupported output accepted" { throw error }
        catch { }
    }
    test("Cancel an active engine and convert again") {
        let worker = ConversionEngine()
        let input = root.appendingPathComponent("cancel-large.png")
        try process(executable("magick")!, ["-size", "2048x2048", "gradient:", input.path])
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { done.signal() }
            _ = try? worker.run(input: input, format: "avif", directory: root, quality: 100)
        }
        let deadline = Date().addingTimeInterval(3)
        while !worker.hasRunningProcess && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
        try check(worker.hasRunningProcess, "Engine did not start")
        worker.cancel()
        try check(done.wait(timeout: .now() + 10) == .success, "Cancellation did not finish")
        worker.reset()
        try exists(worker.run(input: png, format: "jpg", directory: root, quality: 80))
    }
    test("Cancellation and reset") {
        engine.cancel()
        do { _ = try engine.run(input: png, format: "jpg", directory: root, quality: 80); throw ConversionFailure(message: "Cancellation ignored") }
        catch let error as ConversionFailure where error.message == "Cancellation ignored" { throw error }
        catch { }
        engine.reset()
        try exists(engine.run(input: png, format: "jpg", directory: root, quality: 80))
    }
    print("RESULT: \(passed) passed, \(failed) failed")
    return failed == 0 ? 0 : 1
}
