import Foundation

struct Family {
    let name: String
    let icon: String
    let inputs: [String]
    let outputs: [String]
    let engine: String
}
let families: [Family] = [
    Family(name: "PDF", icon: "doc.richtext", inputs: ["pdf"], outputs: ["pdf"], engine: "gs"),
    Family(name: "Images", icon: "photo", inputs: ["jpg","jpeg","png","heic","heif","webp","avif","tiff","tif","bmp","gif","svg","ico","psd","eps"], outputs: ["png","jpg","webp","heic","avif","tiff","bmp","gif","ico","pdf"], engine: "magick"),
    Family(name: "Video", icon: "film", inputs: ["mp4","mov","mkv","avi","webm","m4v","mpeg","mpg","wmv","flv","ts"], outputs: ["mp4","mov","mkv","webm","gif","mp3","m4a","wav","flac"], engine: "ffmpeg"),
    Family(name: "Audio", icon: "waveform", inputs: ["mp3","m4a","aac","wav","flac","ogg","opus","aiff","wma","amr"], outputs: ["mp3","m4a","wav","flac","ogg","opus","aiff"], engine: "ffmpeg"),
    Family(name: "Documents", icon: "doc.text", inputs: ["doc","docx","odt","rtf","txt","html"], outputs: ["pdf","docx","odt","rtf","txt","html"], engine: "soffice"),
    Family(name: "Spreadsheets", icon: "tablecells", inputs: ["xls","xlsx","ods","csv","tsv"], outputs: ["pdf","xlsx","ods","csv"], engine: "soffice"),
    Family(name: "Presentations", icon: "rectangle.on.rectangle", inputs: ["ppt","pptx","odp","fodp"], outputs: ["pdf","pptx","odp"], engine: "soffice"),
    Family(name: "Subtitles", icon: "captions.bubble", inputs: ["srt","vtt","ass","ssa","sub"], outputs: ["srt","vtt","ass"], engine: "ffmpeg")
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
    func reset() { lock.lock(); cancelled = false; lock.unlock() }
    func cancel() { lock.lock(); cancelled = true; process?.terminate(); lock.unlock() }
    func run(input: URL, format: String, directory: URL, quality: Int, compress: Bool = false, maxDimension: Int = 0, stripMetadata: Bool = false, onSize: @escaping (Int64) -> Void = { _ in }) throws -> URL {
        guard let group = family(for: input), group.outputs.contains(format), let tool = executable(group.engine) else { throw ConversionFailure(message: "No installed engine supports this conversion.") }
        lock.lock(); let engineFailed = failedEngines.contains(tool); lock.unlock()
        if engineFailed { throw ConversionFailure(message: "This conversion engine stopped unexpectedly. Further jobs are paused to prevent repeated crashes. Restart Dropform after repairing the engine.") }
        let fm = FileManager.default
        let staging = directory.appendingPathComponent(".dropform-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var output = staging.appendingPathComponent(input.deletingPathExtension().lastPathComponent).appendingPathExtension(format)
        var args: [String]
        if group.engine == "magick" {
            args = [input.path, "-auto-orient"]
            if maxDimension > 0 { args += ["-resize", "\(maxDimension)x\(maxDimension)>"] }
            if stripMetadata { args += ["-strip"] }
            args += ["-quality", String(quality), output.path]
        } else if group.engine == "gs" {
            args = ["-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.6", "-dPDFSETTINGS=" + (quality >= 90 ? "/prepress" : quality >= 70 ? "/ebook" : "/screen"), "-dNOPAUSE", "-dBATCH", "-dSAFER", "-sOutputFile=" + output.path, input.path]
        } else if group.engine == "soffice" {
            args = ["-env:UserInstallation=" + staging.appendingPathComponent("profile").absoluteString, "--headless", "--convert-to", format, "--outdir", staging.path, input.path]
        } else {
            args = ["-nostdin", "-hide_banner", "-loglevel", "error", "-n", "-i", input.path]
            if ["mp3","m4a","wav","flac","ogg","opus","aiff"].contains(format) { args += ["-vn"] }
            if ["mp4","mov","mkv"].contains(format) { args += ["-c:v", "libx264", "-crf", quality >= 90 ? "18" : quality >= 75 ? "23" : "28", "-preset", "fast", "-pix_fmt", "yuv420p"] }
            if maxDimension > 0 && group.name == "Video" && !["mp3","m4a","wav","flac","ogg","opus","aiff"].contains(format) {
                args += ["-vf", "scale=w='min(\(maxDimension),iw)':h='min(\(maxDimension),ih)':force_original_aspect_ratio=decrease:force_divisible_by=2"]
            }
            if ["mp3", "m4a", "ogg", "opus"].contains(format) { args += ["-b:a", quality >= 90 ? "256k" : quality >= 70 ? "160k" : "96k"] }
            if stripMetadata { args += ["-map_metadata", "-1"] }
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
        if group.engine == "magick" {
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
