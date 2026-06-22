import SwiftUI

struct TOCView: View {
    let chapters: [(title: String, chapterIndex: Int)]
    let onChapterSelect: (Int) -> Void
    let isPDF: Bool
    @Environment(ThemeManager.self) private var theme

    init(chapters: [(title: String, chapterIndex: Int)], onChapterSelect: @escaping (Int) -> Void, isPDF: Bool = false) {
        self.chapters = chapters
        self.onChapterSelect = onChapterSelect
        self.isPDF = isPDF
    }

    var body: some View {
        List {
            ForEach(chapters, id: \.chapterIndex) { chapter in
                Button(action: { onChapterSelect(chapter.chapterIndex) }) {
                    HStack {
                        if isPDF {
                            Text("第 \(chapter.chapterIndex + 1) 页")
                                .font(.caption)
                                .foregroundStyle(theme.currentTheme.secondaryText)
                                .frame(width: 50, alignment: .leading)
                        }
                        Text(chapter.title)
                            .font(.subheadline)
                            .foregroundStyle(theme.currentTheme.primaryText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
}
