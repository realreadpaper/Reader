# Native MOBI Container Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native MOBI container inspector that reports format, compression, encoding, DRM, EXTH, resource, and KF8 structure signals without changing existing reading behavior.

**Architecture:** Add a focused `MOBIContainerInspector` module beside the existing MOBI parser files. It consumes the already parsed `PalmDatabase`, extracts diagnostic metadata from `record0` and known marker records, and returns a plain Swift value that tests and future parser stages can reuse. `MOBIParser` will log the diagnostics but continue using the existing parse flow.

**Tech Stack:** Swift 5.9, XCTest, existing `PalmDBReader`, existing `BookParseError`, existing `BookLog`.

---

## Scope

This plan implements Phase 1 from `docs/superpowers/specs/2026-06-24-native-mobi-direct-parser-design.md`.

Included:

- New `MOBIContainerInspector`.
- New `MOBIContainerInfo` diagnostic model.
- Unit tests with synthetic PalmDB/MOBI fixtures.
- Logging diagnostics from `MOBIParser.parseNative`.

Excluded:

- No HUFF/CDIC decompression implementation.
- No KF7 resource rewriting.
- No KF8 FDST/skeleton/fragment reconstruction.
- No change to default calibre fallback behavior.
- No UI changes.

## File Structure

- Create `Reader/Reader/Services/Parsers/MOBIContainerInspector.swift`
  - Defines `MOBIContainerInfo`, `MOBIEXTHEntry`, `MOBIRecordMarker`, `MOBIDRMStatus`, and `MOBIContainerInspector`.
  - Parses record0 offsets, EXTH records, common MOBI fields, DRM status, KF8 boundary, and known marker records.

- Modify `Reader/Reader/Services/Parsers/MOBIParser.swift`
  - Calls `MOBIContainerInspector.inspect(pdb:)` inside `parseNative`.
  - Logs one compact diagnostic summary.
  - Does not change parser branching or output.

- Create `ReaderTests/MOBIContainerInspectorTests.swift`
  - Builds minimal in-memory MOBI/PalmDB fixtures.
  - Verifies classic MOBI fields, EXTH metadata, DRM detection, KF8 boundary detection, and marker record discovery.

---

### Task 1: Add MOBI Container Diagnostic Model

**Files:**
- Create: `Reader/Reader/Services/Parsers/MOBIContainerInspector.swift`
- Test: `ReaderTests/MOBIContainerInspectorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ReaderTests/MOBIContainerInspectorTests.swift` with this content:

