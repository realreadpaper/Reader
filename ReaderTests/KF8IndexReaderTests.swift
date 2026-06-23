import XCTest
@testable import Reader

final class KF8IndexReaderTests: XCTestCase {
    func testParseChapterBoundaries() throws {
        var data = Data()
        data.append("ORDR".data(using: .ascii)!)
        var be32 = UInt32(2).bigEndian
        data.append(Data(bytes: &be32, count: 4))
        be32 = UInt32(0).bigEndian
        data.append(Data(bytes: &be32, count: 4))
        be32 = UInt32(100).bigEndian
        data.append(Data(bytes: &be32, count: 4))

        let reader = KF8IndexReader(data: data)
        let boundaries = reader.chapterOffsets()
        XCTAssertEqual(boundaries, [0, 100])
    }

    func testEmptyDataReturnsEmpty() {
        let reader = KF8IndexReader(data: Data())
        XCTAssertEqual(reader.chapterOffsets(), [])
    }
}
