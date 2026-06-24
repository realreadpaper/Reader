import SwiftUI

struct TopBarView: View {
    let book: Book
    let coordinator: RenderCoordinator
    let storageService: StorageService
    let settings: ReaderSettings
    let onTOCToggle: () -> Void
    let onSearchToggle: () -> Void
    let onFontToggle: () -> Void
    let onAnnotationsToggle: () -> Void
    let onBookmarkAdded: (() -> Void)?

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTOCToggle) {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(themeManager.currentTheme.accent)
            .help("目录 (⌘\\)")

            Text(coordinator.currentTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(themeManager.currentTheme.primaryText)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 14) {
                Button(action: onSearchToggle) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("f", modifiers: .command)
                .help("搜索 (⌘F)")

                Button(action: addBookmark) {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("d", modifiers: .command)
                .help("添加书签 (⌘D)")

                Button(action: onFontToggle) {
                    Text("Aa")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("t", modifiers: .command)
                .help("字体设置 (⌘T)")

                Button(action: onAnnotationsToggle) {
                    Image(systemName: "highlighter")
                }
                .buttonStyle(.plain)
                .help("标注与书签")

                Button(action: decreaseFont) {
                    Image(systemName: "textformat.size.smaller")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("-", modifiers: .command)
                .help("缩小字体 (⌘-)")

                Button(action: increaseFont) {
                    Image(systemName: "textformat.size.larger")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("+", modifiers: .command)
                .help("放大字体 (⌘+)")
            }
            .foregroundStyle(themeManager.currentTheme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(themeManager.currentTheme.sidebarBG)
        .overlay(alignment: .bottom) {
            Divider().background(themeManager.currentTheme.border)
        }
    }

    @MainActor
    private func addBookmark() {
        let position = ReaderNavigationPosition.bookmarkPosition(
            fileType: book.fileType,
            currentChapter: coordinator.currentChapter,
            pdfCurrentPage: coordinator.pdfCurrentPage,
            progress: coordinator.progress
        )
        _ = storageService.addBookmark(
            to: book,
            position: position,
            chapter: coordinator.currentTitle
        )
        onBookmarkAdded?()
    }

    private func increaseFont() {
        settings.fontSize = min(28, settings.fontSize + 1)
    }

    private func decreaseFont() {
        settings.fontSize = max(12, settings.fontSize - 1)
    }
}
