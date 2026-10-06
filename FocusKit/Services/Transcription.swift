@preconcurrency import AVFoundation
import Speech

struct Transcription: Sendable {
    enum Failure: LocalizedError {
        case unsupportedLocale(Locale)
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale(let locale):
                "On-device transcription is not available for \(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)."
            case .unavailable:
                "On-device transcription is not available on this Mac."
            }
        }
    }

    let locale: Locale
    let analyzer: SpeechAnalyzer
    let transcriber: SpeechTranscriber
    let format: AVAudioFormat
    let input: AsyncStream<AnalyzerInput>.Continuation

    static func prepare(for requested: Locale, vocabulary: [String], onDownload: @MainActor @Sendable () -> Void) async throws -> Transcription {
        guard SpeechTranscriber.isAvailable else { throw Failure.unavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw Failure.unsupportedLocale(requested)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            await onDownload()
            try await request.downloadAndInstall()
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Failure.unavailable
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try? await analyzer.setContext(context)
        }
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: stream)

        return Transcription(locale: locale, analyzer: analyzer, transcriber: transcriber, format: format, input: input)
    }

    func finish() async {
        input.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
    }

    static func transcribe(file url: URL, locale requested: Locale, vocabulary: [String]) async throws -> (plain: String, marked: String) {
        guard SpeechTranscriber.isAvailable else { throw Failure.unavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw Failure.unsupportedLocale(requested)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.transcriptionConfidence]
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let context = AnalysisContext()
        if !vocabulary.isEmpty {
            context.contextualStrings[.general] = vocabulary
        }

        let collector = Task {
            var plain: [String] = []
            var marked: [String] = []
            for try await result in transcriber.results where result.isFinal {
                plain.append(String(result.text.characters))
                marked.append(markingUncertainWords(in: result.text))
            }
            return (plain, marked)
        }

        let file = try AVAudioFile(forReading: url)
        let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber], analysisContext: context, finishAfterFile: true)
        let (plain, marked) = try await collector.value
        _ = analyzer
        return (joined(plain), joined(marked))
    }

    static func joined(_ pieces: [String]) -> String {
        pieces.reduce(into: "") { text, piece in
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if text.isEmpty {
                text = trimmed
            } else if trimmed.first.map({ ",.;:!?".contains($0) }) == true {
                text += trimmed
            } else {
                text += " " + trimmed
            }
        }
    }

    private static func markingUncertainWords(in text: AttributedString) -> String {
        var output = ""
        for run in text.runs {
            let piece = String(text[run.range].characters)
            let confidence = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] ?? 1
            let word = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            if confidence < 0.45, word.contains(where: \.isLetter) {
                let leading = piece.prefix { $0.isWhitespace }
                output += leading + "⟦" + word + "⟧"
            } else {
                output += piece
            }
        }
        return output
    }

    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted {
            $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending
        }
    }
}

extension Locale {
    static var preferredSpeech: Locale {
        Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
    }

    static func speech(_ identifier: String) -> Locale {
        identifier.isEmpty ? preferredSpeech : Locale(identifier: identifier)
    }

    var localizedName: String {
        let name = localizedString(forIdentifier: identifier) ?? Locale.current.localizedString(forIdentifier: identifier) ?? identifier
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
