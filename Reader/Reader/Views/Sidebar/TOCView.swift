import SwiftUI

struct TOCView: View {
    let chapters: [(title: String, chapterIndex: Int)]
    let onChapterSelect: (Int) -> Void
    let showPageNumbers: Bool
    let currentIndex: Int

    @Environment(ThemeManager.self) private var theme

    init(
        chapters: [(title: String, chapterIndex: Int)],
        onChapterSelect: @escaping (Int) -> Void,
        showPageNumbers: Bool = false,
        currentIndex: Int = -1
    ) {
        self.chapters = chapters
        self.onChapterSelect = onChapterSelect
        self.showPageNumbers = showPageNumbers
        self.currentIndex = currentIndex
    }

    var body: some View {
        List {
            ForEach(chapters, id: \.chapterIndex) { chapter in
                let isSelected = chapter.chapterIndex == currentIndex
                Button(action: { onChapterSelect(chapter.chapterIndex) }) {
                    HStack {
                        if showPageNumbers {
                            Text("\(chapter.chapterIndex + 1)")
                                .font(.caption)
                                .foregroundStyle(theme.currentTheme.secondaryText)
                                .frame(width: 32, alignment: .trailing)
                        }
                        Text(chapter.title)
                            .font(.subheadline)
                            .foregroundStyle(theme.currentTheme.primaryText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(
                        isSelected
                            ? theme.currentTheme.accent.opacity(0.18)
                            : Color.clear
                    )
                    .overlay(alignment: .leading) {
                        if isSelected {
                            Rectangle()
                                .fill(theme.currentTheme.accent)
                                .frame(width: 3)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
}
