import PDFKit
import SwiftUI

@MainActor
@Observable
final class ReaderModel {
    let document: PDFDocument?
    private(set) var page = 0
    private(set) var selection = ""
    private(set) var scale: CGFloat = 1
    @ObservationIgnored weak var view: PDFView?

    init(url: URL, startPage: Int) {
        document = PDFDocument(url: url)
        page = min(startPage, max(0, (document?.pageCount ?? 1) - 1))
    }

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    func pageChanged(to index: Int) {
        page = index
    }

    func selectionChanged(to text: String) {
        selection = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func scaleChanged(to value: CGFloat) {
        scale = value
    }

    func go(to index: Int) {
        guard let document, let target = document.page(at: min(max(0, index), document.pageCount - 1)) else { return }
        view?.go(to: target)
    }

    func zoom(by factor: CGFloat) {
        guard let view else { return }
        view.autoScales = false
        view.scaleFactor = min(4, max(0.4, view.scaleFactor * factor))
    }

    func fitWidth() {
        view?.autoScales = true
    }

    func clearSelection() {
        view?.clearSelection()
        selection = ""
    }

    func text(around index: Int, radius: Int = 1) -> String {
        guard let document else { return "" }
        let lower = max(0, index - radius)
        let upper = min(document.pageCount - 1, index + radius)
        guard lower <= upper else { return "" }
        return (lower...upper).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
    }
}

struct PDFReader: NSViewRepresentable {
    let model: ReaderModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = model.document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.backgroundColor = .clear
        view.interpolationQuality = .high
        model.view = view
        if let page = model.document?.page(at: model.page) {
            DispatchQueue.main.async { view.go(to: page) }
        }

        let center = NotificationCenter.default
        center.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        center.addObserver(context.coordinator, selector: #selector(Coordinator.selectionChanged(_:)), name: .PDFViewSelectionChanged, object: view)
        center.addObserver(context.coordinator, selector: #selector(Coordinator.scaleChanged(_:)), name: .PDFViewScaleChanged, object: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        let model: ReaderModel

        init(model: ReaderModel) {
            self.model = model
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView, let page = view.currentPage, let document = view.document else { return }
            model.pageChanged(to: document.index(for: page))
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView else { return }
            model.selectionChanged(to: view.currentSelection?.string ?? "")
        }

        @objc func scaleChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView else { return }
            model.scaleChanged(to: view.scaleFactor)
        }
    }
}

enum PDFImport {
    static func pageCount(of url: URL) -> Int? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return PDFDocument(url: url)?.pageCount
    }

    @MainActor
    static func open(_ url: URL, into library: Library) -> StudyDocument? {
        guard url.pathExtension.lowercased() == "pdf", let count = pageCount(of: url) else { return nil }
        return try? library.importDocument(from: url, pageCount: count)
    }
}
