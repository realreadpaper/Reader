import Foundation
@_implementationOnly import cmark_gfm
@_implementationOnly import cmark_gfm_extensions

enum MarkdownRenderer {
    static func renderHTML(_ markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()

        let parser = cmark_parser_new(CMARK_OPT_DEFAULT)
        defer { cmark_parser_free(parser) }

        let extensionNames = ["autolink", "strikethrough", "tagfilter", "tasklist", "table"]
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        cmark_parser_feed(parser, markdown, markdown.utf8.count)

        guard let document = cmark_parser_finish(parser) else {
            return markdown
        }
        defer { cmark_node_free(document) }

        guard let html = cmark_render_html(document, CMARK_OPT_DEFAULT, nil) else {
            return markdown
        }
        defer { free(html) }

        return String(cString: html)
    }
}
