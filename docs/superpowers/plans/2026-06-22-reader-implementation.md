# Reader — macOS 原生阅读器实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 开发一款支持 EPUB/MOBI/PDF 的 macOS 原生阅读器，温暖纸质风格界面

**Architecture:** SwiftUI 构建界面，WKWebView 渲染 EPUB/MOBI，PDFKit 渲染 PDF，SwiftData 持久化数据。MOBI 导入时预转换为 EPUB 复用渲染管线。

**Tech Stack:** SwiftUI, WKWebView, PDFKit, SwiftData, Combine

---

## 文件结构

```
Reader/
├── ReaderApp.swift                    # 应用入口，SwiftData container 配置
├── Models/
│   ├── Book.swift                     # 书籍模型
│   ├── Bookmark.swift                 # 书签模型
│   ├── Highlight.swift                # 标注模型
│   └── Enums.swift                    # FileType, HighlightColor 枚举
├── Views/
│   ├── ContentView.swift              # 主布局容器（侧边栏 + 阅读区）
│   ├── Sidebar/
│   │   ├── SidebarView.swift          # 侧边栏容器（分段切换）
│   │   ├── BookListView.swift         # 书架列表
│   │   ├── BookRowView.swift          # 单本书行视图
│   │   ├── TOCView.swift              # 目录视图
│   │   └── AnnotationView.swift       # 标注列表视图
│   ├── Reader/
│   │   ├── ReaderView.swift           # 阅读主区域容器
│   │   ├── EPUBRendererView.swift     # EPUB WKWebView 渲染
│   │   ├── PDFRendererView.swift      # PDF PDFKit 渲染
│   │   └── RenderCoordinator.swift    # 渲染器协调器，分发格式
│   ├── Toolbar/
│   │   ├── TopBarView.swift           # 顶部工具栏
│   │   ├── BottomBarView.swift        # 底部状态栏
│   │   ├── FontPanelView.swift        # 字体设置面板
│   │   └── SearchPanelView.swift      # 搜索面板
│   └── Components/
│       ├── HighlightMenuView.swift    # 高亮操作弹出菜单
│       └── ProgressRingView.swift     # 进度条组件
├── Services/
│   ├── EPUBParser.swift               # EPUB 解析服务
│   ├── MOBIConverter.swift            # MOBI 转换服务
│   ├── StorageService.swift           # 数据持久化服务
│   └── ThemeManager.swift             # 主题管理
├── Resources/
│   ├── Styles/
│   │   ├── epub-default.css           # EPUB 默认样式
│   │   └── epub-themes.css            # EPUB 主题样式
│   └── Fonts/                         # 内置字体（可选）
└── Assets.xcassets/                   # 图标资源
```

---

## Task 1: 项目初始化与数据模型

**Files:**
- Create: `Reader/Reader.xcodeproj` (Xcode 项目)
- Create: `Reader/ReaderApp.swift`
- Create: `Reader/Models/Enums.swift`
- Create: `Reader/Models/Book.swift`
- Create: `Reader/Models/Bookmark.swift`
- Create: `Reader/Models/Highlight.swift`

- [ ] **Step 1: 创建 Xcode 项目**

在 Xcode 中创建 macOS App 项目：
- Product Name: Reader
- Organization Identifier: (用户指定)
- Interface: SwiftUI
- Language: Swift
- Minimum Deployment: macOS 14.0
- 勾选 Use SwiftData

- [ ] **Step 2: 创建枚举定义**

```swift
// Reader/Models/Enums.swift
import Foundation

enum FileType: String, Codable {
    case epub
    case mobi
    case pdf
}

enum HighlightColor: String, Codable, CaseIterable {
    case yellow
    case green
    case orange
    case blue
    
    var hex: String {
        switch self {
        case .yellow: return "#F5D76E"
        case .green: return "#7EC8A0"
        case .orange: return "#E8A87C"
        case .blue: return "#A0B8E8"
        }
    }
    
    var overlayHex: String {
        switch self {
        case .yellow: return "#E8D5A0"
        case .green: return "#C8E8D5"
        case .orange: return "#E8D0B8"
        case .blue: return "#C8D5E8"
        }
    }
}
```

- [ ] **Step 3: 创建 Book 模型**

```swift
// Reader/Models/Book.swift
import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String?
    var coverPath: String?
    var filePath: String
    var fileType: FileType
    var lastRead: Date?
    var progress: Double
    var isFavorite: Bool
    var addedAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    var bookmarks: [Bookmark]
    
    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    var highlights: [Highlight]
    
    init(
        title: String,
        author: String? = nil,
        coverPath: String? = nil,
        filePath: String,
        fileType: FileType
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.coverPath = coverPath
        self.filePath = filePath
        self.fileType = fileType
        self.lastRead = nil
        self.progress = 0.0
        self.isFavorite = false
        self.addedAt = Date()
        self.bookmarks = []
        self.highlights = []
    }
}
```

- [ ] **Step 4: 创建 Bookmark 模型**

```swift
// Reader/Models/Bookmark.swift
import Foundation
import SwiftData

@Model
final class Bookmark {
    var id: UUID
    var book: Book?
    var position: String  // "chapterIndex:paragraphOffset" 或 CSS 选择器
    var chapter: String?
    var note: String?
    var createdAt: Date
    
    init(
        book: Book?,
        position: String,
        chapter: String? = nil,
        note: String? = nil
    ) {
        self.id = UUID()
        self.book = book
        self.position = position
        self.chapter = chapter
        self.note = note
        self.createdAt = Date()
    }
}
```

