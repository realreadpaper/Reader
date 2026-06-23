import SwiftUI

struct BookRowView: View {
    let book: Book

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
                        .foregroundStyle(theme.currentTheme.primaryText)
                        .lineLimit(1)
                }
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(theme.currentTheme.secondaryText)
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
                            .foregroundStyle(theme.currentTheme.secondaryText)
                    } else {
                        Text("未开始")
                            .font(.caption2)
                            .foregroundStyle(theme.currentTheme.secondaryText)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
