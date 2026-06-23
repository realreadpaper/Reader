import Foundation
import SwiftData

@Model
final class Highlight {
    var id: UUID
    var book: Book?
    var selectedText: String
    var colorRaw: String
    var startOffset: Int
    var endOffset: Int
    var chapter: String?
    var note: String?
    var createdAt: Date

    var color: HighlightColor {
        get { HighlightColor(rawValue: colorRaw) ?? .yellow }
        set { colorRaw = newValue.rawValue }
    }

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
        self.colorRaw = color.rawValue
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.chapter = chapter
        self.note = note
        self.createdAt = Date()
    }
}
