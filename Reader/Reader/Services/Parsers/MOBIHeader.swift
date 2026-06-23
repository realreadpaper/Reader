import Foundation

enum MOBIVariant: Equatable {
    case classicMOBI
    case kf8
    case unsupported(String)
}

enum MOBICompression: Equatable {
    case none
    case palmDoc
    case huff
}

struct MOBIHeader {
    let variant: MOBIVariant
    let compression: MOBICompression
    let firstTextRecord: Int
    let lastTextRecord: Int
    let firstImageRecord: Int?
    let title: String
    let author: String?
    let coverRecordIndex: Int?

    /// record0 头 16 字节是 PalmDOC，之后是 MOBI header
    /// PalmDOC: 0-2 compression, 4-8 textLength, 8-10 recordCount, 10-12 recordSize
    /// MOBI:   16-20 identifier, 20-24 headerLength, 24-28 mobiType, 28-32 textEncoding,
    ///         32-36 uniqueID, 36-40 fileVersion, ...
    static func read(record0: Data) throws -> MOBIHeader {
        guard record0.count >= 16 else {
            throw BookParseError.corruptedFile(detail: "record0 过短")
        }

        let compressionRaw = record0.readUInt16BE(at: 0)
        let compression: MOBICompression
        switch compressionRaw {
        case 1: compression = .none
        case 2: compression = .palmDoc
        case 17480: compression = .huff
        default: compression = .none
        }

        guard record0.count >= 20 else {
            throw BookParseError.corruptedFile(detail: "record0 缺少 MOBI identifier")
        }
        let id = String(data: record0.subdata(in: 16..<20), encoding: .ascii) ?? ""
        guard ["MOBI", "TEXt", "BOUNDARY"].contains(id) else {
            throw BookParseError.corruptedFile(detail: "非 MOBI identifier：\(id)")
        }

        let mobiHeaderLength = Int(record0.readUInt32BE(at: 20))
        guard record0.count >= 16 + mobiHeaderLength else {
            throw BookParseError.corruptedFile(detail: "MOBI header 长度越界")
        }

        let mobiVersion = record0.readUInt32BE(at: 36)
        // MOBI header internal offsets: firstTextRecord at 24, lastTextRecord at 28, firstImageRecord at 108
        // record0 absolute offsets: add 16
        let firstTextRecord: Int
        if record0.count >= 44 {
            firstTextRecord = Int(record0.readUInt32BE(at: 40))
        } else {
            firstTextRecord = 1
        }
        let lastTextRecord: Int
        if record0.count >= 48 {
            lastTextRecord = Int(record0.readUInt32BE(at: 44))
        } else {
            lastTextRecord = 1
        }
        let firstImageRecord: Int
        if record0.count >= 124 {
            firstImageRecord = Int(record0.readUInt32BE(at: 124))
        } else {
            firstImageRecord = 0
        }

        let variant: MOBIVariant
        if compression == .huff {
            variant = .unsupported("HUFF/CDIC 压缩暂未原生实现")
        } else if mobiVersion == 8 {
            variant = .kf8
        } else if [0, 1, 2].contains(compressionRaw) {
            variant = .classicMOBI
        } else {
            variant = .unsupported("未知 MOBI 变体（compression=\(compressionRaw), version=\(mobiVersion)）")
        }

        // EXTH block 起始：record0 offset 16 + mobiHeaderLength
        let exthStart = 16 + mobiHeaderLength
        var title: String? = nil
        var author: String? = nil
        var coverOffset: Int? = nil
        if exthStart + 12 <= record0.count,
           let exthMagic = String(data: record0.subdata(in: exthStart..<(exthStart + 4)), encoding: .ascii),
           exthMagic == "EXTH" {
            let exthHeaderLen = Int(record0.readUInt32BE(at: exthStart + 4))
            let exthCount = Int(record0.readUInt32BE(at: exthStart + 8))
            var p = exthStart + 12
            let end = exthStart + exthHeaderLen
            for _ in 0..<exthCount where p + 8 <= end {
                let type = record0.readUInt32BE(at: p)
                let len = Int(record0.readUInt32BE(at: p + 4))
                guard len >= 8, p + len <= end else { break }
                let valueData = record0.subdata(in: (p + 8)..<(p + len))
                switch type {
                case 100:
                    author = String(data: valueData, encoding: .utf8) ?? String(data: valueData, encoding: .isoLatin1)
                case 503:
                    title = String(data: valueData, encoding: .utf8) ?? String(data: valueData, encoding: .isoLatin1)
                case 201:
                    coverOffset = Int(valueData.readUInt32BE(at: 0))
                default:
                    break
                }
                p += len
            }
        }

        let finalTitle = title ?? "Untitled"
        let coverRecordIndex: Int? = {
            guard let cover = coverOffset, firstImageRecord > 0 else { return nil }
            return firstImageRecord + cover
        }()

        return MOBIHeader(
            variant: variant,
            compression: compression,
            firstTextRecord: firstTextRecord,
            lastTextRecord: lastTextRecord,
            firstImageRecord: firstImageRecord > 0 ? firstImageRecord : nil,
            title: finalTitle,
            author: author,
            coverRecordIndex: coverRecordIndex
        )
    }
}
