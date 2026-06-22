import Foundation

struct EPUBChapter {
    let title: String
    let htmlContent: String
    let fileName: String
}

struct EPUBMetadata {
    let title: String
    let author: String?
    let chapters: [EPUBChapter]
    let tocEntries: [(title: String, chapterIndex: Int)]
}

final class EPUBParser {

    func parse(fileAt url: URL) throws -> EPUBMetadata {
        let unzipDir = try unzipEPUB(at: url)
        defer { try? FileManager.default.removeItem(at: unzipDir) }

        let opfURL = try findOPF(in: unzipDir)
        let metadata = try parseOPF(at: opfURL)
        let containerDir = opfURL.deletingLastPathComponent()

        let chapters = try parseChapters(
            manifest: metadata.manifest,
            containerDir: containerDir
        )

        let tocEntries = chapters.enumerated().map { (index, chapter) in
            (title: chapter.title, chapterIndex: index)
        }

        return EPUBMetadata(
            title: metadata.title,
            author: metadata.author,
            chapters: chapters,
            tocEntries: tocEntries
        )
    }

    private func unzipEPUB(at url: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", url.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw EPUBError.unzipFailed
        }
        return tempDir
    }

    private func findOPF(in directory: URL) throws -> URL {
        let containerPath = directory
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")

        let containerXML = try String(contentsOf: containerPath, encoding: .utf8)

        guard let range = containerXML.range(of: #"full-path"\s*=\s*"[^"]*""#),
              let pathRange = containerXML[range].range(of: #""[^"]*"$"#) else {
            throw EPUBError.invalidContainer
        }

        var fullPath = String(containerXML[pathRange])
        fullPath.removeFirst()
        fullPath.removeLast()

        return directory.appendingPathComponent(fullPath)
    }

    private struct OPFResult {
        let title: String
        let author: String?
        let manifest: [(id: String, href: String, mediaType: String)]
        let spineOrder: [String]
    }

    private func parseOPF(at url: URL) throws -> OPFResult {
        let opfString = try String(contentsOf: url, encoding: .utf8)

        let title = extractTag("dc:title", from: opfString) ?? "Untitled"
        let author = extractTag("dc:creator", from: opfString)

        let manifestPattern = #"<item\s+id="([^"]*)"\s+href="([^"]*)"\s+media-type="([^"]*)""#
        var manifest: [(id: String, href: String, mediaType: String)] = []
        for match in opfString.matches(of: manifestPattern) {
            manifest.append((
                id: String(match.1),
                href: String(match.2),
                mediaType: String(match.3)
            ))
        }

        let spinePattern = #"<itemref\s+idref="([^"]*)""#
        let spineOrder = opfString.matches(of: spinePattern).map { String($0.1) }

        return OPFResult(title: title, author: author, manifest: manifest, spineOrder: spineOrder)
    }

    private func extractTag(_ tag: String, from xml: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]*)</\(tag)>"
        guard let range = xml.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        var content = String(xml[range])
        content = content.replacingOccurrences(of: "<\(tag)[^>]*>", with: "", options: .regularExpression)
        content = content.replacingOccurrences(of: "</\(tag)>", with: "")
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseChapters(
        manifest: [(id: String, href: String, mediaType: String)],
        containerDir: URL
    ) throws -> [EPUBChapter] {
        let htmlItems = manifest.filter { $0.mediaType.contains("html") || $0.mediaType.contains("xhtml") }

        return try htmlItems.map { item in
            let fileURL = containerDir.appendingPathComponent(item.href)
            let html = try String(contentsOf: fileURL, encoding: .utf8)
            let title = extractTitle(from: html) ?? item.href
            return EPUBChapter(title: title, htmlContent: html, fileName: item.href)
        }
    }

    private func extractTitle(from html: String) -> String? {
        if let titleRange = html.range(of: "<title[^>]*>([^<]*)</title>", options: .regularExpression) {
            var title = String(html[titleRange])
            title = title.replacingOccurrences(of: "<title[^>]*>", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "</title>", with: "")
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let h1Range = html.range(of: "<h1[^>]*>([^<]*)</h1>", options: .regularExpression) {
            var title = String(html[h1Range])
            title = title.replacingOccurrences(of: "<h1[^>]*>", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "</h1>", with: "")
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

enum EPUBError: Error, LocalizedError {
    case unzipFailed
    case invalidContainer
    case missingOPF

    var errorDescription: String? {
        switch self {
        case .unzipFailed: return "无法解压 EPUB 文件"
        case .invalidContainer: return "EPUB container.xml 格式无效"
        case .missingOPF: return "未找到 OPF 文件"
        }
    }
}
