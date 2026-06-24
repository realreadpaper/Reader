import SwiftUI
import WebKit

struct TXTRendererView: View {
    let book: Book
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var progress: Double
    let themeManager: ThemeManager
    let settings: ReaderSettings
    let onSelection: (String, CGRect) -> Void
    let onPageReady: (() -> Void)?

    var body: some View {
        TXTWebView(
            chapters: chapters,
            currentChapter: $currentChapter,
            progress: $progress,
            theme: themeManager.currentTheme,
            fontSize: settings.fontSize,
            lineHeight: settings.lineHeight,
            onSelection: onSelection,
            onPageReady: onPageReady
        )
    }
}

struct TXTWebView: NSViewRepresentable {
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var progress: Double
    let theme: AppTheme
    let fontSize: Double
    let lineHeight: Double
    let onSelection: (String, CGRect) -> Void
    let onPageReady: (() -> Void)?

    private static let selectionJS = """
    (function() {
      if (window.__txtSelectionInstalled) return;
      window.__txtSelectionInstalled = true;
      function sendSelection() {
        try {
          var sel = window.getSelection();
          if (!sel || sel.rangeCount === 0) return;
          var text = sel.toString();
          if (!text || text.length === 0 || text.length > 5000) return;
          var range = sel.getRangeAt(0);
          var rect = range.getBoundingClientRect();
          if (rect.width === 0 && rect.height === 0) return;
          window.webkit.messageHandlers.readerBridge.postMessage({
            type: 'selection',
            text: text,
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height
          });
        } catch(e) {}
      }
      var debounceTimer = null;
      document.addEventListener('selectionchange', function() {
        if (debounceTimer) clearTimeout(debounceTimer);
        debounceTimer = setTimeout(sendSelection, 200);
      });

      var scrollTimer = null;
      window.addEventListener('scroll', function() {
        if (scrollTimer) clearTimeout(scrollTimer);
        scrollTimer = setTimeout(function() {
          try {
            var scrollHeight = document.documentElement.scrollHeight - document.documentElement.clientHeight;
            var p = scrollHeight > 0 ? window.scrollY / scrollHeight : 0;
            p = Math.max(0, Math.min(1, p));
            window.webkit.messageHandlers.readerBridge.postMessage({
              type: 'progress',
              progress: p
            });
          } catch(e) {}
        }, 150);
      });

      window.ReaderRestoreProgress = function(progress) {
        try {
          var scrollHeight = document.documentElement.scrollHeight - document.documentElement.clientHeight;
          var target = Math.max(0, Math.min(1, progress)) * scrollHeight;
          window.scrollTo({ top: target, behavior: 'auto' });
        } catch(e) {}
      };

      window.ReaderRestoreHighlights = function(highlights) {
        try {
          var existing = document.querySelectorAll('span[data-reader-highlight]');
          existing.forEach(function(el) {
            var parent = el.parentNode;
            if (!parent) return;
            parent.insertBefore(document.createTextNode(el.textContent || ''), el);
            parent.removeChild(el);
            parent.normalize();
          });

          if (!highlights || highlights.length === 0) return;

          highlights.forEach(function(hl) {
            var text = hl.text;
            var color = hl.color;
            if (!text || text.length === 0) return;
            var className = 'reader-highlight-' + color;

            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
            var node;
            while (node = walker.nextNode()) {
              var nodeText = node.nodeValue || '';
              var idx = nodeText.indexOf(text);
              if (idx < 0) continue;
              try {
                var range = document.createRange();
                range.setStart(node, idx);
                range.setEnd(node, idx + text.length);
                var span = document.createElement('span');
                span.className = className;
                span.setAttribute('data-reader-highlight', 'true');
                range.surroundContents(span);
              } catch(e) {}
            }
          });
        } catch(e) {}
      };

      window.ReaderScrollToHighlight = function(text) {
        try {
          if (!text) return;
          var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
          var node;
          while (node = walker.nextNode()) {
            var nodeText = node.nodeValue || '';
            var idx = nodeText.indexOf(text);
            if (idx < 0) continue;
            var range = document.createRange();
            range.setStart(node, idx);
            range.setEnd(node, idx + text.length);
            var rect = range.getBoundingClientRect();
            if (rect.width > 0 || rect.height > 0) {
              var scrollTop = window.scrollY + rect.top - window.innerHeight / 3;
              window.scrollTo({ top: Math.max(0, scrollTop), behavior: 'smooth' });
            }
            break;
          }
        } catch(e) {}
      };
    })();
    """

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "readerBridge")
        let script = WKUserScript(source: Self.selectionJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        userContent.addUserScript(script)
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.startObservingHighlightRequests()
        context.coordinator.startObservingRestoreProgress()
        context.coordinator.startObservingRestoreHighlights()
        context.coordinator.startObservingScrollToHighlight()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard currentChapter < chapters.count else { return }
        context.coordinator.parent = self

        let needsReload = context.coordinator.lastChapter != currentChapter
        let needsStyleUpdate = context.coordinator.lastFontSize != fontSize
            || context.coordinator.lastLineHeight != lineHeight
            || context.coordinator.lastThemeHex != theme.contentBG.hex

        if needsReload {
            context.coordinator.lastChapter = currentChapter
            context.coordinator.lastFontSize = fontSize
            context.coordinator.lastLineHeight = lineHeight
            context.coordinator.lastThemeHex = theme.contentBG.hex
            let html = wrapHTML(chapter.htmlContent, theme: theme)
            webView.loadHTMLString(html, baseURL: nil)
        } else if needsStyleUpdate {
            context.coordinator.lastFontSize = fontSize
            context.coordinator.lastLineHeight = lineHeight
            context.coordinator.lastThemeHex = theme.contentBG.hex
            let lh = String(format: "%.2f", lineHeight)
            let js = """
            document.body.style.fontSize = '\(fontSize)px';
            document.body.style.lineHeight = '\(lh)';
            document.body.style.background = '\(theme.contentBG.hex)';
            document.body.style.color = '\(theme.primaryText.hex)';
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObservingHighlightRequests()
        coordinator.stopObservingRestoreProgress()
        coordinator.stopObservingRestoreHighlights()
        coordinator.stopObservingScrollToHighlight()
        coordinator.webView = nil
    }

    private var chapter: EPUBChapter {
        chapters[currentChapter]
    }

    private func wrapHTML(_ content: String, theme: AppTheme) -> String {
        let lh = String(format: "%.2f", lineHeight)
        return """
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
                    font-size: \(fontSize)px;
                    line-height: \(lh);
                    background: \(theme.contentBG.hex);
                    color: \(theme.primaryText.hex);
                    white-space: pre-wrap;
                    word-wrap: break-word;
                }
                p { margin: 0.5em 0; }
                .reader-highlight-yellow { background-color: rgba(245, 213, 110, 0.55) !important; }
                .reader-highlight-green  { background-color: rgba(126, 200, 160, 0.55) !important; }
                .reader-highlight-orange { background-color: rgba(232, 168, 124, 0.55) !important; }
                .reader-highlight-blue   { background-color: rgba(160, 184, 232, 0.55) !important; }
            </style>
        </head>
        <body>\(content)</body>
        </html>
        """
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: TXTWebView
        weak var webView: WKWebView?
        var lastChapter: Int = -1
        var lastFontSize: Double = 0
        var lastLineHeight: Double = 0
        var lastThemeHex: String = ""
        private var highlightObserver: NSObjectProtocol?
        private var restoreProgressObserver: NSObjectProtocol?
        private var restoreHighlightsObserver: NSObjectProtocol?
        private var scrollToHighlightObserver: NSObjectProtocol?

        init(parent: TXTWebView) {
            self.parent = parent
        }

        deinit {
            if let obs = highlightObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            if let obs = restoreProgressObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            if let obs = restoreHighlightsObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            if let obs = scrollToHighlightObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        func startObservingHighlightRequests() {
            guard highlightObserver == nil else { return }
            highlightObserver = NotificationCenter.default.addObserver(
                forName: .applyHighlightRequest,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let className = notification.userInfo?["className"] as? String else { return }
                let escaped = className.replacingOccurrences(of: "'", with: "\\'")
                self.webView?.evaluateJavaScript(
                    """
                    (function() {
                      try {
                        var sel = window.getSelection();
                        if (!sel || sel.rangeCount === 0) return false;
                        var range = sel.getRangeAt(0);
                        if (range.collapsed) return false;
                        var span = document.createElement('span');
                        span.className = '\(escaped)';
                        span.setAttribute('data-reader-highlight', 'true');
                        range.surroundContents(span);
                        sel.removeAllRanges();
                        return true;
                      } catch(e) { return false; }
                    })();
                    """,
                    completionHandler: nil
                )
            }
        }

        func stopObservingHighlightRequests() {
            if let obs = highlightObserver {
                NotificationCenter.default.removeObserver(obs)
                highlightObserver = nil
            }
        }

        func startObservingRestoreProgress() {
            guard restoreProgressObserver == nil else { return }
            restoreProgressObserver = NotificationCenter.default.addObserver(
                forName: .epubRestoreProgress,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let progress = notification.userInfo?["progress"] as? Double else { return }
                self.webView?.evaluateJavaScript(
                    "window.ReaderRestoreProgress && window.ReaderRestoreProgress(\(progress));",
                    completionHandler: nil
                )
            }
        }

        func stopObservingRestoreProgress() {
            if let obs = restoreProgressObserver {
                NotificationCenter.default.removeObserver(obs)
                restoreProgressObserver = nil
            }
        }

        func startObservingRestoreHighlights() {
            guard restoreHighlightsObserver == nil else { return }
            restoreHighlightsObserver = NotificationCenter.default.addObserver(
                forName: .restoreHighlights,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let highlights = notification.userInfo?["highlights"] as? [Highlight] else { return }
                let data = highlights.compactMap { hl -> [String: String]? in
                    guard !hl.selectedText.isEmpty else { return nil }
                    return ["text": hl.selectedText, "color": hl.color.rawValue]
                }
                guard !data.isEmpty,
                      let jsonData = try? JSONSerialization.data(withJSONObject: data),
                      let jsonString = String(data: jsonData, encoding: .utf8) else { return }
                let escaped = jsonString.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                self.webView?.evaluateJavaScript(
                    "window.ReaderRestoreHighlights && window.ReaderRestoreHighlights(JSON.parse('\(escaped)'));",
                    completionHandler: nil
                )
            }
        }

        func stopObservingRestoreHighlights() {
            if let obs = restoreHighlightsObserver {
                NotificationCenter.default.removeObserver(obs)
                restoreHighlightsObserver = nil
            }
        }

        func startObservingScrollToHighlight() {
            guard scrollToHighlightObserver == nil else { return }
            scrollToHighlightObserver = NotificationCenter.default.addObserver(
                forName: .scrollToHighlight,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let text = notification.userInfo?["text"] as? String else { return }
                let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                self.webView?.evaluateJavaScript(
                    "window.ReaderScrollToHighlight && window.ReaderScrollToHighlight('\(escaped)');",
                    completionHandler: nil
                )
            }
        }

        func stopObservingScrollToHighlight() {
            if let obs = scrollToHighlightObserver {
                NotificationCenter.default.removeObserver(obs)
                scrollToHighlightObserver = nil
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "selection":
                guard let text = body["text"] as? String, !text.isEmpty else { return }
                let rect = CGRect(
                    x: body["x"] as? Double ?? 0,
                    y: body["y"] as? Double ?? 0,
                    width: body["width"] as? Double ?? 0,
                    height: body["height"] as? Double ?? 0
                )
                Task { @MainActor in
                    parent.onSelection(text, rect)
                }
            case "progress":
                if let p = body["progress"] as? Double {
                    Task { @MainActor in
                        parent.progress = p
                    }
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onPageReady?()
        }
    }
}
