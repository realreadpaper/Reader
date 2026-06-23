import Foundation

enum MOBIDecompressor {
    static func decompress(_ data: Data, compression: MOBICompression) throws -> Data {
        switch compression {
        case .none:
            return data
        case .palmDoc:
            return decompressPalmDoc(data)
        case .huff:
            throw BookParseError.unsupportedFormat(detail: "HUFF/CDIC 压缩暂未实现")
        }
    }

    /// PalmDOC 解压字节码：
    /// 0x01...0x08 复制后续 N 个字面量，0x09...0x7f 为字面量，
    /// 0x80...0xbf 为 back-reference，0xc0...0xff 表示空格 + 低 7 位字符。
    private static func decompressPalmDoc(_ data: Data) -> Data {
        var output = Data()
        var i = 0
        while i < data.count {
            let byte = data[i]
            i += 1

            switch byte {
            case 0:
                output.append(0)
            case 1...8:
                let literalCount = min(Int(byte), data.count - i)
                output.append(data.subdata(in: i..<(i + literalCount)))
                i += literalCount
            case 9...0x7F:
                output.append(byte)
            case 0x80...0xBF:
                guard i < data.count else { return output }
                let pair = (UInt16(byte) << 8) | UInt16(data[i])
                i += 1
                let distance = Int((pair >> 3) & 0x07FF)
                let length = Int(pair & 0x0007) + 3
                guard distance > 0, distance <= output.count else { continue }
                let start = output.count - distance
                for k in 0..<length {
                    let src = start + k
                    guard src >= 0, src < output.count else { break }
                    output.append(output[src])
                }
            default:
                output.append(0x20)
                output.append(byte ^ 0x80)
            }
        }
        return output
    }
}
