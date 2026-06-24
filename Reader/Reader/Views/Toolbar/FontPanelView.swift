import SwiftUI

struct FontPanelView: View {
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var selectedTheme: AppTheme
    @Binding var pdfFilterEnabled: Bool
    let fileType: FileType
    let onClose: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    let lineSpacings: [Double] = [1.5, 1.8, 2.0, 2.2, 2.5]

    private var isPDF: Bool { fileType == .pdf }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("字体与排版")
                    .font(.headline)
                    .foregroundStyle(themeManager.currentTheme.primaryText)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(isPDF ? "缩放比例  \(String(format: "%.0f", fontSize / 16.0 * 100))%" : "字体大小  \(Int(fontSize))px")
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.secondaryText)

                HStack {
                    Button(action: { fontSize = max(12, fontSize - 1) }) {
                        Text("A-").font(.caption)
                    }
                    .buttonStyle(.plain)

                    Slider(value: $fontSize, in: 12...24, step: 1)
                        .tint(themeManager.currentTheme.accent)

                    Button(action: { fontSize = min(28, fontSize + 1) }) {
                        Text("A+").font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !isPDF {
                VStack(alignment: .leading, spacing: 8) {
                    Text("行距")
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.secondaryText)

                    HStack(spacing: 6) {
                        ForEach(lineSpacings, id: \.self) { spacing in
                            Button(action: { lineHeight = spacing }) {
                                Text(String(format: "%.1f", spacing))
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        abs(lineHeight - spacing) < 0.01
                                            ? themeManager.currentTheme.accent
                                            : themeManager.currentTheme.border
                                    )
                                    .foregroundStyle(
                                        abs(lineHeight - spacing) < 0.01
                                            ? .white
                                            : themeManager.currentTheme.primaryText
                                    )
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("主题")
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.secondaryText)

                HStack(spacing: 10) {
                    ForEach(AppTheme.allCases, id: \.self) { t in
                        Button(action: {
                            themeManager.setTheme(t)
                        }) {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(t.contentBG)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                themeManager.currentTheme == t
                                                    ? themeManager.currentTheme.accent
                                                    : .clear,
                                                lineWidth: 2
                                            )
                                    )
                                Text(t.name)
                                    .font(.caption2)
                                    .foregroundStyle(
                                        themeManager.currentTheme == t
                                            ? themeManager.currentTheme.primaryText
                                            : themeManager.currentTheme.secondaryText
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isPDF {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PDF 色调")
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.secondaryText)

                    Toggle("夜间/护眼模式对 PDF 生效", isOn: $pdfFilterEnabled)
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.primaryText)
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 280)
        .background(themeManager.currentTheme.sidebarBG)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 12)
    }
}
