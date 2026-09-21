import AVFoundation
import ScreenCaptureKit

enum RecorderError: LocalizedError {
    case noDisplay
    case noScreenPermission

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "Notula could not find a display to attach the audio capture to."
        case .noScreenPermission:
            return "Notula needs Screen Recording permission to hear what the Mac is playing.\n\nSystem Settings → Privacy & Security → Screen & System Audio Recording → tick Notula, then start the recording again."
        }
    }
}

/// Records two audio tracks at once:
///   mic.wav     — the microphone (the people in the room, and you)
///   system.wav  — whatever the Mac itself is playing (the people on the call)
/// Both come from ScreenCaptureKit, so no extra audio driver is needed.
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {

    private var stream: SCStream?
    private var micFile: AVAudioFile?
    private var systemFile: AVAudioFile?
    private let queue = DispatchQueue(label: "notula.audio")

    private(set) var folder: URL?
    private(set) var startedAt: Date?

    var isRecording: Bool { stream != nil }

    // MARK: - Start / stop

    func start() async throws {
        guard !isRecording else { return }

        // Microphone permission (the dialog appears once, the first time).
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        // Screen & System Audio Recording permission — this is what lets us hear calls.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            throw RecorderError.noScreenPermission
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw RecorderError.noDisplay }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.captureMicrophone = true
        // We want sound, not pictures — so the video side is kept as small and slow as it goes.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 6

        let folder = try Self.makeFolder()
        self.folder = folder

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        try await stream.startCapture()

        self.stream = stream
        self.startedAt = Date()
    }

    /// Stops the capture and returns the folder holding the audio.
    @discardableResult
    func stop() async -> URL? {
        guard let stream else { return nil }
        try? await stream.stopCapture()
        self.stream = nil
        self.startedAt = nil
        queue.sync {
            micFile = nil
            systemFile = nil
        }
        let done = folder
        folder = nil
        return done
    }

    // MARK: - Where recordings land

    private static func makeFolder() throws -> URL {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmm"
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Meetings", isDirectory: true)
        var url = base.appendingPathComponent(stamp.string(from: Date()), isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = base.appendingPathComponent("\(stamp.string(from: Date()))-\(n)", isDirectory: true)
            n += 1
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Audio arriving

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .audio:      write(sampleBuffer, to: &systemFile, named: "system.wav")
        case .microphone: write(sampleBuffer, to: &micFile, named: "mic.wav")
        default: break   // .screen — the 2x2 video we asked for and do not want
        }
    }

    private func write(_ sampleBuffer: CMSampleBuffer, to file: inout AVAudioFile?, named name: String) {
        guard let desc = sampleBuffer.formatDescription,
              var asbd = desc.audioStreamBasicDescription.map({ $0 }),
              let format = AVAudioFormat(streamDescription: &asbd) else { return }

        if file == nil, let folder {
            file = try? AVAudioFile(forWriting: folder.appendingPathComponent(name),
                                    settings: format.settings,
                                    commonFormat: .pcmFormatFloat32,
                                    interleaved: format.isInterleaved)
        }
        guard let target = file else { return }

        try? sampleBuffer.withAudioBufferList { list, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer) else { return }
            try? target.write(from: buffer)
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Notula: capture stopped — \(error.localizedDescription)")
    }
}
