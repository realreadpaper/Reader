import SwiftUI

struct BookListView: View {
    let books: [Book]
    @Binding var selectedBook: Book?
    let onDelete: (Book) -> Void
    let onToggleFavorite: (Book) -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        List(selection: $selectedBook) {
            ForEach(books, id: \.id) { book in
                BookRowView(book: book)
                    .tag(book)
                    .contextMenu {
                        Button(book.isFavorite ? "取消收藏" : "收藏") {
                            onToggleFavorite(book)
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            onDelete(book)
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.currentTheme.sidebarBG)
    }
}
