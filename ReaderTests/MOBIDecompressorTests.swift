import XCTest
@testable import Reader

final class MOBIDecompressorTests: XCTestCase {
    func testNoCompressionReturnsInput() throws {
        let input = Data([0x01, 0x02, 0x03])
        let output = try MOBIDecompressor.decompress(input, compression: .none)
        XCTAssertEqual(output, input)
    }

    func testPalmDocAllLiterals() throws {
        // flags = 0x00 表示后 8 字节全是字面值
        let input = Data([0x00, 0x41, 0x42, 0x43])
        let output = try MOBIDecompressor.decompress(input, compression: .palmDoc)
        XCTAssertEqual(output, Data([0x41, 0x42, 0x43]))  // "ABC"
    }

    func testPalmDocSixLiterals() throws {
        // 1 个 flag byte + 6 个字面值（< 8，剩余 bit 自动跳过）
        let input = Data([0x00, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46])
        let output = try MOBIDecompressor.decompress(input, compression: .palmDoc)
        XCTAssertEqual(String(data: output, encoding: .ascii), "ABCDEF")
    }

    func testHuffThrowsUnsupported() {
        XCTAssertThrowsError(
            try MOBIDecompressor.decompress(Data([0x00]), compression: .huff)
        ) { error in
            guard case BookParseError.unsupportedFormat = error else {
                XCTFail("错误类型不对：\(error)")
                return
            }
        }
    }
}
