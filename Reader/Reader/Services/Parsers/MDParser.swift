import Foundation

final class MDParser: BookParser {
    func parse(fileAt url: URL) async throws -> ParsedBook {
        let content = try String(contentsOf: url, encoding: .utf8)
        let title = url.deletingPathExtension().lastPathComponent
        let html = MarkdownRenderer.renderHTML(content)

        let chapters = [
            ParsedChapter(
                title: title,
                bodyHTML: html,
                sourcePath: "md-document",
                rawMarkdown: content
            )
        ]
        let toc = [ParsedTOCEntry(title: title, chapterIndex: 0)]

        return ParsedBook(
            title: title,
            author: nil,
            coverImage: nil,
            chapters: chapters,
            toc: toc,
            resourceDirectory: url.deletingLastPathComponent(),
            renderer: .markdown,
            pdfDocument: nil
        )
    }
}
