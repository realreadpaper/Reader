# Reader

Reader 是一个面向 macOS 的本地电子书阅读器，使用 SwiftUI、SwiftData、PDFKit 和 WebKit 构建。项目目标是提供一个安静、接近纸质书的阅读界面，同时覆盖常见电子书格式的导入、分页阅读、目录、搜索、书签、标注和阅读进度记录。

当前项目支持单独发布 Apple Silicon（M 系列芯片）和 Intel 芯片版本，也可以按需构建 Universal 版本。

## 功能特性

- 书架管理：导入图书、最近阅读、收藏、删除、搜索筛选。
- 多格式阅读：支持 EPUB、MOBI、PDF、TXT、Markdown。
- 分页阅读：EPUB、MOBI、TXT、Markdown 使用统一分页体验；PDF 使用 PDFKit 原生页。
- 目录导航：支持内嵌目录栏，切换目录时保持阅读器主体区域稳定。
- 内容搜索：支持输入后自动搜索，并可跳转到匹配位置。
- 阅读进度：保存每本书的阅读进度和最近打开时间。
- 书签与标注：支持添加书签、文本高亮、查看和删除记录。
- 阅读设置：支持字体大小、行高、滚动/翻页模式、PDF 显示滤镜。
- 主题：经典、牛皮纸、夜间、护眼。
- 解析缓存：非 PDF 图书会缓存解析结果，避免每次打开重复解析。
- 本地优先：图书文件、缓存和阅读数据保存在本机，不依赖云服务。

## 支持格式

| 格式 | 扩展名 | 渲染方式 | 说明 |
| --- | --- | --- | --- |
| EPUB | `.epub` | HTML/WebKit 分页 | 支持章节解析、目录、搜索、分页 |
| MOBI | `.mobi` | HTML/WebKit 分页 | 内置 MOBI 解析；遇到不支持变体时可使用 calibre 兜底 |
| PDF | `.pdf` | PDFKit | 使用 PDF 原生页面、搜索和选择能力 |
| TXT | `.txt` | 文本分页 | 自动分页、支持搜索和阅读进度 |
| Markdown | `.md`, `.markdown` | Markdown/HTML 分页 | 按文档内容分页，不按章节拆分 |

## 系统要求

- macOS 14.0 或更高版本
- Xcode 15.4 或更高版本
- Swift 5.9
- 可选：calibre，用于部分 MOBI 变体的转换兜底

安装 calibre 后建议确认命令行工具可用：

```bash
which ebook-convert
```

如果命令不存在，可在 calibre 中启用命令行工具，或将 calibre 的命令路径加入 `PATH`。

## 安装使用

从 GitHub Releases 下载对应芯片版本：

- Apple Silicon：`Reader-1.0.0-arm64.dmg`，适用于 M1、M2、M3、M4 及后续 M 系列芯片。
- Intel：`Reader-1.0.0-x86_64.dmg`，适用于 Intel Mac。
- Universal：`Reader-1.0.0-universal.dmg`，同时包含 Apple Silicon 和 Intel 架构，体积更大。

安装步骤：

1. 下载对应 `.dmg` 文件。
2. 打开 `.dmg`。
3. 将 `Reader.app` 拖入 `/Applications`。
4. 从“应用程序”启动 Reader。

如果下载的是未签名或未公证版本，macOS 可能会拦截启动。可以右键点击 `Reader.app` 后选择“打开”。开发测试环境下也可以移除隔离属性：

```bash
xattr -dr com.apple.quarantine /Applications/Reader.app
```

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `Command + O` | 导入图书 |
| `Shift + Command + S` | 展开或折叠书架 |
| `Command + \` | 打开或关闭目录 |
| `Command + F` | 打开搜索 |
| `Command + D` | 添加书签 |
| `Command + T` | 打开字体设置 |
| `Command + +` | 放大字体 |
| `Command + -` | 缩小字体 |

## 从源码运行

克隆仓库后进入项目目录：

```bash
cd /path/to/reader
```

使用 Xcode 打开：

```bash
open Reader.xcodeproj
```

在 Xcode 中选择 `Reader` scheme，然后运行 macOS 目标。

也可以使用命令行构建：

```bash
xcodebuild \
  -project Reader.xcodeproj \
  -scheme Reader \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

运行测试：

```bash
xcodebuild \
  -project Reader.xcodeproj \
  -scheme Reader \
  -destination 'platform=macOS' \
  test
```

