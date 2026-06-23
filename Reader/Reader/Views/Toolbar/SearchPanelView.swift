import SwiftUI

enum SearchPanelLayout {
    static let maxWidth: CGFloat = 480
    static let resultAreaMaxHeight: CGFloat = 200

    static func maxHeight(hasResultArea: Bool) -> CGFloat? {
        hasResultArea ? resultAreaMaxHeight : nil
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
                    .onSubmit { performSearch() }
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
            searchText = ""
            epubResults = []
            currentResultIndex = 0
            coordinator.pdfSearchResults = []
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
            Text(snippet)
                .font(.caption2)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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

        Task {
            let results = await coordinator.searchEPUB(searchText)
            epubResults = results
            currentResultIndex = 0
        }
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
