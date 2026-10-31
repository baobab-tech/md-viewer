import SwiftUI
import WebKit
import UniformTypeIdentifiers

@main
struct MarkdownViewerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .navigationTitle(file.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled")
        }
    }
}

// MARK: - Document

struct MarkdownDocument: FileDocument {
    /// The markdown UTType, declared as an imported type in Info.plist.
    /// New documents are saved with this type (preferred extension: .md).
    static let markdownType: UTType =
        UTType("net.daringfireball.markdown")
        ?? UTType(filenameExtension: "md")
        ?? .plainText

    static var readableContentTypes: [UTType] {
        var types: [UTType] = [markdownType, .plainText]
        if let markdown = UTType(filenameExtension: "markdown") { types.append(markdown) }
        if let mdown = UTType(filenameExtension: "mdown") { types.append(mdown) }
        if let mkd = UTType(filenameExtension: "mkd") { types.append(mkd) }
        return types
    }

    static var writableContentTypes: [UTType] { [markdownType, .plainText] }

    var text: String

    /// Empty document — used by File ▸ New (⌘N) so you can paste markdown in.
    init() {
        text = ""
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Heading outline

struct Heading: Identifiable, Hashable {
    /// Derived from the slug so a re-parse keeps the sidebar rows. A fresh id
    /// per parse replaces every row on each body evaluation.
    var id: String { slug }
    let level: Int
    let text: String
    let slug: String
}

enum HeadingParser {
    /// Walks the markdown line-by-line, skipping fenced code blocks, and
    /// extracts ATX headings. Slugs are deterministic and must match the
    /// slug function in template.html.
    static func extract(from markdown: String) -> [Heading] {
        var results: [Heading] = []
        var inFence = false
        var fence: Substring = ""
        var seen: [String: Int] = [:]

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = trimmed.prefix(3)
                if !inFence {
                    inFence = true
                    fence = marker
                } else if marker == fence {
                    inFence = false
                    fence = ""
                }
                continue
            }
            if inFence { continue }

            guard trimmed.first == "#" else { continue }

            var depth = 0
            for c in trimmed {
                if c == "#" && depth < 6 { depth += 1 } else { break }
            }
            guard depth >= 1, depth <= 6 else { continue }
            let after = trimmed.dropFirst(depth)
            guard let first = after.first, first == " " || first == "\t" else { continue }

            var body = after.drop(while: { $0 == " " || $0 == "\t" })
            while let last = body.last, last == "#" || last == " " || last == "\t" {
                body = body.dropLast()
            }
            let cleaned = stripInlineMarkdown(String(body))
            if cleaned.isEmpty { continue }

            var slug = slugify(cleaned)
            if slug.isEmpty { slug = "section" }
            if let count = seen[slug] {
                let bumped = count + 1
                seen[slug] = bumped
                slug = "\(slug)-\(bumped)"
            } else {
                seen[slug] = 0
            }
            results.append(Heading(level: depth, text: cleaned, slug: slug))
        }
        return results
    }

    static func stripInlineMarkdown(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "`", with: "")
        out = out.replacingOccurrences(of: "**", with: "")
        out = out.replacingOccurrences(of: "__", with: "")
        out = out.replacingOccurrences(of: "*", with: "")
        // Convert [text](url) to text
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^)]+\\)") {
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "$1")
        }
        // Convert [text][ref] to text
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\[[^\\]]*\\]") {
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "$1")
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Lowercase, ASCII-alphanumeric kept, everything else becomes a hyphen
    /// boundary, runs collapsed. Mirrors the JS implementation 1:1.
    static func slugify(_ s: String) -> String {
        var buf = ""
        for scalar in s.lowercased().unicodeScalars {
            let v = scalar.value
            let isLower = (v >= 0x61 && v <= 0x7A)
            let isDigit = (v >= 0x30 && v <= 0x39)
            if isLower || isDigit {
                buf.unicodeScalars.append(scalar)
            } else {
                buf.append(" ")
            }
        }
        return buf
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }
}

// MARK: - Scroll plumbing

struct ScrollRequest: Equatable {
    let slug: String
    let id: UUID = UUID()
}

// MARK: - Appearance

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Web controller (owns the WKWebView ref for toolbar actions)

final class WebController: ObservableObject {
    weak var webView: WKWebView?

