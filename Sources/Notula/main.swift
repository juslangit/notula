import AppKit

// Test mode:  Notula.app/Contents/MacOS/Notula --record 20
// Records for the given number of seconds, runs the pipeline, prints the folder.
// Useful for checking the microphone and call audio really are being picked up.
if CommandLine.arguments.contains("--record") {
    let index = CommandLine.arguments.firstIndex(of: "--record")!
    let seconds = Double(CommandLine.arguments[safe: index + 1] ?? "") ?? 15

    let recorder = Recorder()
    let done = DispatchSemaphore(value: 0)
    Task {
        do {
            try await recorder.start()
            FileHandle.standardError.write("recording for \(Int(seconds))s…\n".data(using: .utf8)!)
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            let folder = await recorder.stop()
            if let folder {
                for name in ["mic.wav", "system.wav"] {
                    let url = folder.appendingPathComponent(name)
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                    FileHandle.standardError.write("  \(name): \((size ?? 0) / 1024) KB\n".data(using: .utf8)!)
                }
                print(folder.path)
            }
        } catch {
            FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
            exit(1)
        }
        done.signal()
    }
    done.wait()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // lives in the menu bar, not the Dock
app.run()

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
