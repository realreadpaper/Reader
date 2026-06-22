import Foundation
import SwiftData

@Observable
final class StorageService {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        self.modelContainer = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: config
        )
        self.modelContext = modelContainer.mainContext
    }

    private init(container: ModelContainer) {
        self.modelContainer = container
        self.modelContext = container.mainContext
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

    func fetchRecentBooks(limit: Int = 10) -> [Book] {
        let descriptor = FetchDescriptor<Book>(
            sortBy: [SortDescriptor(\.lastRead, order: .reverse)],
            fetchLimit: limit
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchFavoriteBooks() -> [Book] {
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
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
            predicate: #Predicate<Bookmark> { $0.book?.id == book.id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
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
            predicate: #Predicate<Highlight> { $0.book?.id == book.id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
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

    // MARK: - Preview

    static var preview: StorageService {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: config
        )
        let service = StorageService(container: container)
        return service
    }
}
