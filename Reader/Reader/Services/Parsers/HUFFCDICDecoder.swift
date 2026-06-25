import Foundation

final class HUFFCDICDecoder {
    private struct Dict1Entry {
        let codelen: Int       // 0–31
        let term: Bool
        let maxcode: UInt32
    }

    private let dict1: [Dict1Entry]
    private var mincode: [UInt32]
    private var maxcode: [UInt32]
    private var dictionary: [DictEntry] = []

    private enum DictEntry {
        case raw(Data)
        case compressed(Data)
        case decompressing
    }

    // MARK: - Init

    init(huffRecord: Data, cdicRecords: [Data]) throws {
        guard huffRecord.count >= 24,
              String(data: huffRecord.prefix(4), encoding: .ascii) == "HUFF" else {
            throw BookParseError.corruptedFile(detail: "HUFF/CDIC dictionary missing HUFF record")
        }

        let off1 = Int(huffRecord.readUInt32BE(at: 8))
        let off2 = Int(huffRecord.readUInt32BE(at: 12))

        // dict1: 256 entries
        var d1 = [Dict1Entry]()
        d1.reserveCapacity(256)
        for i in 0..<256 {
            guard off1 + i * 4 + 4 <= huffRecord.count else {
                throw BookParseError.corruptedFile(detail: "HUFF dict1 overruns record")
            }
            let v = huffRecord.readUInt32BE(at: off1 + i * 4)
            let codelen = Int(v & 0x1F)
            let term = (v & 0x80) != 0
            let rawMax = v >> 8
            let mc: UInt32 = codelen == 0 ? 0 : ((rawMax &+ 1) &<< (32 - codelen)) &- 1
            d1.append(Dict1Entry(codelen: codelen, term: term, maxcode: mc))
        }
        self.dict1 = d1

        // dict2: 32 pairs of (min, max) for codelen 1..32
        var minc = [UInt32](repeating: 0, count: 33)
        var maxc = [UInt32](repeating: 0, count: 33)
        for len in 1...32 {
            let idx = (len - 1) * 8
            guard off2 + idx + 8 <= huffRecord.count else {
                throw BookParseError.corruptedFile(detail: "HUFF dict2 overruns record")
            }
            let rawMin = huffRecord.readUInt32BE(at: off2 + idx)
            let rawMax = huffRecord.readUInt32BE(at: off2 + idx + 4)
            minc[len] = rawMin &<< (32 - len)
            maxc[len] = ((rawMax &+ 1) &<< (32 - len)) &- 1
        }
        self.mincode = minc
        self.maxcode = maxc

        guard !cdicRecords.isEmpty else {
            throw BookParseError.corruptedFile(detail: "HUFF/CDIC dictionary missing CDIC records")
        }

        for cdic in cdicRecords {
            try loadCDIC(cdic)
        }
    }

    convenience init(records: [Data]) throws {
        let huff = records.first { $0.starts(withASCII: "HUFF") }
        let cdic = records.filter { $0.starts(withASCII: "CDIC") }
        guard let huff else {
            throw BookParseError.corruptedFile(detail: "HUFF/CDIC dictionary missing HUFF record")
        }
        try self.init(huffRecord: huff, cdicRecords: cdic)
    }

    // MARK: - Decompress

    func decompress(_ data: Data) throws -> Data {
        let padded = data + Data(repeating: 0, count: 8)
        var pos = 8
        var x = padded.readUInt64BE(at: 0)
        var n = 32

        var output = Data()
        output.reserveCapacity(data.count * 2)

        while pos <= padded.count {
            // refill when needed
            if n <= 0 {
                guard pos + 4 <= padded.count else { break }
                let next32 = padded.readUInt32BE(at: pos)
                x = (x &<< 32) | UInt64(next32)
                pos += 4
                n += 32
            }

            let code = UInt32((x >> n) & 0xFFFFFFFF)

            // stage 1: dict1 lookup via top 8 bits
            let idx = Int(code >> 24)
            let entry = dict1[idx]
            var codelen = entry.codelen

            guard codelen > 0 else {
                throw BookParseError.corruptedFile(detail: "HUFF/CDIC zero-length code in dict1[\(idx)]")
            }

            // stage 2: if non-terminal, walk codelen upward
            var maxc = entry.maxcode
            if !entry.term {
                while codelen <= 32, code < mincode[codelen] {
                    codelen += 1
                }
                guard codelen <= 32 else {
                    throw BookParseError.corruptedFile(detail: "HUFF/CDIC codelen overflow during non-terminal walk")
                }
                maxc = maxcode[codelen]
            }

            // dictionary index
            let dictIdx = Int((maxc &- code) >> (32 - codelen))

            n -= codelen

            let phrase = try resolveEntry(dictIdx)
            output.append(phrase)
        }

        return output
    }

    // MARK: - Private

    private func loadCDIC(_ data: Data) throws {
        guard data.count >= 16,
              String(data: data.prefix(4), encoding: .ascii) == "CDIC" else {
            throw BookParseError.corruptedFile(detail: "HUFF/CDIC invalid CDIC record")
        }

        let phrases = Int(data.readUInt32BE(at: 8))
        let bits = Int(data.readUInt32BE(at: 12))
        let n = min(1 << bits, phrases - dictionary.count)
        guard n > 0 else { return }

        for i in 0..<n {
            let off = Int(data.readUInt16BE(at: 16 + i * 2))
            guard 20 + off + 2 <= data.count else {
                throw BookParseError.corruptedFile(detail: "CDIC phrase offset overrun")
            }
            let blen = Int(data.readUInt16BE(at: 18 + off))
            let flag = (blen & 0x8000) != 0
            let length = blen & 0x7FFF
            let start = 20 + off
            guard start + length <= data.count else {
                throw BookParseError.corruptedFile(detail: "CDIC phrase length overrun")
            }
            let slice = data.subdata(in: start..<(start + length))
            dictionary.append(flag ? .raw(slice) : .compressed(slice))
        }
    }

    private func resolveEntry(_ index: Int) throws -> Data {
        guard index < dictionary.count else {
            throw BookParseError.corruptedFile(detail: "HUFF/CDIC dictionary index \(index) out of range (count=\(dictionary.count))")
        }
        switch dictionary[index] {
        case .raw(let data):
            return data
        case .compressed(let data):
            // recursion guard
            dictionary[index] = .decompressing
            let result = try decompress(data)
            dictionary[index] = .raw(result)
            return result
        case .decompressing:
            throw BookParseError.corruptedFile(detail: "HUFF/CDIC circular reference at dictionary[\(index)]")
        }
    }
}

private extension Data {
    func starts(withASCII prefix: String) -> Bool {
        guard let marker = prefix.data(using: .ascii), count >= marker.count else {
            return false
        }
        return self.prefix(marker.count) == marker
    }

    func readUInt64BE(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 where offset + i < count {
            value = (value << 8) | UInt64(self[offset + i])
        }
        return value
    }
}
