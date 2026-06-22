import Foundation
import PDFKit

@Observable
final class RenderCoordinator {
    var book: Book
    var currentChapter: Int = 0
    var progress: Double = 0
    var epubMetadata: EPUBMetadata?
    var pdfPageCount: Int = 0
    var pdfCurrentPage: Int = 0
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

    func loadPDF() {
        guard book.fileType == .pdf else { return }
        if let document = PDFDocument(url: URL(fileURLWithPath: book.filePath)) {
            pdfPageCount = document.pageCount
            pdfCurrentPage = document.pageCount > 0 ? 1 : 0
            progress = pdfPageCount > 0 ? 1.0 / Double(pdfPageCount) : 0
        }
    }

    var pdfTocEntries: [(title: String, chapterIndex: Int)] {
        guard book.fileType == .pdf, pdfPageCount > 0 else { return [] }
        return (0..<pdfPageCount).map { pageIndex in
            (title: "第 \(pageIndex + 1) 页", chapterIndex: pageIndex)
        }
    }

    func updatePDFProgress(currentPage: Int, totalPages: Int) {
        pdfCurrentPage = currentPage + 1
        pdfPageCount = totalPages
        progress = totalPages > 0 ? Double(currentPage) / Double(totalPages) : 0
    }

    var chapters: [EPUBChapter] {
        epubMetadata?.chapters ?? []
    }

    var tocEntries: [(title: String, chapterIndex: Int)] {
        if book.fileType == .pdf {
            return pdfTocEntries
        }
        return epubMetadata?.tocEntries ?? []
    }

    var totalChapters: Int {
        switch book.fileType {
        case .epub, .mobi:
            return tocEntries.count
        case .pdf:
            return pdfPageCount
        }
    }

    func navigateToChapter(_ index: Int) {
        if book.fileType == .pdf {
            pdfCurrentPage = index + 1
            progress = pdfPageCount > 0 ? Double(index) / Double(pdfPageCount) : 0
        } else {
            guard index < chapters.count else { return }
            currentChapter = index
        }
    }
}