- [ ] **Step 5: 创建 Highlight 模型**

```swift
// Reader/Models/Highlight.swift
import Foundation
import SwiftData

@Model
final class Highlight {
    var id: UUID
    var book: Book?
    var selectedText: String
    var color: HighlightColor
    var startOffset: Int
    var endOffset: Int
    var chapter: String?
    var note: String?
    var createdAt: Date
    
    init(
        book: Book?,
        selectedText: String,
        color: HighlightColor,
        startOffset: Int,
        endOffset: Int,
        chapter: String? = nil,
        note: String? = nil
    ) {
        self.id = UUID()
        self.book = book
        self.selectedText = selectedText
        self.color = color
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.chapter = chapter
        self.note = note
        self.createdAt = Date()
    }
}
```

- [ ] **Step 6: 创建应用入口**

```swift
// Reader/ReaderApp.swift
import SwiftUI
import SwiftData

@main
struct ReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Book.self, Bookmark.self, Highlight.self])
    }
}
```

- [ ] **Step 7: Commit**

```bash
git add Reader/
git commit -m "feat: 初始化项目，创建数据模型"
```

---

## Task 2: 主题管理与配色系统

**Files:**
- Create: `Reader/Services/ThemeManager.swift`

- [ ] **Step 1: 创建主题管理器**

```swift
// Reader/Services/ThemeManager.swift
import SwiftUI

enum AppTheme: String, CaseIterable {
    case classic      // 经典米白
    case kraft        // 复古牛皮纸
    case night        // 夜间模式
    case eyeCare      // 护眼绿
    
    var name: String {
        switch self {
        case .classic: return "经典"
        case .kraft: return "牛皮纸"
        case .night: return "夜间"
        case .eyeCare: return "护眼"
        }
    }
    
    var sidebarBG: Color {
        switch self {
        case .classic: return Color(hex: "#F0E8DE")
        case .kraft: return Color(hex: "#E8DCC8")
        case .night: return Color(hex: "#15120F")
        case .eyeCare: return Color(hex: "#C5D8C0")
        }
    }
    
    var contentBG: Color {
        switch self {
        case .classic: return Color(hex: "#FAF6EF")
        case .kraft: return Color(hex: "#F5EFE3")
        case .night: return Color(hex: "#1E1A15")
        case .eyeCare: return Color(hex: "#D5E8D0")
        }
    }
    
    var primaryText: Color {
        switch self {
        case .classic: return Color(hex: "#3A3025")
        case .kraft: return Color(hex: "#2E2518")
        case .night: return Color(hex: "#D5C8B0")
        case .eyeCare: return Color(hex: "#2A3528")
        }
    }
    
    var secondaryText: Color {
        switch self {
        case .classic: return Color(hex: "#6B5A40")
        case .kraft: return Color(hex: "#5A4A3A")
        case .night: return Color(hex: "#A09080")
        case .eyeCare: return Color(hex: "#4A5A42")
        }
    }
    
    var accent: Color {
        switch self {
        case .classic: return Color(hex: "#8B7355")
        case .kraft: return Color(hex: "#8B7355")
        case .night: return Color(hex: "#C8A870")
        case .eyeCare: return Color(hex: "#6B8B5A")
        }
    }
    
    var border: Color {
        switch self {
        case .classic: return Color(hex: "#E0D5C8")
        case .kraft: return Color(hex: "#D5C8B0")
        case .night: return Color(hex: "#2A2520")
        case .eyeCare: return Color(hex: "#A8C0A0")
        }
    }
    
    var highlightBG: Color {
        switch self {
        case .classic: return Color(hex: "#F5D76E")
        case .kraft: return Color(hex: "#E8D5A0")
        case .night: return Color(hex: "#5A4A28")
        case .eyeCare: return Color(hex: "#C8E0A0")
        }
    }
}

@Observable
final class ThemeManager {
    var currentTheme: AppTheme = .kraft
    
    init() {
        if let saved = UserDefaults.standard.string(forKey: "appTheme"),
           let theme = AppTheme(rawValue: saved) {
            currentTheme = theme
        }
    }
    
    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Reader/Services/ThemeManager.swift
git commit -m "feat: 添加主题管理器和配色系统"
```

---

## Task 3: EPUB 解析器

**Files:**
- Create: `Reader/Services/EPUBParser.swift`

- [ ] **Step 1: 创建 EPUB 解析器**

