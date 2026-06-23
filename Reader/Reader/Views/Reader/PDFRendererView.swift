import SwiftUI
import PDFKit

struct PDFRendererView: View {
    let book: Book
    let coordinator: RenderCoordinator
    let themeManager: ThemeManager

    var body: some View {
        PDFKitContainerView(
            document: coordinator.pdfDocument,
            coordinator: coordinator,
            theme: themeManager.currentTheme
        )
    }
}

struct PDFKitContainerView: NSViewRepresentable {
    let document: PDFDocument?
    let coordinator: RenderCoordinator
    let theme: AppTheme

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor(theme.contentBG)
        pdfView.delegate = context.coordinator

        if let document {
            pdfView.document = document
            if document.pageCount > 0 {
                if let page = document.page(at: 0) {
                    pdfView.go(to: page)
                }
            }
        }

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.backgroundColor = NSColor(theme.contentBG)
        if let document, pdfView.document !== document {
            pdfView.document = document
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(coordinator: coordinator)
    }

    class Coordinator: NSObject, PDFViewDelegate {
        let coordinator: RenderCoordinator
        private var lastPageIndex: Int = -1

        init(coordinator: RenderCoordinator) {
            self.coordinator = coordinator
        }

        func pdfView(_ pdfView: PDFView, willChangePageTo pageIndex: Int) {
            guard pageIndex != lastPageIndex else { return }
            lastPageIndex = pageIndex
            let totalPages = pdfView.document?.pageCount ?? 0
            DispatchQueue.main.async {
                self.coordinator.updatePDFProgress(currentPage: pageIndex, totalPages: totalPages)
            }
        }
    }
}
