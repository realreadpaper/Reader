import SwiftUI

struct AnnotationView: View {
    let highlights: [Highlight]
    let onHighlightSelect: (Highlight) -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        List {
            ForEach(highlights, id: \.id) { highlight in
                Button(action: { onHighlightSelect(highlight) }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle()
                                .fill(Color(hex: highlight.color.overlayHex))
                                .frame(width: 8, height: 8)
                            if let chapter = highlight.chapter {
                                Text(chapter)
                                    .font(.caption)
                                    .foregroundStyle(theme.currentTheme.secondaryText)
                            }
                        }
                        Text(highlight.selectedText)
                            .font(.subheadline)
                            .lineLimit(2)
                            .foregroundStyle(theme.currentTheme.primaryText)
                        if let note = highlight.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(theme.currentTheme.secondaryText)
                                .italic()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
}
