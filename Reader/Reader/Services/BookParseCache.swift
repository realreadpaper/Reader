import Foundation

struct CachedBook: Codable {
    let title: String
    let author: String?
    let coverImage: Data?
    let chapters: [CachedChapter]
    let toc: [CachedTOCEntry]
    let resourceDirectoryPath: String?
    let rendererRaw: String
    let cachedAt: Date
}

struct CachedChapter: Codable {
    let title: String
    let bodyHTML: String
    let sourcePath: String
}

struct CachedTOCEntry: Codable {
    let title: String
    let chapterIndex: Int
}

final class BookParseCache {
    static let shared = BookParseCache()
    private static let cacheFormatVersion = "html-pages-v2"

    private let cacheDir: URL
    private let fileManager = FileManager.default

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("ParseCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func cacheKey(for url: URL) -> String? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }
        let sizeStr = String(size)
        let dateStr = String(modDate.timeIntervalSince1970)
        let raw = "\(Self.cacheFormatVersion)-\(sizeStr)-\(dateStr)"
        return raw.data(using: .utf8)?.base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    func load(from url: URL) -> ParsedBook? {
        guard let key = cacheKey(for: url) else { return nil }
        let cacheFile = cacheDir.appendingPathComponent("\(key).json")
        guard fileManager.fileExists(atPath: cacheFile.path),
              let data = try? Data(contentsOf: cacheFile),
              let cached = try? JSONDecoder().decode(CachedBook.self, from: data) else {
            return nil
        }

        let chapters = cached.chapters.map {
            ParsedChapter(title: $0.title, bodyHTML: $0.bodyHTML, sourcePath: $0.sourcePath)
        }
        let toc = cached.toc.map {
            ParsedTOCEntry(title: $0.title, chapterIndex: $0.chapterIndex)
        }
        let renderer: RendererKind = cached.rendererRaw == "pdfKit" ? .pdfKit : .html
        let resourceDir: URL? = cached.resourceDirectoryPath.flatMap {
            fileManager.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil
        }

        return ParsedBook(
            title: cached.title,
            author: cached.author,
            coverImage: cached.coverImage,
            chapters: chapters,
            toc: toc,
            resourceDirectory: resourceDir,
            renderer: renderer,
            pdfDocument: nil
        )
    }

    func save(_ parsed: ParsedBook, for url: URL) {
        guard parsed.renderer != .pdfKit,
              let key = cacheKey(for: url) else { return }

        let cached = CachedBook(
            title: parsed.title,
            author: parsed.author,
            coverImage: parsed.coverImage,
            chapters: parsed.chapters.map {
                CachedChapter(title: $0.title, bodyHTML: $0.bodyHTML, sourcePath: $0.sourcePath)
            },
            toc: parsed.toc.map {
                CachedTOCEntry(title: $0.title, chapterIndex: $0.chapterIndex)
            },
            resourceDirectoryPath: parsed.resourceDirectory?.path,
            rendererRaw: parsed.renderer == .pdfKit ? "pdfKit" : "html",
            cachedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(cached) else { return }
        let cacheFile = cacheDir.appendingPathComponent("\(key).json")
        try? data.write(to: cacheFile, options: .atomic)
    }

    func invalidate(for url: URL) {
        guard let key = cacheKey(for: url) else { return }
        let cacheFile = cacheDir.appendingPathComponent("\(key).json")
        try? fileManager.removeItem(at: cacheFile)
    }

    func clearAll() {
        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    var cacheSize: Int {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
    }
}
