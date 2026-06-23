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
