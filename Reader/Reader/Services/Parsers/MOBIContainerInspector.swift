import Foundation

struct MOBIContainerInfo: Equatable {
    let name: String
    let type: String
    let creator: String
    let recordCount: Int
    let recordSizes: [Int]
    let compressionRaw: UInt16
    let compression: MOBICompression
    let mobiIdentifier: String
    let mobiHeaderLength: Int
    let mobiType: UInt32
    let mobiVersion: UInt32
    let variant: MOBIVariant
    let textEncodingRaw: UInt32
    let textLength: Int
    let textRecordCount: Int
    let textRecordRange: ClosedRange<Int>?
    let extraDataFlags: UInt32
    let firstImageRecord: Int?
    let drmStatus: MOBIDRMStatus
    let exthRecords: [MOBIEXTHEntry]
    let exthTitle: String?
    let exthAuthor: String?
    let coverRecordIndex: Int?
    let hasKF8Boundary: Bool
    let kf8BoundaryRecordIndex: Int?
    let markers: [MOBIRecordMarker]

    var diagnosticSummary: String {
        let textRange = textRecordRange.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "nil"
        let markerText = markers.map { "\($0.kind)@\($0.recordIndex)" }.joined(separator: ",")
        return [
            "records=\(recordCount)",
            "variant=\(variant)",
            "compression=\(compressionRaw)",
            "version=\(mobiVersion)",
            "encoding=\(textEncodingRaw)",
            "textRange=\(textRange)",
            "extraFlags=0x\(String(extraDataFlags, radix: 16))",
            "drm=\(drmStatus)",
            "firstImage=\(firstImageRecord.map(String.init) ?? "nil")",
            "kf8Boundary=\(kf8BoundaryRecordIndex.map(String.init) ?? "nil")",
            "markers=\(markerText.isEmpty ? "none" : markerText)"
        ].joined(separator: " ")
    }
}

struct MOBIEXTHEntry: Equatable {
    let type: UInt32
    let data: Data

    var utf8String: String? {
        String(data: data, encoding: .utf8)
    }

    var uint32Value: UInt32? {
        guard data.count >= 4 else { return nil }
        return data.readUInt32BE(at: 0)
    }
}

struct MOBIRecordMarker: Equatable {
    let kind: String
    let recordIndex: Int
}

enum MOBIDRMStatus: Equatable, CustomStringConvertible {
    case none
    case encrypted(type: UInt16)

    var description: String {
        switch self {
        case .none:
            return "none"
        case .encrypted(let type):
            return "encrypted(\(type))"
        }
    }
}

