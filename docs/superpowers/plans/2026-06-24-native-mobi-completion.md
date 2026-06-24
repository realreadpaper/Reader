# Native MOBI/KF8 Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the remaining native direct MOBI work: classic MOBI resource mapping, basic TOC/guide, HUFF/CDIC handling, and real KF8/AZW3 reconstruction without external EPUB conversion.

**Architecture:** Keep `PalmDBReader` as the container reader and `MOBIHeader`/`MOBIContainerInspector` as metadata sources. Add small focused helpers around the existing `MOBIParser`: a resource mapper for record resources, a classic TOC extractor, and KF8 reconstruction helpers for `FDST`/flows before expanding index support.

**Tech Stack:** Swift 5.9, XCTest, Foundation `Data`, existing `ParsedBook`, existing WebKit HTML renderer.

---

## Scope Order

1. Classic MOBI resource mapping and HTML reference rewrite.
2. Classic MOBI basic TOC/guide extraction from headings, anchors, and pagebreaks.
3. HUFF/CDIC detection and native decompressor API, with fixture-backed decoder work.
4. KF8/AZW3 reconstruction from PalmDB records using `FDST`, rawML flows, CSS/image resources, and index markers.

## Task 1: Classic MOBI Resource Mapping

**Files:**
- Modify: `Reader/Reader/Services/Parsers/MOBIParser.swift`
- Modify: `ReaderTests/MOBIParserClassicTests.swift`

- [ ] Write failing test with a classic MOBI fixture containing a PNG image record and HTML reference `recindex:00001`.
- [ ] Verify the test fails because the HTML still contains `recindex:` or the resource file is absent.
- [ ] Update resource writing to map source record indexes to stable `images/record-<index>.<ext>` filenames.
- [ ] Rewrite common MOBI image references in HTML: `recindex:NNNNN`, `kindle:embed:NNNN`, and `filepos:` when a direct record can be inferred.
- [ ] Verify the test passes and all MOBI parser tests pass.
- [ ] Commit as `feat: map classic mobi image resources`.

## Task 2: Classic MOBI Basic TOC/Guide

**Files:**
- Modify: `Reader/Reader/Services/Parsers/MOBIParser.swift`
- Modify: `ReaderTests/MOBIParserClassicTests.swift`

- [ ] Write failing tests where `<h1 id="...">` and `<a name="...">` headings produce readable chapter titles and TOC entries.
- [ ] Verify the tests fail because current titles are only `第 N 页`.
- [ ] Extract chapter titles from heading/title tags after splitting.
- [ ] Preserve source anchors in `sourcePath` where possible.
- [ ] Build TOC from parsed chapter titles rather than generic page numbers.
- [ ] Verify the tests and MOBI parser tests pass.
- [ ] Commit as `feat: derive classic mobi toc from headings`.

## Task 3: HUFF/CDIC Decoder Boundary

**Files:**
- Modify: `Reader/Reader/Services/Parsers/MOBIDecompressor.swift`
- Modify: `Reader/Reader/Services/Parsers/MOBIHeader.swift`
- Create: `Reader/Reader/Services/Parsers/HUFFCDICDecoder.swift`
- Modify: `ReaderTests/MOBIDecompressorTests.swift`
- Modify: `ReaderTests/MOBIHeaderTests.swift`

- [ ] Write failing tests proving HUFF compression is routed to a native decoder rather than immediately returning unsupported.
- [ ] Add `HUFFCDICDecoder` with explicit table-loading API and clear `corruptedFile` errors when required dictionary records are missing.
- [ ] Change parser behavior so HUFF can proceed only when required HUFF/CDIC records are discovered.
- [ ] Add a compact fixture for an identity/minimal HUFF dictionary if the format records can be represented locally.
- [ ] Verify HUFF tests and all MOBI parser tests pass.
- [ ] Commit as `feat: add huff cdic decoder boundary`.

## Task 4: KF8 RawML/FDST Reconstruction Foundation

**Files:**
- Modify: `Reader/Reader/Services/Parsers/MOBIParser.swift`
- Create: `Reader/Reader/Services/Parsers/KF8Reconstructor.swift`
- Create: `ReaderTests/KF8ReconstructorTests.swift`

- [ ] Write failing tests for `FDST` flow table parsing and rawML flow extraction.
- [ ] Implement `KF8Reconstructor` that locates boundary, text records, `FDST`, and resource marker records.
- [ ] Reconstruct XHTML/CSS/image flow records without scanning for `PK`.
- [ ] Return `ParsedBook` chapters directly from reconstructed XHTML flows.
- [ ] Keep old ZIP scan only as a temporary compatibility fallback behind explicit logging.
- [ ] Verify KF8 tests and parser tests pass.
- [ ] Commit as `feat: reconstruct kf8 flows natively`.

## Task 5: Full Verification

**Files:**
- No source changes expected.

- [ ] Run:
  `xcodebuild -project Reader.xcodeproj -scheme Reader -destination 'platform=macOS' test -only-testing:ReaderTests/PalmDBReaderTests -only-testing:ReaderTests/MOBIHeaderTests -only-testing:ReaderTests/MOBIDecompressorTests -only-testing:ReaderTests/MOBIParserClassicTests -only-testing:ReaderTests/KF8IndexReaderTests -only-testing:ReaderTests/KF8ReconstructorTests -only-testing:ReaderTests/CalibreFallbackTests -only-testing:ReaderTests/MOBIContainerInspectorTests`
- [ ] Run the full test suite and record any unrelated failures.
- [ ] Confirm `git status --short` contains only user-owned unrelated files, or commit all implementation changes.
