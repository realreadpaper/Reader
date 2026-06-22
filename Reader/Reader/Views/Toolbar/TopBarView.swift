import SwiftUI

struct TopBarView: View {
    let book: Book
    let coordinator: RenderCoordinator
    let storageService: StorageService
    let themeManager: ThemeManager
    let onTOCToggle: () -> Void
    let onSearchToggle: () -> Void
    let onFontToggle: () -> Void

    var body: some View {
        HStack {
            Button(action: onTOCToggle) {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(themeManager.currentTheme.accent)

            Text(currentChapterTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(themeManager.currentTheme.primaryText)

            Spacer()

            HStack(spacing: 16) {
                Button(action: onSearchToggle) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)

                Button(action: addBookmark) {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.plain)

                Button(action: onFontToggle) {
                    Text("Aa")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
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

    private var currentChapterTitle: String {
        guard coordinator.currentChapter < coordinator.tocEntries.count else {
            return book.title
        }
        return coordinator.tocEntries[coordinator.currentChapter].title
    }

    private func addBookmark() {
        let position = "\(coordinator.currentChapter):\(coordinator.progress)"
        let chapter = coordinator.tocEntries[safe: coordinator.currentChapter]?.title
        Task {
            await storageService.addBookmark(to: book, position: position, chapter: chapter)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
