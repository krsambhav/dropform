import AppKit
import PDFKit

// Each tool writes to its own output folder so existing files cannot be replaced.
enum FileTools {
    static func perform(_ operation: String, inputs: [URL], destination: URL) throws -> URL {
        let fm = FileManager.default
        let output = destination.appendingPathComponent("Dropform \(operation) \(UUID().uuidString.prefix(6))", isDirectory: true)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        do {
            switch operation {
            case "Merge PDFs":
                let merged = PDFDocument()
                for input in inputs {
                    guard let document = PDFDocument(url: input), !document.isLocked else { throw ConversionFailure(message: "Cannot open \(input.lastPathComponent). Choose unlocked PDF files.") }
                    for index in 0..<document.pageCount { if let page = document.page(at: index) { merged.insert(page, at: merged.pageCount) } }
                }
                guard merged.pageCount > 0, merged.write(to: output.appendingPathComponent("Merged.pdf")) else { throw ConversionFailure(message: "Could not write the merged PDF.") }
            case "Split PDF pages", "PDF to images", "Extract PDF text":
                for (fileIndex, input) in inputs.enumerated() {
                    guard let document = PDFDocument(url: input), !document.isLocked else { throw ConversionFailure(message: "Cannot open \(input.lastPathComponent). Choose unlocked PDF files.") }
                    let stem = "\(fileIndex + 1)-" + input.deletingPathExtension().lastPathComponent
                    if operation == "Extract PDF text" {
                        guard let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConversionFailure(message: "No selectable text in this PDF. Scanned pages require OCR, which is not included yet.") }
                        try text.write(to: output.appendingPathComponent(stem + ".txt"), atomically: true, encoding: .utf8)
                    } else {
                        for index in 0..<document.pageCount {
                            guard let page = document.page(at: index) else { continue }
                            let name = stem + "-page-\(index + 1)"
                            if operation == "Split PDF pages" {
                                let single = PDFDocument(); single.insert(page, at: 0)
                                guard single.write(to: output.appendingPathComponent(name + ".pdf")) else { throw ConversionFailure(message: "Could not write PDF page.") }
                            } else {
                                let bounds = page.bounds(for: .mediaBox)
                                let scale = min(2.0, 4096 / max(bounds.width, bounds.height))
                                let image = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
                                guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { throw ConversionFailure(message: "Could not render PDF page.") }
                                try png.write(to: output.appendingPathComponent(name + ".png"))
                            }
                        }
                    }
                }
            case "Images to PDF":
                let document = PDFDocument()
                for input in inputs {
                    guard let image = NSImage(contentsOf: input), let page = PDFPage(image: image) else { throw ConversionFailure(message: "Cannot read image \(input.lastPathComponent).") }
                    document.insert(page, at: document.pageCount)
                }
                guard document.write(to: output.appendingPathComponent("Images.pdf")) else { throw ConversionFailure(message: "Could not write PDF.") }
            case "Create ZIP":
                // Ditto preserves paths and resource forks inside an isolated staging directory.
                let staging = output.appendingPathComponent("Files", isDirectory: true)
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                for (index, input) in inputs.enumerated() {
                    var target = staging.appendingPathComponent(input.lastPathComponent)
                    if fm.fileExists(atPath: target.path) { target = staging.appendingPathComponent("\(index + 1)-" + input.lastPathComponent) }
                    try fm.copyItem(at: input, to: target)
                }
                let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                task.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", staging.path, output.appendingPathComponent("Archive.zip").path]
                task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
                try task.run(); task.waitUntilExit()
                guard task.terminationStatus == 0 else { throw ConversionFailure(message: "Could not create ZIP archive.") }
                try fm.removeItem(at: staging)
            default: throw ConversionFailure(message: "Unknown tool.")
            }
            return output
        } catch { try? fm.removeItem(at: output); throw error }
    }
}
