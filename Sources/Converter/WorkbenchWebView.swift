import AppKit
import WebKit
import Combine

final class FileDropWebView: WKWebView {
    var receiveFiles: (([URL]) -> Void)?
    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !fileURLs(sender).isEmpty { evaluateJavaScript("window.setDragging?.(true)"); return .copy }
        return []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { fileURLs(sender).isEmpty ? [] : .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { evaluateJavaScript("window.setDragging?.(false)") }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !fileURLs(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        evaluateJavaScript("window.setDragging?.(false)")
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        receiveFiles?(urls)
        return true
    }
}
@MainActor final class WorkbenchWebView: NSView, WKScriptMessageHandler, WKNavigationDelegate {
    let store: Store
    let web: FileDropWebView
    var showBasket: (() -> Void)?
    var subscription: AnyCancellable?
    let documentURL: URL
    init(store: Store) {
        self.store = store
        documentURL = Bundle.main.resourceURL!.appendingPathComponent("Workbench/index.html")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web = FileDropWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        web.configuration.userContentController.add(self, name: "dropform")
        web.navigationDelegate = self
        web.receiveFiles = { [weak store] in store?.add($0) }
        web.registerForDraggedTypes([.fileURL])
        web.translatesAutoresizingMaskIntoConstraints = false
        addSubview(web)
        NSLayoutConstraint.activate([web.leadingAnchor.constraint(equalTo: leadingAnchor), web.trailingAnchor.constraint(equalTo: trailingAnchor), web.topAnchor.constraint(equalTo: topAnchor), web.bottomAnchor.constraint(equalTo: bottomAnchor)])
        subscription = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.publish() }
        }
        if FileManager.default.fileExists(atPath: documentURL.path) {
            web.loadFileURL(documentURL, allowingReadAccessTo: documentURL.deletingLastPathComponent())
        } else {
            let fallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ui/dist/index.html")
            web.loadFileURL(fallback, allowingReadAccessTo: fallback.deletingLastPathComponent())
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { publish() }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.isFileURL, url.lastPathComponent == "index.html", navigationAction.navigationType == .other, url.standardizedFileURL == (FileManager.default.fileExists(atPath: documentURL.path) ? documentURL : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ui/dist/index.html")).standardizedFileURL else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === web, web.url?.isFileURL == true,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "ready": publish()
        case "chooseFiles": store.chooseFiles()
        case "chooseFolder": if !store.running && !store.toolRunning { store.chooseFolder() }
        case "showBasket": showBasket?()
        case "convert": if !store.running && !store.toolRunning { store.convert() }
        case "cancel": if store.running { store.cancel() }
        case "dismissTool": if !store.toolRunning { store.toolMessage = nil }
        case "clearFinished": if !store.running { store.jobs.removeAll { $0.output != nil } }
        case "remove":
            if !store.running, let id = body["id"] as? String { store.jobs.removeAll { $0.id.uuidString == id } }
        case "reveal":
            if let id = body["id"] as? String, let output = store.jobs.first(where: { $0.id.uuidString == id })?.output { NSWorkspace.shared.activateFileViewerSelecting([output]) }
        case "format":
            if !store.running, let id = body["id"] as? String, let format = body["format"] as? String, let index = store.jobs.firstIndex(where: { $0.id.uuidString == id }), family(for: store.jobs[index].input)?.outputs.contains(format) == true { store.jobs[index].format = format }
        case "setting":
            guard let key = body["key"] as? String else { return }
            if key == "automaticBasket", let value = body["value"] as? Bool { store.automaticBasket = value; return }
            guard !store.running && !store.toolRunning else { publish(); return }
            switch key {
            case "quality": if let value = body["value"] as? Double, value.isFinite { store.quality = max(40, min(100, value)) }
            case "maxDimension": if let value = body["value"] as? Int, [0,640,1280,1920,3840].contains(value) { store.maxDimension = value }
            case "stripMetadata": if let value = body["value"] as? Bool { store.stripMetadata = value }
            case "compress": if let value = body["value"] as? Bool { store.compress = value }
            default: break
            }
        case "tool":
            let allowed = ["Merge PDFs", "Split PDF pages", "PDF to images", "Extract PDF text", "Images to PDF", "Create ZIP"]
            if !store.running && !store.toolRunning, let name = body["name"] as? String, allowed.contains(name) { store.runTool(name) }
        default: break
        }
    }
    func publish() {
        let jobs: [[String: Any]] = store.jobs.map { job in
            let group = family(for: job.input)
            let size = (try? job.input.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return ["id": job.id.uuidString, "name": job.input.lastPathComponent, "extension": job.input.pathExtension,
                    "size": ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file),
                    "format": job.format, "status": job.status, "error": job.error as Any? ?? NSNull(),
                    "output": job.output != nil, "compressionSupported": canCompress(job.input), "formats": group?.outputs ?? [], "family": group?.name ?? "Unknown"]
        }
        let state: [String: Any] = ["jobs": jobs, "running": store.running, "cancelling": store.cancelling,
            "compress": store.compress, "quality": store.quality, "maxDimension": store.maxDimension,
            "stripMetadata": store.stripMetadata, "automaticBasket": store.automaticBasket,
            "destination": store.destination.lastPathComponent, "destinationPath": store.destination.path,
            "toolMessage": store.toolMessage as Any? ?? NSNull(), "toolRunning": store.toolRunning,
            "families": families.map { ["name": $0.name, "inputs": $0.inputs, "outputs": $0.outputs, "available": executable($0.engine) != nil, "engine": $0.engine] as [String: Any] }]
        web.callAsyncJavaScript("if (window.receiveState) window.receiveState(state)", arguments: ["state": state], in: nil, in: .page) { _ in }
    }
}
