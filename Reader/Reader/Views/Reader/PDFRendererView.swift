import SwiftUI
import PDFKit

struct PDFRendererView: View {
    let book: Book
    let coordinator: RenderCoordinator
    let settings: ReaderSettings
    let onSelection: (String, CGRect) -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        PDFContainerView(
            url: URL(fileURLWithPath: book.filePath),
            document: coordinator.pdfDocument,
            coordinator: coordinator,
            targetPageIndex: coordinator.pdfCurrentPage - 1,
            theme: themeManager.currentTheme,
            filterEnabled: settings.pdfFilterEnabled,
            scaleFactor: settings.fontSize / 16.0,
            onSelection: onSelection
        )
    }
}
