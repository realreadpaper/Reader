import SwiftUI

enum ReaderPositionLabel {
    static func text(fileType: FileType, currentIndex: Int, total: Int, pdfCurrentPage: Int) -> String {
        let page = fileType == .pdf ? pdfCurrentPage : currentIndex + 1
        return "第 \(page) 页 / 共 \(total) 页"
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
                    fileType: book.fileType,
                    currentIndex: coordinator.currentChapter,
                    total: coordinator.totalChapters,
                    pdfCurrentPage: coordinator.pdfCurrentPage
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
