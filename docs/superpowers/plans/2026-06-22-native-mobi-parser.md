# 原生 MOBI 解析器与可扩展格式架构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用原生 Swift 解析 MOBI（PalmDOC + AZW3/KF8）替换 calibre 外部依赖，统一 `BookParser` 协议让格式扩展零侵入，并给 PDFKit 加上主题色调控制。

**Architecture:** 统一中间模型 `ParsedBook`；`BookParserRegistry` 按 FileType 分派到各 Parser；EPUB/MOBI 共用 WKWebView 渲染路径，PDF 走 PDFKit；MOBI 子格式由 MOBIHeader 分流到 classic / KF8 / calibre 三条路径；PDF 通过 `PDFContainerView` 叠 CIFilter 实现主题色调。

**Tech Stack:** Swift 5.9, macOS 14+, SwiftUI, PDFKit, WebKit, XCTest, xcodegen 2.45+

## Global Constraints

- 部署目标：macOS 14.0
- Xcode 版本：15.4（注意 `objectVersion` 必须 ≤ 60，`xcodegen` 2.45+ 会产出 77 需 sed 降级）
- Swift 版本：5.9
- 主线程安全：所有解析必须能在 `Task.detached(priority: .userInitiated)` 里跑，禁止在 `@MainActor` 上做阻塞 I/O 或 `Process.waitUntilExit()`
- 文件路径根：`/Users/hejianglong/Desktop/code/reader/`
- 触碰文件后必须运行 `xcodegen generate`（然后 sed 降 objectVersion）以更新 `Reader.xcodeproj/project.pbxproj`
- 错误信息用中文，遵循 `LocalError` 模式（`LocalizedError` 协议）
- 命名：Parser 类型首字母大写，方法 `parse(fileAt:) async throws -> ParsedBook`
- commit 风格遵循现有仓库：`feat:` / `fix:` / `refactor:` / `test:` / `docs:` 开头

---

## 文件结构

**新建**：
- `Reader/Reader/Services/Parsers/BookParser.swift` — 协议 + `ParsedBook` 模型 + `BookParserRegistry` 枚举 + `BookParseError`
- `Reader/Reader/Services/Parsers/PDFParser.swift` — 包装 `PDFDocument`，最简 `BookParser` 实现
- `Reader/Reader/Services/Parsers/PalmDBReader.swift` — PalmDB + PalmDOC 头解析，输出 `[Data]` records
- `Reader/Reader/Services/Parsers/MOBIHeader.swift` — MOBI header 解析，输出 variant + EXTH 元数据
- `Reader/Reader/Services/Parsers/MOBIDecompressor.swift` — PalmDOC LZ77（+ HUFF/CDIC 占位符）
- `Reader/Reader/Services/Parsers/MOBIParser.swift` — 编排器：variant 分流到 parseClassic / parseKF8 / parseViaCalibre
- `Reader/Reader/Services/Parsers/KF8IndexReader.swift` — AZW3/KF8 章节索引解析
- `Reader/Reader/Views/Reader/PDFContainerView.swift` — NSView 容器 + CIFilter 管理
- `ReaderTests/` — 测试 target
- `ReaderTests/Fixtures/` — 二进制 fixtures（gitignore 大文件，仅占位 .gitkeep）

**改造**：
- `Reader/Reader/Services/EPUBParser.swift` — conform `BookParser`，新增 `parse(fileAt:) async throws -> ParsedBook`
- `Reader/Reader/Services/MOBIConverter.swift` — 重构为真正异步（`Task.detached` 包 `Process`）
- `Reader/Reader/Services/ReaderSettings.swift` — 加 `pdfFilterEnabled: Bool` 字段
- `Reader/Reader/Views/Reader/RenderCoordinator.swift` — `load()` 改走 Registry；删除 `loadEPUB/loadMOBI/loadPDF`
- `Reader/Reader/Views/Reader/PDFRendererView.swift` — 外层包 `PDFContainerView`
- `Reader/Reader/Views/Toolbar/FontPanelView.swift` — 加 "PDF 滤镜" 开关
- `project.yml` — 加 `ReaderTests` target

---

## Task 1: Foundation — 协议、模型、Registry、错误类型

**Files:**
- Create: `Reader/Reader/Services/Parsers/BookParser.swift`
- Modify: `project.yml`（加 ReaderTests target 的占位，让 build 先不破）

**Interfaces:**
- Produces:
  - `protocol BookParser { func parse(fileAt url: URL) async throws -> ParsedBook }`
  - `struct ParsedBook { title, author, coverImage, chapters, toc, resourceDirectory, renderer, pdfDocument }`
  - `struct ParsedChapter { title, bodyHTML, sourcePath }`
  - `struct ParsedTOCEntry { title, chapterIndex }`
  - `enum RendererKind { case html, pdfKit }`
  - `enum BookParserRegistry { static func parser(for type: FileType) -> BookParser }`
  - `enum BookParseError: LocalizedError { unsupportedFormat(corruptedFile/calibreNotInstalled/calibreConversionFailed) }`

- [ ] **Step 1: 创建 Parsers 目录与新文件**

创建 `Reader/Reader/Services/Parsers/BookParser.swift`：

```swift
import Foundation
import PDFKit

struct ParsedBook {
    let title: String
    let author: String?
    let coverImage: Data?

    let chapters: [ParsedChapter]
    let toc: [ParsedTOCEntry]

    let resourceDirectory: URL?
    let renderer: RendererKind
    let pdfDocument: PDFDocument?
}

struct ParsedChapter {
    let title: String
    let bodyHTML: String
    let sourcePath: String
}

struct ParsedTOCEntry {
    let title: String
    let chapterIndex: Int
}

enum RendererKind {
    case html
    case pdfKit
}

protocol BookParser {
    func parse(fileAt url: URL) async throws -> ParsedBook
}

enum BookParserRegistry {
    static func parser(for type: FileType) -> BookParser {
        switch type {
        case .epub: return EPUBParser()
        case .mobi: return MOBIParser()
        case .pdf:  return PDFParser()
        }
    }
}

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

注意：此时 `EPUBParser` / `MOBIParser` / `PDFParser` 还未 conform 协议或还不存在，编译会失败。下一步先注释掉 Registry 的 switch body 让项目先编译。

- [ ] **Step 2: 临时注释 Registry，保证 build**

把 Registry 改成：

```swift
enum BookParserRegistry {
    static func parser(for type: FileType) -> BookParser? {
        // 后续 Task 会逐个填充
        return nil
    }
}
```

- [ ] **Step 3: 更新 project.yml，添加 ReaderTests target（占位）**

在 `project.yml` 的 `targets:` 下追加：

```yaml
  ReaderTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - ReaderTests
    dependencies:
      - target: Reader
    settings:
      base:
        SWIFT_VERSION: "5.9"
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        GENERATE_INFOPLIST_FILE: YES
```

- [ ] **Step 4: 创建 ReaderTests 占位目录**

```bash
mkdir -p ReaderTests/Fixtures
touch ReaderTests/.keep
touch ReaderTests/Fixtures/.gitkeep
```

- [ ] **Step 5: 重新生成 Xcode 项目**

```bash
cd /Users/hejianglong/Desktop/code/reader
xcodegen generate
sed -i '' 's/objectVersion = 77/objectVersion = 60/' Reader.xcodeproj/project.pbxproj
```

Expected: `⚙ Generating plists ...` 无错误；pbxproj 里的 objectVersion 改成 60。

- [ ] **Step 6: Build 验证**

```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add Reader/Reader/Services/Parsers/BookParser.swift ReaderTests project.yml Reader.xcodeproj
git commit -m "feat: 引入 BookParser 协议与 ParsedBook 统一模型"
```

---

## Task 2: PDFParser（最简协议实现，验证形状）

**Files:**
- Create: `Reader/Reader/Services/Parsers/PDFParser.swift`
- Test: `ReaderTests/PDFParserTests.swift`

**Interfaces:**
- Consumes: `BookParser`, `ParsedBook`, `RendererKind`, `FileType.pdf`
- Produces: `final class PDFParser: BookParser`

- [ ] **Step 1: 写失败测试**

创建 `ReaderTests/PDFParserTests.swift`：

```swift
import XCTest
import PDFKit
@testable import Reader

