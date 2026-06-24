import SwiftUI
import WebKit

struct MDRendererView: View {
    let book: Book
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var progress: Double
    let themeManager: ThemeManager
    let storageService: StorageService
    let settings: ReaderSettings
    let onProgress: (Double) -> Void
    let onSelection: (String, CGRect) -> Void
    let onPageReady: (() -> Void)?

    @State private var layoutMode: MDLayoutMode = .split
    @State private var editedContent: String = ""
    @State private var originalContent: String = ""
    @State private var hasUnsavedChanges = false
    @State private var saveError: String?

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

                Button(action: saveContent) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 13))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(hasUnsavedChanges ? themeManager.currentTheme.accent : themeManager.currentTheme.secondaryText)
                .disabled(!hasUnsavedChanges)
                .keyboardShortcut("s", modifiers: .command)
                .help("保存 (⌘S)")

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
                    theme: themeManager.currentTheme,
                    fontSize: settings.fontSize,
                    lineHeight: settings.lineHeight,
                    hasUnsavedChanges: $hasUnsavedChanges,
                    progress: $progress,
                    onProgress: onProgress,
                    onSelection: onSelection,
                    onPageReady: onPageReady
                )
            case .previewOnly:
                MDPreviewView(
                    content: editedContent,
                    theme: themeManager.currentTheme,
                    fontSize: settings.fontSize,
                    lineHeight: settings.lineHeight,
                    progress: $progress,
                    onProgress: onProgress,
                    onSelection: onSelection,
                    onPageReady: onPageReady
                )
            }
        }
        .onAppear { loadContent() }
        .onChange(of: currentChapter) { _, _ in loadContent() }
        .onChange(of: editedContent) { _, newValue in
            hasUnsavedChanges = newValue != originalContent
        }
        .alert("保存失败", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func loadContent() {
        guard currentChapter < chapters.count else { return }
        let chapter = chapters[currentChapter]
        originalContent = chapter.htmlContent
        editedContent = chapter.htmlContent
        hasUnsavedChanges = false
    }

    @MainActor
    private func saveContent() {
        do {
            let url = URL(fileURLWithPath: book.filePath)
            try editedContent.write(to: url, atomically: true, encoding: .utf8)
            originalContent = editedContent
            hasUnsavedChanges = false
            storageService.updateBook(book)
        } catch {
            saveError = error.localizedDescription
        }
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
    let fontSize: Double
    let lineHeight: Double
    @Binding var hasUnsavedChanges: Bool
    @Binding var progress: Double
    let onProgress: (Double) -> Void
    let onSelection: (String, CGRect) -> Void
    let onPageReady: (() -> Void)?

    var body: some View {
        HSplitView {
            MDEditorView(
                content: $content,
                hasChanges: $hasUnsavedChanges,
                theme: theme,
                fontSize: fontSize
            )
            .frame(minWidth: 200)

            MDPreviewView(
                content: content,
                theme: theme,
                fontSize: fontSize,
                lineHeight: lineHeight,
                progress: $progress,
                onProgress: onProgress,
                onSelection: onSelection,
                onPageReady: onPageReady
            )
            .frame(minWidth: 200)
        }
    }
}

struct MDEditorView: NSViewRepresentable {
    @Binding var content: String
    @Binding var hasChanges: Bool
    let theme: AppTheme
    let fontSize: Double

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
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
        let targetFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font?.pointSize != CGFloat(fontSize) {
            textView.font = targetFont
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
    let fontSize: Double
    let lineHeight: Double
    @Binding var progress: Double
    let onProgress: (Double) -> Void
    let onSelection: (String, CGRect) -> Void
    let onPageReady: (() -> Void)?

    private static let selectionJS = """
    (function() {
      if (window.__mdSelectionInstalled) return;
      window.__mdSelectionInstalled = true;
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
        context.coordinator.parent = self
        let html = markdownToHTML(content)
        let fullHTML = wrapHTML(html, theme: theme)
        webView.loadHTMLString(fullHTML, baseURL: nil)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObservingHighlightRequests()
        coordinator.stopObservingRestoreProgress()
        coordinator.stopObservingRestoreHighlights()
        coordinator.stopObservingScrollToHighlight()
        coordinator.webView = nil
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
        let lh = String(format: "%.2f", lineHeight)
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    max-width: min(68ch, calc(100vw - 40px));
                    margin: 0 auto;
                    padding: 40px clamp(14px, 4vw, 28px);
                    font-family: -apple-system, "PingFang SC", "Songti SC", serif;
                    font-size: \(fontSize)px;
                    line-height: \(lh);
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
                .reader-highlight-yellow { background-color: rgba(245, 213, 110, 0.55) !important; }
                .reader-highlight-green  { background-color: rgba(126, 200, 160, 0.55) !important; }
                .reader-highlight-orange { background-color: rgba(232, 168, 124, 0.55) !important; }
                .reader-highlight-blue   { background-color: rgba(160, 184, 232, 0.55) !important; }
            </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: MDPreviewView
        weak var webView: WKWebView?
        private var restoredInitialProgress = false
        private var highlightObserver: NSObjectProtocol?
        private var restoreProgressObserver: NSObjectProtocol?
        private var restoreHighlightsObserver: NSObjectProtocol?
        private var scrollToHighlightObserver: NSObjectProtocol?

        init(parent: MDPreviewView) {
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
                        parent.onProgress(p)
                    }
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if !restoredInitialProgress {
                restoredInitialProgress = true
                let progress = max(0, min(1, parent.progress))
                webView.evaluateJavaScript(
                    "window.ReaderRestoreProgress && window.ReaderRestoreProgress(\(progress));",
                    completionHandler: nil
                )
            }
            parent.onPageReady?()
        }
    }
}
