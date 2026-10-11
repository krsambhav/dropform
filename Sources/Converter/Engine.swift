import Foundation

struct Family {
    let name: String
    let icon: String
    let inputs: [String]
    let outputs: [String]
    let engine: String
}
let families: [Family] = [
    Family(name: "Email", icon: "envelope", inputs: ["eml"], outputs: ["txt", "html", "pdf", "docx", "png", "jpg"], engine: "python3"),
    Family(name: "Ebooks & markup", icon: "book", inputs: ["epub", "md", "markdown", "rst"], outputs: ["docx", "odt", "rtf", "html", "txt", "epub", "md", "rst", "pdf", "png", "jpg"], engine: "pandoc"),
    Family(name: "PDF", icon: "doc.richtext", inputs: ["pdf"], outputs: ["png", "jpg", "webp", "tiff", "bmp", "docx", "doc", "odt", "txt", "rtf", "html", "pdf"], engine: "gs"),
    Family(name: "Images", icon: "photo", inputs: ["jpg","jpeg","png","heic","heif","webp","avif","tiff","tif","bmp","gif","svg","ico","psd","eps"], outputs: ["png","jpg","webp","heic","avif","tiff","bmp","gif","ico","pdf","docx","doc","odt","html"], engine: "magick"),
    Family(name: "Video", icon: "film", inputs: ["mp4","mov","mkv","avi","webm","m4v","mpeg","mpg","wmv","flv","ts"], outputs: ["mp4","mov","mkv","webm","avi","mpeg","flv","gif","png","jpg","webp","mp3","m4a","aac","wav","flac","ogg","opus","aiff"], engine: "ffmpeg"),
    Family(name: "Audio", icon: "waveform", inputs: ["mp3","m4a","aac","wav","flac","ogg","opus","aiff","wma","amr"], outputs: ["mp3","m4a","aac","wav","flac","ogg","opus","aiff"], engine: "ffmpeg"),
    Family(name: "Documents", icon: "doc.text", inputs: ["doc","docx","odt","rtf","txt","html"], outputs: ["pdf","docx","doc","odt","rtf","txt","html","md","epub","rst","png","jpg","webp","tiff","bmp"], engine: "soffice"),
    Family(name: "Spreadsheets", icon: "tablecells", inputs: ["xls","xlsx","ods","csv","tsv"], outputs: ["pdf","xlsx","xls","ods","csv","html","png","jpg","webp","tiff","bmp"], engine: "soffice"),
    Family(name: "Presentations", icon: "rectangle.on.rectangle", inputs: ["ppt","pptx","odp","fodp"], outputs: ["pdf","pptx","ppt","odp","png","jpg","webp","tiff","bmp"], engine: "soffice"),
    Family(name: "Subtitles", icon: "captions.bubble", inputs: ["srt","vtt","ass","ssa","sub"], outputs: ["srt","vtt","ass","txt","docx","pdf"], engine: "ffmpeg")
]
func executable(_ name: String) -> String? {
    if name == "soffice" {
        let headless = NSHomeDirectory() + "/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/MacOS/soffice"
        if FileManager.default.isExecutableFile(atPath: headless) { return headless }
    }
    let locations = ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/", "/Applications/LibreOffice.app/Contents/MacOS/", NSHomeDirectory() + "/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/override/"]
    return locations.map { $0 + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
}
func canonicalFormat(_ ext: String) -> String {
    ["jpeg": "jpg", "tif": "tiff", "heif": "heic", "m4v": "mp4", "ssa": "ass"][ext.lowercased()] ?? ext.lowercased()
}
func family(for url: URL) -> Family? { families.first { $0.inputs.contains(url.pathExtension.lowercased()) } }
func canCompress(_ url: URL) -> Bool {
    guard let group = family(for: url) else { return false }
    return ["Images", "Video", "Audio", "PDF"].contains(group.name) && group.outputs.contains(canonicalFormat(url.pathExtension))
}
struct ConversionFailure: LocalizedError { let message: String; var errorDescription: String? { message } }
final class ConversionEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var failedEngines: Set<String> = []
    var hasRunningProcess: Bool { lock.lock(); defer { lock.unlock() }; return process?.isRunning == true }
    func checkCancellation() throws {
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped { throw ConversionFailure(message: "Cancelled") }
    }
    func reset() { lock.lock(); cancelled = false; lock.unlock() }
    func cancel() { lock.lock(); cancelled = true; process?.terminate(); lock.unlock() }
    func run(input: URL, format: String, directory: URL, quality: Int, compress: Bool = false, maxDimension: Int = 0, stripMetadata: Bool = false, usingPandoc: Bool = false, onSize: @escaping (Int64) -> Void = { _ in }) throws -> URL {
        try checkCancellation()
        if input.pathExtension.lowercased() == "pdf", ["png", "jpg", "webp", "tiff", "bmp", "docx", "doc", "odt", "txt", "rtf", "html"].contains(format) {
            return try convertPDF(input: input, format: format, directory: directory, quality: quality, maxDimension: maxDimension, onSize: onSize)
        }
        if !usingPandoc, let group = family(for: input), group.outputs.contains(format),
           (group.name == "Email" && format != "txt") ||
           (group.name == "Video" && format == "webp") ||
           (group.engine == "soffice" && pageImageFormats.contains(format)) ||
           (group.name == "Documents" && ["md", "epub", "rst"].contains(format)) ||
           (group.engine == "pandoc" && (["pdf"].contains(format) || pageImageFormats.contains(format))) ||
           (group.name == "Images" && ["docx", "doc", "odt", "html"].contains(format)) ||
           (group.name == "Subtitles" && ["txt", "docx", "pdf"].contains(format)) {
            return try runChained(input: input, format: format, directory: directory, quality: quality, maxDimension: maxDimension, onSize: onSize)
        }
        guard let group = family(for: input), group.outputs.contains(format), let tool = executable(usingPandoc ? "pandoc" : group.engine) else { throw ConversionFailure(message: "No installed engine supports this conversion.") }
        let engineName = usingPandoc ? "pandoc" : group.engine
        lock.lock(); let engineFailed = failedEngines.contains(tool); lock.unlock()
        if engineFailed { throw ConversionFailure(message: "This conversion engine stopped unexpectedly. Further jobs are paused to prevent repeated crashes. Restart Dropform after repairing the engine.") }
        let fm = FileManager.default
        let staging = directory.appendingPathComponent(".dropform-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var output = staging.appendingPathComponent(input.deletingPathExtension().lastPathComponent).appendingPathExtension(format)
        var args: [String]
        if engineName == "python3" {
            args = ["-c", EmailExtraction.script, input.path, output.path]
        } else if engineName == "magick" {
            args = [input.path, "-auto-orient"]
            if maxDimension > 0 { args += ["-resize", "\(maxDimension)x\(maxDimension)>"] }
            if stripMetadata { args += ["-strip"] }
            args += ["-quality", String(quality), output.path]
        } else if engineName == "gs" {
            args = ["-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.6", "-dPDFSETTINGS=" + (quality >= 90 ? "/prepress" : quality >= 70 ? "/ebook" : "/screen"), "-dNOPAUSE", "-dBATCH", "-dSAFER", "-sOutputFile=" + output.path, input.path]
        } else if engineName == "pandoc" {
            let writer = format == "txt" ? "plain" : format == "md" ? "gfm" : format
            let reader = ["md", "markdown"].contains(input.pathExtension.lowercased()) ? "gfm" : input.pathExtension.lowercased()
            args = ["--sandbox", "--from", reader, "--to", writer, "--standalone", input.path, "--output", output.path]
        } else if engineName == "soffice" {
            args = ["-env:UserInstallation=" + staging.appendingPathComponent("profile").absoluteString, "--headless"]
            if input.pathExtension.lowercased() == "html" { args += ["--infilter=HTML (StarWriter)"] }
            let writerFilters = ["docx": "Office Open XML Text", "doc": "MS Word 97", "odt": "writer8"]
            let exportFormat = group.name == "Documents" ? writerFilters[format].map { format + ":" + $0 } ?? format : format
            args += ["--convert-to", exportFormat, "--outdir", staging.path, input.path]
        } else {
            args = ["-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-i", input.path]
            if ["mp3","m4a","aac","wav","flac","ogg","opus","aiff"].contains(format) { args += ["-vn"] }
            if ["mp4","mov","mkv"].contains(format) { args += ["-c:v", "libx264", "-crf", quality >= 90 ? "18" : quality >= 75 ? "23" : "28", "-preset", "fast", "-pix_fmt", "yuv420p"] }
            if maxDimension > 0 && group.name == "Video" && !["mp3","m4a","aac","wav","flac","ogg","opus","aiff"].contains(format) {
                args += ["-vf", "scale=w='min(\(maxDimension),iw)':h='min(\(maxDimension),ih)':force_original_aspect_ratio=decrease:force_divisible_by=2"]
            }
            if ["mp3", "m4a", "ogg", "opus"].contains(format) { args += ["-b:a", quality >= 90 ? "256k" : quality >= 70 ? "160k" : "96k"] }
            if stripMetadata { args += ["-map_metadata", "-1"] }
            if group.name == "Video" && ["png", "jpg", "webp"].contains(format) { args += ["-frames:v", "1", "-update", "1"] }
            if format == "mp4" { args += ["-movflags", "+faststart"] }
            args += [output.path]
        }
        let task = Process(); task.executableURL = URL(fileURLWithPath: tool); task.arguments = args
        let log = staging.appendingPathComponent("engine.log")
        fm.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
        task.standardOutput = handle; task.standardError = handle
        lock.lock()
        if cancelled { lock.unlock(); throw ConversionFailure(message: "Cancelled") }
        process = task
        do { try task.run() } catch { process = nil; lock.unlock(); throw error }
        lock.unlock()
        let sizeMonitor = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "dropform.output-size"))
        let trackedOutput = output
        sizeMonitor.schedule(deadline: .now(), repeating: .milliseconds(250))
        sizeMonitor.setEventHandler {
            if let bytes = (try? fm.attributesOfItem(atPath: trackedOutput.path)[.size]) as? NSNumber {
                onSize(bytes.int64Value)
            }
        }
        sizeMonitor.resume()
        defer { sizeMonitor.cancel() }
        task.waitUntilExit()
        lock.lock()
        process = nil
        let wasCancelled = cancelled
        if task.terminationReason == .uncaughtSignal && !wasCancelled { failedEngines.insert(tool) }
        lock.unlock()
        if wasCancelled { throw ConversionFailure(message: "Cancelled") }
        if engineName == "magick" {
            let generated = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).filter { $0.pathExtension == format }
            if generated.count > 1 { throw ConversionFailure(message: "This file produces multiple pages. Choose a format that preserves them, such as PDF or TIFF.") }
            if !fm.fileExists(atPath: output.path), let first = generated.first { output = first }
        }
        guard task.terminationStatus == 0, fm.fileExists(atPath: output.path) else {
            if task.terminationReason == .uncaughtSignal { throw ConversionFailure(message: "The \(group.engine) engine stopped unexpectedly. Further jobs using it have been paused. Your original file is unchanged.") }
            let detail = (try? String(contentsOf: log)) ?? ""
            if detail.contains("Output file does not contain any stream") { throw ConversionFailure(message: "This file has no compatible audio track. Choose a video output instead.") }
            throw ConversionFailure(message: detail.isEmpty ? "The engine could not convert this file." : String(detail.suffix(1800)))
        }
        if compress {
            let originalSize = (try fm.attributesOfItem(atPath: input.path)[.size] as? NSNumber)?.intValue ?? 0
            let resultSize = (try fm.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue ?? 0
            if resultSize >= originalSize { throw ConversionFailure(message: "This file is already efficient at these settings. Try lower quality or a smaller size. No larger copy was saved.") }
        }
        let stem = input.deletingPathExtension().lastPathComponent
        var destination = directory.appendingPathComponent(stem).appendingPathExtension(format)
        var number = 1
        while fm.fileExists(atPath: destination.path) { destination = directory.appendingPathComponent("\(stem) converted \(number)").appendingPathExtension(format); number += 1 }
        try fm.moveItem(at: output, to: destination)
        return destination
    }
}
