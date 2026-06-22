import SwiftUI
import PDFKit

struct PDFRendererView: View {
    let book: Book
    @Binding var progress: Double
    let themeManager: ThemeManager

    var body: some View {
        PDFKitView(url: URL(fileURLWithPath: book.filePath), progress: $progress)
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL
    @Binding var progress: Double

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if let document = pdfView.document, let page = pdfView.currentPage {
            let pageIndex = document.index(for: page)
            let totalPages = document.pageCount
            progress = totalPages > 0 ? Double(pageIndex) / Double(totalPages) : 0
        }
    }
}
