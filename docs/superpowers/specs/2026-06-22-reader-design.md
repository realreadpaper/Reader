# Reader — macOS 原生阅读器设计文档

> 日期：2026-06-22  
> 状态：设计完成，待实现

## 1. 概述

开发一款 macOS 原生电子书阅读器，支持 EPUB、MOBI、PDF 三种格式。界面采用温暖纸质风格（复古牛皮纸配色），布局为侧边栏 + 阅读区，操作简洁直觉。

## 2. 核心需求

### 2.1 目标用户

需要在 Mac 上阅读小说和混合类型书籍（技术文档、文学作品等）的用户，追求简洁美观的阅读体验。

### 2.2 功能清单

| 功能 | 优先级 | 说明 |
|------|--------|------|
| 书架管理 | P0 | 导入书籍、分类整理、按标签/分组管理 |
| EPUB 渲染 | P0 | 解析 EPUB 并渲染为可读内容 |
| MOBI 渲染 | P0 | 导入时预转换为 EPUB，复用 EPUB 渲染管线 |
| PDF 渲染 | P0 | 原生 PDFKit 渲染 |
| 书签 | P0 | 记录阅读位置，快速跳回 |
| 高亮/标注 | P0 | 选中文字进行 4 色高亮，支持添加笔记 |
| 全文搜索 | P0 | 在书中搜索关键词，跳转到对应位置 |
| 目录导航 | P0 | 通过目录快速跳转章节 |
| 字体/排版自定义 | P0 | 字体大小、行距、背景色、暗黑模式 |
| 阅读进度 | P0 | 自动记录，下次打开恢复进度 |

## 3. 技术架构

### 3.1 技术栈

- **SwiftUI** — 界面构建
- **WKWebView** — EPUB/MOBI 渲染（注入自定义 CSS 控制排版）
- **PDFKit** — PDF 渲染
- **SwiftData** — 数据持久化（书签、标注、阅读进度）
- **Combine** — 状态管理

### 3.2 模块划分

| 模块 | 职责 | 关键依赖 |
|------|------|----------|
| `ReaderApp` | 应用入口、全局状态 | SwiftUI |
| `Library` | 书架管理、文件导入、元数据提取 | SwiftData, FilePicker |
| `Renderer` | 统一渲染接口，分发 EPUB/MOBI/PDF | WKWebView, PDFKit |
| `Sidebar` | 侧边栏（书架 + 目录 + 标注列表） | SwiftUI |
| `ReaderView` | 阅读主区域、翻页、滚动 | Renderer |
| `Toolbar` | 顶部/底部工具栏、字体设置面板 | SwiftUI |
| `Storage` | 书签、标注、阅读进度持久化 | SwiftData |

### 3.3 数据流

```
Library → 选择书籍 → Renderer 渲染 → ReaderView 显示 → 用户交互 → Storage 持久化
```

### 3.4 目标平台

- macOS 14.0+（Sonoma 及以上，使用 SwiftData 做数据持久化）
- Apple Silicon & Intel
- 若需支持 macOS 12-13，需将 SwiftData 降级为 Core Data（不在当前范围内）

## 4. 界面设计

### 4.1 整体布局

```
┌──────────────────────────────────────────────────────────┐
│ ┌──────────┐ ┌──────────────────────────────────────────┐ │
│ │  书架    │ │  顶部工具栏: ◀ 目录 | 章节标题 | 🔍🔖Aa⋯ │ │
│ │ ┌──────┐ │ ├──────────────────────────────────────────┤ │
│ │ │ 全部 │ │ │                                          │ │
│ │ │ 最近 │ │ │         正文阅读区                        │ │
│ │ │ 收藏 │ │ │         (居中 560px 最大宽度)             │ │
│ │ └──────┘ │ │         行距 2.1, 首行缩进               │ │
│ │          │ │                                          │ │
│ │ 书籍列表 │ │                                          │ │
│ │ - 封面   │ ├──────────────────────────────────────────┤ │
│ │ - 书名   │ │  底部状态栏: 第2/15章 ===42%=== 42%      │ │
│ │ - 进度   │ └──────────────────────────────────────────┘ │
│ └──────────┘                                              │
└──────────────────────────────────────────────────────────┘
```