```swift
import XCTest
@testable import Reader

final class MOBIContainerInspectorTests: XCTestCase {
    func testInspectClassicMOBIReportsHeaderAndEXTHFields() throws {
        let pdb = try PalmDBFixtureBuilder(
            mobiVersion: 6,
            compression: 2,
            textEncoding: 936,
            textRecordCount: 2,
            encryptionType: 0,
            extraDataFlags: 0x0003,
            firstImageRecord: 3,
            exthRecords: [
                (100, Data("Author Name".utf8)),
                (503, Data("Book Title".utf8)),
                (201, UInt32(1).beData)
            ],
            extraRecords: [
                Data("<html>one</html>".utf8),
                Data("<html>two</html>".utf8),
                Data([0xFF, 0xD8, 0xFF, 0xE0])
            ]
        ).build()

        let info = try MOBIContainerInspector.inspect(pdb: pdb)

        XCTAssertEqual(info.name, "Fixture")
        XCTAssertEqual(info.type, "BOOK")
        XCTAssertEqual(info.creator, "MOBI")
        XCTAssertEqual(info.recordCount, 4)
        XCTAssertEqual(info.compressionRaw, 2)
        XCTAssertEqual(info.compression, .palmDoc)
        XCTAssertEqual(info.mobiVersion, 6)
        XCTAssertEqual(info.variant, .classicMOBI)
        XCTAssertEqual(info.textEncodingRaw, 936)
        XCTAssertEqual(info.textRecordCount, 2)
        XCTAssertEqual(info.textRecordRange, 1...2)
        XCTAssertEqual(info.extraDataFlags, 0x0003)
        XCTAssertEqual(info.firstImageRecord, 3)
        XCTAssertEqual(info.coverRecordIndex, 4)
        XCTAssertEqual(info.drmStatus, .none)
        XCTAssertEqual(info.exthTitle, "Book Title")
        XCTAssertEqual(info.exthAuthor, "Author Name")
        XCTAssertFalse(info.hasKF8Boundary)
        XCTAssertTrue(info.markers.isEmpty)
    }

    func testInspectDetectsDRMFromPalmDOCEncryptionType() throws {
        let pdb = try PalmDBFixtureBuilder(
            mobiVersion: 6,
            compression: 2,
            textEncoding: 65001,
            textRecordCount: 1,
            encryptionType: 1,
            extraDataFlags: 0,
            firstImageRecord: 0,
            exthRecords: [],
            extraRecords: [Data("<html>encrypted</html>".utf8)]
        ).build()

        let info = try MOBIContainerInspector.inspect(pdb: pdb)

        XCTAssertEqual(info.drmStatus, .encrypted(type: 1))
    }

    func testInspectDetectsKF8BoundaryAndMarkerRecords() throws {
        var boundary = Data(repeating: 0, count: 16)
        boundary.append("BOUNDARY".data(using: .ascii)!)

        let pdb = try PalmDBFixtureBuilder(
            mobiVersion: 6,
            compression: 1,
            textEncoding: 65001,
            textRecordCount: 1,
            encryptionType: 0,
            extraDataFlags: 0,
            firstImageRecord: 0,
            exthRecords: [],
            extraRecords: [
                boundary,
                Data("FDST".utf8) + UInt32(16).beData,
                Data("INDX".utf8) + UInt32(24).beData,
                Data("RESC".utf8) + UInt32(32).beData
            ]
        ).build()

        let info = try MOBIContainerInspector.inspect(pdb: pdb)

        XCTAssertEqual(info.variant, .kf8)
        XCTAssertTrue(info.hasKF8Boundary)
        XCTAssertEqual(info.kf8BoundaryRecordIndex, 1)
        XCTAssertTrue(info.markers.contains(MOBIRecordMarker(kind: "FDST", recordIndex: 2)))
        XCTAssertTrue(info.markers.contains(MOBIRecordMarker(kind: "INDX", recordIndex: 3)))
        XCTAssertTrue(info.markers.contains(MOBIRecordMarker(kind: "RESC", recordIndex: 4)))
    }

    func testInspectThrowsForMissingRecord0() {
        let pdb = PalmDatabase(name: "Empty", type: "BOOK", creator: "MOBI", records: [])

        XCTAssertThrowsError(try MOBIContainerInspector.inspect(pdb: pdb)) { error in
            guard case BookParseError.corruptedFile(let detail) = error else {
                XCTFail("错误类型不对：\(error)")
                return
            }
            XCTAssertTrue(detail.contains("record0"))
        }
    }
}

private struct PalmDBFixtureBuilder {
    let mobiVersion: UInt32
    let compression: UInt16
    let textEncoding: UInt32
    let textRecordCount: UInt16
    let encryptionType: UInt16
    let extraDataFlags: UInt32
    let firstImageRecord: UInt32
    let exthRecords: [(UInt32, Data)]
    let extraRecords: [Data]

    func build() throws -> PalmDatabase {
        let record0 = makeRecord0()
        return PalmDatabase(
            name: "Fixture",
            type: "BOOK",
            creator: "MOBI",
            records: [record0] + extraRecords
        )
    }

    private func makeRecord0() -> Data {
        var data = Data()
        data.append(compression.beData)
        data.append(UInt16(0).beData)
        data.append(UInt32(2048).beData)
        data.append(textRecordCount.beData)
        data.append(UInt16(4096).beData)
        data.append(encryptionType.beData)
        data.append(UInt16(0).beData)

        data.append("MOBI".data(using: .ascii)!)
        data.append(UInt32(232).beData)
        data.append(UInt32(2).beData)
        data.append(textEncoding.beData)
        data.append(UInt32(1).beData)
        data.append(mobiVersion.beData)

        appendPadding(toRecord0Offset: 124, data: &data)
        data.append(firstImageRecord.beData)

        appendPadding(toRecord0Offset: 240, data: &data)
        data.replaceSubrange(240..<244, with: extraDataFlags.beData)

        appendPadding(toRecord0Offset: 248, data: &data)

        if !exthRecords.isEmpty {
            let exthStart = data.count
            data.append("EXTH".data(using: .ascii)!)
            data.append(UInt32(0).beData)
            data.append(UInt32(exthRecords.count).beData)
            for (type, value) in exthRecords {
                data.append(type.beData)
                data.append(UInt32(8 + value.count).beData)
                data.append(value)
            }
            let exthLength = UInt32(data.count - exthStart)
            data.replaceSubrange((exthStart + 4)..<(exthStart + 8), with: exthLength.beData)
        }

        return data
    }

    private func appendPadding(toRecord0Offset target: Int, data: inout Data) {
        if data.count < target {
            data.append(Data(repeating: 0, count: target - data.count))
        }
    }
}

private extension UInt16 {
    var beData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: 2)
    }
}

private extension UInt32 {
    var beData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: 4)
    }
}
```

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' test -only-testing:ReaderTests/MOBIContainerInspectorTests
```

Expected: build fails with `Cannot find 'MOBIContainerInspector' in scope`.

- [ ] **Step 3: Add the diagnostic model and inspector**

Create `Reader/Reader/Services/Parsers/MOBIContainerInspector.swift` with this content:

```swift
import Foundation

