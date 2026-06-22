import Foundation
import SwiftData

@MainActor
@Observable
final class StorageService {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    private init(container: ModelContainer) {
        self.modelContainer = container
        self.modelContext = container.mainContext
    }

    static func create() async -> StorageService {
        await Task { @MainActor in
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            let container = try! ModelContainer(
                for: Book.self, Bookmark.self, Highlight.self,
                configurations: config
            )
            return StorageService(container: container)
        }.value
    }

    // MARK: - Book CRUD

    func addBook(title: String, author: String? = nil, filePath: String, fileType: FileType) -> Book {
        let book = Book(title: title, author: author, filePath: filePath, fileType: fileType)
        modelContext.insert(book)
        save()
        return book
    }

    func fetchBooks() -> [Book] {
        let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.lastRead, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchRecentBooks() -> [Book] {
        let descriptor = FetchDescriptor<Book>(
            sortBy: [SortDescriptor(\.lastRead, order: .reverse)]
        )
        let books = (try? modelContext.fetch(descriptor)) ?? []
        return Array(books.prefix(10))
    }

    func fetchFavoriteBooks() -> [Book] {
        let descriptor = FetchDescriptor<Book>(
            sortBy: [SortDescriptor(\.title)]
        )
        let books = (try? modelContext.fetch(descriptor)) ?? []
        return books.filter { $0.isFavorite }
    }

    func updateBook(_ book: Book) {
        book.lastRead = Date()
        save()
    }

    func deleteBook(_ book: Book) {
        modelContext.delete(book)
        save()
    }

    // MARK: - Bookmark CRUD

    func addBookmark(to book: Book, position: String, chapter: String? = nil) -> Bookmark {
        let bookmark = Bookmark(book: book, position: position, chapter: chapter)
        modelContext.insert(bookmark)
        save()
        return bookmark
    }

    func fetchBookmarks(for book: Book) -> [Bookmark] {
        let descriptor = FetchDescriptor<Bookmark>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let bookmarks = (try? modelContext.fetch(descriptor)) ?? []
        return bookmarks.filter { $0.book?.id == book.id }
    }

    func deleteBookmark(_ bookmark: Bookmark) {
        modelContext.delete(bookmark)
        save()
    }

    // MARK: - Highlight CRUD

    func addHighlight(
        to book: Book,
        text: String,
        color: HighlightColor,
        startOffset: Int,
        endOffset: Int,
        chapter: String? = nil
    ) -> Highlight {
        let highlight = Highlight(
            book: book,
            selectedText: text,
            color: color,
            startOffset: startOffset,
            endOffset: endOffset,
            chapter: chapter
        )
        modelContext.insert(highlight)
        save()
        return highlight
    }

    func fetchHighlights(for book: Book) -> [Highlight] {
        let descriptor = FetchDescriptor<Highlight>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let highlights = (try? modelContext.fetch(descriptor)) ?? []
        return highlights.filter { $0.book?.id == book.id }
    }

    func updateHighlight(_ highlight: Highlight, note: String?) {
        highlight.note = note
        save()
    }

    func deleteHighlight(_ highlight: Highlight) {
        modelContext.delete(highlight)
        save()
    }

    // MARK: - Private

    private func save() {
        try? modelContext.save()
    }
}