### 4.2 侧边栏（220px 宽）

- **顶部**：书架标题 + "全部/最近/收藏" 分段切换
- **中部**：书籍列表，每项包含封面缩略图（36×48）+ 书名 + 阅读进度
- **底部**：设置 + 导入选项

### 4.3 阅读区

- **顶部工具栏**：目录返回按钮 + 章节标题 + 搜索/书签/字体/更多图标
- **正文区**：牛皮纸背景，最大宽度 560px 居中，行距 2.1，首行缩进 2em
- **底部状态栏**：当前章节 + 进度条 + 百分比

### 4.4 配色方案

| 元素 | 色值 | 说明 |
|------|------|------|
| 正文背景 | #F5EFE3 | 主阅读区背景 |
| 侧边栏背景 | #E8DCC8 | 侧边栏底色 |
| 选中项背景 | #DDD0B8 | 侧边栏选中项 |
| 侧边栏边框 | #D5C8B0 | 分割线 |
| 主文字 | #2E2518 | 标题、正文 |
| 次要文字 | #3A3025 | 正文段落 |
| 辅助文字 | #8A7A60 | 图标、进度、提示 |
| 强调色 | #8B7355 | 按钮、选中态、进度条 |
| 高亮黄 | #E8D5A0 | 文字高亮 |

### 4.5 主题模式

| 主题 | 背景 | 侧边栏 | 文字 | 说明 |
|------|------|--------|------|------|
| 经典米白 | #FAF6EF | #F0E8DE | #3A3025 | 浅色默认 |
| 复古牛皮纸 | #F5EFE3 | #E8DCC8 | #2E2518 | 温暖护眼（推荐） |
| 夜间模式 | #1E1A15 | #15120F | #D5C8B0 | 深色主题 |
| 护眼绿 | #D5E8D0 | #C5D8C0 | #2A3528 | 柔和绿色调 |

## 5. 交互设计

### 5.1 翻页方式

支持两种模式，用户可在设置中切换：

- **连续滚动**（默认）：像网页一样上下滚动，支持触控板手势，PDF 保持原生滚动
- **仿真翻页**：左右键/手势触发翻页动画，PDF 天然分页，EPUB 按屏幕高度分页

### 5.2 高亮/标注流程

```
选中文字 → 弹出操作栏
├── 4 色高亮（黄/绿/橙/蓝）
├── 添加笔记（弹出文本输入框）
├── 复制文字
└── 删除标注
```

侧边栏可切换到「标注」标签页，显示当前书籍所有高亮和笔记，按章节分组，点击跳转。

### 5.3 搜索交互

- 快捷键 `⌘F` 打开搜索栏
- 实时搜索，显示匹配结果列表（按章节分组）
- 每条结果显示：章节名 + 页码 + 匹配片段（关键词高亮）
- 支持 `▲▼` 上下跳转

### 5.4 字体/排版设置面板

- **字体大小**：滑块调节，`A-` / `A+` 按钮
- **行距**：预设选项 1.5 / 1.8 / 2.0 / 2.2
- **主题**：4 种主题切换（经典/牛皮纸/夜间/护眼）
- **字体**：系统默认 / 宋体 / 苹方

### 5.5 键盘快捷键

| 操作 | 快捷键 |
|------|--------|
| 打开文件 | ⌘ O |
| 全文搜索 | ⌘ F |
| 添加书签 | ⌘ D |
| 字体设置 | ⌘ T |
| 切换侧边栏 | ⌘ ⇧ S |
| 全屏阅读 | ⌘ ⏏ |
| 放大字体 | ⌘ + |
| 缩小字体 | ⌘ - |

## 6. 数据模型

### 6.1 Book