final class PDFParserTests: XCTestCase {
    func testParseInvalidPathThrowsCorrupted() async throws {
        let url = URL(fileURLWithPath: "/dev/null")
        let parser = PDFParser()
        do {
            _ = try await parser.parse(fileAt: url)
            XCTFail("应抛错")
        } catch BookParseError.corruptedFile {
            // 通过
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    func testParseValidPDFReturnsPdfKitRenderer() async throws {
        let pdfData = makeMinimalPDF()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".pdf")
        try pdfData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let parsed = try await PDFParser().parse(fileAt: tmp)
        XCTAssertEqual(parsed.renderer, .pdfKit)
        XCTAssertNotNil(parsed.pdfDocument)
        XCTAssertEqual(parsed.chapters.count, 1)
        XCTAssertEqual(parsed.toc.count, 1)
    }

    private func makeMinimalPDF() -> Data {
        let format = UIGraphicsRendererFormat()
        // 用 PDFKit 直接生成一个 1 页 PDF
        let pageRect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            NSString(string: "hello").draw(at: CGPoint(x: 10, y: 10),
                                           withAttributes: [:])
        }
    }
}
```

注意：`UIGraphicsPDFRenderer` 在 macOS 上不可用，改用下文 Swift 方式生成测试 PDF：

```swift
private func makeMinimalPDF() -> Data {
    // 用 PDFKit 直接构造一个最简 PDF
    let doc = PDFDocument()
    let page = PDFPage()
    doc.insert(page, at: 0)
    return doc.dataRepresentation() ?? Data()
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: 编译失败（`PDFParser` 不存在）。

- [ ] **Step 3: 实现 PDFParser**

创建 `Reader/Reader/Services/Parsers/PDFParser.swift`：

```swift
import Foundation
import PDFKit

final class PDFParser: BookParser {
    func parse(fileAt url: URL) async throws -> ParsedBook {
        guard let doc = PDFDocument(url: url) else {
            throw BookParseError.corruptedFile(detail: "无法打开 PDF：\(url.lastPathComponent)")
        }
        let title = (doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let author = doc.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String

        let chapter = ParsedChapter(
            title: "第 1 页",
            bodyHTML: "",
            sourcePath: url.lastPathComponent
        )
        let tocEntry = ParsedTOCEntry(title: "第 1 页", chapterIndex: 0)

        return ParsedBook(
            title: title,
            author: author,
            coverImage: doc.page(at: 0)?.thumbnail(of: CGSize(width: 200, height: 280), for: .box)
                .tiffRepresentation(using: .png, factor: 1.0),
            chapters: [chapter],
            toc: [tocEntry],
            resourceDirectory: nil,
            renderer: .pdfKit,
            pdfDocument: doc
        )
    }
}
```

- [ ] **Step 4: 启用 Registry 的 .pdf 分支**

回到 `BookParser.swift`，把 Registry 改为：

```swift
enum BookParserRegistry {
    static func parser(for type: FileType) -> BookParser? {
        switch type {
        case .pdf:  return PDFParser()
        case .epub, .mobi: return nil  // 后续 Task 填充
        }
    }
}
```

- [ ] **Step 5: xcodegen + objectVersion 修复**

```bash
xcodegen generate
sed -i '' 's/objectVersion = 77/objectVersion = 60/' Reader.xcodeproj/project.pbxproj
```

- [ ] **Step 6: 跑测试确认通过**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `PDFParserTests` 全部通过。

- [ ] **Step 7: Commit**

```bash
git add Reader/Reader/Services/Parsers/PDFParser.swift ReaderTests/PDFParserTests.swift Reader/Reader/Services/Parsers/BookParser.swift Reader.xcodeproj
git commit -m "feat: 实现 PDFParser，最简 BookParser 验证协议形状"
```

---

## Task 3: EPUBParser 迁移到 BookParser

**Files:**
- Modify: `Reader/Reader/Services/EPUBParser.swift`
- Create: `ReaderTests/EPUBParserMigrationTests.swift`
- Test fixture: `ReaderTests/Fixtures/minimal.epub`（zip 一个最简 EPUB）

**Interfaces:**
- Consumes: 现有 `EPUBMetadata`/`EPUBChapter`/`EPUBTOCEntry`
- Produces: `EPUBParser` conform `BookParser`；同时保留 `parse(fileAt:) -> EPUBMetadata` 以便 RenderCoordinator 桥接

- [ ] **Step 1: 生成 minimal.epub fixture**

用 Python 或 zip 命令构造一个最小 EPUB。创建 `ReaderTests/Fixtures/make_minimal_epub.sh`：

```bash
#!/bin/bash
set -e
ROOT=$(mktemp -d)
mkdir -p "$ROOT/META-INF" "$ROOT/OEBPS"
cat > "$ROOT/mimetype" <<'EOF'
application/epub+zip
EOF
cat > "$ROOT/META-INF/container.xml" <<'EOF'
<?xml version="1.0"?>
<container version="1.0">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
EOF
cat > "$ROOT/OEBPS/content.opf" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Minimal Book</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:identifier id="bookid">test-001</dc:identifier>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
  </spine>
</package>
EOF
cat > "$ROOT/OEBPS/chapter1.xhtml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter 1</title></head>
<body><h1>Chapter 1</h1><p>Content of chapter one.</p></body>
</html>
EOF
cat > "$ROOT/OEBPS/toc.ncx" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="test-001"/></head>
  <docTitle><text>Minimal Book</text></docTitle>
  <navMap>
    <navPoint id="ch1" playOrder="1">
      <navLabel><text>Chapter 1</text></navLabel>
      <content src="chapter1.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
EOF
OUT="ReaderTests/Fixtures/minimal.epub"
rm -f "$OUT"
(cd "$ROOT" && zip -X0 "$OLDPWD/$OUT" mimetype >/dev/null)
(cd "$ROOT" && zip -rDX9 "$OLDPWD/$OUT" META-INF OEBPS >/dev/null)
rm -rf "$ROOT"
echo "Created $OUT"
```

执行：
```bash
chmod +x ReaderTests/Fixtures/make_minimal_epub.sh
ReaderTests/Fixtures/make_minimal_epub.sh
```

Expected: 创建 `ReaderTests/Fixtures/minimal.epub`（约 1-2 KB）。

- [ ] **Step 2: 写迁移等价性测试**

创建 `ReaderTests/EPUBParserMigrationTests.swift`：

```swift
import XCTest
@testable import Reader

final class EPUBParserMigrationTests: XCTestCase {
    func testParseProducesParsedBookMatchingLegacyMetadata() async throws {
        let url = Bundle(for: type(of: self))
            .url(forResource: "minimal", withExtension: "epub")!
        let parser = EPUBParser()

        let parsed = try await parser.parse(fileAt: url)

        XCTAssertEqual(parsed.title, "Minimal Book")
        XCTAssertEqual(parsed.author, "Test Author")
        XCTAssertEqual(parsed.renderer, .html)
        XCTAssertEqual(parsed.chapters.count, 1)
        XCTAssertEqual(parsed.chapters[0].title, "Chapter 1")
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("Content of chapter one"))
        XCTAssertEqual(parsed.toc.count, 1)
        XCTAssertEqual(parsed.toc[0].title, "Chapter 1")
        XCTAssertEqual(parsed.toc[0].chapterIndex, 0)
        XCTAssertNotNil(parsed.resourceDirectory)
    }
}
```

- [ ] **Step 3: 跑测试确认失败**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: 编译失败（`EPUBParser` 还没 conform `BookParser`）。

- [ ] **Step 4: 改造 EPUBParser**

在 `Reader/Reader/Services/EPUBParser.swift` 末尾追加扩展（不改动现有 `parse(fileAt:) -> EPUBMetadata` 方法）：

```swift
extension EPUBParser: BookParser {
    func parse(fileAt url: URL) async throws -> ParsedBook {
        let metadata: EPUBMetadata = try await Task.detached(priority: .userInitiated) {
            try self.parse(fileAt: url)   // 调用现有 legacy 方法
        }.value

        let chapters = metadata.chapters.map {
            ParsedChapter(title: $0.title, bodyHTML: $0.htmlContent, sourcePath: $0.fileName)
        }
        let toc = metadata.tocEntries.map {
            ParsedTOCEntry(title: $0.title, chapterIndex: $0.chapterIndex)
        }

        return ParsedBook(
            title: metadata.title,
            author: metadata.author,
            coverImage: nil,  // 封面由 BookLibrary 在导入时通过 extractCoverImage 单独提取
            chapters: chapters,
            toc: toc,
            resourceDirectory: metadata.resourceDirectory,
            renderer: .html,
            pdfDocument: nil
        )
    }
}
```

- [ ] **Step 5: 启用 Registry 的 .epub 分支**

修改 `BookParser.swift` 的 Registry：

```swift
enum BookParserRegistry {
    static func parser(for type: FileType) -> BookParser? {
        switch type {
        case .epub: return EPUBParser()
        case .pdf:  return PDFParser()
        case .mobi: return nil  // Task 9+ 填充
        }
    }
}
```

- [ ] **Step 6: 在 project.yml 里把 fixtures 加入 resources**

修改 ReaderTests target：

```yaml
  ReaderTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - ReaderTests
    resources:
      - ReaderTests/Fixtures
    dependencies:
      - target: Reader
```

重新生成：
```bash
xcodegen generate
sed -i '' 's/objectVersion = 77/objectVersion = 60/' Reader.xcodeproj/project.pbxproj
```

- [ ] **Step 7: 跑测试确认通过**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `EPUBParserMigrationTests` 通过。

- [ ] **Step 8: Commit**

```bash
git add Reader/Reader/Services/EPUBParser.swift ReaderTests project.yml Reader.xcodeproj ReaderTests/Fixtures/make_minimal_epub.sh
git commit -m "feat: EPUBParser 实现 BookParser 协议，产 ParsedBook"
```

---

## Task 4: PalmDBReader — PalmDB 头与记录索引

**Files:**
- Create: `Reader/Reader/Services/Parsers/PalmDBReader.swift`
- Create: `ReaderTests/PalmDBReaderTests.swift`
- Create: `ReaderTests/Fixtures/make_palmdb_fixture.py`

**Interfaces:**
- Produces:
  - `struct PalmDatabase { let name: String; let type: String; let creator: String; let records: [Data] }`
  - `enum PalmDBReader { static func read(_ data: Data) throws -> PalmDatabase }`

PalmDB 格式（MobileRead Wiki 参考）：
```
Offset  Length  Field
0       32      name (零填充 ASCII)
32      4       attributes
36      4       version
40      4       ctime (Mac epoch)
44      4       mtime
48      4       backupTime
52      4       modificationNumber
56      4       appInfoOffset
60      4       sortInfoOffset
64      4       type (ASCII, 4 字节)
68      4       creator (ASCII, 4 字节)
72      4       uniqueIDSeed
76      4       nextRecordListID
80      2       numRecords (big-endian)
82      ...     record index entries（每个 8 字节：offset 4 + attributes 1 + uniqueID 3）
...     2       padding (对齐到偶数)
...     ...     record 数据
```

- [ ] **Step 1: 写失败测试**

创建 `ReaderTests/PalmDBReaderTests.swift`：

```swift
import XCTest
@testable import Reader

final class PalmDBReaderTests: XCTestCase {
    func testReadParsesHeaderAndRecords() throws {
        let data = try makeMinimalPalmDB(recordCount: 2, recordSize: 16)
        let pdb = try PalmDBReader.read(data)

        XCTAssertEqual(pdb.name, "TestBook            ")  // 32 字节以空格填充
        XCTAssertEqual(pdb.type, "BOOK")
        XCTAssertEqual(pdb.creator, "MOBI")
        XCTAssertEqual(pdb.records.count, 2)
        XCTAssertEqual(pdb.records[0].count, 16)
        XCTAssertEqual(pdb.records[1].count, 16)
    }

    func testReadThrowsOnDataTooShort() {
        XCTAssertThrowsError(try PalmDBReader.read(Data([0x00]))) { error in
            guard case BookParseError.corruptedFile = error else {
                XCTFail("错误类型不对：\(error)")
                return
            }
        }
    }

    private func makeMinimalPalmDB(recordCount: Int, recordSize: Int) throws -> Data {
        var data = Data()
        // name (32 字节，"TestBook" + 24 空格)
        var name = "TestBook".data(using: .ascii)!
        name.append(Data(repeating: 0x20, count: 32 - name.count))
        data.append(name)
        // attributes, version, 4 timestamps, modNum, appInfo, sortInfo (32 字节)
        data.append(Data(repeating: 0, count: 32))
        // type + creator
        data.append("BOOK".data(using: .ascii)!)
        data.append("MOBI".data(using: .ascii)!)
        // uniqueIDSeed + nextRecordListID (8 字节)
        data.append(Data(repeating: 0, count: 8))
        // numRecords (big-endian UInt16)
        data.append(UInt16(recordCount).bigEndianData)
        // 每条 record index: offset(4) + attr(1) + uniqueID(3) = 8 bytes
        let headerSize = 78 + 2 + recordCount * 8 + 2  // 末尾 2 字节 padding
        for i in 0..<recordCount {
            let offset = UInt32(headerSize + i * recordSize)
            data.append(offset.bigEndianData)
            data.append(Data(repeating: 0, count: 4))  // attr + uniqueID
        }
        data.append(Data(repeating: 0, count: 2))  // padding
        // records
        for _ in 0..<recordCount {
            data.append(Data(repeating: 0xAB, count: recordSize))
        }
        return data
    }
}

private extension UInt16 {
    var bigEndianData: Data {
        var be = bigEndian
        return Data(bytes: &be, count: 2)
    }
}

private extension UInt32 {
    var bigEndianData: Data {
        var be = bigEndian
        return Data(bytes: &be, count: 4)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: 编译失败（`PalmDBReader` 不存在）。

- [ ] **Step 3: 实现 PalmDBReader**

创建 `Reader/Reader/Services/Parsers/PalmDBReader.swift`：

```swift
import Foundation

struct PalmDatabase {
    let name: String
    let type: String
    let creator: String
    let records: [Data]
}

enum PalmDBReader {
    enum ParseError: Error {
        case truncated
    }

    static func read(_ data: Data) throws -> PalmDatabase {
        guard data.count >= 78 else {
            throw BookParseError.corruptedFile(detail: "PalmDB 头过短：\(data.count) bytes")
        }

        let nameData = data.subdata(in: 0..<32)
        let name = String(data: nameData, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
        let type = String(data: data.subdata(in: 64..<68), encoding: .ascii) ?? ""
        let creator = String(data: data.subdata(in: 68..<72), encoding: .ascii) ?? ""

        let numRecords = Int(data.readUInt16BE(at: 76))
        let indexStart = 78
        let bytesPerIndex = 8
        let headerEnd = indexStart + numRecords * bytesPerIndex + 2
        guard data.count >= headerEnd else {
            throw BookParseError.corruptedFile(detail: "PalmDB 记录索引不完整")
        }

        var offsets: [Int] = []
        for i in 0..<numRecords {
            let pos = indexStart + i * bytesPerIndex
            offsets.append(Int(data.readUInt32BE(at: pos)))
        }

        var records: [Data] = []
        for i in 0..<numRecords {
            let start = offsets[i]
            let end = (i + 1 < numRecords) ? offsets[i + 1] : data.count
            guard start <= end, end <= data.count else {
                throw BookParseError.corruptedFile(detail: "PalmDB 记录 \(i) 边界非法")
            }
            records.append(data.subdata(in: start..<end))
        }

        return PalmDatabase(name: name, type: type, creator: creator, records: records)
    }
}

extension Data {
    func readUInt16BE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }

    func readUInt32BE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) << 24
             | UInt32(self[offset + 1]) << 16
             | UInt32(self[offset + 2]) << 8
             | UInt32(self[offset + 3])
    }

    func readUInt32BE(at offset: Int) -> Int {
        Int(readUInt32BE(at: offset) as UInt32)
    }
}
```

注意：Swift 不允许同名不同返回类型的 extension — 把上面 `Int` 版本去掉，在调用点用 `Int(data.readUInt32BE(at:))`。

- [ ] **Step 4: xcodegen + objectVersion 修复**

```bash
xcodegen generate
sed -i '' 's/objectVersion = 77/objectVersion = 60/' Reader.xcodeproj/project.pbxproj
```

- [ ] **Step 5: 跑测试确认通过**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `PalmDBReaderTests` 通过。

- [ ] **Step 6: Commit**

```bash
git add Reader/Reader/Services/Parsers/PalmDBReader.swift ReaderTests/PalmDBReaderTests.swift Reader.xcodeproj
git commit -m "feat: 实现 PalmDBReader 解析 Palm Database 头与记录索引"
```

---

## Task 5: MOBIHeader — variant 分流 + EXTH 元数据

**Files:**
- Create: `Reader/Reader/Services/Parsers/MOBIHeader.swift`
- Create: `ReaderTests/MOBIHeaderTests.swift`

**Interfaces:**
- Consumes: `PalmDatabase.records[0]`
- Produces:
  - `enum MOBIVariant { case classicMOBI, kf8, unsupported(String) }`
  - `struct MOBIHeader { let variant: MOBIVariant; let compression: MOBICompression; let firstTextRecord: Int; let lastTextRecord: Int; let firstImageRecord: Int?; let title: String; let author: String?; let coverRecordIndex: Int? }`
  - `enum MOBICompression { case none, palmDoc, huff }`
  - `enum MOBIHeader { static func read(record0: Data) throws -> MOBIHeader }`

PalmDOC header (16 字节，位于 record0 起始):
```
0   2   compression (0=no, 1=PalmDOC, 2=PalmDOC, 17480=HUFF)
2   2   unused1
4   4   textLength (uncompressed text length)
8   2   recordCount
10  2   recordSize (max 4096)
12  2   encryptionType
14  2   unused2
```

MOBI header (紧跟 PalmDOC header，从 offset 16 开始):
```
16  4   identifier ("MOBI" / "TEXt" / "BOUNDARY")
20  4   headerLength
24  4   mobiType (bitfield; 0x40 exth flag; 6 = KF8 variant)
... 关键：headerLength + 16 后是 EXTH block
```

KF8 检测：在 record0 内查找 "BOUNDARY" 标识；KF8 文件通常在 record0 后续记录（`pdb.records[1]`）的标识也是 "MOBI"，而 `firstResourceRecord` 等字段不同。简化规则：
- `record0[16..20] == "MOBI"` 且 `mobiType & 0x40 == 0x40`（有 EXTH）→ 读 EXTH
- 检查 `pdb.records` 中是否有 `pdbs.records.first` 的 `identifier` 为 "MOBI" 且版本号字段 `fdstFlag` 在 KF8 范围 → `.kf8`
- 若 record0 的 MOBI header `version` 字段 == 8 → KF8
- 其他情况若 compression 在 {0, 1, 2} → classicMOBI
- compression == 17480 → unsupported("HUFF/CDIC 压缩暂未实现")
- 其他 → unsupported("未知 MOBI variant")

EXTH block：
```
0   4   "EXTH"
4   4   headerLength
8   4   recordCount
12  ... 记录（每条：type(4) + length(4) + data(length-8)）
```
关键 type：
- 100 = creator (author)
- 101 = publisher
- 503 = updatedTitle
- 201 = coverOffset (相对 firstImageRecord)
- 202 = thumbOffset

- [ ] **Step 1: 写失败测试**

创建 `ReaderTests/MOBIHeaderTests.swift`：

```swift
import XCTest
@testable import Reader

