import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let recorder = Recorder()
    private var tick: Timer?
    private var busy = false          // true while the transcript + summary are being made

    private let recordItem = NSMenuItem(title: "Start Recording", action: #selector(toggle), keyEquivalent: "r")
    private let stateItem  = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(recording: false)

        let menu = NSMenu()
        recordItem.target = self
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        menu.addItem(recordItem)
        menu.addItem(withTitle: "Summarise an Audio File…", action: #selector(pickFile), keyEquivalent: "o").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Meetings Folder", action: #selector(openFolder), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notula", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    // MARK: - Menu bar look

    private func setIcon(recording: Bool) {
        let name = recording ? "record.circle.fill" : "waveform"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Notula")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func setTitle(_ text: String?) {
        statusItem.button?.title = text.map { " \($0)" } ?? ""
    }

    // MARK: - Recording

    @objc private func toggle() {
        if recorder.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        Task { @MainActor in
            do {
                try await recorder.start()
                setIcon(recording: true)
                recordItem.title = "Stop and Summarise"
                stateItem.title = "Recording…"
                tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    guard let self, let started = self.recorder.startedAt else { return }
                    let seconds = Int(Date().timeIntervalSince(started))
                    let text = String(format: "%02d:%02d", seconds / 60, seconds % 60)
                    self.setTitle(text)
                    self.stateItem.title = "Recording — \(text)"
                }
            } catch {
                show(error)
            }
        }
    }

    private func stopRecording() {
        Task { @MainActor in
            let folder = await recorder.stop()
            tick?.invalidate(); tick = nil
            setIcon(recording: false)
            setTitle(nil)
            recordItem.title = "Start Recording"
            guard let folder else { stateItem.title = "Idle"; return }
            runPipeline(on: folder)
        }
    }

    // MARK: - Transcribe + summarise

    @objc private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a recording to summarise"
        panel.allowedContentTypes = [.audio, .mpeg4Movie, .movie]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            runPipeline(on: url)
        }
    }

    private func runPipeline(on target: URL) {
        guard !busy else { return }
        busy = true
        recordItem.isEnabled = false
        stateItem.title = "Transcribing…"
        setTitle("…")

        let script = Self.pipelineScript()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = [script.path, target.path]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            var output = Data()
            pipe.fileHandleForReading.readabilityHandler = { output.append($0.availableData) }

            do { try task.run() } catch {
                DispatchQueue.main.async { self?.finish(error: error, log: "") }
                return
            }
            task.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            output.append(pipe.fileHandleForReading.readDataToEndOfFile())
            let log = String(data: output, encoding: .utf8) ?? ""
            let status = task.terminationStatus

            DispatchQueue.main.async {
                guard let self else { return }
                if status == 0 {
                    // The script prints the folder it wrote to on its last line.
                    let last = log.split(separator: "\n").last.map(String.init) ?? ""
                    let folder = URL(fileURLWithPath: last.hasPrefix("/") ? last : target.path)
                    // The page first — it is the readable one. The Markdown is still there.
                    let page = folder.appendingPathComponent("summary.html")
                    let markdown = folder.appendingPathComponent("summary.md")
                    if FileManager.default.fileExists(atPath: page.path) {
                        NSWorkspace.shared.open(page)
                    } else if FileManager.default.fileExists(atPath: markdown.path) {
                        NSWorkspace.shared.open(markdown)
                    } else {
                        NSWorkspace.shared.open(folder)
                    }
                    self.finish(error: nil, log: log)
                } else {
                    self.finish(error: NSError(domain: "Notula", code: Int(status),
                                               userInfo: [NSLocalizedDescriptionKey: "The transcript step failed."]),
                                log: log)
                }
            }
        }
    }

    private func finish(error: Error?, log: String) {
        busy = false
        recordItem.isEnabled = true
        stateItem.title = "Idle"
        setTitle(nil)
        if let error {
            let alert = NSAlert()
            alert.messageText = "Notula could not finish"
            alert.informativeText = error.localizedDescription + "\n\n" + String(log.suffix(600))
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// The shell script that does the real work. build.sh records its path in Info.plist,
    /// so editing tools/pipeline.sh takes effect straight away — no rebuild.
    private static func pipelineScript() -> URL {
        if let path = Bundle.main.object(forInfoDictionaryKey: "NotulaPipeline") as? String,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.resourceURL!.appendingPathComponent("pipeline.sh")
    }

    // MARK: - Small menu actions

    @objc private func openFolder() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Meetings")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        Task { @MainActor in
            await recorder.stop()
            NSApp.terminate(nil)
        }
    }

    private func show(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Notula could not start recording"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