struct MOBIContainerInfo: Equatable {
    let name: String
    let type: String
    let creator: String
    let recordCount: Int
    let recordSizes: [Int]
    let compressionRaw: UInt16
    let compression: MOBICompression
    let mobiIdentifier: String
    let mobiHeaderLength: Int
    let mobiType: UInt32
    let mobiVersion: UInt32
    let variant: MOBIVariant
    let textEncodingRaw: UInt32
    let textLength: Int
    let textRecordCount: Int
    let textRecordRange: ClosedRange<Int>?
    let extraDataFlags: UInt32
    let firstImageRecord: Int?
    let drmStatus: MOBIDRMStatus
    let exthRecords: [MOBIEXTHEntry]
    let exthTitle: String?
    let exthAuthor: String?
    let coverRecordIndex: Int?
    let hasKF8Boundary: Bool
    let kf8BoundaryRecordIndex: Int?
    let markers: [MOBIRecordMarker]

    var diagnosticSummary: String {
        let textRange = textRecordRange.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "nil"
        let markerText = markers.map { "\($0.kind)@\($0.recordIndex)" }.joined(separator: ",")
        return [
            "records=\(recordCount)",
            "variant=\(variant)",
            "compression=\(compressionRaw)",
            "version=\(mobiVersion)",
            "encoding=\(textEncodingRaw)",
            "textRange=\(textRange)",
            "extraFlags=0x\(String(extraDataFlags, radix: 16))",
            "drm=\(drmStatus)",
            "firstImage=\(firstImageRecord.map(String.init) ?? "nil")",
            "kf8Boundary=\(kf8BoundaryRecordIndex.map(String.init) ?? "nil")",
            "markers=\(markerText.isEmpty ? "none" : markerText)"
        ].joined(separator: " ")
    }
}

struct MOBIEXTHEntry: Equatable {
    let type: UInt32
    let data: Data

    var utf8String: String? {
        String(data: data, encoding: .utf8)
    }

    var uint32Value: UInt32? {
        guard data.count >= 4 else { return nil }
        return data.readUInt32BE(at: 0)
    }
}

struct MOBIRecordMarker: Equatable {
    let kind: String
    let recordIndex: Int
}

enum MOBIDRMStatus: Equatable, CustomStringConvertible {
    case none
    case encrypted(type: UInt16)

