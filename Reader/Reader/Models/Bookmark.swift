import Foundation
import SwiftData

@Model
final class Bookmark {
    var id: UUID
    var book: Book?
    var position: String
    var chapter: String?
    var note: String?
    var createdAt: Date

    init(
        book: Book?,
        position: String,
        chapter: String? = nil,
        note: String? = nil
    ) {
        self.id = UUID()
        self.book = book
        self.position = position
        self.chapter = chapter
        self.note = note
        self.createdAt = Date()
    }
}