```swift
// Reader/Services/EPUBParser.swift
import Foundation

struct EPUBChapter {
    let title: String
    let htmlContent: String
    let fileName: String
}

struct EPUBMetadata {
    let title: String
    let author: String?
    let chapters: [EPUBChapter]
    let tocEntries: [(title: String, chapterIndex: Int)]
}

final class EPUBParser {
    
    func parse(fileAt url: URL) throws -> EPUBMetadata {
        let unzipDir = try unzipEPUB(at: url)
        defer { try? FileManager.default.removeItem(at: unzipDir) }
        
        let opfURL = try findOPF(in: unzipDir)
        let metadata = try parseOPF(at: opfURL)
        let containerDir = opfURL.deletingLastPathComponent()
        
        let chapters = try parseChapters(
            manifest: metadata.manifest,
            containerDir: containerDir
        )
        
        let tocEntries = parseTOC(
            toc: metadata.toc,
            spineOrder: metadata.spineOrder,
            chapters: chapters
        )
        
        return EPUBMetadata(
            title: metadata.title,
            author: metadata.author,
            chapters: chapters,
            tocEntries: tocEntries
        )
    }
    
    private func unzipEPUB(at url: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // 使用 Process 调用 unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", url.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw EPUBError.unzipFailed
        }
        return tempDir
    }
    
    private func findOPF(in directory: URL) throws -> URL {
        let containerPath = directory
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")
        
        let containerXML = try String(contentsOf: containerPath, encoding: .utf8)
        
        // 提取 full-path 属性
        guard let range = containerXML.range(of: #""full-path"\s*=\s*"[^"]*""#),
              let pathRange = containerXML[range].range(of: #""[^"]*"$"#) else {
            throw EPUBError.invalidContainer
        }
        
        var fullPath = String(containerXML[pathRange])
        fullPath.removeFirst()  // 移除开头引号
        fullPath.removeLast()   // 移除结尾引号
        
        return directory.appendingPathComponent(fullPath)
    }
    
    private struct OPFResult {
        let title: String
        let author: String?
        let manifest: [(id: String, href: String, mediaType: String)]
        let spineOrder: [String]
        let toc: [(title: String, href: String)]?
    }
    
    private func parseOPF(at url: URL) throws -> OPFResult {
        let opfString = try String(contentsOf: url, encoding: .utf8)
        // 简化解析，实际应使用 XMLParser
        // 此处使用正则提取关键信息
        
        let title = extractTag("dc:title", from: opfString) ?? "Untitled"
        let author = extractTag("dc:creator", from: opfString)
        
        // 提取 manifest items
        let manifestPattern = #"<item\s+id="([^"]*)"\s+href="([^"]*)"\s+media-type="([^"]*)""#
        var manifest: [(id: String, href: String, mediaType: String)] = []
        for match in opfString.matches(of: manifestPattern) {
            manifest.append((
                id: String(match.1),
                href: String(match.2),
                mediaType: String(match.3)
            ))
        }
        
        // 提取 spine order
        let spinePattern = #"<itemref\s+idref="([^"]*)""#
        let spineOrder = opfString.matches(of: spinePattern).map { String($0.1) }
        
        return OPFResult(
            title: title,
            author: author,
            manifest: manifest,
            spineOrder: spineOrder,
            toc: nil
        )
    }
    
    private func extractTag(_ tag: String, from xml: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]*)</\(tag)>"
        guard let range = xml.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        var content = String(xml[range])
        content = content.replacingOccurrences(of: "<\(tag)[^>]*>", with: "", options: .regularExpression)
        content = content.replacingOccurrences(of: "</\(tag)>", with: "")
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func parseChapters(
        manifest: [(id: String, href: String, mediaType: String)],
        containerDir: URL
    ) throws -> [EPUBChapter] {
        let htmlItems = manifest.filter { $0.mediaType.contains("html") || $0.mediaType.contains("xhtml") }
        
        return try htmlItems.map { item in
            let fileURL = containerDir.appendingPathComponent(item.href)
            let html = try String(contentsOf: fileURL, encoding: .utf8)
            let title = extractTitle(from: html) ?? item.href
            return EPUBChapter(title: title, htmlContent: html, fileName: item.href)
        }
    }
    
    private func extractTitle(from html: String) -> String? {
        if let titleRange = html.range(of: "<title[^>]*>([^<]*)</title>", options: .regularExpression) {
            var title = String(html[titleRange])
            title = title.replacingOccurrences(of: "<title[^>]*>", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "</title>", with: "")
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let h1Range = html.range(of: "<h1[^>]*>([^<]*)</h1>", options: .regularExpression) {
            var title = String(html[h1Range])
            title = title.replacingOccurrences(of: "<h1[^>]*>", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "</h1>", with: "")
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    private func parseTOC(
        toc: [(title: String, href: String)]?,
        spineOrder: [String],
        chapters: [EPUBChapter]
    ) -> [(title: String, chapterIndex: Int)] {
        return chapters.enumerated().map { (index, chapter) in
            (title: chapter.title, chapterIndex: index)
        }
    }
}

enum EPUBError: Error, LocalizedError {
    case unzipFailed
    case invalidContainer
    case missingOPF
    
    var errorDescription: String? {
        switch self {
        case .unzipFailed: return "无法解压 EPUB 文件"
        case .invalidContainer: return "EPUB container.xml 格式无效"
        case .missingOPF: return "未找到 OPF 文件"
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Reader/Services/EPUBParser.swift
git commit -m "feat: 添加 EPUB 解析器"
```

---

## Task 4: MOBI 转换器

**Files:**
- Create: `Reader/Services/MOBIConverter.swift`

- [ ] **Step 1: 创建 MOBI 转换器**

```swift
// Reader/Services/MOBIConverter.swift
import Foundation

final class MOBIConverter {
    
    private let converterPath: String?
    
    init() {
        // 尝试查找 calibre 的 ebook-convert 工具
        let paths = [
            "/opt/homebrew/bin/ebook-convert",
            "/usr/local/bin/ebook-convert",
            "/Applications/calibre.app/Contents/MacOS/ebook-convert"
        ]
        self.converterPath = paths.first { FileManager.default.fileExists(atPath: $0) }
    }
    
    var isAvailable: Bool {
        converterPath != nil
    }
    
    func convertToEPUB(mobiURL: URL) async throws -> URL {
        guard let converterPath else {
            throw MOBIError.converterNotFound
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(mobiURL.deletingPathExtension().lastPathComponent).epub")
        
        // 如果已转换过，直接返回
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: converterPath)
        process.arguments = [mobiURL.path, outputURL.path]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "未知错误"
            throw MOBIError.conversionFailed(errorMessage)
        }
        
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw MOBIError.conversionFailed("转换后文件不存在")
        }
        
        return outputURL
    }
}

enum MOBIError: Error, LocalizedError {
    case converterNotFound
    case conversionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .converterNotFound: 
            return "未找到 ebook-convert 工具，请安装 calibre"
        case .conversionFailed(let msg): 
            return "MOBI 转换失败: \(msg)"
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Reader/Services/MOBIConverter.swift
git commit -m "feat: 添加 MOBI 转换器"
```

