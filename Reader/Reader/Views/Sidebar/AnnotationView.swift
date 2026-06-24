import SwiftUI

struct AnnotationView: View {
    let highlights: [Highlight]
    let onHighlightSelect: (Highlight) -> Void
    let onDelete: (Highlight) -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        List {
            ForEach(highlights, id: \.id) { highlight in
                HStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle()
                                    .fill(Color(hex: highlight.color.overlayHex))
                                    .frame(width: 8, height: 8)
                                if let chapter = highlight.chapter {
                                    Text(chapter)
                                        .font(.caption)
                                        .foregroundStyle(theme.currentTheme.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(highlight.createdAt.formatted(.dateTime.month().day().hour().minute()))
                                    .font(.caption2)
                                    .foregroundStyle(theme.currentTheme.secondaryText)
                            }
                            Text(highlight.selectedText)
                                .font(.subheadline)
                                .lineLimit(2)
                                .foregroundStyle(theme.currentTheme.primaryText)
                            if let note = highlight.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(theme.currentTheme.secondaryText)
                                    .italic()
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onHighlightSelect(highlight) }

                    Spacer()
                    Button(action: { onDelete(highlight) }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(theme.currentTheme.sidebarBG)
    }
}
