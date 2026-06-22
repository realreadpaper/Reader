import Foundation

@Observable
final class RenderCoordinator {
    var book: Book
    var currentChapter: Int = 0
    var progress: Double = 0
    var epubMetadata: EPUBMetadata?
    var showTOC: Bool = false
    var showSearch: Bool = false
    var showFontPanel: Bool = false

    init(book: Book) {
        self.book = book
    }

    func loadEPUB() async {
        guard book.fileType == .epub else { return }
        let parser = EPUBParser()
        if let metadata = try? parser.parse(fileAt: URL(fileURLWithPath: book.filePath)) {
            self.epubMetadata = metadata
        }
    }

    func loadMOBI() async {
        guard book.fileType == .mobi else { return }
        let converter = MOBIConverter()
        if converter.isAvailable,
           let epubURL = try? await converter.convertToEPUB(mobiURL: URL(fileURLWithPath: book.filePath)) {
            let parser = EPUBParser()
            if let metadata = try? parser.parse(fileAt: epubURL) {
                self.epubMetadata = metadata
            }
        }
    }

    var chapters: [EPUBChapter] {
        epubMetadata?.chapters ?? []
    }

    var tocEntries: [(title: String, chapterIndex: Int)] {
        epubMetadata?.tocEntries ?? []
    }

    func navigateToChapter(_ index: Int) {
        guard index < chapters.count else { return }
        currentChapter = index
    }
}
