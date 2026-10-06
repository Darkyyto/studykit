import AppKit
import UniformTypeIdentifiers

@MainActor
enum NotesPDF {
    static func export(_ recording: Recording, goal: Goal?, original: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = recording.title.replacing("/", with: "-") + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        write(document(for: recording, goal: goal, original: original), to: url)
    }

    private static func write(_ text: NSAttributedString, to url: URL) {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 56
        info.bottomMargin = 56
        info.leftMargin = 60
        info.rightMargin = 60
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        view.isVerticallyResizable = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textStorage?.setAttributedString(text)
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
    }

    private static func document(for recording: Recording, goal: Goal?, original: Bool) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let ink = NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        let secondary = NSColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)
        let accent = goal.map { NSColor($0.tint.color) } ?? NSColor(red: 0.4, green: 0.31, blue: 0.9, alpha: 1)

        func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        }

        func append(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = ink, before: CGFloat = 0, after: CGFloat = 6, line: CGFloat = 1.3, indent: CGFloat = 0) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = before
            style.paragraphSpacing = after
            style.lineHeightMultiple = line
            style.headIndent = indent
            style.firstLineHeadIndent = indent == 0 ? 0 : indent - 14
            output.append(NSAttributedString(string: string + "\n", attributes: [
                .font: font(size, weight),
                .foregroundColor: color,
                .paragraphStyle: style,
            ]))
        }

        var details = [
            recording.createdAt.formatted(date: .long, time: .shortened),
            recording.duration.compactDuration,
        ]
        if let goal {
            details.insert(goal.title, at: 0)
        }

        append(details.joined(separator: "  ·  ").uppercased(), size: 9, weight: .semibold, color: accent, after: 8)
        append(recording.title, size: 26, weight: .bold, after: 14, line: 1.05)

        if let notes = recording.notes, !original {
            if !notes.summary.isEmpty {
                append(notes.summary, size: 13, weight: .medium, color: secondary, after: 18, line: 1.4)
            }
            for section in notes.sections where !section.items.isEmpty {
                append(section.title, size: 15, weight: .bold, color: accent, before: 10, after: 8)
                for item in section.items {
                    switch section.style {
                    case .flashcards:
                        append(item.primary, size: 12, weight: .semibold, after: 2, line: 1.3)
                        if let answer = item.secondary {
                            append(answer, size: 12, color: secondary, after: 10, line: 1.3)
                        }
                    case .definitions:
                        append(item.primary, size: 12, weight: .semibold, after: 1)
                        if let definition = item.secondary {
                            append(definition, size: 12, color: secondary, after: 9, line: 1.3)
                        }
                    case .checklist:
                        let owner = item.secondary.map { "  —  \($0)" } ?? ""
                        append("☐\t" + item.primary + owner, size: 12, after: 5, indent: 14)
                    case .bullets:
                        append("•\t" + item.primary, size: 12, after: 5, indent: 14)
                    }
                }
            }
            append("Notes", size: 15, weight: .bold, color: accent, before: 14, after: 8)
            for paragraph in notes.text.components(separatedBy: "\n") where !paragraph.trimmingCharacters(in: .whitespaces).isEmpty {
                append(paragraph, size: 12, after: 9, line: 1.45)
            }
        } else {
            append("Transcript", size: 15, weight: .bold, color: accent, before: 4, after: 8)
            append(recording.transcript.isEmpty ? "No transcript was captured." : recording.transcript, size: 12, after: 9, line: 1.45)
        }

        append("Made with FocusKit", size: 8, weight: .medium, color: secondary, before: 24)
        return output
    }
}
