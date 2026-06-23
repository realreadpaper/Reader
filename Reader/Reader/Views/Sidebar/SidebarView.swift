import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    let storageService: StorageService
    let library: BookLibrary
    @Binding var selectedBook: Book?
    let onRequestImport: () -> Void
    @Binding var importError: String?

    @State private var selectedTab: SidebarTab = .all
    @State private var searchText = ""
    @Environment(ThemeManager.self) private var theme

    enum SidebarTab: String, CaseIterable {
        case all = "全部"
        case recent = "最近"
        case favorite = "收藏"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("书架")
                    .font(.headline)
                    .foregroundStyle(theme.currentTheme.primaryText)
                Spacer()
                Button(action: onRequestImport) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.currentTheme.accent)
                .keyboardShortcut("o", modifiers: .command)
                .help("导入书籍 (⌘O)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            HStack(spacing: 0) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.rawValue)
                            .font(.caption)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .foregroundStyle(
                                selectedTab == tab
                                    ? theme.currentTheme.primaryText
                                    : theme.currentTheme.secondaryText
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                selectedTab == tab
                                    ? theme.currentTheme.border.opacity(0.6)
                                    : Color.clear
                            )
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(theme.currentTheme.secondaryText)
                TextField("筛选书名", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(theme.currentTheme.primaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(theme.currentTheme.border.opacity(0.4))
            .cornerRadius(6)
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider()
                .background(theme.currentTheme.border)
                .padding(.top, 8)

            BookListView(
                books: filteredBooks,
                selectedBook: $selectedBook,
                onDelete: deleteBook,
                onToggleFavorite: toggleFavorite
            )
        }
        .background(theme.currentTheme.sidebarBG)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    @MainActor
    private var allBooks: [Book] {
        switch selectedTab {
        case .all: return storageService.fetchBooks()
        case .recent: return storageService.fetchRecentBooks()
        case .favorite: return storageService.fetchFavoriteBooks()
        }
    }

    @MainActor
    private var filteredBooks: [Book] {
        guard !searchText.isEmpty else { return allBooks }
        return allBooks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    @MainActor
    private func deleteBook(_ book: Book) {
        if selectedBook?.id == book.id {
            selectedBook = nil
        }
        library.deleteBookFiles(book)
        storageService.deleteBook(book)
    }

    @MainActor
    private func toggleFavorite(_ book: Book) {
        storageService.toggleFavorite(book)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    do {
                        _ = try library.importBook(at: url)
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            }
        }
    }
}
