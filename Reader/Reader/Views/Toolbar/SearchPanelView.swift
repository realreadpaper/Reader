import SwiftUI

struct SearchPanelView: View {
    let coordinator: RenderCoordinator
    let onResultSelect: (SearchResultTarget) -> Void
    let onClose: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @State private var searchText = ""
    @State private var epubResults: [EPUBSearchResult] = []
    @State private var currentResultIndex = 0

    struct EPUBSearchResult: Identifiable {
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
                    .submitLabel(.search)

                if !epubResults.isEmpty || !coordinator.pdfSearchResults.isEmpty {
                    Text(totalResultsText)
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.secondaryText)
                }

                Button(action: previousResult) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(totalResultsCount == 0)

                Button(action: nextResult) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(totalResultsCount == 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(themeManager.currentTheme.border)
            .cornerRadius(8)

            resultList
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: 240)
        .background(themeManager.currentTheme.sidebarBG)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 12)
    }

    @MainActor
    @ViewBuilder
    private var resultList: some View {
        let total = totalResultsCount
        if total == 0 {
            if searchText.isEmpty {
                EmptyView()
            } else {
                Text("无匹配结果")
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.secondaryText)
                    .padding(.top, 8)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if coordinator.book.fileType == .pdf {
                        ForEach(coordinator.pdfSearchResults, id: \.pageIndex) { result in
                            Button(action: {
                                onResultSelect(.pdfPage(result.pageIndex))
                            }) {
                                searchRow(title: result.title, snippet: result.snippet)
                            }
                            .buttonStyle(.plain)
                            Divider().background(themeManager.currentTheme.border)
                        }
                    } else {
                        ForEach(epubResults) { result in
                            Button(action: {
                                onResultSelect(.epubChapter(result.chapterIndex))
                            }) {
                                searchRow(title: result.chapterTitle, snippet: result.snippet)
                            }
                            .buttonStyle(.plain)
                            Divider().background(themeManager.currentTheme.border)
                        }
                    }
                }
            }
        }
    }

    private func searchRow(title: String, snippet: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(themeManager.currentTheme.primaryText)
            Text(snippet)
                .font(.caption)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }

    @MainActor
    private var totalResultsCount: Int {
        coordinator.book.fileType == .pdf
            ? coordinator.pdfSearchResults.count
            : epubResults.count
    }

    @MainActor
    private var totalResultsText: String {
        let total = totalResultsCount
        return total == 0 ? "" : "\(currentResultIndex + 1)/\(total)"
    }

    @MainActor
    private func performSearch() {
        guard !searchText.isEmpty else {
            epubResults = []
            return
        }

        if coordinator.book.fileType == .pdf {
            coordinator.searchPDF(searchText)
            return
        }

        var results: [EPUBSearchResult] = []
        for (index, chapter) in coordinator.chapters.enumerated() {
            let plainText = chapter.htmlContent.replacingOccurrences(
                of: "<[^>]+>",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: "&nbsp;", with: " ")
            if let range = plainText.range(of: searchText, options: .caseInsensitive) {
                let start = plainText.index(range.lowerBound, offsetBy: -30, limitedBy: plainText.startIndex) ?? plainText.startIndex
                let end = plainText.index(range.upperBound, offsetBy: 30, limitedBy: plainText.endIndex) ?? plainText.endIndex
                let snippet = "..." + plainText[start..<end] + "..."
                results.append(EPUBSearchResult(
                    chapterTitle: chapter.title,
                    chapterIndex: index,
                    snippet: snippet
                ))
                if results.count >= 200 { break }
            }
        }
        epubResults = results
        currentResultIndex = 0
    }

    @MainActor
    private func nextResult() {
        let total = totalResultsCount
        guard total > 0 else { return }
        currentResultIndex = (currentResultIndex + 1) % total
        navigateToCurrent()
    }

    @MainActor
    private func previousResult() {
        let total = totalResultsCount
        guard total > 0 else { return }
        currentResultIndex = (currentResultIndex - 1 + total) % total
        navigateToCurrent()
    }

    @MainActor
    private func navigateToCurrent() {
        if coordinator.book.fileType == .pdf {
            let r = coordinator.pdfSearchResults
            if currentResultIndex >= 0 && currentResultIndex < r.count {
                onResultSelect(.pdfPage(r[currentResultIndex].pageIndex))
            }
        } else {
            let r = epubResults
            if currentResultIndex >= 0 && currentResultIndex < r.count {
                onResultSelect(.epubChapter(r[currentResultIndex].chapterIndex))
            }
        }
    }
}
