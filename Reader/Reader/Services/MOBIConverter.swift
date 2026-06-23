import Foundation

final class MOBIConverter {

    /// 转换最长允许 120 秒，超时则视为失败，避免 calibre 卡死导致 UI 一直 loading
    private static let conversionTimeout: TimeInterval = 120

    private let converterPath: String?

    init() {
        let paths = [
            "/opt/homebrew/bin/ebook-convert",
            "/usr/local/bin/ebook-convert",
            "/Applications/calibre.app/Contents/MacOS/ebook-convert"
        ]
        self.converterPath = paths.first { FileManager.default.fileExists(atPath: $0) }
        if let path = converterPath {
            BookLog.converter.info("init: ebook-convert found at \(path, privacy: .public)")
        } else {
            BookLog.converter.notice("init: ebook-convert NOT found in standard paths")
        }
    }

    var isAvailable: Bool { converterPath != nil }

    func convertToEPUB(mobiURL: URL) async throws -> URL {
        guard let converterPath else {
            throw BookParseError.calibreNotInstalled
        }

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderMOBI", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputURL = outputDir.appendingPathComponent("\(UUID().uuidString).epub")

        let converterPathCopy = converterPath
        let mobiPathCopy = mobiURL.path
        let outputPathCopy = outputURL.path
        BookLog.converter.info("convertToEPUB: invoking ebook-convert timeout=\(Self.conversionTimeout)s")

        let result: Result<Void, Error>
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: converterPathCopy)
                    process.arguments = [mobiPathCopy, outputPathCopy]
                    let errorPipe = Pipe()
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = errorPipe
                    try process.run()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let msg = String(data: data, encoding: .utf8) ?? "未知错误"
                        try? FileManager.default.removeItem(at: URL(fileURLWithPath: outputPathCopy))
                        BookLog.converter.error("convertToEPUB: exit status=\(process.terminationStatus) stderr=\(msg, privacy: .public)")
                        throw BookParseError.calibreConversionFailed(stderr: msg)
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(Self.conversionTimeout * 1_000_000_000))
                    BookLog.converter.error("convertToEPUB: timed out after \(Self.conversionTimeout)s")
                    throw BookParseError.calibreConversionFailed(stderr: "转换超时（>120s），已终止")
                }
                // 取第一个完成（成功或超时），另一个任务会被取消
                try await group.next()
                group.cancelAll()
            }
            result = .success(())
        } catch {
            result = .failure(error)
        }

        switch result {
        case .success:
            BookLog.converter.info("convertToEPUB: completed, output=\(outputURL.lastPathComponent, privacy: .public)")
        case .failure(let error):
            throw error
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            BookLog.converter.error("convertToEPUB: output file missing at \(outputURL.lastPathComponent, privacy: .public)")
            throw BookParseError.calibreConversionFailed(stderr: "转换后文件不存在")
        }
        return outputURL
    }
}
