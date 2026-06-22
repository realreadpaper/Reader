import SwiftUI

enum AppTheme: String, CaseIterable {
    case classic
    case kraft
    case night
    case eyeCare

    var name: String {
        switch self {
        case .classic: return "经典"
        case .kraft: return "牛皮纸"
        case .night: return "夜间"
        case .eyeCare: return "护眼"
        }
    }

    var sidebarBG: Color {
        switch self {
        case .classic: return Color(hex: "#F0E8DE")
        case .kraft: return Color(hex: "#E8DCC8")
        case .night: return Color(hex: "#15120F")
        case .eyeCare: return Color(hex: "#C5D8C0")
        }
    }

    var contentBG: Color {
        switch self {
        case .classic: return Color(hex: "#FAF6EF")
        case .kraft: return Color(hex: "#F5EFE3")
        case .night: return Color(hex: "#1E1A15")
        case .eyeCare: return Color(hex: "#D5E8D0")
        }
    }

    var primaryText: Color {
        switch self {
        case .classic: return Color(hex: "#3A3025")
        case .kraft: return Color(hex: "#2E2518")
        case .night: return Color(hex: "#D5C8B0")
        case .eyeCare: return Color(hex: "#2A3528")
        }
    }

    var secondaryText: Color {
        switch self {
        case .classic: return Color(hex: "#6B5A40")
        case .kraft: return Color(hex: "#5A4A3A")
        case .night: return Color(hex: "#A09080")
        case .eyeCare: return Color(hex: "#4A5A42")
        }
    }

    var accent: Color {
        switch self {
        case .classic: return Color(hex: "#8B7355")
        case .kraft: return Color(hex: "#8B7355")
        case .night: return Color(hex: "#C8A870")
        case .eyeCare: return Color(hex: "#6B8B5A")
        }
    }

    var border: Color {
        switch self {
        case .classic: return Color(hex: "#E0D5C8")
        case .kraft: return Color(hex: "#D5C8B0")
        case .night: return Color(hex: "#2A2520")
        case .eyeCare: return Color(hex: "#A8C0A0")
        }
    }

    var highlightBG: Color {
        switch self {
        case .classic: return Color(hex: "#F5D76E")
        case .kraft: return Color(hex: "#E8D5A0")
        case .night: return Color(hex: "#5A4A28")
        case .eyeCare: return Color(hex: "#C8E0A0")
        }
    }
}

@Observable
final class ThemeManager {
    var currentTheme: AppTheme = .kraft

    init() {
        if let saved = UserDefaults.standard.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: saved) {
            currentTheme = theme
        }
    }

    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    var hex: String {
        guard let components = NSColor(self).cgColor.components else { return "#000000" }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components.count > 2 ? components[2] * 255 : 0)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
