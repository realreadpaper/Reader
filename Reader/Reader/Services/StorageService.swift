import Foundation
import SwiftData

@MainActor
@Observable
final class StorageService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Book CRUD

    func addBook(title: String, author: String? = nil, coverPath: String? = nil, filePath: String, fileType: FileType) -> Book {
        let book = Book(
            title: title,
            author: author,
            coverPath: coverPath,
            filePath: filePath,
            fileType: fileType
        )
        modelContext.insert(book)
        save()
        return book
    }

    func fetchBooks() -> [Book] {
        let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.lastRead, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchRecentBooks(limit: Int = 10) -> [Book] {
        var descriptor = FetchDescriptor<Book>(
            sortBy: [SortDescriptor(\.lastRead, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchFavoriteBooks() -> [Book] {
        let predicate = #Predicate<Book> { $0.isFavorite == true }
        let descriptor = FetchDescriptor<Book>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func updateBook(_ book: Book) {
        book.lastRead = Date()
        save()
    }

    func updateProgress(_ book: Book, progress: Double) {
        book.progress = max(0, min(1, progress))
        book.lastRead = Date()
        save()
    }

    func toggleFavorite(_ book: Book) {
        book.isFavorite.toggle()
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
        let bookID = book.id
        let predicate = #Predicate<Bookmark> { $0.book?.id == bookID }
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: predicate,
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
        let bookID = book.id
        let predicate = #Predicate<Highlight> { $0.book?.id == bookID }
        let descriptor = FetchDescriptor<Highlight>(
            predicate: predicate,
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
        do {
            try modelContext.save()
        } catch {
            print("StorageService save error: \(error)")
        }
    }
}
