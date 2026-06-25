import Foundation

extension String.Encoding {
    /// GB18030 是 GBK / GB2312 的超集，覆盖简体中文
    static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )
    /// Big5 繁体中文
    static let big5 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        )
    )
    /// EUC-KR 韩文
    static let eucKR = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
        )
    )
}

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
    let textLength: Int
    let firstImageRecord: Int?
    let textEncodingRaw: UInt32
    let extraDataFlags: UInt32
    let title: String
    let author: String?
    let coverRecordIndex: Int?

    /// 将 MOBI 头里声明的 text encoding codepage 映射到 Swift String.Encoding
    /// 常见值：1252=Western, 65001=UTF-8, 936=GBK/GB2312, 950=Big5
    var preferredTextEncoding: String.Encoding? {
        switch textEncodingRaw {
        case 1252: return String.Encoding.windowsCP1252
        case 65001: return String.Encoding.utf8
        case 936: return .gb18030
        case 950: return .big5
        default: return nil
        }
    }

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
            BookLog.mobi.error("read: non-MOBI identifier in record0: \(id, privacy: .public) record0Size=\(record0.count)")
            throw BookParseError.corruptedFile(detail: "非 MOBI identifier：\(id)")
        }

        let mobiHeaderLength = Int(record0.readUInt32BE(at: 20))
        guard record0.count >= 16 + mobiHeaderLength else {
            BookLog.mobi.error("read: MOBI header length overflows record0: headerLen=\(mobiHeaderLength) record0Size=\(record0.count)")
            throw BookParseError.corruptedFile(detail: "MOBI header 长度越界")
        }

        let mobiVersion = record0.readUInt32BE(at: 36)
        let textEncodingRaw = record0.readUInt32BE(at: 28)
        let textLength = Int(record0.readUInt32BE(at: 4))
        let extraDataFlags = record0.count >= 244 ? record0.readUInt32BE(at: 240) : 0
        // PalmDOC 头 offset 8-10 是 text record count（不含 record0 头记录）
        // 这是经典 MOBI 文本范围的权威来源，比 MOBI header 内部的字段更可靠
        let palmDocTextRecordCount = Int(record0.readUInt16BE(at: 8))
        BookLog.mobi.info("read: record0Size=\(record0.count) id=\(id, privacy: .public) headerLen=\(mobiHeaderLength) version=\(mobiVersion) compression=\(compressionRaw) textEncoding=\(textEncodingRaw) palmDocTextRecordCount=\(palmDocTextRecordCount)")

        // 经典 MOBI 的文本记录范围：record 0 是头，records 1..palmDocTextRecordCount 是文本
        // 注意：MOBI header 偏移 24/28 在不同实现里定义不一致（generator index / first non-book index），
        // 真实文件常为 0xFFFFFFFF，不能作为文本范围使用
        let firstTextRecord = 1
        let lastTextRecord: Int = {
            // PalmDOC recordCount 为 0 或异常时退回到 record0 之外的所有记录
            if palmDocTextRecordCount > 0 {
                return palmDocTextRecordCount
            }
            return 1
        }()

        // firstImageRecord: MOBI header offset 108 (record0 offset 124)
        // 部分老文件该字段缺失或为 0，此时返回 nil
        let firstImageRecord: Int
        if record0.count >= 128 {
            firstImageRecord = Int(record0.readUInt32BE(at: 124))
        } else {
            firstImageRecord = 0
        }

        let variant: MOBIVariant
        if mobiVersion == 8 {
            variant = .kf8
        } else if [0, 1, 2, 17480].contains(compressionRaw) {
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
                    author = String(data: valueData, encoding: .utf8) ?? String(data: valueData, encoding: .gb18030) ?? String(data: valueData, encoding: .isoLatin1)
                case 503:
                    title = String(data: valueData, encoding: .utf8) ?? String(data: valueData, encoding: .gb18030) ?? String(data: valueData, encoding: .isoLatin1)
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
            textLength: textLength,
            firstImageRecord: firstImageRecord > 0 ? firstImageRecord : nil,
            textEncodingRaw: textEncodingRaw,
            extraDataFlags: extraDataFlags,
            title: finalTitle,
            author: author,
            coverRecordIndex: coverRecordIndex
        )
    }

    /// 接收完整 PalmDatabase，能检测跨记录的 KF8 BOUNDARY 标识
    static func read(pdb: PalmDatabase) throws -> MOBIHeader {
        guard let record0 = pdb.records.first else {
            throw BookParseError.corruptedFile(detail: "无 record0")
        }
        let base = try read(record0: record0)

        // 优先看 record0 自身的 version == 8
        if pdb.records.first?.count ?? 0 >= 40,
           record0.readUInt32BE(at: 36) == 8 {
            return base
        }
        // 再看 records[1] 是否是 BOUNDARY
        if pdb.records.count > 1 {
            let rec1 = pdb.records[1]
            if rec1.count >= 20 {
                let id = String(data: rec1.subdata(in: 16..<20), encoding: .ascii) ?? ""
                if id == "BOUNDARY" {
                    let textLast = base.lastTextRecord > 1 ? base.lastTextRecord : max(1, pdb.records.count - 2)
                    return MOBIHeader(
                        variant: .kf8,
                        compression: base.compression,
                        firstTextRecord: 1,
                        lastTextRecord: textLast,
                        textLength: base.textLength,
                        firstImageRecord: base.firstImageRecord,
                        textEncodingRaw: base.textEncodingRaw,
                        extraDataFlags: base.extraDataFlags,
                        title: base.title,
                        author: base.author,
                        coverRecordIndex: base.coverRecordIndex
                    )
                }
            }
        }

        // 经典 MOBI: 用 PalmDB 实际记录数对 lastTextRecord 做兜底
        // 避免 PalmDOC recordCount 为 0 但实际有文本记录的边缘情况
        if base.variant == .classicMOBI,
           base.lastTextRecord > pdb.records.count - 1 {
            return MOBIHeader(
                variant: base.variant,
                compression: base.compression,
                firstTextRecord: base.firstTextRecord,
                lastTextRecord: max(1, pdb.records.count - 1),
                textLength: base.textLength,
                firstImageRecord: base.firstImageRecord,
                textEncodingRaw: base.textEncodingRaw,
                extraDataFlags: base.extraDataFlags,
                title: base.title,
                author: base.author,
                coverRecordIndex: base.coverRecordIndex
            )
        }
        return base
    }
}
