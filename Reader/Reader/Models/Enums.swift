import Foundation

enum FileType: String, Codable, CaseIterable {
    case epub
    case mobi
    case pdf
    case txt
    case md
    case azw3
    case azw

    static func fromFileExtension(_ ext: String) -> FileType? {
        switch ext.lowercased() {
        case "epub": return .epub
        case "mobi": return .mobi
        case "pdf": return .pdf
        case "txt": return .txt
        case "md", "markdown": return .md
        case "azw3": return .azw3
        case "azw": return .azw
        default: return nil
        }
    }
}

enum HighlightColor: String, Codable, CaseIterable {
    case yellow
    case green
    case orange
    case blue

    var hex: String {
        switch self {
        case .yellow: return "#F5D76E"
        case .green: return "#7EC8A0"
        case .orange: return "#E8A87C"
        case .blue: return "#A0B8E8"
        }
    }

    var overlayHex: String {
        switch self {
        case .yellow: return "#E8D5A0"
        case .green: return "#C8E8D5"
        case .orange: return "#E8D0B8"
        case .blue: return "#C8D5E8"
        }
    }
}