    var description: String {
        switch self {
        case .none:
            return "none"
        case .encrypted(let type):
            return "encrypted(\(type))"
        }
    }
}

enum MOBIContainerInspector {
    static func inspect(pdb: PalmDatabase) throws -> MOBIContainerInfo {
        guard let record0 = pdb.records.first else {
            throw BookParseError.corruptedFile(detail: "无 record0")
        }
        guard record0.count >= 40 else {
            throw BookParseError.corruptedFile(detail: "record0 过短：\(record0.count) bytes")
        }

        let compressionRaw = record0.readUInt16BE(at: 0)
        let compression = compressionKind(raw: compressionRaw)
        let textLength = Int(record0.readUInt32BE(at: 4))
        let textRecordCount = Int(record0.readUInt16BE(at: 8))
        let encryptionType = record0.readUInt16BE(at: 12)
        let drmStatus: MOBIDRMStatus = encryptionType == 0 ? .none : .encrypted(type: encryptionType)
        let mobiIdentifier = String(data: record0.readBytes(at: 16, length: 4), encoding: .ascii) ?? ""
        let mobiHeaderLength = Int(record0.readUInt32BE(at: 20))
        let mobiType = record0.readUInt32BE(at: 24)
        let textEncodingRaw = record0.readUInt32BE(at: 28)
        let mobiVersion = record0.readUInt32BE(at: 36)
        let extraDataFlags = record0.count >= 244 ? record0.readUInt32BE(at: 240) : 0
        let firstImageRaw = record0.count >= 128 ? Int(record0.readUInt32BE(at: 124)) : 0
        let firstImageRecord = firstImageRaw > 0 ? firstImageRaw : nil
        let exthRecords = readEXTHEntries(record0: record0, mobiHeaderLength: mobiHeaderLength)
        let coverOffset = exthRecords.first(where: { $0.type == 201 })?.uint32Value.map(Int.init)
        let coverRecordIndex: Int? = {
            guard let firstImageRecord, let coverOffset else { return nil }
            return firstImageRecord + coverOffset
        }()
        let kf8BoundaryRecordIndex = findKF8Boundary(in: pdb.records)
        let variant: MOBIVariant = {
            if compression == .huff {
                return .unsupported("HUFF/CDIC 压缩暂未原生实现")
            }
            if mobiVersion == 8 || kf8BoundaryRecordIndex != nil {
                return .kf8
            }
            if [0, 1, 2].contains(compressionRaw) {
                return .classicMOBI
            }
            return .unsupported("未知 MOBI 变体（compression=\(compressionRaw), version=\(mobiVersion)）")
        }()
        let textRecordRange: ClosedRange<Int>? = {
            guard textRecordCount > 0 else { return nil }
            return 1...min(textRecordCount, max(1, pdb.records.count - 1))
        }()

        return MOBIContainerInfo(
            name: pdb.name,
            type: pdb.type,
            creator: pdb.creator,
            recordCount: pdb.records.count,
            recordSizes: pdb.records.map(\.count),
            compressionRaw: compressionRaw,
            compression: compression,
            mobiIdentifier: mobiIdentifier,
            mobiHeaderLength: mobiHeaderLength,
            mobiType: mobiType,
            mobiVersion: mobiVersion,
            variant: variant,
            textEncodingRaw: textEncodingRaw,
            textLength: textLength,
            textRecordCount: textRecordCount,
            textRecordRange: textRecordRange,
            extraDataFlags: extraDataFlags,
            firstImageRecord: firstImageRecord,
            drmStatus: drmStatus,
            exthRecords: exthRecords,
            exthTitle: exthRecords.first(where: { $0.type == 503 })?.utf8String,
            exthAuthor: exthRecords.first(where: { $0.type == 100 })?.utf8String,
            coverRecordIndex: coverRecordIndex,
            hasKF8Boundary: kf8BoundaryRecordIndex != nil,
            kf8BoundaryRecordIndex: kf8BoundaryRecordIndex,
            markers: findMarkers(in: pdb.records)
        )
    }

