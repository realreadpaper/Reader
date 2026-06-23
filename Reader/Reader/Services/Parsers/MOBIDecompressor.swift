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

    /// PalmDOC LZ77 解压：1 字节 flag，逐位（MSB 优先）判定 literal / back-reference
    private static func decompressPalmDoc(_ data: Data) -> Data {
        var output = Data()
        var i = 0
        while i < data.count {
            let flags = data[i]
            i += 1
            for bit in 0..<8 where i < data.count {
                if (flags & (0x80 >> bit)) != 0 {
                    guard i + 1 < data.count else { return output }
                    let pair = (UInt16(data[i]) << 8) | UInt16(data[i + 1])
                    i += 2
                    let distance = Int(pair >> 3)
                    let length = Int(pair & 0x7) + 3
                    let start = output.count - distance - 1
                    for k in 0..<length {
                        let src = start + k
                        if src >= 0 && src < output.count {
                            output.append(output[src])
                        } else {
                            output.append(0)
                        }
                    }
                } else {
                    output.append(data[i])
                    i += 1
                }
            }
        }
        return output
    }
}
