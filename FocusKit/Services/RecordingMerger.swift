@preconcurrency import AVFoundation
import Foundation

enum RecordingMerger {
    enum Failure: LocalizedError {
        case noAudio

        var errorDescription: String? {
            "None of these recordings has audio left to merge."
        }
    }

    @MainActor
    static func merge(_ recordings: [Recording], in library: Library) async throws -> Recording {
        let ordered = recordings.sorted { $0.createdAt < $1.createdAt }
        guard var merged = ordered.first else { throw Failure.noAudio }
        let sources = ordered.map { library.audioURL(for: $0) }
        let fileName = "\(UUID().uuidString).\(AudioCapture.fileExtension)"
        let destination = library.recordingsDirectory.appending(path: fileName)

        let duration = try await Task.detached(priority: .userInitiated) {
            try writeAudio(from: sources, to: destination)
        }.value

        merged.fileName = fileName
        merged.duration = max(duration, ordered.reduce(0) { $0 + $1.duration })
        merged.transcript = ordered.map(\.transcript).filter { !$0.isEmpty }.joined(separator: "\n\n")
        merged.goalID = ordered.compactMap(\.goalID).first
        merged.notes = combine(ordered.compactMap(\.notes))
        merged.stage = .ready
        merged.wasInterrupted = nil

        let others = Set(ordered.dropFirst().map(\.id))
        for var session in library.sessions where session.recordingID.map(others.contains) == true {
            session.recordingID = merged.id
            library.log(session)
        }
        library.save(merged)
        for recording in ordered.dropFirst() {
            library.delete(recording)
        }
        try? FileManager.default.removeItem(at: sources[0])
        library.flush()
        return merged
    }

    private static func combine(_ notes: [SmartNotes]) -> SmartNotes? {
        guard !notes.isEmpty else { return nil }
        var sections: [SmartNotes.Section] = []
        for section in notes.flatMap(\.sections) {
            if let index = sections.firstIndex(where: { $0.title == section.title && $0.style == section.style }) {
                let known = Set(sections[index].items.map { $0.primary.lowercased() })
                sections[index].items += section.items.filter { !known.contains($0.primary.lowercased()) }
            } else {
                sections.append(section)
            }
        }
        return SmartNotes(
            text: notes.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n"),
            summary: notes.map(\.summary).filter { !$0.isEmpty }.joined(separator: " "),
            sections: sections,
            createdAt: .now
        )
    }

    nonisolated private static func writeAudio(from sources: [URL], to destination: URL) throws -> TimeInterval {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioCapture.sampleRate, channels: 1, interleaved: false) else {
            throw Failure.noAudio
        }
        let output = try AVAudioFile(
            forWriting: destination,
            settings: [
                AVFormatIDKey: kAudioFormatAppleIMA4,
                AVSampleRateKey: AudioCapture.sampleRate,
                AVNumberOfChannelsKey: 1,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        var written: AVAudioFramePosition = 0
        for url in sources {
            guard let input = try? AVAudioFile(forReading: url),
                  let converter = AVAudioConverter(from: input.processingFormat, to: format) else { continue }
            let ratio = format.sampleRate / input.processingFormat.sampleRate
            while input.framePosition < input.length {
                let remaining = AVAudioFrameCount(min(32_768, input.length - input.framePosition))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: remaining) else { break }
                do {
                    try input.read(into: buffer, frameCount: remaining)
                } catch {
                    break
                }
                guard buffer.frameLength > 0 else { break }
                let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1_024
                guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { break }
                let source = OneShot(buffer)
                var error: NSError?
                converter.convert(to: converted, error: &error) { _, status in
                    source.next(status)
                }
                if let error { throw error }
                if converted.frameLength > 0 {
                    try output.write(from: converted)
                    written += AVAudioFramePosition(converted.frameLength)
                }
            }
        }
        guard written > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw Failure.noAudio
        }
        return Double(written) / format.sampleRate
    }
}

private final class OneShot: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
