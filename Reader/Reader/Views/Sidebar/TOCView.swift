import SwiftUI

enum TOCStyle {
    static func background(for theme: AppTheme) -> Color {
        theme.sidebarBG
    }

    static func rowBackground(for theme: AppTheme, isSelected: Bool) -> Color {
        isSelected ? theme.highlightBG.opacity(0.35) : Color.clear
    }

    static func primaryText(for theme: AppTheme) -> Color {
        theme.primaryText
    }

    static func secondaryText(for theme: AppTheme) -> Color {
        theme.secondaryText
    }

    static func backgroundHex(for theme: AppTheme) -> String {
        theme.sidebarBG.hex
    }

    static func primaryTextHex(for theme: AppTheme) -> String {
        theme.primaryText.hex
    }

    static func secondaryTextHex(for theme: AppTheme) -> String {
        theme.secondaryText.hex
    }
}

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
                                .foregroundStyle(TOCStyle.secondaryText(for: theme.currentTheme))
                                .frame(width: 32, alignment: .trailing)
                        }
                        Text(chapter.title)
                            .font(.subheadline)
                            .foregroundStyle(TOCStyle.primaryText(for: theme.currentTheme))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(TOCStyle.rowBackground(for: theme.currentTheme, isSelected: isSelected))
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
                .listRowBackground(TOCStyle.background(for: theme.currentTheme))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(TOCStyle.background(for: theme.currentTheme))
    }
}