    private static func compressionKind(raw: UInt16) -> MOBICompression {
        switch raw {
        case 1:
            return .none
        case 2:
            return .palmDoc
        case 17480:
            return .huff
        default:
            return .none
        }
    }

    private static func readEXTHEntries(record0: Data, mobiHeaderLength: Int) -> [MOBIEXTHEntry] {
        let exthStart = 16 + mobiHeaderLength
        guard exthStart + 12 <= record0.count else { return [] }
        guard String(data: record0.readBytes(at: exthStart, length: 4), encoding: .ascii) == "EXTH" else {
            return []
        }

        let exthLength = Int(record0.readUInt32BE(at: exthStart + 4))
        let exthCount = Int(record0.readUInt32BE(at: exthStart + 8))
        let exthEnd = min(record0.count, exthStart + exthLength)
        var entries: [MOBIEXTHEntry] = []
        var offset = exthStart + 12
        for _ in 0..<exthCount {
            guard offset + 8 <= exthEnd else { break }
            let type = record0.readUInt32BE(at: offset)
            let length = Int(record0.readUInt32BE(at: offset + 4))
            guard length >= 8, offset + length <= exthEnd else { break }
            entries.append(MOBIEXTHEntry(
                type: type,
                data: record0.subdata(in: (offset + 8)..<(offset + length))
            ))
            offset += length
        }
        return entries
    }

    private static func findKF8Boundary(in records: [Data]) -> Int? {
        for (index, record) in records.enumerated() where record.count >= 20 {
            if String(data: record.readBytes(at: 16, length: 4), encoding: .ascii) == "BOUN" ||
               String(data: record.readBytes(at: 16, length: 8), encoding: .ascii) == "BOUNDARY" {
                return index
            }
        }
        return nil
    }

