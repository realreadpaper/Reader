import Foundation

enum FileType: String, Codable, CaseIterable {
    case epub
    case mobi
    case pdf
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
