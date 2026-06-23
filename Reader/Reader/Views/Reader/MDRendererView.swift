import SwiftUI
import WebKit

struct MDRendererView: View {
    let book: Book
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var progress: Double
    let themeManager: ThemeManager
    let storageService: StorageService

    @State private var isEditing = true
    @State private var editedContent: String = ""
    @State private var originalContent: String = ""
    @State private var hasUnsavedChanges = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Spacer()

                Button(action: { isEditing = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("编辑")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(isEditing ? themeManager.currentTheme.accent : Color.clear)
                    .foregroundStyle(isEditing ? .white : themeManager.currentTheme.secondaryText)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button(action: { isEditing = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                        Text("预览")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(!isEditing ? themeManager.currentTheme.accent : Color.clear)
                    .foregroundStyle(!isEditing ? .white : themeManager.currentTheme.secondaryText)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                if hasUnsavedChanges {
                    Button(action: saveChanges) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("保存")
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(themeManager.currentTheme.sidebarBG)

            if isEditing {
                MDEditorView(
                    content: $editedContent,
                    hasChanges: $hasUnsavedChanges,
                    theme: themeManager.currentTheme
                )
            } else {
                MDPreviewView(
                    content: editedContent,
                    theme: themeManager.currentTheme
                )
            }
        }
        .onAppear {
            loadContent()
        }
        .onChange(of: currentChapter) { _, _ in
            if hasUnsavedChanges {
                saveChanges()
            }
            loadContent()
        }
    }

    private func loadContent() {
        guard currentChapter < chapters.count else { return }
        let chapter = chapters[currentChapter]
        let html = chapter.htmlContent

        let plainText = html
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        originalContent = plainText
        editedContent = plainText
        hasUnsavedChanges = false
    }

    private func saveChanges() {
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
    }
}

struct MDEditorView: NSViewRepresentable {
    @Binding var content: String
    @Binding var hasChanges: Bool
    let theme: AppTheme

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = NSColor(theme.contentBG)
        textView.textColor = NSColor(theme.primaryText)
        textView.insertionPointColor = NSColor(theme.accent)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(theme.accent).withAlphaComponent(0.3)
        ]
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        textView.string = content

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != content && !context.coordinator.isEditing {
            textView.string = content
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MDEditorView
        var isEditing = false

        init(_ parent: MDEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            parent.content = textView.string
            parent.hasChanges = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isEditing = false
            }
        }
    }
}

struct MDPreviewView: NSViewRepresentable {
    let content: String
    let theme: AppTheme

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = markdownToHTML(content)
        let fullHTML = wrapHTML(html, theme: theme)
        webView.loadHTMLString(fullHTML, baseURL: nil)
    }

    private func markdownToHTML(_ markdown: String) -> String {
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

    private func wrapHTML(_ body: String, theme: AppTheme) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    max-width: 600px;
                    margin: 0 auto;
                    padding: 40px 20px;
                    font-family: -apple-system, "PingFang SC", "Songti SC", serif;
                    font-size: 15px;
                    line-height: 1.8;
                    background: \(theme.contentBG.hex);
                    color: \(theme.primaryText.hex);
                }
                h1, h2, h3, h4 { color: \(theme.primaryText.hex); margin-top: 1.5em; }
                h1 { font-size: 1.6em; }
                h2 { font-size: 1.3em; }
                h3 { font-size: 1.1em; }
                p { margin: 0.8em 0; }
                pre {
                    background: \(theme.border.hex);
                    padding: 12px;
                    border-radius: 6px;
                    overflow-x: auto;
                    font-size: 13px;
                }
                code {
                    font-family: "Menlo", monospace;
                    font-size: 0.9em;
                    background: \(theme.border.hex);
                    padding: 2px 4px;
                    border-radius: 3px;
                }
                pre code {
                    background: none;
                    padding: 0;
                }
                blockquote {
                    border-left: 3px solid \(theme.accent.hex);
                    margin: 1em 0;
                    padding: 0.5em 1em;
                    color: \(theme.secondaryText.hex);
                }
                a { color: \(theme.accent.hex); }
                hr { border: none; border-top: 1px solid \(theme.border.hex); margin: 1.5em 0; }
                li { margin: 0.3em 0; }
            </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}