    /// Find state for the rendered view. The matches live in the page's DOM,
    /// so counting and stepping go through JavaScript.
    @Published var findCount: Int = 0
    @Published var findIndex: Int = -1
    private(set) var findQuery: String = ""

    func updateFind(_ query: String) {
        findQuery = query
        guard !query.isEmpty else { clearFind(); return }
        guard let wv = webView else { return }
        // One call, so overlapping searches can't each step past the first match.
        let js = "window.__find ? __find.search(\(Self.jsString(query))) : [0, -1]"
        wv.evaluateJavaScript(js) { result, _ in
            let values = (result as? [NSNumber])?.map(\.intValue) ?? [0, -1]
            self.findCount = values.first ?? 0
            self.findIndex = values.last ?? -1
        }
    }

    func stepFind(_ delta: Int) {
        guard let wv = webView, !findQuery.isEmpty else { return }
        wv.evaluateJavaScript("window.__find ? __find.go(\(delta)) : -1") { result, _ in
            if let idx = (result as? NSNumber)?.intValue, idx >= 0 { self.findIndex = idx }
        }
    }

    /// Drops the highlights but keeps the query, so a reload can restore them.
    func clearFind() {
        findCount = 0
        findIndex = -1
        webView?.evaluateJavaScript("window.__find && __find.clear();")
    }

    func endFind() {
        findQuery = ""
        clearFind()
    }

    func reapplyFind() {
        guard !findQuery.isEmpty else { return }
        updateFind(findQuery)
    }

    private static func jsString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
        var out = String(data: data, encoding: .utf8) ?? "[\"\"]"
        if out.hasPrefix("[") { out.removeFirst() }
        if out.hasSuffix("]") { out.removeLast() }
        return out
    }

    func copy(_ markdown: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(markdown, forType: .string)
    }

    func savePDF(defaultName: String) {
        guard let wv = webView else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(defaultName).pdf"
        panel.canCreateDirectories = true
        panel.title = "Save as PDF"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                self.generatePDF(webView: wv, to: url)
            }
        }
    }

    /// Forces a print-friendly stylesheet, captures the PDF, then removes it.
    /// Without this the PDF inherits the current theme — dark mode text on a
    /// white PDF background renders as nearly-invisible light grey.
    private func generatePDF(webView wv: WKWebView, to url: URL) {
        let injectCSS = """
        (function() {
          if (document.getElementById('__pdf_export_style')) return;
          var s = document.createElement('style');
          s.id = '__pdf_export_style';
          s.textContent = `
            html, body { background: #ffffff !important; color: #111111 !important; }
            h1, h2, h3, h4 { color: #111111 !important; border-color: #d2d2d7 !important; }
            h5, h6 { color: #4a4a4f !important; }
            p, li, td, th, strong, em { color: #111111 !important; }
            a { color: #0044aa !important; }
            blockquote { color: #4a4a4f !important; border-color: #d2d2d7 !important; }
            code { background: rgba(0,0,0,0.06) !important; color: #111111 !important; }
            pre { background: rgba(0,0,0,0.04) !important; color: #111111 !important; }
            pre code { background: transparent !important; color: #111111 !important; }
            th { background: rgba(0,0,0,0.05) !important; color: #111111 !important; }
            table, th, td { border-color: #d2d2d7 !important; }
            hr { border-color: #d2d2d7 !important; }
          `;
          document.head.appendChild(s);
        })();
        """
        let removeCSS = "document.getElementById('__pdf_export_style')?.remove();"

        wv.evaluateJavaScript(injectCSS) { _, _ in
            // One runloop turn to let the layout settle before capture.
            DispatchQueue.main.async {
                let config = WKPDFConfiguration()
                wv.createPDF(configuration: config) { result in
                    wv.evaluateJavaScript(removeCSS, completionHandler: nil)
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let data):
                            do {
                                try data.write(to: url)
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } catch {
                                self.presentError("Couldn't save PDF", error.localizedDescription)
                            }
                        case .failure(let err):
                            self.presentError("Couldn't generate PDF", err.localizedDescription)
                        }
                    }
                }
            }
        }
    }

    private func presentError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Document bridge

