import SwiftUI
import PDFKit
import QuartzCore

struct PDFContainerView: NSViewRepresentable {
    let url: URL
    let document: PDFDocument?
    let coordinator: RenderCoordinator
    let targetPageIndex: Int
    let theme: AppTheme
    let filterEnabled: Bool
    let scaleFactor: Double
    let onSelection: (String, CGRect) -> Void

    func makeCoordinator() -> PDFRendererCoordinator {
        PDFRendererCoordinator(renderCoordinator: coordinator)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = AdaptivePDFView()
        pdfView.autoScales = false
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.wantsLayer = true
        pdfView.delegate = context.coordinator
        pdfView.onLayout = { [weak coordinator = context.coordinator, weak pdfView] in
            guard let pdfView else { return }
            guard let coordinator else { return }
            coordinator.applyAdaptiveScale(to: pdfView, userScale: coordinator.currentUserScale)
        }
        context.coordinator.parent = self
        context.coordinator.currentUserScale = scaleFactor
        context.coordinator.applyRenderOptions(
            to: pdfView,
            theme: theme,
            filterEnabled: filterEnabled
        )

        let doc = document ?? PDFDocument(url: url)
        if let doc {
            pdfView.document = doc
        }
        context.coordinator.applyAdaptiveScale(to: pdfView, userScale: scaleFactor)

        if let doc {
            let startPage = max(0, min(targetPageIndex, doc.pageCount - 1))
            if doc.pageCount > 0, let page = doc.page(at: startPage) {
                pdfView.go(to: page)
            }
            context.coordinator.bindInitialProgress(
                pageIndex: startPage,
                totalPages: doc.pageCount
            )
        }

        context.coordinator.pdfView = pdfView
        context.coordinator.startObservingPageChanges(pdfView: pdfView)
        context.coordinator.startObservingHighlightRequests()
        context.coordinator.startObservingRestoreHighlights()
        context.coordinator.startObservingScrollToHighlight()
        context.coordinator.startSelectionMonitoring(pdfView: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.currentUserScale = scaleFactor
        context.coordinator.applyRenderOptions(
            to: pdfView,
            theme: theme,
            filterEnabled: filterEnabled
        )
        context.coordinator.applyAdaptiveScale(to: pdfView, userScale: scaleFactor)

        let doc = document ?? PDFDocument(url: url)
        if let doc, pdfView.document !== doc {
            pdfView.document = doc
            let startPage = max(0, min(targetPageIndex, doc.pageCount - 1))
            if doc.pageCount > 0, let page = doc.page(at: startPage) {
                pdfView.go(to: page)
            }
            context.coordinator.applyAdaptiveScale(to: pdfView, userScale: scaleFactor)
        } else if let doc = pdfView.document {
            let current = pdfView.currentPage.flatMap { doc.index(for: $0) } ?? -1
            if targetPageIndex >= 0 && targetPageIndex < doc.pageCount && targetPageIndex != current {
                if let page = doc.page(at: targetPageIndex) {
                    pdfView.go(to: page)
                }
            }
        }
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: PDFRendererCoordinator) {
        coordinator.stopObservingPageChanges()
        coordinator.stopObservingHighlightRequests()
        coordinator.stopObservingRestoreHighlights()
        coordinator.stopObservingScrollToHighlight()
        coordinator.stopSelectionMonitoring()
        coordinator.pdfView = nil
    }
}

final class AdaptivePDFView: PDFView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

struct PDFRenderOptions: Equatable {
    let theme: AppTheme
    let filterEnabled: Bool

    func apply(to view: PDFView) {
        let background = Self.backgroundColor(for: theme)
        view.wantsLayer = true
        view.backgroundColor = background
        view.layer?.backgroundColor = background.cgColor
        view.layer?.isOpaque = true
        view.contentFilters = filterEnabled ? Self.filters(for: theme) : []
    }

    static func backgroundColor(for theme: AppTheme) -> NSColor {
        NSColor(theme.contentBG)
    }

    static func filters(for theme: AppTheme) -> [CIFilter] {
        switch theme {
        case .classic, .kraft:
            return []
        case .eyeCare:
            let saturation = CIFilter(name: "CIColorControls", parameters: [
                "inputSaturation": 0.85,
                "inputBrightness": 0.02,
            ])
            return [saturation].compactMap { $0 }
        case .night:
            let invert = CIFilter(name: "CIColorInvert")
            let adjust = CIFilter(name: "CIColorControls", parameters: [
                "inputBrightness": -0.15,
                "inputContrast": 1.05,
            ])
            return [invert, adjust].compactMap { $0 }
        }
    }
}

struct PDFRenderOptionsState {
    private var current: PDFRenderOptions?

