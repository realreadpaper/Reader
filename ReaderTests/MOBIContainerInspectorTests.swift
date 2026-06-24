import XCTest
@testable import Reader

final class MOBIContainerInspectorTests: XCTestCase {
    func testInspectClassicMOBIReportsHeaderAndEXTHFields() throws {
        let pdb = try PalmDBFixtureBuilder(
            mobiVersion: 6,
            compression: 2,
            textEncoding: 936,
            textRecordCount: 2,
            encryptionType: 0,
            extraDataFlags: 0x0003,
            firstImageRecord: 3,
            exthRecords: [
                (100, Data("Author Name".utf8)),
                (503, Data("Book Title".utf8)),
                (201, UInt32(1).beData)
            ],
            extraRecords: [
                Data("<html>one</html>".utf8),
                Data("<html>two</html>".utf8),
                Data([0xFF, 0xD8, 0xFF, 0xE0])
            ]
        ).build()

        let info = try MOBIContainerInspector.inspect(pdb: pdb)

        XCTAssertEqual(info.name, "Fixture")
        XCTAssertEqual(info.type, "BOOK")
        XCTAssertEqual(info.creator, "MOBI")
        XCTAssertEqual(info.recordCount, 4)
        XCTAssertEqual(info.compressionRaw, 2)
        XCTAssertEqual(info.compression, .palmDoc)
        XCTAssertEqual(info.mobiVersion, 6)
        XCTAssertEqual(info.variant, .classicMOBI)
        XCTAssertEqual(info.textEncodingRaw, 936)
        XCTAssertEqual(info.textRecordCount, 2)
        XCTAssertEqual(info.textRecordRange, 1...2)
        XCTAssertEqual(info.extraDataFlags, 0x0003)
        XCTAssertEqual(info.firstImageRecord, 3)
        XCTAssertEqual(info.coverRecordIndex, 4)
        XCTAssertEqual(info.drmStatus, .none)
        XCTAssertEqual(info.exthTitle, "Book Title")
        XCTAssertEqual(info.exthAuthor, "Author Name")
        XCTAssertFalse(info.hasKF8Boundary)
        XCTAssertTrue(info.markers.isEmpty)
    }

    func testInspectDetectsDRMFromPalmDOCEncryptionType() throws {
        let pdb = try PalmDBFixtureBuilder(
            mobiVersion: 6,
            compression: 2,
            textEncoding: 65001,
            textRecordCount: 1,
            encryptionType: 1,
            extraDataFlags: 0,
            firstImageRecord: 0,
            exthRecords: [],
            extraRecords: [Data("<html>encrypted</html>".utf8)]
        ).build()

        let info = try MOBIContainerInspector.inspect(pdb: pdb)

        XCTAssertEqual(info.drmStatus, .encrypted(type: 1))
    }

    func testInspectDetectsKF8BoundaryAndMarkerRecords() throws {
        var boundary = Data(repeating: 0, count: 16)
        boundary.append("BOUNDARY".data(using: .ascii)!)

        let pdb = try PalmDBFixtureBuilder(
            mobiVersion: 6,
            compression: 1,
            textEncoding: 65001,
            textRecordCount: 1,
            encryptionType: 0,
            extraDataFlags: 0,
            firstImageRecord: 0,
            exthRecords: [],
            extraRecords: [
                boundary,
                Data("FDST".utf8) + UInt32(16).beData,
                Data("INDX".utf8) + UInt32(24).beData,
                Data("RESC".utf8) + UInt32(32).beData
            ]
        ).build()

        let info = try MOBIContainerInspector.inspect(pdb: pdb)

        XCTAssertEqual(info.variant, .kf8)
        XCTAssertTrue(info.hasKF8Boundary)
        XCTAssertEqual(info.kf8BoundaryRecordIndex, 1)
        XCTAssertTrue(info.markers.contains(MOBIRecordMarker(kind: "FDST", recordIndex: 2)))
        XCTAssertTrue(info.markers.contains(MOBIRecordMarker(kind: "INDX", recordIndex: 3)))
        XCTAssertTrue(info.markers.contains(MOBIRecordMarker(kind: "RESC", recordIndex: 4)))
    }

    func testInspectThrowsForMissingRecord0() {
        let pdb = PalmDatabase(name: "Empty", type: "BOOK", creator: "MOBI", records: [])

        XCTAssertThrowsError(try MOBIContainerInspector.inspect(pdb: pdb)) { error in
            guard case BookParseError.corruptedFile(let detail) = error else {
                XCTFail("错误类型不对：\(error)")
                return
            }
            XCTAssertTrue(detail.contains("record0"))
        }
    }
}

private struct PalmDBFixtureBuilder {
    let mobiVersion: UInt32
    let compression: UInt16
    let textEncoding: UInt32
    let textRecordCount: UInt16
    let encryptionType: UInt16
    let extraDataFlags: UInt32
    let firstImageRecord: UInt32
    let exthRecords: [(UInt32, Data)]
    let extraRecords: [Data]

    func build() throws -> PalmDatabase {
        let record0 = makeRecord0()
        return PalmDatabase(
            name: "Fixture",
            type: "BOOK",
            creator: "MOBI",
            records: [record0] + extraRecords
        )
    }

    private func makeRecord0() -> Data {
        var data = Data()
        data.append(compression.beData)
        data.append(UInt16(0).beData)
        data.append(UInt32(2048).beData)
        data.append(textRecordCount.beData)
        data.append(UInt16(4096).beData)
        data.append(encryptionType.beData)
        data.append(UInt16(0).beData)

        data.append("MOBI".data(using: .ascii)!)
        data.append(UInt32(232).beData)
        data.append(UInt32(2).beData)
        data.append(textEncoding.beData)
        data.append(UInt32(1).beData)
        data.append(mobiVersion.beData)

        appendPadding(toRecord0Offset: 124, data: &data)
        data.append(firstImageRecord.beData)

        appendPadding(toRecord0Offset: 244, data: &data)
        data.replaceSubrange(240..<244, with: extraDataFlags.beData)

        appendPadding(toRecord0Offset: 248, data: &data)

        if !exthRecords.isEmpty {
            let exthStart = data.count
            data.append("EXTH".data(using: .ascii)!)
            data.append(UInt32(0).beData)
            data.append(UInt32(exthRecords.count).beData)
            for (type, value) in exthRecords {
                data.append(type.beData)
                data.append(UInt32(8 + value.count).beData)
                data.append(value)
            }
            let exthLength = UInt32(data.count - exthStart)
            data.replaceSubrange((exthStart + 4)..<(exthStart + 8), with: exthLength.beData)
        }

        return data
    }

    private func appendPadding(toRecord0Offset target: Int, data: inout Data) {
        if data.count < target {
            data.append(Data(repeating: 0, count: target - data.count))
        }
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
