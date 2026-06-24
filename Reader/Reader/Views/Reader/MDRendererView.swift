import SwiftUI
import WebKit

struct MDRendererView: View {
    let book: Book
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var progress: Double
    let themeManager: ThemeManager
    let storageService: StorageService

    @State private var layoutMode: MDLayoutMode = .split
    @State private var editedContent: String = ""
    @State private var originalContent: String = ""
    @State private var hasUnsavedChanges = false

    enum MDLayoutMode: String, CaseIterable {
        case split = "分栏"
        case previewOnly = "纯预览"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(MDLayoutMode.allCases, id: \.self) { mode in
                        Button(action: { layoutMode = mode }) {
                            Image(systemName: layoutIcon(for: mode))
                                .font(.system(size: 12))
                                .frame(width: 28, height: 24)
                                .background(
                                    layoutMode == mode
                                        ? themeManager.currentTheme.accent
                                        : Color.clear
                                )
                                .foregroundStyle(
                                    layoutMode == mode
                                        ? .white
                                        : themeManager.currentTheme.secondaryText
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(themeManager.currentTheme.border.opacity(0.5))
                .cornerRadius(6)

                Spacer()

                Text("\(editedContent.count) 字")
                    .font(.caption2)
                    .foregroundStyle(themeManager.currentTheme.secondaryText)

                if hasUnsavedChanges {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(themeManager.currentTheme.sidebarBG)
            .overlay(alignment: .bottom) {
                Divider().background(themeManager.currentTheme.border)
            }

            switch layoutMode {
            case .split:
                SplitView(
                    content: $editedContent,
                    theme: themeManager.currentTheme
                )
            case .previewOnly:
                MDPreviewView(
                    content: editedContent,
                    theme: themeManager.currentTheme
                )
            }
        }
        .onAppear { loadContent() }
        .onChange(of: currentChapter) { _, _ in loadContent() }
    }

    private func loadContent() {
        guard currentChapter < chapters.count else { return }
        let chapter = chapters[currentChapter]
        originalContent = chapter.htmlContent
        editedContent = chapter.htmlContent
        hasUnsavedChanges = false
    }

    private func layoutIcon(for mode: MDLayoutMode) -> String {
        switch mode {
        case .split: return "rectangle.split.2x1"
        case .previewOnly: return "eye"
        }
    }
}

struct SplitView: View {
    @Binding var content: String
    let theme: AppTheme

    var body: some View {
        HSplitView {
            MDEditorView(
                content: $content,
                hasChanges: .constant(false),
                theme: theme
            )
            .frame(minWidth: 200)

            MDPreviewView(
                content: content,
                theme: theme
            )
            .frame(minWidth: 200)
        }
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
        textView.autoresizingMask = [.width, .height]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        textView.string = content

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if !context.coordinator.isTyping && textView.string != content {
            textView.string = content
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MDEditorView
        var isTyping = false
        private var updateTimer: Timer?

        init(_ parent: MDEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isTyping = true
            parent.content = textView.string
            parent.hasChanges = true

            updateTimer?.invalidate()
            updateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.isTyping = false
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
                pre code { background: none; padding: 0; }
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
