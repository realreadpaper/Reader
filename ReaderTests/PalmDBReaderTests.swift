import XCTest
@testable import Reader

final class PalmDBReaderTests: XCTestCase {
    func testReadParsesHeaderAndRecords() throws {
        let data = try makeMinimalPalmDB(recordCount: 2, recordSize: 16)
        let pdb = try PalmDBReader.read(data)

        XCTAssertEqual(pdb.name, "TestBook")
        XCTAssertEqual(pdb.type, "BOOK")
        XCTAssertEqual(pdb.creator, "MOBI")
        XCTAssertEqual(pdb.records.count, 2)
        XCTAssertEqual(pdb.records[0].count, 16)
        XCTAssertEqual(pdb.records[1].count, 16)
    }

    func testReadThrowsOnDataTooShort() {
        XCTAssertThrowsError(try PalmDBReader.read(Data([0x00]))) { error in
            guard case BookParseError.corruptedFile = error else {
                XCTFail("错误类型不对：\(error)")
                return
            }
        }
    }

    private func makeMinimalPalmDB(recordCount: Int, recordSize: Int) throws -> Data {
        var data = Data()
        var name = "TestBook".data(using: .ascii)!
        name.append(Data(repeating: 0x00, count: 32 - name.count))
        data.append(name)
        // attributes(2) + version(2) + 4 timestamps(16) + modNum(4) + appInfo(4) + sortInfo(4) = 32 bytes
        data.append(Data(repeating: 0, count: 28))
        data.append("BOOK".data(using: .ascii)!)  // 60-64
        data.append("MOBI".data(using: .ascii)!)  // 64-68
        data.append(Data(repeating: 0, count: 8))  // uniqueIDSeed + nextRecordListID (68-76)
        var be16 = UInt16(recordCount).bigEndian
        data.append(Data(bytes: &be16, count: 2))  // numRecords (76-78)
        let headerSize = 78 + recordCount * 8 + 2
        for i in 0..<recordCount {
            var be32 = UInt32(headerSize + i * recordSize).bigEndian
            data.append(Data(bytes: &be32, count: 4))
            data.append(Data(repeating: 0, count: 4))  // attr + uniqueID
        }
        data.append(Data(repeating: 0, count: 2))  // padding
        for _ in 0..<recordCount {
            data.append(Data(repeating: 0xAB, count: recordSize))
        }
        return data
    }
}
