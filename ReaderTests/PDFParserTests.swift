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
        let doc = PDFDocument()
        let page = PDFPage()
        doc.insert(page, at: 0)
        let pdfData = doc.dataRepresentation()!
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

    func testPDFRenderOptionsUseThemeBackgroundToAvoidBlackFlash() {
        let view = PDFView()

        PDFRenderOptions(theme: .classic, filterEnabled: false).apply(to: view)

        XCTAssertEqual(view.backgroundColor.readerHexString, "#FAF6EF")
        XCTAssertTrue(view.wantsLayer)
        XCTAssertEqual(view.layer?.backgroundColor?.readerHexString, "#FAF6EF")
    }

    func testPDFRenderOptionsStateSkipsUnchangedAppearance() {
        var state = PDFRenderOptionsState()
        let options = PDFRenderOptions(theme: .classic, filterEnabled: false)

        XCTAssertTrue(state.markIfChanged(options))
        XCTAssertFalse(state.markIfChanged(options))
        XCTAssertTrue(state.markIfChanged(PDFRenderOptions(theme: .night, filterEnabled: false)))
    }

    func testPDFScalePolicyRecomputesFromCurrentFitScale() {
        XCTAssertEqual(
            PDFScalePolicy.targetScale(fitScale: 0.8, userScale: 1.25),
            1.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            PDFScalePolicy.targetScale(fitScale: 0.5, userScale: 1.25),
            0.625,
            accuracy: 0.0001
        )
    }

    func testPDFScalePolicyUsesToleranceToAvoidTinyScaleChurn() {
        XCTAssertFalse(PDFScalePolicy.shouldUpdate(current: 1.0, target: 1.004))
        XCTAssertTrue(PDFScalePolicy.shouldUpdate(current: 1.0, target: 1.02))
    }
}

private extension CGColor {
    var readerHexString: String {
        NSColor(cgColor: self)?.readerHexString ?? "#000000"
    }
}

private extension NSColor {
    var readerHexString: String {
        guard let rgb = usingColorSpace(.deviceRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }
}
