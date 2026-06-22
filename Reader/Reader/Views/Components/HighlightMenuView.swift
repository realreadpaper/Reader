import SwiftUI

struct HighlightMenuView: View {
    let selectedText: String
    let onHighlight: (HighlightColor) -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button(action: { onHighlight(color) }) {
                    Circle()
                        .fill(Color(hex: color.hex))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 20)

            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("复制")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(8)
        .background(.white)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}
