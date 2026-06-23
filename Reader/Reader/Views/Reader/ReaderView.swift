import SwiftUI

struct ReaderView: View {
    let book: Book
    let themeManager: ThemeManager
    let storageService: StorageService

    @State private var coordinator: RenderCoordinator
    @State private var highlightToast: String?

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

                ZStack {
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

                    if coordinator.isLoading {
                        LoadingOverlay()
                    }

                    if let toast = highlightToast {
                        Text(toast)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }

            BottomBarView(
                book: book,
                coordinator: coordinator
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

struct LoadingOverlay: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("加载中...")
                .font(.caption)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}