    mutating func markIfChanged(_ next: PDFRenderOptions) -> Bool {
        guard current != next else { return false }
        current = next
        return true
    }
}

enum PDFScalePolicy {
    static func targetScale(fitScale: CGFloat, userScale: Double) -> CGFloat {
        let safeFitScale = max(0.01, fitScale)
        let safeUserScale = max(0.5, min(2.0, userScale))
        return safeFitScale * CGFloat(safeUserScale)
    }

    static func shouldUpdate(current: CGFloat, target: CGFloat) -> Bool {
        abs(current - target) > 0.01
    }
}

final class PDFRendererCoordinator: NSObject, PDFViewDelegate {
    let renderCoordinator: RenderCoordinator
    var parent: PDFContainerView?
    weak var pdfView: PDFView?
    private var pageChangeObserver: NSObjectProtocol?
    private var highlightObserver: NSObjectProtocol?
    private var restoreHighlightsObserver: NSObjectProtocol?
    private var scrollToHighlightObserver: NSObjectProtocol?
    private var eventMonitor: Any?
    private var lastPageIndex: Int = -1
    private var renderOptionsState = PDFRenderOptionsState()
    private var lastSelectedText: String = ""
    var currentUserScale: Double = 1

    init(renderCoordinator: RenderCoordinator) {
        self.renderCoordinator = renderCoordinator
    }

    deinit {
        if let obs = pageChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = highlightObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = restoreHighlightsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = scrollToHighlightObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @MainActor
    func bindInitialProgress(pageIndex: Int, totalPages: Int) {
        guard totalPages > 0 else { return }
        if lastPageIndex != pageIndex {
            lastPageIndex = pageIndex
        }
        let p = Double(pageIndex + 1) / Double(totalPages)
        if renderCoordinator.progress < p || renderCoordinator.progress == 0 {
            renderCoordinator.updatePDFProgress(currentPage: pageIndex, totalPages: totalPages)
        }
    }

    func startObservingPageChanges(pdfView: PDFView) {
        guard pageChangeObserver == nil else { return }
        pageChangeObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] notification in
            self?.handlePageChanged(notification)
        }
    }