/// SwiftUI's `DocumentGroup` is backed by `NSDocument` with autosaving-in-place,
/// and that has no off switch: any write to `document.text` bumps the change
/// count, and a changed document gets written back to the file on its own — on a
/// timer, on app deactivation, on quit. Reaching the `NSDocument` lets a reload
/// put fresh text on screen without ever arming that write, so a window that is
/// only being read never touches the file.
enum DocumentBridge {
    static func nsDocument(for url: URL?) -> NSDocument? {
        guard let url else { return nil }
        if let doc = NSDocumentController.shared.document(for: url) { return doc }
        // Fall back to a resolved-path match: the URL the scene hands us can be
        // an alias or go through a symlinked directory.
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        return NSDocumentController.shared.documents.first {
            $0.fileURL?.resolvingSymlinksInPath().standardizedFileURL == resolved
        }
    }

    /// True when the window holds edits that are not on disk.
    static func hasUnsavedEdits(_ url: URL?) -> Bool {
        nsDocument(for: url)?.isDocumentEdited ?? false
    }

    /// Declares the in-memory document identical to the file on disk: clears the
    /// edited flag, so autosave has nothing to write, and adopts the file's
    /// current modification date, so a later save doesn't report that the file
    /// was changed by another application.
    static func markClean(_ url: URL?) {
        guard let doc = nsDocument(for: url) else { return }
        doc.updateChangeCount(.changeCleared)
        if let url,
           let date = try? FileManager.default
               .attributesOfItem(atPath: url.path)[.modificationDate] as? Date {
            doc.fileModificationDate = date
        }
    }
}

/// Size + modification date, to spot a write by another application.
struct FileStamp: Equatable {
    let modified: Date
    let size: Int64

    init?(url: URL?) {
        guard let url,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else { return nil }
        self.modified = modified
        self.size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
    }
}

