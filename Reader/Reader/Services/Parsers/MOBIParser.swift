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
        defer {
            try? FileManager.default.removeItem(at: epubURL)
        }
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
        guard let kf8Data = extractKF8Data(from: pdb) else {
            throw BookParseError.corruptedFile(detail: "无法提取 KF8 ZIP 数据")
        }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderMOBI-KF8")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpEPUB = tmpDir.appendingPathComponent("\(UUID().uuidString).epub")
        try kf8Data.write(to: tmpEPUB)
        defer { try? FileManager.default.removeItem(at: tmpEPUB) }

        let epubParser = EPUBParser()
        let metadata = try epubParser.parse(fileAt: tmpEPUB)

        let chapters = metadata.chapters.map { ch in
            ParsedChapter(title: ch.title, bodyHTML: ch.htmlContent, sourcePath: ch.fileName)
        }
        let toc = metadata.tocEntries.map { entry in
            ParsedTOCEntry(title: entry.title, chapterIndex: entry.chapterIndex)
        }

        let cover: Data? = {
            if let idx = header.coverRecordIndex, idx < pdb.records.count {
                return pdb.records[idx]
            }
            return nil
        }()

        return ParsedBook(
            title: header.title,
            author: header.author,
            coverImage: cover,
            chapters: chapters,
            toc: toc,
            resourceDirectory: metadata.resourceDirectory,
            renderer: .html,
            pdfDocument: nil
        )
    }

    /// 从 PalmDB 记录中提取 KF8 ZIP 数据
    private func extractKF8Data(from pdb: PalmDatabase) -> Data? {
        let pkSignature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]

        // 纯 KF8: records[1]+ 是 ZIP
        // 混合 MOBI+KF8: records[1] 是 BOUNDARY，records[2]+ 是 ZIP
        let startRecord: Int
        if pdb.records.count > 1 {
            let rec1 = pdb.records[1]
            if rec1.count >= 20,
               let id = String(data: rec1.subdata(in: 16..<20), encoding: .ascii),
               id == "BOUNDARY" {
                startRecord = 2
            } else {
                startRecord = 1
            }
        } else {
            return nil
        }

        var combined = Data()
        for i in startRecord..<pdb.records.count {
            combined.append(pdb.records[i])
        }

        guard let pkRange = combined.range(of: Data(pkSignature)) else { return nil }
        return combined.subdata(in: pkRange.lowerBound..<combined.count)
    }
}
