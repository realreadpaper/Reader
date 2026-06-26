import XCTest
@testable import Reader

final class KF8IndexReaderTests: XCTestCase {
    func testParseChapterBoundariesFromINDXTAGXEntries() throws {
        let reader = KF8IndexReader(data: makeINDXChapterIndex(offsets: [0, 100]))

        XCTAssertEqual(reader.chapterOffsets(), [0, 100])
    }

    func testORDRAloneIsIgnoredBecauseRealKF8UsesINDX() {
        var data = Data("ORDR".utf8)
        data.append(UInt32(2).beData)
        data.append(UInt32(0).beData)
        data.append(UInt32(100).beData)

        XCTAssertEqual(KF8IndexReader(data: data).chapterOffsets(), [])
    }

    func testEmptyDataReturnsEmpty() {
        let reader = KF8IndexReader(data: Data())
        XCTAssertEqual(reader.chapterOffsets(), [])
    }

    private func makeINDXChapterIndex(offsets: [Int]) -> Data {
        var entries = Data()
        var positions: [Int] = []
        for offset in offsets {
            positions.append(0x48 + entries.count)
            entries.append(0)      // empty leading text
            entries.append(0x01)   // control byte: tag 6 present
            entries.append(vwi(offset))
            entries.append(vwi(1)) // paired length, ignored by chapter offset reader
        }

        let idxtOffset = 0x48 + entries.count
        var data = Data("INDX".utf8)
        data.append(UInt32(0x38).beData)              // header length; TAGX starts here
        data.append(UInt32(0).beData)                 // nul1
        data.append(UInt32(0).beData)                 // type
        data.append(UInt32(0).beData)                 // gen
        data.append(UInt32(idxtOffset).beData)        // IDXT start
        data.append(UInt32(offsets.count).beData)     // entry count
        data.append(UInt32(65001).beData)             // codepage
        data.append(UInt32(0).beData)                 // language
        data.append(UInt32(offsets.count).beData)     // total
        data.append(UInt32(0xFFFFFFFF).beData)        // ordt
        data.append(UInt32(0xFFFFFFFF).beData)        // ligt
        data.append(UInt32(0).beData)                 // nligt
        data.append(UInt32(0).beData)                 // nctoc
        data.append(Data("TAGX".utf8))
        data.append(UInt32(16).beData)                // first tag entry offset
        data.append(UInt32(1).beData)                 // control byte count
        data.append(contentsOf: [6, 2, 0x01, 0])      // tag 6: start/length pair
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
