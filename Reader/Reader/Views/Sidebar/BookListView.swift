import SwiftUI

struct BookListView: View {
    let books: [Book]
    @Binding var selectedBook: Book?

    var body: some View {
        List(selection: $selectedBook) {
            ForEach(books, id: \.id) { book in
                BookRowView(book: book)
                    .tag(book)
            }
        }
        .listStyle(.sidebar)
    }
}
