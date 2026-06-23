import SwiftUI
import WebKit

struct TXTRendererView: View {
    let book: Book
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var progress: Double
    let themeManager: ThemeManager

    var body: some View {
        TXTWebView(
            chapters: chapters,
            currentChapter: $currentChapter,
            progress: $progress,
            theme: themeManager.currentTheme
        )
    }
}

struct TXTWebView: NSViewRepresentable {
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var progress: Double
    let theme: AppTheme

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard currentChapter < chapters.count else { return }
        let chapter = chapters[currentChapter]

        if context.coordinator.lastChapter != currentChapter {
            context.coordinator.lastChapter = currentChapter
            let html = wrapHTML(chapter.htmlContent, theme: theme)
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    private func wrapHTML(_ content: String, theme: AppTheme) -> String {
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
                    font-family: "Menlo", "Courier New", monospace;
                    font-size: 14px;
                    line-height: 1.8;
                    background: \(theme.contentBG.hex);
                    color: \(theme.primaryText.hex);
                    white-space: pre-wrap;
                    word-wrap: break-word;
                }
                p { margin: 0.5em 0; }
            </style>
        </head>
        <body>\(content)</body>
        </html>
        """
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var lastChapter: Int = -1
    }
}
