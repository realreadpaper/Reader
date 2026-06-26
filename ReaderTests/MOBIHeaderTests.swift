import XCTest
@testable import Reader

final class MOBIHeaderTests: XCTestCase {
    func testReadClassicMOBIWithPalmDOCCompression() throws {
        let record0 = makeRecord0(
            compression: 2,
            mobiVersion: 6,
            exthRecords: [(100, "Author Name"), (503, "Updated Title")]
        )
        let header = try MOBIHeader.read(record0: record0)
        XCTAssertEqual(header.variant, .classicMOBI)
        XCTAssertEqual(header.compression, .palmDoc)
        XCTAssertEqual(header.title, "Updated Title")
        XCTAssertEqual(header.author, "Author Name")
    }

    func testReadKF8ByVersion8() throws {
        let record0 = makeRecord0(
            compression: 1,
            mobiVersion: 8,
            exthRecords: []
        )
        let header = try MOBIHeader.read(record0: record0)
        XCTAssertEqual(header.variant, .kf8)
    }

    func testReadHUFFKeepsNativeClassicVariant() throws {
        let record0 = makeRecord0(
            compression: 17480,
            mobiVersion: 6,
            exthRecords: []
        )
        let header = try MOBIHeader.read(record0: record0)
        XCTAssertEqual(header.variant, .classicMOBI)
        XCTAssertEqual(header.compression, .huff)
    }

    func testReadSpecOffsetMetadataFields() throws {
        var record0 = makeRecord0(
            compression: 17480,
            mobiVersion: 6,
            exthRecords: []
        )
        record0.replaceSubrange(108..<112, with: UInt32(7).beData)
        record0.replaceSubrange(112..<116, with: UInt32(9).beData)
        record0.replaceSubrange(116..<120, with: UInt32(3).beData)
        record0.replaceSubrange(186..<188, with: UInt16(12).beData)
        record0.replaceSubrange(240..<242, with: UInt16(0x1234).beData)
        record0.replaceSubrange(242..<244, with: UInt16(0x0002).beData)

        let header = try MOBIHeader.read(record0: record0)

        XCTAssertEqual(header.firstImageRecord, 7)
        XCTAssertEqual(header.huffRecordIndex, 9)
        XCTAssertEqual(header.huffRecordCount, 3)
        XCTAssertEqual(header.lastImageRecord, 12)
        XCTAssertEqual(header.extraDataFlags, 0x0002)
    }

    func testReadUsesFirstNonBookIndexToLimitTextRecordsWhenPresent() throws {
        var record0 = makeRecord0(
            compression: 2,
            mobiVersion: 6,
            exthRecords: []
        )
        record0.replaceSubrange(8..<10, with: UInt16(5).beData)
        record0.replaceSubrange(80..<84, with: UInt32(3).beData)

        let header = try MOBIHeader.read(record0: record0)

        XCTAssertEqual(header.firstNonBookIndex, 3)
        XCTAssertEqual(header.lastTextRecord, 2)
    }

    func testReadDoesNotExtendClassicTextRangePastPalmDOCCount() throws {
        var record0 = makeRecord0(
            compression: 2,
            mobiVersion: 6,
            exthRecords: []
        )
        record0.replaceSubrange(8..<10, with: UInt16(605).beData)
        record0.replaceSubrange(80..<84, with: UInt32(607).beData)

        let header = try MOBIHeader.read(record0: record0)

        XCTAssertEqual(header.firstNonBookIndex, 607)
        XCTAssertEqual(header.lastTextRecord, 605)
    }

    private func makeRecord0(
        compression: UInt16,
        mobiVersion: UInt32,
        exthRecords: [(type: UInt32, value: String)]
    ) -> Data {
        var data = Data()
        // PalmDOC header (16 bytes)
        var be16 = compression.bigEndian
        data.append(Data(bytes: &be16, count: 2))           // compression
        data.append(Data(repeating: 0, count: 2))           // unused1
        var be32 = UInt32(1024).bigEndian
        data.append(Data(bytes: &be32, count: 4))           // textLength
        be16 = UInt16(1).bigEndian
        data.append(Data(bytes: &be16, count: 2))           // recordCount
        be16 = UInt16(4096).bigEndian
        data.append(Data(bytes: &be16, count: 2))           // recordSize
        data.append(Data(repeating: 0, count: 4))           // encryption + unused2

        // MOBI header
        // offset 16: identifier "MOBI"
        data.append("MOBI".data(using: .ascii)!)
        // offset 20: headerLength = 232
        be32 = UInt32(232).bigEndian
        data.append(Data(bytes: &be32, count: 4))
        // offset 24: mobiType = 0
        be32 = UInt32(0).bigEndian
        data.append(Data(bytes: &be32, count: 4))
        // offset 28: textEncoding
        be32 = UInt32(1252).bigEndian
        data.append(Data(bytes: &be32, count: 4))
        // offset 32: uniqueID
        be32 = UInt32(1).bigEndian
        data.append(Data(bytes: &be32, count: 4))
        // offset 36: fileVersion
        be32 = mobiVersion.bigEndian
        data.append(Data(bytes: &be32, count: 4))
        // We've appended: "MOBI"(4) + headerLength(4) + mobiType(4) + textEncoding(4) + uniqueID(4) + fileVersion(4) = 24 bytes
        // headerLength=232, so padding = 232 - 24 = 208 bytes
        data.append(Data(repeating: 0, count: 208))

        // EXTH block
        if !exthRecords.isEmpty {
            let exthStart = data.count  // EXTH 起始偏移
            data.append("EXTH".data(using: .ascii)!)
            let headerLenPos = data.count
            be32 = UInt32(0).bigEndian
            data.append(Data(bytes: &be32, count: 4))  // placeholder for headerLength
            be32 = UInt32(exthRecords.count).bigEndian
            data.append(Data(bytes: &be32, count: 4))
            for r in exthRecords {
                let valueData = r.value.data(using: .utf8) ?? Data()
                be32 = r.type.bigEndian
                data.append(Data(bytes: &be32, count: 4))
                be32 = UInt32(8 + valueData.count).bigEndian
                data.append(Data(bytes: &be32, count: 4))
                data.append(valueData)
            }
            // EXTH headerLength 包含 magic；从 exthStart 到 block 末尾
            let headerLen = UInt32(data.count - exthStart)
            var be = headerLen.bigEndian
            data.replaceSubrange(headerLenPos..<(headerLenPos + 4), with: Data(bytes: &be, count: 4))
        }
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
