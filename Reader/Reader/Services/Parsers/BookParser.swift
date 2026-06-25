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
    static func parser(for type: FileType) -> BookParser {
        switch type {
        case .epub: return EPUBParser()
        case .mobi: return MOBIParser()
        case .pdf:  return PDFParser()
        case .txt:  return TXTParser()
        case .md:   return MDParser()
        }
    }

    static func parseWithCache(fileAt url: URL, type: FileType) async throws -> ParsedBook {
        if type != .pdf, let cached = BookParseCache.shared.load(from: url) {
            return cached
        }

        let parser = parser(for: type)
        let parsed = try await parser.parse(fileAt: url)

        if type != .pdf {
            BookParseCache.shared.save(parsed, for: url)
        }

        return parsed
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
            return "原生解析不支持该 MOBI 变体，且未检测到 calibre。请安装 calibre 后重试。"
        case .calibreConversionFailed(let stderr):
            return "calibre 转换失败：\(stderr)"
        }
    }
}
