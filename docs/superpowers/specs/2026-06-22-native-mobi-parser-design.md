# 原生 MOBI 解析器与可扩展格式架构

## 背景

当前项目（`Reader/Reader/`）加载 .mobi 书籍会一直显示"加载中"。根因：

1. `MOBIConverter.convertToEPUB()` 在 `async` 函数内同步调用 `Process.run()` + `waitUntilExit()`。`RenderCoordinator` 是 `@MainActor`，转换期间主线程被阻塞，UI 完全冻结。
2. 现方案依赖外部 `calibre` 的 `ebook-convert`，用户必须单独安装；calibre 启动 3-10s，大文件转换 30s+，体验差。
3. 现有架构 `RenderCoordinator.load()` 用 `switch book.fileType` 分派到 `loadEPUB/loadMOBI/loadPDF`，新增格式必须改核心代码；MOBI 走"转 EPUB 再解析"的绕路，没有统一的中间表示。

## 目标

- **原生解析 MOBI**：覆盖 PalmDOC LZ77 压缩 + AZW3/KF8，不依赖 calibre
- **calibre 兜底**：原生无法处理的子格式（HUFF/CDIC）回退到 calibre
- **可扩展架构**：新增格式 = 新增一个 `BookParser` 实现 + 一行注册，核心加载流程不动
- **修复主线程阻塞**：所有解析在后台 executor 执行

## 非目标

- 不实现 HUFF/CDIC 原生解码（用 calibre 兜底）
- 不改造 `EPUBWebView` / `PDFKitView` 的接口（通过临时桥接层保持兼容）
- 不新增 metadata 字段（language/publisher 等到实际需要时再加）

## 架构总览

```
┌──────────────────────────────────────────────────────┐
│  ReaderView / RenderCoordinator (UI层)               │
│     ↓ fileType                                       │
│  BookParserRegistry.parser(for:) → BookParser        │
│     ↓                                                │
│  parser.parse(fileAt:) → ParsedBook (异步, 后台)     │
│     ↓                                                │
│  按 ParsedBook.renderer 分发：                       │
│     ├── .html   → EPUBWebView (复用现有)             │
│     └── .pdfKit → PDFKitView (复用现有)              │
└──────────────────────────────────────────────────────┘

文件分布（每个 Parser 一个文件）:
  Services/Parsers/
    BookParser.swift              ← 协议 + ParsedBook 模型 + Registry
    EPUBParser.swift              ← 现有文件改造（conform 协议）
    MOBIParser.swift              ← 新（原生 + calibre 兜底）
    PDFParser.swift               ← 新（薄封装 PDFDocument）
    PalmDBReader.swift            ← 新（PalmDB + MOBI header 解析）
    MOBIDecompressor.swift        ← 新（PalmDOC LZ77 + HUFF/CDIC）
    KF8IndexReader.swift          ← 新（AZW3 章节索引解析）
```

## 统一模型 ParsedBook

```swift
struct ParsedBook {
    let title: String
    let author: String?
    let coverImage: Data?              // PNG/JPEG 原始字节，由调用方落盘

    let chapters: [ParsedChapter]      // 按阅读顺序
    let toc: [ParsedTOCEntry]          // 可为空（PDF/老 MOBI 没有 toc 时用章节列表兜底）

    let resourceDirectory: URL?        // 有外部资源（图片/CSS）时指向解压目录
    let renderer: RendererKind         // .html | .pdfKit
    let pdfDocument: PDFDocument?      // renderer == .pdfKit 时填充
}

struct ParsedChapter {
    let title: String
    let bodyHTML: String               // 纯 HTML 片段（不带 <html><body>）
    let sourcePath: String             // 用于相对资源解析
}

struct ParsedTOCEntry {
    let title: String
    let chapterIndex: Int
}

enum RendererKind {
    case html
    case pdfKit
}
```

### 关键取舍

1. **`coverImage` 用 `Data?` 而非 `URL?`**：EPUB 封面在 zip 里、MOBI 封面是 EXTH record、PDF 封面是 `page.thumbnail`。Parser 吐原始字节，调用方统一落盘到 `Covers/{uuid}.png`。
2. **`resourceDirectory` 可选**：HTML 渲染器需要（WKWebView 用 `loadFileURL`），PDF 渲染器忽略。
3. **`pdfDocument` 内联**：虽然"不纯"，但 PDF 渲染单元就是 `PDFDocument`，硬塞中间结构徒增转换。用 `renderer` 枚举 + 关联字段，避免泛型化。
4. **不含 `language`/`publisher`**：YAGNI，书库列表当前只用 title/author/cover。chapters/toc 是阅读路径必需，仍然包含。
5. **`bodyHTML` 不含 `<html><body>` 包裹**：包裹由 `EPUBScripts.wrapHTML` 做。MOBI Parser 只产 HTML 片段。

### 对现有类型的迁移

- `EPUBMetadata` → `ParsedBook`（字段一一对应）
- `EPUBChapter` → `ParsedChapter`（`htmlContent` → `bodyHTML`，`fileName` → `sourcePath`）
- `EPUBTOCEntry` → `ParsedTOCEntry`