    func stopObservingPageChanges() {
        if let obs = pageChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            pageChangeObserver = nil
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
            // className is like "reader-highlight-yellow"
            let colorName = className.replacingOccurrences(of: "reader-highlight-", with: "")
            Task { @MainActor in
                self.addPDFHighlightAnnotation(colorName: colorName)
            }
        }
    }

    func stopObservingHighlightRequests() {
        if let obs = highlightObserver {
            NotificationCenter.default.removeObserver(obs)
            highlightObserver = nil
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
            Task { @MainActor in
                self.restorePDFHighlights(highlights)
            }
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
                  let text = notification.userInfo?["text"] as? String,
                  let pdfView = self.pdfView,
                  let document = pdfView.document else { return }
            let selections = document.findString(text, withOptions: .caseInsensitive)
            if let first = selections.first, let page = first.pages.first {
                pdfView.go(to: page)
            }
        }
    }

    func stopObservingScrollToHighlight() {
        if let obs = scrollToHighlightObserver {
            NotificationCenter.default.removeObserver(obs)
            scrollToHighlightObserver = nil
        }
    }

    @MainActor
    private func restorePDFHighlights(_ highlights: [Highlight]) {
        guard let pdfView, let document = pdfView.document else { return }

        // Remove existing highlight annotations
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let annotations = page.annotations.filter { $0.type == "Highlight" }
            for annotation in annotations {
                page.removeAnnotation(annotation)
            }
        }

        // Re-add highlights from stored data
        for highlight in highlights {
            let colorName = highlight.color.rawValue
            let pdfColor: NSColor
            switch colorName {
            case "yellow": pdfColor = NSColor(red: 0.96, green: 0.84, blue: 0.43, alpha: 0.55)
            case "green":  pdfColor = NSColor(red: 0.49, green: 0.78, blue: 0.63, alpha: 0.55)
            case "orange": pdfColor = NSColor(red: 0.91, green: 0.66, blue: 0.49, alpha: 0.55)
            case "blue":   pdfColor = NSColor(red: 0.63, green: 0.72, blue: 0.91, alpha: 0.55)
            default:       pdfColor = NSColor(red: 0.96, green: 0.84, blue: 0.43, alpha: 0.55)
            }

            let selections = document.findString(highlight.selectedText, withOptions: .caseInsensitive)
            for selection in selections {
                for lineSelection in selection.selectionsByLine() {
                    guard let page = lineSelection.pages.first else { continue }
                    let bounds = lineSelection.bounds(for: page)
                    guard !bounds.isEmpty else { continue }
                    let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                    annotation.color = pdfColor
                    page.addAnnotation(annotation)
                }
            }
        }
    }

    func startSelectionMonitoring(pdfView: PDFView) {
        // Monitor mouseUp events to detect text selection
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let self, let pdfView = self.pdfView else { return event }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.checkSelection(pdfView: pdfView)
            }
            return event
        }
    }

    func stopSelectionMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func checkSelection(pdfView: PDFView) {
        guard let selection = pdfView.currentSelection,
              let page = pdfView.currentPage else {
            if !lastSelectedText.isEmpty {
                lastSelectedText = ""
                Task { @MainActor in
                    parent?.onSelection("", .zero)
                }
            }
            return
        }

        let selectedText = selection.string ?? ""
        guard !selectedText.isEmpty, selectedText != lastSelectedText else { return }
        lastSelectedText = selectedText

        // Get the selection bounds in window coordinates
        let selectionBounds = selection.bounds(for: page)
        if let pageView = pdfView.documentView {
            let pageBounds = pdfView.convert(selectionBounds, from: page)
            let windowBounds = pageView.convert(pageBounds, to: nil)
            Task { @MainActor in
                parent?.onSelection(selectedText, windowBounds)
            }
        }
    }

    @MainActor
    private func addPDFHighlightAnnotation(colorName: String) {
        guard let pdfView, let selection = pdfView.currentSelection else { return }

        let pdfColor: NSColor
        switch colorName {
        case "yellow": pdfColor = NSColor(red: 0.96, green: 0.84, blue: 0.43, alpha: 0.55)
        case "green":  pdfColor = NSColor(red: 0.49, green: 0.78, blue: 0.63, alpha: 0.55)
        case "orange": pdfColor = NSColor(red: 0.91, green: 0.66, blue: 0.49, alpha: 0.55)
        case "blue":   pdfColor = NSColor(red: 0.63, green: 0.72, blue: 0.91, alpha: 0.55)
        default:       pdfColor = NSColor(red: 0.96, green: 0.84, blue: 0.43, alpha: 0.55)
        }

        for lineSelection in selection.selectionsByLine() {
            guard let page = lineSelection.pages.first else { continue }
            let bounds = lineSelection.bounds(for: page)
            guard !bounds.isEmpty else { continue }
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = pdfColor
            page.addAnnotation(annotation)
        }

        // Clear selection after highlighting
        pdfView.clearSelection()
        lastSelectedText = ""
    }

    func applyRenderOptions(to pdfView: PDFView, theme: AppTheme, filterEnabled: Bool) {
        let options = PDFRenderOptions(theme: theme, filterEnabled: filterEnabled)
        guard renderOptionsState.markIfChanged(options) else { return }
        options.apply(to: pdfView)
    }

    func applyAdaptiveScale(to pdfView: PDFView, userScale: Double) {
        guard pdfView.document != nil else { return }
        let targetScale = PDFScalePolicy.targetScale(
            fitScale: pdfView.scaleFactorForSizeToFit,
            userScale: userScale
        )
        if PDFScalePolicy.shouldUpdate(current: pdfView.scaleFactor, target: targetScale) {
            pdfView.scaleFactor = targetScale
        }
    }

    private func handlePageChanged(_ notification: Notification) {
        guard let pdfView = notification.object as? PDFView,
              let document = pdfView.document,
              let page = pdfView.currentPage else { return }
        let idx = document.index(for: page)
        guard idx != lastPageIndex, idx >= 0 else { return }
        lastPageIndex = idx
        Task { @MainActor in
            renderCoordinator.updatePDFProgress(currentPage: idx, totalPages: document.pageCount)
        }
    }
}
