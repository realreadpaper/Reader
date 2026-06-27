import Foundation
import PDFKit

struct ParsedBook {
    let title: String
    let author: String?
    let coverImage: Data?

    let chapters: [ParsedChapter]
    let toc: [ParsedTOCEntry]

    let resourceDirectory: URL?
    let renderer: RendererKind
    let pdfDocument: PDFDocument?
    let resourceOwner: ParsedResourceDirectoryOwner?

    init(
        title: String,
        author: String?,
        coverImage: Data?,
        chapters: [ParsedChapter],
        toc: [ParsedTOCEntry],
        resourceDirectory: URL?,
        renderer: RendererKind,
        pdfDocument: PDFDocument?,
        resourceOwner: ParsedResourceDirectoryOwner? = nil
    ) {
        self.title = title
        self.author = author
        self.coverImage = coverImage
        self.chapters = chapters
        self.toc = toc
        self.resourceDirectory = resourceDirectory
        self.renderer = renderer
        self.pdfDocument = pdfDocument
        self.resourceOwner = resourceOwner
    }
}

final class ParsedResourceDirectoryOwner {
    let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    deinit {
        try? fileManager.removeItem(at: directory)
    }
}

struct ParsedChapter {
    let title: String
    let bodyHTML: String
    let sourcePath: String
    var rawMarkdown: String? = nil
}

struct ParsedTOCEntry {
    let title: String
    let chapterIndex: Int
}

enum RendererKind {
    case html
    case pdfKit
    case markdown
    case plaintext
}

protocol BookParser {
    func parse(fileAt url: URL) async throws -> ParsedBook
}

enum BookParserRegistry {
    private static let flightStore = BookParseFlightStore()

    static func parser(for type: FileType) -> BookParser {
        switch type {
        case .epub: return EPUBParser()
        case .mobi: return MOBIParser()
        case .pdf:  return PDFParser()
        case .txt:  return TXTParser()
        case .md:   return MDParser()
        case .azw3, .azw: return KindleParser()
        }
    }

    static func parseWithCache(fileAt url: URL, type: FileType) async throws -> ParsedBook {
        try await parseWithCache(fileAt: url, type: type, parser: parser(for: type))
    }

    static func parseWithCache(fileAt url: URL, type: FileType, parser: BookParser) async throws -> ParsedBook {
        if type == .pdf {
            return try await parser.parse(fileAt: url)
        }

        if type != .pdf, let cached = BookParseCache.shared.load(from: url) {
            BookLog.parsing.info("parseWithCache: cache hit path=\(url.lastPathComponent, privacy: .public)")
            return cached
        }

        guard let key = BookParseCache.shared.cacheKey(for: url) else {
            BookLog.parsing.info("parseWithCache: cache unavailable, parsing path=\(url.lastPathComponent, privacy: .public)")
            let parsed = try await parser.parse(fileAt: url)
            BookParseCache.shared.save(parsed, for: url)
            return BookParseCache.shared.load(from: url) ?? parsed
        }

        return try await flightStore.value(for: key) {
            if let cached = BookParseCache.shared.load(from: url) {
                BookLog.parsing.info("parseWithCache: cache filled while waiting path=\(url.lastPathComponent, privacy: .public)")
                return cached
            }

            BookLog.parsing.info("parseWithCache: cache miss, parsing path=\(url.lastPathComponent, privacy: .public)")
            let parsed = try await parser.parse(fileAt: url)
            BookParseCache.shared.save(parsed, for: url)

            if let cached = BookParseCache.shared.load(from: url) {
                BookLog.parsing.info("parseWithCache: saved parse cache path=\(url.lastPathComponent, privacy: .public)")
                return cached
            }

            return parsed
        }
    }
}

private actor BookParseFlightStore {
    private var tasks: [String: Task<ParsedBook, Error>] = [:]

    func value(for key: String, operation: @escaping () async throws -> ParsedBook) async throws -> ParsedBook {
        if let task = tasks[key] {
            return try await task.value
        }

        let task = Task {
            try await operation()
        }
        tasks[key] = task

        do {
            let value = try await task.value
            tasks[key] = nil
            return value
        } catch {
            tasks[key] = nil
            throw error
        }
    }
}

enum BookParseError: Error, LocalizedError {
    case unsupportedFormat(detail: String)
    case corruptedFile(detail: String)
    case calibreNotInstalled
    case calibreConversionFailed(stderr: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let d):
            return "暂不支持的格式：\(d)"
        case .corruptedFile(let d):
            return "文件损坏：\(d)"
        case .calibreNotInstalled:
            return "原生解析不支持该格式，且未检测到 calibre。请安装 calibre 后重试。"
        case .calibreConversionFailed(let stderr):
            return "calibre 转换失败：\(stderr)"
        }
    }
}
