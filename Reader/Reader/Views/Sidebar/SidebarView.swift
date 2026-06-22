import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Binding var selectedBook: Book?
    let storageService: StorageService

    @State private var selectedTab: SidebarTab = .all
    @Environment(ThemeManager.self) private var theme

    enum SidebarTab: String, CaseIterable {
        case all = "全部"
        case recent = "最近"
        case favorite = "收藏"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("书架")
                    .font(.headline)
                    .foregroundStyle(theme.currentTheme.primaryText)
                Spacer()
                Button(action: importBook) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.currentTheme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            HStack(spacing: 0) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab.rawValue)
                            .font(.caption)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .foregroundStyle(
                                selectedTab == tab
                                    ? theme.currentTheme.primaryText
                                    : theme.currentTheme.secondaryText
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                selectedTab == tab
                                    ? theme.currentTheme.border.opacity(0.6)
                                    : Color.clear
                            )
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Divider()
                .background(theme.currentTheme.border)

            TabView(selection: $selectedTab) {
                BookListView(
                    books: storageService.fetchBooks(),
                    selectedBook: $selectedBook
                )
                .tag(SidebarTab.all)

                BookListView(
                    books: storageService.fetchRecentBooks(),
                    selectedBook: $selectedBook
                )
                .tag(SidebarTab.recent)

                BookListView(
                    books: storageService.fetchFavoriteBooks(),
                    selectedBook: $selectedBook
                )
                .tag(SidebarTab.favorite)
            }
        }
        .background(theme.currentTheme.sidebarBG)
    }

    @MainActor
    private func importBook() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        var types: [UTType] = []
        if let epubType = UTType(filenameExtension: "epub") {
            types.append(epubType)
        }
        if let mobiType = UTType(filenameExtension: "mobi") {
            types.append(mobiType)
        }
        if let pdfType = UTType(filenameExtension: "pdf") {
            types.append(pdfType)
        }
        panel.allowedContentTypes = types

        let result = panel.runModal()
        guard result == .OK, let url = panel.url else { return }
        
        let ext = url.pathExtension.lowercased()
        let fileType = FileType(rawValue: ext) ?? .epub
        let title = url.deletingPathExtension().lastPathComponent
        
        _ = storageService.addBook(
            title: title,
            filePath: url.path,
            fileType: fileType
        )
    }
}
