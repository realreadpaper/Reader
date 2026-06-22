import SwiftUI

struct TOCView: View {
    let chapters: [(title: String, chapterIndex: Int)]
    let onChapterSelect: (Int) -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        List {
            ForEach(chapters, id: \.chapterIndex) { chapter in
                Button(action: { onChapterSelect(chapter.chapterIndex) }) {
                    Text(chapter.title)
                        .font(.subheadline)
                        .foregroundStyle(theme.currentTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
}
