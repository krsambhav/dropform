import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoreText

struct Job: Identifiable {
    let id = UUID()
    let input: URL
    var quality = 90.0
    var outputBytes: Int64?
    var previewBytes: Int64?
    var previewState = ""
    var format: String
    var status = "Ready"
    var output: URL?
    var error: String?
}
@MainActor final class Store: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var running = false
    @Published var destination = UserDefaults.standard.url(forKey: "outputFolder") ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] {
        didSet { UserDefaults.standard.set(destination, forKey: "outputFolder") }
    }
    @Published var automaticBasket = UserDefaults.standard.object(forKey: "automaticBasket") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automaticBasket, forKey: "automaticBasket") }
    }
    @Published var openAtLogin = true
    @Published var loginNeedsApproval = false
    @Published var loginError: String?
    @Published var showFormats = false
    @Published var compress = false
    @Published var maxDimension = 0
    @Published var stripMetadata = false
    @Published var cancelling = false
    @Published var toolMessage: String?
    @Published var toolRunning = false
    var previewTask: Task<Void, Never>?
    var previewEngine: ConversionEngine?
    var previewRevision = 0
    var previewArtifacts: [UUID: PreviewArtifact] = [:]
    let previewWindow = PreviewWindow()
    let engine = ConversionEngine()
    func runTool(_ operation: String) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.canChooseDirectories = operation == "Create ZIP"
        if operation.contains("PDF") && operation != "Images to PDF" { panel.allowedContentTypes = [.pdf] }
        if operation == "Images to PDF" { panel.allowedContentTypes = [.image] }
        panel.message = operation == "Merge PDFs" || operation == "Images to PDF" ? "Files are combined in filename order." : operation
        guard panel.runModal() == .OK else { return }
        let inputs = panel.urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let folder = destination
        stopPreviews()
        toolRunning = true; toolMessage = "\(operation)…"
        Task {
            let result = await Task.detached { () -> Result<URL, Error> in Result { try FileTools.perform(operation, inputs: inputs, destination: folder) } }.value
            toolRunning = false
            switch result {
            case .success(let output): toolMessage = "\(operation) complete."; NSWorkspace.shared.activateFileViewerSelecting([output])
            case .failure(let error): toolMessage = error.localizedDescription
            }
        }
    }
    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            guard !jobs.contains(where: { $0.input == url }) else { continue }
            let group = family(for: url)
            let formats = availableFormats(for: url)
            let available = !formats.isEmpty
            jobs.append(Job(input: url, format: formats.first ?? "", status: available ? "Ready" : "Unavailable", error: group == nil ? "This file type is not supported yet." : available ? nil : "Install \(group!.engine) to convert this file."))
        }
        schedulePreviews()
    }
    func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK { add(panel.urls) }
    }
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true; panel.allowedContentTypes = []; panel.directoryURL = destination; panel.prompt = "Choose folder"
        if panel.runModal() == .OK, let url = panel.url { destination = url }
    }
    func convert() {
        guard !running else { return }; stopPreviews(); running = true; engine.reset()
        Task {
            await previewTask?.value
            for id in jobs.filter({ $0.output == nil && $0.status != "Unavailable" && (!compress || canCompress($0.input)) }).map(\.id) {
                guard !cancelling, let index = jobs.firstIndex(where: { $0.id == id }) else { break }
                jobs[index].status = "Converting"; jobs[index].error = nil; jobs[index].outputBytes = nil; jobs[index].previewBytes = nil
                let job = jobs[index], folder = destination, value = Int(job.quality), worker = engine
                let shrink = compress, dimension = maxDimension, strip = stripMetadata
                let format = shrink ? canonicalFormat(job.input.pathExtension) : job.format
                let result = await Task.detached { () -> Result<URL, Error> in
                    Result { try worker.run(input: job.input, format: format, directory: folder, quality: value, compress: shrink, maxDimension: dimension, stripMetadata: strip, onSize: { bytes in
                        Task { @MainActor in
                            if let current = self.jobs.firstIndex(where: { $0.id == id }), self.jobs[current].status == "Converting" {
                                self.jobs[current].outputBytes = bytes
                            }
                        }
                    }) }
                }.value
                guard let current = jobs.firstIndex(where: { $0.id == id }) else { continue }
                switch result {
                case .success(let url):
                    jobs[current].output = url
                    let original = (try? job.input.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let converted = outputSize(url)
                    jobs[current].outputBytes = Int64(converted)
                    let size = ByteCountFormatter.string(fromByteCount: Int64(converted), countStyle: .file)
                    let saving = original > 0 && converted < original ? " · \(Int((1 - Double(converted) / Double(original)) * 100))% smaller" : ""
                    jobs[current].status = "Done · \(size)\(saving)"
                case .failure(let error): jobs[current].outputBytes = nil; jobs[current].status = cancelling ? "Cancelled" : "Failed"; jobs[current].error = error.localizedDescription
                }
            }
            running = false; cancelling = false
        }
    }
    func cancel() { cancelling = true; engine.cancel() }
}
let jade = Color(red: 0.19, green: 0.48, blue: 0.39)
struct DropArea: NSViewRepresentable {
    var onDrop: ([URL]) -> Void
    func makeNSView(context: Context) -> DropReceiver { let view = DropReceiver(); view.onDrop = onDrop; return view }
    func updateNSView(_ view: DropReceiver, context: Context) { view.onDrop = onDrop }
}
final class DropReceiver: NSView {
    var onDrop: (([URL]) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        onDrop?(urls); return true
    }
}
struct BasketView: View {
    let receive: ([URL]) -> Void
    let dismiss: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 34, weight: .light)).foregroundStyle(jade)
            Text("Drop to transform").font(.custom("Plus Jakarta Sans", size: 17).weight(.semibold))
            Text("Your files. A new form.").font(.custom("Plus Jakarta Sans", size: 12)).foregroundStyle(.secondary)
        }.frame(width: 250, height: 156).background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(jade.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
            .overlay(DropArea(onDrop: receive))
            .overlay(alignment: .topTrailing) { Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).padding(10) }.buttonStyle(.plain).foregroundStyle(.secondary).help("Hide basket") }.padding(8)
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var window: NSWindow!
    var basket: NSPanel!
    var item: NSStatusItem!
    var timer: Timer?
    var lastDrag = NSPasteboard(name: .drag).changeCount
    var previousDown = false
    var basketIsAutomatic = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let font = Bundle.main.resourceURL?.appendingPathComponent("Fonts/PlusJakartaSans.ttf") {
            CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
        }
        store.initializeLoginItem()
        let mainMenu = NSMenu()
        let appMenu = NSMenu(); let appRoot = NSMenuItem(); appRoot.submenu = appMenu; mainMenu.addItem(appRoot)
        appMenu.addItem(withTitle: "Quit Dropform", action: #selector(quit), keyEquivalent: "q").target = self
        let editMenu = NSMenu(title: "Edit"); let editRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editRoot.submenu = editMenu; mainMenu.addItem(editRoot)
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = mainMenu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Dropform"; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        let workbench = WorkbenchWebView(store: store)
        workbench.showBasket = { [weak self] in self?.showBasket() }
        window.contentView = workbench
        window.minSize = NSSize(width: 820, height: 660)
        window.center()
        basket = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 266, height: 172), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        basket.level = .floating; basket.isOpaque = false; basket.backgroundColor = .clear; basket.hasShadow = true; basket.hidesOnDeactivate = false
        basket.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        basket.contentView = NSHostingView(rootView: BasketView(receive: { [weak self] urls in self?.store.add(urls); self?.basket.orderOut(nil); self?.basketIsAutomatic = false; self?.show() }, dismiss: { [weak self] in self?.basket.orderOut(nil); self?.basketIsAutomatic = false }))
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Dropform")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Dropform", action: #selector(show), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Show drop basket", action: #selector(showBasket), keyEquivalent: "b").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Dropform", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in Task { @MainActor in self?.pollDrag() } }
        timer?.tolerance = 0.03
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        show()
    }
    func applicationDidBecomeActive(_ notification: Notification) { store.refreshLoginItem() }
    @objc func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc func showBasket() { presentBasket(automatically: false) }
    func presentBasket(automatically: Bool) {
        basketIsAutomatic = automatically
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.visibleFrame { basket.setFrameOrigin(NSPoint(x: frame.maxX - 290, y: frame.midY - 86)) }
        basket.orderFrontRegardless()
    }
    func pollDrag() {
        let pasteboard = NSPasteboard(name: .drag)
        let down = NSEvent.pressedMouseButtons & 1 != 0
        if store.automaticBasket && down && pasteboard.changeCount != lastDrag {
            lastDrag = pasteboard.changeCount
            if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { presentBasket(automatically: true) }
        }
        if previousDown && !down && basketIsAutomatic { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in if self?.basketIsAutomatic == true { self?.basket.orderOut(nil); self?.basketIsAutomatic = false } } }
        previousDown = down
    }
    @objc func quit() { store.stopPreviews(); store.engine.cancel(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { store.stopPreviews(); store.engine.cancel(); timer?.invalidate() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { store.add(filenames.map { URL(fileURLWithPath: $0) }); show() }
}
