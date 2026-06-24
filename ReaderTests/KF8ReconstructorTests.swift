import XCTest
@testable import Reader

final class KF8ReconstructorTests: XCTestCase {
    func testParseFDSTSections() throws {
        let fdst = makeFDST(sections: [0..<42, 42..<80])

        let sections = try KF8Reconstructor.parseFDST(fdst)

        XCTAssertEqual(sections, [
            KF8Reconstructor.FlowSection(start: 0, end: 42),
            KF8Reconstructor.FlowSection(start: 42, end: 80)
        ])
    }

    func testReconstructsRawMLFlowsWithoutZipPayload() throws {
        let rawML = """
        <html><head><title>第一章</title></head><body><h1>第一章</h1><p>直接 KF8 正文。</p></body></html>
        <html><body><h1>第二章</h1><p>没有 EPUB ZIP。</p></body></html>
        """
        let split = rawML.range(of: "<html><body><h1>第二章")!.lowerBound
        let splitOffset = rawML.utf8.distance(from: rawML.utf8.startIndex, to: String(rawML[..<split]).utf8.endIndex)
        let pdb = try makeKF8Fixture(
            rawML: Data(rawML.utf8),
            fdst: makeFDST(sections: [0..<splitOffset, splitOffset..<Data(rawML.utf8).count])
        )
        let header = try MOBIHeader.read(pdb: pdb)

        let book = try KF8Reconstructor(pdb: pdb, header: header, sourceURL: URL(fileURLWithPath: "/tmp/book.azw3")).reconstruct()

        XCTAssertEqual(book.chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertTrue(book.chapters[0].bodyHTML.contains("直接 KF8 正文"))
        XCTAssertTrue(book.chapters[1].bodyHTML.contains("没有 EPUB ZIP"))
        XCTAssertEqual(book.toc.map(\.chapterIndex), [0, 1])
    }

    func testParserUsesNativeKF8ReconstructionWhenNoZipExists() async throws {
        let rawML = """
        <html><body><h1>AZW3 章节</h1><p>KF8 rawML 直接解析。</p></body></html>
        """
        let url = try makeKF8File(
            rawML: Data(rawML.utf8),
            fdst: makeFDST(sections: [0..<Data(rawML.utf8).count])
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertEqual(parsed.title, "KF8 Fixture")
        XCTAssertEqual(parsed.chapters.count, 1)
        XCTAssertEqual(parsed.chapters[0].title, "AZW3 章节")
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("KF8 rawML 直接解析"))
    }

    private func makeFDST(sections: [Range<Int>]) -> Data {
        var data = Data("FDST".utf8)
        data.append(UInt32(12 + sections.count * 8).beData)
        data.append(UInt32(sections.count).beData)
        for section in sections {
            data.append(UInt32(section.lowerBound).beData)
            data.append(UInt32(section.upperBound).beData)
        }
        return data
    }

    private func makeKF8File(rawML: Data, fdst: Data) throws -> URL {
        let pdb = try makeKF8Fixture(rawML: rawML, fdst: fdst)
        var file = Data()
        var name = Data("KF8 Fixture".utf8)
        name.append(Data(repeating: 0, count: 32 - name.count))
        file.append(name)
        file.append(Data(repeating: 0, count: 28))
        file.append(Data("BOOK".utf8))
        file.append(Data("MOBI".utf8))
        file.append(Data(repeating: 0, count: 8))
        file.append(UInt16(pdb.records.count).beData)
        let headerSize = 78 + pdb.records.count * 8 + 2
        var nextOffset = headerSize
        for record in pdb.records {
            file.append(UInt32(nextOffset).beData)
            file.append(Data(repeating: 0, count: 4))
            nextOffset += record.count
        }
        file.append(Data(repeating: 0, count: 2))
        for record in pdb.records {
            file.append(record)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".azw3")
        try file.write(to: url)
        return url
    }

    private func makeKF8Fixture(rawML: Data, fdst: Data) throws -> PalmDatabase {
        let record0 = makeRecord0(textLength: rawML.count, textRecordCount: 1)
        return PalmDatabase(
            name: "KF8 Fixture",
            type: "BOOK",
            creator: "MOBI",
            records: [record0, rawML, fdst]
        )
    }

    private func makeRecord0(textLength: Int, textRecordCount: UInt16) -> Data {
        var data = Data()
        data.append(UInt16(1).beData)
        data.append(UInt16(0).beData)
        data.append(UInt32(textLength).beData)
        data.append(textRecordCount.beData)
        data.append(UInt16(4096).beData)
        data.append(UInt16(0).beData)
        data.append(UInt16(0).beData)

        data.append(Data("MOBI".utf8))
        data.append(UInt32(232).beData)
        data.append(UInt32(2).beData)
        data.append(UInt32(65001).beData)
        data.append(UInt32(1).beData)
        data.append(UInt32(8).beData)

        if data.count < 248 {
            data.append(Data(repeating: 0, count: 248 - data.count))
        }

        let exthStart = data.count
        data.append(Data("EXTH".utf8))
        data.append(UInt32(0).beData)
        data.append(UInt32(1).beData)
        let title = Data("KF8 Fixture".utf8)
        data.append(UInt32(503).beData)
        data.append(UInt32(8 + title.count).beData)
        data.append(title)
        data.replaceSubrange((exthStart + 4)..<(exthStart + 8), with: UInt32(data.count - exthStart).beData)
        return data
    }
}

private extension UInt16 {
    var beData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: 2)
    }
}

private extension UInt32 {
    var beData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: 4)
    }
}
