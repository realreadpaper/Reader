import Foundation

protocol MOBIConverting {
    var isAvailable: Bool { get }
    func convertToEPUB(mobiURL: URL) async throws -> URL
}

extension MOBIConverter: MOBIConverting {}

final class MOBIParser: BookParser {
    private static let targetHTMLPageSize = 6_000
    private let converter: MOBIConverting

    init(converter: MOBIConverting = MOBIConverter()) {
        self.converter = converter
    }

    func parse(fileAt url: URL) async throws -> ParsedBook {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        BookLog.mobi.info("parse: start url=\(url.lastPathComponent, privacy: .public) size=\(fileSize)")
        do {
            let result = try await parseNative(fileAt: url)
            BookLog.mobi.info("parse: native OK variant=\(String(describing: result.renderer), privacy: .public) chapters=\(result.chapters.count)")
            return result
        } catch BookParseError.unsupportedFormat {
            BookLog.mobi.notice("parse: native unsupported, falling back to calibre")
            return try await parseViaCalibre(fileAt: url)
        } catch {
            BookLog.mobi.error("parse: native failed error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func parseNative(fileAt url: URL) async throws -> ParsedBook {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        BookLog.mobi.info("parseNative: loaded \(data.count) bytes")
        let pdb = try PalmDBReader.read(data)
        BookLog.mobi.info("parseNative: pdb records=\(pdb.records.count) name=\(pdb.name, privacy: .public) type=\(pdb.type, privacy: .public) creator=\(pdb.creator, privacy: .public)")
        guard pdb.records.first != nil else {
            throw BookParseError.corruptedFile(detail: "无 record0")
        }
        if let info = try? MOBIContainerInspector.inspect(pdb: pdb) {
            BookLog.mobi.info("parseNative: container \(info.diagnosticSummary, privacy: .public)")
        }
        let header = try MOBIHeader.read(pdb: pdb)
        BookLog.mobi.info("parseNative: header variant=\(String(describing: header.variant), privacy: .public) compression=\(String(describing: header.compression), privacy: .public) textRange=\(header.firstTextRecord)-\(header.lastTextRecord) firstImage=\(header.firstImageRecord.map(String.init) ?? "nil", privacy: .public) title=\(header.title, privacy: .public)")

        switch header.variant {
        case .classicMOBI:
            BookLog.mobi.info("parseNative: dispatching to parseClassic")
            return try parseClassic(pdb: pdb, header: header, sourceURL: url)
        case .kf8:
            BookLog.mobi.info("parseNative: dispatching to parseKF8")
            return try parseKF8(pdb: pdb, header: header, sourceURL: url)
        case .unsupported(let reason):
            BookLog.mobi.notice("parseNative: variant unsupported: \(reason, privacy: .public)")
            throw BookParseError.unsupportedFormat(detail: reason)
        }
    }

    private func parseViaCalibre(fileAt url: URL) async throws -> ParsedBook {
        guard converter.isAvailable else {
            BookLog.converter.error("parseViaCalibre: ebook-convert not found")
            throw BookParseError.calibreNotInstalled
        }
        BookLog.converter.info("parseViaCalibre: converting \(url.lastPathComponent, privacy: .public)")
        let epubURL = try await converter.convertToEPUB(mobiURL: url)
        BookLog.converter.info("parseViaCalibre: conversion done, parsing epub")
        defer {
            // 只清理我们自己在临时目录生成的文件，避免误删测试 fixture 或用户文件
            let tempRoot = FileManager.default.temporaryDirectory.path
            if epubURL.path.hasPrefix(tempRoot) {
                try? FileManager.default.removeItem(at: epubURL)
            }
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
        BookLog.mobi.info("parseClassic: text records \(first)...\(last) of \(pdb.records.count)")
        guard first <= last else {
            throw BookParseError.corruptedFile(detail: "text record 范围非法 first=\(first) last=\(last) total=\(pdb.records.count)")
        }

        var raw = Data()
        for i in first...last {
            let record = pdb.records[i]
            let part = try MOBIDecompressor.decompress(record, compression: header.compression)
            raw.append(part)
        }
        if header.textLength > 0, raw.count > header.textLength {
            raw = Data(raw.prefix(header.textLength))
        }
        BookLog.mobi.info("parseClassic: decompressed \(raw.count) bytes total")

        let html = Self.decodeHTML(raw, declaredEncoding: header.preferredTextEncoding)
        if html.isEmpty {
            BookLog.mobi.error("parseClassic: html is empty after decoding (raw not utf8/latin1, raw.prefix=\(raw.prefix(16).map(String.init).joined(), privacy: .public))")
        } else {
            BookLog.mobi.info("parseClassic: html length=\(html.count) prefix=\(String(html.prefix(80)), privacy: .public)")
        }

        let pieces = splitChapters(in: html)
        BookLog.mobi.info("parseClassic: split into \(pieces.count) chapter pieces")
        let chapters: [ParsedChapter] = pieces.enumerated().map { idx, piece in
            ParsedChapter(
                title: "第 \(idx + 1) 页",
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
        // 策略 1: <mbp:pagebreak> 标记
        let pageBreakMarker = "<!-- reader-pagebreak -->"
        let pageBreakHTML = html.replacingOccurrences(
            of: "<mbp:pagebreak[^>]*>",
            with: pageBreakMarker,
            options: .regularExpression
        )
        let pages = pageBreakHTML.components(separatedBy: pageBreakMarker)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if pages.count > 1 {
            let result = paginatePieces(pages)
            BookLog.mobi.info("splitChapters: split by mbp:pagebreak into \(pages.count) pieces, paginated into \(result.count) pages")
            return result
        }

        // 策略 2: <h1> 分章
        let h1Parts = html.components(separatedBy: "<h1")
        if h1Parts.count > 1 {
            let result = h1Parts.enumerated().compactMap { idx, part -> String? in
                let body = idx == 0 ? "" : "<h1" + part
                return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : body
            }
            if result.count > 1 {
                let pages = paginatePieces(result)
                BookLog.mobi.info("splitChapters: split by <h1> into \(result.count) pieces, paginated into \(pages.count) pages")
                return pages
            }
        }

        // 策略 3: <h2> 分章（比 Calibre 更细粒度）
        let h2Parts = html.components(separatedBy: "<h2")
        if h2Parts.count > 1 {
            let result = h2Parts.enumerated().compactMap { idx, part -> String? in
                let body = idx == 0 ? "" : "<h2" + part
                return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : body
            }
            if result.count > 1 {
                let pages = paginatePieces(result)
                BookLog.mobi.info("splitChapters: split by <h2> into \(result.count) pieces, paginated into \(pages.count) pages")
                return pages
            }
        }

        // 策略 4: <h3> 分章
        let h3Parts = html.components(separatedBy: "<h3")
        if h3Parts.count > 1 {
            let result = h3Parts.enumerated().compactMap { idx, part -> String? in
                let body = idx == 0 ? "" : "<h3" + part
                return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : body
            }
            if result.count > 1 {
                let pages = paginatePieces(result)
                BookLog.mobi.info("splitChapters: split by <h3> into \(result.count) pieces, paginated into \(pages.count) pages")
                return pages
            }
        }

        // 策略 5: <hr> 分页（某些 MOBI 用水平线分隔章节）
        let hrParts = html.components(separatedBy: "<hr")
        if hrParts.count > 2 {
            let result = hrParts.enumerated().compactMap { idx, part -> String? in
                let body = idx == 0 ? "" : "<hr" + part
                return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : body
            }
            if result.count > 1 {
                let pages = paginatePieces(result)
                BookLog.mobi.info("splitChapters: split by <hr> into \(result.count) pieces, paginated into \(pages.count) pages")
                return pages
            }
        }

        // 策略 6: 按大小自动分页（超过目标页大小的 HTML 按段落边界拆分）
        if html.count > Self.targetHTMLPageSize {
            let result = smartSplitBySize(html)
            if result.count > 1 {
                BookLog.mobi.info("splitChapters: smart split by size into \(result.count) pieces")
                return result
            }
        }

        BookLog.mobi.info("splitChapters: no split markers found, returning as single chapter")
        return [html]
    }

    private func paginatePieces(_ pieces: [String]) -> [String] {
        pieces.flatMap { smartSplitBySize($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 按大小智能分页：在段落边界处拆分
    private func smartSplitBySize(_ html: String) -> [String] {
        let maxChunkSize = Self.targetHTMLPageSize
        var chunks: [String] = []
        var lastParagraphEnd = html.startIndex

        let paragraphEnders = ["</p>", "</div>", "</blockquote>", "</li>", "</td>"]
        var searchStart = html.startIndex

        while searchStart < html.endIndex {
            var nextRange: Range<String.Index>?
            for ender in paragraphEnders {
                guard let range = html.range(of: ender, range: searchStart..<html.endIndex) else {
                    continue
                }
                if nextRange == nil || range.upperBound < nextRange!.upperBound {
                    nextRange = range
                }
            }

            guard let range = nextRange else {
                break
            }

            let candidateEnd = range.upperBound
            let distance = html.distance(from: lastParagraphEnd, to: candidateEnd)
            if distance > maxChunkSize {
                let chunk = String(html[lastParagraphEnd..<candidateEnd])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty {
                    chunks.append(chunk)
                }
                lastParagraphEnd = candidateEnd
            }
            searchStart = candidateEnd
        }

        if lastParagraphEnd < html.endIndex {
            let remaining = String(html[lastParagraphEnd..<html.endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                chunks.append(remaining)
            }
        }

        return chunks.isEmpty ? [html] : chunks
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
            BookLog.mobi.error("parseKF8: cannot extract KF8 ZIP data from \(pdb.records.count) records")
            throw BookParseError.corruptedFile(detail: "无法提取 KF8 ZIP 数据")
        }
        BookLog.mobi.info("parseKF8: extracted ZIP \(kf8Data.count) bytes")

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderMOBI-KF8")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpEPUB = tmpDir.appendingPathComponent("\(UUID().uuidString).epub")
        try kf8Data.write(to: tmpEPUB)
        defer { try? FileManager.default.removeItem(at: tmpEPUB) }
        BookLog.mobi.info("parseKF8: wrote temp epub \(tmpEPUB.lastPathComponent, privacy: .public)")

        let epubParser = EPUBParser()
        let metadata = try epubParser.parse(fileAt: tmpEPUB)
        BookLog.mobi.info("parseKF8: epub parsed chapters=\(metadata.chapters.count)")

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
                BookLog.mobi.info("extractKF8: hybrid MOBI+KF8, ZIP starts at record 2")
            } else {
                startRecord = 1
                BookLog.mobi.info("extractKF8: pure KF8, ZIP starts at record 1")
            }
        } else {
            BookLog.mobi.error("extractKF8: pdb has only \(pdb.records.count) record(s)")
            return nil
        }

        var combined = Data()
        for i in startRecord..<pdb.records.count {
            combined.append(pdb.records[i])
        }
        BookLog.mobi.info("extractKF8: combined \(combined.count) bytes, scanning for PK signature")

        guard let pkRange = combined.range(of: Data(pkSignature)) else {
            BookLog.mobi.error("extractKF8: PK signature not found in \(combined.count) bytes")
            return nil
        }
        BookLog.mobi.info("extractKF8: PK signature at offset \(pkRange.lowerBound)")
        return combined.subdata(in: pkRange.lowerBound..<combined.count)
    }

    /// 解码 MOBI 文本记录。MOBI 文件实际编码不一定与 header 声明一致：
    /// 很多中文 MOBI 声明 1252 (Western) 但内容是 GBK/GB18030。
    /// 策略：UTF-8（严格）→ 头声明的编码 → GB18030 → Big5 → Latin1 兜底
    static func decodeHTML(_ raw: Data, declaredEncoding: String.Encoding?) -> String {
        if let s = String(data: raw, encoding: .utf8) {
            BookLog.mobi.info("decodeHTML: utf8 OK")
            return s
        }
        if declaredEncoding == .utf8 {
            BookLog.mobi.notice("decodeHTML: utf8 lossy fallback OK")
            return String(decoding: raw, as: UTF8.self)
        }
        if let enc = declaredEncoding, enc != .utf8, let s = String(data: raw, encoding: enc) {
            BookLog.mobi.info("decodeHTML: declared encoding OK")
            return s
        }
        // 中文 MOBI 最常见的实际编码：GB18030 兼容 GBK/GB2312
        if let s = String(data: raw, encoding: .gb18030) {
            BookLog.mobi.info("decodeHTML: GB18030 OK")
            return s
        }
        if let s = String(data: raw, encoding: .big5) {
            BookLog.mobi.info("decodeHTML: Big5 OK")
            return s
        }
        BookLog.mobi.notice("decodeHTML: falling back to isoLatin1 (may produce mojibake)")
        return String(data: raw, encoding: .isoLatin1) ?? ""
    }
}
