import SwiftUI
import PDFKit

struct PDFRendererView: View {
    let book: Book
    let coordinator: RenderCoordinator
    let themeManager: ThemeManager

    var body: some View {
        PDFKitView(
            url: URL(fileURLWithPath: book.filePath),
            coordinator: coordinator
        )
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL
    let coordinator: RenderCoordinator

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.delegate = context.coordinator

        if let document = PDFDocument(url: url) {
            pdfView.document = document
            let pageCount = document.pageCount
            DispatchQueue.main.async {
                coordinator.pdfPageCount = pageCount
                coordinator.pdfCurrentPage = 1
                coordinator.progress = pageCount > 0 ? 1.0 / Double(pageCount) : 0
            }
        }

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {}

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
                self.coordinator.pdfCurrentPage = pageIndex + 1
                self.coordinator.pdfPageCount = totalPages
                self.coordinator.progress = totalPages > 0 ? Double(pageIndex) / Double(totalPages) : 0
            }
        }
    }
}
