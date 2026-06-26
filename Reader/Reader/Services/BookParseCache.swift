import Foundation
import CryptoKit

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
    var rawMarkdown: String? = nil
}

struct CachedTOCEntry: Codable {
    let title: String
    let chapterIndex: Int
}

final class BookParseCache {
    static let shared = BookParseCache()
    private static let cacheFormatVersion = "text-md-rawmd-v10-no-prev"

    private let cacheDir: URL
    private let resourcesDir: URL
    private let fileManager = FileManager.default

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("ParseCache", isDirectory: true)
        resourcesDir = appSupport.appendingPathComponent("Reader/Resources", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
    }

    func cacheKey(for url: URL) -> String? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }
        let sizeStr = String(size)
        let dateStr = String(modDate.timeIntervalSince1970)
        let pathStr = url.standardizedFileURL.path
        let raw = "\(Self.cacheFormatVersion)-\(pathStr)-\(sizeStr)-\(dateStr)"
        guard let data = raw.data(using: .utf8) else { return nil }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(Self.cacheFormatVersion)-\(hex)"
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
            ParsedChapter(title: $0.title, bodyHTML: $0.bodyHTML, sourcePath: $0.sourcePath, rawMarkdown: $0.rawMarkdown)
        }
        let toc = cached.toc.map {
            ParsedTOCEntry(title: $0.title, chapterIndex: $0.chapterIndex)
        }
        let renderer: RendererKind
        switch cached.rendererRaw {
        case "pdfKit": renderer = .pdfKit
        case "markdown": renderer = .markdown
        case "plaintext": renderer = .plaintext
        default: renderer = .html
        }
        let resourceDir: URL?
        if let resourceDirectoryPath = cached.resourceDirectoryPath {
            guard fileManager.fileExists(atPath: resourceDirectoryPath) else {
                try? fileManager.removeItem(at: cacheFile)
                return nil
            }
            resourceDir = URL(fileURLWithPath: resourceDirectoryPath)
        } else {
            resourceDir = nil
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

        let resourceDirectory = persistResourceDirectory(parsed.resourceDirectory, key: key)
        let cached = CachedBook(
            title: parsed.title,
            author: parsed.author,
            coverImage: parsed.coverImage,
            chapters: parsed.chapters.map {
                CachedChapter(title: $0.title, bodyHTML: $0.bodyHTML, sourcePath: $0.sourcePath, rawMarkdown: $0.rawMarkdown)
            },
            toc: parsed.toc.map {
                CachedTOCEntry(title: $0.title, chapterIndex: $0.chapterIndex)
            },
            resourceDirectoryPath: resourceDirectory?.path,
            rendererRaw: rawRendererName(parsed.renderer),
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
        try? fileManager.removeItem(at: persistentResourceDirectory(forKey: key))
    }

    func clearAll() {
        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.removeItem(at: resourcesDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
    }

    var cacheSize: Int {
        directorySize(cacheDir) + directorySize(resourcesDir)
    }

    private func rawRendererName(_ renderer: RendererKind) -> String {
        switch renderer {
        case .html: return "html"
        case .pdfKit: return "pdfKit"
        case .markdown: return "markdown"
        case .plaintext: return "plaintext"
        }
    }

    private func persistResourceDirectory(_ source: URL?, key: String) -> URL? {
        guard let source,
              fileManager.fileExists(atPath: source.path) else { return nil }

        let destination = persistentResourceDirectory(forKey: key)
        do {
            try? fileManager.removeItem(at: destination)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: destination)
            return nil
        }
    }

    private func persistentResourceDirectory(forKey key: String) -> URL {
        resourcesDir.appendingPathComponent(key, isDirectory: true)
    }

    private func directorySize(_ directory: URL) -> Int {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total = 0
        for case let fileURL as URL in enumerator {
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}