// MARK: - Content view (sidebar + detail)

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    @State private var isEditing: Bool
    @State private var scrollRequest: ScrollRequest? = nil
    @State private var visibility: NavigationSplitViewVisibility = .automatic
    @State private var copiedRecently: Bool = false
    @State private var refreshSpin: Bool = false
    @State private var lastSeenOnDisk: FileStamp? = nil
    @State private var diskPoll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    @StateObject private var controller = WebController()
    @StateObject private var editorController = EditorController()
    @State private var findVisible: Bool = false
    @State private var findQuery: String = ""
    @State private var editorMatches: [NSRange] = []
    @State private var editorIndex: Int = -1
    @State private var findFocusRequest: Int = 0
    @AppStorage("appTheme") private var theme: AppTheme = .system

    init(document: Binding<MarkdownDocument>, fileURL: URL?) {
        self._document = document
        self.fileURL = fileURL
        // New / empty documents open straight into edit mode so you can paste.
        self._isEditing = State(initialValue: document.wrappedValue.text.isEmpty)
    }

    private var text: String { document.text }
    private var headings: [Heading] { HeadingParser.extract(from: text) }
    private var defaultPDFName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    private func refresh() {
        guard loadFromDisk(silent: false) else { return }
        withAnimation(.easeOut(duration: 0.4)) { refreshSpin.toggle() }
    }

    /// Puts the file's current contents on screen. Writing through the binding
    /// is what marks the document edited, so the edited flag is cleared right
    /// after — twice, because SwiftUI can bump the change count on the runloop
    /// turn after the assignment returns.
    @discardableResult
    private func loadFromDisk(silent: Bool) -> Bool {
        guard let url = fileURL else { return false }
        let fresh: String
        do {
            fresh = try String(contentsOf: url, encoding: .utf8)
        } catch {
            if !silent {
                let alert = NSAlert()
                alert.messageText = "Couldn't reload file"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return false
        }
        lastSeenOnDisk = FileStamp(url: url)
        if fresh != document.text { document.text = fresh }
        DocumentBridge.markClean(url)
        DispatchQueue.main.async { DocumentBridge.markClean(url) }
        return true
    }

    /// Picks up writes made by another application while the file is open for
    /// reading. Skipped while editing, and skipped whenever the window holds
    /// unsaved edits — those keep macOS's own conflict handling.
    private func reloadIfChangedOnDisk() {
        guard !isEditing, let url = fileURL else { return }
        guard let stamp = FileStamp(url: url), stamp != lastSeenOnDisk else { return }
        guard !DocumentBridge.hasUnsavedEdits(url) else {
            lastSeenOnDisk = stamp
            return
        }
        loadFromDisk(silent: true)
    }

    // MARK: Find

    private var findMatchCount: Int {
        isEditing ? editorMatches.count : controller.findCount
    }

    private var findStatus: String {
        guard !findQuery.isEmpty else { return "" }
        guard findMatchCount > 0 else { return "No results" }
        let index = isEditing ? editorIndex : controller.findIndex
        return "\(max(0, index) + 1) of \(findMatchCount)"
    }

    private func openFind() {
        findVisible = true
        findFocusRequest += 1
        if !findQuery.isEmpty { runFind() }
    }

    private func closeFind() {
        findVisible = false
        editorMatches = []
        editorIndex = -1
        controller.endFind()
    }

    /// Recomputes the match set. In the editor the first match at or after the
    /// caret is selected, so ⌘F picks up from where you are reading.
    private func runFind() {
        guard isEditing else {
            controller.updateFind(findQuery)
            return
        }
        editorMatches = Self.ranges(of: findQuery, in: document.text)
        guard !editorMatches.isEmpty else { editorIndex = -1; return }
        let caret = editorController.caretLocation
        editorIndex = editorMatches.firstIndex { $0.location >= caret } ?? 0
        editorController.reveal(editorMatches[editorIndex])
    }

    /// Refreshes the matches after an edit without touching the selection.
    /// Revealing a match here would make the next keystroke replace it.
    private func refreshEditorMatches() {
        editorMatches = Self.ranges(of: findQuery, in: document.text)
        editorIndex = editorMatches.isEmpty ? -1 : min(max(0, editorIndex), editorMatches.count - 1)
    }

    private func stepFind(_ delta: Int) {
        guard isEditing else {
            controller.stepFind(delta)
            return
        }
        guard !editorMatches.isEmpty else { runFind(); return }
        let from = editorIndex < 0 ? 0 : editorIndex
        editorIndex = (from + delta + editorMatches.count) % editorMatches.count
        editorController.reveal(editorMatches[editorIndex])
    }

    private static func ranges(of query: String, in text: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let haystack = text as NSString
        var found: [NSRange] = []
        var start = 0
        while start < haystack.length {
            let searchRange = NSRange(location: start, length: haystack.length - start)
            let match = haystack.range(of: query, options: .caseInsensitive, range: searchRange)
            if match.location == NSNotFound { break }
            found.append(match)
            start = match.location + max(1, match.length)
        }
        return found
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
        } detail: {
            VStack(spacing: 0) {
                if findVisible {
                    FindBar(
                        query: $findQuery,
                        status: findStatus,
                        hasMatches: findMatchCount > 0,
                        focusRequest: findFocusRequest,
                        onStep: stepFind,
                        onClose: closeFind
                    )
                    Divider()
                }
                Group {
                    if isEditing {
                        editor
                    } else {
                        MarkdownWebView(
                            text: text,
                            fileURL: fileURL,
                            scrollRequest: scrollRequest,
                            theme: theme,
                            controller: controller
                        )
                        .ignoresSafeArea(.container, edges: .bottom)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(theme.colorScheme)
        .onAppear {
            lastSeenOnDisk = FileStamp(url: fileURL)
            DocumentBridge.markClean(fileURL)
        }
        .onReceive(diskPoll) { _ in reloadIfChangedOnDisk() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            reloadIfChangedOnDisk()
        }
        .onChange(of: findQuery) { _ in
            guard findVisible else { return }
            runFind()
        }
        .onChange(of: isEditing) { _ in
            guard findVisible else { return }
            controller.clearFind()
            editorMatches = []
            editorIndex = -1
            // The incoming view doesn't exist yet when this runs.
            DispatchQueue.main.async { runFind() }
        }
        .onChange(of: text) { _ in
            guard findVisible, isEditing else { return }
            refreshEditorMatches()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openFind()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Find (⌘F)")
                .keyboardShortcut("f", modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isEditing.toggle() }
                } label: {
                    Image(systemName: isEditing ? "eye" : "pencil")
                }
                .help(isEditing ? "Preview (⌘⇧P)" : "Edit (⌘⇧P)")
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(refreshSpin ? 360 : 0))
                }
                .help("Reload from disk (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(fileURL == nil || isEditing)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Appearance", selection: $theme) {
                        ForEach(AppTheme.allCases) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: theme.icon)
                }
                .menuStyle(.borderlessButton)
                .help("Appearance: \(theme.label)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    controller.copy(text)
                    copiedRecently = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copiedRecently = false
                    }
                } label: {
                    Image(systemName: copiedRecently
                          ? "checkmark"
                          : "doc.on.clipboard")
                }
                .help(copiedRecently ? "Copied" : "Copy raw markdown")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    controller.savePDF(defaultName: defaultPDFName)
                } label: {
                    Image(systemName: "arrow.down.doc")
                }
                .help("Save as PDF…")
                .disabled(isEditing || text.isEmpty)
            }
        }
    }

    @ViewBuilder private var editor: some View {
        ZStack(alignment: .topLeading) {
            MarkdownTextEditor(
                text: $document.text,
                controller: editorController,
                autoFocus: !findVisible
            )
            .padding(.horizontal, 4)
            if document.text.isEmpty {
                Text("Paste or type Markdown here…\n\nThen ⌘S to save, or hit the eye icon to preview.")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private var sidebar: some View {
        if headings.isEmpty {
            VStack {
                Spacer()
                Text("No headings")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            let minLevel = headings.map(\.level).min() ?? 1
            List {
                ForEach(headings) { h in
                    Button {
                        scrollRequest = ScrollRequest(slug: h.slug)
                    } label: {
                        HStack(spacing: 0) {
                            Text(h.text)
                                .font(font(for: h.level))
                                .foregroundStyle(h.level - minLevel <= 1 ? .primary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, CGFloat(max(0, h.level - minLevel)) * 12)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func font(for level: Int) -> Font {
        switch level {
        case 1: return .system(.body, design: .default).weight(.semibold)
        case 2: return .system(.body)
        case 3: return .system(.callout)
        default: return .system(.footnote)
        }
    }
}

// MARK: - Find bar

/// Owns the field's `@FocusState` so that only this view depends on focus. On
/// `ContentView` it re-runs the whole body whenever focus moves.
struct FindBar: View {
    @Binding var query: String
    let status: String
    let hasMatches: Bool
    /// Bumped by ⌘F, so pressing it again returns to the field.
    let focusRequest: Int
    let onStep: (Int) -> Void
    let onClose: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Find", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($fieldFocused)
                .onSubmit { onStep(1) }
                .frame(maxWidth: 260)
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .leading)
            Spacer(minLength: 0)
            Button { onStep(-1) } label: { Image(systemName: "chevron.up") }
                .help("Previous match (⇧⌘G)")
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!hasMatches)
            Button { onStep(1) } label: { Image(systemName: "chevron.down") }
                .help("Next match (⌘G)")
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!hasMatches)
            Button("Done", action: onClose)
                .keyboardShortcut(.cancelAction)
                .font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
        .onChange(of: focusRequest) { _ in fieldFocused = true }
    }
}

// MARK: - Plain-text editor (NSTextView)

/// Holds the editor's `NSTextView` so the find bar can select and reveal a
/// match. SwiftUI's `TextEditor` exposes neither selection nor scrolling.
final class EditorController: ObservableObject {
    weak var textView: NSTextView?

    var caretLocation: Int {
        textView?.selectedRange().location ?? 0
    }

    func reveal(_ range: NSRange) {
        guard let tv = textView else { return }
        guard NSMaxRange(range) <= (tv.string as NSString).length else { return }
        tv.setSelectedRange(range)
        tv.scrollRangeToVisible(range)
        tv.showFindIndicator(for: range)
    }
}

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController
    /// Takes keyboard focus on creation. Off while the find field wants it.
    let autoFocus: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.string = text
        Self.applyStyle(tv)

        controller.textView = tv
        if autoFocus {
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        controller.textView = tv
        guard tv.string != text else { return }
        let caret = tv.selectedRange().location
        tv.string = text
        Self.applyStyle(tv)
        let length = (text as NSString).length
        tv.setSelectedRange(NSRange(location: min(caret, length), length: 0))
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    /// Assigning `string` drops attributes, so font, colour and line spacing
    /// are re-applied over the whole run every time the text is replaced.
    /// `labelColor` is dynamic, so it still follows the window's appearance.
    private static func applyStyle(_ tv: NSTextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        tv.defaultParagraphStyle = paragraph
        tv.typingAttributes = attrs
        tv.insertionPointColor = .labelColor
        if let storage = tv.textStorage, storage.length > 0 {
            storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if text.wrappedValue != tv.string { text.wrappedValue = tv.string }
        }
    }
}

// MARK: - WebView

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    let fileURL: URL?
    let scrollRequest: ScrollRequest?
    let theme: AppTheme
    let controller: WebController

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Track the scroll offset so a reload — ⌘R, or another application
        // writing the file — can put the reader back where they were instead of
        // at the top of the document.
        let tracker = WKUserScript(source: """
        (function() {
          var last = -1;
          window.addEventListener('scroll', function() {
            var y = window.scrollY;
            if (Math.abs(y - last) < 4) return;
            last = y;
            window.webkit.messageHandlers.scrollPos.postMessage(y);
          }, { passive: true });
        })();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(tracker)
        // In-page find: wraps every case-insensitive match in <mark>, keeps the
        // list so the toolbar can step through it, and unwraps on clear.
        let finder = WKUserScript(source: """
        (function() {
          var style = document.createElement('style');
          style.textContent =
            'mark.__fm{background:rgba(255,214,10,.42);color:inherit;border-radius:2px;}' +
            'mark.__fm.__fm-cur{background:#ff9f0a;color:#1a1a1a;}';
          (document.head || document.documentElement).appendChild(style);

          var marks = [];
          var cur = -1;

          function clear() {
            var existing = document.querySelectorAll('mark.__fm');
            var parents = [];
            for (var i = 0; i < existing.length; i++) {
              var m = existing[i];
              var p = m.parentNode;
              if (!p) continue;
              while (m.firstChild) p.insertBefore(m.firstChild, m);
              p.removeChild(m);
              if (parents.indexOf(p) === -1) parents.push(p);
            }
            for (var j = 0; j < parents.length; j++) parents[j].normalize();
            marks = [];
            cur = -1;
          }

          function textNodes() {
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
              acceptNode: function(n) {
                if (!n.nodeValue || !n.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
                var name = n.parentNode && n.parentNode.nodeName;
                if (name === 'SCRIPT' || name === 'STYLE' || name === 'NOSCRIPT') {
                  return NodeFilter.FILTER_REJECT;
                }
                return NodeFilter.FILTER_ACCEPT;
              }
            });
            var out = [], n;
            while ((n = walker.nextNode())) out.push(n);
            return out;
          }

          function update(query) {
            clear();
            if (!query) return 0;
            var needle = query.toLowerCase();
            var nodes = textNodes();
            for (var i = 0; i < nodes.length; i++) {
              var node = nodes[i];
              var lower = node.nodeValue.toLowerCase();
              var at = 0, hits = [];
              while ((at = lower.indexOf(needle, at)) !== -1) {
                hits.push(at);
                at += needle.length;
              }
              // Split from the end so the earlier offsets stay valid.
              for (var h = hits.length - 1; h >= 0; h--) {
                var match = node.splitText(hits[h]);
                match.splitText(needle.length);
                var mark = document.createElement('mark');
                mark.className = '__fm';
                match.parentNode.replaceChild(mark, match);
                mark.appendChild(match);
              }
            }
            marks = Array.prototype.slice.call(document.querySelectorAll('mark.__fm'));
            return marks.length;
          }

          function go(delta) {
            if (!marks.length) return -1;
            if (cur >= 0 && marks[cur]) marks[cur].classList.remove('__fm-cur');
            if (cur < 0) {
              cur = delta >= 0 ? 0 : marks.length - 1;
            } else {
              cur = (cur + delta + marks.length) % marks.length;
            }
            var el = marks[cur];
            el.classList.add('__fm-cur');
            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
            return cur;
          }

          function search(query) {
            var count = update(query);
            return [count, count > 0 ? go(1) : -1];
          }

          window.__find = { search: search, go: go, clear: clear };
        })();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(finder)
        config.userContentController.add(context.coordinator, name: "scrollPos")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.appearance = theme.nsAppearance
        context.coordinator.webView = webView
        context.coordinator.controller = controller
        controller.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        coord.controller = controller
        if coord.lastTheme != theme {
            coord.lastTheme = theme
            webView.appearance = theme.nsAppearance
        }
        if coord.lastText != text || coord.lastFileURL != fileURL {
            let sameDocument = coord.lastText != nil && coord.lastFileURL == fileURL
            coord.restoreY = sameDocument ? coord.lastScrollY : nil
            coord.lastScrollY = sameDocument ? coord.lastScrollY : 0
            coord.lastText = text
            coord.lastFileURL = fileURL
            coord.loaded = false
            let html = renderHTML(text)
            let base = fileURL?.deletingLastPathComponent() ?? Bundle.main.resourceURL
            webView.loadHTMLString(html, baseURL: base)
        }
        if let req = scrollRequest, coord.lastScrollID != req.id {
            coord.lastScrollID = req.id
            coord.pendingSlug = req.slug
            coord.flushScrollIfReady()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var controller: WebController?
        var lastText: String?
        var lastFileURL: URL?
        var lastTheme: AppTheme?
        var loaded: Bool = false
        var lastScrollID: UUID?
        var pendingSlug: String?
        var lastScrollY: Double = 0
        var restoreY: Double?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let y = restoreY, y > 0 {
                webView.evaluateJavaScript("window.scrollTo(0, \(y));")
            }
            restoreY = nil
            flushScrollIfReady()
            // A re-render throws the old highlights away with the old DOM.
            controller?.reapplyFind()
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "scrollPos",
                  let y = message.body as? Double else { return }
            lastScrollY = y
        }

        func flushScrollIfReady() {
            guard loaded, let slug = pendingSlug, let wv = webView else { return }
            let escaped = slug
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let js = """
            (function(){
                var el = document.getElementById('\(escaped)');
                if (el) el.scrollIntoView({behavior:'smooth', block:'start'});
            })();
            """
            wv.evaluateJavaScript(js)
            pendingSlug = nil
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow); return
            }
            if navigationAction.navigationType == .other || url.scheme == "about" {
                decisionHandler(.allow); return
            }
            if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
    }

    // MARK: HTML render

    private func renderHTML(_ markdown: String) -> String {
        guard let tplURL = Bundle.main.url(forResource: "template", withExtension: "html"),
              let template = try? String(contentsOf: tplURL, encoding: .utf8) else {
            let escaped = markdown
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
            return "<html><body><pre>\(escaped)</pre></body></html>"
        }

        // Inline marked.min.js so it loads regardless of baseURL
        // (baseURL points at the document's directory so relative images resolve).
        // Do NOT run escapeForInlineScript over this — marked's minified
        // source contains regex literals like /^</.test(e) where naively
        // rewriting "</" to "<\/" turns the regex into invalid JS.
        // Marked is a trusted vendored file; we've verified it has no "</script".
        let markedJS: String = {
            guard let url = Bundle.main.url(forResource: "marked.min", withExtension: "js"),
                  let src = try? String(contentsOf: url, encoding: .utf8) else { return "" }
            return src
        }()
        let withMarked = template.replacingOccurrences(
            of: "<script src=\"marked.min.js\"></script>",
            with: "<script>\(markedJS)</script>"
        )

        // Encode markdown as a JSON-string literal for safe JS injection.
        // If the document itself contains "</script" (e.g. inside a code fence
        // showing HTML), JSONSerialization does NOT escape it — but inside an
        // inline <script>, any literal "</" can prematurely terminate the tag.
        // So we post-escape "</" -> "<\/".
        let data = (try? JSONSerialization.data(withJSONObject: [markdown])) ?? Data()
        var jsArray = String(data: data, encoding: .utf8) ?? "[\"\"]"
        if jsArray.hasPrefix("[") { jsArray.removeFirst() }
        if jsArray.hasSuffix("]") { jsArray.removeLast() }
        jsArray = escapeForInlineScript(jsArray)
        return withMarked.replacingOccurrences(of: "/*__MARKDOWN__*/\"\"", with: jsArray)
    }

    /// Escapes "</" so the surrounding inline <script> tag isn't closed early
    /// by user content (e.g. an HTML example inside a markdown code fence).
    /// The browser still parses "<\/" correctly inside a JS string literal.
    private func escapeForInlineScript(_ s: String) -> String {
        s.replacingOccurrences(of: "</", with: "<\\/")
    }
}
