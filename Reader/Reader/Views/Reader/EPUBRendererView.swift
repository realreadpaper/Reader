import SwiftUI
import WebKit

struct EPUBRendererView: View {
    let book: Book
    let chapters: [EPUBChapter]
    let resourceDirectory: URL?
    @Binding var currentChapter: Int
    @Binding var progress: Double
    let themeManager: ThemeManager
    let settings: ReaderSettings
    let onSelection: (String, CGRect) -> Void

    var body: some View {
        EPUBWebView(
            chapters: chapters,
            resourceDirectory: resourceDirectory,
            currentChapter: $currentChapter,
            progress: $progress,
            theme: themeManager.currentTheme,
            fontSize: settings.fontSize,
            lineHeight: settings.lineHeight,
            onSelection: onSelection
        )
    }
}

struct EPUBWebView: NSViewRepresentable {
    let chapters: [EPUBChapter]
    let resourceDirectory: URL?
    @Binding var currentChapter: Int
    @Binding var progress: Double
    let theme: AppTheme
    let fontSize: Double
    let lineHeight: Double
    let onSelection: (String, CGRect) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "readerBridge")

        let bootScript = WKUserScript(
            source: EPUBScripts.bootScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContent.addUserScript(bootScript)

        config.userContentController = userContent
        config.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = true

        context.coordinator.webView = webView
        context.coordinator.startObservingHighlightRequests()

        if !chapters.isEmpty {
            context.coordinator.loadChapter(
                index: currentChapter,
                chapters: chapters,
                resourceDirectory: resourceDirectory
            )
            context.coordinator.lastChapter = currentChapter
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard !chapters.isEmpty else { return }

        if context.coordinator.lastChapter != currentChapter {
            context.coordinator.lastChapter = currentChapter
            context.coordinator.loadChapter(
                index: currentChapter,
                chapters: chapters,
                resourceDirectory: resourceDirectory
            )
        } else {
            context.coordinator.applyStyles(
                theme: theme,
                fontSize: fontSize,
                lineHeight: lineHeight
            )
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: EPUBWebView.Coordinator) {
        coordinator.stopObservingHighlightRequests()
        coordinator.webView = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: EPUBWebView
        weak var webView: WKWebView?
        var lastChapter: Int = -1
        private var appliedTheme: String = ""
        private var appliedFontSize: Double = 0
        private var appliedLineHeight: Double = 0
        private var highlightObserver: NSObjectProtocol?

        init(parent: EPUBWebView) {
            self.parent = parent
        }

        deinit {
            if let obs = highlightObserver {
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
                self.applyHighlight(className: className)
                self.clearSelection()
            }
        }

        func stopObservingHighlightRequests() {
            if let obs = highlightObserver {
                NotificationCenter.default.removeObserver(obs)
                highlightObserver = nil
            }
        }

        func loadChapter(index: Int, chapters: [EPUBChapter], resourceDirectory: URL?) {
            guard index >= 0, index < chapters.count else { return }
            let chapter = chapters[index]
            let webView = self.webView

            if let resourceDir = resourceDirectory {
                let chapterURL = resourceDir.appendingPathComponent(chapter.fileName)
                if FileManager.default.fileExists(atPath: chapterURL.path) {
                    let dir = chapterURL.deletingLastPathComponent()
                    webView?.loadFileURL(chapterURL, allowingReadAccessTo: dir)
                    return
                }
            }

            let wrapped = EPUBScripts.wrapHTML(
                body: chapter.htmlContent,
                theme: parent.theme,
                fontSize: parent.fontSize,
                lineHeight: parent.lineHeight
            )
            let baseURL = resourceDirectory
            webView?.loadHTMLString(wrapped, baseURL: baseURL)
        }

        func applyStyles(theme: AppTheme, fontSize: Double, lineHeight: Double) {
            let themeKey = theme.rawValue
            guard appliedTheme != themeKey
                    || appliedFontSize != fontSize
                    || appliedLineHeight != lineHeight else { return }
            appliedTheme = themeKey
            appliedFontSize = fontSize
            appliedLineHeight = lineHeight

            let bg = theme.contentBG.hex
            let fg = theme.primaryText.hex
            let lh = String(format: "%.2f", lineHeight)
            let js = "window.ReaderApplyStyles && window.ReaderApplyStyles('\(bg)', '\(fg)', \(fontSize), '\(lh)');"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        // MARK: - WKScriptMessageHandler

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
                parent.onSelection(text, rect)

            case "progress":
                let p = body["value"] as? Double ?? 0
                Task { @MainActor in
                    parent.progress = p
                }

            default:
                break
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyStyles(
                theme: parent.theme,
                fontSize: parent.fontSize,
                lineHeight: parent.lineHeight
            )
        }

        // MARK: - JS helpers for host code

        func applyHighlight(className: String) {
            guard let webView else { return }
            let escaped = className.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("window.ReaderWrapSelection('\(escaped)');", completionHandler: nil)
        }

        func clearSelection() {
            webView?.evaluateJavaScript("window.ReaderClearSelection();", completionHandler: nil)
        }
    }
}

// MARK: - Injected JS/CSS

enum EPUBScripts {
    static func wrapHTML(body: String, theme: AppTheme, fontSize: Double, lineHeight: Double) -> String {
        let bg = theme.contentBG.hex
        let fg = theme.primaryText.hex
        let lh = String(format: "%.2f", lineHeight)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        \(cssTemplate)
        </style>
        </head>
        <body>
        \(body)
        <script>
        \(bootScript)
        </script>
        </body>
        </html>
        """
    }

    /// 注入到 EPUB 章节的 CSS 模板，CSS 变量在运行时由 `applyStyles` 覆盖
    static let cssTemplate: String = """
    :root {
      --reader-bg: #F5EFE3;
      --reader-fg: #2E2518;
      --reader-font-size: 16px;
      --reader-line-height: 2.10;
    }
    html, body {
      background: var(--reader-bg) !important;
    }
    body, p, li, dd, dt, blockquote, figcaption, cite, span, div, a:link {
      color: var(--reader-fg) !important;
    }
    body {
      max-width: 560px !important;
      margin: 0 auto !important;
      padding: 40px 24px 120px !important;
      font-family: -apple-system, "PingFang SC", "Songti SC", "Noto Serif CJK SC", serif !important;
      font-size: var(--reader-font-size) !important;
      line-height: var(--reader-line-height) !important;
      word-wrap: break-word !important;
      -webkit-text-size-adjust: 100% !important;
    }
    p, li {
      font-size: 1em !important;
      line-height: var(--reader-line-height) !important;
      text-indent: 2em !important;
      margin-bottom: 1em !important;
    }
    h1, h2, h3, h4, h5, h6 {
      color: var(--reader-fg) !important;
      margin-top: 1.5em !important;
      margin-bottom: 0.8em !important;
      line-height: 1.4 !important;
    }
    h1 { font-size: 1.6em !important; }
    h2 { font-size: 1.4em !important; }
    h3 { font-size: 1.2em !important; }
    h4 { font-size: 1.05em !important; }
    img, svg, video, canvas {
      max-width: 100% !important;
      height: auto !important;
    }
    a:link { color: var(--reader-fg) !important; text-decoration: underline; }
    a:visited { color: var(--reader-fg) !important; opacity: 0.8; }
    table { max-width: 100% !important; }
    .reader-highlight-yellow { background-color: rgba(245, 213, 110, 0.55) !important; }
    .reader-highlight-green  { background-color: rgba(126, 200, 160, 0.55) !important; }
    .reader-highlight-orange { background-color: rgba(232, 168, 124, 0.55) !important; }
    .reader-highlight-blue   { background-color: rgba(160, 184, 232, 0.55) !important; }
    """

    static let bootScript: String = """
    (function() {
      if (window.__readerInstalled) return;
      window.__readerInstalled = true;

      function injectCSS() {
        if (document.getElementById('reader-style')) return;
        var style = document.createElement('style');
        style.id = 'reader-style';
        style.textContent = `\(cssTemplate)`;
        var root = document.documentElement;
        root.appendChild(style);
        if (document.head && style.parentNode !== document.head) {
          document.head.appendChild(style);
        }
      }
      injectCSS();
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', injectCSS);
      }

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
      function reportProgress() {
        try {
          var sh = document.documentElement.scrollHeight - document.documentElement.clientHeight;
          var st = document.documentElement.scrollTop || document.body.scrollTop;
          var p = sh > 0 ? Math.max(0, Math.min(1, st / sh)) : 0;
          window.webkit.messageHandlers.readerBridge.postMessage({ type: 'progress', value: p });
        } catch(e) {}
      }
      window.addEventListener('scroll', function() {
        if (scrollTimer) return;
        scrollTimer = setTimeout(function() {
          scrollTimer = null;
          reportProgress();
        }, 100);
      });
      window.addEventListener('load', reportProgress);

      window.ReaderWrapSelection = function(className) {
        try {
          var sel = window.getSelection();
          if (!sel || sel.rangeCount === 0) return false;
          var range = sel.getRangeAt(0);
          if (range.collapsed) return false;
          var span = document.createElement('span');
          span.className = className;
          range.surroundContents(span);
          sel.removeAllRanges();
          return true;
        } catch(e) {
          return false;
        }
      };

      window.ReaderClearSelection = function() {
        try {
          var sel = window.getSelection();
          if (sel) sel.removeAllRanges();
        } catch(e) {}
      };

      window.ReaderApplyStyles = function(bg, fg, fontSize, lineHeight) {
        try {
          injectCSS();
          var root = document.documentElement;
          root.style.setProperty('--reader-bg', bg);
          root.style.setProperty('--reader-fg', fg);
          root.style.setProperty('--reader-font-size', fontSize + 'px');
          root.style.setProperty('--reader-line-height', lineHeight);
          if (document.body) {
            document.body.style.background = bg;
            document.body.style.color = fg;
          }
        } catch(e) {}
      };
    })();
    """
}
