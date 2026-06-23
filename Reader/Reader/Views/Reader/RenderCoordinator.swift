import Foundation
import PDFKit

@Observable
final class RenderCoordinator {
    var book: Book
    var currentChapter: Int = 0
    var progress: Double = 0
    var epubMetadata: EPUBMetadata?
    var pdfDocument: PDFDocument?
    var pdfPageCount: Int = 0
    var pdfCurrentPage: Int = 0
    var showTOC: Bool = false
    var showSearch: Bool = false
    var showFontPanel: Bool = false
    var isLoading: Bool = false
    var loadError: String?

    init(book: Book) {
        self.book = book
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        switch book.fileType {
        case .epub:
            await loadEPUB()
        case .mobi:
            await loadMOBI()
        case .pdf:
            loadPDF()
        }
    }

    private func loadEPUB() async {
        let filePath = book.filePath
        let metadata: EPUBMetadata? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let parser = EPUBParser()
                let result = try? parser.parse(fileAt: URL(fileURLWithPath: filePath))
                continuation.resume(returning: result)
            }
        }
        if let metadata {
            self.epubMetadata = metadata
            self.currentChapter = 0
            self.progress = 0
        } else {
            self.loadError = "EPUB 解析失败"
        }
    }

    private func loadMOBI() async {
        let filePath = book.filePath
        let metadata: EPUBMetadata? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let converter = MOBIConverter()
                guard converter.isAvailable else {
                    continuation.resume(returning: nil)
                    return
                }
                guard let epubURL = try? converter.convertToEPUBSync(mobiURL: URL(fileURLWithPath: filePath)) else {
                    continuation.resume(returning: nil)
                    return
                }
                let parser = EPUBParser()
                let result = try? parser.parse(fileAt: epubURL)
                continuation.resume(returning: result)
            }
        }
        if let metadata {
            self.epubMetadata = metadata
            self.currentChapter = 0
            self.progress = 0
        } else {
            self.loadError = "MOBI 转换失败（需要安装 calibre）"
        }
    }

    private func loadPDF() {
        let url = URL(fileURLWithPath: book.filePath)
        guard let document = PDFDocument(url: url) else {
            self.loadError = "PDF 加载失败"
            return
        }
        self.pdfDocument = document
        self.pdfPageCount = document.pageCount
        self.pdfCurrentPage = 1
        self.progress = document.pageCount > 0 ? 1.0 / Double(document.pageCount) : 0
    }

    func updatePDFProgress(currentPage: Int, totalPages: Int) {
        pdfCurrentPage = currentPage + 1
        pdfPageCount = totalPages
        progress = totalPages > 0 ? Double(currentPage + 1) / Double(totalPages) : 0
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

    var pdfTocEntries: [(title: String, chapterIndex: Int)] {
        guard book.fileType == .pdf, pdfPageCount > 0 else { return [] }
        return (0..<pdfPageCount).map { pageIndex in
            (title: "第 \(pageIndex + 1) 页", chapterIndex: pageIndex)
        }
    }

    var totalChapters: Int {
        switch book.fileType {
        case .epub, .mobi:
            return tocEntries.count
        case .pdf:
            return pdfPageCount
        }
    }

    var currentTitle: String {
        if book.fileType == .pdf {
            return pdfPageCount > 0 ? "第 \(pdfCurrentPage) 页" : book.title
        }
        guard currentChapter < tocEntries.count else { return book.title }
        return tocEntries[currentChapter].title
    }

    func navigateToChapter(_ index: Int) {
        if book.fileType == .pdf {
            let clamped = max(0, min(index, max(0, pdfPageCount - 1)))
            pdfCurrentPage = clamped + 1
            progress = pdfPageCount > 0 ? Double(clamped + 1) / Double(pdfPageCount) : 0
        } else {
            guard index >= 0, index < chapters.count else { return }
            currentChapter = index
        }
    }
}