---

## Task 5: 存储服务

**Files:**
- Create: `Reader/Services/StorageService.swift`

- [ ] **Step 1: 创建存储服务**

```swift
// Reader/Services/StorageService.swift
import Foundation
import SwiftData

@Observable
final class StorageService {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    
    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        self.modelContainer = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: config
        )
        self.modelContext = modelContainer.mainContext
    }
    
    // MARK: - Book CRUD
    
    func addBook(title: String, author: String? = nil, filePath: String, fileType: FileType) -> Book {
        let book = Book(title: title, author: author, filePath: filePath, fileType: fileType)
        modelContext.insert(book)
        save()
        return book
    }
    
    func fetchBooks() -> [Book] {
        let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.lastRead, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func fetchRecentBooks(limit: Int = 10) -> [Book] {
        let descriptor = FetchDescriptor<Book>(
            sortBy: [SortDescriptor(\.lastRead, order: .reverse)],
            fetchLimit: limit
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func fetchFavoriteBooks() -> [Book] {
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.title)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func updateBook(_ book: Book) {
        book.lastRead = Date()
        save()
    }
    
    func deleteBook(_ book: Book) {
        modelContext.delete(book)
        save()
    }
    
    // MARK: - Bookmark CRUD
    
    func addBookmark(to book: Book, position: String, chapter: String? = nil) -> Bookmark {
        let bookmark = Bookmark(book: book, position: position, chapter: chapter)
        modelContext.insert(bookmark)
        save()
        return bookmark
    }
    
    func fetchBookmarks(for book: Book) -> [Bookmark] {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate<Bookmark> { $0.book?.id == book.id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func deleteBookmark(_ bookmark: Bookmark) {
        modelContext.delete(bookmark)
        save()
    }
    
    // MARK: - Highlight CRUD
    
    func addHighlight(
        to book: Book,
        text: String,
        color: HighlightColor,
        startOffset: Int,
        endOffset: Int,
        chapter: String? = nil
    ) -> Highlight {
        let highlight = Highlight(
            book: book,
            selectedText: text,
            color: color,
            startOffset: startOffset,
            endOffset: endOffset,
            chapter: chapter
        )
        modelContext.insert(highlight)
        save()
        return highlight
    }
    
    func fetchHighlights(for book: Book) -> [Highlight] {
        let descriptor = FetchDescriptor<Highlight>(
            predicate: #Predicate<Highlight> { $0.book?.id == book.id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func updateHighlight(_ highlight: Highlight, note: String?) {
        highlight.note = note
        save()
    }
    
    func deleteHighlight(_ highlight: Highlight) {
        modelContext.delete(highlight)
        save()
    }
    
    // MARK: - Private
    
    private func save() {
        try? modelContext.save()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Reader/Services/StorageService.swift
git commit -m "feat: 添加存储服务"
```

---

## Task 6: 主布局与侧边栏

**Files:**
- Create: `Reader/Views/ContentView.swift`
- Create: `Reader/Views/Sidebar/SidebarView.swift`
- Create: `Reader/Views/Sidebar/BookListView.swift`
- Create: `Reader/Views/Sidebar/BookRowView.swift`
- Create: `Reader/Views/Sidebar/TOCView.swift`
- Create: `Reader/Views/Sidebar/AnnotationView.swift`

- [ ] **Step 1: 创建主布局容器**

```swift
// Reader/Views/ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var themeManager = ThemeManager()
    @State private var selectedBook: Book?
    @State private var showSidebar = true
    @State private var storageService: StorageService
    
    init() {
        _storageService = State(initialValue: try! StorageService())
    }
    
    var body: some View {
        HSplitView {
            if showSidebar {
                SidebarView(
                    selectedBook: $selectedBook,
                    storageService: storageService
                )
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
            }
            
            if let book = selectedBook {
                ReaderView(book: book, themeManager: themeManager)
            } else {
                WelcomeView()
            }
        }
        .environment(themeManager)
        .environment(storageService)
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" {
                    showSidebar.toggle()
                    return nil
                }
                return event
            }
        }
    }
}

struct WelcomeView: View {
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book")
                .font(.system(size: 64))
                .foregroundStyle(theme.accent)
            Text("选择一本书开始阅读")
                .font(.title2)
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.contentBG)
    }
}
```

- [ ] **Step 2: 创建侧边栏容器**

```swift
// Reader/Views/Sidebar/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    @Binding var selectedBook: Book?
    let storageService: StorageService
    
    @State private var selectedTab: SidebarTab = .all
    @State private var searchText = ""
    
    enum SidebarTab: String, CaseIterable {
        case all = "全部"
        case recent = "最近"
        case favorite = "收藏"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("书架")
                    .font(.headline)
                    .foregroundStyle(ThemeManager().primaryText)
                Spacer()
                Button(action: importBook) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            // 分段切换
            Picker("", selection: $selectedTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            
            // 内容
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
            _ = storageService.addBook(
                title: url.deletingPathExtension().lastPathComponent,
                filePath: url.path,
                fileType: fileType
            )
        }
    }
}
```

