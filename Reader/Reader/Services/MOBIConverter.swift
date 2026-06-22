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

    var isAvailable: Bool {
        converterPath != nil
    }

    func convertToEPUB(mobiURL: URL) throws -> URL {
        guard let converterPath else {
            throw MOBIError.converterNotFound
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(mobiURL.deletingPathExtension().lastPathComponent).epub")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: converterPath)
        process.arguments = [mobiURL.path, outputURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
            throw MOBIError.conversionFailed(errorMessage)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw MOBIError.conversionFailed("转换后文件不存在")
        }

        return outputURL
    }
}

enum MOBIError: Error, LocalizedError {
    case converterNotFound
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .converterNotFound:
            return "未找到 ebook-convert 工具，请安装 calibre"
        case .conversionFailed(let msg):
            return "MOBI 转换失败: \(msg)"
        }
    }
}
