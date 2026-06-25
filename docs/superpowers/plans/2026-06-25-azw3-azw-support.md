# AZW3/AZW Format Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add native support for Kindle AZW3 and AZW formats with DRM detection and calibre fallback.

**Architecture:** KindleParser wraps MOBIParser, checks DRM flags in MOBI header before delegating. DRM-protected files skip native parsing and go straight to calibre ebook-convert fallback.

**Tech Stack:** Swift, PalmDBReader, MOBIHeader, MOBIParser, MOBIConverter (calibre), UTType

## Global Constraints

- Follow existing Strategy + Registry pattern for format dispatch
- Reuse MOBIParser's KF8/classic MOBI parsing — no new binary parsing code
- DRM detection via MOBI header drmOffset field (offset 168 in record0)
- All switch statements on FileType must include `.azw3` and `.azw` cases
- Use `BookLog.mobi` for KindleParser logging with `KindleParser:` prefix

---

### Task 1: Add FileType Cases

**Files:**
- Modify: `Reader/Reader/Models/Enums.swift:3-19`

**Interfaces:**
- Produces: `FileType.azw3`, `FileType.azw` enum cases
- Produces: `FileType.fromFileExtension("azw3")` → `.azw3`, `FileType.fromFileExtension("azw")` → `.azw`

- [ ] **Step 1: Add azw3 and azw cases to FileType enum**

In `Reader/Reader/Models/Enums.swift`, add two new cases after `.md`:

```swift
enum FileType: String, Codable, CaseIterable {
    case epub
    case mobi
    case pdf
    case txt
    case md
    case azw3
    case azw
```

- [ ] **Step 2: Add extension mapping in fromFileExtension**

In the same file, add two new cases to the switch in `fromFileExtension`:

```swift
case "azw3": return .azw3
case "azw": return .azw
```

- [ ] **Step 3: Verify build compiles**

Run: `xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug build 2>&1 | tail -5`

Expected: Build succeeds. The new enum cases will cause switch statement warnings in other files — those are fixed in later tasks.

- [ ] **Step 4: Commit**

```bash
git add Reader/Reader/Models/Enums.swift
git commit -m "feat: add azw3 and azw FileType cases"
```

---

### Task 2: Add DRM Detection to MOBIHeader

**Files:**
- Modify: `Reader/Reader/Services/Parsers/MOBIHeader.swift:36-48`
- Test: `ReaderTests/MOBIHeaderTests.swift`

**Interfaces:**
- Produces: `MOBIHeader.drmOffset: UInt32`
- Produces: `MOBIHeader.hasDRM: Bool` — true when drmOffset is not 0xFFFFFFFF and not 0

- [ ] **Step 1: Write failing test for hasDRM**

In `ReaderTests/MOBIHeaderTests.swift`, add:

```swift
func testHasDRMFalseWhenOffsetIsFFFFFFFF() throws {
    let record0 = makeRecord0(
        compression: 2,
        mobiVersion: 8,
        exthRecords: [],
        drmOffset: 0xFFFFFFFF
    )
    let header = try MOBIHeader.read(record0: record0)
    XCTAssertFalse(header.hasDRM)
}

func testHasDRMFalseWhenOffsetIsZero() throws {
    let record0 = makeRecord0(
        compression: 2,
        mobiVersion: 8,
        exthRecords: [],
        drmOffset: 0
    )
    let header = try MOBIHeader.read(record0: record0)
    XCTAssertFalse(header.hasDRM)
}

func testHasDRMTrueWhenOffsetIsValid() throws {
    let record0 = makeRecord0(
        compression: 2,
        mobiVersion: 8,
        exthRecords: [],
        drmOffset: 168
    )
    let header = try MOBIHeader.read(record0: record0)
    XCTAssertTrue(header.hasDRM)
}
```

Also update the existing `makeRecord0` helper to accept a `drmOffset` parameter (default `0xFFFFFFFF`). The DRM offset is at byte offset 168 in record0 (MOBI header offset 152, since MOBI header starts at record0 offset 16). Add after the existing MOBI header fields:

```swift
// Pad to offset 168 (MOBI header offset 152 from start of MOBI at 16)
// Current position varies; ensure we reach byte 168
while data.count < 168 {
    data.append(0)
}
var drmBE = drmOffset.bigEndian
data.append(Data(bytes: &drmBE, count: 4))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Reader.xcodeproj -scheme Reader -only-testing:ReaderTests/MOBIHeaderTests test 2>&1 | tail -20`