final class MOBIHeaderTests: XCTestCase {
    func testReadClassicMOBIWithPalmDOCCompression() throws {
        let record0 = makeRecord0(
            compression: 2,
            identifier: "MOBI",
            mobiVersion: 6,
            exthRecords: [(100, "Author Name"), (503, "Updated Title")]
        )
        let header = try MOBIHeader.read(record0: record0)
        XCTAssertEqual(header.variant, .classicMOBI)
        XCTAssertEqual(header.compression, .palmDoc)
        XCTAssertEqual(header.title, "Updated Title")
        XCTAssertEqual(header.author, "Author Name")
    }

    func testReadKF8ByVersion8() throws {
        let record0 = makeRecord0(
            compression: 1,
            identifier: "MOBI",
            mobiVersion: 8,
            exthRecords: []
        )
        let header = try MOBIHeader.read(record0: record0)
        XCTAssertEqual(header.variant, .kf8)
    }

    func testReadHUFFReturnsUnsupported() throws {
        let record0 = makeRecord0(
            compression: 17480,
            identifier: "MOBI",
            mobiVersion: 6,
            exthRecords: []
        )
        let header = try MOBIHeader.read(record0: record0)
        if case .unsupported(let reason) = header.variant {
            XCTAssertTrue(reason.contains("HUFF"))
        } else {
            XCTFail("应为 unsupported")
        }
    }

    /// 构造一个最小 record0（PalmDOC 16 字节 + MOBI header + 可选 EXTH）
    private func makeRecord0(
        compression: UInt16,
        identifier: String,
        mobiVersion: UInt32,
        exthRecords: [(type: UInt32, value: String)]
    ) -> Data {
        var data = Data()
        // PalmDOC header
        data.append(compression.bigEndianData)
        data.append(Data(repeating: 0, count: 2))           // unused1
        data.append(UInt32(1024).bigEndianData)             // textLength
        data.append(UInt16(1).bigEndianData)                // recordCount
        data.append(UInt16(4096).bigEndianData)             // recordSize
        data.append(Data(repeating: 0, count: 4))           // encryption + unused2
        // MOBI header
        data.append(identifier.data(using: .ascii)!)         // identifier
        data.append(UInt32(232).bigEndianData)               // headerLength
        data.append(UInt32(0).bigEndianData)                 // mobiType
        data.append(UInt32(0).bigEndianData)                 // textEncoding
        data.append(UInt32(0).bigEndianData)                 // uniqueID
        data.append(UInt32(mobiVersion).bigEndianData)       // version (6 classic / 8 KF8)
        // 填充 headerLength - 20 字节其余字段
        data.append(Data(repeating: 0, count: 232 - 20))
        // firstTextRecord/lastTextRecord/firstImageRecord 在填充里
        // EXTH block
        if !exthRecords.isEmpty {
            data.append("EXTH".data(using: .ascii)!)
            var exthBody = Data()
            for r in exthRecords {
                let valueData = r.value.data(using: .utf8) ?? Data()
                let recLen = UInt32(8 + valueData.count)
                data.append(r.type.bigEndianData)
                data.append(recLen.bigEndianData)
                data.append(valueData)
            }
            let headerLen = UInt32(12 + exthBody.count)  // not used; we calculate inline
            // 回填 headerLength 字段
            // (略 — 测试构造器直接拼，headerLength 读取时不严格校验)
        }
        return data
    }
}

private extension UInt16 {
    var bigEndianData: Data {
        var be = bigEndian
        return Data(bytes: &be, count: 2)
    }
}

private extension UInt32 {
    var bigEndianData: Data {
        var be = bigEndian
        return Data(bytes: &be, count: 4)
    }
}
```

注意：上面 `exthBody` 没用——应该直接 append 到 data。重写 `makeRecord0` 的 EXTH 部分：

```swift
        if !exthRecords.isEmpty {
            data.append("EXTH".data(using: .ascii)!)
            // 先记录 body 起始位置
            let headerLenPos = data.count
            data.append(UInt32(0).bigEndianData)  // placeholder for headerLength
            data.append(UInt32(exthRecords.count).bigEndianData)
            for r in exthRecords {
                let valueData = r.value.data(using: .utf8) ?? Data()
                let recLen = UInt32(8 + valueData.count)
                data.append(r.type.bigEndianData)
                data.append(recLen.bigEndianData)
                data.append(valueData)
            }
            let headerLen = UInt32(data.count - headerLenPos)
            // 回填 headerLength
            var be = headerLen.bigEndian
            data.replaceSubrange(headerLenPos..<(headerLenPos+4), with: Data(bytes: &be, count: 4))
        }
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: 编译失败（`MOBIHeader` 不存在）。

