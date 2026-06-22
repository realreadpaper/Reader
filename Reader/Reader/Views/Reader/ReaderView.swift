import SwiftUI

struct ReaderView: View {
    let book: Book
    let themeManager: ThemeManager
    let storageService: StorageService

    @State private var coordinator: RenderCoordinator

    init(book: Book, themeManager: ThemeManager, storageService: StorageService) {
        self.book = book
        self.themeManager = themeManager
        self.storageService = storageService
        _coordinator = State(initialValue: RenderCoordinator(book: book))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView(
                book: book,
                coordinator: coordinator,
                storageService: storageService,
                themeManager: themeManager,
                onTOCToggle: { coordinator.showTOC.toggle() },
                onSearchToggle: { coordinator.showSearch.toggle() },
                onFontToggle: { coordinator.showFontPanel.toggle() }
            )

            HStack(spacing: 0) {
                if coordinator.showTOC {
                    TOCView(
                        chapters: coordinator.tocEntries,
                        onChapterSelect: { coordinator.navigateToChapter($0) },
                        isPDF: book.fileType == .pdf
                    )
                    .frame(width: 200)
                    .background(themeManager.currentTheme.sidebarBG)
                }

                Group {
                    switch book.fileType {
                    case .epub, .mobi:
                        EPUBRendererView(
                            book: book,
                            chapters: coordinator.chapters,
                            currentChapter: $coordinator.currentChapter,
                            progress: $coordinator.progress,
                            themeManager: themeManager
                        )
                    case .pdf:
                        PDFRendererView(
                            book: book,
                            coordinator: coordinator,
                            themeManager: themeManager
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(themeManager.currentTheme.contentBG)
            }

            BottomBarView(
                book: book,
                coordinator: coordinator,
                themeManager: themeManager
            )
        }
        .background(themeManager.currentTheme.contentBG)
        .task {
            await loadBook()
        }
    }

    private func loadBook() async {
        switch book.fileType {
        case .epub:
            await coordinator.loadEPUB()
        case .mobi:
            await coordinator.loadMOBI()
        case .pdf:
            coordinator.loadPDF()
        }
    }
}
