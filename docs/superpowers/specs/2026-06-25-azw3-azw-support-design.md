# AZW3/AZW Format Support Design

Date: 2026-06-25

## Overview

Add native support for Kindle AZW3 and AZW formats as the 6th and 7th file types. Uses a `KindleParser` wrapper around the existing `MOBIParser` with DRM detection and calibre fallback.

## Background

- AZW3 is KF8 (Kindle Format 8) in a MOBI container — the existing `MOBIParser` already handles KF8 natively
- AZW is an older Kindle format, also a MOBI container — `MOBIParser` handles classic MOBI too
- Many AZW3/AZW files from Kindle Store have DRM protection that prevents native parsing
- The app already has a calibre fallback (`MOBIConverter`) for unsupported MOBI variants

## Design Decisions

1. **KindleParser wrapper** (not extending MOBIParser directly) — adds DRM detection layer before delegation
2. **Calibre fallback for DRM** — detect DRM early, skip native parse, go straight to calibre
3. **Distinct badges** — AZW3 and AZW get their own file type badges on the bookshelf
4. **Shared renderer** — both formats use EPUBRendererView (same as epub/mobi)

## Changes

### 1. FileType Enum (`Reader/Reader/Models/Enums.swift`)

Add two new cases:

```swift
case azw3
case azw
```

Update `fromFileExtension`:
```swift
case "azw3": return .azw3
case "azw": return .azw
```

Badge display is automatic — `BookRowView` uses `book.fileType.rawValue.uppercased()`.

### 2. KindleParser (`Reader/Reader/Services/Parsers/KindleParser.swift` — NEW)

New wrapper class:

```swift
final class KindleParser: BookParser {
    private let mobiParser: MOBIParser

    init(converter: MOBIConverting = MOBIConverter()) {
        self.mobiParser = MOBIParser(converter: converter)
    }

    func parse(fileAt url: URL) async throws -> ParsedBook {
        if try isDRMProtected(url) {
            return try await mobiParser.parseViaCalibre(fileAt: url)
        }
        return try await mobiParser.parse(fileAt: url)
    }

    private func isDRMProtected(_ url: URL) throws -> Bool {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let pdb = try PalmDBReader.read(data)
        let header = try MOBIHeader.read(pdb: pdb)
        return header.hasDRM
    }
}
```

### 3. MOBIHeader DRM Detection (`Reader/Reader/Services/Parsers/MOBIHeader.swift`)

Add `drmOffset` property (UInt32 at byte offset 168 in MOBI header):

```swift
let drmOffset: UInt32

var hasDRM: Bool {
    drmOffset != 0xFFFFFFFF && drmOffset != 0
}
```

### 4. MOBIParser Visibility (`Reader/Reader/Services/Parsers/MOBIParser.swift`)

Change `parseViaCalibre` from `private` to `internal` so KindleParser can call it.

### 5. BookParserRegistry (`Reader/Reader/Services/Parsers/BookParser.swift`)

Add dispatch:
```swift
case .azw3, .azw: return KindleParser()
```

### 6. ReaderView.mainRenderer (`Reader/Reader/Views/Reader/ReaderView.swift`)

Group azw3/azw with epub/mobi:
```swift
case .epub, .mobi, .azw3, .azw:
```

### 7. RenderCoordinator (`Reader/Reader/Views/Reader/RenderCoordinator.swift`)

Update both `totalChapters` and `displayCurrentPage`:
```swift
case .epub, .mobi, .azw3, .azw, .txt, .md:
```

### 8. ContentView Import Types (`Reader/Reader/Views/ContentView.swift`)

Add to `supportedImportTypes`:
```swift
if let azw3 = UTType(filenameExtension: "azw3") { types.append(azw3) }
if let azw = UTType(filenameExtension: "azw") { types.append(azw) }
```

### 9. FontPanelOverlay (`Reader/Reader/Views/Reader/ReaderView.swift`)

Group azw3/azw with epub/mobi (no PDF-specific options).

### 10. Error Messages (`Reader/Reader/Services/Parsers/BookParser.swift`)

Update `calibreNotInstalled` message:
```swift
return "原生解析不支持该格式，且未检测到 calibre。请安装 calibre 后重试。"
```

## Files Modified

| File | Change |
|------|--------|
| `Enums.swift` | Add `.azw3`, `.azw` cases + extension mapping |
| `KindleParser.swift` | NEW — wrapper with DRM detection |
| `MOBIHeader.swift` | Add `drmOffset` + `hasDRM` |
| `MOBIParser.swift` | Make `parseViaCalibre` internal |
| `BookParser.swift` | Add registry dispatch + update error message |
| `ReaderView.swift` | Update `mainRenderer` + FontPanelOverlay switches |
| `RenderCoordinator.swift` | Update page numbering switches |
| `ContentView.swift` | Add import types |

## Edge Cases

- **AZW that is classic MOBI**: MOBIParser handles via `MOBIVariant.classicMOBI` path
- **Corrupted file**: Throws `BookParseError.corruptedFile`
- **DRM + no calibre**: Throws `BookParseError.calibreNotInstalled`
- **Large files**: Uses `.mappedIfSafe` for memory efficiency

## Testing

1. Non-DRM AZW3 — native KF8 parse, render in EPUBRendererView
2. DRM AZW3 — detect DRM, calibre fallback, parse resulting EPUB
3. Non-DRM AZW — same as AZW3
4. DRM AZW — same DRM fallback path
5. Corrupted AZW3/AZW — throw corruptedFile
6. No calibre + DRM — throw calibreNotInstalled
7. Import picker — azw3/azw files appear in file dialog
8. Bookshelf badge — shows "AZW3" / "AZW" respectively
