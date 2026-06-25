import Foundation

struct KF8Reconstructor {
    struct FlowSection: Equatable {
        let start: Int
        let end: Int
    }

    let pdb: PalmDatabase
    let header: MOBIHeader
    let sourceURL: URL

    static func parseFDST(_ data: Data) throws -> [FlowSection] {
        guard data.count >= 12,
              String(data: data.prefix(4), encoding: .ascii) == "FDST" else {
            throw BookParseError.corruptedFile(detail: "KF8 FDST record missing")
        }
        let count = Int(data.readUInt32BE(at: 8))
        guard count > 0 else { return [] }
        guard 12 + count * 8 <= data.count else {
            throw BookParseError.corruptedFile(detail: "KF8 FDST table out of range")
        }

        var sections: [FlowSection] = []
        for index in 0..<count {
            let offset = 12 + index * 8
            let start = Int(data.readUInt32BE(at: offset))
            let end = Int(data.readUInt32BE(at: offset + 4))
            guard start <= end else {
                throw BookParseError.corruptedFile(detail: "KF8 FDST section has invalid range")
            }
            sections.append(FlowSection(start: start, end: end))
        }
        return sections
    }

    func reconstruct() throws -> ParsedBook {
        let rawML = try readRawML()
        let flows = try splitFlows(rawML: rawML)
        let chapters = flows.enumerated().compactMap { index, flow -> ParsedChapter? in
            let diagnostic = MOBIParser.decodeHTMLWithDiagnostic(flow, declaredEncoding: .utf8)
            let html = diagnostic.html.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !html.isEmpty else {
                return nil
            }
            return ParsedChapter(
                title: Self.extractTitle(from: html) ?? "第 \(index + 1) 页",
                bodyHTML: html,
                sourcePath: "kf8-flow-\(index).xhtml"
            )
        }
        guard !chapters.isEmpty else {
            throw BookParseError.corruptedFile(detail: "KF8 rawML contains no readable XHTML flows")
        }

        return ParsedBook(
            title: header.title,
            author: header.author,
            coverImage: coverImage(),
            chapters: chapters,
            toc: chapters.enumerated().map { ParsedTOCEntry(title: $0.element.title, chapterIndex: $0.offset) },
            resourceDirectory: nil,
            renderer: .html,
            pdfDocument: nil
        )
    }

    private func readRawML() throws -> Data {
        let first = max(1, header.firstTextRecord)
        let last = min(pdb.records.count - 1, header.lastTextRecord)
        guard first <= last else {
            throw BookParseError.corruptedFile(detail: "KF8 text record range invalid")
        }

        var raw = Data()
        for index in first...last {
            let decompressed = try MOBIDecompressor.decompress(pdb.records[index], compression: header.compression)
            let part = stripTrailingExtraData(from: decompressed, flags: header.extraDataFlags)
            raw.append(part)
        }
        if header.textLength > 0, raw.count > header.textLength {
            raw = truncateToUTF8Boundary(raw, maxLength: header.textLength)
        }
        return raw
    }

    private func splitFlows(rawML: Data) throws -> [Data] {
        guard let fdst = pdb.records.first(where: { $0.starts(withASCII: "FDST") }) else {
            return [rawML]
        }
        let sections = try Self.parseFDST(fdst)
        guard !sections.isEmpty else { return [rawML] }
        return try sections.map { section in
            guard section.end <= rawML.count else {
                throw BookParseError.corruptedFile(detail: "KF8 FDST section exceeds rawML length")
            }
            return rawML.subdata(in: section.start..<section.end)
        }
    }

    private func coverImage() -> Data? {
        guard let index = header.coverRecordIndex, index < pdb.records.count else {
            return nil
        }
        let data = pdb.records[index]
        if isImageRecord(data) { return data }
        guard let firstImage = header.firstImageRecord else { return data }
        for i in firstImage..<pdb.records.count {
            if isImageRecord(pdb.records[i]) { return pdb.records[i] }
        }
        return data
    }

    private func isImageRecord(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let prefix = [UInt8](data.prefix(4))
        if prefix[0] == 0xFF && prefix[1] == 0xD8 { return true }
        if prefix[0] == 0x89 && prefix[1] == 0x50 && prefix[2] == 0x4E && prefix[3] == 0x47 { return true }
        if prefix[0] == 0x47 && prefix[1] == 0x49 && prefix[2] == 0x46 && prefix[3] == 0x38 { return true }
        return false
    }

    private static func extractTitle(from html: String) -> String? {
        for pattern in [
            #"<h1[^>]*>([\s\S]*?)</h1>"#,
            #"<h2[^>]*>([\s\S]*?)</h2>"#,
            #"<h3[^>]*>([\s\S]*?)</h3>"#,
            #"<title[^>]*>([\s\S]*?)</title>"#
        ] {
            guard let range = html.range(of: pattern, options: .regularExpression) else {
                continue
            }
            let tag = String(html[range])
            let text = tag
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }
        return nil
    }
}

private extension Data {
    func starts(withASCII prefix: String) -> Bool {
        guard let marker = prefix.data(using: .ascii), count >= marker.count else {
            return false
        }
        return self.prefix(marker.count) == marker
    }
}