Expected: New tests fail with "value of type 'MOBIHeader' has no member 'hasDRM'"

- [ ] **Step 3: Add drmOffset property to MOBIHeader**

In `Reader/Reader/Services/Parsers/MOBIHeader.swift`, add to the struct properties:

```swift
let drmOffset: UInt32

var hasDRM: Bool {
    drmOffset != 0xFFFFFFFF && drmOffset != 0
}
```

- [ ] **Step 4: Read drmOffset in MOBIHeader.read(record0:)**

In the `read(record0:)` method, after reading `extraDataFlags` (around line 97), add:

```swift
let drmOffset: UInt32 = record0.count >= 172 ? record0.readUInt32BE(at: 168) : 0xFFFFFFFF
```

- [ ] **Step 5: Pass drmOffset to all MOBIHeader initializers**

Update all `return MOBIHeader(...)` calls in `read(record0:)` and `read(pdb:)` to include `drmOffset: drmOffset`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild -project Reader.xcodeproj -scheme Reader -only-testing:ReaderTests/MOBIHeaderTests test 2>&1 | tail -20`

Expected: All tests pass including the new DRM tests.

- [ ] **Step 7: Commit**

```bash
git add Reader/Reader/Services/Parsers/MOBIHeader.swift ReaderTests/MOBIHeaderTests.swift
git commit -m "feat: add DRM detection to MOBIHeader via drmOffset field"
```

---

### Task 3: Make MOBIParser.parseViaCalibre Internal

**Files:**
- Modify: `Reader/Reader/Services/Parsers/MOBIParser.swift:61`

**Interfaces:**
- Produces: `MOBIParser.parseViaCalibre(fileAt:)` — accessible from same module

- [ ] **Step 1: Change access modifier**

In `Reader/Reader/Services/Parsers/MOBIParser.swift`, line 61, change:

```swift
private func parseViaCalibre(fileAt url: URL) async throws -> ParsedBook {
```

to:

```swift
func parseViaCalibre(fileAt url: URL) async throws -> ParsedBook {
```

- [ ] **Step 2: Verify build compiles**

Run: `xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Reader/Reader/Services/Parsers/MOBIParser.swift
git commit -m "refactor: make MOBIParser.parseViaCalibre internal for KindleParser access"
```

---

### Task 4: Create KindleParser

**Files:**
- Create: `Reader/Reader/Services/Parsers/KindleParser.swift`

**Interfaces:**
- Implements: `BookParser` protocol
- Consumes: `MOBIParser.parseViaCalibre(fileAt:)`, `MOBIParser.parse(fileAt:)`, `PalmDBReader.read(_:)`, `MOBIHeader.read(pdb:)`
- Produces: `KindleParser.parse(fileAt:)` → `ParsedBook`

- [ ] **Step 1: Create KindleParser.swift**

Create `Reader/Reader/Services/Parsers/KindleParser.swift`:

```swift
import Foundation

final class KindleParser: BookParser {
    private let mobiParser: MOBIParser

    init(converter: MOBIConverting = MOBIConverter()) {
        self.mobiParser = MOBIParser(converter: converter)
    }

    func parse(fileAt url: URL) async throws -> ParsedBook {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        BookLog.mobi.info("KindleParser: start url=\(url.lastPathComponent, privacy: .public) size=\(fileSize)")

        if (try? isDRMProtected(url)) == true {
            BookLog.mobi.notice("KindleParser: DRM detected, falling back to calibre")
            return try await mobiParser.parseViaCalibre(fileAt: url)
        }

        do {
            let result = try await mobiParser.parse(fileAt: url)
            BookLog.mobi.info("KindleParser: native OK chapters=\(result.chapters.count)")
            return result
        } catch {
            BookLog.mobi.error("KindleParser: native failed error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func isDRMProtected(_ url: URL) throws -> Bool {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let pdb = try PalmDBReader.read(data)
        let header = try MOBIHeader.read(pdb: pdb)
        BookLog.mobi.info("KindleParser: DRM check drmOffset=\(header.drmOffset) hasDRM=\(header.hasDRM)")
        return header.hasDRM
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

The file needs to be added to the Xcode project's compile sources. Build will auto-detect it if the file is in the correct directory.

- [ ] **Step 3: Verify build compiles**

Run: `xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Reader/Reader/Services/Parsers/KindleParser.swift
git commit -m "feat: add KindleParser with DRM detection and calibre fallback"
```

---

### Task 5: Register KindleParser in BookParserRegistry

**Files:**
- Modify: `Reader/Reader/Services/Parsers/BookParser.swift:40-49`

**Interfaces:**
- Produces: `BookParserRegistry.parser(for: .azw3)` → `KindleParser`
- Produces: `BookParserRegistry.parser(for: .azw)` → `KindleParser`

- [ ] **Step 1: Add registry dispatch**

In `Reader/Reader/Services/Parsers/BookParser.swift`, in the `parser(for:)` switch, add before the closing brace:

```swift
case .azw3, .azw: return KindleParser()
```

- [ ] **Step 2: Update calibreNotInstalled error message**

In the same file, update the `calibreNotInstalled` case:

```swift
case .calibreNotInstalled:
    return "原生解析不支持该格式，且未检测到 calibre。请安装 calibre 后重试。"
```

- [ ] **Step 3: Verify build compiles**

Run: `xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Reader/Reader/Services/Parsers/BookParser.swift
git commit -m "feat: register KindleParser for azw3/azw in BookParserRegistry"
```

---

### Task 6: Update Switch Statements in Views

**Files:**
- Modify: `Reader/Reader/Views/Reader/ReaderView.swift:177-248`
- Modify: `Reader/Reader/Views/Reader/RenderCoordinator.swift:193-209`

**Interfaces:**
- `.azw3` and `.azw` grouped with `.epub`, `.mobi` in renderer selection
- `.azw3` and `.azw` grouped with `.epub`, `.mobi`, `.txt`, `.md` in page numbering

- [ ] **Step 1: Update ReaderView.mainRenderer**

In `Reader/Reader/Views/Reader/ReaderView.swift`, line 178, change:

```swift
case .epub, .mobi:
```

to:

```swift
case .epub, .mobi, .azw3, .azw:
```

- [ ] **Step 2: Update RenderCoordinator.totalChapters**

In `Reader/Reader/Views/Reader/RenderCoordinator.swift`, line 195, change:

```swift
case .epub, .mobi, .txt, .md:
```

to:

```swift
case .epub, .mobi, .azw3, .azw, .txt, .md:
```

- [ ] **Step 3: Update RenderCoordinator.displayCurrentPage**

In the same file, line 204, change:

```swift
case .epub, .mobi, .txt, .md:
```

to:

```swift
case .epub, .mobi, .azw3, .azw, .txt, .md:
```

- [ ] **Step 4: Verify build compiles**

Run: `xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug build 2>&1 | tail -5`

Expected: Build succeeds with no warnings about missing switch cases.

- [ ] **Step 5: Commit**

```bash
git add Reader/Reader/Views/Reader/ReaderView.swift Reader/Reader/Views/Reader/RenderCoordinator.swift
git commit -m "feat: add azw3/azw to renderer and page numbering switches"
```

---

### Task 7: Add Import Types to ContentView

**Files:**
- Modify: `Reader/Reader/Views/ContentView.swift:5-14`

**Interfaces:**
- azw3 and azw files appear in the macOS file import dialog

- [ ] **Step 1: Add UTType entries**

In `Reader/Reader/Views/ContentView.swift`, in the `supportedImportTypes` closure, add after the markdown line:

```swift
if let azw3 = UTType(filenameExtension: "azw3") { types.append(azw3) }
if let azw = UTType(filenameExtension: "azw") { types.append(azw) }
```

- [ ] **Step 2: Verify build compiles**

Run: `xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Reader/Reader/Views/ContentView.swift
git commit -m "feat: add azw3/azw to supported import types"
```

---

### Task 8: Manual Integration Test

- [ ] **Step 1: Build and run the app in Xcode**

Open `Reader.xcodeproj`, select the Reader scheme, run on macOS.

- [ ] **Step 2: Test import a non-DRM AZW3 file**

If you have a non-DRM AZW3 file, import it via the file picker. Verify:
- File appears in the bookshelf with "AZW3" badge
- Content renders correctly in the HTML renderer
- Page navigation works

- [ ] **Step 3: Test import a non-DRM AZW file**

Same as above but with .azw extension. Verify "AZW" badge.

- [ ] **Step 4: Test DRM detection (if DRM file available)**

Import a DRM-protected AZW3. Verify:
- If calibre is installed: file converts and renders
- If calibre is not installed: shows error message "原生解析不支持该格式，且未检测到 calibre。请安装 calibre 后重试。"

- [ ] **Step 5: Run full test suite**

Run: `xcodebuild -project Reader.xcodeproj -scheme Reader test 2>&1 | tail -20`

Expected: All tests pass.
