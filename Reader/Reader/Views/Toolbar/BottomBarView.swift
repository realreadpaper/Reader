import SwiftUI

enum ReaderPositionLabel {
    static func text(currentPage: Int, total: Int) -> String {
        return "第 \(max(1, currentPage)) 页 / 共 \(max(0, total)) 页"
    }
}

enum EPUBProgressPolicy {
    static func overallProgress(currentPage: Int, totalPages: Int) -> Double {
        guard totalPages > 0 else { return 0 }
        let page = max(0, min(currentPage, totalPages - 1))
        return max(0, min(1, Double(page + 1) / Double(totalPages)))
    }

    static func restoredPage(savedProgress: Double, totalPages: Int) -> Int {
        guard totalPages > 0 else { return 0 }
        let progress = max(0, min(1, savedProgress))
        return max(0, min(Int(progress * Double(totalPages)) - 1, totalPages - 1))
    }
}

enum ReaderNavigationTarget: Equatable {
    case pdfPage(Int)
    case pagedContent(chapterIndex: Int, progress: Double?)
}

enum ReaderNavigationPosition {
    static func bookmarkPosition(
        fileType: FileType,
        currentChapter: Int,
        pdfCurrentPage: Int,
        progress: Double
    ) -> String {
        switch fileType {
        case .pdf:
            return "pdfPage:\(max(0, pdfCurrentPage - 1))"
        case .epub, .mobi, .txt, .md:
            return "\(fileType.rawValue):\(max(0, currentChapter)):\(max(0, min(1, progress)))"
        }
    }

    static func highlightStartOffset(
        fileType: FileType,
        currentChapter: Int,
        pdfCurrentPage: Int
    ) -> Int {
        switch fileType {
        case .pdf:
            return max(0, pdfCurrentPage - 1) * 1_000_000
        case .epub, .mobi, .txt, .md:
            return max(0, currentChapter) * 1_000_000
        }
    }

    static func parse(_ position: String) -> ReaderNavigationTarget? {
        let parts = position.split(separator: ":").map(String.init)
        guard parts.count >= 2, let index = Int(parts[1]) else { return nil }

        switch parts[0] {
        case "pdfPage":
            return .pdfPage(max(0, index))
        case "pdf":
            return .pdfPage(max(0, index - 1))
        case "epub", "mobi", "txt", "md":
            let progress = parts.count >= 3 ? Double(parts[2]) : nil
            return .pagedContent(chapterIndex: max(0, index), progress: progress)
        default:
            return nil
        }
    }
}

struct BottomBarView: View {
    let book: Book
    let coordinator: RenderCoordinator

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 8) {
            if coordinator.totalChapters > 0 {
                Text(ReaderPositionLabel.text(
                    currentPage: coordinator.displayCurrentPage,
                    total: coordinator.totalChapters
                ))
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
            }

            Spacer()

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(themeManager.currentTheme.border)
                        .frame(height: 2)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(themeManager.currentTheme.accent)
                        .frame(width: max(0, min(geometry.size.width, geometry.size.width * coordinator.progress)), height: 2)
                }
            }
            .frame(width: 120)

            Text("\(Int(coordinator.progress * 100))%")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 32)
        .background(themeManager.currentTheme.sidebarBG)
        .overlay(alignment: .top) {
            Divider().background(themeManager.currentTheme.border)
        }
    }
}
