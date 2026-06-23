import Foundation
import SwiftData

@Model
final class Highlight {
    var id: UUID
    var book: Book?
    var selectedText: String
    var color: HighlightColor
    var startOffset: Int
    var endOffset: Int
    var chapter: String?
    var note: String?
    var createdAt: Date

    init(
        book: Book?,
        selectedText: String,
        color: HighlightColor,
        startOffset: Int,
        endOffset: Int,
        chapter: String? = nil,
        note: String? = nil
    ) {
        self.id = UUID()
        self.book = book
        self.selectedText = selectedText
        self.color = color
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.chapter = chapter
        self.note = note
        self.createdAt = Date()
    }
}
