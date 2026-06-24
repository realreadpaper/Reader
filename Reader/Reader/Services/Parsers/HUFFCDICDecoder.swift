import Foundation

struct HUFFCDICDecoder {
    let huffRecord: Data
    let cdicRecords: [Data]

    init(huffRecord: Data, cdicRecords: [Data]) throws {
        guard huffRecord.starts(withASCII: "HUFF") else {
            throw BookParseError.corruptedFile(detail: "HUFF/CDIC dictionary missing HUFF record")
        }
        guard !cdicRecords.isEmpty else {
            throw BookParseError.corruptedFile(detail: "HUFF/CDIC dictionary missing CDIC records")
        }
        guard cdicRecords.allSatisfy({ $0.starts(withASCII: "CDIC") }) else {
            throw BookParseError.corruptedFile(detail: "HUFF/CDIC dictionary contains invalid CDIC record")
        }
        self.huffRecord = huffRecord
        self.cdicRecords = cdicRecords
    }

    init(records: [Data]) throws {
        let huff = records.first { $0.starts(withASCII: "HUFF") }
        let cdic = records.filter { $0.starts(withASCII: "CDIC") }
        guard let huff else {
            throw BookParseError.corruptedFile(detail: "HUFF/CDIC dictionary missing HUFF record")
        }
        try self.init(huffRecord: huff, cdicRecords: cdic)
    }

    func decompress(_ data: Data) throws -> Data {
        throw BookParseError.unsupportedFormat(detail: "HUFF/CDIC dictionary found, but Huffman table expansion is not implemented")
    }
}

private extension Data {
    func starts(withASCII prefix: String) -> Bool {
        guard let marker = prefix.data(using: .ascii), count >= marker.count else {
            return false
        }
        return self.prefix(marker.count) == marker
    }
}
