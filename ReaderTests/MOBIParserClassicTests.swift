import XCTest
@testable import Reader

final class MOBIParserClassicTests: XCTestCase {
    func testParseClassicMOBIReturnsHtmlBook() async throws {
        let html = "<html><body><h1>Fixture</h1><p>Fixture content here.</p></body></html>"
        let url = try makeClassicMOBIFixture(html: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertEqual(parsed.renderer, .html)
        XCTAssertEqual(parsed.title, "Fixture Title")
        XCTAssertEqual(parsed.author, "Fixture Author")
        XCTAssertFalse(parsed.chapters.isEmpty)
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("Fixture content"))
    }

    func testParseClassicMOBIDecodesChineseUTF8PalmDoc() async throws {
        let html = "<html><body><h1>简单的逻辑学</h1><p>逻辑是一门独立的学问。</p></body></html>"
        let url = try makeClassicMOBIFixture(html: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertFalse(parsed.chapters.isEmpty)
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("简单的逻辑学"))
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("逻辑是一门独立的学问"))
    }

    func testParseClassicMOBISplitsPageBreaksIntoPages() async throws {
        let html = """
        <html><body><p>第一页内容</p><mbp:pagebreak/><p>第二页内容</p></body></html>
        """
        let url = try makeClassicMOBIFixture(html: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertEqual(parsed.chapters.count, 2)
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("第一页内容"))
        XCTAssertTrue(parsed.chapters[1].bodyHTML.contains("第二页内容"))
        XCTAssertEqual(parsed.toc.map(\.title), ["第 1 页", "第 2 页"])
    }

    func testParseClassicMOBIContinuesPaginatingLongPageBreakSections() async throws {
        let longPage = (0..<420).map { "<p>第 \($0) 段内容，用来模拟一个很长的 MOBI 页面。</p>" }.joined()
        let html = "<html><body>\(longPage)<mbp:pagebreak/>\(longPage)</body></html>"
        let url = try makeClassicMOBIFixture(html: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertGreaterThan(parsed.chapters.count, 2)
        XCTAssertEqual(parsed.toc.first?.title, "第 1 页")
        XCTAssertEqual(parsed.toc.last?.title, "第 \(parsed.chapters.count) 页")
    }

    func testDecodeHTMLUsesLossyUTF8ForDeclaredUTF8() {
        var raw = Data("<p>逻辑".utf8)
        raw.append(0x91)
        raw.append(Data("发现</p>".utf8))

        let html = MOBIParser.decodeHTML(raw, declaredEncoding: .utf8)

        XCTAssertTrue(html.contains("逻辑"))
        XCTAssertTrue(html.contains("发现"))
        XCTAssertFalse(html.contains("é»"))
    }

    private func makeClassicMOBIFixture(html: String) throws -> URL {
        let textRecord = palmDocLiteralRecord(for: Data(html.utf8))

        var record0 = Data()
        var be16: UInt16
        var be32: UInt32

        // PalmDOC header (16 bytes)
        be16 = UInt16(2).bigEndian
        record0.append(Data(bytes: &be16, count: 2))       // compression = PalmDOC
        record0.append(Data(repeating: 0, count: 2))       // unused
        be32 = UInt32(Data(html.utf8).count).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // textLength
        be16 = UInt16(1).bigEndian
        record0.append(Data(bytes: &be16, count: 2))       // recordCount = 1
        be16 = UInt16(4096).bigEndian
        record0.append(Data(bytes: &be16, count: 2))       // recordSize
        record0.append(Data(repeating: 0, count: 4))       // encryption + unused

        // MOBI header
        record0.append("MOBI".data(using: .ascii)!)        // identifier
        be32 = UInt32(232).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // headerLength
        be32 = UInt32(0).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // mobiType
        be32 = UInt32(65001).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // textEncoding
        be32 = UInt32(1).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // uniqueID
        be32 = UInt32(6).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // fileVersion = 6 (classic)
        // firstTextRecord (record0 offset 44)
        be32 = UInt32(1).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        // lastTextRecord (record0 offset 48)
        be32 = UInt32(1).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        // 填充到 MOBI header 总长 232
        // 已写 MOBI 部分: 4(identifier)+4(headerLen)+4(mobiType)+4(textEncoding)+4(uniqueID)+4(version)+4(firstText)+4(lastText) = 32 bytes
        // 剩 232-32 = 200 bytes
        record0.append(Data(repeating: 0, count: 200))

        // EXTH block
        let exthStart = record0.count
        record0.append("EXTH".data(using: .ascii)!)
        let headerLenPos = record0.count
        be32 = UInt32(0).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        be32 = UInt32(2).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // record count
        // type 100 = author
        let authorData = "Fixture Author".data(using: .utf8)!
        be32 = UInt32(100).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        be32 = UInt32(8 + authorData.count).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        record0.append(authorData)
        // type 503 = updatedTitle
        let titleData = "Fixture Title".data(using: .utf8)!
        be32 = UInt32(503).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        be32 = UInt32(8 + titleData.count).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        record0.append(titleData)
        let exthLen = UInt32(record0.count - exthStart)
        var be = exthLen.bigEndian
        record0.replaceSubrange(headerLenPos..<(headerLenPos + 4), with: Data(bytes: &be, count: 4))

        // PalmDB
        var pdb = Data()
        var name = "Fixture".data(using: .ascii)!
        name.append(Data(repeating: 0x00, count: 32 - name.count))
        pdb.append(name)
        pdb.append(Data(repeating: 0, count: 28))          // attrs..sortInfo
        pdb.append("BOOK".data(using: .ascii)!)            // type
        pdb.append("MOBI".data(using: .ascii)!)            // creator
        pdb.append(Data(repeating: 0, count: 8))           // uniqueIDSeed + nextRecordListID
        be16 = UInt16(2).bigEndian
        pdb.append(Data(bytes: &be16, count: 2))           // numRecords = 2
        let headerSize = 78 + 2 * 8 + 2                    // = 96
        be32 = UInt32(headerSize).bigEndian
        pdb.append(Data(bytes: &be32, count: 4))           // record 0 offset
        pdb.append(Data(repeating: 0, count: 4))
        be32 = UInt32(headerSize + record0.count).bigEndian
        pdb.append(Data(bytes: &be32, count: 4))           // record 1 offset
        pdb.append(Data(repeating: 0, count: 4))
        pdb.append(Data(repeating: 0, count: 2))           // padding
        pdb.append(record0)
        pdb.append(textRecord)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mobi")
        try pdb.write(to: url)
        return url
    }

    private func palmDocLiteralRecord(for htmlData: Data) -> Data {
        let htmlBytes = Array(htmlData)
        var textRecord = Data()
        var idx = 0
        while idx < htmlBytes.count {
            let byte = htmlBytes[idx]
            if byte >= 0x09 && byte <= 0x7F {
                textRecord.append(byte)
                idx += 1
            } else {
                let start = idx
                idx += 1
                while idx < htmlBytes.count,
                      idx - start < 8,
                      !(htmlBytes[idx] >= 0x09 && htmlBytes[idx] <= 0x7F) {
                    idx += 1
                }
                textRecord.append(UInt8(idx - start))
                textRecord.append(contentsOf: htmlBytes[start..<idx])
            }
        }
        return textRecord
    }
}