`RenderCoordinator` 保留 `epubMetadata: EPUBMetadata?` 字段做临时桥接，避免一次性改动过多 View 层。后续可以再清理。

## MOBIParser 内部结构

```swift
final class MOBIParser: BookParser {
    func parse(fileAt url: URL) async throws -> ParsedBook {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let pdb = try PalmDBReader.read(data)
        let header = try MOBIHeader.read(record0: pdb.records[0])

        switch header.variant {
        case .classicMOBI:
            return try parseClassic(pdb: pdb, header: header)
        case .kf8:
            return try parseKF8(pdb: pdb, header: header)
        case .unsupported(let reason):
            return try await parseViaCalibre(fileAt: url, reason: reason)
        }
    }
}
```

### 子组件

**PalmDBReader**（~150 行）
- 解析 Palm Database 头：name/ctime/mtime/type/creator/lastRecordID/nextRecordID（78 字节）
- 记录索引：每条记录 (offset, length)
- 输出 `PalmDB { records: [Data] }`

**MOBIHeader**（~200 行）
- 读取 record0 前 16 字节：PalmDOC header（compression/recordCount/textLength）
- 后续 MOBI header：magic ("MOBI"/"TEXt"/"BOUNDARY")、variant（classic/KF8）、firstImageRecord、firstChapterIndex
- EXTH block → title/author/coverIndex
- 输出 `MOBIHeader { variant, compression, firstTextRecord, lastTextRecord, title, author, coverRecordIndex }`

**MOBIDecompressor**（~250 行）
- `palmDoc(_:)`：LZ77 变体，1 bit 标志位 + 8 字节窗口（~80 行）
- `huff(_:_:)`：HUFF/CDIC 压缩，两个 CDIC 表，Huffman 树解码（~150 行，仅在 fallback 不可能时使用）
- 未压缩 → 直接返回

**parseClassic**（~150 行）
1. textRecords = records[firstTextRecord ... lastTextRecord]
2. 每条记录按 compression 解压 → 拼成大 HTML 字符串
3. 按 `<mbp:pagebreak/>` 或 `<xmp>` 拆章节；没有就整本一章
4. 章节标题：toc records（若有）或第一章提取 `<title>` / `<h1>`
5. 图片资源写入临时目录 `{tmp}/ReaderMOBI/{uuid}/images/`，`resourceDirectory` 指向该目录

**parseKF8**（~300 行）
- KF8 header 在 record0 不同 offset：`firstResourceRecord`/`flowMode`
- FDST 表分段，每段对应 flow record
- KF8 index（ORDR/TOLK）给章节边界
- 解出来是 HTML 片段（KF8 内部即结构化 HTML）
- 图片资源：KFSI 表定位 image records

**parseViaCalibre**（~80 行，重构现有 MOBIConverter）
- 关键修复：用 `Task.detached(priority: .userInitiated)` 包 `Process.run/waitUntilExit`，不阻塞主 actor
- 失败时抛 `BookParseError.calibreConversionFailed(stderr:)`

## PDF 色调控制（PDFContainerView + CIFilter）

完全自研 PDF 渲染器不现实（规范 1000+ 页）。用 CIFilter 给 PDFKit 的输出叠主题色调，保留全部交互能力。

### 实现

```
PDFContainerView (新)
  ├── NSView 容器，背景色 = themeManager.currentTheme.contentBG
  └── PDFView (现有)
        ├── underPageBackgroundColor = contentBG
        └── contentFilters = [ 按主题动态切换 ]
```

**滤镜映射**

| 主题 | 滤镜 |
|---|---|
| `.classic` / `.kraft` | 无滤镜；容器背景提供暖底 |
| `.eyeCare` | 轻量 `CIColorControls(saturation: 0.85)` + 绿色 5% 叠加 |
| `.night` | `CIColorInvert` + `CIColorControls(brightness: -0.15, contrast: 1.05)` |

**接口**
- 新增 `PDFRendererView` 外层包装 `PDFContainerView`，接收 `themeManager` 订阅主题变化
- 主题切换时只重算 `contentFilters`，不重载 `PDFDocument`
- `FontPanelView` 新增"PDF 滤镜开关"（默认开），让用户对个别 PDF 关闭滤镜应对兼容问题

### 落地清单

- `Views/Reader/PDFContainerView.swift`（新，~100 行）：NSView 容器 + 滤镜管理
- 改造 `PDFRendererView`：包一层 `PDFContainerView`，传 themeManager
- `RenderCoordinator` 无需改动（输出仍是 `PDFDocument`）
- `ReaderSettings` 加 `pdfFilterEnabled: Bool`（默认 true），持久化到 UserDefaults

### 取舍

1. **保留文字选择/搜索/缩放/目录**：PDFKit 内建能力全部可用
2. **滤镜对扫描版 PDF 效果略差**：扫描页本身就是图片，反色后观感与原生 EPUB 反色类似；用户可以一键关滤镜
3. **不实现"重排/重排为 EPUB"**：PDF 重排是另一个大工程，超出本次 scope