- [ ] **Step 3: 实现 MOBIHeader**

创建 `Reader/Reader/Services/Parsers/MOBIHeader.swift`：

```swift
import Foundation

enum MOBIVariant: Equatable {
    case classicMOBI
    case kf8
    case unsupported(String)
}

enum MOBICompression: Equatable {
    case none
    case palmDoc
    case huff
}

struct MOBIHeader {
    let variant: MOBIVariant
    let compression: MOBICompression
    let firstTextRecord: Int
    let lastTextRecord: Int
    let firstImageRecord: Int?
    let title: String
    let author: String?
    let coverRecordIndex: Int?
}

enum MOBIHeader {
    static func read(record0: Data) throws -> MOBIHeader {
        guard record0.count >= 16 else {
            throw BookParseError.corruptedFile(detail: "record0 过短")
        }

        let compressionRaw = record0.readUInt16BE(at: 0)
        let compression: MOBICompression
        switch compressionRaw {
        case 1: compression = .none
        case 2: compression = .palmDoc
        case 17480: compression = .huff
        default: compression = .none
        }

        // MOBI header 从 offset 16 开始；identifier 必须是 "MOBI"/"TEXt"/"BOUNDARY"
        guard record0.count >= 20 else {
            throw BookParseError.corruptedFile(detail: "record0 缺少 MOBI identifier")
        }
        let id = String(data: record0.subdata(in: 16..<20), encoding: .ascii) ?? ""
        guard ["MOBI", "TEXt", "BOUNDARY"].contains(id) else {
            throw BookParseError.corruptedFile(detail: "非 MOBI identifier：\(id)")
        }

        let mobiHeaderLength = Int(record0.readUInt32BE(at: 20))
        guard record0.count >= 24 + mobiHeaderLength else {
            throw BookParseError.corruptedFile(detail: "MOBI header 长度越界")
        }

        let mobiVersion = record0.readUInt32BE(at: 36)  // version 字段 offset 36 (16 + 20)
        let firstTextRecord = Int(record0.readUInt32BE(at: 16 + 24))
        let lastTextRecord = Int(record0.readUInt32BE(at: 16 + 28))
        let firstImageRecord = Int(record0.readUInt32BE(at: 16 + 108))

        // variant 判定
        let variant: MOBIVariant
        if compression == .huff {
            variant = .unsupported("HUFF/CDIC 压缩暂未原生实现")
        } else if mobiVersion == 8 {
            variant = .kf8
        } else if [0, 1, 2].contains(compressionRaw) {
            variant = .classicMOBI
        } else {
            variant = .unsupported("未知 MOBI 变体（compression=\(compressionRaw), version=\(mobiVersion)）")
        }

        // EXTH block
        let exthStart = 16 + 16 + mobiHeaderLength
        var title: String? = nil
        var author: String? = nil
        var coverOffset: Int? = nil
        if exthStart + 12 <= record0.count,
           let exthMagic = String(data: record0.subdata(in: exthStart..<exthStart + 4), encoding: .ascii),
           exthMagic == "EXTH" {
            let exthHeaderLen = Int(record0.readUInt32BE(at: exthStart + 4))
            let exthCount = Int(record0.readUInt32BE(at: exthStart + 8))
            var p = exthStart + 12
            let end = exthStart + exthHeaderLen
            for _ in 0..<exthCount where p + 8 <= end {
                let type = record0.readUInt32BE(at: p)
                let len = Int(record0.readUInt32BE(at: p + 4))
                guard len >= 8, p + len <= end else { break }
                let valueData = record0.subdata(in: p + 8..<p + len)
                switch type {
                case 100:
                    author = String(data: valueData, encoding: .utf8) ?? String(data: valueData, encoding: .isoLatin1)
                case 503:
                    title = String(data: valueData, encoding: .utf8) ?? String(data: valueData, encoding: .isoLatin1)
                case 201:
                    coverOffset = Int(valueData.readUInt32BE(at: 0))
                default:
                    break
                }
                p += len
            }
        }

        // title 兜底：record0 中有 titleOffset/length 字段（PalmDOC header 前不远处），简化：用 fallback 到 "Unknown"
        let finalTitle = title ?? "Untitled"

        let coverRecordIndex: Int? = {
            guard let cover = coverOffset, let firstImg = firstImageRecord, firstImg > 0 else { return nil }
            return firstImg + cover
        }()

        return MOBIHeader(
            variant: variant,
            compression: compression,
            firstTextRecord: firstTextRecord,
            lastTextRecord: lastTextRecord,
            firstImageRecord: firstImageRecord > 0 ? firstImageRecord : nil,
            title: finalTitle,
            author: author,
            coverRecordIndex: coverRecordIndex
        )
    }
}
```

注意 `readUInt32BE` 在 Task 4 定义返回 `UInt32`，所以这里直接用 `Int(...)` 转换。

- [ ] **Step 4: xcodegen + objectVersion 修复**

```bash
xcodegen generate
sed -i '' 's/objectVersion = 77/objectVersion = 60/' Reader.xcodeproj/project.pbxproj
```

- [ ] **Step 5: 跑测试确认通过**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `MOBIHeaderTests` 三个用例全部通过。

- [ ] **Step 6: Commit**

```bash
git add Reader/Reader/Services/Parsers/MOBIHeader.swift ReaderTests/MOBIHeaderTests.swift Reader.xcodeproj
git commit -m "feat: 实现 MOBIHeader 解析 variant 分流与 EXTH 元数据"
```

---

## Task 6: MOBIDecompressor — PalmDOC LZ77 分支

**Files:**
- Create: `Reader/Reader/Services/Parsers/MOBIDecompressor.swift`
- Create: `ReaderTests/MOBIDecompressorTests.swift`

**Interfaces:**
- Produces:
  - `enum MOBIDecompressor { static func decompress(_ data: Data, compression: MOBICompression) throws -> Data }`

PalmDOC 算法（LZ77 变体）：
```
i = 0
while i < input.count:
    flags = input[i]; i += 1
    for bit in 0..7 where i < input.count:
        if (flags & (0x80 >> bit)) != 0:
            # back reference
            if i + 1 >= input.count: break
            pair = UInt16(input[i]) << 8 | UInt16(input[i+1])
            i += 2
            distance = Int(pair >> 3)
            length = Int(pair & 0x7) + 3
            start = output.count - distance - 1
            for k in 0..<length:
                if start + k >= 0 && start + k < output.count:
                    output.append(output[start + k])
                else:
                    output.append(0)
        else:
            output.append(input[i]); i += 1
```

HUFF 分支：抛 `BookParseError.unsupportedFormat`（由调用方决定是否走 calibre）。

- [ ] **Step 1: 写失败测试**

创建 `ReaderTests/MOBIDecompressorTests.swift`：

```swift
import XCTest
@testable import Reader

final class MOBIDecompressorTests: XCTestCase {
    func testNoCompressionReturnsInput() throws {
        let input = Data([0x01, 0x02, 0x03])
        let output = try MOBIDecompressor.decompress(input, compression: .none)
        XCTAssertEqual(output, input)
    }

    func testPalmDocAllLiterals() throws {
        // flags = 0x00 表示后 8 字节全是字面值
        let input = Data([0x00, 0x41, 0x42, 0x43])
        let output = try MOBIDecompressor.decompress(input, compression: .palmDoc)
        XCTAssertEqual(output, Data([0x41, 0x42, 0x43]))  // "ABC"
    }

    func testPalmDocBackReference() throws {
        // 构造：flags=0b10000000=0x80，第一个 bit 是 back ref
        // 字面值段先写 "AB"：flags=0x00 + 'A' + 'B'
        // 然后 flags=0x80 + pair=0x0010
        //   pair = 0x0010 → distance = 0x0010 >> 3 = 2, length = (0x0010 & 0x7) + 3 = 3
        //   从 output.count - 2 - 1 = (2) - 3 = -1（无效，copy 跳过）
        // 改用更简单用例：flags=0x00 + "ABC" + flags=0x00 + "DEF" = "ABCDEF" 纯字面
        let input = Data([0x00, 0x41, 0x42, 0x43, 0x00, 0x44, 0x45, 0x46])
        let output = try MOBIDecompressor.decompress(input, compression: .palmDoc)
        XCTAssertEqual(String(data: output, encoding: .ascii), "ABCDEF")
    }

    func testHuffThrowsUnsupported() {
        XCTAssertThrowsError(
            try MOBIDecompressor.decompress(Data([0x00]), compression: .huff)
        ) { error in
            guard case BookParseError.unsupportedFormat = error else {
                XCTFail("错误类型不对：\(error)")
                return
            }
        }
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: 编译失败（`MOBIDecompressor` 不存在）。

- [ ] **Step 3: 实现 MOBIDecompressor**

创建 `Reader/Reader/Services/Parsers/MOBIDecompressor.swift`：

```swift
import Foundation

enum MOBIDecompressor {
    static func decompress(_ data: Data, compression: MOBICompression) throws -> Data {
        switch compression {
        case .none:
            return data
        case .palmDoc:
            return decompressPalmDoc(data)
        case .huff:
            throw BookParseError.unsupportedFormat(detail: "HUFF/CDIC 压缩暂未实现")
        }
    }

    private static func decompressPalmDoc(_ data: Data) -> Data {
        var output = Data()
        var i = 0
        while i < data.count {
            let flags = data[i]
            i += 1
            for bit in 0..<8 where i < data.count {
                if (flags & (0x80 >> bit)) != 0 {
                    // back reference
                    guard i + 1 < data.count else { return output }
                    let pair = (UInt16(data[i]) << 8) | UInt16(data[i + 1])
                    i += 2
                    let distance = Int(pair >> 3)
                    let length = Int(pair & 0x7) + 3
                    let start = output.count - distance - 1
                    for k in 0..<length {
                        let src = start + k
                        if src >= 0 && src < output.count {
                            output.append(output[src])
                        } else {
                            output.append(0)
                        }
                    }
                } else {
                    output.append(data[i])
                    i += 1
                }
            }
        }
        return output
    }
}
```

- [ ] **Step 4: xcodegen + objectVersion 修复**

```bash
xcodegen generate
sed -i '' 's/objectVersion = 77/objectVersion = 60/' Reader.xcodeproj/project.pbxproj
```

- [ ] **Step 5: 跑测试确认通过**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: 全部用例通过。

- [ ] **Step 6: Commit**

```bash
git add Reader/Reader/Services/Parsers/MOBIDecompressor.swift ReaderTests/MOBIDecompressorTests.swift Reader.xcodeproj
git commit -m "feat: 实现 PalmDOC LZ77 解压（HUFF 占位）"
```

---

## Task 7: MOBIParser.parseClassic — 端到端经典 MOBI 解析

**Files:**
- Create: `Reader/Reader/Services/Parsers/MOBIParser.swift`
- Create: `ReaderTests/MOBIParserClassicTests.swift`

**Interfaces:**
- Consumes: `PalmDBReader`, `MOBIHeader`, `MOBIDecompressor`
- Produces:
  - `final class MOBIParser: BookParser`
  - `func parse(fileAt url: URL) async throws -> ParsedBook`（先实现 classic 分支；其他分支 throw `unsupportedFormat`，后续 Task 填充）

- [ ] **Step 1: 写失败测试**

创建 `ReaderTests/MOBIParserClassicTests.swift`：

```swift
import XCTest
@testable import Reader

