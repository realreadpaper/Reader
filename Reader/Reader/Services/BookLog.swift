import Foundation
import os

/// 统一日志入口，使用 os.Logger 输出到 Xcode 控制台和 Console.app
/// 查看方式：Xcode 控制台自动展示；或 Console.app 过滤 Subsystem = "com.reader.Reader"
enum BookLog {
    private static let subsystem = "com.reader.Reader"

    static let parsing = Logger(subsystem: subsystem, category: "parsing")
    static let mobi = Logger(subsystem: subsystem, category: "mobi")
    static let palm = Logger(subsystem: subsystem, category: "palm")
    static let epub = Logger(subsystem: subsystem, category: "epub")
    static let converter = Logger(subsystem: subsystem, category: "converter")
    static let render = Logger(subsystem: subsystem, category: "render")
}