项目中保留了 `project.yml`，如果需要根据配置重新生成 Xcode 工程，可先安装 XcodeGen，然后执行：

```bash
xcodegen generate
```

## 项目结构

```text
.
├── Reader.xcodeproj              # Xcode 工程
├── project.yml                   # XcodeGen 配置
├── Reader
│   ├── Assets.xcassets           # App 图标和颜色资源
│   └── Reader
│       ├── Models                # SwiftData 模型：Book、Bookmark、Highlight
│       ├── Services              # 书库、存储、主题、设置、解析缓存
│       ├── Services/Parsers      # PDF、TXT、MD、MOBI 等解析器
│       ├── Views                 # SwiftUI 页面和组件
│       └── ReaderApp.swift       # App 入口
├── ReaderTests                   # 单元测试
└── docs                          # 设计文档和开发计划
```

核心模块：

- `BookLibrary`：负责导入、复制和删除图书文件。
- `StorageService`：负责 SwiftData 数据读写。
- `BookParserRegistry`：按文件类型选择解析器，并管理解析缓存。
- `BookParseCache`：缓存非 PDF 图书解析结果。
- `RenderCoordinator`：协调阅读器加载、进度、目录、搜索和跳转。
- `EPUBRendererView`、`PDFRendererView`、`TXTRendererView`、`MDRendererView`：不同格式的阅读渲染入口。

## 本地数据位置

Reader 会把导入后的图书复制到应用支持目录，并使用 SwiftData 保存书架、进度、收藏、书签和标注。

常见路径：

```text
~/Library/Application Support/Books
~/Library/Application Support/ParseCache
```

SwiftData 的实际存储文件由系统管理，通常位于应用容器或应用支持目录下。删除应用不一定会自动删除这些数据；如果需要彻底清理，可在备份后手动清理相关应用数据。

## 隐私说明

- Reader 默认在本地解析图书文件。
- 图书内容、阅读进度、书签和标注不会主动上传。
- 如果安装并使用 calibre 作为 MOBI 兜底转换工具，转换过程仍在本机执行。
- 项目当前没有内置统计、登录或云同步逻辑。

## 常见问题

### 为什么打开 MOBI 失败？

MOBI 存在多种历史格式和变体。Reader 内置了原生 MOBI 解析逻辑；如果遇到暂不支持的变体，会提示安装 calibre。安装 calibre 后，Reader 可以通过 `ebook-convert` 做转换兜底。

### 为什么第一次打开 EPUB 或 MOBI 比较慢？

第一次打开需要解包、解析目录、处理 HTML 内容并计算分页。解析结果会进入 `BookParseCache`，下次打开同一本文件通常不需要重新完整解析。

### 为什么 PDF 和 EPUB 的分页方式不同？

PDF 自带固定页面，Reader 直接使用 PDFKit 的原生页码。EPUB、MOBI、TXT 和 Markdown 是流式内容，需要根据窗口宽度、字体、行高和主题重新分页。

### 为什么修改字体后页数变化？

流式文本的页数取决于版心宽度、字体大小和行高。调整这些设置会导致重新分页，这是正常行为。

### 为什么未签名版本打不开？

macOS Gatekeeper 会限制未签名或未公证的应用。发布公开版本时建议使用 Developer ID 签名并提交公证。

## 开发检查清单

发布前建议至少执行：

```bash
xcodebuild \
  -project Reader.xcodeproj \
  -scheme Reader \
  -destination 'platform=macOS' \
  test

xcodebuild \
  -project Reader.xcodeproj \
  -scheme Reader \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build
```

也建议手动验证：

- EPUB：目录、翻页、搜索、书签、标注、关闭后恢复进度。
- MOBI：中文编码、完整页数、目录、缓存复用。
- PDF：打开多本 PDF、搜索、翻页、页面闪烁情况。
- TXT：分页、搜索、进度恢复。
- Markdown：长文档分页、代码块、标题、列表展示。
- 书架：导入、删除、收藏、折叠/展开、切换图书。
- 主题：经典、牛皮纸、夜间、护眼的文字可读性。

## Roadmap

- 更稳定的 MOBI/KF8 解析覆盖。
- 更精确的 EPUB CFI 或位置锚点恢复。
- 标注编辑和导出。
- 阅读数据备份与恢复。
- 自动化 Release 脚本。
- GitHub Actions 构建和上传产物。
- 已签名和已公证的正式安装包。

## License

[MIT](LICENSE)