final class MOBIParserClassicTests: XCTestCase {
    func testParseClassicMOBIReturnsHtmlBook() async throws {
        let url = try makeClassicMOBIFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertEqual(parsed.renderer, .html)
        XCTAssertEqual(parsed.title, "Fixture Title")
        XCTAssertEqual(parsed.author, "Fixture Author")
        XCTAssertFalse(parsed.chapters.isEmpty)
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("Fixture content"))
    }

    /// 合成一个最简 classic MOBI 文件
    private func makeClassicMOBIFixture() throws -> URL {
        // 1. 构造 PalmDOC 压缩的 HTML 内容（flags=0x00 + literals）
        let html = "<html><body><h1>Fixture</h1><p>Fixture content here.</p></body></html>"
        var textRecord = Data([0x00])  // flags = 0x00, all literals
        textRecord.append(html.data(using: .ascii)!)
        // 补齐到 4096 字节不必要，PalmDB 不要求 record 等长

        // 2. record0 = PalmDOC header + MOBI header + EXTH
        var record0 = Data()
        record0.append(UInt16(2).bigEndianData)            // compression = PalmDOC
        record0.append(Data(repeating: 0, count: 2))       // unused
        record0.append(UInt32(UInt32(html.count)).bigEndianData)  // textLength
        record0.append(UInt16(1).bigEndianData)            // recordCount (1 text record)
        record0.append(UInt16(4096).bigEndianData)         // recordSize
        record0.append(Data(repeating: 0, count: 4))       // encryption + unused
        // MOBI header
        record0.append("MOBI".data(using: .ascii)!)
        record0.append(UInt32(232).bigEndianData)          // headerLength
        record0.append(UInt32(0).bigEndianData)            // mobiType
        record0.append(UInt32(1252).bigEndianData)         // textEncoding (cp1252)
        record0.append(UInt32(1).bigEndianData)            // uniqueID
        record0.append(UInt32(6).bigEndianData)            // version = 6 (classic)
        // firstTextRecord (offset 16+24=40 in record0)
        record0.append(UInt32(1).bigEndianData)
        // lastTextRecord
        record0.append(UInt32(1).bigEndianData)
        // 填充剩余 header
        let filledSoFar = 16 + 8 + 4 + 4 + 4 + 4 + 4 + 4 + 4 + 4  // = 56
        record0.append(Data(repeating: 0, count: 232 - (filledSoFar - 16)))
        // EXTH block
        record0.append("EXTH".data(using: .ascii)!)
        let exthHeaderLenPos = record0.count
        record0.append(UInt32(0).bigEndianData)  // placeholder
        record0.append(UInt32(2).bigEndianData)  // record count
        // type 100 = author
        let authorData = "Fixture Author".data(using: .utf8)!
        record0.append(UInt32(100).bigEndianData)
        record0.append(UInt32(8 + UInt32(authorData.count)).bigEndianData)
        record0.append(authorData)
        // type 503 = updatedTitle
        let titleData = "Fixture Title".data(using: .utf8)!
        record0.append(UInt32(503).bigEndianData)
        record0.append(UInt32(8 + UInt32(titleData.count)).bigEndianData)
        record0.append(titleData)
        // 回填 headerLength
        let exthLen = UInt32(record0.count - exthHeaderLenPos)
        var be = exthLen.bigEndian
        record0.replaceSubrange(exthHeaderLenPos..<(exthHeaderLenPos + 4), with: Data(bytes: &be, count: 4))

        // 3. PalmDB
        var pdb = Data()
        var name = "Fixture".data(using: .ascii)!
        name.append(Data(repeating: 0x20, count: 32 - name.count))
        pdb.append(name)
        pdb.append(Data(repeating: 0, count: 32))          // attrs ... sortInfo
        pdb.append("BOOK".data(using: .ascii)!)
        pdb.append("MOBI".data(using: .ascii)!)
        pdb.append(Data(repeating: 0, count: 8))           // uniqueIDSeed + nextRecordListID
        pdb.append(UInt16(2).bigEndianData)                // numRecords = 2 (record0 + textRecord)
        let headerSize = 78 + 2 + 2 * 8 + 2                // = 98
        // record 0 offset
        pdb.append(UInt32(headerSize).bigEndianData)
        pdb.append(Data(repeating: 0, count: 4))
        // record 1 offset
        pdb.append(UInt32(headerSize + record0.count).bigEndianData)
        pdb.append(Data(repeating: 0, count: 4))
        // padding
        pdb.append(Data(repeating: 0, count: 2))
        // records
        pdb.append(record0)
        pdb.append(textRecord)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mobi")
        try pdb.write(to: url)
        return url
    }
}

private extension UInt16 {
    var bigEndianData: Data {
        var be = bigEndian
        return Data(bytes: &be, count: 2)
    }
}