## Registry + RenderCoordinator 改造

```swift
enum BookParserRegistry {
    static func parser(for type: FileType) -> BookParser {
        switch type {
        case .epub: return EPUBParser()
        case .mobi: return MOBIParser()
        case .pdf:  return PDFParser()
        }
    }
}

// RenderCoordinator.load() 简化：
func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
        let parser = BookParserRegistry.parser(for: book.fileType)
        let parsed = try await Task.detached(priority: .userInitiated) {
            try await parser.parse(fileAt: URL(fileURLWithPath: self.book.filePath))
        }.value
        apply(parsed)
    } catch {
        loadError = error.localizedDescription
    }
}

private func apply(_ parsed: ParsedBook) {
    switch parsed.renderer {
    case .html:
        epubMetadata = EPUBMetadata(parsed)  // 临时桥接
    case .pdfKit:
        pdfDocument = parsed.pdfDocument
        pdfPageCount = parsed.pdfDocument?.pageCount ?? 0
        if let doc = parsed.pdfDocument {
            pdfOutline = buildPDFOutline(from: doc)
        }
    }
}
```

## 错误处理 + calibre 兜底策略

```swift
enum BookParseError: Error, LocalizedError {
    case unsupportedFormat(detail: String)
    case corruptedFile(detail: String)
    case calibreNotInstalled
    case calibreConversionFailed(stderr: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let d):
            return "暂不支持的格式：\(d)"
        case .corruptedFile(let d):
            return "文件损坏：\(d)"
        case .calibreNotInstalled:
            return "原生解析不支持该 MOBI 变体，且未检测到 calibre。请安装 calibre 后重试。"
        case .calibreConversionFailed(let stderr):
            return "calibre 转换失败：\(stderr)"
        }
    }
}
```

### 兜底决策表

| 场景 | 动作 |
|---|---|
| PalmDOC 压缩 MOBI | 原生解析 |
| 未压缩 MOBI | 原生解析 |
| AZW3/KF8 | 原生解析 |
| HUFF/CDIC 压缩 | `unsupportedFormat` → calibre |
| EXTH 缺失（无 title/author） | 原生解析，title 用文件名兜底 |
| 解析中结构异常 | 抛 `corruptedFile`，不再 fallback（数据可能已损坏） |
| `MOBIParser` 决定 fallback 但 calibre 不可用 | 抛 `calibreNotInstalled`（带友好提示） |

## 测试策略

**单元测试**（新增 `ReaderTests` target）

```
ReaderTests/
  PalmDBReaderTests.swift        — 真实 PalmDB 二进制 fixture 验证 offset/length
  MOBIHeaderTests.swift          — 构造 fake record0 验证 variant 分流
  MOBIDecompressorTests.swift    — PalmDOC: 已知输入→预期输出；HUFF: fixture + 边界
  MOBIParserClassicTests.swift   — 端到端：公网样本 .mobi → ParsedBook
  MOBIParserKF8Tests.swift       — 端到端：AZW3 样本
  EPUBParserMigrationTests.swift — 旧 EPUBMetadata 输出 vs 新 ParsedBook 输出，等价性
  CalibreFallbackTests.swift     — mock MOBIConverter，验证 fallback 触发
```

**Fixtures**：`ReaderTests/Fixtures/`，每个 < 100KB
- `classic-palmDOC.mobi` — 公网样本
- `azw3-kf8.mobi` — 公网样本
- `minimal.epub` — 构造一个最小 EPUB 用于迁移测试

**验收标准（手测）**
- 打开经典 .mobi：< 500ms 出章节（calibre 路径 5-10s）
- 打开 AZW3/KF8：封面/目录正确显示
- 卸载 calibre 后打开 HUFF 压缩 .mobi：alert 提示而非卡死
- 加载失败（文件损坏）：alert 显示明确错误而非卡死

## 迁移步骤（实施计划摘要）

1. 新建 `Services/Parsers/` 目录，落 `BookParser.swift`（协议 + 模型 + Registry）
2. 实现 `PDFParser`（最简单，~50 行，验证协议形状）
3. 改造 `EPUBParser` conform 协议，保留旧 API 供桥接
4. 实现 `PalmDBReader` + `MOBIHeader` + `MOBIDecompressor`（PalmDOC 分支）
5. 实现 `MOBIParser.parseClassic` + 兜底逻辑
6. 实现 `KF8IndexReader` + `MOBIParser.parseKF8`
7. 重构 `MOBIConverter` 为异步非阻塞，集成到 `MOBIParser.parseViaCalibre`
8. 改造 `RenderCoordinator.load()` 走 Registry
9. 新增 `PDFContainerView` + 主题滤镜映射；改造 `PDFRendererView` 包一层
10. `ReaderSettings` 加 `pdfFilterEnabled`，`FontPanelView` 加开关
11. 新增 `ReaderTests` target，补单测
12. 手测验收 + 清理旧的 `loadEPUB/loadMOBI/loadPDF` 方法

详细步骤与验收门槛见后续实施计划（writing-plans）。
