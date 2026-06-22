import SwiftUI

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
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.currentTheme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Picker("", selection: $selectedTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)

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

    private func importBook() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .init(filenameExtension: "epub")!,
            .init(filenameExtension: "mobi")!,
            .init(filenameExtension: "pdf")!
        ]

        if panel.runModal() == .OK, let url = panel.url {
            let fileType = FileType(rawValue: url.pathExtension.lowercased()) ?? .epub
            Task {
                await storageService.addBook(
                    title: url.deletingPathExtension().lastPathComponent,
                    filePath: url.path,
                    fileType: fileType
                )
            }
        }
    }
}