- [ ] **Step 3: 创建书籍列表视图**

```swift
// Reader/Views/Sidebar/BookListView.swift
import SwiftUI

struct BookListView: View {
    let books: [Book]
    @Binding var selectedBook: Book?
    
    var body: some View {
        List(selection: $selectedBook) {
            ForEach(books, id: \.id) { book in
                BookRowView(book: book)
                    .tag(book)
            }
        }
        .listStyle(.sidebar)
    }
}

struct BookRowView: View {
    let book: Book
    
    var body: some View {
        HStack(spacing: 10) {
            // 封面占位
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: "#D5C8B0"))
                .frame(width: 36, height: 48)
                .overlay(
                    Text(String(book.title.prefix(2)))
                        .font(.caption2)
                        .foregroundStyle(Color(hex: "#6B5A40"))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text("读到 \(Int(book.progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 4: 创建目录视图**

```swift
// Reader/Views/Sidebar/TOCView.swift
import SwiftUI

struct TOCView: View {
    let chapters: [(title: String, chapterIndex: Int)]
    let onChapterSelect: (Int) -> Void
    
    var body: some View {
        List {
            ForEach(chapters, id: \.chapterIndex) { chapter in
                Button(action: { onChapterSelect(chapter.chapterIndex) }) {
                    Text(chapter.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
}
```

- [ ] **Step 5: 创建标注列表视图**

```swift
// Reader/Views/Sidebar/AnnotationView.swift
import SwiftUI

struct AnnotationView: View {
    let highlights: [Highlight]
    let onHighlightSelect: (Highlight) -> Void
    
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
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(highlight.selectedText)
                            .font(.subheadline)
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                        if let note = highlight.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
```

- [ ] **Step 6: Commit**

```bash
git add Reader/Views/
git commit -m "feat: 添加主布局和侧边栏视图"
```

---

## Task 7: EPUB 渲染器

**Files:**
- Create: `Reader/Views/Reader/EPUBRendererView.swift`
- Create: `Reader/Resources/Styles/epub-default.css`
- Create: `Reader/Resources/Styles/epub-themes.css`

- [ ] **Step 1: 创建 EPUB CSS 样式**

```css
/* Reader/Resources/Styles/epub-default.css */
body {
    max-width: 560px;
    margin: 0 auto;
    padding: 40px 20px;
    font-family: -apple-system, "PingFang SC", "Songti SC", serif;
    font-size: 16px;
    line-height: 2.1;
    color: #2E2518;
    background: #F5EFE3;
}

h1, h2, h3, h4 {
    color: #2E2518;
    margin-top: 2em;
    margin-bottom: 0.8em;
}

h1 { font-size: 1.8em; }
h2 { font-size: 1.5em; }
h3 { font-size: 1.3em; }

p {
    text-indent: 2em;
    margin-bottom: 1em;
}

img {
    max-width: 100%;
    height: auto;
}

/* 高亮样式 */
.highlight-yellow { background-color: #E8D5A0; }
.highlight-green { background-color: #C8E8D5; }
.highlight-orange { background-color: #E8D0B8; }
.highlight-blue { background-color: #C8D5E8; }
```

- [ ] **Step 2: 创建主题 CSS**

```css
/* Reader/Resources/Styles/epub-themes.css */

/* 经典米白 */
.theme-classic {
    background: #FAF6EF;
    color: #3A3025;
}
.theme-classic h1, .theme-classic h2, .theme-classic h3 { color: #3A3025; }

/* 复古牛皮纸 */
.theme-kraft {
    background: #F5EFE3;
    color: #2E2518;
}
.theme-kraft h1, .theme-kraft h2, .theme-kraft h3 { color: #2E2518; }

/* 夜间模式 */
.theme-night {
    background: #1E1A15;
    color: #D5C8B0;
}
.theme-night h1, .theme-night h2, .theme-night h3 { color: #D5C8B0; }
.theme-night .highlight-yellow { background-color: #5A4A28; }
.theme-night .highlight-green { background-color: #2A4A35; }
.theme-night .highlight-orange { background-color: #4A3528; }
.theme-night .highlight-blue { background-color: #2A3550; }

/* 护眼绿 */
.theme-eyeCare {
    background: #D5E8D0;
    color: #2A3528;
}
.theme-eyeCare h1, .theme-eyeCare h2, .theme-eyeCare h3 { color: #2A3528; }
```

- [ ] **Step 3: 创建 EPUB 渲染视图**

```swift
// Reader/Views/Reader/EPUBRendererView.swift
import SwiftUI
import WebKit

struct EPUBRendererView: View {
    let book: Book
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var progress: Double
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        EPUBWebView(
            chapters: chapters,
            currentChapter: $currentChapter,
            progress: $progress,
            theme: theme.currentTheme
        )
    }
}

struct EPUBWebView: NSViewRepresentable {
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var progress: Double
    let theme: AppTheme
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "readerBridge")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        guard currentChapter < chapters.count else { return }
        let chapter = chapters[currentChapter]
        
        let html = wrapHTML(chapter.htmlContent, theme: theme)
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    private func wrapHTML(_ content: String, theme: AppTheme) -> String {
        let themeClass = "theme-\(theme.rawValue)"
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="stylesheet" href="epub-default.css">
            <link rel="stylesheet" href="epub-themes.css">
            <style>
                body { background: \(theme.contentBG.hex); color: \(theme.primaryText.hex); }
                \(getThemeOverrides(theme))
            </style>
        </head>
        <body class="\(themeClass)">
            \(content)
            <script>
                document.addEventListener('selectionchange', function() {
                    var selection = window.getSelection();
                    if (selection.rangeCount > 0 && selection.toString().length > 0) {
                        var range = selection.getRangeAt(0);
                        var rect = range.getBoundingClientRect();
                        window.webkit.messageHandlers.readerBridge.postMessage({
                            type: 'selection',
                            text: selection.toString(),
                            x: rect.x,
                            y: rect.y,
                            width: rect.width,
                            height: rect.height
                        });
                    }
                });
            </script>
        </body>
        </html>
        """
    }
    
    private func getThemeOverrides(_ theme: AppTheme) -> String {
        switch theme {
        case .night:
            return """
            img { filter: brightness(0.8); }
            """
        default:
            return ""
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EPUBWebView
        
        init(_ parent: EPUBWebView) {
            self.parent = parent
        }
        
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  body["type"] as? String == "selection" else { return }
            
            if let text = body["text"] as? String {
                // 发送选中事件通知
                NotificationCenter.default.post(
                    name: .textSelected,
                    object: nil,
                    userInfo: ["text": text]
                )
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 章节加载完成
        }
    }
}

extension Notification.Name {
    static let textSelected = Notification.Name("textSelected")
}
```

- [ ] **Step 4: Commit**

```bash
git add Reader/Views/Reader/EPUBRendererView.swift Reader/Resources/Styles/
git commit -m "feat: 添加 EPUB 渲染器和样式"
```

---

## Task 8: PDF 渲染器

**Files:**
- Create: `Reader/Views/Reader/PDFRendererView.swift`

- [ ] **Step 1: 创建 PDF 渲染视图**

```swift
// Reader/Views/Reader/PDFRendererView.swift
import SwiftUI
import PDFKit

struct PDFRendererView: View {
    let book: Book
    @Binding var progress: Double
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        PDFKitView(url: URL(fileURLWithPath: book.filePath), progress: $progress)
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL
    @Binding var progress: Double
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
        
        return pdfView
    }
    
    func updateNSView(_ pdfView: PDFView, context: Context) {
        // 更新进度
        if let document = pdfView.document, let page = pdfView.currentPage {
            let pageIndex = document.index(for: page)
            let totalPages = document.pageCount
            progress = totalPages > 0 ? Double(pageIndex) / Double(totalPages) : 0
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Reader/Views/Reader/PDFRendererView.swift
git commit -m "feat: 添加 PDF 渲染器"
```

---

## Task 9: 阅读主区域与工具栏

**Files:**
- Create: `Reader/Views/Reader/ReaderView.swift`
- Create: `Reader/Views/Reader/RenderCoordinator.swift`
- Create: `Reader/Views/Toolbar/TopBarView.swift`
- Create: `Reader/Views/Toolbar/BottomBarView.swift`

- [ ] **Step 1: 创建渲染协调器**

```swift
// Reader/Views/Reader/RenderCoordinator.swift
import Foundation

@Observable
final class RenderCoordinator {
    var book: Book
    var currentChapter: Int = 0
    var progress: Double = 0
    var epubMetadata: EPUBMetadata?
    var showTOC: Bool = false
    var showSearch: Bool = false
    var showFontPanel: Bool = false
    
    init(book: Book) {
        self.book = book
    }
    
    func loadEPUB() async {
        guard book.fileType == .epub else { return }
        let parser = EPUBParser()
        if let metadata = try? parser.parse(fileAt: URL(fileURLWithPath: book.filePath)) {
            self.epubMetadata = metadata
        }
    }
    
    func loadMOBI() async {
        guard book.fileType == .mobi else { return }
        let converter = MOBIConverter()
        if converter.isAvailable,
           let epubURL = try? await converter.convertToEPUB(mobiURL: URL(fileURLWithPath: book.filePath)) {
            let parser = EPUBParser()
            if let metadata = try? parser.parse(fileAt: epubURL) {
                self.epubMetadata = metadata
            }
        }
    }
    
    var chapters: [EPUBChapter] {
        epubMetadata?.chapters ?? []
    }
    
    var tocEntries: [(title: String, chapterIndex: Int)] {
        epubMetadata?.tocEntries ?? []
    }
    
    func navigateToChapter(_ index: Int) {
        guard index < chapters.count else { return }
        currentChapter = index
    }
}
```

- [ ] **Step 2: 创建阅读主区域**

```swift
// Reader/Views/Reader/ReaderView.swift
import SwiftUI

struct ReaderView: View {
    let book: Book
    let themeManager: ThemeManager
    
    @State private var coordinator: RenderCoordinator
    @State private var storageService: StorageService
    
    init(book: Book, themeManager: ThemeManager) {
        self.book = book
        self.themeManager = themeManager
        _coordinator = State(initialValue: RenderCoordinator(book: book))
        _storageService = State(initialValue: try! StorageService())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            TopBarView(
                book: book,
                coordinator: coordinator,
                onTOCToggle: { coordinator.showTOC.toggle() },
                onSearchToggle: { coordinator.showSearch.toggle() },
                onFontToggle: { coordinator.showFontPanel.toggle() }
            )
            
            // 内容区
            HStack(spacing: 0) {
                // 目录侧栏（可选）
                if coordinator.showTOC {
                    TOCView(
                        chapters: coordinator.tocEntries,
                        onChapterSelect: { coordinator.navigateToChapter($0) }
                    )
                    .frame(width: 200)
                    .background(themeManager.currentTheme.sidebarBG)
                }
                
                // 渲染器
                Group {
                    switch book.fileType {
                    case .epub, .mobi:
                        EPUBRendererView(
                            book: book,
                            chapters: coordinator.chapters,
                            currentChapter: $coordinator.currentChapter,
                            progress: $coordinator.progress,
                            environment: themeManager
                        )
                    case .pdf:
                        PDFRendererView(
                            book: book,
                            progress: $coordinator.progress,
                            environment: themeManager
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(themeManager.currentTheme.contentBG)
            }
            
            // 底部状态栏
            BottomBarView(
                book: book,
                coordinator: coordinator
            )
        }
        .background(themeManager.currentTheme.contentBG)
        .task {
            await loadBook()
        }
    }
    
    private func loadBook() async {
        switch book.fileType {
        case .epub:
            await coordinator.loadEPUB()
        case .mobi:
            await coordinator.loadMOBI()
        case .pdf:
            break
        }
    }
}
```

- [ ] **Step 3: 创建顶部工具栏**

```swift
// Reader/Views/Toolbar/TopBarView.swift
import SwiftUI

struct TopBarView: View {
    let book: Book
    let coordinator: RenderCoordinator
    let onTOCToggle: () -> Void
    let onSearchToggle: () -> Void
    let onFontToggle: () -> Void
    
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        HStack {
            Button(action: onTOCToggle) {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.currentTheme.accent)
            
            Text(currentChapterTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(theme.currentTheme.primaryText)
            
            Spacer()
            
            HStack(spacing: 16) {
                Button(action: onSearchToggle) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                
                Button(action: addBookmark) {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.plain)
                
                Button(action: onFontToggle) {
                    Text("Aa")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(theme.currentTheme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.currentTheme.sidebarBG)
        .overlay(alignment: .bottom) {
            Divider().background(theme.currentTheme.border)
        }
    }
    
    private var currentChapterTitle: String {
        guard coordinator.currentChapter < coordinator.tocEntries.count else {
            return book.title
        }
        return coordinator.tocEntries[coordinator.currentChapter].title
    }
    
    private func addBookmark() {
        let position = "\(coordinator.currentChapter):\(coordinator.progress)"
        let chapter = coordinator.tocEntries[safe: coordinator.currentChapter]?.title
        _ = storageService.addBookmark(to: book, position: position, chapter: chapter)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

- [ ] **Step 4: 创建底部状态栏**

```swift
// Reader/Views/Toolbar/BottomBarView.swift
import SwiftUI

struct BottomBarView: View {
    let book: Book
    let coordinator: RenderCoordinator
    
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        HStack {
            Text("第 \(coordinator.currentChapter + 1)/\(coordinator.tocEntries.count) 章")
                .font(.caption)
                .foregroundStyle(theme.currentTheme.secondaryText)
            
            Spacer()
            
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.currentTheme.border)
                        .frame(height: 3)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.currentTheme.accent)
                        .frame(width: geometry.size.width * coordinator.progress, height: 3)
                }
            }
            .frame(width: 120)
            
            Spacer()
            
            Text("\(Int(coordinator.progress * 100))%")
                .font(.caption)
                .foregroundStyle(theme.currentTheme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.currentTheme.sidebarBG)
        .overlay(alignment: .top) {
            Divider().background(theme.currentTheme.border)
        }
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add Reader/Views/Reader/ReaderView.swift Reader/Views/Reader/RenderCoordinator.swift Reader/Views/Toolbar/
git commit -m "feat: 添加阅读主区域和工具栏"
```

---

## Task 10: 字体设置面板与搜索面板

**Files:**
- Create: `Reader/Views/Toolbar/FontPanelView.swift`
- Create: `Reader/Views/Toolbar/SearchPanelView.swift`

- [ ] **Step 1: 创建字体设置面板**

```swift
// Reader/Views/Toolbar/FontPanelView.swift
import SwiftUI

struct FontPanelView: View {
    @Binding var fontSize: CGFloat
    @Binding var lineHeight: CGFloat
    @Binding var selectedTheme: AppTheme
    @Environment(ThemeManager.self) private var themeManager
    
    let themes: [AppTheme] = [.classic, .kraft, .night, .eyeCare]
    let lineSpacings: [CGFloat] = [1.5, 1.8, 2.0, 2.2]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 字体大小
            VStack(alignment: .leading, spacing: 8) {
                Text("字体大小")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(themeManager.currentTheme.secondaryText)
                
                HStack {
                    Button(action: { fontSize = max(12, fontSize - 1) }) {
                        Text("A-")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    
                    Slider(value: $fontSize, in: 12...24, step: 1)
                        .tint(themeManager.currentTheme.accent)
                    
                    Button(action: { fontSize = min(24, fontSize + 1) }) {
                        Text("A+")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // 行距
            VStack(alignment: .leading, spacing: 8) {
                Text("行距")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(themeManager.currentTheme.secondaryText)
                
                HStack(spacing: 6) {
                    ForEach(lineSpacings, id: \.self) { spacing in
                        Button(action: { lineHeight = spacing }) {
                            Text(String(format: "%.1f", spacing))
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    lineHeight == spacing
                                        ? themeManager.currentTheme.accent
                                        : themeManager.currentTheme.border
                                )
                                .foregroundStyle(
                                    lineHeight == spacing
                                        ? .white
                                        : themeManager.currentTheme.primaryText
                                )
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // 主题
            VStack(alignment: .leading, spacing: 8) {
                Text("主题")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(themeManager.currentTheme.secondaryText)
                
                HStack(spacing: 10) {
                    ForEach(themes, id: \.self) { t in
                        Button(action: { 
                            selectedTheme = t
                            themeManager.setTheme(t)
                        }) {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(t.contentBG)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                selectedTheme == t
                                                    ? themeManager.currentTheme.accent
                                                    : .clear,
                                                lineWidth: 2
                                            )
                                    )
                                Text(t.name)
                                    .font(.caption2)
                                    .foregroundStyle(
                                        selectedTheme == t
                                            ? themeManager.currentTheme.primaryText
                                            : themeManager.currentTheme.secondaryText
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
```

- [ ] **Step 2: 创建搜索面板**

```swift
// Reader/Views/Toolbar/SearchPanelView.swift
import SwiftUI

struct SearchPanelView: View {
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var currentResultIndex = 0
    
    let chapters: [EPUBChapter]
    let onResultSelect: (Int, Int) -> Void  // chapterIndex, paragraphIndex
    
    @Environment(ThemeManager.self) private var theme
    
    struct SearchResult: Identifiable {
        let id = UUID()
        let chapterTitle: String
        let chapterIndex: Int
        let snippet: String
        let matchedRange: Range<String.Index>?
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.currentTheme.secondaryText)
                
                TextField("搜索...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { performSearch() }
                
                if !searchResults.isEmpty {
                    Text("\(currentResultIndex + 1)/\(searchResults.count)")
                        .font(.caption)
                        .foregroundStyle(theme.currentTheme.secondaryText)
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
            .background(theme.currentTheme.border)
            .cornerRadius(8)
            
            // 结果列表
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
                                        .foregroundStyle(theme.currentTheme.primaryText)
                                    
                                    Text(result.snippet)
                                        .font(.caption)
                                        .foregroundStyle(theme.currentTheme.secondaryText)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                            }
                            .buttonStyle(.plain)
                            
                            Divider().background(theme.currentTheme.border)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(theme.currentTheme.sidebarBG)
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        searchResults = []
        for (index, chapter) in chapters.enumerated() {
            if let range = chapter.htmlContent.range(
                of: searchText,
                options: .caseInsensitive
            ) {
                let start = chapter.htmlContent.startIndex
                let snippetStart = chapter.htmlContent.index(range.lowerBound, offsetBy: -20, constrainedBy: start) ?? start
                let snippetEnd = chapter.htmlContent.index(range.upperBound, offsetBy: 20, constrainedBy: chapter.htmlContent.endIndex) ?? chapter.htmlContent.endIndex
                
                let snippet = "..." + chapter.htmlContent[snippetStart..<snippetEnd] + "..."
                
                searchResults.append(SearchResult(
                    chapterTitle: chapter.title,
                    chapterIndex: index,
                    snippet: snippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression),
                    matchedRange: range
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
```

- [ ] **Step 3: Commit**

```bash
git add Reader/Views/Toolbar/FontPanelView.swift Reader/Views/Toolbar/SearchPanelView.swift
git commit -m "feat: 添加字体设置面板和搜索面板"
```

---

## Task 11: 高亮操作菜单

**Files:**
- Create: `Reader/Views/Components/HighlightMenuView.swift`
- Create: `Reader/Views/Components/ProgressRingView.swift`

- [ ] **Step 1: 创建高亮操作菜单**

```swift
// Reader/Views/Components/HighlightMenuView.swift
import SwiftUI

struct HighlightMenuView: View {
    let selectedText: String
    let onHighlight: (HighlightColor) -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        HStack(spacing: 4) {
            // 高亮颜色选择
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button(action: { onHighlight(color) }) {
                    Circle()
                        .fill(Color(hex: color.hex))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
            
            Divider()
                .frame(height: 20)
            
            // 操作按钮
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("复制")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(8)
        .background(.white)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}
```

- [ ] **Step 2: 创建进度条组件**

```swift
// Reader/Views/Components/ProgressRingView.swift
import SwiftUI

struct ProgressRingView: View {
    let progress: Double
    let lineWidth: CGFloat
    
    init(progress: Double, lineWidth: CGFloat = 3) {
        self.progress = progress
        self.lineWidth = lineWidth
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: "#D5C8B0"), lineWidth: lineWidth)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color(hex: "#8B7355"), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Reader/Views/Components/
git commit -m "feat: 添加高亮菜单和进度组件"
```

---

## Task 12: 集成与最终调试

- [ ] **Step 1: 验证所有视图编译**

在 Xcode 中构建项目，确保无编译错误。

- [ ] **Step 2: 测试 EPUB 导入和渲染**

导入一本 EPUB 测试书籍，验证：
- 书籍出现在书架
- 点击打开后正常渲染
- 目录可以跳转
- 进度正确显示

- [ ] **Step 3: 测试 PDF 渲染**

导入一本 PDF 测试文件，验证：
- 正常渲染显示
- 滚动/缩放正常
- 进度正确记录

- [ ] **Step 4: 测试书签和高亮**

- 添加书签，验证出现在书签列表
- 选中文字，弹出高亮菜单
- 选择颜色后高亮生效
- 添加笔记后保存成功

- [ ] **Step 5: 测试主题切换**

切换 4 种主题，验证：
- 所有视图颜色正确更新
- EPUB 内容区主题同步
- 设置持久化（重启后保留）

- [ ] **Step 6: 最终 Commit**

```bash
git add .
git commit -m "feat: 完成阅读器基础功能集成"
```
