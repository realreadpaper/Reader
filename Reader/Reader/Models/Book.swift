import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String?
    var coverPath: String?
    var filePath: String
    var fileTypeRaw: String = FileType.epub.rawValue
    var lastRead: Date?
    var progress: Double
    var isFavorite: Bool
    var addedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    var bookmarks: [Bookmark]

    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    var highlights: [Highlight]

    var fileType: FileType {
        get { FileType(rawValue: fileTypeRaw) ?? .epub }
        set { fileTypeRaw = newValue.rawValue }
    }

    init(
        title: String,
        author: String? = nil,
        coverPath: String? = nil,
        filePath: String,
        fileType: FileType
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.coverPath = coverPath
        self.filePath = filePath
        self.fileTypeRaw = fileType.rawValue
        self.lastRead = nil
        self.progress = 0.0
        self.isFavorite = false
        self.addedAt = Date()
        self.bookmarks = []
        self.highlights = []
    }
}