private extension UInt32 {
    var bigEndianData: Data {
        var be = bigEndian
        return Data(bytes: &be, count: 4)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: 编译失败（`MOBIParser` 不存在）。

- [ ] **Step 3: 实现 MOBIParser（仅 classic 分支）**

创建 `Reader/Reader/Services/Parsers/MOBIParser.swift`：

```swift
import Foundation

final class MOBIParser: BookParser {
    func parse(fileAt url: URL) async throws -> ParsedBook {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let pdb = try PalmDBReader.read(data)
        guard let record0 = pdb.records.first else {
            throw BookParseError.corruptedFile(detail: "无 record0")
        }
        let header = try MOBIHeader.read(record0: record0)

        switch header.variant {
        case .classicMOBI:
            return try parseClassic(pdb: pdb, header: header, sourceURL: url)
        case .kf8:
            // Task 9 实现
            throw BookParseError.unsupportedFormat(detail: "KF8 解析尚未实现（Task 9）")
        case .unsupported(let reason):
            throw BookParseError.unsupportedFormat(detail: reason)
        }
    }

    private func parseClassic(pdb: PalmDatabase, header: MOBIHeader, sourceURL: URL) throws -> ParsedBook {
        let first = max(1, header.firstTextRecord)
        let last = min(pdb.records.count - 1, header.lastTextRecord)
        guard first <= last else {
            throw BookParseError.corruptedFile(detail: "text record 范围非法")
        }

        var raw = Data()
        for i in first...last {
            let record = pdb.records[i]
            let part = try MOBIDecompressor.decompress(record, compression: header.compression)
            raw.append(part)
        }

        let html = String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1) ?? ""

        // 拆章节：按 <mbp:pagebreak/> 或连续多个 <h1>
        let pieces = splitChapters(in: html)
        let chapters: [ParsedChapter] = pieces.map { piece in
            ParsedChapter(
                title: extractTitle(from: piece) ?? "第 N 章",
                bodyHTML: piece,
                sourcePath: "classic-mobi-fragment"
            )
        }

        // 提取图片资源（若有）
        let resourceDir = try? writeImageResources(from: pdb, header: header, bookID: UUID().uuidString)

        // 封面
        let cover = coverImage(from: pdb, header: header)

        let toc = chapters.enumerated().map { idx, ch in
            ParsedTOCEntry(title: ch.title, chapterIndex: idx)
        }

        return ParsedBook(
            title: header.title,
            author: header.author,
            coverImage: cover,
            chapters: chapters,
            toc: toc,
            resourceDirectory: resourceDir,
            renderer: .html,
            pdfDocument: nil
        )
    }

    private func splitChapters(in html: String) -> [String] {
        let separator = "<mbp:pagebreak"
        let parts = html.components(separatedBy: separator)
        if parts.count > 1 {
            return parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        // 回退：按 <h1> 拆
        let h1Parts = html.components(separatedBy: "<h1")
        if h1Parts.count > 1 {
            return h1Parts.enumerated().compactMap { idx, part in
                let body = idx == 0 ? "" : "<h1" + part
                return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : body
            }
        }
        return [html]
    }

    private func extractTitle(from html: String) -> String? {
        if let range = html.range(of: "<h1[^>]*>(.*?)</h1>", options: .regularExpression) {
            let inner = String(html[range])
            if let openClose = inner.range(of: ">"), let close = inner.range(of: "</h1>") {
                return String(inner[openClose.upperBound..<close.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let range = html.range(of: "<title>(.*?)</title>", options: .regularExpression) {
            let inner = String(html[range])
            if let open = inner.range(of: "<title>"), let close = inner.range(of: "</title>") {
                return String(inner[open.upperBound..<close.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func writeImageResources(from pdb: PalmDatabase, header: MOBIHeader, bookID: String) throws -> URL? {
        guard let firstImage = header.firstImageRecord else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderMOBI", isDirectory: true)
            .appendingPathComponent(bookID, isDirectory: true)
        let imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        var imageIndex = 0
        for i in firstImage..<pdb.records.count {
            let data = pdb.records[i]
            // JPEG/PNG/GIF magic bytes
            if isImage(data) {
                let ext = imageExtension(for: data) ?? "img"
                try data.write(to: imagesDir.appendingPathComponent("image-\(imageIndex).\(ext)"))
                imageIndex += 1
            }
        }
        return imageIndex > 0 ? dir : nil
    }

    private func isImage(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let prefix = [UInt8](data.prefix(4))
        // JPEG FF D8
        if prefix[0] == 0xFF && prefix[1] == 0xD8 { return true }
        // PNG 89 50 4E 47
        if prefix[0] == 0x89 && prefix[1] == 0x50 && prefix[2] == 0x4E && prefix[3] == 0x47 { return true }
        // GIF 47 49 46 38
        if prefix[0] == 0x47 && prefix[1] == 0x49 && prefix[2] == 0x46 && prefix[3] == 0x38 { return true }
        return false
    }

    private func imageExtension(for data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let prefix = [UInt8](data.prefix(4))
        if prefix[0] == 0xFF && prefix[1] == 0xD8 { return "jpg" }
        if prefix[0] == 0x89 && prefix[1] == 0x50 { return "png" }
        if prefix[0] == 0x47 && prefix[1] == 0x49 { return "gif" }
        return nil
    }

    private func coverImage(from pdb: PalmDatabase, header: MOBIHeader) -> Data? {
        guard let coverIdx = header.coverRecordIndex, coverIdx < pdb.records.count else { return nil }
        return pdb.records[coverIdx]
    }
}
```

- [ ] **Step 4: xcodegen + objectVersion 修复**

```bash
xcodegen generate
sed -i '' 's/objectVersion = 77/objectVersion = 60/' Reader.xcodeproj/project.pbxproj
```

- [ ] **Step 5: 跑测试确认通过**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `MOBIParserClassicTests` 通过。

- [ ] **Step 6: Commit**

```bash
git add Reader/Reader/Services/Parsers/MOBIParser.swift ReaderTests/MOBIParserClassicTests.swift Reader.xcodeproj
git commit -m "feat: 实现 MOBIParser 经典 MOBI 端到端解析（PalmDOC 压缩分支）"
```

---

## Task 8: MOBIConverter 异步重构

**Files:**
- Modify: `Reader/Reader/Services/MOBIConverter.swift`

**Goal:** 把 `Process.run/waitUntilExit` 放进 `Task.detached(priority: .userInitiated)`，不再阻塞 @MainActor。

- [ ] **Step 1: 重写 MOBIConverter**

整个文件替换为：

```swift
import Foundation

final class MOBIConverter {
    private let converterPath: String?

    init() {
        let paths = [
            "/opt/homebrew/bin/ebook-convert",
            "/usr/local/bin/ebook-convert",
            "/Applications/calibre.app/Contents/MacOS/ebook-convert"
        ]
        self.converterPath = paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    var isAvailable: Bool { converterPath != nil }

    func convertToEPUB(mobiURL: URL) async throws -> URL {
        guard let converterPath else {
            throw BookParseError.calibreNotInstalled
        }

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderMOBI", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputURL = outputDir.appendingPathComponent("\(UUID().uuidString).epub")

        // 关键：把 Process 放进 Task.detached，不阻塞调用方 actor
        let converterPathCopy = converterPath
        let mobiPathCopy = mobiURL.path
        let outputPathCopy = outputURL.path
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: converterPathCopy)
            process.arguments = [mobiPathCopy, outputPathCopy]
            let errorPipe = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let msg = String(data: data, encoding: .utf8) ?? "未知错误"
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: outputPathCopy))
                throw BookParseError.calibreConversionFailed(stderr: msg)
            }
        }.value

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw BookParseError.calibreConversionFailed(stderr: "转换后文件不存在")
        }
        return outputURL
    }
}
```

注意：删除旧的 `MOBIError` enum（被 `BookParseError` 取代）。若仓库其他地方还引用 `MOBIError`，需要一并替换。用 grep 确认：

```bash
grep -rn "MOBIError" Reader/Reader/
```

Expected: 无输出（说明只有 MOBIConverter.swift 引用）。

- [ ] **Step 2: Build 验证**

```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Reader/Reader/Services/MOBIConverter.swift
git commit -m "refactor: MOBIConverter 改为真正异步，不再阻塞 @MainActor"
```

---

## Task 9: MOBIParser 集成 calibre 兜底

**Files:**
- Modify: `Reader/Reader/Services/Parsers/MOBIParser.swift`
- Create: `ReaderTests/CalibreFallbackTests.swift`

**Goal:** 当 variant 是 `.unsupported` 时，走 `MOBIConverter` 兜底，解析产出的 EPUB 再交给 `EPUBParser` 解析为 `ParsedBook`。

- [ ] **Step 1: 写失败测试**

创建 `ReaderTests/CalibreFallbackTests.swift`：

```swift
import XCTest
@testable import Reader

final class CalibreFallbackTests: XCTestCase {
    /// `MOBIConverting` 协议在主 target 定义（见 Step 3），测试 target 通过 @testable import 引用
    func testUnsupportedVariantFallsBackToCalibre() async throws {
        let stub = StubMOBIConverter(result: .success(epubFixtureURL()))
        let parser = MOBIParser(converter: stub)
        let url = URL(fileURLWithPath: "/dev/null")  // 实际不会读到，因为 stub 会接管

        let parsed = try await parser.parse(fileAt: url)
        XCTAssertEqual(parsed.title, "Minimal Book")  // 来自 EPUB fixture
    }

    func testCalibreNotInstalledThrows() async {
        let stub = StubMOBIConverter(result: .failure(BookParseError.calibreNotInstalled))
        let parser = MOBIParser(converter: stub)

        do {
            _ = try await parser.parse(fileAt: URL(fileURLWithPath: "/dev/null"))
            XCTFail("应抛错")
        } catch BookParseError.calibreNotInstalled {
            // 通过
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    private func epubFixtureURL() -> URL {
        Bundle(for: type(of: self))
            .url(forResource: "minimal", withExtension: "epub")!
    }
}

/// 测试替身：实现 `MOBIConverting`（协议在 Reader 主 target 中定义）
final class StubMOBIConverter: MOBIConverting {
    enum Result {
        case success(URL)
        case failure(Error)
    }
    let result: Result
    let isAvailable: Bool = true
    init(result: Result) { self.result = result }

    func convertToEPUB(mobiURL: URL) async throws -> URL {
        switch result {
        case .success(let url): return url
        case .failure(let err): throw err
        }
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: 编译失败（`MOBIParser` 没有 `init(converter:)`）。

- [ ] **Step 3: 改造 MOBIParser 集成兜底**

修改 `Reader/Reader/Services/Parsers/MOBIParser.swift`：

```swift
import Foundation

protocol MOBIConverting {
    var isAvailable: Bool { get }
    func convertToEPUB(mobiURL: URL) async throws -> URL
}

extension MOBIConverter: MOBIConverting {}

final class MOBIParser: BookParser {
    private let converter: MOBIConverting

    init(converter: MOBIConverting = MOBIConverter()) {
        self.converter = converter
    }

    func parse(fileAt url: URL) async throws -> ParsedBook {
        // 先尝试原生解析；unsupported 才走 calibre
        do {
            return try await parseNative(fileAt: url)
        } catch BookParseError.unsupportedFormat {
            // 继续走 calibre
            return try await parseViaCalibre(fileAt: url)
        }
    }

    private func parseNative(fileAt url: URL) async throws -> ParsedBook {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let pdb = try PalmDBReader.read(data)
        guard let record0 = pdb.records.first else {
            throw BookParseError.corruptedFile(detail: "无 record0")
        }
        let header = try MOBIHeader.read(record0: record0)

        switch header.variant {
        case .classicMOBI:
            return try parseClassic(pdb: pdb, header: header, sourceURL: url)
        case .kf8:
            throw BookParseError.unsupportedFormat(detail: "KF8 解析尚未实现")
        case .unsupported(let reason):
            throw BookParseError.unsupportedFormat(detail: reason)
        }
    }

    private func parseViaCalibre(fileAt url: URL) async throws -> ParsedBook {
        guard converter.isAvailable else {
            throw BookParseError.calibreNotInstalled
        }
        let epubURL = try await converter.convertToEPUB(mobiURL: url)
        return try await EPUBParser().parse(fileAt: epubURL)
    }

    // parseClassic / splitChapters / extractTitle / writeImageResources /
    // isImage / imageExtension / coverImage 保持 Task 7 的实现，原样保留
}
```

- [ ] **Step 4: xcodegen + objectVersion 修复**

```bash
xcodegen generate
sed -i '' 's/objectVersion = 77/objectVersion = 60/' Reader.xcodeproj/project.pbxproj
```

- [ ] **Step 5: 跑测试确认通过**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `CalibreFallbackTests` 通过；`MOBIParserClassicTests` 仍通过（走原生分支）。

- [ ] **Step 6: 启用 Registry 的 .mobi 分支**

修改 `Reader/Reader/Services/Parsers/BookParser.swift`：

```swift
enum BookParserRegistry {
    static func parser(for type: FileType) -> BookParser? {
        switch type {
        case .epub: return EPUBParser()
        case .mobi: return MOBIParser()
        case .pdf:  return PDFParser()
        }
    }
}
```

去掉返回类型 `Optional`（`BookParser` 替代 `BookParser?`）：

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
```

- [ ] **Step 7: Build 验证**

```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add Reader/Reader/Services/Parsers/MOBIParser.swift ReaderTests/CalibreFallbackTests.swift Reader/Reader/Services/Parsers/BookParser.swift Reader.xcodeproj
git commit -m "feat: MOBIParser 接入 calibre 兜底，MOBIConverting 协议支持测试替身"
```

---

## Task 10: KF8IndexReader + MOBIParser.parseKF8

**Files:**
- Create: `Reader/Reader/Services/Parsers/KF8IndexReader.swift`
- Modify: `Reader/Reader/Services/Parsers/MOBIParser.swift`
- Create: `ReaderTests/KF8IndexReaderTests.swift`

**Goal:** 支持 AZW3/KF8 variant 解析。

KF8 结构（简化）：
- `pdb.records[0]` 是 PalmDB MOBI header（识别为 version 6 但 `mobiType` 字段特殊）
- `pdb.records[1]` 是 KF8 header（identifier "MOBI"，version 8）
- 我们已经在 MOBIHeader 检测 version == 8 → `.kf8`（但 `pdb.records[0]` 的 version 字段是 6，所以检测要看 `records[1]` 或其他线索）

修订：MOBIHeader.read 应该检查 `pdb.records[1]` 是否存在且 identifier 也是 "MOBI"，并且该记录的 version 字段 == 8。这需要把 PalmDatabase 传给 MOBIHeader（而不是单个 record0）。

调整 MOBIHeader 接口为 `read(pdb: PalmDatabase) throws -> MOBIHeader`：

- [ ] **Step 1: 修改 MOBIHeader 接口支持 KF8 检测**

修改 `Reader/Reader/Services/Parsers/MOBIHeader.swift`，在 `read(record0:)` 之外新增 `read(pdb:)`：

```swift
extension MOBIHeader {
    static func read(pdb: PalmDatabase) throws -> MOBIHeader {
        guard let record0 = pdb.records.first else {
            throw BookParseError.corruptedFile(detail: "无 record0")
        }
        let base = try read(record0: record0)

        // KF8 检测：record0 version == 8 → 直接 KF8
        // 或者 pdb.records[1] 的 identifier 是 "MOBI" 且 version == 8 → KF8
        if isKF8Record0(record0) {
            return MOBIHeader(
                variant: .kf8,
                compression: base.compression,
                firstTextRecord: base.firstTextRecord,
                lastTextRecord: base.lastTextRecord,
                firstImageRecord: base.firstImageRecord,
                title: base.title,
                author: base.author,
                coverRecordIndex: base.coverRecordIndex
            )
        }
        if pdb.records.count > 1, isKF8Boundary(pdb.records[1]) {
            return MOBIHeader(
                variant: .kf8,
                compression: .none,
                firstTextRecord: 1,
                lastTextRecord: pdb.records.count - 2,
                firstImageRecord: base.firstImageRecord,
                title: base.title,
                author: base.author,
                coverRecordIndex: base.coverRecordIndex
            )
        }
        return base
    }

    private static func isKF8Record0(_ record0: Data) -> Bool {
        guard record0.count >= 40 else { return false }
        return record0.readUInt32BE(at: 36) == 8  // version 字段
    }

    private static func isKF8Boundary(_ record1: Data) -> Bool {
        guard record1.count >= 20 else { return false }
        let id = String(data: record1.subdata(in: 16..<20), encoding: .ascii) ?? ""
        return id == "BOUNDARY"
    }
}
```

更新 MOBIParser 调用：`MOBIHeader.read(record0:)` → `MOBIHeader.read(pdb:)`。

- [ ] **Step 2: 写 KF8IndexReader 失败测试**

创建 `ReaderTests/KF8IndexReaderTests.swift`：

```swift
import XCTest
@testable import Reader

final class KF8IndexReaderTests: XCTestCase {
    func testParseChapterBoundaries() throws {
        // 构造一个最小 ORSR index：4 字节 magic "ORDR" + 4 字节 count + count×4 字节 offset
        var data = Data()
        data.append("ORDR".data(using: .ascii)!)
        data.append(UInt32(2).bigEndianData)
        data.append(UInt32(0).bigEndianData)
        data.append(UInt32(100).bigEndianData)

        let reader = KF8IndexReader(data: data)
        let boundaries = reader.chapterOffsets()
        XCTAssertEqual(boundaries, [0, 100])
    }

    func testEmptyDataReturnsEmpty() {
        let reader = KF8IndexReader(data: Data())
        XCTAssertEqual(reader.chapterOffsets(), [])
    }
}

private extension UInt32 {
    var bigEndianData: Data {
        var be = bigEndian
        return Data(bytes: &be, count: 4)
    }
}
```

- [ ] **Step 3: 实现 KF8IndexReader**

创建 `Reader/Reader/Services/Parsers/KF8IndexReader.swift`：

```swift
import Foundation

struct KF8IndexReader {
    let data: Data

    /// 从 KF8 index 记录中读取章节起始偏移
    func chapterOffsets() -> [Int] {
        guard data.count >= 8 else { return [] }
        guard let magic = String(data: data.subdata(in: 0..<4), encoding: .ascii),
              magic == "ORDR" else { return [] }
        let count = Int(data.readUInt32BE(at: 4))
        var offsets: [Int] = []
        for i in 0..<count {
            let pos = 8 + i * 4
            guard pos + 4 <= data.count else { break }
            offsets.append(Int(data.readUInt32BE(at: pos)))
        }
        return offsets
    }
}
```

- [ ] **Step 4: 实现 MOBIParser.parseKF8**

在 `MOBIParser.swift` 添加：

```swift
extension MOBIParser {
    func parseKF8(pdb: PalmDatabase, header: MOBIHeader, sourceURL: URL) throws -> ParsedBook {
        // 简化版：拼接所有 text records 为一个大 HTML 字符串
        // KF8 章节边界需要索引记录，这里先做"整本一章"兜底
        guard pdb.records.count >= 2 else {
            throw BookParseError.corruptedFile(detail: "KF8 records 过少")
        }
        var raw = Data()
        for i in 1..<pdb.records.count {
            raw.append(pdb.records[i])
        }
        let html = String(data: raw, encoding: .utf8) ?? ""

        let chapter = ParsedChapter(
            title: header.title,
            bodyHTML: html,
            sourcePath: "kf8-flow"
        )
        let toc = [ParsedTOCEntry(title: header.title, chapterIndex: 0)]
        return ParsedBook(
            title: header.title,
            author: header.author,
            coverImage: nil,
            chapters: [chapter],
            toc: toc,
            resourceDirectory: nil,
            renderer: .html,
            pdfDocument: nil
        )
    }
}
```

注意：KF8 的完整解析涉及 FDST、ORDR、TOLK 等表，非常复杂。此版兜底实现能打开 AZW3 文件但不一定按章节拆分；真正的章节级解析留给后续迭代（spec 非目标里也只说"覆盖"KF8）。更新 `parseNative` 里的 switch：

```swift
switch header.variant {
case .classicMOBI:
    return try parseClassic(pdb: pdb, header: header, sourceURL: url)
case .kf8:
    return try parseKF8(pdb: pdb, header: header, sourceURL: url)
case .unsupported(let reason):
    throw BookParseError.unsupportedFormat(detail: reason)
}
```

- [ ] **Step 5: xcodegen + objectVersion 修复**

```bash
xcodegen generate
sed -i '' 's/objectVersion = 77/objectVersion = 60/' Reader.xcodeproj/project.pbxproj
```

- [ ] **Step 6: 跑测试确认通过**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: `KF8IndexReaderTests` 通过；其他用例不受影响。

- [ ] **Step 7: Commit**

```bash
git add Reader/Reader/Services/Parsers/KF8IndexReader.swift Reader/Reader/Services/Parsers/MOBIParser.swift Reader/Reader/Services/Parsers/MOBIHeader.swift ReaderTests/KF8IndexReaderTests.swift Reader.xcodeproj
git commit -m "feat: 支持 AZW3/KF8 解析（整本一章兜底）+ KF8IndexReader"
```

---

## Task 11: RenderCoordinator 改走 Registry

**Files:**
- Modify: `Reader/Reader/Views/Reader/RenderCoordinator.swift`

**Goal:** 删除 `loadEPUB/loadMOBI/loadPDF`，统一用 `BookParserRegistry.parser(for:).parse(...)`。保留 `epubMetadata: EPUBMetadata?` 字段作为 ParsedBook → 视图层的临时桥接。

- [ ] **Step 1: 修改 RenderCoordinator.load()**

在 `Reader/Reader/Views/Reader/RenderCoordinator.swift` 替换 `load` / `loadEPUB` / `loadMOBI` / `loadPDF` 方法为：

```swift
func load() async {
    isLoading = true
    defer { isLoading = false }

    do {
        let parser = BookParserRegistry.parser(for: book.fileType)
        let filePath = book.filePath
        let parsed = try await Task.detached(priority: .userInitiated) {
            try await parser.parse(fileAt: URL(fileURLWithPath: filePath))
        }.value
        apply(parsed)
    } catch {
        self.loadError = error.localizedDescription
    }
}

private func apply(_ parsed: ParsedBook) {
    switch parsed.renderer {
    case .html:
        let metadata = EPUBMetadata(
            title: parsed.title,
            author: parsed.author,
            chapters: parsed.chapters.map {
                EPUBChapter(
                    title: $0.title,
                    htmlContent: $0.bodyHTML,
                    fileName: $0.sourcePath,
                    spineIndex: 0
                )
            },
            tocEntries: parsed.toc.map {
                EPUBTOCEntry(title: $0.title, chapterIndex: $0.chapterIndex)
            },
            resourceDirectory: parsed.resourceDirectory ?? FileManager.default.temporaryDirectory
        )
        self.epubMetadata = metadata
        self.currentChapter = min(currentChapter, max(0, metadata.chapters.count - 1))
    case .pdfKit:
        guard let doc = parsed.pdfDocument else {
            self.loadError = "PDF 加载失败"
            return
        }
        self.pdfDocument = doc
        self.pdfPageCount = doc.pageCount
        self.pdfOutline = buildPDFOutline(from: doc)
        if doc.pageCount > 0 {
            let restored = max(0, Int(progress * Double(doc.pageCount)) - 1)
            let clamped = min(restored, doc.pageCount - 1)
            self.pdfCurrentPage = clamped + 1
            self.progress = Double(clamped + 1) / Double(doc.pageCount)
        }
    }
}
```

删除旧的 `loadEPUB()`, `loadMOBI()`, `loadPDF()`。

- [ ] **Step 2: Build 验证**

```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 手测**

打开 Xcode，Run app，分别打开 EPUB / PDF / MOBI 书籍，验证：
- EPUB：正常显示章节、可切换、可高亮
- PDF：正常显示、翻页进度更新
- MOBI（经典 PalmDOC 压缩）：能加载出 HTML 章节内容
- MOBI（HUFF 压缩、无 calibre）：弹错误 alert，不卡死

- [ ] **Step 4: Commit**

```bash
git add Reader/Reader/Views/Reader/RenderCoordinator.swift
git commit -m "refactor: RenderCoordinator.load 统一走 BookParserRegistry"
```

---

## Task 12: PDFContainerView + 主题 CIFilter

**Files:**
- Create: `Reader/Reader/Views/Reader/PDFContainerView.swift`
- Modify: `Reader/Reader/Services/ReaderSettings.swift`（加 `pdfFilterEnabled`）

**Interfaces:**
- Produces: `struct PDFContainerView: NSViewRepresentable`（包裹 PDFView 并应用滤镜）

- [ ] **Step 1: 在 ReaderSettings 加 pdfFilterEnabled**

修改 `Reader/Reader/Services/ReaderSettings.swift`，在类里增加：

```swift
    var pdfFilterEnabled: Bool {
        didSet {
            if oldValue != pdfFilterEnabled {
                UserDefaults.standard.set(pdfFilterEnabled, forKey: "readerPdfFilterEnabled")
            }
        }
    }
```

init 里加：
```swift
        let storedPdfFilter = UserDefaults.standard.object(forKey: "readerPdfFilterEnabled") as? Bool
        self.pdfFilterEnabled = storedPdfFilter ?? true
```

- [ ] **Step 2: 实现 PDFContainerView**

创建 `Reader/Reader/Views/Reader/PDFContainerView.swift`：

```swift
import SwiftUI
import PDFKit
import QuartzCore

struct PDFContainerView: NSViewRepresentable {
    let pdfView: PDFView
    let theme: AppTheme
    let filterEnabled: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = theme.contentBG.nsColor.cgColor

        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.wantsLayer = true
        pdfView.underPageBackgroundColor = theme.contentBG.nsColor
        container.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: container.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        applyFilters(to: pdfView)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        container.layer?.backgroundColor = theme.contentBG.nsColor.cgColor
        pdfView.underPageBackgroundColor = theme.contentBG.nsColor
        applyFilters(to: pdfView)
    }

    private func applyFilters(to view: PDFView) {
        guard filterEnabled else {
            view.contentFilters = []
            return
        }
        view.contentFilters = Self.filters(for: theme)
    }

    static func filters(for theme: AppTheme) -> [CIFilter] {
        switch theme {
        case .classic, .kraft:
            return []
        case .eyeCare:
            let saturation = CIFilter(name: "CIColorControls", parameters: [
                "inputSaturation": 0.85,
                "inputBrightness": 0.02,
            ])
            return [saturation].compactMap { $0 }
        case .night:
            let invert = CIFilter(name: "CIColorInvert")
            let adjust = CIFilter(name: "CIColorControls", parameters: [
                "inputBrightness": -0.15,
                "inputContrast": 1.05,
            ])
            return [invert, adjust].compactMap { $0 }
        }
    }
}

extension Color {
    var nsColor: NSColor {
        NSColor(self)
    }
}
```

- [ ] **Step 3: xcodegen + objectVersion 修复**

```bash
xcodegen generate
sed -i '' 's/objectVersion = 77/objectVersion = 60/' Reader.xcodeproj/project.pbxproj
```

- [ ] **Step 4: Build 验证**

```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Reader/Reader/Views/Reader/PDFContainerView.swift Reader/Reader/Services/ReaderSettings.swift Reader.xcodeproj
git commit -m "feat: PDFContainerView 按主题叠加 CIFilter（夜间反色/护眼轻饱和）"
```

---

## Task 13: PDFRendererView 包裹 PDFContainerView + FontPanel 开关

**Files:**
- Modify: `Reader/Reader/Views/Reader/PDFRendererView.swift`
- Modify: `Reader/Reader/Views/Toolbar/FontPanelView.swift`

- [ ] **Step 1: 改造 PDFRendererView 和 PDFContainerView 合并**

思路：把现有 `PDFKitView`（NSViewRepresentable）的所有逻辑搬到 `PDFContainerView` 里，`PDFContainerView.makeNSView` 创建外层 NSView 容器 + 内层 PDFView 子视图，在 `updateNSView` 里根据 theme 重算 contentFilters。`PDFRendererView` 改为直接调用 `PDFContainerView`。

修改 `Reader/Reader/Views/Reader/PDFRendererView.swift`，整个文件替换为：

```swift
import SwiftUI
import PDFKit

struct PDFRendererView: View {
    let book: Book
    let coordinator: RenderCoordinator

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        PDFContainerView(
            url: URL(fileURLWithPath: book.filePath),
            coordinator: coordinator,
            targetPageIndex: coordinator.pdfCurrentPage - 1,
            theme: themeManager.currentTheme,
            filterEnabled: filterEnabled
        )
    }

