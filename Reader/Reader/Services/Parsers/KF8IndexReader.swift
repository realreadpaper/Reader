import Foundation

struct KF8IndexReader {
    let data: Data

    /// 从 KF8 index 记录中读取章节起始偏移
    func chapterOffsets() -> [Int] {
        guard data.count >= 8 else { return [] }
        guard let magic = String(data: data.subdata(in: 0..<4), encoding: .ascii),
              magic == "ORDR" else { return [] }
        let count = Int(data.readUInt32BE(at: 4))
        var offsets: [Int] = []
        for i in 0..<count {
            let pos = 8 + i * 4
            guard pos + 4 <= data.count else { break }
            offsets.append(Int(data.readUInt32BE(at: pos)))
        }
        return offsets
    }
}
