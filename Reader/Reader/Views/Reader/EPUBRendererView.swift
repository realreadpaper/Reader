import SwiftUI
import WebKit

struct EPUBPageMetrics {
    let currentPage: Int
    let totalPages: Int
    let chapterIndex: Int
}

struct EPUBRendererView: View {
    let book: Book
    let chapters: [EPUBChapter]
    let resourceDirectory: URL?
    @Binding var currentChapter: Int
    let themeManager: ThemeManager
    let settings: ReaderSettings
    let initialProgress: Double
    let onPageMetrics: (EPUBPageMetrics) -> Void
    let onSelection: (String, CGRect) -> Void
    let onPageReady: (() -> Void)?

    var body: some View {
        EPUBWebView(
            chapters: chapters,
            resourceDirectory: resourceDirectory,
            currentChapter: $currentChapter,
            theme: themeManager.currentTheme,
            fontSize: settings.fontSize,
            lineHeight: settings.lineHeight,
            initialProgress: initialProgress,
            onPageMetrics: onPageMetrics,
            onSelection: onSelection,
            onPageReady: onPageReady
        )
    }
}

struct EPUBWebView: NSViewRepresentable {
    let chapters: [EPUBChapter]
    let resourceDirectory: URL?
    @Binding var currentChapter: Int
    let theme: AppTheme
    let fontSize: Double
    let lineHeight: Double
    let initialProgress: Double
    let onPageMetrics: (EPUBPageMetrics) -> Void
    let onSelection: (String, CGRect) -> Void
    let onPageReady: (() -> Void)?

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
        context.coordinator.startObservingSearchRequests()
        context.coordinator.startObservingRestoreProgress()
        context.coordinator.startObservingRestoreHighlights()
        context.coordinator.startObservingScrollToHighlight()

