import Foundation
import PDFKit

final class PDFParser: BookParser {
    func parse(fileAt url: URL) async throws -> ParsedBook {
        BookLog.render.info("PDFParser: opening \(url.lastPathComponent, privacy: .public) path=\(url.path, privacy: .public)")

        guard FileManager.default.fileExists(atPath: url.path) else {
            BookLog.render.error("PDFParser: file does not exist at path")
            throw BookParseError.corruptedFile(detail: "PDF 文件不存在：\(url.lastPathComponent)")
        }

        guard let doc = PDFDocument(url: url) else {
            BookLog.render.error("PDFParser: PDFDocument(url:) returned nil - file may be corrupted or encrypted")
            throw BookParseError.corruptedFile(detail: "无法打开 PDF：\(url.lastPathComponent)。文件可能已损坏、加密或格式不支持。")
        }

        let pageCount = doc.pageCount
        BookLog.render.info("PDFParser: opened OK pages=\(pageCount)")

        guard pageCount > 0 else {
            throw BookParseError.corruptedFile(detail: "PDF 无页面内容：\(url.lastPathComponent)")
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

        let cover: Data? = {
            guard let page = doc.page(at: 0) else { return nil }
            let img = page.thumbnail(of: CGSize(width: 200, height: 280), for: .mediaBox)
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }()

        return ParsedBook(
            title: title,
            author: author,
            coverImage: cover,
            chapters: [chapter],
            toc: [tocEntry],
            resourceDirectory: nil,
            renderer: .pdfKit,
            pdfDocument: doc
        )
    }
}