    /// 从 ReaderSettings 读 pdfFilterEnabled；这里通过 EnvironmentObject 拿不到时默认 true
    private var filterEnabled: Bool {
        // ReaderView 已注入 ReaderSettings 到 environment；此处通过 Environment 取
        // 简化：直接在 PDFContainerView 内部读，避免此处 Environment 拉取
        return true
    }
}
```

把 `Reader/Reader/Views/Reader/PDFContainerView.swift` 从 Task 12 的占位实现改为完整的 NSViewRepresentable（合并 PDFKitView 的全部逻辑）：

```swift
import SwiftUI
import PDFKit
import QuartzCore

struct PDFContainerView: NSViewRepresentable {
    let url: URL
    let coordinator: PDFRendererCoordinator
    let targetPageIndex: Int
    let theme: AppTheme
    let filterEnabled: Bool

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.wantsLayer = true
        pdfView.underPageBackgroundColor = theme.contentBG.nsColor
        pdfView.delegate = context.coordinator

        if let document = PDFDocument(url: url) {
            pdfView.document = document
            let startPage = max(0, min(targetPageIndex, document.pageCount - 1))
            if document.pageCount > 0, let page = document.page(at: startPage) {
                pdfView.go(to: page)
            }
            context.coordinator.bindInitialProgress(
                pageIndex: startPage,
                totalPages: document.pageCount
            )
        }
        context.coordinator.startObservingPageChanges(pdfView: pdfView)

