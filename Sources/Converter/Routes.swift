import Foundation

let pageImageFormats = ["png", "jpg", "webp", "tiff", "bmp"]

func routeEngines(input: URL, format: String) -> [String] {
    guard let group = family(for: input) else { return [] }
    if group.name == "Email" { return format == "txt" ? ["python3"] : ["python3", "soffice"] }
    if group.name == "Video", format == "webp" { return ["ffmpeg", "magick"] }
    if group.engine == "pandoc" {
        return (["pdf"].contains(format) || pageImageFormats.contains(format)) ? ["pandoc", "soffice"] : ["pandoc"]
    }
    if group.name == "Documents", ["md", "epub", "rst"].contains(format) { return ["soffice", "pandoc"] }
    if group.name == "PDF" {
        if format == "pdf" { return ["gs"] }
        if format == "webp" { return ["magick"] }
        if ["docx", "doc", "odt", "html"].contains(format) { return ["soffice"] }
        return []
    }
    if group.name == "Images", ["docx", "doc", "odt", "html"].contains(format) {
        return format == "html" ? ["magick"] : ["magick", "soffice"]
    }
    if group.name == "Subtitles", ["txt", "docx", "pdf"].contains(format) {
        return format == "txt" ? [] : ["soffice"]
    }
    if group.engine == "soffice", format == "webp" { return ["soffice", "magick"] }
    return [group.engine]
}
func availableFormats(for input: URL) -> [String] {
    (family(for: input)?.outputs ?? []).filter { format in routeEngines(input: input, format: format).allSatisfy { executable($0) != nil } }
}

extension ConversionEngine {
    func runChained(input: URL, format: String, directory: URL, quality: Int, maxDimension: Int,
                    onSize: @escaping (Int64) -> Void) throws -> URL {
        let fm = FileManager.default
        let work = directory.appendingPathComponent(".dropform-route-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let stem = input.deletingPathExtension().lastPathComponent
        let group = family(for: input)!
        if group.name == "Email" {
            let text = try run(input: input, format: "txt", directory: work, quality: quality)
            return try run(input: text, format: format, directory: directory, quality: quality, maxDimension: maxDimension, onSize: onSize)
        }
        if group.name == "Video", format == "webp" {
            let frame = try run(input: input, format: "png", directory: work, quality: quality, maxDimension: maxDimension)
            return try run(input: frame, format: "webp", directory: directory, quality: quality, onSize: onSize)
        }
        if group.engine == "pandoc" {
            let docx = try run(input: input, format: "docx", directory: work, quality: quality)
            return try run(input: docx, format: format, directory: directory, quality: quality, maxDimension: maxDimension, onSize: onSize)
        }
        if group.name == "Documents", ["md", "epub", "rst"].contains(format) {
            let docx = input.pathExtension.lowercased() == "docx" ? input : try run(input: input, format: "docx", directory: work, quality: quality)
            return try run(input: docx, format: format, directory: directory, quality: quality, usingPandoc: true, onSize: onSize)
        }
        if group.engine == "soffice", pageImageFormats.contains(format) {
            let pdf = try run(input: input, format: "pdf", directory: work, quality: quality)
            return try run(input: pdf, format: format, directory: directory, quality: quality, maxDimension: maxDimension, onSize: onSize)
        }
        var source: URL
        if group.name == "Images" {
            let png = try run(input: input, format: "png", directory: work, quality: quality, maxDimension: maxDimension)
            let data = try Data(contentsOf: png).base64EncodedString()
            // A self-contained HTML intermediate keeps images embedded and stays offline.
            source = work.appendingPathComponent(stem).appendingPathExtension("html")
            try "<!doctype html><html><head><meta charset=\"utf-8\"></head><body><img alt=\"\" style=\"max-width:100%\" src=\"data:image/png;base64,\(data)\"></body></html>".write(to: source, atomically: true, encoding: .utf8)
        } else {
            source = work.appendingPathComponent(stem).appendingPathExtension("txt")
            // Retain cues and timings instead of silently discarding subtitle information.
            let content = try String(contentsOf: input, encoding: .utf8)
            try content.write(to: source, atomically: true, encoding: .utf8)
        }
        try checkCancellation()
        if source.pathExtension == format {
            var target = directory.appendingPathComponent(stem).appendingPathExtension(format)
            var n = 1
            while fm.fileExists(atPath: target.path) { target = directory.appendingPathComponent("\(stem) converted \(n).\(format)"); n += 1 }
            try fm.moveItem(at: source, to: target)
            onSize(outputSize(target)); return target
        }
        return try run(input: source, format: format, directory: directory, quality: quality, onSize: onSize)
    }
}
