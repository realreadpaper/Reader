import XCTest
@testable import Reader

final class MOBIParserClassicTests: XCTestCase {
    func testParseClassicMOBIReturnsHtmlBook() async throws {
        let url = try makeClassicMOBIFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertEqual(parsed.renderer, .html)
        XCTAssertEqual(parsed.title, "Fixture Title")
        XCTAssertEqual(parsed.author, "Fixture Author")
        XCTAssertFalse(parsed.chapters.isEmpty)
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("Fixture content"))
    }

    private func makeClassicMOBIFixture() throws -> URL {
        let html = "<html><body><h1>Fixture</h1><p>Fixture content here.</p></body></html>"
        let htmlBytes = Array(html.utf8)

        // PalmDOC: 每 8 个字面值前要 1 个 flag byte（0x00 = 全字面）
        var textRecord = Data()
        var idx = 0
        while idx < htmlBytes.count {
            textRecord.append(0x00)  // flag byte
            for _ in 0..<8 where idx < htmlBytes.count {
                textRecord.append(htmlBytes[idx])
                idx += 1
            }
        }

        var record0 = Data()
        var be16: UInt16
        var be32: UInt32

        // PalmDOC header (16 bytes)
        be16 = UInt16(2).bigEndian
        record0.append(Data(bytes: &be16, count: 2))       // compression = PalmDOC
        record0.append(Data(repeating: 0, count: 2))       // unused
        be32 = UInt32(html.count).bigEndian
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
        be32 = UInt32(1252).bigEndian
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
}