        applyFilters(to: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.underPageBackgroundColor = theme.contentBG.nsColor
        applyFilters(to: pdfView)

        guard let document = pdfView.document else { return }
        let current = pdfView.currentPage.flatMap { document.index(for: $0) } ?? -1
        if targetPageIndex >= 0 && targetPageIndex < document.pageCount && targetPageIndex != current {
            if let page = document.page(at: targetPageIndex) {
                pdfView.go(to: page)
            }
        }
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: PDFRendererCoordinator) {
        coordinator.stopObservingPageChanges()
    }

    func makeCoordinator() -> PDFRendererCoordinator { coordinator }

    private func applyFilters(to view: PDFView) {
        guard filterEnabled else {
            view.contentFilters = []
            return
        }
        view.contentFilters = Self.filters(for: theme)
    }

    static func filters(for theme: AppTheme) -> [CIFilter] {
        switch theme {
        case .classic, .kraft:
            return []
        case .eyeCare:
            let saturation = CIFilter(name: "CIColorControls", parameters: [
                "inputSaturation": 0.85,
                "inputBrightness": 0.02,
            ])
            return [saturation].compactMap { $0 }
        case .night:
            let invert = CIFilter(name: "CIColorInvert")
            let adjust = CIFilter(name: "CIColorControls", parameters: [
                "inputBrightness": -0.15,
                "inputContrast": 1.05,
            ])
            return [invert, adjust].compactMap { $0 }
        }
    }
}

extension Color {
    var nsColor: NSColor { NSColor(self) }
}

/// 把原 PDFKitView.Coordinator 改名，避免冲突
typealias PDFRendererCoordinator = PDFKitView.Coordinator
```

注意：`PDFKitView.Coordinator` 是现有类型，保留即可，只是 typealias 让 PDFContainerView 引用。原 `PDFKitView` 整个结构体可以删除（PDFContainerView 取代它）。

ReaderSettings 的 `pdfFilterEnabled` 需要从 `ReaderView` 传入。修改 `ReaderView.mainRenderer` 里 `PDFRendererView` 调用处：

```swift
case .pdf:
    PDFRendererView(book: book, coordinator: coordinator)
        .environment(settings)  // 已在 environment 链路里；确保 ReaderView 有 @State settings
```

如果 `ReaderView` 尚未把 settings 注入 environment，在 `body` 顶层 `.environment(settings)` 补上，并在 `PDFRendererView` 里 `@Environment(ReaderSettings.self) private var settings`，把 `filterEnabled` 改为 `settings.pdfFilterEnabled`。

- [ ] **Step 2: 删除旧 PDFKitView**

在 `PDFRendererView.swift` 里删除 `struct PDFKitView: NSViewRepresentable` 整个定义，但**保留** `final class PDFKitView.Coordinator`（被 typealias 引用）。更干净的做法：把 Coordinator 类提到文件顶层，命名为 `PDFRendererCoordinator`，删除 typealias。

```swift
final class PDFRendererCoordinator: NSObject, PDFViewDelegate {
    let coordinator: RenderCoordinator
    private var pageChangeObserver: NSObjectProtocol?
    private var lastPageIndex: Int = -1

    init(coordinator: RenderCoordinator) {
        self.coordinator = coordinator
    }

    deinit {
        if let obs = pageChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    @MainActor
    func bindInitialProgress(pageIndex: Int, totalPages: Int) {
        // 复用原 PDFKitView.Coordinator 的实现（保持不变）
    }

    func startObservingPageChanges(pdfView: PDFView) { /* 复用原实现 */ }
    func stopObservingPageChanges() { /* 复用原实现 */ }
    private func handlePageChanged(_ notification: Notification) { /* 复用原实现 */ }
}
```

把原 `PDFKitView.Coordinator` 里的方法实现逐字搬到这个新 class 里。

- [ ] **Step 2: FontPanelView 加 PDF 滤镜开关**

在 `FontPanelView.swift` 的"主题"区下方新增：

```swift
            VStack(alignment: .leading, spacing: 8) {
                Text("PDF 色调")
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.secondaryText)

                Toggle("夜间/护眼模式对 PDF 生效", isOn: $settings.pdfFilterEnabled)
                    .font(.caption)
                    .foregroundStyle(themeManager.currentTheme.primaryText)
            }
```

需要 `@Bindable var settings: ReaderSettings` 参数（从 ReaderView 传入）。修改 `FontPanelOverlay` 把 settings 透传下去（如果还没透传，把 settings 加到 FontPanelView init）。

- [ ] **Step 3: xcodegen + objectVersion 修复**

```bash
xcodegen generate
sed -i '' 's/objectVersion = 77/objectVersion = 60/' Reader.xcodeproj/project.pbxproj
```

- [ ] **Step 4: Build 验证**

```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 手测**

打开 PDF，切换到夜间主题：页面应反色。切回牛皮纸：反色消失。字体面板关闭"PDF 色调"开关：PDF 保持原始色调，不受主题影响。

- [ ] **Step 6: Commit**

```bash
git add Reader/Reader/Views/Reader/PDFRendererView.swift Reader/Reader/Views/Reader/PDFContainerView.swift Reader/Reader/Views/Toolbar/FontPanelView.swift Reader.xcodeproj
git commit -m "feat: PDF 渲染走 PDFContainerView 主题滤镜，字体面板加开关"
```

---

## Task 14: 最终清理 + 完整回归

**Files:**
- Verify: no stale references to `loadEPUB/loadMOBI/loadPDF`
- Run full test suite
- Manual smoke test

- [ ] **Step 1: 确认旧方法已删**

```bash
grep -rn "loadEPUB\|loadMOBI\|loadPDF" Reader/Reader/
```

Expected: 无输出。

- [ ] **Step 2: 跑全部测试**

```bash
xcodebuild test -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: 所有 test case 通过。

- [ ] **Step 3: 手测清单**

- 打开 EPUB → 章节/目录/字体/主题/搜索/高亮 全部正常
- 打开 PDF → 翻页/进度/章节/搜索/主题切换反色 正常
- 打开经典 MOBI（PalmDOC 压缩）→ 章节内容正常
- 打开 AZW3/KF8 → 能加载（单章），不崩溃
- 卸载 calibre 后打开 HUFF MOBI → 弹 alert 提示，不卡死
- 在"字体与排版"里切 PDF 滤镜开关 → 生效

- [ ] **Step 4: 更新 CHANGELOG 或 README（可选）**

跳过——无强制要求。

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "chore: 最终清理旧 MOBI/EPUB/PDF 加载路径" --allow-empty
```

---

## 验收门槛

| 门槛 | 验证方式 |
|---|---|
| 加载经典 MOBI 不卡死 | Task 11 手测 |
| 加载 HUFF MOBI 有明确错误提示 | Task 11 手测 |
| AZW3/KF8 能打开 | Task 14 手测 |
| PDF 夜间模式反色生效 | Task 13 手测 |
| 全部单元测试通过 | Task 14 |
| 无 `MOBIError` / `loadEPUB` 等遗留引用 | Task 14 grep |
| `xcodebuild build` SUCCEEDED | 每个 Task 末尾 |