enum MOBIContainerInspector {
    static func inspect(pdb: PalmDatabase) throws -> MOBIContainerInfo {
        guard let record0 = pdb.records.first else {
            throw BookParseError.corruptedFile(detail: "无 record0")
        }
        guard record0.count >= 40 else {
            throw BookParseError.corruptedFile(detail: "record0 过短：\(record0.count) bytes")
        }

        let compressionRaw = record0.readUInt16BE(at: 0)
        let compression = compressionKind(raw: compressionRaw)
        let textLength = Int(record0.readUInt32BE(at: 4))
        let textRecordCount = Int(record0.readUInt16BE(at: 8))
        let encryptionType = record0.readUInt16BE(at: 12)
        let drmStatus: MOBIDRMStatus = encryptionType == 0 ? .none : .encrypted(type: encryptionType)
        let mobiIdentifier = String(data: record0.readBytes(at: 16, length: 4), encoding: .ascii) ?? ""
        let mobiHeaderLength = Int(record0.readUInt32BE(at: 20))
        let mobiType = record0.readUInt32BE(at: 24)
        let textEncodingRaw = record0.readUInt32BE(at: 28)
        let mobiVersion = record0.readUInt32BE(at: 36)
        let extraDataFlags = record0.count >= 244 ? record0.readUInt32BE(at: 240) : 0
        let firstImageRaw = record0.count >= 128 ? Int(record0.readUInt32BE(at: 124)) : 0
        let firstImageRecord = firstImageRaw > 0 ? firstImageRaw : nil
        let exthRecords = readEXTHEntries(record0: record0, mobiHeaderLength: mobiHeaderLength)
        let coverOffset = exthRecords.first(where: { $0.type == 201 })?.uint32Value.map(Int.init)
        let coverRecordIndex: Int? = {
            guard let firstImageRecord, let coverOffset else { return nil }
            return firstImageRecord + coverOffset
        }()
        let kf8BoundaryRecordIndex = findKF8Boundary(in: pdb.records)
        let variant: MOBIVariant = {
            if compression == .huff {
                return .unsupported("HUFF/CDIC 压缩暂未原生实现")
            }
            if mobiVersion == 8 || kf8BoundaryRecordIndex != nil {
                return .kf8
            }
            if [0, 1, 2].contains(compressionRaw) {
                return .classicMOBI
            }
            return .unsupported("未知 MOBI 变体（compression=\(compressionRaw), version=\(mobiVersion)）")
        }()
        let textRecordRange: ClosedRange<Int>? = {
            guard textRecordCount > 0 else { return nil }
            return 1...min(textRecordCount, max(1, pdb.records.count - 1))
        }()

        return MOBIContainerInfo(
            name: pdb.name,
            type: pdb.type,
            creator: pdb.creator,
            recordCount: pdb.records.count,
            recordSizes: pdb.records.map(\.count),
            compressionRaw: compressionRaw,
            compression: compression,
            mobiIdentifier: mobiIdentifier,
            mobiHeaderLength: mobiHeaderLength,
            mobiType: mobiType,
            mobiVersion: mobiVersion,
            variant: variant,
            textEncodingRaw: textEncodingRaw,
            textLength: textLength,
            textRecordCount: textRecordCount,
            textRecordRange: textRecordRange,
            extraDataFlags: extraDataFlags,
            firstImageRecord: firstImageRecord,
            drmStatus: drmStatus,
            exthRecords: exthRecords,
            exthTitle: exthRecords.first(where: { $0.type == 503 })?.utf8String,
            exthAuthor: exthRecords.first(where: { $0.type == 100 })?.utf8String,
            coverRecordIndex: coverRecordIndex,
            hasKF8Boundary: kf8BoundaryRecordIndex != nil,
            kf8BoundaryRecordIndex: kf8BoundaryRecordIndex,
            markers: findMarkers(in: pdb.records)
        )
    }

    private static func compressionKind(raw: UInt16) -> MOBICompression {
        switch raw {
        case 1:
            return .none
        case 2:
            return .palmDoc
        case 17480:
            return .huff
        default:
            return .none
        }
    }

    private static func readEXTHEntries(record0: Data, mobiHeaderLength: Int) -> [MOBIEXTHEntry] {
        let exthStart = 16 + mobiHeaderLength
        guard exthStart + 12 <= record0.count else { return [] }
        guard String(data: record0.readBytes(at: exthStart, length: 4), encoding: .ascii) == "EXTH" else {
            return []
        }

        let exthLength = Int(record0.readUInt32BE(at: exthStart + 4))
        let exthCount = Int(record0.readUInt32BE(at: exthStart + 8))
        let exthEnd = min(record0.count, exthStart + exthLength)
        var entries: [MOBIEXTHEntry] = []
        var offset = exthStart + 12
        for _ in 0..<exthCount {
            guard offset + 8 <= exthEnd else { break }
            let type = record0.readUInt32BE(at: offset)
            let length = Int(record0.readUInt32BE(at: offset + 4))
            guard length >= 8, offset + length <= exthEnd else { break }
            entries.append(MOBIEXTHEntry(
                type: type,
                data: record0.subdata(in: (offset + 8)..<(offset + length))
            ))
            offset += length
        }
        return entries
    }

    private static func findKF8Boundary(in records: [Data]) -> Int? {
        for (index, record) in records.enumerated() where record.count >= 20 {
            if String(data: record.readBytes(at: 16, length: 4), encoding: .ascii) == "BOUN" ||
                String(data: record.readBytes(at: 16, length: 8), encoding: .ascii) == "BOUNDARY" {
                return index
            }
        }
        return nil
    }

    private static func findMarkers(in records: [Data]) -> [MOBIRecordMarker] {
        let known = Set(["FDST", "INDX", "FLIS", "FCIS", "RESC", "SRCS", "DATP"])
        var markers: [MOBIRecordMarker] = []
        for (index, record) in records.enumerated() where record.count >= 4 {
            guard let kind = String(data: record.prefix(4), encoding: .ascii), known.contains(kind) else {
                continue
            }
            markers.append(MOBIRecordMarker(kind: kind, recordIndex: index))
        }
        return markers
    }
}
