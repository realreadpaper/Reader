import SwiftUI

enum SearchPanelLayout {
    static let maxWidth: CGFloat = 480
    static let resultAreaMaxHeight: CGFloat = 200

    static func maxHeight(hasResultArea: Bool) -> CGFloat? {
        hasResultArea ? resultAreaMaxHeight : nil
    }
}

enum SearchInputPolicy {
    static let debounceDelay: Duration = .milliseconds(250)

    static func normalizedQuery(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shouldSearchAutomatically(previous: String, current: String) -> Bool {
        normalizedQuery(previous) != normalizedQuery(current)
    }
}

struct SearchPanelView: View {
    let coordinator: RenderCoordinator
    let onResultSelect: (SearchResultTarget) -> Void
    let onClose: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @State private var searchText = ""
    @State private var epubResults: [RenderCoordinator.EPUBSearchResult] = []
    @State private var currentResultIndex = 0
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.secondaryText)

                TextField("搜索内容...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.currentTheme.primaryText)
                    .tint(themeManager.currentTheme.accent)
                    .onSubmit { performSearchImmediately() }
                    .submitLabel(.search)

                if !epubResults.isEmpty || !coordinator.pdfSearchResults.isEmpty {
                    Text(totalResultsText)
                        .font(.caption2)
                        .foregroundStyle(themeManager.currentTheme.secondaryText)
                        .monospacedDigit()
                }

                Divider()
                    .frame(height: 14)
                    .background(themeManager.currentTheme.border)

                Button(action: previousResult) {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(totalResultsCount > 0 ? themeManager.currentTheme.secondaryText : themeManager.currentTheme.border)
                .disabled(totalResultsCount == 0)

                Button(action: nextResult) {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(totalResultsCount > 0 ? themeManager.currentTheme.secondaryText : themeManager.currentTheme.border)
                .disabled(totalResultsCount == 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(themeManager.currentTheme.contentBG)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(themeManager.currentTheme.border, lineWidth: 0.5)
            )

            resultList
        }
        .frame(
            maxWidth: SearchPanelLayout.maxWidth,
            maxHeight: SearchPanelLayout.maxHeight(hasResultArea: hasResultArea),
            alignment: .top
        )
        .background(themeManager.currentTheme.sidebarBG)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .onDisappear {
            searchTask?.cancel()
            searchText = ""
            epubResults = []
            currentResultIndex = 0
            coordinator.pdfSearchResults = []
        }
        .onChange(of: searchText) { oldValue, newValue in
            scheduleSearch(previous: oldValue, current: newValue)
        }
    }

    @MainActor
    private var hasResultArea: Bool {
        !searchText.isEmpty || totalResultsCount > 0
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
                    .padding(.vertical, 12)
            }
        } else {
            Divider().background(themeManager.currentTheme.border)
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
                        }
                    } else {
                        ForEach(epubResults) { result in
                            Button(action: {
                                onResultSelect(.epubChapter(result.chapterIndex))
                            }) {
                                searchRow(title: result.chapterTitle, snippet: result.snippet)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func searchRow(title: String, snippet: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(themeManager.currentTheme.primaryText)
            Text(highlightedSnippet(snippet))
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func highlightedSnippet(_ snippet: String) -> AttributedString {
        var attr = AttributedString(snippet)
        attr.foregroundColor = themeManager.currentTheme.secondaryText
        guard !searchText.isEmpty else { return attr }
        let nsSnippet = snippet as NSString
        var searchRange = NSRange(location: 0, length: nsSnippet.length)
        while searchRange.location < nsSnippet.length {
            let found = nsSnippet.range(of: searchText, options: .caseInsensitive, range: searchRange)
            guard found.location != NSNotFound else { break }
            if let attrRange = Range(found, in: attr) {
                attr[attrRange].foregroundColor = themeManager.currentTheme.accent
                attr[attrRange].font = .caption2.weight(.semibold)
            }
            searchRange = NSRange(location: found.location + found.length, length: nsSnippet.length - found.location - found.length)
        }
        return attr
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
    private func scheduleSearch(previous: String, current: String) {
        searchTask?.cancel()
        guard SearchInputPolicy.shouldSearchAutomatically(previous: previous, current: current) else {
            return
        }

        let query = SearchInputPolicy.normalizedQuery(current)
        guard !query.isEmpty else {
            clearSearchResults()
            return
        }

        searchTask = Task { @MainActor in
            try? await Task.sleep(for: SearchInputPolicy.debounceDelay)
            guard !Task.isCancelled else { return }
            await performSearch(query)
        }
    }

    @MainActor
    private func performSearchImmediately() {
        searchTask?.cancel()
        let query = SearchInputPolicy.normalizedQuery(searchText)
        Task { @MainActor in
            await performSearch(query)
        }
    }

    @MainActor
    private func clearSearchResults() {
        epubResults = []
        coordinator.pdfSearchResults = []
        currentResultIndex = 0
    }

    @MainActor
    private func performSearch(_ query: String) async {
        guard !query.isEmpty else {
            clearSearchResults()
            return
        }

        currentResultIndex = 0

        if coordinator.book.fileType == .pdf {
            epubResults = []
            coordinator.searchPDF(query)
            return
        }

        coordinator.pdfSearchResults = []
        epubResults = await coordinator.searchEPUB(query)
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
