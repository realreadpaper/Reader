import SwiftUI

struct HighlightMenuView: View {
    let selectedText: String
    let onHighlight: (HighlightColor) -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button(action: { onHighlight(color) }) {
                    Circle()
                        .fill(Color(hex: color.hex))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .help(colorName(color))
            }

            Divider()
                .frame(height: 18)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("复制")

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.7))
            .help("取消")
        }
        .padding(10)
        .background(theme.currentTheme.sidebarBG)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.currentTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    private func colorName(_ color: HighlightColor) -> String {
        switch color {
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .orange: return "橙色"
        case .blue: return "蓝色"
        }
    }
}
