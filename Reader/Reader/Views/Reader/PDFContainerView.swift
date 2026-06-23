import SwiftUI
import PDFKit
import QuartzCore

struct PDFContainerView: NSViewRepresentable {
    let url: URL
    let document: PDFDocument?
    let coordinator: RenderCoordinator
    let targetPageIndex: Int
    let theme: AppTheme
    let filterEnabled: Bool

    func makeCoordinator() -> PDFRendererCoordinator {
        PDFRendererCoordinator(renderCoordinator: coordinator)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.wantsLayer = true
        pdfView.delegate = context.coordinator
        context.coordinator.applyRenderOptions(
            to: pdfView,
            theme: theme,
            filterEnabled: filterEnabled
        )

        let doc = document ?? PDFDocument(url: url)
        if let doc {
            pdfView.document = doc
            let startPage = max(0, min(targetPageIndex, doc.pageCount - 1))
            if doc.pageCount > 0, let page = doc.page(at: startPage) {
                pdfView.go(to: page)
            }
            context.coordinator.bindInitialProgress(
                pageIndex: startPage,
                totalPages: doc.pageCount
            )
        }

        context.coordinator.startObservingPageChanges(pdfView: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.applyRenderOptions(
            to: pdfView,
            theme: theme,
            filterEnabled: filterEnabled
        )

        let doc = document ?? PDFDocument(url: url)
        if let doc, pdfView.document !== doc {
            pdfView.document = doc
            let startPage = max(0, min(targetPageIndex, doc.pageCount - 1))
            if doc.pageCount > 0, let page = doc.page(at: startPage) {
                pdfView.go(to: page)
            }
        } else if let doc = pdfView.document {
            let current = pdfView.currentPage.flatMap { doc.index(for: $0) } ?? -1
            if targetPageIndex >= 0 && targetPageIndex < doc.pageCount && targetPageIndex != current {
                if let page = doc.page(at: targetPageIndex) {
                    pdfView.go(to: page)
                }
            }
        }
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: PDFRendererCoordinator) {
        coordinator.stopObservingPageChanges()
    }

}

struct PDFRenderOptions: Equatable {
    let theme: AppTheme
    let filterEnabled: Bool

    func apply(to view: PDFView) {
        let background = Self.backgroundColor(for: theme)
        view.wantsLayer = true
        view.backgroundColor = background
        view.layer?.backgroundColor = background.cgColor
        view.layer?.isOpaque = true
        view.contentFilters = filterEnabled ? Self.filters(for: theme) : []
    }

    static func backgroundColor(for theme: AppTheme) -> NSColor {
        NSColor(theme.contentBG)
    }

    static func filters(for theme: AppTheme) -> [CIFilter] {
        switch theme {
        case .classic, .kraft:
            return []
        case .eyeCare:
            let saturation = CIFilter(name: "CIColorControls", parameters: [
                "inputSaturation": 0.85,
                "inputBrightness": 0.02,
            ])
            return [saturation].compactMap { $0 }
        case .night:
            let invert = CIFilter(name: "CIColorInvert")
            let adjust = CIFilter(name: "CIColorControls", parameters: [
                "inputBrightness": -0.15,
                "inputContrast": 1.05,
            ])
            return [invert, adjust].compactMap { $0 }
        }
    }
}

struct PDFRenderOptionsState {
    private var current: PDFRenderOptions?

    mutating func markIfChanged(_ next: PDFRenderOptions) -> Bool {
        guard current != next else { return false }
        current = next
        return true
    }
}

final class PDFRendererCoordinator: NSObject, PDFViewDelegate {
    let renderCoordinator: RenderCoordinator
    private var pageChangeObserver: NSObjectProtocol?
    private var lastPageIndex: Int = -1
    private var renderOptionsState = PDFRenderOptionsState()

    init(renderCoordinator: RenderCoordinator) {
        self.renderCoordinator = renderCoordinator
    }

    deinit {
        if let obs = pageChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    @MainActor
    func bindInitialProgress(pageIndex: Int, totalPages: Int) {
        guard totalPages > 0 else { return }
        if lastPageIndex != pageIndex {
            lastPageIndex = pageIndex
        }
        let p = Double(pageIndex + 1) / Double(totalPages)
        if renderCoordinator.progress < p || renderCoordinator.progress == 0 {
            renderCoordinator.updatePDFProgress(currentPage: pageIndex, totalPages: totalPages)
        }
    }

    func startObservingPageChanges(pdfView: PDFView) {
        guard pageChangeObserver == nil else { return }
        pageChangeObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] notification in
            self?.handlePageChanged(notification)
        }
    }

    func stopObservingPageChanges() {
        if let obs = pageChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            pageChangeObserver = nil
        }
    }

    func applyRenderOptions(to pdfView: PDFView, theme: AppTheme, filterEnabled: Bool) {
        let options = PDFRenderOptions(theme: theme, filterEnabled: filterEnabled)
        guard renderOptionsState.markIfChanged(options) else { return }
        options.apply(to: pdfView)
    }

    private func handlePageChanged(_ notification: Notification) {
        guard let pdfView = notification.object as? PDFView,
              let document = pdfView.document,
              let page = pdfView.currentPage else { return }
        let idx = document.index(for: page)
        guard idx != lastPageIndex, idx >= 0 else { return }
        lastPageIndex = idx
        Task { @MainActor in
            renderCoordinator.updatePDFProgress(currentPage: idx, totalPages: document.pageCount)
        }
    }
}