```swift
@Model
class Book {
    var id: UUID
    var title: String
    var author: String?
    var coverPath: String?
    var filePath: String
    var fileType: FileType  // .epub, .mobi, .pdf
    var lastRead: Date?
    var progress: Double    // 0.0 - 1.0
    var isFavorite: Bool
    var addedAt: Date
    
    @Relationship(deleteRule: .cascade)
    var bookmarks: [Bookmark]
    
    @Relationship(deleteRule: .cascade)
    var highlights: [Highlight]
}
```

### 6.2 Bookmark

```swift
@Model
class Bookmark {
    var id: UUID
    var book: Book?
    var position: String    // 格式: "chapterIndex:paragraphOffset" 或 CSS 选择器路径
    var chapter: String?
    var note: String?
    var createdAt: Date
}
```

### 6.3 Highlight

```swift
@Model
class Highlight {
    var id: UUID
    var book: Book?
    var selectedText: String
    var color: HighlightColor  // .yellow, .green, .orange, .blue
    var startOffset: Int
    var endOffset: Int
    var chapter: String?
    var note: String?
    var createdAt: Date
}
```

## 7. 文件格式处理

### 7.1 EPUB

- **解析**：ZIP 解压 → 解析 content.opf 获取章节列表 → 逐章读取 XHTML
- **渲染**：WKWebView 加载 HTML，注入自定义 CSS 控制字体、行距、主题
- **交互**：JavaScript Bridge 处理选中文字、翻页、目录跳转

### 7.2 MOBI

- **导入时**：调用命令行工具 calibre/ebook-convert 转为 EPUB
- **存储**：转换后的 EPUB 保存到 App 沙盒，原文件保留但标记为"已转换"
- **优势**：避免运行时解析 MOBI 的复杂性，复用 EPUB 渲染管线

### 7.3 PDF

- **渲染**：PDFView 原生渲染，支持缩放、滚动
- **搜索**：PDFDocument.findString() 原生全文搜索
- **高亮**：PDFAnnotation 添加文字标注
- **限制**：纯图片 PDF 无法选择文字（与原生 Preview 行为一致）

## 8. 项目结构

```
Reader/
├── ReaderApp.swift              # 应用入口
├── Models/
│   ├── Book.swift               # 书籍模型
│   ├── Bookmark.swift           # 书签模型
│   └── Highlight.swift          # 标注模型
├── Views/
│   ├── Sidebar/
│   │   ├── SidebarView.swift    # 侧边栏容器
│   │   ├── BookListView.swift   # 书架列表
│   │   ├── TOCView.swift        # 目录视图
│   │   └── AnnotationView.swift # 标注列表
│   ├── Reader/
│   │   ├── ReaderView.swift     # 阅读主区域
│   │   ├── EPUBRenderer.swift   # EPUB 渲染
│   │   ├── PDFRenderer.swift    # PDF 渲染
│   │   └── MOBIRenderer.swift   # MOBI 渲染
│   ├── Toolbar/
│   │   ├── TopBar.swift         # 顶部工具栏
│   │   ├── BottomBar.swift      # 底部状态栏
│   │   ├── FontPanel.swift      # 字体设置面板
│   │   └── SearchPanel.swift    # 搜索面板
│   └── Components/
│       ├── HighlightMenu.swift  # 高亮操作菜单
│       └── ProgressView.swift   # 进度条组件
├── Services/
│   ├── EPUBParser.swift         # EPUB 解析
│   ├── MOBIConverter.swift      # MOBI 转换
│   └── StorageService.swift     # 数据持久化
├── Resources/
│   ├── Fonts/                   # 内置字体
│   └── Styles/                  # CSS 样式模板
└── Assets.xcassets/             # 图标资源
```

## 9. 风险与注意事项

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| MOBI 格式解析复杂 | 导入失败 | 使用 calibre 预转换，提供错误提示 |
| WKWebView 内存占用 | 大文件卡顿 | 按章节懒加载，限制同时加载章节 |
| PDF 纯图片无法选字 | 搜索/高亮失效 | 与 Preview 行为一致，不做额外处理 |
| SwiftData 兼容性 | 低版本 macOS 不支持 | 最低支持 macOS 12，SwiftData 需 macOS 14+，使用 Core Data 作为降级方案 |
