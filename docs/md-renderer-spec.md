# Markdown 渲染器改进方案

## 参考项目

[swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) (3.8k stars)
- 使用 `cmark-gfm` 解析 Markdown 为 AST
- 支持完整 GFM 规范（表格、任务列表、删除线、自动链接等）

## 当前问题

`MDRendererView.swift` 中的 `markdownToHTML()` 使用手写正则表达式做转换，存在以下问题：

1. **不支持标题语法** — `# H1`、`## H2` 等无法识别
2. **不支持表格** — GFM 表格语法完全忽略
3. **不支持图片** — `![alt](url)` 无法渲染
4. **不支持删除线** — `~~text~~` 无法识别
5. **不支持任务列表** — `- [x] done` 无法识别
6. **不支持嵌套列表** — 多级列表扁平化
7. **不支持 HTML 实体** — `&amp;` 等处理不正确
8. **正则匹配顺序问题** — 代码块内的格式化符号会被错误转换
9. **段落检测粗糙** — 双换行分割，无法处理复杂结构

## 改进方案

### 核心思路

引入 `swift-cmark` 库（Apple 官方维护的 CommonMark/GFM 解析器），在 `MDParser` 层将 Markdown 解析为规范 HTML，然后复用现有 WKWebView 渲染管线。

### 架构变更

```
当前:  .md 文件 → 原始字符串 → 正则转HTML → WKWebView
改进:  .md 文件 → cmark-gfm 解析 → 规范HTML → WKWebView
```

### 需要修改的文件

| 文件 | 变更内容 |
|------|---------|
| `Package.swift` / SPM 依赖 | 添加 `swift-cmark` 依赖 |
| `MDParser.swift` | 使用 cmark 将 markdown 解析为 HTML |
| `MDRendererView.swift` | 移除 `markdownToHTML()` 正则逻辑，直接使用解析后的 HTML |

## 待实现功能清单

### P0 — 必须实现（核心 Markdown 语法）

| # | 功能 | 语法示例 | 当前状态 |
|---|------|---------|---------|
| 1 | 标题 | `# H1` ~ `###### H6` | 不支持 |
| 2 | 段落 | 空行分隔的文本块 | 部分支持（正则粗糙） |
| 3 | 粗体 | `**bold**` 或 `__bold__` | 支持 |
| 4 | 斜体 | `*italic*` 或 `_italic_` | 支持 |
| 5 | 行内代码 | `` `code` `` | 支持 |
| 6 | 代码块 | ` ```lang ... ``` ` | 支持（无语法高亮） |
| 7 | 链接 | `[text](url)` | 支持 |
| 8 | 图片 | `![alt](url)` | 不支持 |
| 9 | 引用块 | `> quote` | 部分支持（不支持嵌套） |
| 10 | 无序列表 | `- item` | 部分支持（不支持嵌套） |
| 11 | 有序列表 | `1. item` | 部分支持（不支持嵌套） |
| 12 | 分割线 | `---` | 支持 |

### P1 — 应该实现（GFM 扩展语法）

| # | 功能 | 语法示例 | 当前状态 |
|---|------|---------|---------|
| 13 | 表格 | `\| a \| b \|` | 不支持 |
| 14 | 任务列表 | `- [x] done` | 不支持 |
| 15 | 删除线 | `~~text~~` | 不支持 |
| 16 | 自动链接 | `<https://example.com>` | 不支持 |
| 17 | 嵌套列表 | 多级缩进列表 | 不支持 |

### P2 — 可选增强

| # | 功能 | 说明 |
|---|------|------|
| 18 | HTML 块 | 直接嵌入 HTML 标签 |
| 19 | 软换行/硬换行 | 行尾双空格或 `\` 强制换行 |
| 20 | 代码块语法高亮 | 根据语言高亮代码 |

## 实现步骤

### Step 1: 添加 cmark 依赖

在项目的 SPM 依赖中添加 `swift-cmark`：

```swift
.package(url: "https://github.com/swiftlang/swift-cmark", from: "0.4.0")
```

### Step 2: 新建 MarkdownParser

创建 `Services/Parsers/MarkdownRenderer.swift`，封装 cmark 解析逻辑：

```swift
import cmark_gfm
import cmark_gfm_extensions

struct MarkdownRenderer {
    static func renderHTML(_ markdown: String) -> String {
        // 1. 注册 GFM 扩展（autolink, strikethrough, tagfilter, tasklist, table）
        // 2. 创建 cmark_parser
        // 3. feed markdown 内容
        // 4. 调用 cmark_render_html 输出 HTML
    }
}
```

### Step 3: 修改 MDParser

```swift
// 修改前:
let content = try String(contentsOf: url, encoding: .utf8)
let chapters = [ParsedChapter(title: title, bodyHTML: content, ...)]

// 修改后:
let content = try String(contentsOf: url, encoding: .utf8)
let html = MarkdownRenderer.renderHTML(content)
let chapters = [ParsedChapter(title: title, bodyHTML: html, ...)]
```

### Step 4: 简化 MDRendererView

移除 `markdownToHTML()` 方法，`MDPreviewView.updateNSView` 直接使用已解析的 HTML：

```swift
func updateNSView(_ webView: WKWebView, context: Context) {
    context.coordinator.parent = self
    let fullHTML = wrapHTML(content, theme: theme)  // content 已是 HTML
    webView.loadHTMLString(fullHTML, baseURL: nil)
}
```

### Step 5: 完善 CSS 样式

为新增的 HTML 元素补充 CSS：

- `table`, `th`, `td` — 表格样式
- `input[type="checkbox"]` — 任务列表样式
- `del` — 删除线样式
- `img` — 图片样式（max-width, 居中）
- 嵌套 `blockquote` / `ul` / `ol` — 递归样式

## 不在范围内

以下功能暂不实现，保持现有架构：

- **原生 SwiftUI 渲染**（替换 WKWebView）— 改动过大，且 WKWebView 方案已稳定
- **WYSIWYG 编辑**— 当前分栏编辑/预览模式已满足需求
- **实时增量解析**— cmark 解析速度足够快，全量解析无需优化

## 预期效果

改进后，一个典型的 Markdown 文件将从：

```
# Hello World
This is **bold** and *italic*.

| Name | Age |
|------|-----|
| Alice | 30 |

- [x] Task 1
- [ ] Task 2
```

正确渲染为包含标题、粗斜体、GFM 表格、任务列表的完整 HTML，而非当前的纯文本混排。
