import SwiftUI

struct BottomBarView: View {
    let book: Book
    let coordinator: RenderCoordinator
    let themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 8) {
            if coordinator.totalChapters > 0 {
                Text("第 \(coordinator.currentChapter + 1)/\(coordinator.totalChapters) 章")
                    .font(.caption2)
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
                        .frame(width: geometry.size.width * coordinator.progress, height: 2)
                }
            }
            .frame(width: 80)

            Text("\(Int(coordinator.progress * 100))%")
                .font(.caption2)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 24)
        .background(themeManager.currentTheme.sidebarBG)
        .overlay(alignment: .top) {
            Divider().background(themeManager.currentTheme.border)
        }
    }
}
