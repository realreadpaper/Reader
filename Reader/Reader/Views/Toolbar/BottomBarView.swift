import SwiftUI

struct BottomBarView: View {
    let book: Book
    let coordinator: RenderCoordinator

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 8) {
            if coordinator.totalChapters > 0 {
                if book.fileType == .pdf {
                    Text("第 \(coordinator.pdfCurrentPage) 页 / 共 \(coordinator.totalChapters) 页")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.currentTheme.secondaryText)
                } else {
                    Text("第 \(coordinator.currentChapter + 1) 章 / 共 \(coordinator.totalChapters) 章")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.currentTheme.secondaryText)
                }
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
