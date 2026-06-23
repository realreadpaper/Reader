import XCTest
@testable import Reader

final class CalibreFallbackTests: XCTestCase {
    /// 直接调用 parseViaCalibre 测试 fallback 路径，避免 /dev/null 权限问题
    func testParseViaCalibreSuccessReturnsParsedBook() async throws {
        let stub = StubMOBIConverter(result: .success(epubFixtureURL()))
        let parser = MOBIParser(converter: stub)

        let parsed = try await parser.testParseViaCalibre(fileAt: URL(fileURLWithPath: "/tmp/ignored"))
        XCTAssertEqual(parsed.title, "Minimal Book")
    }

    func testParseViaCalibreThrowsWhenNotInstalled() async {
        let stub = StubMOBIConverter(result: .failure(BookParseError.calibreNotInstalled))
        let parser = MOBIParser(converter: stub)

        do {
            _ = try await parser.testParseViaCalibre(fileAt: URL(fileURLWithPath: "/tmp/ignored"))
            XCTFail("应抛错")
        } catch BookParseError.calibreNotInstalled {
            // 通过
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    private func epubFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/minimal.epub")
    }
}

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
