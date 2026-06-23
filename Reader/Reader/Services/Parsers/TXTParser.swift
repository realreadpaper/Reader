import Foundation

final class TXTParser: BookParser {
    func parse(fileAt url: URL) async throws -> ParsedBook {
        let content = try String(contentsOf: url, encoding: .utf8)
        let title = url.deletingPathExtension().lastPathComponent

        let lines = content.components(separatedBy: .newlines)
        let chunks = splitIntoChunks(lines)

        let chapters: [ParsedChapter] = chunks.enumerated().map { idx, chunk in
            let html = chunk.map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    return "<br>"
                }
                return "<p>\(escapeHTML(line))</p>"
            }.joined(separator: "\n")

            return ParsedChapter(
                title: idx == 0 ? title : "第 \(idx + 1) 段",
                bodyHTML: html,
                sourcePath: "txt-chapter-\(idx)"
            )
        }

        let toc = chapters.enumerated().map { idx, ch in
            ParsedTOCEntry(title: ch.title, chapterIndex: idx)
        }

        return ParsedBook(
            title: title,
            author: nil,
            coverImage: nil,
            chapters: chapters,
            toc: toc,
            resourceDirectory: nil,
            renderer: .plaintext,
            pdfDocument: nil
        )
    }

    private func splitIntoChunks(_ lines: [String]) -> [[String]] {
        var chunks: [[String]] = []
        var current: [String] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty && !current.isEmpty {
                let joined = current.joined(separator: "\n")
                if joined.count > 5000 {
                    chunks.append(current)
                    current = []
                }
            }
            current.append(line)
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        if chunks.isEmpty {
            chunks.append(lines)
        }

        return chunks
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