        if !chapters.isEmpty {
            context.coordinator.loadBook(
                chapters: chapters,
                resourceDirectory: resourceDirectory
            )
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard !chapters.isEmpty else { return }
        context.coordinator.parent = self

        let bookKey = context.coordinator.bookKey(
            chapters: chapters,
            resourceDirectory: resourceDirectory
        )
        if context.coordinator.loadedBookKey != bookKey {
            context.coordinator.loadBook(
                chapters: chapters,
                resourceDirectory: resourceDirectory
            )
        } else if context.coordinator.visibleChapter != currentChapter {
            context.coordinator.goToChapter(currentChapter)
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
        coordinator.stopObservingSearchRequests()
        coordinator.stopObservingRestoreProgress()
        coordinator.stopObservingRestoreHighlights()
        coordinator.stopObservingScrollToHighlight()
        coordinator.webView = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: EPUBWebView
        weak var webView: WKWebView?
        var loadedBookKey: String = ""
        var visibleChapter: Int = 0
        private var restoredInitialProgress = false
        private var appliedTheme: String = ""
        private var appliedFontSize: Double = 0
        private var appliedLineHeight: Double = 0
        private var highlightObserver: NSObjectProtocol?
        private var searchObserver: NSObjectProtocol?
        private var restoreProgressObserver: NSObjectProtocol?
        private var restoreHighlightsObserver: NSObjectProtocol?
        private var scrollToHighlightObserver: NSObjectProtocol?

        init(parent: EPUBWebView) {
            self.parent = parent
        }

        deinit {
            if let obs = highlightObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            if let obs = searchObserver {
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

        func startObservingSearchRequests() {
            guard searchObserver == nil else { return }
            searchObserver = NotificationCenter.default.addObserver(
                forName: .epubSearchRequest,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let chapterIndex = notification.userInfo?["chapterIndex"] as? Int,
                      let query = notification.userInfo?["query"] as? String,
                      !query.isEmpty else { return }
                self.goToSearchResult(chapterIndex: chapterIndex, query: query)
            }
        }

        func stopObservingSearchRequests() {
            if let obs = searchObserver {
                NotificationCenter.default.removeObserver(obs)
                searchObserver = nil
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
                    guard let text = hl.selectedText as String? else { return nil }
                    return ["text": text, "color": hl.color.rawValue]
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

        func bookKey(chapters: [EPUBChapter], resourceDirectory: URL?) -> String {
            let sources = chapters.map(\.fileName).joined(separator: "|")
            return "\(resourceDirectory?.path ?? "")|\(chapters.count)|\(sources)"
        }

        func loadBook(chapters: [EPUBChapter], resourceDirectory: URL?) {
            guard !chapters.isEmpty else { return }
            loadedBookKey = bookKey(chapters: chapters, resourceDirectory: resourceDirectory)
            visibleChapter = max(0, min(parent.currentChapter, chapters.count - 1))
            restoredInitialProgress = false

            let wrapped = EPUBScripts.wrapBookHTML(
                chapters: chapters,
                theme: parent.theme,
                fontSize: parent.fontSize,
                lineHeight: parent.lineHeight
            )
            webView?.loadHTMLString(wrapped, baseURL: resourceDirectory)
        }

        func goToChapter(_ index: Int) {
            guard index >= 0, index < parent.chapters.count else { return }
            visibleChapter = index
            webView?.evaluateJavaScript("window.ReaderGoToChapter && window.ReaderGoToChapter(\(index));", completionHandler: nil)
        }

        func goToSearchResult(chapterIndex: Int, query: String) {
            guard chapterIndex >= 0, chapterIndex < parent.chapters.count else { return }
            visibleChapter = chapterIndex
            let queryLiteral = javaScriptStringLiteral(query)
            webView?.evaluateJavaScript(
                "window.ReaderGoToSearchResult && window.ReaderGoToSearchResult(\(chapterIndex), \(queryLiteral));",
                completionHandler: nil
            )
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
                let page = body["currentPage"] as? Int ?? 0
                let total = body["totalPages"] as? Int ?? 1
                let chapter = body["chapterIndex"] as? Int ?? visibleChapter
                visibleChapter = chapter
                let metrics = EPUBPageMetrics(
                    currentPage: max(0, page),
                    totalPages: max(1, total),
                    chapterIndex: max(0, chapter)
                )
                Task { @MainActor in
                    parent.onPageMetrics(metrics)
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
            webView.evaluateJavaScript(
                "window.ReaderApplyStyles && window.ReaderApplyStyles('\(parent.theme.contentBG.hex)', '\(parent.theme.primaryText.hex)', \(parent.fontSize), '\(String(format: "%.2f", parent.lineHeight))');",
                completionHandler: nil
            )
            if !restoredInitialProgress {
                restoredInitialProgress = true
                let progress = max(0, min(1, parent.initialProgress))
                webView.evaluateJavaScript(
                    "window.ReaderRestoreProgress && window.ReaderRestoreProgress(\(progress));",
                    completionHandler: nil
                )
            }
            parent.onPageReady?()
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

        private func javaScriptStringLiteral(_ value: String) -> String {
            if let data = try? JSONSerialization.data(withJSONObject: [value]),
               let arrayLiteral = String(data: data, encoding: .utf8),
               arrayLiteral.count >= 2 {
                return String(arrayLiteral.dropFirst().dropLast())
            }

            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            return "'\(escaped)'"
        }
    }
}

// MARK: - Injected JS/CSS

enum EPUBScripts {
    static func wrapBookHTML(chapters: [EPUBChapter], theme: AppTheme, fontSize: Double, lineHeight: Double) -> String {
        let bg = theme.contentBG.hex
        let fg = theme.primaryText.hex
        let lh = String(format: "%.2f", lineHeight)
        let body = chapters.enumerated().map { index, chapter in
            let attrs = extractBodyAttributes(from: chapter.htmlContent)
            let content = extractBodyContent(from: chapter.htmlContent)
            let rewritten = rewriteResourceLinks(in: content, sourcePath: chapter.fileName)
            return #"<section class="reader-chapter" data-reader-chapter="\#(index)" \#(attrs)>\#(rewritten)</section>"#
        }.joined(separator: "\n")

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
        <div id="reader-viewport">
          <main id="reader-book" style="--reader-bg: \(bg); --reader-fg: \(fg); --reader-font-size: \(fontSize)px; --reader-line-height: \(lh);">
            \(body)
          </main>
        </div>
        <script>
        \(bootScript)
        </script>
        </body>
        </html>
        """
    }

    static func wrapHTML(body: String, theme: AppTheme, fontSize: Double, lineHeight: Double) -> String {
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

    static func extractBodyContent(from html: String) -> String {
        guard let bodyOpen = html.range(of: #"<body\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]),
              let bodyClose = html.range(of: #"</body>"#, options: [.regularExpression, .caseInsensitive]) else {
            return html
        }
        return String(html[bodyOpen.upperBound..<bodyClose.lowerBound])
    }

    static func extractBodyAttributes(from html: String) -> String {
        guard let bodyOpen = html.range(of: #"<body\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) else {
            return ""
        }
        var tag = String(html[bodyOpen])
        tag = tag.replacingOccurrences(of: #"</?body"#, with: "", options: [.regularExpression, .caseInsensitive])
        tag = tag.replacingOccurrences(of: ">", with: "")
        tag = tag.replacingOccurrences(of: #"(?i)\sclass\s*=\s*(['"]).*?\1"#, with: "", options: .regularExpression)
        return tag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func rewriteResourceLinks(in html: String, sourcePath: String) -> String {
        let pattern = #"(?i)(src|href|xlink:href)\s*=\s*(['"])(.*?)\2"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var result = html
        for match in regex.matches(in: html, range: nsRange).reversed() {
            guard match.numberOfRanges == 4,
                  let attrRange = Range(match.range(at: 1), in: html),
                  let quoteRange = Range(match.range(at: 2), in: html),
                  let valueRange = Range(match.range(at: 3), in: html),
                  let fullRange = Range(match.range(at: 0), in: html) else { continue }
            let value = String(html[valueRange])
            let rewritten = rewriteResourcePath(value, sourcePath: sourcePath)
            let attr = String(html[attrRange])
            let quote = String(html[quoteRange])
            result.replaceSubrange(fullRange, with: "\(attr)=\(quote)\(rewritten)\(quote)")
        }
        return result
    }

    static func rewriteResourcePath(_ path: String, sourcePath: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.hasPrefix("//"),
              !trimmed.hasPrefix("data:"),
              !trimmed.hasPrefix("javascript:"),
              !trimmed.hasPrefix("mailto:"),
              URL(string: trimmed)?.scheme == nil else {
            return path
        }

        if trimmed.hasPrefix("/") {
            return String(trimmed.drop(while: { $0 == "/" }))
        }

        let sourceDir = (sourcePath as NSString).deletingLastPathComponent
        let combined = sourceDir.isEmpty ? trimmed : "\(sourceDir)/\(trimmed)"
        var parts: [String] = []
        for part in combined.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            if part == "." { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
            } else {
                parts.append(part)
            }
        }
        return parts.joined(separator: "/")
    }

    /// 注入到 EPUB 章节的 CSS 模板，CSS 变量在运行时由 `applyStyles` 覆盖
    static let cssTemplate: String = """
    :root {
      --reader-bg: #F5EFE3;
      --reader-fg: #1A1208;
      --reader-font-size: 16px;
      --reader-line-height: 2.10;
      --reader-page-margin-y: clamp(24px, 5vh, 40px);
      --reader-page-padding-x: clamp(22px, 6vw, 56px);
      --reader-column-gap: calc(var(--reader-page-padding-x) + var(--reader-page-padding-x));
      --reader-page-width: calc(100vw - var(--reader-page-padding-x) - var(--reader-page-padding-x));
    }
    html, body {
      width: 100%;
      height: 100%;
      margin: 0 !important;
      padding: 0 !important;
      overflow: hidden !important;
      background: var(--reader-bg) !important;
    }
    body, p, li, dd, dt, blockquote, figcaption, cite, span, div, a:link {
      color: var(--reader-fg) !important;
    }
    body {
      font-family: -apple-system, "PingFang SC", "Songti SC", "Noto Serif CJK SC", serif !important;
      font-size: var(--reader-font-size) !important;
      line-height: var(--reader-line-height) !important;
      word-wrap: break-word !important;
      -webkit-text-size-adjust: 100% !important;
    }
    #reader-viewport {
      position: fixed;
      inset: 0;
      overflow-x: auto;
      overflow-y: hidden;
      background: var(--reader-bg) !important;
      scrollbar-width: none;
    }
    #reader-viewport::-webkit-scrollbar {
      display: none;
    }
    #reader-book {
      box-sizing: border-box;
      height: calc(100vh - var(--reader-page-margin-y) - var(--reader-page-margin-y));
      margin: var(--reader-page-margin-y) 0;
      padding: 0 var(--reader-page-padding-x);
      color: var(--reader-fg) !important;
      font-family: -apple-system, "PingFang SC", "Songti SC", "Noto Serif CJK SC", serif !important;
      font-size: var(--reader-font-size) !important;
      line-height: var(--reader-line-height) !important;
      column-width: var(--reader-page-width);
      -webkit-column-width: var(--reader-page-width);
      column-gap: var(--reader-column-gap);
      -webkit-column-gap: var(--reader-column-gap);
      overflow: visible;
    }
    .reader-chapter {
      break-before: column;
      -webkit-column-break-before: always;
    }
    .reader-chapter:first-child {
      break-before: auto;
      -webkit-column-break-before: auto;
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
    .reader-search-hit {
      background-color: rgba(245, 213, 110, 0.72) !important;
      border-radius: 2px;
    }
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
      var restoreTimer = null;
      var handlersInstalled = false;
      var wheelAccumulator = 0;
      var wheelResetTimer = null;
      var lastWheelTurnAt = 0;
      var lastReportedPage = 0;
      var lastPageWidth = 0;
      var lastKnownProgress = 0;
      var resizeTimer = null;
      var resizeObserverInstalled = false;

      function viewport() {
        return document.getElementById('reader-viewport');
      }

      function book() {
        return document.getElementById('reader-book');
      }

      function pageWidth() {
        var v = viewport();
        return Math.max(1, v ? v.clientWidth : window.innerWidth || 1);
      }

      function totalPages() {
        var v = viewport();
        if (!v) return 1;
        return Math.max(1, Math.ceil(v.scrollWidth / pageWidth()));
      }

      function readingProgress() {
        var pages = totalPages();
        return pages > 0 ? (currentPage() + 1) / pages : 0;
      }

      function pageForProgress(progress) {
        var pages = totalPages();
        return Math.max(0, Math.min(pages - 1, Math.ceil(Math.max(0, Math.min(1, progress)) * pages) - 1));
      }

      function currentPage() {
        var v = viewport();
        if (!v) return 0;
        return Math.max(0, Math.min(totalPages() - 1, Math.round(v.scrollLeft / pageWidth())));
      }

      function rememberCurrentPage() {
        lastReportedPage = currentPage();
        lastPageWidth = pageWidth();
        lastKnownProgress = readingProgress();
        return lastReportedPage;
      }

      function rememberSettledPage() {
        var v = viewport();
        var width = pageWidth();
        if (!v || width <= 1) return rememberCurrentPage();
        var rawPage = v.scrollLeft / width;
        var rounded = Math.round(rawPage);
        if (Math.abs(rawPage - rounded) < 0.02) {
          lastReportedPage = Math.max(0, Math.min(totalPages() - 1, rounded));
          lastPageWidth = width;
          lastKnownProgress = readingProgress();
        }
        return Math.max(0, Math.min(totalPages() - 1, rounded));
      }

      function chapterAtViewportCenter() {
        try {
          var v = viewport();
          if (!v) return 0;
          var rect = v.getBoundingClientRect();
          var x = rect.left + Math.min(rect.width - 2, Math.max(2, rect.width / 2));
          var y = rect.top + Math.min(rect.height - 2, Math.max(2, rect.height / 2));
          var node = document.elementFromPoint(x, y);
          var chapter = node && node.closest ? node.closest('.reader-chapter') : null;
          if (chapter && chapter.dataset.readerChapter) {
            return parseInt(chapter.dataset.readerChapter, 10) || 0;
          }
        } catch(e) {}
        return 0;
      }

      function snapToNearestPage() {
        var v = viewport();
        if (!v) return;
        var target = currentPage() * pageWidth();
        if (Math.abs(v.scrollLeft - target) > 1) {
          v.scrollTo({ left: target, top: 0, behavior: 'smooth' });
        }
      }

      function reportProgress() {
        try {
          var page = rememberSettledPage();
          window.webkit.messageHandlers.readerBridge.postMessage({
            type: 'progress',
            currentPage: page,
            totalPages: totalPages(),
            chapterIndex: chapterAtViewportCenter()
          });
        } catch(e) {}
      }
      window.ReaderReportProgress = reportProgress;
      function scheduleReport() {
        if (scrollTimer) return;
        scrollTimer = setTimeout(function() {
          scrollTimer = null;
          reportProgress();
        }, 100);
      }

      function goToPage(page, behavior) {
        var v = viewport();
        if (!v) return;
        var clampedPage = Math.max(0, Math.min(totalPages() - 1, page));
        lastReportedPage = clampedPage;
        lastPageWidth = pageWidth();
        lastKnownProgress = totalPages() > 0 ? (clampedPage + 1) / totalPages() : 0;
        var target = clampedPage * lastPageWidth;
        v.scrollTo({ left: target, top: 0, behavior: behavior || 'auto' });
        setTimeout(reportProgress, 80);
      }

      function realignAfterResize() {
        var v = viewport();
        if (!v) return;
        var width = pageWidth();
        if (width <= 1) return;
        var targetPage = pageForProgress(lastKnownProgress || readingProgress());
        var targetLeft = targetPage * width;
        if (Math.abs(v.scrollLeft - targetLeft) > 1) {
          v.scrollTo({ left: targetLeft, top: 0, behavior: 'auto' });
        }
        lastReportedPage = targetPage;
        lastPageWidth = width;
        setTimeout(reportProgress, 80);
      }

      function scheduleResizeRealignment() {
        if (resizeTimer) clearTimeout(resizeTimer);
        resizeTimer = setTimeout(realignAfterResize, 80);
      }

      window.ReaderTurnPage = function(delta) {
        var next = currentPage() + delta;
        goToPage(next, 'smooth');
      };

      window.ReaderRestoreProgress = function(progress) {
        if (restoreTimer) clearTimeout(restoreTimer);
        restoreTimer = setTimeout(function() {
          var pages = totalPages();
          var page = pageForProgress(progress);
          goToPage(page, 'auto');
        }, 120);
      };

      window.ReaderGoToChapter = function(index) {
        try {
          var section = document.querySelector('.reader-chapter[data-reader-chapter="' + index + '"]');
          var v = viewport();
          if (!section || !v) return;
          var rect = section.getBoundingClientRect();
          var vRect = v.getBoundingClientRect();
          var left = rect.left - vRect.left + v.scrollLeft;
          goToPage(Math.floor(left / pageWidth()), 'smooth');
        } catch(e) {}
      };

      function removeSearchHits() {
        try {
          var hits = document.querySelectorAll('span.reader-search-hit');
          hits.forEach(function(hit) {
            var parent = hit.parentNode;
            if (!parent) return;
            parent.insertBefore(document.createTextNode(hit.textContent || ''), hit);
            parent.removeChild(hit);
            parent.normalize();
          });
        } catch(e) {}
      }

      function normalizedSearchText(value) {
        return (value || '').replace(/\\u00a0/g, ' ').replace(/[\\s\\u00a0]+/g, ' ').trim();
      }

      function textNodesIn(root) {
        var nodes = [];
        try {
          var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function(node) {
              if (!node.nodeValue) return NodeFilter.FILTER_REJECT;
              var parent = node.parentElement;
              if (!parent) return NodeFilter.FILTER_REJECT;
              if (parent.closest('script, style, noscript, svg')) return NodeFilter.FILTER_REJECT;
              return NodeFilter.FILTER_ACCEPT;
            }
          });
          var node = walker.nextNode();
          while (node) {
            nodes.push(node);
            node = walker.nextNode();
          }
        } catch(e) {}
        return nodes;
      }

      function scrollToRange(range) {
        var v = viewport();
        if (!v || !range) return;
        var rect = range.getBoundingClientRect();
        if (!rect || (rect.width === 0 && rect.height === 0)) return;
        var vRect = v.getBoundingClientRect();
        var left = rect.left - vRect.left + v.scrollLeft;
        goToPage(Math.floor(left / pageWidth()), 'smooth');
      }

      window.ReaderGoToSearchResult = function(index, query) {
        try {
          removeSearchHits();
          var section = document.querySelector('.reader-chapter[data-reader-chapter="' + index + '"]');
          if (!section) return false;

          var normalizedQuery = normalizedSearchText(query).toLocaleLowerCase();
          if (!normalizedQuery) return false;

          var nodes = textNodesIn(section);
          var fullText = '';
          var offsets = [];
          nodes.forEach(function(node) {
            var text = (node.nodeValue || '').replace(/\\u00a0/g, ' ');
            offsets.push({ node: node, start: fullText.length, end: fullText.length + text.length });
            fullText += text;
          });

          var foundAt = fullText.toLocaleLowerCase().indexOf(normalizedQuery);
          if (foundAt < 0) {
            window.ReaderGoToChapter(index);
            return false;
          }

          var foundEnd = foundAt + normalizedQuery.length;
          var startInfo = offsets.find(function(info) { return foundAt >= info.start && foundAt <= info.end; });
          var endInfo = offsets.find(function(info) { return foundEnd >= info.start && foundEnd <= info.end; });
          if (!startInfo || !endInfo) {
            window.ReaderGoToChapter(index);
            return false;
          }

          var range = document.createRange();
          range.setStart(startInfo.node, Math.max(0, foundAt - startInfo.start));
          range.setEnd(endInfo.node, Math.max(0, foundEnd - endInfo.start));

          try {
            var mark = document.createElement('span');
            mark.className = 'reader-search-hit';
            range.surroundContents(mark);
            var markRange = document.createRange();
            markRange.selectNodeContents(mark);
            scrollToRange(markRange);
          } catch(e) {
            scrollToRange(range);
          }

          setTimeout(reportProgress, 120);
          return true;
        } catch(e) {
          return false;
        }
      };

      function installPagingHandlers() {
        if (handlersInstalled) return;
        var v = viewport();
        if (!v) return;
        handlersInstalled = true;
        v.addEventListener('scroll', scheduleReport);
        if (!resizeObserverInstalled && typeof ResizeObserver !== 'undefined') {
          resizeObserverInstalled = true;
          var observer = new ResizeObserver(scheduleResizeRealignment);
          observer.observe(v);
        }
        window.addEventListener('wheel', function(event) {
          var delta = Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY;
          if (Math.abs(delta) < 1) return;
          event.preventDefault();

          if (wheelResetTimer) clearTimeout(wheelResetTimer);
          wheelResetTimer = setTimeout(function() {
            wheelAccumulator = 0;
          }, 180);

          wheelAccumulator += delta;
          var now = Date.now();
          var threshold = Math.max(36, Math.min(120, pageWidth() * 0.10));
          if (Math.abs(wheelAccumulator) >= threshold && now - lastWheelTurnAt > 180) {
            window.ReaderTurnPage(wheelAccumulator > 0 ? 1 : -1);
            wheelAccumulator = 0;
            lastWheelTurnAt = now;
          }
        }, { passive: false });
        document.addEventListener('keydown', function(event) {
          var tag = event.target && event.target.tagName ? event.target.tagName.toLowerCase() : '';
          if (tag === 'input' || tag === 'textarea' || event.metaKey || event.ctrlKey || event.altKey) return;

          if (event.key === 'ArrowRight' || event.key === 'PageDown' || event.key === ' ') {
            event.preventDefault();
            window.ReaderTurnPage(1);
          } else if (event.key === 'ArrowLeft' || event.key === 'PageUp') {
            event.preventDefault();
            window.ReaderTurnPage(-1);
          }
        });
      }
      installPagingHandlers();
      document.addEventListener('DOMContentLoaded', function() {
        installPagingHandlers();
        reportProgress();
      });
      window.addEventListener('resize', function() {
        scheduleResizeRealignment();
      });
      window.addEventListener('load', function() {
        installPagingHandlers();
        reportProgress();
        setTimeout(reportProgress, 250);
        setTimeout(reportProgress, 800);
      });

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

            var walker = document.createTreeWalker(
              document.getElementById('reader-book') || document.body,
              NodeFilter.SHOW_TEXT,
              null
            );
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
          var book = document.getElementById('reader-book') || document.body;
          var walker = document.createTreeWalker(book, NodeFilter.SHOW_TEXT, null);
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
              var v = viewport();
              if (v) {
                var vRect = v.getBoundingClientRect();
                var left = rect.left - vRect.left + v.scrollLeft;
                goToPage(Math.floor(left / pageWidth()), 'smooth');
              }
            }
            break;
          }
        } catch(e) {}
      };

      window.ReaderApplyStyles = function(bg, fg, fontSize, lineHeight) {
        try {
          injectCSS();
          rememberCurrentPage();
          var root = document.documentElement;
          root.style.setProperty('--reader-bg', bg);
          root.style.setProperty('--reader-fg', fg);
          root.style.setProperty('--reader-font-size', fontSize + 'px');
          root.style.setProperty('--reader-line-height', lineHeight);
          var bookEl = book();
          if (bookEl) {
            bookEl.style.setProperty('--reader-bg', bg);
            bookEl.style.setProperty('--reader-fg', fg);
            bookEl.style.setProperty('--reader-font-size', fontSize + 'px');
            bookEl.style.setProperty('--reader-line-height', lineHeight);
          }
          if (document.body) {
            document.body.style.background = bg;
            document.body.style.color = fg;
          }
          setTimeout(realignAfterResize, 80);
        } catch(e) {}
      };
    })();
    """
}
