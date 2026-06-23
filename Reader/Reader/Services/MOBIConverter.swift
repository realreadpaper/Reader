import Foundation

final class MOBIConverter {

    private let converterPath: String?

    init() {
        let paths = [
            "/opt/homebrew/bin/ebook-convert",
            "/usr/local/bin/ebook-convert",
            "/Applications/calibre.app/Contents/MacOS/ebook-convert"
        ]
        self.converterPath = paths.first { FileManager.default.fileExists(atPath: $0) }
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
        try await Task.detached(priority: .userInitiated) {
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
                throw BookParseError.calibreConversionFailed(stderr: msg)
            }
        }.value

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw BookParseError.calibreConversionFailed(stderr: "转换后文件不存在")
        }
        return outputURL
    }
}