    private static func findMarkers(in records: [Data]) -> [MOBIRecordMarker] {
        let known = Set(["FDST", "INDX", "FLIS", "FCIS", "RESC", "SRCS", "DATP"])
        var markers: [MOBIRecordMarker] = []
        for (index, record) in records.enumerated() where record.count >= 4 {
            guard let kind = String(data: record.prefix(4), encoding: .ascii), known.contains(kind) else {
                continue
            }
            markers.append(MOBIRecordMarker(kind: kind, recordIndex: index))
        }
        return markers
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' test -only-testing:ReaderTests/MOBIContainerInspectorTests
```

Expected: all four `MOBIContainerInspectorTests` tests pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add Reader/Reader/Services/Parsers/MOBIContainerInspector.swift ReaderTests/MOBIContainerInspectorTests.swift
git commit -m "feat: add mobi container inspector"
```

---

### Task 2: Log Diagnostics During MOBI Native Parse

**Files:**
- Modify: `Reader/Reader/Services/Parsers/MOBIParser.swift`
- Test: `ReaderTests/MOBIParserClassicTests.swift`

- [ ] **Step 1: Write a regression test proving existing classic parse still works**

Modify `ReaderTests/MOBIParserClassicTests.swift` by adding this test inside `MOBIParserClassicTests`:

```swift
func testParseClassicMOBIStillWorksWithContainerDiagnosticsEnabled() async throws {
    let html = "<html><body><h1>Diagnostics</h1><p>Parser behavior is unchanged.</p></body></html>"
    let url = try makeClassicMOBIFixture(html: html)
    defer { try? FileManager.default.removeItem(at: url) }

    let parsed = try await MOBIParser().parse(fileAt: url)

    XCTAssertEqual(parsed.renderer, .html)
    XCTAssertEqual(parsed.title, "Fixture Title")
    XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("Parser behavior is unchanged."))
}
```

- [ ] **Step 2: Run the regression test before changing parser logging**

Run:

```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' test -only-testing:ReaderTests/MOBIParserClassicTests/testParseClassicMOBIStillWorksWithContainerDiagnosticsEnabled
```

Expected: PASS before implementation because behavior has not changed.

- [ ] **Step 3: Add diagnostic logging without changing parse decisions**

Modify `Reader/Reader/Services/Parsers/MOBIParser.swift` inside `parseNative(fileAt:)`.

Replace this block:

```swift
let header = try MOBIHeader.read(pdb: pdb)
BookLog.mobi.info("parseNative: header variant=\(String(describing: header.variant), privacy: .public) compression=\(String(describing: header.compression), privacy: .public) textRange=\(header.firstTextRecord)-\(header.lastTextRecord) firstImage=\(header.firstImageRecord.map(String.init) ?? "nil", privacy: .public) title=\(header.title, privacy: .public)")
```

With this block:

```swift
if let info = try? MOBIContainerInspector.inspect(pdb: pdb) {
    BookLog.mobi.info("parseNative: container \(info.diagnosticSummary, privacy: .public)")
}
let header = try MOBIHeader.read(pdb: pdb)
BookLog.mobi.info("parseNative: header variant=\(String(describing: header.variant), privacy: .public) compression=\(String(describing: header.compression), privacy: .public) textRange=\(header.firstTextRecord)-\(header.lastTextRecord) firstImage=\(header.firstImageRecord.map(String.init) ?? "nil", privacy: .public) title=\(header.title, privacy: .public)")
```

This keeps `MOBIHeader.read(pdb:)` as the authority for current parsing behavior. A diagnostics failure must not break existing parse behavior during Phase 1.

- [ ] **Step 4: Run targeted MOBI tests**

Run:

```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' test -only-testing:ReaderTests/MOBIParserClassicTests -only-testing:ReaderTests/MOBIContainerInspectorTests
```

Expected: all targeted tests pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add Reader/Reader/Services/Parsers/MOBIParser.swift ReaderTests/MOBIParserClassicTests.swift
git commit -m "chore: log mobi container diagnostics"
```

---

### Task 3: Add Full Regression Verification

**Files:**
- No source changes expected.

- [ ] **Step 1: Run all parser-related tests**

Run:

```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' test -only-testing:ReaderTests/PalmDBReaderTests -only-testing:ReaderTests/MOBIHeaderTests -only-testing:ReaderTests/MOBIDecompressorTests -only-testing:ReaderTests/MOBIParserClassicTests -only-testing:ReaderTests/KF8IndexReaderTests -only-testing:ReaderTests/CalibreFallbackTests -only-testing:ReaderTests/MOBIContainerInspectorTests
```

Expected: all selected parser tests pass.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' test
```

Expected: test suite passes. If unrelated UI or environment tests fail, capture the exact failing test names and failure messages before deciding whether the implementation is complete.

- [ ] **Step 3: Confirm the git diff contains only Phase 1 work**

Run:

```bash
git status --short
git diff --stat HEAD
```

Expected:

- Source/test changes are limited to:
  - `Reader/Reader/Services/Parsers/MOBIContainerInspector.swift`
  - `Reader/Reader/Services/Parsers/MOBIParser.swift`
  - `ReaderTests/MOBIContainerInspectorTests.swift`
  - `ReaderTests/MOBIParserClassicTests.swift`
- Existing unrelated files such as Xcode user state and `dist/` are not staged or modified by this work.

- [ ] **Step 4: Leave verification as a no-op commit step**

Do not create a commit in this step. If Step 2 found a real issue, return to Task 1 or Task 2, make the fix in the relevant file, rerun that task's verification command, and use that task's commit command.

Expected: `git status --short` still shows no additional Phase 1 changes beyond the commits from Task 1 and Task 2.

---

## Plan Self-Review

- Spec coverage for Phase 1: covered by `MOBIContainerInspector`, tests, and parser logging.
- Explicitly deferred Phase 2 HUFF/CDIC, extra data assembly, KF7 resource mapping, and Phase 3 KF8 reconstruction to future plans.
- No parser behavior changes are planned in this phase.
- Types introduced in tests match implementation names:
  - `MOBIContainerInspector`
  - `MOBIContainerInfo`
  - `MOBIEXTHEntry`
  - `MOBIRecordMarker`
  - `MOBIDRMStatus`
- Verification commands use the existing Xcode project and `Reader` scheme.
