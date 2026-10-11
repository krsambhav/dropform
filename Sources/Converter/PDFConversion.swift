import AppKit
import PDFKit

extension ConversionEngine {
    func convertPDF(input: URL, format: String, directory: URL, quality: Int, maxDimension: Int,
                    onSize: @escaping (Int64) -> Void) throws -> URL {
        guard let document = PDFDocument(url: input), !document.isLocked, document.pageCount > 0 else {
            throw ConversionFailure(message: "Cannot open this PDF. Choose an unlocked, readable document.")
        }
        let fm = FileManager.default
        let staging = directory.appendingPathComponent(".dropform-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let stem = input.deletingPathExtension().lastPathComponent
        var result: URL
        if pageImageFormats.contains(format) {
            let pages = staging.appendingPathComponent(stem + " pages", isDirectory: true)
            try fm.createDirectory(at: pages, withIntermediateDirectories: true)
            var bytes: Int64 = 0
            for index in 0..<document.pageCount {
                try checkCancellation()
                guard let page = document.page(at: index) else { throw ConversionFailure(message: "Cannot read PDF page \(index + 1).") }
                let bounds = page.bounds(for: .mediaBox)
                let limit = CGFloat(maxDimension > 0 ? maxDimension : 4096)
                let scale = min(2, limit / max(bounds.width, bounds.height))
                let image = page.thumbnail(of: NSSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale)), for: .mediaBox)
                guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
                      let encoded = bitmap.representation(using: format == "jpg" ? .jpeg : format == "tiff" ? .tiff : format == "bmp" ? .bmp : .png,
                                                         properties: [.compressionFactor: Double(quality) / 100]) else {
                    throw ConversionFailure(message: "Cannot render PDF page \(index + 1).")
                }
                let pageURL = pages.appendingPathComponent(String(format: "page-%04d.%@", index + 1, format == "webp" ? "png" : format))
                try encoded.write(to: pageURL)
                if format == "webp" {
                    _ = try run(input: pageURL, format: "webp", directory: pages, quality: quality)
                    try fm.removeItem(at: pageURL)
                }
                bytes = outputSize(pages); onSize(bytes)
            }
            if document.pageCount == 1 {
                result = try fm.contentsOfDirectory(at: pages, includingPropertiesForKeys: nil)[0]
            } else { result = pages }
        } else {
            let text = NSMutableAttributedString(string: "")
            for index in 0..<document.pageCount {
                try checkCancellation()
                if index > 0 { text.append(NSAttributedString(string: "\n\n")) }
                if let page = document.page(at: index)?.attributedString { text.append(page) }
            }
            guard !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConversionFailure(message: "This PDF has no selectable text. Scanned pages need OCR; choose PNG or JPG to preserve their appearance.")
            }
            result = staging.appendingPathComponent(stem).appendingPathExtension(format)
            if format == "txt" { try text.string.write(to: result, atomically: true, encoding: .utf8) }
            else {
                let rtf = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                let source = staging.appendingPathComponent(stem).appendingPathExtension("rtf")
                try rtf.write(to: source)
                if format == "rtf" { result = source }
                else { result = try run(input: source, format: format, directory: staging, quality: quality, onSize: onSize) }
            }
        }
        try checkCancellation()
        let isFolder = (try? result.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        var target = directory.appendingPathComponent(isFolder ? stem + " " + format.uppercased() + " pages" : stem + "." + format)
        var number = 1
        while fm.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent(isFolder ? "\(stem) \(format.uppercased()) pages \(number)" : "\(stem) converted \(number).\(format)")
            number += 1
        }
        try fm.moveItem(at: result, to: target)
        onSize(outputSize(target))
        return target
    }
}

func outputSize(_ url: URL) -> Int64 {
    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        return (FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? []).reduce(0) {
            $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
    return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
}
