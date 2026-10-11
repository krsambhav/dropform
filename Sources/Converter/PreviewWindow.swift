import AppKit
import Quartz

struct PreviewArtifact {
    let folder: URL
    let output: URL
}

@MainActor final class PreviewWindow: NSObject {
    private var window: NSWindow?
    private var preview: QLPreviewView?
    private let label = NSTextField(labelWithString: "")
    private var previous: NSButton!
    private var next: NSButton!
    private var files: [URL] = []
    private var page = 0
    private(set) var jobID: UUID?

    func show(job: Job, output: URL) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSView()
            let view = QLPreviewView(frame: .zero, style: .normal)!
            view.autostarts = false
            previous = NSButton(title: "Previous page", target: self, action: #selector(back))
            next = NSButton(title: "Next page", target: self, action: #selector(forward))
            label.font = NSFont(name: "Plus Jakarta Sans", size: 12)
            let controls = NSStackView(views: [previous, label, next])
            controls.spacing = 16; controls.alignment = .centerY
            for child in [view as NSView, controls] { child.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(child) }
            NSLayoutConstraint.activate([
                controls.topAnchor.constraint(equalTo: host.topAnchor, constant: 12), controls.centerXAnchor.constraint(equalTo: host.centerXAnchor),
                view.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12), view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: host.trailingAnchor), view.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            ])
            window.contentView = host; window.center()
            self.window = window; preview = view
        }
        jobID = job.id; page = 0
        update(job: job, output: output)
        window?.makeKeyAndOrderFront(nil)
    }
    func invalidate() {
        preview?.previewItem = nil
        files = []
        label.stringValue = "Updating preview…"
        previous?.isEnabled = false; next?.isEnabled = false
    }
    func update(job: Job, output: URL) {
        guard jobID == job.id else { return }
        window?.title = "Live preview · \(job.input.lastPathComponent) · \(Int(job.quality))%"
        if (try? output.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            files = ((try? FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        } else { files = [output] }
        page = min(page, max(0, files.count - 1)); render()
    }
    func unavailable(_ message: String) { guard jobID != nil else { return }; invalidate(); label.stringValue = message }
    private func render() {
        guard !files.isEmpty else { return }
        preview?.previewItem = files[page] as NSURL
        preview?.refreshPreviewItem()
        label.stringValue = files.count > 1 ? "Page \(page + 1) of \(files.count)" : "Converted output · not saved yet"
        previous.isHidden = files.count < 2; next.isHidden = files.count < 2
        previous.isEnabled = page > 0; next.isEnabled = page + 1 < files.count
    }
    @objc private func back() { page = max(0, page - 1); render() }
    @objc private func forward() { page = min(files.count - 1, page + 1); render() }
}
