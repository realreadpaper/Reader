import SwiftUI

struct BottomBarView: View {
    let book: Book
    let coordinator: RenderCoordinator
    let themeManager: ThemeManager

    var body: some View {
        HStack {
            Text("第 \(coordinator.currentChapter + 1)/\(coordinator.tocEntries.count) 章")
                .font(.caption)
                .foregroundStyle(themeManager.currentTheme.secondaryText)

            Spacer()

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(themeManager.currentTheme.border)
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(themeManager.currentTheme.accent)
                        .frame(width: geometry.size.width * coordinator.progress, height: 3)
                }
            }
            .frame(width: 120)

            Spacer()

            Text("\(Int(coordinator.progress * 100))%")
                .font(.caption)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(themeManager.currentTheme.sidebarBG)
        .overlay(alignment: .top) {
            Divider().background(themeManager.currentTheme.border)
        }
    }
}
