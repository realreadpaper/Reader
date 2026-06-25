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

        let huffDecoder: HUFFCDICDecoder?
        if header.compression == .huff {
            huffDecoder = try HUFFCDICDecoder(records: Array(pdb.records.dropFirst(last + 1)))
        } else {
            huffDecoder = nil
        }

        var raw = Data()
        for i in first...last {
            let record = pdb.records[i]
            let decompressed = try MOBIDecompressor.decompress(record, compression: header.compression, huffDecoder: huffDecoder)
            let part = stripTrailingExtraData(from: decompressed, flags: header.extraDataFlags)
            raw.append(part)
        }
        if header.textLength > 0, raw.count > header.textLength {
            raw = truncateToUTF8Boundary(raw, maxLength: header.textLength)
        }
        BookLog.mobi.info("parseClassic: decompressed \(raw.count) bytes total")

        let decodeDiagnostic = Self.decodeHTMLWithDiagnostic(raw, declaredEncoding: header.preferredTextEncoding)
        BookLog.mobi.notice("decodeHTML: \(decodeDiagnostic.summary, privacy: .public)")
        let html = decodeDiagnostic.html
        if html.isEmpty {
            BookLog.mobi.error("parseClassic: html is empty after decoding (raw not utf8/latin1, raw.prefix=\(raw.prefix(16).map(String.init).joined(), privacy: .public))")
        } else {
            BookLog.mobi.info("parseClassic: html length=\(html.count) prefix=\(String(html.prefix(80)), privacy: .public)")
        }

        let resourceMap = try writeImageResources(from: pdb, header: header, bookID: UUID().uuidString)
        let mappedHTML = rewriteResourceReferences(in: html, resourcePaths: resourceMap.pathsByRecordIndex, firstImageRecord: header.firstImageRecord)
        let pieces = splitChapters(in: mappedHTML)
        BookLog.mobi.info("parseClassic: split into \(pieces.count) chapter pieces")
        let chapters: [ParsedChapter] = pieces.enumerated().map { idx, piece in
            let title = extractTitle(from: piece) ?? "第 \(idx + 1) 页"
            return ParsedChapter(
                title: title,
                bodyHTML: piece,
                sourcePath: "classic-mobi-fragment-\(idx)"
            )
        }

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
            resourceDirectory: resourceMap.directory,
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
                return cleanHTMLText(String(inner[openClose.upperBound..<close.lowerBound]))
            }
        }
        if let range = html.range(of: "<h2[^>]*>(.*?)</h2>", options: .regularExpression) {
            let inner = String(html[range])
            if let openClose = inner.range(of: ">"), let close = inner.range(of: "</h2>") {
                return cleanHTMLText(String(inner[openClose.upperBound..<close.lowerBound]))
            }
        }
        if let range = html.range(of: "<h3[^>]*>(.*?)</h3>", options: .regularExpression) {
            let inner = String(html[range])
            if let openClose = inner.range(of: ">"), let close = inner.range(of: "</h3>") {
                return cleanHTMLText(String(inner[openClose.upperBound..<close.lowerBound]))
            }
        }
        if let range = html.range(of: "<a\\s+[^>]*(?:name|id)=[\"'][^\"']+[\"'][^>]*>\\s*([^<]+)\\s*</a>", options: .regularExpression) {
            let inner = String(html[range])
            if let openClose = inner.range(of: ">"), let close = inner.range(of: "</a>") {
                return cleanHTMLText(String(inner[openClose.upperBound..<close.lowerBound]))
            }
        }
        if let range = html.range(of: "<title[^>]*>(.*?)</title>", options: .regularExpression) {
            let inner = String(html[range])
            if let open = inner.range(of: ">"), let close = inner.range(of: "</title>") {
                return cleanHTMLText(String(inner[open.upperBound..<close.lowerBound]))
            }
        }
        return nil
    }

    private func cleanHTMLText(_ html: String) -> String? {
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        let cleaned = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private struct MOBIResourceMap {
        let directory: URL?
        let pathsByRecordIndex: [Int: String]
    }

    private func writeImageResources(from pdb: PalmDatabase, header: MOBIHeader, bookID: String) throws -> MOBIResourceMap {
        guard let firstImage = header.firstImageRecord else {
            return MOBIResourceMap(directory: nil, pathsByRecordIndex: [:])
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderMOBI", isDirectory: true)
            .appendingPathComponent(bookID, isDirectory: true)
        let imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        var pathsByRecordIndex: [Int: String] = [:]
        for i in firstImage..<pdb.records.count where i < pdb.records.count {
            let data = pdb.records[i]
            if isImage(data) {
                let ext = imageExtension(for: data) ?? "img"
                let relativePath = "images/record-\(i).\(ext)"
                try data.write(to: dir.appendingPathComponent(relativePath))
                pathsByRecordIndex[i] = relativePath
            }
        }
        return MOBIResourceMap(directory: pathsByRecordIndex.isEmpty ? nil : dir, pathsByRecordIndex: pathsByRecordIndex)
    }

    private func rewriteResourceReferences(
        in html: String,
        resourcePaths: [Int: String],
        firstImageRecord: Int?
    ) -> String {
        guard !resourcePaths.isEmpty, let firstImageRecord else { return html }
        var result = html

        let maxOffset = max(0, (resourcePaths.keys.max() ?? firstImageRecord) - firstImageRecord)
        for offset in 0...maxOffset {
            let recordIndex = firstImageRecord + offset
            guard let path = resourcePaths[recordIndex] else { continue }
            result = result.replacingOccurrences(
                of: "recindex:\\s*0*\(offset)",
                with: path,
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: "kindle:embed:\\s*0*\(offset)",
                with: path,
                options: .regularExpression
            )
        }

        return result
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
        let data = pdb.records[coverIdx]
        if isImage(data) { return data }
        // coverRecordIndex 指向的不是图片（firstImageRecord 是 first non-book index）
        // 从 firstImageRecord 开始扫描第一张有效图片作为 fallback
        guard let firstImage = header.firstImageRecord else { return data }
        for i in firstImage..<pdb.records.count {
            if isImage(pdb.records[i]) { return pdb.records[i] }
        }
        return data
    }

    func parseKF8(pdb: PalmDatabase, header: MOBIHeader, sourceURL: URL) throws -> ParsedBook {
        do {
            let reconstructed = try KF8Reconstructor(pdb: pdb, header: header, sourceURL: sourceURL).reconstruct()
            BookLog.mobi.info("parseKF8: native rawML reconstructed chapters=\(reconstructed.chapters.count)")

            // 提取图片并重写 KF8 flow 中的 recindex:XXXX 引用
            let resourceMap = try writeImageResources(from: pdb, header: header, bookID: UUID().uuidString)
            let updatedChapters = reconstructed.chapters.map { ch in
                ParsedChapter(
                    title: ch.title,
                    bodyHTML: rewriteResourceReferences(
                        in: ch.bodyHTML,
                        resourcePaths: resourceMap.pathsByRecordIndex,
                        firstImageRecord: header.firstImageRecord
                    ),
                    sourcePath: ch.sourcePath
                )
            }

            return ParsedBook(
                title: reconstructed.title,
                author: reconstructed.author,
                coverImage: reconstructed.coverImage,
                chapters: updatedChapters,
                toc: reconstructed.toc,
                resourceDirectory: resourceMap.directory,
                renderer: .html,
                pdfDocument: nil
            )
        } catch {
            BookLog.mobi.notice("parseKF8: native rawML reconstruction failed, trying legacy ZIP scan: \(error.localizedDescription, privacy: .public)")
        }

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

        let cover = coverImage(from: pdb, header: header)

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
    /// 策略：头声明的非 UTF-8 编码 → UTF-8（严格）→ 少量坏字节按 CP1252 修复 → GB18030 → Big5 → UTF-8 lossy → Latin1 兜底
    static func decodeHTML(_ raw: Data, declaredEncoding: String.Encoding?) -> String {
        decodeHTMLWithDiagnostic(raw, declaredEncoding: declaredEncoding).html
    }

    struct HTMLDecodeDiagnostic {
        let html: String
        let method: String
        let declaredEncoding: String
        let rawByteCount: Int
        let replacementCharacterCount: Int
        let sample: String

        var summary: String {
            "method=\(method) declared=\(declaredEncoding) rawBytes=\(rawByteCount) replacementChars=\(replacementCharacterCount) sample=\(sample)"
        }
    }

    static func decodeHTMLWithDiagnostic(_ raw: Data, declaredEncoding: String.Encoding?) -> HTMLDecodeDiagnostic {
        let declaredName = encodingName(declaredEncoding)
        var declaredCP1252LooksMojibake = false
        if let enc = declaredEncoding, enc != .utf8, let s = String(data: raw, encoding: enc) {
            if enc == .windowsCP1252, looksLikeLatinMojibake(s) {
                // 声明 CP1252 但解码结果高比例 Latin-1 补充字符 → 很可能是中文 GBK 被误解释
                // 跳过此结果，并在 UTF-8 之前优先尝试 GB18030，避免 GBK 字节刚好组成合法 UTF-8 时被误收。
                declaredCP1252LooksMojibake = true
            } else {
                return HTMLDecodeDiagnostic(
                    html: s,
                    method: "declared-\(encodingName(enc))",
                    declaredEncoding: declaredName,
                    rawByteCount: raw.count,
                    replacementCharacterCount: replacementCount(in: s),
                    sample: diagnosticSample(from: s)
                )
            }
        }
        if declaredCP1252LooksMojibake, let s = String(data: raw, encoding: .gb18030) {
            return HTMLDecodeDiagnostic(
                html: s,
                method: "gb18030",
                declaredEncoding: declaredName,
                rawByteCount: raw.count,
                replacementCharacterCount: replacementCount(in: s),
                sample: diagnosticSample(from: s)
            )
        }
        if let s = String(data: raw, encoding: .utf8) {
            return HTMLDecodeDiagnostic(
                html: s,
                method: "utf8-strict",
                declaredEncoding: declaredName,
                rawByteCount: raw.count,
                replacementCharacterCount: replacementCount(in: s),
                sample: diagnosticSample(from: s)
            )
        }
        if declaredEncoding == .utf8 {
            if let repaired = repairInvalidUTF8HTMLBytesWithWindowsCP1252(raw) {
                return HTMLDecodeDiagnostic(
                    html: repaired,
                    method: "utf8-html-repair-windowsCP1252",
                    declaredEncoding: declaredName,
                    rawByteCount: raw.count,
                    replacementCharacterCount: replacementCount(in: repaired),
                    sample: diagnosticSample(from: repaired)
                )
            }
            let lossyUTF8 = String(decoding: raw, as: UTF8.self)
            let lossyUTF8ReplacementCount = replacementCount(in: lossyUTF8)
            let maxSparseUTF8Replacements = max(1, raw.count / 200)
            if lossyUTF8ReplacementCount <= maxSparseUTF8Replacements {
                return HTMLDecodeDiagnostic(
                    html: lossyUTF8,
                    method: "utf8-lossy",
                    declaredEncoding: declaredName,
                    rawByteCount: raw.count,
                    replacementCharacterCount: lossyUTF8ReplacementCount,
                    sample: diagnosticSample(from: lossyUTF8)
                )
            }
        }
        // 中文 MOBI 最常见的实际编码：GB18030 兼容 GBK/GB2312
        if let s = String(data: raw, encoding: .gb18030) {
            return HTMLDecodeDiagnostic(
                html: s,
                method: "gb18030",
                declaredEncoding: declaredName,
                rawByteCount: raw.count,
                replacementCharacterCount: replacementCount(in: s),
                sample: diagnosticSample(from: s)
            )
        }
        // GB18030 容错：处理大段中文中夹杂个别无效字节的场景
        let gb18030Lossy = decodeGB18030Tolerant(raw)
        let gb18030ReplacementCount = replacementCount(in: gb18030Lossy)
        if gb18030ReplacementCount * 10 <= raw.count {
            return HTMLDecodeDiagnostic(
                html: gb18030Lossy,
                method: "gb18030-tolerant",
                declaredEncoding: declaredName,
                rawByteCount: raw.count,
                replacementCharacterCount: gb18030ReplacementCount,
                sample: diagnosticSample(from: gb18030Lossy)
            )
        }
        if let s = String(data: raw, encoding: .big5) {
            return HTMLDecodeDiagnostic(
                html: s,
                method: "big5",
                declaredEncoding: declaredName,
                rawByteCount: raw.count,
                replacementCharacterCount: replacementCount(in: s),
                sample: diagnosticSample(from: s)
            )
        }
        if let s = String(data: raw, encoding: .shiftJIS) {
            return HTMLDecodeDiagnostic(
                html: s,
                method: "shiftJIS",
                declaredEncoding: declaredName,
                rawByteCount: raw.count,
                replacementCharacterCount: replacementCount(in: s),
                sample: diagnosticSample(from: s)
            )
        }
        if let s = String(data: raw, encoding: .eucKR) {
            return HTMLDecodeDiagnostic(
                html: s,
                method: "eucKR",
                declaredEncoding: declaredName,
                rawByteCount: raw.count,
                replacementCharacterCount: replacementCount(in: s),
                sample: diagnosticSample(from: s)
            )
        }
        if declaredEncoding == .utf8 {
            let s = String(decoding: raw, as: UTF8.self)
            return HTMLDecodeDiagnostic(
                html: s,
                method: "utf8-lossy",
                declaredEncoding: declaredName,
                rawByteCount: raw.count,
                replacementCharacterCount: replacementCount(in: s),
                sample: diagnosticSample(from: s)
            )
        }
        let s = String(data: raw, encoding: .isoLatin1) ?? ""
        return HTMLDecodeDiagnostic(
            html: s,
            method: "isoLatin1-fallback",
            declaredEncoding: declaredName,
            rawByteCount: raw.count,
            replacementCharacterCount: replacementCount(in: s),
            sample: diagnosticSample(from: s)
        )
    }

    private static func repairInvalidUTF8HTMLBytesWithWindowsCP1252(_ raw: Data) -> String? {
        let bytes = [UInt8](raw)
        guard !bytes.isEmpty else { return nil }

        var html = ""
        html.reserveCapacity(raw.count)
        var repairedByteCount = 0
        var segmentStart = 0
        var index = 0

        while index < bytes.count {
            if let length = validUTF8SequenceLength(in: bytes, at: index) {
                index += length
                continue
            }

            if segmentStart < index {
                html.append(String(decoding: bytes[segmentStart..<index], as: UTF8.self))
            }
            guard let repaired = String(data: Data([bytes[index]]), encoding: .windowsCP1252) else {
                return nil
            }
            html.append(repaired)
            repairedByteCount += 1
            index += 1
            segmentStart = index
        }

        guard repairedByteCount > 0 else { return nil }
        if segmentStart < bytes.count {
            html.append(String(decoding: bytes[segmentStart..<bytes.count], as: UTF8.self))
        }

        let maxRepairableBytes = max(1, raw.count / 20)
        guard repairedByteCount <= maxRepairableBytes else { return nil }
        return html
    }

    private static func validUTF8SequenceLength(in bytes: [UInt8], at index: Int) -> Int? {
        let byte = bytes[index]
        if byte <= 0x7F { return 1 }

        func hasContinuation(_ offset: Int) -> Bool {
            let nextIndex = index + offset
            guard nextIndex < bytes.count else { return false }
            return (bytes[nextIndex] & 0xC0) == 0x80
        }

        if (0xC2...0xDF).contains(byte) {
            return hasContinuation(1) ? 2 : nil
        }
        if byte == 0xE0 {
            guard index + 2 < bytes.count, (0xA0...0xBF).contains(bytes[index + 1]), hasContinuation(2) else {
                return nil
            }
            return 3
        }
        if (0xE1...0xEC).contains(byte) || (0xEE...0xEF).contains(byte) {
            return hasContinuation(1) && hasContinuation(2) ? 3 : nil
        }
        if byte == 0xED {
            guard index + 2 < bytes.count, (0x80...0x9F).contains(bytes[index + 1]), hasContinuation(2) else {
                return nil
            }
            return 3
        }
        if byte == 0xF0 {
            guard index + 3 < bytes.count, (0x90...0xBF).contains(bytes[index + 1]), hasContinuation(2), hasContinuation(3) else {
                return nil
            }
            return 4
        }
        if (0xF1...0xF3).contains(byte) {
            return hasContinuation(1) && hasContinuation(2) && hasContinuation(3) ? 4 : nil
        }
        if byte == 0xF4 {
            guard index + 3 < bytes.count, (0x80...0x8F).contains(bytes[index + 1]), hasContinuation(2), hasContinuation(3) else {
                return nil
            }
            return 4
        }
        return nil
    }

    private static func encodingName(_ encoding: String.Encoding?) -> String {
        guard let encoding else { return "nil" }
        switch encoding {
        case .utf8: return "utf8"
        case .windowsCP1252: return "windowsCP1252"
        case .gb18030: return "gb18030"
        case .big5: return "big5"
        case .shiftJIS: return "shiftJIS"
        case .eucKR: return "eucKR"
        case .isoLatin1: return "isoLatin1"
        default: return "raw-\(encoding.rawValue)"
        }
    }

    private static func replacementCount(in text: String) -> Int {
        text.reduce(0) { $0 + ($1 == "\u{FFFD}" ? 1 : 0) }
    }

    /// 检测 CP1252 解码结果是否是中文被 Latin-1 误解释的乱码
    /// 中文字节解码为 CP1252 后 U+0080-U+00FF 占比通常 >50%，合法西文文本 <10%
    private static func looksLikeLatinMojibake(_ text: String) -> Bool {
        let visibleText = stripHTMLTags(from: text)
        var nonAscii = 0
        var total = 0
        var currentRun = 0
        var maxRun = 0
        for char in visibleText {
            guard !char.isWhitespace else { continue }
            total += 1
            if let scalar = char.unicodeScalars.first, scalar.value >= 0x80, scalar.value <= 0xFF {
                nonAscii += 1
                currentRun += 1
                maxRun = max(maxRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        guard total > 8 else { return false }
        if total > 20 {
            return nonAscii > total / 4
        }
        return maxRun >= 4 && nonAscii * 2 >= total
    }

    private static func stripHTMLTags(from text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var insideTag = false

        for char in text {
            if char == "<" {
                insideTag = true
                continue
            }
            if char == ">" {
                insideTag = false
                continue
            }
            if !insideTag {
                result.append(char)
            }
        }

        return result
    }

    /// GB18030 容错解码：逐字节解析，无效序列插入 U+FFFD 而非整段失败
    private static func decodeGB18030Tolerant(_ raw: Data) -> String {
        let bytes = [UInt8](raw)
        var result = ""
        result.reserveCapacity(raw.count)
        var segStart = 0
        var i = 0

        while i < bytes.count {
            let adv = gb18030SequenceAdvance(bytes: bytes, at: i)
            if adv > 0 {
                i += adv
            } else {
                if segStart < i {
                    if let s = String(data: Data(bytes[segStart..<i]), encoding: .gb18030) {
                        result.append(s)
                    } else {
                        result.append(String(decoding: bytes[segStart..<i], as: UTF8.self))
                    }
                }
                result.append("\u{FFFD}")
                i += 1
                segStart = i
            }
        }
        if segStart < bytes.count {
            if let s = String(data: Data(bytes[segStart..<bytes.count]), encoding: .gb18030) {
                result.append(s)
            } else {
                result.append(String(decoding: bytes[segStart..<bytes.count], as: UTF8.self))
            }
        }
        return result
    }

    /// 返回当前字节位置开始的 GB18030 序列长度：1(ASCII)、2(GBK)、4(扩展)，无效返回 0
    private static func gb18030SequenceAdvance(bytes: [UInt8], at i: Int) -> Int {
        let b0 = bytes[i]
        if b0 <= 0x7F { return 1 }
        guard b0 >= 0x81 && b0 <= 0xFE, i + 1 < bytes.count else { return 0 }
        let b1 = bytes[i + 1]
        // Two-byte: second byte 0x40-0xFE, excluding 0x7F
        if b1 >= 0x40 && b1 <= 0xFE && b1 != 0x7F { return 2 }
        // Four-byte: b1=0x30-0x39, b2=0x81-0xFE, b3=0x30-0x39
        if b1 >= 0x30 && b1 <= 0x39, i + 3 < bytes.count {
            let b2 = bytes[i + 2]
            let b3 = bytes[i + 3]
            if b2 >= 0x81 && b2 <= 0xFE && b3 >= 0x30 && b3 <= 0x39 { return 4 }
        }
        return 0
    }

    private static func diagnosticSample(from text: String) -> String {
        String(text.prefix(120))
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

/// 从解压后的 record 尾部剥除 trailing extra data（overlap + size entry）
/// - Parameters:
///   - record: 解压后的单条 text record
///   - flags: MOBI header 的 extraDataFlags
/// - Returns: 干净的正文数据
func stripTrailingExtraData(from record: Data, flags: UInt32) -> Data {
    guard !record.isEmpty else { return record }

    var end = record.count

    if flags != 0 {
        for bit in 0..<32 where (flags & (1 << UInt32(bit))) != 0 {
            guard end > 0 else { return Data() }
            if bit == 0 {
                let overlapLength = Int(record[end - 1] & 0x03)
                guard overlapLength <= end else { return Data() }
                end -= overlapLength
            } else {
                guard let newEnd = extraDataStart(in: record, endingAt: end) else {
                    break
                }
                end = newEnd
            }
        }
    } else {
        // 防御性 overlap 检测：早期 MOBI 可能未设 bit 0 但仍有跨 record overlap
        // 尾字节低 2 位表示 overlap 长度(1-3)，正常 HTML 文本不以控制字符结尾
        let lastByte = record[end - 1]
        let possibleOverlap = Int(lastByte & 0x03)
        if possibleOverlap > 0, lastByte <= 0x1F, possibleOverlap < end {
            end -= possibleOverlap
        }
    }

    return end == record.count ? record : record.subdata(in: 0..<end)
}

/// 从 record 尾部反向解析变长 size entry
func extraDataStart(in record: Data, endingAt initialEnd: Int) -> Int? {
    var end = initialEnd
    var size = 0
    var shift = 0

    repeat {
        guard end > 0, shift <= 28 else { return nil }
        end -= 1
        let byte = record[end]
        size |= Int(byte & 0x7F) << shift
        shift += 7
        if byte & 0x80 == 0 {
            break
        }
    } while true

    guard size >= 0, size <= end else { return nil }
    return end - size
}

/// 将截断位置对齐到 UTF-8 字符边界，避免切断多字节字符产生 U+FFFD
func truncateToUTF8Boundary(_ data: Data, maxLength: Int) -> Data {
    guard maxLength < data.count else { return data }
    var end = maxLength
    // UTF-8 continuation bytes: 0x80-0xBF (10xxxxxx)
    // 回退到第一个非 continuation byte
    while end > 0, data[end - 1] & 0xC0 == 0x80 {
        end -= 1
    }
    return data.prefix(end)
}
