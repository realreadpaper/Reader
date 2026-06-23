import Foundation

@Observable
final class ReaderSettings {
    enum PageMode: String, CaseIterable {
        case scroll
        case paged

        var name: String {
            switch self {
            case .scroll: return "滚动"
            case .paged: return "翻页"
            }
        }
    }

    var fontSize: Double {
        didSet {
            if oldValue != fontSize {
                UserDefaults.standard.set(fontSize, forKey: "readerFontSize")
            }
        }
    }

    var lineHeight: Double {
        didSet {
            if oldValue != lineHeight {
                UserDefaults.standard.set(lineHeight, forKey: "readerLineHeight")
            }
        }
    }

    var pageMode: PageMode {
        didSet {
            if oldValue != pageMode {
                UserDefaults.standard.set(pageMode.rawValue, forKey: "readerPageMode")
            }
        }
    }

    var pdfFilterEnabled: Bool {
        didSet {
            if oldValue != pdfFilterEnabled {
                UserDefaults.standard.set(pdfFilterEnabled, forKey: "readerPdfFilterEnabled")
            }
        }
    }

    init() {
        let storedFont = UserDefaults.standard.object(forKey: "readerFontSize") as? Double
        let storedLine = UserDefaults.standard.object(forKey: "readerLineHeight") as? Double
        let storedMode = UserDefaults.standard.string(forKey: "readerPageMode")
        let storedPdfFilter = UserDefaults.standard.object(forKey: "readerPdfFilterEnabled") as? Bool

        self.fontSize = storedFont ?? 16
        self.lineHeight = storedLine ?? 2.1
        self.pageMode = PageMode(rawValue: storedMode ?? "") ?? .scroll
        self.pdfFilterEnabled = storedPdfFilter ?? true
    }
}
