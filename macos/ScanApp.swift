import AppKit
import UniformTypeIdentifiers

final class ScanApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let preset = NSPopUpButton()
    private let resolution = NSPopUpButton()
    private let mode = NSPopUpButton()
    private let format = NSPopUpButton()
    private let searchable = NSButton(checkboxWithTitle: "Make PDFs searchable with OCR", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "Ready to scan")
    private let pageCount = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let scanButton = NSButton(title: "Scan…", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel Scan", target: nil, action: nil)
    private let addPageButton = NSButton(title: "Add Page & Scan Next", target: nil, action: nil)
    private let finishPDFButton = NSButton(title: "Finish & Save PDF", target: nil, action: nil)
    private let savePNGButton = NSButton(title: "Save PNG", target: nil, action: nil)
    private let openButton = NSButton(title: "Open Scan", target: nil, action: nil)
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private let cropButton = NSButton(title: "Crop Selection", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset Edits", target: nil, action: nil)
    private let rotateLeftButton = NSButton(title: "Rotate Left", target: nil, action: nil)
    private let rotateRightButton = NSButton(title: "Rotate Right", target: nil, action: nil)
    private let deskewButton = NSButton(title: "Auto Deskew", target: nil, action: nil)
    private let preview = CropPreviewView()

    private var process: Process?
    private var errorPipe: Pipe?
    private var diagnostics = ""
    private var lastFile: URL?
    private var outputURL: URL?
    private var workspace: URL?
    private var pages: [URL] = []
    private var currentImage: CGImage?
    private var originalImage: CGImage?
    private var processing = false
    private var quitting = false

    private var isPDF: Bool { format.indexOfSelectedItem == 0 }
    private var selectedDPI: Int { Int(resolution.titleOfSelectedItem?.split(separator: " ").first ?? "300") ?? 300 }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let root = NSMenuItem()
        menu.addItem(root)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit HP M1005 Scan", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu
        NSApp.mainMenu = menu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "HP M1005 Scan"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 650, height: 690)
        window.center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -18)
        ])

        let title = NSTextField(labelWithString: "HP LaserJet M1005")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        stack.addArrangedSubview(title)
        let instructions = NSTextField(wrappingLabelWithString: "Place a page face-down on the scanner glass and close the lid. Scan each page, preview and edit it, then save as PNG or a multi-page PDF.")
        instructions.textColor = .secondaryLabelColor
        instructions.preferredMaxLayoutWidth = 690
        stack.addArrangedSubview(instructions)

        preset.addItems(withTitles: ["Document", "Photo", "Grayscale"])
        resolution.addItems(withTitles: ["75 dpi", "100 dpi", "150 dpi", "200 dpi", "300 dpi", "600 dpi"])
        mode.addItems(withTitles: ["Grayscale", "Color"])
        format.addItems(withTitles: ["PDF", "PNG"])
        preset.target = self
        preset.action = #selector(applyPreset)
        format.target = self
        format.action = #selector(formatChanged)
        searchable.state = .on
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Preset"), preset],
            [NSTextField(labelWithString: "Resolution"), resolution],
            [NSTextField(labelWithString: "Color mode"), mode],
            [NSTextField(labelWithString: "Save as"), format]
        ])
        grid.rowSpacing = 7
        grid.columnSpacing = 24
        grid.column(at: 0).width = 100
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading
        stack.addArrangedSubview(grid)
        stack.addArrangedSubview(searchable)

        let progressRow = NSStackView()
        progressRow.orientation = .horizontal
        progressRow.spacing = 10
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 100
        progress.isDisplayedWhenStopped = false
        progress.widthAnchor.constraint(equalToConstant: 180).isActive = true
        status.font = .systemFont(ofSize: 13)
        status.preferredMaxLayoutWidth = 490
        progressRow.addArrangedSubview(progress)
        progressRow.addArrangedSubview(status)
        stack.addArrangedSubview(progressRow)

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 8
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = NSColor.separatorColor.cgColor
        preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        preview.heightAnchor.constraint(lessThanOrEqualToConstant: 390).isActive = true
        preview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        preview.onSelectionChanged = { [weak self] rect in self?.cropButton.isEnabled = !rect.isEmpty && self?.currentImage != nil }
        stack.addArrangedSubview(preview)

        let editRow = NSStackView()
        editRow.spacing = 8
        for button in [cropButton, resetButton, rotateLeftButton, rotateRightButton, deskewButton] {
            button.target = self
            button.bezelStyle = .rounded
            editRow.addArrangedSubview(button)
        }
        cropButton.action = #selector(cropSelection)
        resetButton.action = #selector(resetEdits)
        rotateLeftButton.action = #selector(rotateLeft)
        rotateRightButton.action = #selector(rotateRight)
        deskewButton.action = #selector(autoDeskew)
        stack.addArrangedSubview(editRow)

        let actions = NSStackView()
        actions.spacing = 8
        for button in [scanButton, cancelButton, addPageButton, finishPDFButton, savePNGButton] {
            button.target = self
            button.bezelStyle = .rounded
            actions.addArrangedSubview(button)
        }
        scanButton.action = #selector(scan)
        scanButton.keyEquivalent = "\r"
        cancelButton.action = #selector(cancel)
        addPageButton.action = #selector(addPageAndContinue)
        finishPDFButton.action = #selector(finishPDF)
        savePNGButton.action = #selector(savePNG)
        stack.addArrangedSubview(actions)

        pageCount.textColor = .secondaryLabelColor
        stack.addArrangedSubview(pageCount)
        let results = NSStackView()
        results.spacing = 8
        for button in [openButton, revealButton] {
            button.target = self
            button.bezelStyle = .rounded
            results.addArrangedSubview(button)
        }
        openButton.action = #selector(openScan)
        revealButton.action = #selector(revealScan)
        stack.addArrangedSubview(results)

        applyPreset()
        updateControls()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @objc private func applyPreset() {
        switch preset.titleOfSelectedItem {
        case "Photo":
            resolution.selectItem(withTitle: "600 dpi")
            mode.selectItem(withTitle: "Color")
            format.selectItem(withTitle: "PNG")
            searchable.state = .off
        case "Grayscale":
            resolution.selectItem(withTitle: "300 dpi")
            mode.selectItem(withTitle: "Grayscale")
            format.selectItem(withTitle: "PDF")
            searchable.state = .on
        default:
            resolution.selectItem(withTitle: "300 dpi")
            mode.selectItem(withTitle: "Grayscale")
            format.selectItem(withTitle: "PDF")
            searchable.state = .on
        }
        updateControls()
    }

    @objc private func formatChanged() { updateControls() }

    private func updateControls() {
        let busy = process != nil || processing
        preset.isEnabled = !busy && outputURL == nil
        resolution.isEnabled = !busy && outputURL == nil
        mode.isEnabled = !busy && outputURL == nil
        format.isEnabled = !busy && outputURL == nil
        searchable.isEnabled = !busy && outputURL == nil && isPDF
        let hasPreview = currentImage != nil
        scanButton.isEnabled = !busy && !hasPreview
        scanButton.title = pages.isEmpty ? "Scan…" : "Scan Next Page…"
        cancelButton.isEnabled = process?.isRunning == true
        addPageButton.isHidden = !isPDF
        addPageButton.isEnabled = !busy && isPDF && hasPreview
        finishPDFButton.isHidden = !isPDF
        finishPDFButton.isEnabled = !busy && isPDF && (hasPreview || !pages.isEmpty)
        savePNGButton.isHidden = isPDF
        savePNGButton.isEnabled = !busy && !isPDF && hasPreview
        for button in [cropButton, resetButton, rotateLeftButton, rotateRightButton, deskewButton] {
            button.isEnabled = !busy && hasPreview
        }
        cropButton.isEnabled = !busy && hasPreview && !preview.selection.isEmpty
        openButton.isEnabled = lastFile != nil
        revealButton.isEnabled = lastFile != nil
        pageCount.stringValue = pages.isEmpty ? "" : "\(pages.count) page\(pages.count == 1 ? "" : "s") added to this PDF."
    }

    @objc private func scan() {
        guard process == nil, !processing, currentImage == nil else { return }
        if outputURL != nil { beginScanPage(); return }
        let panel = NSSavePanel()
        let type: UTType = isPDF ? .pdf : .png
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        panel.nameFieldStringValue = "Scan \(formatter.string(from: Date())).\(isPDF ? "pdf" : "png")"
        panel.prompt = "Choose Destination"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let destination = panel.url else { return }
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                self.showError("That file already exists. Choose a new filename.", details: destination.path)
                return
            }
            do {
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("m1005-scan-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                self.outputURL = destination
                self.workspace = work
                self.pages = []
                self.beginScanPage()
            } catch {
                self.showError("Could not prepare a temporary scan folder.", details: error.localizedDescription)
            }
        }
    }

    private func beginScanPage() {
        guard let workspace else { return }
        let destination = workspace.appendingPathComponent(String(format: "capture-%03d.png", pages.count + 1))
        guard let executable = Bundle.main.url(forResource: "m1005", withExtension: nil) else {
            showError("The scanner component is missing. Reinstall HP M1005 Scan.", details: "Bundle resource m1005 was not found.")
            return
        }
        let task = Process()
        task.executableURL = executable
        task.arguments = ["scan", destination.path, String(selectedDPI), mode.indexOfSelectedItem == 0 ? "gray" : "color", "0"]
        let pipe = Pipe()
        errorPipe = pipe
        diagnostics = ""
        progress.doubleValue = 0
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        status.stringValue = pages.isEmpty ? "Connecting to scanner…" : "Connecting for page \(pages.count + 1)…"
        task.standardError = pipe
        task.standardOutput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; return }
            guard let text = String(data: bytes, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.diagnostics += text
                if self.diagnostics.count > 24000 { self.diagnostics = String(self.diagnostics.suffix(24000)) }
                self.updateScanProgress(from: text)
            }
        }
        task.terminationHandler = { [weak self] completed in
            DispatchQueue.main.async {
                guard let self else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                let tail = pipe.fileHandleForReading.readDataToEndOfFile()
                if let text = String(data: tail, encoding: .utf8) { self.diagnostics += text }
                self.errorPipe = nil
                self.process = nil
                self.progress.stopAnimation(nil)
                self.progress.isIndeterminate = false
                if completed.terminationStatus == 0 {
                    do {
                        let image = try ScanDocument.loadImage(destination)
                        self.originalImage = image
                        self.currentImage = image
                        self.preview.image = image
                        self.status.stringValue = "Preview page \(self.pages.count + 1). Drag on the page to select an area to crop."
                    } catch {
                        self.showError("The scan finished, but the preview could not be opened.", details: error.localizedDescription)
                    }
                } else {
                    let details = self.diagnostics.trimmingCharacters(in: .whitespacesAndNewlines)
                    let canceled = details.localizedCaseInsensitiveContains("scan canceled")
                    self.status.stringValue = canceled
                        ? "Scan canceled. Your previously added PDF pages are kept."
                        : self.friendlyError(for: details)
                    if !canceled { self.showError(self.friendlyError(for: details), details: details) }
                }
                self.updateControls()
                if self.quitting && self.process == nil { NSApp.reply(toApplicationShouldTerminate: true) }
            }
        }
        process = task
        updateControls()
        do {
            try task.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            process = nil
            errorPipe = nil
            progress.isIndeterminate = false
            showError("Could not start the scanner program.", details: error.localizedDescription)
            updateControls()
        }
    }

    private func updateScanProgress(from text: String) {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let line = lines.last.map(String.init) else { return }
        status.stringValue = line
        if let range = line.range(of: #"Scanning\.\.\.\s*(\d+)%"#, options: .regularExpression),
           let digits = line[range].split(whereSeparator: { !$0.isNumber }).last,
           let value = Double(digits) {
            progress.isIndeterminate = false
            progress.doubleValue = value
        }
    }

    private func friendlyError(for details: String) -> String {
        let text = details.lowercased()
        if text.contains("0xe00002f0") || text.contains("cannot open m1005 scanner") {
            return "Scanner not found. Check that the M1005 is powered on and connected directly by USB."
        }
        if text.contains("not ready") || text.contains("no other scan") {
            return "The scanner is busy or not ready. Close other scanner apps, check the lid, and try again."
        }
        if text.contains("timeout") || text.contains("no data") {
            return "The scanner stopped responding. Check USB and power, then try the scan again."
        }
        if text.contains("permission") || text.contains("not permitted") {
            return "macOS denied USB access. Reconnect the printer and allow the accessory if macOS asks."
        }
        if text.contains("incomplete scan") || text.contains("invalid scanner") {
            return "The scanner sent incomplete image data. Check the USB connection and retry at a lower resolution."
        }
        return "Scanning failed. Check the printer's USB connection and power, then try again."
    }

    @objc private func cropSelection() {
        guard let image = currentImage, let rect = preview.pixelCropRect() else { return }
        do { setCurrentImage(try ScanDocument.crop(image, rectInImage: rect)); status.stringValue = "Crop applied to the page preview." }
        catch { showError(error.localizedDescription, details: "") }
    }

    @objc private func resetEdits() {
        guard let originalImage else { return }
        setCurrentImage(originalImage)
        status.stringValue = "Edits reset for this page."
    }

    @objc private func rotateLeft() { rotateCurrent(by: -90) }
    @objc private func rotateRight() { rotateCurrent(by: 90) }

    private func rotateCurrent(by degrees: CGFloat) {
        guard let image = currentImage else { return }
        do { setCurrentImage(try ScanDocument.rotate(image, degrees: degrees)); status.stringValue = "Page rotated." }
        catch { showError(error.localizedDescription, details: "") }
    }

    @objc private func autoDeskew() {
        guard let image = currentImage, !processing else { return }
        processing = true
        status.stringValue = "Checking text alignment…"
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        updateControls()
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<CGImage?, Error> = Result {
                guard let angle = try ScanDocument.deskewAngle(image) else { return nil }
                return try ScanDocument.rotate(image, degrees: angle)
            }
            DispatchQueue.main.async {
                self.processing = false
                self.progress.stopAnimation(nil)
                self.progress.isIndeterminate = false
                switch result {
                case .success(let corrected):
                    if let corrected { self.setCurrentImage(corrected); self.status.stringValue = "Page deskewed using detected text lines." }
                    else { self.status.stringValue = "No reliable page skew was detected; the preview is unchanged." }
                case .failure(let error): self.showError("Could not deskew this page.", details: error.localizedDescription)
                }
                self.updateControls()
            }
        }
    }

    private func setCurrentImage(_ image: CGImage) {
        currentImage = image
        preview.image = image
        updateControls()
    }

    @objc private func addPageAndContinue() {
        guard isPDF, currentImage != nil else { return }
        do {
            try commitCurrentPage()
            status.stringValue = "Page added. Place the next page on the glass."
            beginScanPage()
        } catch { showError("Could not add this page to the PDF.", details: error.localizedDescription) }
    }

    @objc private func finishPDF() {
        guard isPDF, !processing else { return }
        do {
            if currentImage != nil { try commitCurrentPage() }
            guard !pages.isEmpty, let outputURL, let workspace else { return }
            processing = true
            status.stringValue = searchable.state == .on ? "Preparing searchable PDF…" : "Building PDF…"
            progress.isIndeterminate = false
            progress.doubleValue = 0
            updateControls()
            let tempPDF = workspace.appendingPathComponent("finished.pdf")
            let pageFiles = pages
            let dpi = selectedDPI
            let ocr = searchable.state == .on
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<Void, Error> = Result {
                    try ScanDocument.writePDF(pages: pageFiles, to: tempPDF, dpi: dpi, searchable: ocr) { completed, message in
                        DispatchQueue.main.async {
                            self.status.stringValue = message
                            self.progress.doubleValue = Double(completed) / Double(max(1, pageFiles.count)) * 100
                        }
                    }
                    guard !FileManager.default.fileExists(atPath: outputURL.path) else {
                        throw ScanDocumentError("The destination appeared while the PDF was being created. Choose a new filename.")
                    }
                    try FileManager.default.moveItem(at: tempPDF, to: outputURL)
                }
                DispatchQueue.main.async {
                    self.processing = false
                    self.progress.doubleValue = 0
                    switch result {
                    case .success: self.completeSave(outputURL)
                    case .failure(let error): self.showError("Could not finish the PDF.", details: error.localizedDescription)
                    }
                    self.updateControls()
                }
            }
        } catch { showError("Could not add the last page.", details: error.localizedDescription) }
    }

    private func commitCurrentPage() throws {
        guard let currentImage, let workspace else { throw ScanDocumentError("There is no page preview to add.") }
        let pageURL = workspace.appendingPathComponent(String(format: "page-%03d.png", pages.count + 1))
        try ScanDocument.writePNG(currentImage, to: pageURL, dpi: selectedDPI)
        pages.append(pageURL)
        self.currentImage = nil
        originalImage = nil
        preview.image = nil
        updateControls()
    }

    @objc private func savePNG() {
        guard !isPDF, let currentImage, let outputURL else { return }
        do {
            try ScanDocument.writePNG(currentImage, to: outputURL, dpi: selectedDPI)
            completeSave(outputURL)
        } catch { showError("Could not save the PNG.", details: error.localizedDescription) }
    }

    @objc private func cancel() {
        guard let process, process.isRunning else { return }
        process.interrupt()
        cancelButton.isEnabled = false
        status.stringValue = "Canceling… waiting for the scanner to return home."
    }

    private func completeSave(_ url: URL) {
        lastFile = url
        status.stringValue = "Saved \(url.lastPathComponent)"
        if let workspace { try? FileManager.default.removeItem(at: workspace) }
        self.workspace = nil
        outputURL = nil
        pages = []
        currentImage = nil
        originalImage = nil
        preview.image = nil
        NSWorkspace.shared.open(url)
        updateControls()
    }

    private func showError(_ message: String, details: String) {
        status.stringValue = message
        guard window != nil else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = details.isEmpty ? "" : "Details: \(details)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    @objc private func openScan() { if let lastFile { NSWorkspace.shared.open(lastFile) } }
    @objc private func revealScan() { if let lastFile { NSWorkspace.shared.activateFileViewerSelecting([lastFile]) } }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if process != nil { cancel(); return false }
        if let workspace { try? FileManager.default.removeItem(at: workspace) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if process != nil { quitting = true; cancel(); return .terminateLater }
        if let workspace { try? FileManager.default.removeItem(at: workspace) }
        return .terminateNow
    }
}
