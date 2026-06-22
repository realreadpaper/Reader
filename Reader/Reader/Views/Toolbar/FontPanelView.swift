import SwiftUI

struct FontPanelView: View {
    @Binding var fontSize: CGFloat
    @Binding var lineHeight: CGFloat
    @Binding var selectedTheme: AppTheme
    let themeManager: ThemeManager

    let themes: [AppTheme] = [.classic, .kraft, .night, .eyeCare]
    let lineSpacings: [CGFloat] = [1.5, 1.8, 2.0, 2.2]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("字体大小")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(themeManager.currentTheme.secondaryText)

                HStack {
                    Button(action: { fontSize = max(12, fontSize - 1) }) {
                        Text("A-").font(.caption)
                    }
                    .buttonStyle(.plain)

                    Slider(value: $fontSize, in: 12...24, step: 1)
                        .tint(themeManager.currentTheme.accent)

                    Button(action: { fontSize = min(24, fontSize + 1) }) {
                        Text("A+").font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("行距")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(themeManager.currentTheme.secondaryText)

                HStack(spacing: 6) {
                    ForEach(lineSpacings, id: \.self) { spacing in
                        Button(action: { lineHeight = spacing }) {
                            Text(String(format: "%.1f", spacing))
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    lineHeight == spacing
                                        ? themeManager.currentTheme.accent
                                        : themeManager.currentTheme.border
                                )
                                .foregroundStyle(
                                    lineHeight == spacing
                                        ? .white
                                        : themeManager.currentTheme.primaryText
                                )
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("主题")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(themeManager.currentTheme.secondaryText)

                HStack(spacing: 10) {
                    ForEach(themes, id: \.self) { t in
                        Button(action: {
                            selectedTheme = t
                            themeManager.setTheme(t)
                        }) {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(t.contentBG)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                selectedTheme == t
                                                    ? themeManager.currentTheme.accent
                                                    : .clear,
                                                lineWidth: 2
                                            )
                                    )
                                Text(t.name)
                                    .font(.caption2)
                                    .foregroundStyle(
                                        selectedTheme == t
                                            ? themeManager.currentTheme.primaryText
                                            : themeManager.currentTheme.secondaryText
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
