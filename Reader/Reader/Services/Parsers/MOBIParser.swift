import Foundation

protocol MOBIConverting {
    var isAvailable: Bool { get }
    func convertToEPUB(mobiURL: URL) async throws -> URL
}

extension MOBIConverter: MOBIConverting {}

final class MOBIParser: BookParser {
    private let converter: MOBIConverting

    init(converter: MOBIConverting = MOBIConverter()) {
        self.converter = converter
    }

    func parse(fileAt url: URL) async throws -> ParsedBook {
        do {
            return try await parseNative(fileAt: url)
        } catch BookParseError.unsupportedFormat {
            return try await parseViaCalibre(fileAt: url)
        }
    }

    private func parseNative(fileAt url: URL) async throws -> ParsedBook {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let pdb = try PalmDBReader.read(data)
        guard let record0 = pdb.records.first else {
            throw BookParseError.corruptedFile(detail: "无 record0")
        }
        let header = try MOBIHeader.read(pdb: pdb)

        switch header.variant {
        case .classicMOBI:
            return try parseClassic(pdb: pdb, header: header, sourceURL: url)
        case .kf8:
            return try parseKF8(pdb: pdb, header: header, sourceURL: url)
        case .unsupported(let reason):
            throw BookParseError.unsupportedFormat(detail: reason)
        }
    }

    private func parseViaCalibre(fileAt url: URL) async throws -> ParsedBook {
        guard converter.isAvailable else {
            throw BookParseError.calibreNotInstalled
        }
        let epubURL = try await converter.convertToEPUB(mobiURL: url)
        return try await EPUBParser().parse(fileAt: epubURL)
    }

    /// 测试钩子：绕过 parseNative，直接走 calibre 兜底
    func testParseViaCalibre(fileAt url: URL) async throws -> ParsedBook {
        try await parseViaCalibre(fileAt: url)
    }

    func parseClassic(pdb: PalmDatabase, header: MOBIHeader, sourceURL: URL) throws -> ParsedBook {
        let first = max(1, header.firstTextRecord)
        let last = min(pdb.records.count - 1, header.lastTextRecord)
        guard first <= last else {
            throw BookParseError.corruptedFile(detail: "text record 范围非法")
        }

        var raw = Data()
        for i in first...last {
            let record = pdb.records[i]
            let part = try MOBIDecompressor.decompress(record, compression: header.compression)
            raw.append(part)
        }

        let html = String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1) ?? ""

        let pieces = splitChapters(in: html)
        let chapters: [ParsedChapter] = pieces.enumerated().map { idx, piece in
            ParsedChapter(
                title: extractTitle(from: piece) ?? "第 \(idx + 1) 节",
                bodyHTML: piece,
                sourcePath: "classic-mobi-fragment-\(idx)"
            )
        }

        let resourceDir = try? writeImageResources(from: pdb, header: header, bookID: UUID().uuidString)
        let cover = coverImage(from: pdb, header: header)

        let toc = chapters.enumerated().map { idx, ch in
            ParsedTOCEntry(title: ch.title, chapterIndex: idx)
        }

        return ParsedBook(
            title: header.title,
            author: header.author,
            coverImage: cover,
            chapters: chapters,
            toc: toc,
            resourceDirectory: resourceDir,
            renderer: .html,
            pdfDocument: nil
        )
    }

    private func splitChapters(in html: String) -> [String] {
        let separator = "<mbp:pagebreak"
        let parts = html.components(separatedBy: separator)
        if parts.count > 1 {
            return parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let h1Parts = html.components(separatedBy: "<h1")
        if h1Parts.count > 1 {
            return h1Parts.enumerated().compactMap { idx, part in
                let body = idx == 0 ? "" : "<h1" + part
                return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : body
            }
        }
        return [html]
    }

    private func extractTitle(from html: String) -> String? {
        if let range = html.range(of: "<h1[^>]*>(.*?)</h1>", options: .regularExpression) {
            let inner = String(html[range])
            if let openClose = inner.range(of: ">"), let close = inner.range(of: "</h1>") {
                return String(inner[openClose.upperBound..<close.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let range = html.range(of: "<title>(.*?)</title>", options: .regularExpression) {
            let inner = String(html[range])
            if let open = inner.range(of: "<title>"), let close = inner.range(of: "</title>") {
                return String(inner[open.upperBound..<close.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func writeImageResources(from pdb: PalmDatabase, header: MOBIHeader, bookID: String) throws -> URL? {
        guard let firstImage = header.firstImageRecord else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderMOBI", isDirectory: true)
            .appendingPathComponent(bookID, isDirectory: true)
        let imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        var imageIndex = 0
        for i in firstImage..<pdb.records.count where i < pdb.records.count {
            let data = pdb.records[i]
            if isImage(data) {
                let ext = imageExtension(for: data) ?? "img"
                try data.write(to: imagesDir.appendingPathComponent("image-\(imageIndex).\(ext)"))
                imageIndex += 1
            }
        }
        return imageIndex > 0 ? dir : nil
    }

    private func isImage(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let prefix = [UInt8](data.prefix(4))
        if prefix[0] == 0xFF && prefix[1] == 0xD8 { return true }
        if prefix[0] == 0x89 && prefix[1] == 0x50 && prefix[2] == 0x4E && prefix[3] == 0x47 { return true }
        if prefix[0] == 0x47 && prefix[1] == 0x49 && prefix[2] == 0x46 && prefix[3] == 0x38 { return true }
        return false
    }

    private func imageExtension(for data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let prefix = [UInt8](data.prefix(4))
        if prefix[0] == 0xFF && prefix[1] == 0xD8 { return "jpg" }
        if prefix[0] == 0x89 && prefix[1] == 0x50 { return "png" }
        if prefix[0] == 0x47 && prefix[1] == 0x49 { return "gif" }
        return nil
    }

    private func coverImage(from pdb: PalmDatabase, header: MOBIHeader) -> Data? {
        guard let coverIdx = header.coverRecordIndex, coverIdx < pdb.records.count else { return nil }
        return pdb.records[coverIdx]
    }

    func parseKF8(pdb: PalmDatabase, header: MOBIHeader, sourceURL: URL) throws -> ParsedBook {
        guard pdb.records.count >= 2 else {
            throw BookParseError.corruptedFile(detail: "KF8 records 过少")
        }
        var raw = Data()
        for i in 1..<pdb.records.count {
            raw.append(pdb.records[i])
        }
        let html = String(data: raw, encoding: .utf8) ?? ""

        let chapter = ParsedChapter(
            title: header.title,
            bodyHTML: html,
            sourcePath: "kf8-flow"
        )
        let toc = [ParsedTOCEntry(title: header.title, chapterIndex: 0)]
        return ParsedBook(
            title: header.title,
            author: header.author,
            coverImage: nil,
            chapters: [chapter],
            toc: toc,
            resourceDirectory: nil,
            renderer: .html,
            pdfDocument: nil
        )
    }
}
