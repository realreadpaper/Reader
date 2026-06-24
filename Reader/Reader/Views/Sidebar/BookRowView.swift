import SwiftUI

struct BookRowView: View {
    let book: Book
    let isSelected: Bool

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(coverGradient)
                    .frame(width: 36, height: 48)
                if let coverImage = loadCoverImage() {
                    Image(nsImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text(String(book.title.prefix(2)))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if book.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.currentTheme.accent)
                    }
                    Text(book.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(BookRowSelectionStyle.titleColor(theme: theme.currentTheme, isSelected: isSelected))
                        .lineLimit(1)
                }
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(BookRowSelectionStyle.secondaryColor(theme: theme.currentTheme, isSelected: isSelected))
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if book.progress > 0 {
                        ProgressView(value: book.progress)
                            .progressViewStyle(.linear)
                            .tint(theme.currentTheme.accent)
                            .frame(width: 40)
                        Text("\(Int(book.progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(BookRowSelectionStyle.secondaryColor(theme: theme.currentTheme, isSelected: isSelected))
                    } else {
                        Text("未开始")
                            .font(.caption2)
                            .foregroundStyle(BookRowSelectionStyle.secondaryColor(theme: theme.currentTheme, isSelected: isSelected))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(BookRowSelectionStyle.backgroundColor(theme: theme.currentTheme, isSelected: isSelected))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(BookRowSelectionStyle.borderColor(theme: theme.currentTheme, isSelected: isSelected), lineWidth: 0.5)
        )
    }

    private var coverGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "#8B7355"),
                Color(hex: "#5A4A3A")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func loadCoverImage() -> NSImage? {
        guard let path = book.coverPath,
              FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return NSImage(data: data)
    }
}

enum BookRowSelectionStyle {
    static func backgroundColor(theme: AppTheme, isSelected: Bool) -> Color {
        isSelected ? theme.border.opacity(0.72) : Color.clear
    }

    static func borderColor(theme: AppTheme, isSelected: Bool) -> Color {
        isSelected ? theme.accent.opacity(0.45) : Color.clear
    }

    static func titleColor(theme: AppTheme, isSelected: Bool) -> Color {
        theme.primaryText
    }

    static func secondaryColor(theme: AppTheme, isSelected: Bool) -> Color {
        theme.secondaryText
    }

    static func backgroundHex(theme: AppTheme, isSelected: Bool) -> String {
        isSelected ? theme.border.hex : "#00000000"
    }

    static func titleHex(theme: AppTheme, isSelected: Bool) -> String {
        titleColor(theme: theme, isSelected: isSelected).hex
    }
}
