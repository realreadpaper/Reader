import SwiftUI

struct BookListView: View {
    let books: [Book]
    @Binding var selectedBook: Book?
    let onDelete: (Book) -> Void
    let onToggleFavorite: (Book) -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(books, id: \.id) { book in
                    BookRowView(
                        book: book,
                        isSelected: selectedBook?.id == book.id
                    )
                    .onTapGesture {
                        selectedBook = book
                    }
                    .contextMenu {
                        Button(book.isFavorite ? "取消收藏" : "收藏") {
                            onToggleFavorite(book)
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            onDelete(book)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
            .padding(.vertical, 6)
        }
        .background(theme.currentTheme.sidebarBG)
    }
}
