import SwiftUI
import PDFKit

struct PDFRendererView: View {
    let book: Book
    let coordinator: RenderCoordinator
    let settings: ReaderSettings

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        PDFContainerView(
            url: URL(fileURLWithPath: book.filePath),
            coordinator: PDFRendererCoordinator(renderCoordinator: coordinator),
            targetPageIndex: coordinator.pdfCurrentPage - 1,
            theme: themeManager.currentTheme,
            filterEnabled: settings.pdfFilterEnabled
        )
    }
}
