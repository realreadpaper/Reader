import Foundation

struct PalmDatabase {
    let name: String
    let type: String
    let creator: String
    let records: [Data]
}

enum PalmDBReader {
    static func read(_ data: Data) throws -> PalmDatabase {
        guard data.count >= 78 else {
            BookLog.palm.error("read: header too short: \(data.count) bytes")
            throw BookParseError.corruptedFile(detail: "PalmDB 头过短：\(data.count) bytes")
        }

        let nameData = data.subdata(in: 0..<32)
        let rawName = String(data: nameData, encoding: .ascii) ?? ""
        let name = rawName.trimmingCharacters(in: .controlCharacters).trimmingCharacters(in: .whitespaces)
        // PalmDB layout: type at 60-64, creator at 64-68, numRecords at 76-78
        let type = String(data: data.subdata(in: 60..<64), encoding: .ascii) ?? ""
        let creator = String(data: data.subdata(in: 64..<68), encoding: .ascii) ?? ""

        let numRecords = Int(data.readUInt16BE(at: 76))
        BookLog.palm.info("read: name=\(name, privacy: .public) type=\(type, privacy: .public) creator=\(creator, privacy: .public) numRecords=\(numRecords) fileSize=\(data.count)")
        let indexStart = 78
        let bytesPerIndex = 8
        let headerEnd = indexStart + numRecords * bytesPerIndex + 2
        guard data.count >= headerEnd else {
            BookLog.palm.error("read: record index incomplete, need \(headerEnd) have \(data.count)")
            throw BookParseError.corruptedFile(detail: "PalmDB 记录索引不完整")
        }

        var offsets: [Int] = []
        for i in 0..<numRecords {
            let pos = indexStart + i * bytesPerIndex
            offsets.append(Int(data.readUInt32BE(at: pos)))
        }

        var records: [Data] = []
        for i in 0..<numRecords {
            let start = offsets[i]
            let end = (i + 1 < numRecords) ? offsets[i + 1] : data.count
            guard start <= end, end <= data.count else {
                BookLog.palm.error("read: record \(i) boundary invalid start=\(start) end=\(end) fileSize=\(data.count)")
                throw BookParseError.corruptedFile(detail: "PalmDB 记录 \(i) 边界非法")
            }
            records.append(data.subdata(in: start..<end))
        }
        BookLog.palm.info("read: extracted \(records.count) records, record0=\(records.first?.count ?? 0) bytes")

        return PalmDatabase(name: name, type: type, creator: creator, records: records)
    }
}

extension Data {
    func readUInt16BE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }

    func readUInt32BE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) << 24
             | UInt32(self[offset + 1]) << 16
             | UInt32(self[offset + 2]) << 8
             | UInt32(self[offset + 3])
    }

    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
             | UInt32(self[offset + 1]) << 8
             | UInt32(self[offset + 2]) << 16
             | UInt32(self[offset + 3]) << 24
    }

    func readBytes(at offset: Int, length: Int) -> Data {
        guard offset + length <= count else { return Data() }
        return subdata(in: offset..<(offset + length))
    }
}
