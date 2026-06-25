import XCTest
@testable import Reader

final class MOBIParserClassicTests: XCTestCase {
    func testParseClassicMOBIReturnsHtmlBook() async throws {
        let html = "<html><body><h1>Fixture</h1><p>Fixture content here.</p></body></html>"
        let url = try makeClassicMOBIFixture(html: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertEqual(parsed.renderer, .html)
        XCTAssertEqual(parsed.title, "Fixture Title")
        XCTAssertEqual(parsed.author, "Fixture Author")
        XCTAssertFalse(parsed.chapters.isEmpty)
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("Fixture content"))
    }

    func testParseClassicMOBIDecodesChineseUTF8PalmDoc() async throws {
        let html = "<html><body><h1>简单的逻辑学</h1><p>逻辑是一门独立的学问。</p></body></html>"
        let url = try makeClassicMOBIFixture(html: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertFalse(parsed.chapters.isEmpty)
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("简单的逻辑学"))
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("逻辑是一门独立的学问"))
    }

    func testParseClassicMOBISplitsPageBreaksIntoPages() async throws {
        let html = """
        <html><body><p>第一页内容</p><mbp:pagebreak/><p>第二页内容</p></body></html>
        """
        let url = try makeClassicMOBIFixture(html: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertEqual(parsed.chapters.count, 2)
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("第一页内容"))
        XCTAssertTrue(parsed.chapters[1].bodyHTML.contains("第二页内容"))
        XCTAssertEqual(parsed.toc.map(\.title), ["第 1 页", "第 2 页"])
    }

    func testParseClassicMOBIContinuesPaginatingLongPageBreakSections() async throws {
        let longPage = (0..<420).map { "<p>第 \($0) 段内容，用来模拟一个很长的 MOBI 页面。</p>" }.joined()
        let html = "<html><body>\(longPage)<mbp:pagebreak/>\(longPage)</body></html>"
        let url = try makeClassicMOBIFixture(html: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertGreaterThan(parsed.chapters.count, 2)
        XCTAssertEqual(parsed.toc.first?.title, "第 1 页")
        XCTAssertEqual(parsed.toc.last?.title, "第 \(parsed.chapters.count) 页")
    }

    func testParseClassicMOBIStillWorksWithContainerDiagnosticsEnabled() async throws {
        let html = "<html><body><h1>Diagnostics</h1><p>Parser behavior is unchanged.</p></body></html>"
        let url = try makeClassicMOBIFixture(html: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertEqual(parsed.renderer, .html)
        XCTAssertEqual(parsed.title, "Fixture Title")
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("Parser behavior is unchanged."))
    }

    func testParseClassicMOBIStripsTrailingExtraDataBeforeDecoding() async throws {
        let firstChunk = "<html><body><h1>Clean Text</h1><p>"
        let secondChunk = "正文不能混入尾部控制数据。</p></body></html>"
        let tailPayload = Data("<span>TRAILING-NOISE</span>".utf8)
        let tailNoise = tailPayload + Data([UInt8(tailPayload.count)])
        let url = try makeClassicMOBIFixture(
            htmlChunks: [firstChunk, secondChunk],
            extraDataFlags: 0x0002,
            trailingTextRecordData: [tailNoise, Data([0x01])]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("正文不能混入尾部控制数据"))
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("<p>正文不能混入尾部控制数据"))
        XCTAssertFalse(parsed.chapters[0].bodyHTML.contains("TRAILING-NOISE"))
    }

    func testParseClassicMOBIRewritesRecindexImagesToResourceFiles() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
        let html = """
        <html><body><h1>Illustrated</h1><p><img src="recindex:00000"/></p></body></html>
        """
        let url = try makeClassicMOBIFixture(html: html, resourceRecords: [png])
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        let resourceDirectory = try XCTUnwrap(parsed.resourceDirectory)
        let imageURL = resourceDirectory.appendingPathComponent("images/record-2.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("images/record-2.png"))
        XCTAssertFalse(parsed.chapters[0].bodyHTML.contains("recindex:"))
    }

    func testParseClassicMOBIDerivesChapterTitlesAndTOCFromHeadings() async throws {
        let html = """
        <html><body>
        <h1 id="intro">引言</h1><p>第一章正文。</p>
        <h1 id="logic">逻辑学基础</h1><p>第二章正文。</p>
        </body></html>
        """
        let url = try makeClassicMOBIFixture(html: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertEqual(parsed.chapters.map(\.title), ["引言", "逻辑学基础"])
        XCTAssertEqual(parsed.toc.map(\.title), ["引言", "逻辑学基础"])
        XCTAssertEqual(parsed.toc.map(\.chapterIndex), [0, 1])
    }

    func testDecodeHTMLRepairsCP1252PunctuationInsideDeclaredUTF8HTML() {
        var raw = Data("<p>逻辑".utf8)
        raw.append(0x91)
        raw.append(Data("发现</p>".utf8))

        let html = MOBIParser.decodeHTML(raw, declaredEncoding: .utf8)

        XCTAssertTrue(html.contains("逻辑"))
        XCTAssertTrue(html.contains("‘"))
        XCTAssertTrue(html.contains("发现"))
        XCTAssertFalse(html.contains("é»"))
        XCTAssertFalse(html.contains("�"))
    }

    func testDecodeHTMLDiagnosticRepairsInvalidWindows1252ByteInsideUTF8HTML() {
        var raw = Data("<p>一个".utf8)
        raw.append(0x97)
        raw.append(Data("小时</p>".utf8))

        let diagnostic = MOBIParser.decodeHTMLWithDiagnostic(raw, declaredEncoding: .utf8)

        XCTAssertEqual(diagnostic.method, "utf8-html-repair-windowsCP1252")
        XCTAssertEqual(diagnostic.replacementCharacterCount, 0)
        XCTAssertTrue(diagnostic.html.contains("一个—小时"))
        XCTAssertFalse(diagnostic.html.contains("�"))
        XCTAssertTrue(diagnostic.summary.contains("method=utf8-html-repair-windowsCP1252"))
        XCTAssertTrue(diagnostic.summary.contains("replacementChars=0"))
    }

    func testDecodeHTMLFallsBackToGB18030WhenDeclaredUTF8HasTooManyInvalidBytes() throws {
        let raw = try XCTUnwrap("<html><body><p>逻辑是一门独立的学问。</p></body></html>".data(using: .gb18030))

        let diagnostic = MOBIParser.decodeHTMLWithDiagnostic(raw, declaredEncoding: .utf8)

        XCTAssertEqual(diagnostic.method, "gb18030")
        XCTAssertEqual(diagnostic.replacementCharacterCount, 0)
        XCTAssertTrue(diagnostic.html.contains("逻辑是一门独立的学问"))
        XCTAssertFalse(diagnostic.html.contains("�"))
    }

    func testDecodeHTMLUsesTolerantUTF8WhenDeclaredUTF8HasSparseInvalidBytes() {
        var raw = Data("<html><body><h1>长尾理论</h1><p>目录</p><p>互联网时代的选择和传播。</p>".utf8)
        raw.append(0x90) // CP1252 undefined byte; should not make the whole book fall back to GB18030.
        raw.append(Data("<p>继续保持中文可读。</p></body></html>".utf8))

        let diagnostic = MOBIParser.decodeHTMLWithDiagnostic(raw, declaredEncoding: .utf8)

        XCTAssertEqual(diagnostic.method, "utf8-lossy")
        XCTAssertTrue(diagnostic.html.contains("长尾理论"))
        XCTAssertTrue(diagnostic.html.contains("互联网时代的选择和传播"))
        XCTAssertTrue(diagnostic.html.contains("继续保持中文可读"))
        XCTAssertFalse(diagnostic.html.contains("闀垮熬鐞嗚"))
    }

    func testDecodeHTMLPrefersDeclaredGB18030OverAccidentalValidUTF8() throws {
        let raw = try XCTUnwrap("<html><body><p>一业之为也</p></body></html>".data(using: .gb18030))

        let diagnostic = MOBIParser.decodeHTMLWithDiagnostic(raw, declaredEncoding: .gb18030)

        XCTAssertEqual(diagnostic.method, "declared-gb18030")
        XCTAssertTrue(diagnostic.html.contains("一业之为也"))
        XCTAssertFalse(diagnostic.html.contains("һҵ֮ΪҲ"))
    }

    func testDecodeHTMLFallsBackToGB18030WhenCP1252DeclaredBytesAreAccidentalValidUTF8() throws {
        let raw = try XCTUnwrap("<html><body><p>一业之为也</p></body></html>".data(using: .gb18030))

        let diagnostic = MOBIParser.decodeHTMLWithDiagnostic(raw, declaredEncoding: .windowsCP1252)

        XCTAssertEqual(diagnostic.method, "gb18030")
        XCTAssertTrue(diagnostic.html.contains("一业之为也"))
        XCTAssertFalse(diagnostic.html.contains("һҵ֮ΪҲ"))
    }

    func testParseClassicMOBIDecodesGB18030BodyWhenHeaderDeclaresCP1252() async throws {
        let html = "<html><body><h1>简单的逻辑学</h1><p>逻辑是一门独立的学问。</p></body></html>"
        let url = try makeClassicMOBIFixture(
            html: html,
            textEncodingRaw: 1252,
            bodyEncoding: .gb18030
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MOBIParser().parse(fileAt: url)

        XCTAssertFalse(parsed.chapters.isEmpty)
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("简单的逻辑学"))
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("逻辑是一门独立的学问"))
        XCTAssertFalse(parsed.chapters[0].bodyHTML.contains("¼òµ¥"))
    }

    private func makeClassicMOBIFixture(
        html: String,
        textEncodingRaw: UInt32 = 65001,
        bodyEncoding: String.Encoding = .utf8,
        extraDataFlags: UInt32 = 0,
        trailingTextRecordData: Data = Data(),
        resourceRecords: [Data] = []
    ) throws -> URL {
        try makeClassicMOBIFixture(
            htmlChunks: [html],
            textEncodingRaw: textEncodingRaw,
            bodyEncoding: bodyEncoding,
            extraDataFlags: extraDataFlags,
            trailingTextRecordData: [trailingTextRecordData],
            resourceRecords: resourceRecords
        )
    }

    private func makeClassicMOBIFixture(
        htmlChunks: [String],
        textEncodingRaw: UInt32 = 65001,
        bodyEncoding: String.Encoding = .utf8,
        extraDataFlags: UInt32 = 0,
        trailingTextRecordData: [Data] = [],
        resourceRecords: [Data] = []
    ) throws -> URL {
        let htmlData = try XCTUnwrap(htmlChunks.joined().data(using: bodyEncoding))
        let textRecords = htmlChunks.enumerated().map { idx, chunk in
            let chunkData = chunk.data(using: bodyEncoding) ?? Data(chunk.utf8)
            return palmDocLiteralRecord(for: chunkData) + trailingTextRecordData[safe: idx, default: Data()]
        }

        var record0 = Data()
        var be16: UInt16
        var be32: UInt32

        // PalmDOC header (16 bytes)
        be16 = UInt16(2).bigEndian
        record0.append(Data(bytes: &be16, count: 2))       // compression = PalmDOC
        record0.append(Data(repeating: 0, count: 2))       // unused
        be32 = UInt32(htmlData.count).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // textLength
        be16 = UInt16(textRecords.count).bigEndian
        record0.append(Data(bytes: &be16, count: 2))       // recordCount
        be16 = UInt16(4096).bigEndian
        record0.append(Data(bytes: &be16, count: 2))       // recordSize
        record0.append(Data(repeating: 0, count: 4))       // encryption + unused

        // MOBI header
        record0.append("MOBI".data(using: .ascii)!)        // identifier
        be32 = UInt32(232).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // headerLength
        be32 = UInt32(0).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // mobiType
        be32 = textEncodingRaw.bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // textEncoding
        be32 = UInt32(1).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // uniqueID
        be32 = UInt32(6).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // fileVersion = 6 (classic)
        // firstTextRecord (record0 offset 44)
        be32 = UInt32(1).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        // lastTextRecord (record0 offset 48)
        be32 = UInt32(textRecords.count).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        // 填充到 MOBI header 总长 232
        // 已写 MOBI 部分: 4(identifier)+4(headerLen)+4(mobiType)+4(textEncoding)+4(uniqueID)+4(version)+4(firstText)+4(lastText) = 32 bytes
        // 剩 232-32 = 200 bytes
        record0.append(Data(repeating: 0, count: 200))
        if extraDataFlags != 0 {
            be32 = extraDataFlags.bigEndian
            record0.replaceSubrange(240..<244, with: Data(bytes: &be32, count: 4))
        }
        if !resourceRecords.isEmpty {
            be32 = UInt32(1 + textRecords.count).bigEndian
            record0.replaceSubrange(124..<128, with: Data(bytes: &be32, count: 4))
        }

        // EXTH block
        let exthStart = record0.count
        record0.append("EXTH".data(using: .ascii)!)
        let headerLenPos = record0.count
        be32 = UInt32(0).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        be32 = UInt32(2).bigEndian
        record0.append(Data(bytes: &be32, count: 4))       // record count
        // type 100 = author
        let authorData = "Fixture Author".data(using: .utf8)!
        be32 = UInt32(100).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        be32 = UInt32(8 + authorData.count).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        record0.append(authorData)
        // type 503 = updatedTitle
        let titleData = "Fixture Title".data(using: .utf8)!
        be32 = UInt32(503).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        be32 = UInt32(8 + titleData.count).bigEndian
        record0.append(Data(bytes: &be32, count: 4))
        record0.append(titleData)
        let exthLen = UInt32(record0.count - exthStart)
        var be = exthLen.bigEndian
        record0.replaceSubrange(headerLenPos..<(headerLenPos + 4), with: Data(bytes: &be, count: 4))

        // PalmDB
        var pdb = Data()
        var name = "Fixture".data(using: .ascii)!
        name.append(Data(repeating: 0x00, count: 32 - name.count))
        pdb.append(name)
        pdb.append(Data(repeating: 0, count: 28))          // attrs..sortInfo
        pdb.append("BOOK".data(using: .ascii)!)            // type
        pdb.append("MOBI".data(using: .ascii)!)            // creator
        pdb.append(Data(repeating: 0, count: 8))           // uniqueIDSeed + nextRecordListID
        let allRecords = [record0] + textRecords + resourceRecords
        be16 = UInt16(allRecords.count).bigEndian
        pdb.append(Data(bytes: &be16, count: 2))           // numRecords
        let headerSize = 78 + allRecords.count * 8 + 2
        var nextOffset = headerSize
        for record in allRecords {
            be32 = UInt32(nextOffset).bigEndian
            pdb.append(Data(bytes: &be32, count: 4))
            pdb.append(Data(repeating: 0, count: 4))
            nextOffset += record.count
        }
        pdb.append(Data(repeating: 0, count: 2))           // padding
        for record in allRecords {
            pdb.append(record)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mobi")
        try pdb.write(to: url)
        return url
    }

    private func palmDocLiteralRecord(for htmlData: Data) -> Data {
        let htmlBytes = Array(htmlData)
        var textRecord = Data()
        var idx = 0
        while idx < htmlBytes.count {
            let byte = htmlBytes[idx]
            if byte >= 0x09 && byte <= 0x7F {
                textRecord.append(byte)
                idx += 1
            } else {
                let start = idx
                idx += 1
                while idx < htmlBytes.count,
                      idx - start < 8,
                      !(htmlBytes[idx] >= 0x09 && htmlBytes[idx] <= 0x7F) {
                    idx += 1
                }
                textRecord.append(UInt8(idx - start))
                textRecord.append(contentsOf: htmlBytes[start..<idx])
            }
        }
        return textRecord
    }
}

private extension Array {
    subscript(safe index: Index, default defaultValue: Element) -> Element {
        indices.contains(index) ? self[index] : defaultValue
    }
}
