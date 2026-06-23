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
    var epubPageCount: Int = 0
    var epubCurrentPage: Int = 0
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

        let fileType = book.fileType
        let filePath = book.filePath
        BookLog.render.info("load: start fileType=\(fileType.rawValue, privacy: .public) path=\(filePath, privacy: .public)")

        do {
            let parsed = try await Task.detached(priority: .userInitiated) {
                try await BookParserRegistry.parseWithCache(
                    fileAt: URL(fileURLWithPath: filePath),
                    type: fileType
                )
            }.value
            BookLog.render.info("load: parsed title=\(parsed.title, privacy: .public) chapters=\(parsed.chapters.count) renderer=\(String(describing: parsed.renderer), privacy: .public)")
            apply(parsed)
        } catch {
            BookLog.render.error("load: failed fileType=\(fileType.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            self.loadError = error.localizedDescription
        }
    }

    private func apply(_ parsed: ParsedBook) {
        switch parsed.renderer {
        case .html:
            if parsed.chapters.isEmpty {
                BookLog.render.error("apply: parsed book has 0 chapters, marking as loadError to avoid infinite loading")
                self.loadError = "解析成功但未提取到任何页面，可能是该 MOBI 文件格式不被支持，请尝试安装 calibre 作为兜底转换器。"
                return
            }
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
            self.epubCurrentPage = 0
            self.epubPageCount = 0
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

    func updateEPUBProgress(_ metrics: EPUBPageMetrics) {
        epubCurrentPage = metrics.currentPage + 1
        epubPageCount = metrics.totalPages
        if metrics.chapterIndex >= 0, metrics.chapterIndex < chapters.count {
            currentChapter = metrics.chapterIndex
        }
        progress = EPUBProgressPolicy.overallProgress(
            currentPage: metrics.currentPage,
            totalPages: metrics.totalPages
        )
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
            return epubPageCount > 0 ? epubPageCount : chapters.count
        case .pdf:
            return pdfPageCount
        }
    }

    var displayCurrentPage: Int {
        switch book.fileType {
        case .epub, .mobi:
            return epubCurrentPage > 0 ? epubCurrentPage : currentChapter + 1
        case .pdf:
            return pdfCurrentPage
        }
    }

    var currentTitle: String {
        if book.fileType == .pdf {
            return book.title
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

    private var searchTask: Task<Void, Never>?

    func searchPDF(_ query: String) {
        searchTask?.cancel()
        guard book.fileType == .pdf, let doc = pdfDocument, !query.isEmpty else {
            pdfSearchResults = []
            return
        }
        pdfSearchResults = []
        let task = Task.detached(priority: .userInitiated) {
            Self.findInPDF(doc: doc, query: query)
        }
        searchTask = Task {
            let results = await task.value
            guard !Task.isCancelled else { return }
            pdfSearchResults = results
        }
    }

    func searchEPUB(_ query: String) async -> [EPUBSearchResult] {
        let chapters = self.chapters
        guard !query.isEmpty, !chapters.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) {
            var results: [EPUBSearchResult] = []
            for (index, chapter) in chapters.enumerated() {
                guard !Task.isCancelled else { return [] }
                let plainText = chapter.htmlContent
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                if plainText.range(of: query, options: .caseInsensitive) != nil {
                    let snippet = Self.makeSnippet(from: plainText, query: query)
                    results.append(EPUBSearchResult(
                        chapterTitle: chapter.title,
                        chapterIndex: index,
                        snippet: snippet
                    ))
                    if results.count >= 200 { break }
                }
            }
            return results
        }.value
    }

    struct EPUBSearchResult: Identifiable {
        let id = UUID()
        let chapterTitle: String
        let chapterIndex: Int
        let snippet: String
    }

    nonisolated private static func findInPDF(
        doc: PDFDocument,
        query: String
    ) -> [(title: String, pageIndex: Int, snippet: String)] {
        let selections = doc.findString(query, withOptions: .caseInsensitive)
        var seen = Set<Int>()
        var results: [(title: String, pageIndex: Int, snippet: String)] = []
        for sel in selections {
            guard let page = sel.pages.first else { continue }
            let idx = doc.index(for: page)
            guard idx >= 0, !seen.contains(idx) else { continue }
            seen.insert(idx)
            let pageText = (page.string ?? "").replacingOccurrences(of: "\n", with: " ")
            let snippet = Self.makeSnippet(from: pageText, query: query)
            results.append((title: "第 \(idx + 1) 页", pageIndex: idx, snippet: snippet))
            if results.count >= 200 { break }
        }
        return results
    }

    nonisolated private static func makeSnippet(from text: String, query: String) -> String {
        guard let range = text.range(of: query, options: .caseInsensitive) else {
            return String(text.prefix(80))
        }
        let start = text.index(range.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 30, limitedBy: text.endIndex) ?? text.endIndex
        let prefix = start == text.startIndex ? "" : "..."
        let suffix = end == text.endIndex ? "" : "..."
        return prefix + String(text[start..<end]) + suffix
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
