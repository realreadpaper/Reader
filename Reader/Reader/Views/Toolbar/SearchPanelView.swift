import SwiftUI

struct SearchPanelView: View {
    let chapters: [EPUBChapter]
    let onResultSelect: (Int, Int) -> Void
    @Environment(ThemeManager.self) private var themeManager

    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var currentResultIndex = 0

    struct SearchResult: Identifiable {
        let id = UUID()
        let chapterTitle: String
        let chapterIndex: Int
        let snippet: String
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(themeManager.currentTheme.secondaryText)

                TextField("搜索...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(themeManager.currentTheme.primaryText)
                    .onSubmit { performSearch() }

                if !searchResults.isEmpty {
                    Text("\(currentResultIndex + 1)/\(searchResults.count)")
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.secondaryText)
                }

                Button(action: previousResult) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(searchResults.isEmpty)

                Button(action: nextResult) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(searchResults.isEmpty)
            }
            .padding(10)
            .background(themeManager.currentTheme.border)
            .cornerRadius(8)

            if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults) { result in
                            Button(action: {
                                onResultSelect(result.chapterIndex, 0)
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.chapterTitle)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(themeManager.currentTheme.primaryText)

                                    Text(result.snippet)
                                        .font(.caption)
                                        .foregroundStyle(themeManager.currentTheme.secondaryText)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                            }
                            .buttonStyle(.plain)

                            Divider().background(themeManager.currentTheme.border)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(themeManager.currentTheme.sidebarBG)
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }

        searchResults = []
        for (index, chapter) in chapters.enumerated() {
            let plainText = chapter.htmlContent.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            if let range = plainText.range(of: searchText, options: .caseInsensitive) {
                let snippetStart = plainText.index(range.lowerBound, offsetBy: -20, limitedBy: plainText.startIndex) ?? plainText.startIndex
                let snippetEnd = plainText.index(range.upperBound, offsetBy: 20, limitedBy: plainText.endIndex) ?? plainText.endIndex

                let snippet = "..." + plainText[snippetStart..<snippetEnd] + "..."

                searchResults.append(SearchResult(
                    chapterTitle: chapter.title,
                    chapterIndex: index,
                    snippet: snippet
                ))
            }
        }

        currentResultIndex = 0
    }

    private func nextResult() {
        guard !searchResults.isEmpty else { return }
        currentResultIndex = (currentResultIndex + 1) % searchResults.count
        let result = searchResults[currentResultIndex]
        onResultSelect(result.chapterIndex, 0)
    }

    private func previousResult() {
        guard !searchResults.isEmpty else { return }
        currentResultIndex = (currentResultIndex - 1 + searchResults.count) % searchResults.count
        let result = searchResults[currentResultIndex]
        onResultSelect(result.chapterIndex, 0)
    }
}
