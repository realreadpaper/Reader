import Foundation

final class MDParser: BookParser {
    func parse(fileAt url: URL) async throws -> ParsedBook {
        let content = try String(contentsOf: url, encoding: .utf8)
        let title = url.deletingPathExtension().lastPathComponent

        let chapters = parseMarkdownToChapters(content, title: title)

        let toc = chapters.enumerated().map { idx, ch in
            ParsedTOCEntry(title: ch.title, chapterIndex: idx)
        }

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

    private func parseMarkdownToChapters(_ content: String, title: String) -> [ParsedChapter] {
        var chapters: [ParsedChapter] = []
        var currentTitle = title
        var currentContent = ""

        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            if line.hasPrefix("# ") {
                if !currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chapters.append(ParsedChapter(
                        title: currentTitle,
                        bodyHTML: markdownToHTML(currentContent),
                        sourcePath: "md-chapter-\(chapters.count)"
                    ))
                }
                currentTitle = String(line.dropFirst(2).trimmingCharacters(in: .whitespaces))
                currentContent = ""
            } else if line.hasPrefix("## ") || line.hasPrefix("### ") {
                if !currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chapters.append(ParsedChapter(
                        title: currentTitle,
                        bodyHTML: markdownToHTML(currentContent),
                        sourcePath: "md-chapter-\(chapters.count)"
                    ))
                }
                currentTitle = String(line.dropFirst(line.hasPrefix("### ") ? 4 : 3).trimmingCharacters(in: .whitespaces))
                currentContent = ""
            } else {
                currentContent += line + "\n"
            }
        }

        if !currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chapters.append(ParsedChapter(
                title: currentTitle,
                bodyHTML: markdownToHTML(currentContent),
                sourcePath: "md-chapter-\(chapters.count)"
            ))
        }

        if chapters.isEmpty {
            chapters.append(ParsedChapter(
                title: title,
                bodyHTML: markdownToHTML(content),
                sourcePath: "md-chapter-0"
            ))
        }

        return chapters
    }

    func markdownToHTML(_ markdown: String) -> String {
        var html = markdown

        html = html.replacingOccurrences(of: "&", with: "&amp;")
        html = html.replacingOccurrences(of: "<", with: "&lt;")
        html = html.replacingOccurrences(of: ">", with: "&gt;")

        let regexPatterns: [(pattern: String, template: String)] = [
            ("```(\\w*)\\n([\\s\\S]*?)```", "<pre><code>$2</code></pre>"),
            ("`([^`]+)`", "<code>$1</code>"),
            ("\\*\\*([^*]+)\\*\\*", "<strong>$1</strong>"),
            ("\\*([^*]+)\\*", "<em>$1</em>"),
            ("\\[([^\\]]+)\\]\\(([^)]+)\\)", "<a href=\"$2\">$1</a>"),
            ("^> (.+)$", "<blockquote>$1</blockquote>"),
            ("^---+$", "<hr>"),
            ("^(\\d+)\\. (.+)$", "<li>$2</li>"),
            ("^- (.+)$", "<li>$1</li>")
        ]

        for (pattern, template) in regexPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                let range = NSRange(html.startIndex..., in: html)
                html = regex.stringByReplacingMatches(in: html, range: range, withTemplate: template)
            }
        }

        let paragraphs = html.components(separatedBy: "\n\n")
        html = paragraphs.map { para -> String in
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "" }
            if trimmed.hasPrefix("<") { return trimmed }
            return "<p>\(trimmed)</p>"
        }.joined(separator: "\n")

        return html
    }
}
