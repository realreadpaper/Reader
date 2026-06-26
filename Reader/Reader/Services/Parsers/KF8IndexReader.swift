import Foundation

struct KF8IndexReader {
    let data: Data

    /// 从 KF8 INDX/TAGX index 记录中读取章节起始偏移。
    /// KF8 skeleton/fragment records expose start/length pairs as tag 6 values.
    func chapterOffsets() -> [Int] {
        guard data.count >= 0x38,
              ascii(at: 0, length: 4) == "INDX" else { return [] }

        let headerLength = Int(data.readUInt32BE(at: 4))
        let idxtOffset = Int(data.readUInt32BE(at: 20))
        let entryCount = Int(data.readUInt32BE(at: 24))
        guard headerLength > 0,
              headerLength + 12 <= data.count,
              idxtOffset + 4 <= data.count,
              entryCount > 0,
              ascii(at: headerLength, length: 4) == "TAGX",
              ascii(at: idxtOffset, length: 4) == "IDXT" else {
            return []
        }

        let tagx = parseTAGX(at: headerLength)
        guard tagx.controlByteCount > 0,
              let chapterTag = tagx.tags.first(where: { $0.tag == 6 }) else {
            return []
        }

        var offsets: [Int] = []
        for entryIndex in 0..<entryCount {
            guard let range = entryRange(index: entryIndex, count: entryCount, idxtOffset: idxtOffset) else {
                continue
            }
            let values = parseTagValues(in: range, tagx: tagx)
            guard let tagValues = values[chapterTag.tag] else { continue }
            for index in stride(from: 0, to: tagValues.count, by: max(1, Int(chapterTag.valuesPerEntry))) {
                offsets.append(tagValues[index])
            }
        }

        return Array(Set(offsets)).sorted()
    }

    private struct Tagx {
        let controlByteCount: Int
        let tags: [Tag]
    }

    private struct Tag {
        let tag: UInt8
        let valuesPerEntry: UInt8
        let mask: UInt8
        let endFlag: UInt8
    }

    private func parseTAGX(at offset: Int) -> Tagx {
        let firstEntryOffset = Int(data.readUInt32BE(at: offset + 4))
        let controlByteCount = Int(data.readUInt32BE(at: offset + 8))
        let entriesStart = offset + 12
        let entriesEnd = min(data.count, offset + firstEntryOffset)
        guard firstEntryOffset >= 12,
              controlByteCount > 0,
              entriesStart <= entriesEnd else {
            return Tagx(controlByteCount: 0, tags: [])
        }

        var tags: [Tag] = []
        var cursor = entriesStart
        while cursor + 4 <= entriesEnd {
            tags.append(Tag(
                tag: data[cursor],
                valuesPerEntry: data[cursor + 1],
                mask: data[cursor + 2],
                endFlag: data[cursor + 3]
            ))
            cursor += 4
        }
        return Tagx(controlByteCount: controlByteCount, tags: tags)
    }

    private func entryRange(index: Int, count: Int, idxtOffset: Int) -> Range<Int>? {
        let positionOffset = idxtOffset + 4 + index * 2
        guard positionOffset + 2 <= data.count else { return nil }
        let start = Int(data.readUInt16BE(at: positionOffset))
        let end: Int
        if index + 1 < count {
            let nextOffset = positionOffset + 2
            guard nextOffset + 2 <= data.count else { return nil }
            end = Int(data.readUInt16BE(at: nextOffset))
        } else {
            end = idxtOffset
        }
        guard start >= 0, start <= end, end <= data.count else { return nil }
        return start..<end
    }

    private func parseTagValues(in range: Range<Int>, tagx: Tagx) -> [UInt8: [Int]] {
        guard range.lowerBound < range.upperBound else { return [:] }
        var cursor = range.lowerBound
        let textLength = Int(data[cursor])
        cursor += 1 + textLength
        guard cursor + tagx.controlByteCount <= range.upperBound else { return [:] }

        let controlStart = cursor
        cursor += tagx.controlByteCount

        var result: [UInt8: [Int]] = [:]
        for tag in tagx.tags {
            var valueCount = 0
            for byteIndex in 0..<tagx.controlByteCount {
                let control = data[controlStart + byteIndex]
                guard control & tag.mask != 0 else { continue }
                valueCount += valueCountFromControlByte(control & tag.mask) * max(1, Int(tag.valuesPerEntry))
            }
            guard valueCount > 0 else { continue }

            var values: [Int] = []
            for _ in 0..<valueCount {
                guard let decoded = readVariableWidthInteger(cursor: &cursor, limit: range.upperBound) else {
                    return result
                }
                values.append(decoded)
            }
            if !values.isEmpty {
                result[tag.tag, default: []].append(contentsOf: values)
            }
        }
        return result
    }

    private func valueCountFromControlByte(_ value: UInt8) -> Int {
        var current = value
        var count = 0
        while current > 0 {
            count += Int(current & 1)
            current >>= 1
        }
        return max(1, count)
    }

    private func readVariableWidthInteger(cursor: inout Int, limit: Int) -> Int? {
        var value = 0
        while cursor < limit {
            let byte = data[cursor]
            cursor += 1
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 != 0 {
                return value
            }
        }
        return nil
    }

    private func ascii(at offset: Int, length: Int) -> String? {
        guard offset + length <= data.count else { return nil }
        return String(data: data.subdata(in: offset..<(offset + length)), encoding: .ascii)
    }
}
