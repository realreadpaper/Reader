import Foundation

struct EPUBChapter {
    let title: String
    let htmlContent: String
    let fileName: String
    let spineIndex: Int
}

struct EPUBMetadata {
    let title: String
    let author: String?
    let chapters: [EPUBChapter]
    let tocEntries: [EPUBTOCEntry]
    let resourceDirectory: URL
}

struct EPUBTOCEntry {
    let title: String
    let chapterIndex: Int
}

struct EPUBBookInfo {
    let title: String
    let author: String?
    let coverImageData: Data?
}

final class EPUBParser {

    struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String
        let properties: String
    }

    struct OPFResult {
        let title: String
        let author: String?
        let manifest: [ManifestItem]
        let spine: [String]
    }

    func parse(fileAt url: URL) throws -> EPUBMetadata {
        let unzipDir = try unzipEPUB(at: url)
        let opfURL = try findOPF(in: unzipDir)
        let opf = try parseOPF(at: opfURL)
        let containerDir = opfURL.deletingLastPathComponent()

        let chapters = try loadChapters(
            manifest: opf.manifest,
            spine: opf.spine,
            containerDir: containerDir
        )

        let tocEntries = try buildTOC(
            manifest: opf.manifest,
            spine: opf.spine,
            chapters: chapters,
            containerDir: containerDir
        )

        return EPUBMetadata(
            title: opf.title,
            author: opf.author,
            chapters: chapters,
            tocEntries: tocEntries,
            resourceDirectory: containerDir
        )
    }

    func parseMetadata(fileAt url: URL) throws -> EPUBBookInfo {
        let unzipDir = try unzipEPUB(at: url)
        defer { try? FileManager.default.removeItem(at: unzipDir) }

        let opfURL = try findOPF(in: unzipDir)
        let opf = try parseOPF(at: opfURL)
        let containerDir = opfURL.deletingLastPathComponent()
        let coverData = extractCoverData(manifest: opf.manifest, containerDir: containerDir)

        return EPUBBookInfo(
            title: opf.title,
            author: opf.author,
            coverImageData: coverData
        )
    }

    func extractCoverImage(fileAt url: URL) -> Data? {
        guard let unzipDir = try? unzipEPUB(at: url) else { return nil }
        defer { try? FileManager.default.removeItem(at: unzipDir) }

        guard let opfURL = try? findOPF(in: unzipDir),
              let opf = try? parseOPF(at: opfURL) else { return nil }
        let containerDir = opfURL.deletingLastPathComponent()
        return extractCoverData(manifest: opf.manifest, containerDir: containerDir)
    }

    // MARK: - Unzip

    private func unzipEPUB(at url: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-qq", url.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw EPUBError.unzipFailed
        }
        return tempDir
    }

    // MARK: - container.xml → OPF path

    private func findOPF(in directory: URL) throws -> URL {
        let containerPath = directory
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")

        guard let containerXML = try? String(contentsOf: containerPath, encoding: .utf8) else {
            throw EPUBError.invalidContainer
        }

        guard let range = containerXML.range(
            of: #"full-path\s*=\s*"[^"]*""#,
            options: .regularExpression
        ) else {
            throw EPUBError.invalidContainer
        }

        let match = String(containerXML[range])
        guard let firstQuote = match.firstIndex(of: "\""),
              let lastQuote = match.lastIndex(of: "\""),
              firstQuote < lastQuote else {
            throw EPUBError.invalidContainer
        }
        let fullPath = String(match[match.index(after: firstQuote)..<lastQuote])
        return directory.appendingPathComponent(fullPath)
    }

    // MARK: - OPF parsing

    func parseOPF(at url: URL) throws -> OPFResult {
        let delegate = OPFDelegate()
        let parser = XMLParser(contentsOf: url)
        parser?.delegate = delegate
        parser?.shouldProcessNamespaces = true
        guard let parser, parser.parse() else {
            throw EPUBError.invalidOPF
        }
        if let error = parser.parserError {
            throw error
        }
        return OPFResult(
            title: delegate.title ?? "Untitled",
            author: delegate.author,
            manifest: delegate.manifest,
            spine: delegate.spine
        )
    }

    // MARK: - Chapter loading

    private func loadChapters(
        manifest: [ManifestItem],
        spine: [String],
        containerDir: URL
    ) throws -> [EPUBChapter] {
        let manifestByID = Dictionary(manifest.map { ($0.id, $0) }) { first, _ in first }

        var chapters: [EPUBChapter] = []
        for (index, idref) in spine.enumerated() {
            guard let item = manifestByID[idref] else { continue }
            guard item.mediaType.contains("html") || item.mediaType.contains("xml") else { continue }
            let fileURL = containerDir.appendingPathComponent(item.href)
            let html = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let title = extractHTMLTitle(from: html) ?? item.href
            chapters.append(EPUBChapter(
                title: title,
                htmlContent: html,
                fileName: item.href,
                spineIndex: index
            ))
        }

        if chapters.isEmpty {
            let htmlItems = manifest.filter {
                $0.mediaType.contains("html") || $0.mediaType.contains("xml")
            }
            for (index, item) in htmlItems.enumerated() {
                let fileURL = containerDir.appendingPathComponent(item.href)
                let html = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                let title = extractHTMLTitle(from: html) ?? item.href
                chapters.append(EPUBChapter(
                    title: title,
                    htmlContent: html,
                    fileName: item.href,
                    spineIndex: index
                ))
            }
        }
        return chapters
    }

    // MARK: - TOC

    private func buildTOC(
        manifest: [ManifestItem],
        spine: [String],
        chapters: [EPUBChapter],
        containerDir: URL
    ) throws -> [EPUBTOCEntry] {
        if let navItem = manifest.first(where: { $0.properties.contains("nav") }) {
            let navURL = containerDir.appendingPathComponent(navItem.href)
            if let entries = parseNavTOC(at: navURL) {
                return mapTOCToSpine(entries: entries, chapters: chapters)
            }
        }

        if let ncxItem = manifest.first(where: { $0.mediaType.contains("dtbncx") }) {
            let ncxURL = containerDir.appendingPathComponent(ncxItem.href)
            if let entries = parseNCXTOC(at: ncxURL) {
                return mapTOCToSpine(entries: entries, chapters: chapters)
            }
        }

        return chapters.enumerated().map { (i, ch) in
            EPUBTOCEntry(title: ch.title, chapterIndex: i)
        }
    }

    private func mapTOCToSpine(
        entries: [(title: String, src: String)],
        chapters: [EPUBChapter]
    ) -> [EPUBTOCEntry] {
        let chapterByFile: [String: Int] = Dictionary(
            chapters.map { ($0.fileName, $0.spineIndex) }
        ) { first, _ in first }

        var seen = Set<Int>()
        var result: [EPUBTOCEntry] = []

        for entry in entries {
            let filePart = entry.src.split(separator: "#").first.map(String.init) ?? entry.src
            guard let idx = chapterByFile[filePart], !seen.contains(idx) else { continue }
            seen.insert(idx)
            result.append(EPUBTOCEntry(title: entry.title, chapterIndex: idx))
        }

        if result.isEmpty {
            return chapters.enumerated().map { (i, ch) in
                EPUBTOCEntry(title: ch.title, chapterIndex: i)
            }
        }
        return result
    }

    private func parseNavTOC(at url: URL) -> [(title: String, src: String)]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let delegate = NavTOCDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.entries
    }

    private func parseNCXTOC(at url: URL) -> [(title: String, src: String)]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let delegate = NCXTOCDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        return delegate.entries
    }

    // MARK: - Cover

    private func extractCoverData(manifest: [ManifestItem], containerDir: URL) -> Data? {
        let coverItem = manifest.first { $0.properties.contains("cover-image") }
            ?? manifest.first { $0.id.lowercased().contains("cover") && $0.mediaType.hasPrefix("image/") }
        guard let item = coverItem else { return nil }
        let coverURL = containerDir.appendingPathComponent(item.href)
        return try? Data(contentsOf: coverURL)
    }

    // MARK: - HTML title

    private func extractHTMLTitle(from html: String) -> String? {
        if let range = html.range(of: #"<title[^>]*>([\s\S]*?)</title>"#, options: .regularExpression) {
            var title = String(html[range])
            title = title.replacingOccurrences(of: #"<title[^>]*>"#, with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "</title>", with: "")
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = html.range(of: #"<h1[^>]*>([\s\S]*?)</h1>"#, options: .regularExpression) {
            var title = String(html[range])
            title = title.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

// MARK: - XMLParser Delegates

private final class OPFDelegate: NSObject, XMLParserDelegate {
    var title: String?
    var author: String?
    var manifest: [EPUBParser.ManifestItem] = []
    var spine: [String] = []

    private var currentText = ""
    private var pendingItem: EPUBParser.ManifestItem?
    private var inTitle = false
    private var inCreator = false

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String]) {
        let name = elementName.lowercased()
        currentText = ""

        switch name {
        case "item":
            let id = attributeDict["id"] ?? ""
            let href = attributeDict["href"] ?? ""
            let media = attributeDict["media-type"] ?? ""
            let props = attributeDict["properties"] ?? ""
            pendingItem = EPUBParser.ManifestItem(id: id, href: href, mediaType: media, properties: props)
        case "itemref":
            if let idref = attributeDict["idref"] {
                spine.append(idref)
            }
        case "title":
            inTitle = true
        case "creator":
            inCreator = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "item":
            if let item = pendingItem {
                manifest.append(item)
                pendingItem = nil
            }
        case "title":
            if inTitle && title == nil && !text.isEmpty {
                title = text
            }
            inTitle = false
        case "creator":
            if inCreator && author == nil && !text.isEmpty {
                author = text
            }
            inCreator = false
        default:
            break
        }
        currentText = ""
    }
}

private final class NavTOCDelegate: NSObject, XMLParserDelegate {
    var entries: [(title: String, src: String)] = []
    private var inNav = false
    private var currentHref: String?
    private var currentText = ""
    private var collectingText = false

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String]) {
        let name = elementName.lowercased()
        if name == "nav" { inNav = true }
        if inNav && name == "a" {
            currentHref = attributeDict["href"]
            collectingText = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingText { currentText += string }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if name == "a" && collectingText {
            let title = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let href = currentHref, !title.isEmpty {
                entries.append((title: title, src: href))
            }
            collectingText = false
            currentHref = nil
            currentText = ""
        }
    }
}

private final class NCXTOCDelegate: NSObject, XMLParserDelegate {
    var entries: [(title: String, src: String)] = []
    private var inText = false
    private var currentText = ""
    private var pendingSrc: String?

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String]) {
        let name = elementName.lowercased()
        if name == "text" { inText = true; currentText = "" }
        if name == "content" { pendingSrc = attributeDict["src"] }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { currentText += string }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if name == "text" { inText = false }
        if name == "content", let src = pendingSrc {
            let title = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                entries.append((title: title, src: src))
            } else {
                entries.append((title: src, src: src))
            }
            pendingSrc = nil
            currentText = ""
        }
    }
}

enum EPUBError: Error, LocalizedError {
    case unzipFailed
    case invalidContainer
    case invalidOPF

    var errorDescription: String? {
        switch self {
        case .unzipFailed: return "无法解压 EPUB 文件"
        case .invalidContainer: return "EPUB container.xml 格式无效"
        case .invalidOPF: return "EPUB OPF 文件格式无效"
        }
    }
}

extension EPUBParser: BookParser {
    func parse(fileAt url: URL) async throws -> ParsedBook {
        let metadata: EPUBMetadata = try await Task.detached(priority: .userInitiated) {
            try self.parse(fileAt: url)
        }.value

        let chapters = metadata.chapters.map {
            ParsedChapter(title: $0.title, bodyHTML: $0.htmlContent, sourcePath: $0.fileName)
        }
        let toc = metadata.tocEntries.map {
            ParsedTOCEntry(title: $0.title, chapterIndex: $0.chapterIndex)
        }

        return ParsedBook(
            title: metadata.title,
            author: metadata.author,
            coverImage: nil,
            chapters: chapters,
            toc: toc,
            resourceDirectory: metadata.resourceDirectory,
            renderer: .html,
            pdfDocument: nil
        )
    }
}
