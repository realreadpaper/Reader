import SwiftUI
import WebKit

struct EPUBRendererView: View {
    let book: Book
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var progress: Double
    let themeManager: ThemeManager

    var body: some View {
        EPUBWebView(
            chapters: chapters,
            currentChapter: $currentChapter,
            progress: $progress,
            theme: themeManager.currentTheme
        )
    }
}

struct EPUBWebView: NSViewRepresentable {
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var progress: Double
    let theme: AppTheme

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "readerBridge")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
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
                    max-width: 560px;
                    margin: 0 auto;
                    padding: 40px 20px;
                    font-family: -apple-system, "PingFang SC", "Songti SC", serif;
                    font-size: 16px;
                    line-height: 2.1;
                    background: \(theme.contentBG.hex);
                    color: \(theme.primaryText.hex);
                }
                h1, h2, h3 { color: \(theme.primaryText.hex); margin-top: 1.5em; }
                p { text-indent: 2em; margin-bottom: 1em; }
                img { max-width: 100%; height: auto; }
                .highlight-yellow { background-color: #E8D5A0; }
                .highlight-green { background-color: #C8E8D5; }
                .highlight-orange { background-color: #E8D0B8; }
                .highlight-blue { background-color: #C8D5E8; }
            </style>
        </head>
        <body>
            \(content)
            <script>
                document.addEventListener('selectionchange', function() {
                    var selection = window.getSelection();
                    if (selection.rangeCount > 0 && selection.toString().length > 0) {
                        var range = selection.getRangeAt(0);
                        var rect = range.getBoundingClientRect();
                        window.webkit.messageHandlers.readerBridge.postMessage({
                            type: 'selection',
                            text: selection.toString(),
                            x: rect.x,
                            y: rect.y,
                            width: rect.width,
                            height: rect.height
                        });
                    }
                });
            </script>
        </body>
        </html>
        """
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EPUBWebView
        var lastChapter: Int = -1

        init(_ parent: EPUBWebView) {
            self.parent = parent
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  body["type"] as? String == "selection" else { return }

            if let text = body["text"] as? String {
                NotificationCenter.default.post(
                    name: .textSelected,
                    object: nil,
                    userInfo: ["text": text]
                )
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
    }
}

extension Notification.Name {
    static let textSelected = Notification.Name("textSelected")
}
