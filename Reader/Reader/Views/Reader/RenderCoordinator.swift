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
    private var restoreGuard: ProgressRestoreGuard

    init(book: Book, storageService: StorageService) {
        self.book = book
        self.storageService = storageService
        self.progress = book.progress
        self.restoreGuard = ProgressRestoreGuard(savedProgress: book.progress)
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
        case .markdown, .plaintext:
            if parsed.chapters.isEmpty {
                self.loadError = "文件内容为空"
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
        }
    }

    func updatePDFProgress(currentPage: Int, totalPages: Int) {
        pdfCurrentPage = currentPage + 1
        pdfPageCount = totalPages
        let p = totalPages > 0 ? Double(currentPage + 1) / Double(totalPages) : 0
        guard restoreGuard.shouldAcceptReportedProgress(p) else { return }
        progress = p
        scheduleProgressSave()
    }

    func updateEPUBProgress(_ metrics: EPUBPageMetrics) {
        epubCurrentPage = metrics.currentPage + 1
        epubPageCount = metrics.totalPages
        if metrics.chapterIndex >= 0, metrics.chapterIndex < chapters.count {
            currentChapter = metrics.chapterIndex
        }
        let p = EPUBProgressPolicy.overallProgress(
            currentPage: metrics.currentPage,
            totalPages: metrics.totalPages
        )
        guard restoreGuard.shouldAcceptReportedProgress(p) else { return }
        progress = p
        scheduleProgressSave()
    }

    func updateScrollableProgress(_ value: Double) {
        let p = max(0, min(1, value))
        guard restoreGuard.shouldAcceptReportedProgress(p) else { return }
        progress = p
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
        case .epub, .mobi, .txt, .md:
            return epubPageCount > 0 ? epubPageCount : chapters.count
        case .pdf:
            return pdfPageCount
        }
    }

    var displayCurrentPage: Int {
        switch book.fileType {
        case .epub, .mobi, .txt, .md:
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
        let normalizedQuery = Self.normalizedSearchText(query)
        guard !normalizedQuery.isEmpty, !chapters.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) {
            var results: [EPUBSearchResult] = []
            for (index, chapter) in chapters.enumerated() {
                guard !Task.isCancelled else { return [] }
                let plainText = Self.visibleText(fromEPUBHTML: chapter.htmlContent)
                if plainText.range(of: normalizedQuery, options: .caseInsensitive) != nil {
                    let snippet = Self.makeSnippet(from: plainText, query: normalizedQuery)
                    results.append(EPUBSearchResult(
                        chapterTitle: chapter.title,
                        chapterIndex: index,
                        snippet: snippet,
                        query: normalizedQuery
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
        let query: String
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

    nonisolated private static func visibleText(fromEPUBHTML html: String) -> String {
        var text = EPUBScripts.extractBodyContent(from: html)
        text = text.replacingOccurrences(
            of: #"<!--[\s\S]*?-->"#,
            with: " ",
            options: .regularExpression
        )
        for tag in ["script", "style", "noscript", "svg"] {
            text = text.replacingOccurrences(
                of: #"(?i)<\#(tag)\b[\s\S]*?</\#(tag)\s*>"#,
                with: " ",
                options: .regularExpression
            )
        }
        text = text.replacingOccurrences(
            of: #"(?i)<br\b[^>]*>|</(p|div|section|article|h[1-6]|li|tr|td|th|blockquote)\s*>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = decodeHTMLEntities(in: text)
        return normalizedSearchText(text)
    }

    nonisolated private static func normalizedSearchText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: #"[\s\p{Z}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func decodeHTMLEntities(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&(#x[0-9A-Fa-f]+|#[0-9]+|[A-Za-z][A-Za-z0-9]+);"#) else {
            return text
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        for match in regex.matches(in: text, range: nsRange).reversed() {
            guard let fullRange = Range(match.range(at: 0), in: text),
                  let entityRange = Range(match.range(at: 1), in: text) else { continue }
            let entity = String(text[entityRange])
            guard let decoded = decodedHTMLEntity(entity) else { continue }
            result.replaceSubrange(fullRange, with: decoded)
        }
        return result
    }

    nonisolated private static func decodedHTMLEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            guard let value = UInt32(entity.dropFirst(2), radix: 16),
                  let scalar = UnicodeScalar(value) else { return nil }
            return String(scalar)
        }
        if entity.hasPrefix("#") {
            guard let value = UInt32(entity.dropFirst(), radix: 10),
                  let scalar = UnicodeScalar(value) else { return nil }
            return String(scalar)
        }

        switch entity.lowercased() {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return " "
        case "ensp", "emsp", "thinsp": return " "
        case "ndash": return "-"
        case "mdash": return "-"
        case "lsquo", "rsquo": return "'"
        case "ldquo", "rdquo": return "\""
        case "hellip": return "..."
        case "middot": return "·"
        default: return nil
        }
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
        storageService.stageProgress(book, progress: value)

        progressSaveTimer?.invalidate()
        let book = self.book
        let storage = self.storageService
        progressSaveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            Task { @MainActor in
                storage.updateProgress(book, progress: value)
            }
        }
    }

    func flushProgressSave() {
        progressSaveTimer?.invalidate()
        progressSaveTimer = nil
        storageService.updateProgress(book, progress: progress)
    }
}

struct ProgressRestoreGuard {
    private let savedProgress: Double
    private var hasReachedSavedProgress: Bool

    init(savedProgress: Double) {
        self.savedProgress = max(0, min(1, savedProgress))
        self.hasReachedSavedProgress = savedProgress <= 0.001
    }

    mutating func shouldAcceptReportedProgress(_ reportedProgress: Double) -> Bool {
        let reported = max(0, min(1, reportedProgress))
        guard !hasReachedSavedProgress else { return true }

        if reported + 0.01 >= savedProgress {
            hasReachedSavedProgress = true
            return true
        }

        return false
    }
}
