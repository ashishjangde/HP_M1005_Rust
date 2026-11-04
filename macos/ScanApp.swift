import AppKit
import UniformTypeIdentifiers

final class ScanApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let resolution = NSPopUpButton()
    private let mode = NSPopUpButton()
    private let format = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "Ready to scan")
    private let progress = NSProgressIndicator()
    private let scanButton = NSButton(title: "Scan…", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let openButton = NSButton(title: "Open Scan", target: nil, action: nil)
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private let rotate = NSButton(checkboxWithTitle: "Rotate page 180°", target: nil, action: nil)
    private var process: Process?
    private var errorPipe: Pipe?
    private var diagnostics = ""
    private var lastFile: URL?
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let root = NSMenuItem()
        menu.addItem(root)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit HP M1005 Scan", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        root.submenu = appMenu
        NSApp.mainMenu = menu
        NSApp.applicationIconImage = NSImage(systemSymbolName: "scanner", accessibilityDescription: "Scanner")

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "HP M1005 Scan"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28)
        ])

        let title = NSTextField(labelWithString: "HP LaserJet M1005")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        stack.addArrangedSubview(title)
        let instructions = NSTextField(wrappingLabelWithString: "Place your page face-down on the scanner glass and close the lid. Keep the printer connected by USB.")
        instructions.textColor = .secondaryLabelColor
        instructions.preferredMaxLayoutWidth = 475
        stack.addArrangedSubview(instructions)

        resolution.addItems(withTitles: ["75 dpi", "100 dpi", "150 dpi", "200 dpi", "300 dpi", "600 dpi"])
        resolution.selectItem(withTitle: "300 dpi")
        mode.addItems(withTitles: ["Grayscale", "Color"])
        format.addItems(withTitles: ["PDF", "PNG"])
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Paper"), NSTextField(labelWithString: "A4 · Flatbed")],
            [NSTextField(labelWithString: "Resolution"), resolution],
            [NSTextField(labelWithString: "Color mode"), mode],
            [NSTextField(labelWithString: "Save as"), format]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 28
        grid.column(at: 0).width = 100
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading
        stack.addArrangedSubview(grid)
        stack.addArrangedSubview(rotate)

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.spacing = 10
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        status.font = .systemFont(ofSize: 13)
        status.preferredMaxLayoutWidth = 440
        statusRow.addArrangedSubview(progress)
        statusRow.addArrangedSubview(status)
        stack.addArrangedSubview(statusRow)

        let actions = NSStackView()
        actions.spacing = 10
        scanButton.target = self
        scanButton.action = #selector(scan)
        scanButton.bezelStyle = .rounded
        scanButton.keyEquivalent = "\r"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.bezelStyle = .rounded
        cancelButton.isEnabled = false
        actions.addArrangedSubview(scanButton)
        actions.addArrangedSubview(cancelButton)
        stack.addArrangedSubview(actions)

        let results = NSStackView()
        results.spacing = 10
        openButton.target = self
        openButton.action = #selector(openScan)
        revealButton.target = self
        revealButton.action = #selector(revealScan)
        for button in [openButton, revealButton] {
            button.bezelStyle = .rounded
            button.isEnabled = false
            results.addArrangedSubview(button)
        }
        stack.addArrangedSubview(results)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setBusy(_ busy: Bool) {
        scanButton.isEnabled = !busy
        cancelButton.isEnabled = busy
        resolution.isEnabled = !busy
        mode.isEnabled = !busy
        format.isEnabled = !busy
        rotate.isEnabled = !busy
        if busy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }

    @objc private func scan() {
        guard process == nil else { return }
        let panel = NSSavePanel()
        let type: UTType = format.indexOfSelectedItem == 0 ? .pdf : .png
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        panel.nameFieldStringValue = "Scan \(formatter.string(from: Date())).\(type == .pdf ? "pdf" : "png")"
        panel.prompt = "Scan and Save"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self = self, let destination = panel.url else { return }
            if FileManager.default.fileExists(atPath: destination.path) {
                self.status.stringValue = "Choose a new filename to preserve your existing file."
                return
            }
            self.start(destination)
        }
    }

    private func start(_ destination: URL) {
        guard let executable = Bundle.main.url(forResource: "m1005", withExtension: nil) else {
            status.stringValue = "Scanner component is missing. Reinstall the Scan app."
            return
        }
        let task = Process()
        task.executableURL = executable
        let dpi = resolution.titleOfSelectedItem!.split(separator: " ")[0]
        task.arguments = ["scan", destination.path, String(dpi), mode.indexOfSelectedItem == 0 ? "gray" : "color",
                          rotate.state == .on ? "180" : "0"]
        let pipe = Pipe()
        errorPipe = pipe
        task.standardError = pipe
        task.standardOutput = FileHandle.nullDevice
        diagnostics = ""
        status.stringValue = "Connecting to scanner…"
        setBusy(true)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            guard !bytes.isEmpty, let text = String(data: bytes, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.diagnostics += text
                if self.diagnostics.count > 16000 { self.diagnostics = String(self.diagnostics.suffix(16000)) }
                if let line = text.split(separator: "\n").last { self.status.stringValue = String(line) }
            }
        }
        task.terminationHandler = { [weak self] completed in
            DispatchQueue.main.async {
                guard let self = self else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                self.errorPipe = nil
                self.process = nil
                self.setBusy(false)
                if completed.terminationStatus == 0 {
                    self.lastFile = destination
                    self.status.stringValue = "Saved \(destination.lastPathComponent)"
                    self.openButton.isEnabled = true
                    self.revealButton.isEnabled = true
                    NSWorkspace.shared.open(destination)
                } else if self.diagnostics.contains("scan canceled") {
                    self.status.stringValue = "Scan canceled. Ready for the next page."
                } else {
                    self.status.stringValue = self.diagnostics.split(separator: "\n").last.map(String.init) ?? "Scanning failed. Check USB and printer power."
                }
                if self.quitting { NSApp.reply(toApplicationShouldTerminate: true) }
            }
        }
        process = task
        do { try task.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            process = nil
            errorPipe = nil
            setBusy(false)
            status.stringValue = "Could not start scanner: \(error.localizedDescription)"
        }
    }

    @objc private func cancel() {
        guard let task = process, task.isRunning else { return }
        task.interrupt()
        cancelButton.isEnabled = false
        status.stringValue = "Canceling… waiting for the scanner to return home."
    }
    @objc private func openScan() { if let url = lastFile { NSWorkspace.shared.open(url) } }
    @objc private func revealScan() { if let url = lastFile { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if process != nil { cancel(); return false }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if process != nil { quitting = true; cancel(); return .terminateLater }
        return .terminateNow
    }
}

let app = NSApplication.shared
let delegate = ScanApp()
app.delegate = delegate
app.run()
