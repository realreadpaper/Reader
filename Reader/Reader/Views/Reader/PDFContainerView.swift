import SwiftUI
import PDFKit
import QuartzCore

struct PDFContainerView: NSViewRepresentable {
    let url: URL
    let coordinator: PDFRendererCoordinator
    let targetPageIndex: Int
    let theme: AppTheme
    let filterEnabled: Bool

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.wantsLayer = true
        pdfView.delegate = context.coordinator

        if let document = PDFDocument(url: url) {
            pdfView.document = document
            let startPage = max(0, min(targetPageIndex, document.pageCount - 1))
            if document.pageCount > 0, let page = document.page(at: startPage) {
                pdfView.go(to: page)
            }
            context.coordinator.bindInitialProgress(
                pageIndex: startPage,
                totalPages: document.pageCount
            )
        }

        context.coordinator.startObservingPageChanges(pdfView: pdfView)

        applyFilters(to: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        applyFilters(to: pdfView)

        guard let document = pdfView.document else { return }
        let current = pdfView.currentPage.flatMap { document.index(for: $0) } ?? -1
        if targetPageIndex >= 0 && targetPageIndex < document.pageCount && targetPageIndex != current {
            if let page = document.page(at: targetPageIndex) {
                pdfView.go(to: page)
            }
        }
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: PDFRendererCoordinator) {
        coordinator.stopObservingPageChanges()
    }

    func makeCoordinator() -> PDFRendererCoordinator { coordinator }

    private func applyFilters(to view: PDFView) {
        guard filterEnabled else {
            view.contentFilters = []
            return
        }
        view.contentFilters = Self.filters(for: theme)
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

final class PDFRendererCoordinator: NSObject, PDFViewDelegate {
    let renderCoordinator: RenderCoordinator
    private var pageChangeObserver: NSObjectProtocol?
    private var lastPageIndex: Int = -1

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
