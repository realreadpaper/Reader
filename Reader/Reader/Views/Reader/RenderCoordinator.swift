import Foundation
import PDFKit

@MainActor
@Observable
final class RenderCoordinator {
    let book: Book
    let storageService: StorageService

    var currentChapter: Int = 0
    var progress: Double = 0
    var epubMetadata: EPUBMetadata?
    var pdfDocument: PDFDocument?
    var pdfPageCount: Int = 0
    var pdfCurrentPage: Int = 0
    var pdfOutline: [(title: String, pageIndex: Int)] = []
    var pdfSearchResults: [(title: String, pageIndex: Int, snippet: String)] = []

    var showTOC: Bool = false
    var showSearch: Bool = false
    var showFontPanel: Bool = false
    var showAnnotations: Bool = false

    var loadError: String?
    var isLoading: Bool = false

    private var lastReportedProgress: Double = -1
    private var progressSaveTimer: Timer?

    init(book: Book, storageService: StorageService) {
        self.book = book
        self.storageService = storageService
        self.progress = book.progress
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let parser = BookParserRegistry.parser(for: book.fileType)
            let filePath = book.filePath
            let parsed = try await Task.detached(priority: .userInitiated) {
                try await parser.parse(fileAt: URL(fileURLWithPath: filePath))
            }.value
            apply(parsed)
        } catch {
            self.loadError = error.localizedDescription
        }
    }

    private func apply(_ parsed: ParsedBook) {
        switch parsed.renderer {
        case .html:
            let metadata = EPUBMetadata(
                title: parsed.title,
                author: parsed.author,
                chapters: parsed.chapters.map {
                    EPUBChapter(
                        title: $0.title,
                        htmlContent: $0.bodyHTML,
                        fileName: $0.sourcePath,
                        spineIndex: 0
                    )
                },
                tocEntries: parsed.toc.map {
                    EPUBTOCEntry(title: $0.title, chapterIndex: $0.chapterIndex)
                },
                resourceDirectory: parsed.resourceDirectory ?? FileManager.default.temporaryDirectory
            )
            self.epubMetadata = metadata
            self.currentChapter = min(currentChapter, max(0, metadata.chapters.count - 1))
        case .pdfKit:
            guard let doc = parsed.pdfDocument else {
                self.loadError = "PDF 加载失败"
                return
            }
            self.pdfDocument = doc
            self.pdfPageCount = doc.pageCount
            self.pdfOutline = buildPDFOutline(from: doc)
            if doc.pageCount > 0 {
                let restored = max(0, Int(progress * Double(doc.pageCount)) - 1)
                let clamped = min(restored, doc.pageCount - 1)
                self.pdfCurrentPage = clamped + 1
                self.progress = Double(clamped + 1) / Double(doc.pageCount)
            }
        }
    }

    func updatePDFProgress(currentPage: Int, totalPages: Int) {
        pdfCurrentPage = currentPage + 1
        pdfPageCount = totalPages
        let p = totalPages > 0 ? Double(currentPage + 1) / Double(totalPages) : 0
        progress = p
        scheduleProgressSave()
    }

    func updateEPUBProgress(_ value: Double) {
        progress = value
        scheduleProgressSave()
    }

    func navigateToChapter(_ index: Int) {
        if book.fileType == .pdf {
            guard index >= 0, index < pdfPageCount else { return }
            pdfCurrentPage = index + 1
            progress = pdfPageCount > 0 ? Double(index + 1) / Double(pdfPageCount) : 0
            scheduleProgressSave()
        } else {
            guard index >= 0, index < chapters.count else { return }
            currentChapter = index
            progress = 0
        }
    }

    var chapters: [EPUBChapter] {
        epubMetadata?.chapters ?? []
    }

    var resourceDirectory: URL? {
        epubMetadata?.resourceDirectory
    }

    var tocEntries: [EPUBTOCEntry] {
        if book.fileType == .pdf {
            return pdfOutline.map { EPUBTOCEntry(title: $0.title, chapterIndex: $0.pageIndex) }
        }
        return epubMetadata?.tocEntries ?? []
    }

    var totalChapters: Int {
        switch book.fileType {
        case .epub, .mobi:
            return chapters.count
        case .pdf:
            return pdfPageCount
        }
    }

    var currentTitle: String {
        if book.fileType == .pdf {
            return "第 \(pdfCurrentPage) 页 / 共 \(pdfPageCount) 页"
        }
        let entries = epubMetadata?.tocEntries ?? []
        if currentChapter >= 0 && currentChapter < entries.count {
            return entries[currentChapter].title
        }
        if !chapters.isEmpty && currentChapter < chapters.count {
            return chapters[currentChapter].title
        }
        return book.title
    }

    func searchPDF(_ query: String) {
        guard book.fileType == .pdf, let doc = pdfDocument, !query.isEmpty else {
            pdfSearchResults = []
            return
        }
        var results: [(title: String, pageIndex: Int, snippet: String)] = []
        let lower = query.lowercased()
        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex),
                  let text = page.string else { continue }
            if text.lowercased().contains(lower) {
                let snippet = makeSnippet(from: text, query: query)
                let title = "第 \(pageIndex + 1) 页"
                results.append((title: title, pageIndex: pageIndex, snippet: snippet))
                if results.count >= 200 { break }
            }
        }
        pdfSearchResults = results
    }

    private func makeSnippet(from text: String, query: String) -> String {
        guard let range = text.range(of: query, options: .caseInsensitive) else {
            return String(text.prefix(80))
        }
        let start = text.index(range.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 30, limitedBy: text.endIndex) ?? text.endIndex
        let snippet = String(text[start..<end])
        return "..." + snippet.replacingOccurrences(of: "\n", with: " ") + "..."
    }

    private func buildPDFOutline(from document: PDFDocument) -> [(title: String, pageIndex: Int)] {
        var result: [(title: String, pageIndex: Int)] = []
        guard let root = document.outlineRoot else {
            for i in 0..<document.pageCount {
                result.append((title: "第 \(i + 1) 页", pageIndex: i))
            }
            return result
        }
        collectOutline(outline: root, into: &result, document: document)
        if result.isEmpty {
            for i in 0..<document.pageCount {
                result.append((title: "第 \(i + 1) 页", pageIndex: i))
            }
        }
        return result
    }

    private func collectOutline(
        outline: PDFOutline,
        into result: inout [(title: String, pageIndex: Int)],
        document: PDFDocument
    ) {
        for i in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: i) else { continue }
            guard let dest = child.destination,
                  let destPage = dest.page else { continue }
            let idx = document.index(for: destPage)
            result.append((title: child.label ?? "第 \(idx + 1) 页", pageIndex: idx))
            if child.numberOfChildren > 0 {
                collectOutline(outline: child, into: &result, document: document)
            }
        }
    }

    private func scheduleProgressSave() {
        let value = progress
        if abs(value - lastReportedProgress) < 0.005 { return }
        lastReportedProgress = value

        progressSaveTimer?.invalidate()
        let book = self.book
        let storage = self.storageService
        progressSaveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            Task { @MainActor in
                storage.updateProgress(book, progress: value)
            }
        }
    }
}
