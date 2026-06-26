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

    func testParserUsesKF8RecordsAfterHybridBoundary() async throws {
        let classicHTML = Data("<html><body><h1>KF7</h1><p>旧格式正文。</p></body></html>".utf8)
        let rawML = Data("<html><body><h1>KF8 Hybrid</h1><p>boundary 后的 KF8 正文。</p></body></html>".utf8)
        let url = try makeHybridKF8File(
            classicHTML: classicHTML,
            rawML: rawML,
            fdst: makeFDST(sections: [0..<rawML.count])
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertEqual(parsed.chapters.count, 1)
        XCTAssertEqual(parsed.chapters[0].title, "KF8 Hybrid")
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("boundary 后的 KF8 正文"))
        XCTAssertFalse(parsed.chapters[0].bodyHTML.contains("旧格式正文"))
    }

    func testParserExtendsKF8TextRangeToFDSTWhenHeaderCountIsTooSmall() async throws {
        let classicHTML = Data("<html><body><h1>KF7</h1><p>旧格式正文。</p></body></html>".utf8)
        let firstPart = Data("<html><body><h1>KF8 Split</h1>".utf8)
        let secondPart = Data("<p>第二条 rawML record。</p></body></html>".utf8)
        let rawML = firstPart + secondPart
        let url = try makeHybridKF8File(
            classicHTML: classicHTML,
            kf8TextRecordCount: 1,
            rawMLRecords: [firstPart, secondPart],
            fdst: makeFDST(sections: [0..<rawML.count])
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertEqual(parsed.chapters.count, 1)
        XCTAssertEqual(parsed.chapters[0].title, "KF8 Split")
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("第二条 rawML record"))
    }

    func testParserDoesNotTruncateKF8RawMLBeforeFDSTEndWhenTextLengthIsTooSmall() async throws {
        let classicHTML = Data("<html><body><h1>KF7</h1><p>旧格式正文。</p></body></html>".utf8)
        let rawML = Data("<html><body><h1>KF8 Full</h1><p>textLength 偏小但 FDST 范围完整。</p></body></html>".utf8)
        let url = try makeHybridKF8File(
            classicHTML: classicHTML,
            kf8TextLength: rawML.count - 12,
            kf8TextRecordCount: 1,
            rawMLRecords: [rawML],
            fdst: makeFDST(sections: [0..<rawML.count])
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertEqual(parsed.chapters.count, 1)
        XCTAssertEqual(parsed.chapters[0].title, "KF8 Full")
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("FDST 范围完整"))
    }

    func testReconstructorSplitsFirstFlowByKF8IndexOffsetsWhenAvailable() throws {
        let first = Data("<html><body><h1>第一章</h1><p>索引切章。</p></body></html>".utf8)
        let second = Data("<html><body><h1>第二章</h1><p>不是 FDST flow。</p></body></html>".utf8)
        let rawML = first + second
        let pdb = try makeKF8Fixture(
            rawML: rawML,
            fdst: makeFDST(sections: [0..<rawML.count]),
            indexRecords: [makeINDXChapterIndex(offsets: [0, first.count])]
        )
        let header = try MOBIHeader.read(pdb: pdb)

        let book = try KF8Reconstructor(pdb: pdb, header: header, sourceURL: URL(fileURLWithPath: "/tmp/book.azw3")).reconstruct()

        XCTAssertEqual(book.chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertTrue(book.chapters[0].bodyHTML.contains("索引切章"))
        XCTAssertTrue(book.chapters[1].bodyHTML.contains("不是 FDST flow"))
    }

    func testParserReportsNativeKF8FailureInsteadOfZipFailure() async throws {
        let rawML = Data("<html><body><h1>Broken</h1></body></html>".utf8)
        let url = try makeKF8File(
            rawML: rawML,
            fdst: makeFDST(sections: [0..<(rawML.count + 10)])
        )
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await MOBIParser().parse(fileAt: url)
            XCTFail("Expected KF8 reconstruction to fail")
        } catch BookParseError.corruptedFile(let detail) {
            XCTAssertTrue(detail.contains("KF8 rawML 重建失败"), detail)
            XCTAssertFalse(detail.contains("ZIP"), detail)
        }
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
        return try writePalmDatabase(pdb, extension: "azw3")
    }

    private func makeHybridKF8File(classicHTML: Data, rawML: Data, fdst: Data) throws -> URL {
        try makeHybridKF8File(
            classicHTML: classicHTML,
            kf8TextRecordCount: 1,
            rawMLRecords: [rawML],
            fdst: fdst
        )
    }

    private func makeHybridKF8File(
        classicHTML: Data,
        kf8TextLength: Int? = nil,
        kf8TextRecordCount: UInt16,
        rawMLRecords: [Data],
        fdst: Data
    ) throws -> URL {
        let rawMLLength = rawMLRecords.reduce(0) { $0 + $1.count }
        let classicHeader = makeRecord0(textLength: classicHTML.count, textRecordCount: 1, mobiVersion: 6)
        let kf8Header = makeRecord0(textLength: kf8TextLength ?? rawMLLength, textRecordCount: kf8TextRecordCount, mobiVersion: 8)
        var boundary = Data(repeating: 0, count: 16)
        boundary.append(Data("BOUNDARY".utf8))
        let pdb = PalmDatabase(
            name: "Hybrid KF8 Fixture",
            type: "BOOK",
            creator: "MOBI",
            records: [classicHeader, classicHTML, boundary, kf8Header] + rawMLRecords + [fdst]
        )
        return try writePalmDatabase(pdb, extension: "azw3")
    }

    private func writePalmDatabase(_ pdb: PalmDatabase, extension ext: String) throws -> URL {
        var file = Data()
        var name = Data(pdb.name.utf8)
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".\(ext)")
        try file.write(to: url)
        return url
    }

    private func makeKF8Fixture(rawML: Data, fdst: Data, indexRecords: [Data] = []) throws -> PalmDatabase {
        let record0 = makeRecord0(textLength: rawML.count, textRecordCount: 1)
        return PalmDatabase(
            name: "KF8 Fixture",
            type: "BOOK",
            creator: "MOBI",
            records: [record0, rawML, fdst] + indexRecords
        )
    }

    private func makeINDXChapterIndex(offsets: [Int]) -> Data {
        var entries = Data()
        var positions: [Int] = []
        for offset in offsets {
            positions.append(0x48 + entries.count)
            entries.append(0)
            entries.append(0x01)
            entries.append(vwi(offset))
            entries.append(vwi(1))
        }

        let idxtOffset = 0x48 + entries.count
        var data = Data("INDX".utf8)
        data.append(UInt32(0x38).beData)
        data.append(UInt32(0).beData)
        data.append(UInt32(0).beData)
        data.append(UInt32(0).beData)
        data.append(UInt32(idxtOffset).beData)
        data.append(UInt32(offsets.count).beData)
        data.append(UInt32(65001).beData)
        data.append(UInt32(0).beData)
        data.append(UInt32(offsets.count).beData)
        data.append(UInt32(0xFFFFFFFF).beData)
        data.append(UInt32(0xFFFFFFFF).beData)
        data.append(UInt32(0).beData)
        data.append(UInt32(0).beData)
        data.append(Data("TAGX".utf8))
        data.append(UInt32(16).beData)
        data.append(UInt32(1).beData)
        data.append(contentsOf: [6, 2, 0x01, 0])
        data.append(entries)
        data.append(Data("IDXT".utf8))
        for position in positions {
            data.append(UInt16(position).beData)
        }
        return data
    }

    private func vwi(_ value: Int) -> Data {
        precondition(value >= 0)
        if value < 0x80 {
            return Data([UInt8(value) | 0x80])
        }
        var chunks: [UInt8] = []
        var current = value
        repeat {
            chunks.insert(UInt8(current & 0x7F), at: 0)
            current >>= 7
        } while current > 0
        chunks[chunks.count - 1] |= 0x80
        return Data(chunks)
    }

    private func makeRecord0(textLength: Int, textRecordCount: UInt16, mobiVersion: UInt32 = 8) -> Data {
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
        data.append(mobiVersion.beData)

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
