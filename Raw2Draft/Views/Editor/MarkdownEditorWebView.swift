import SwiftUI
import WebKit
import os

private let logger = Logger(subsystem: "com.raw2draft", category: "EditorWebView")

/// WKWebView-based markdown editor powered by CodeMirror 6.
/// Replaces the NSTextView-based MarkdownEditorView.
struct MarkdownEditorWebView: NSViewRepresentable {
    let content: String
    let fontName: String
    let fontSize: CGFloat
    let socialMode: Bool
    let showPreview: Bool
    let showLineNumbers: Bool
    let baseDirectory: URL?
    @Binding var scrollToOffset: Int?
    @Binding var scrollToHeadingIndex: Int?
    let onContentChanged: (String) -> Void
    let onSave: () -> Void
    let onWordCount: (Int, Int) -> Void
    let onCursorPosition: (Int, Int) -> Void
    let onSendToTerminal: (String) -> Void
    let envLookup: (String) -> String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "editor")

        // Custom URL scheme for loading arbitrary local assets referenced by
        // the active markdown file (images, etc.). Keeps the WebView's normal
        // file:// access scoped to the bundle so fonts/same-origin resources
        // keep working.
        config.setURLSchemeHandler(AssetSchemeHandler(), forURLScheme: "r2dasset")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Enable Safari Web Inspector (Develop menu → Raw2Draft → index.html)
        // on macOS 13.3+. Safe to leave on in release — costs nothing unless
        // the user opens Safari's Develop menu.
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        // Load the bundled editor HTML. Scope read access to the Resources
        // directory so bundled fonts/assets keep same-origin semantics.
        // User-project assets are served via the r2dasset:// scheme above.
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator

        // Always keep the coordinator's pending content up to date so the
        // "ready" handler can use it even if isReady hasn't fired yet.
        coordinator.pendingContent = content

        logger.info("updateNSView: isReady=\(coordinator.isReady) contentLen=\(content.count) lastSentLen=\(coordinator.lastSentContent.count) match=\(content == coordinator.lastSentContent)")

        // Update content if it changed externally (file switch, etc.)
        if coordinator.isReady && content != coordinator.lastSentContent {
            coordinator.lastSentContent = content
            coordinator.sendContent(content, to: webView)
        }

        // Update font
        if coordinator.isReady && (fontName != coordinator.lastFontName || fontSize != coordinator.lastFontSize) {
            coordinator.lastFontName = fontName
            coordinator.lastFontSize = fontSize
            webView.evaluateJavaScript("window.editorBridge.setFont('\(fontName.jsSingleQuoteEscaped)', \(fontSize))")
        }

        // Update content width for social mode
        if coordinator.isReady && socialMode != coordinator.lastSocialMode {
            coordinator.lastSocialMode = socialMode
            let width = socialMode ? 550 : 720
            webView.evaluateJavaScript("window.editorBridge.setContentWidth(\(width))")
        }

        // Update preview visibility
        if coordinator.isReady && showPreview != coordinator.lastShowPreview {
            coordinator.lastShowPreview = showPreview
            webView.evaluateJavaScript("window.editorBridge.setPreviewVisible(\(showPreview))")
        }

        // Update line numbers
        if coordinator.isReady && showLineNumbers != coordinator.lastShowLineNumbers {
            coordinator.lastShowLineNumbers = showLineNumbers
            webView.evaluateJavaScript("window.editorBridge.setLineNumbers(\(showLineNumbers))")
        }

        // Update base directory so the editor can resolve relative asset paths.
        if coordinator.isReady && baseDirectory?.path != coordinator.lastBaseDirectory?.path {
            coordinator.lastBaseDirectory = baseDirectory
            coordinator.sendBaseDirectory(baseDirectory, to: webView)
        }

        // Scroll to offset (e.g., from heading outline)
        if coordinator.isReady, let offset = scrollToOffset {
            // Convert character offset to a line number for the bridge
            let line = content.prefix(offset).filter { $0 == "\n" }.count + 1
            webView.evaluateJavaScript("window.editorBridge.scrollToLine(\(line))")
            // Also scroll preview to the matching heading
            if let headingIndex = scrollToHeadingIndex {
                webView.evaluateJavaScript("window.editorBridge.scrollToHeading(\(headingIndex))")
            }
            DispatchQueue.main.async { [self] in
                self.scrollToOffset = nil
                self.scrollToHeadingIndex = nil
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let parent: MarkdownEditorWebView
        weak var webView: WKWebView?
        var isReady = false
        var lastSentContent = ""
        /// The latest content from SwiftUI, kept in sync by updateNSView.
        /// Used by the "ready" handler to avoid relying on the stale `parent` reference.
        var pendingContent: String = ""
        var lastFontName = ""
        var lastFontSize: CGFloat = 0
        var lastSocialMode = false
        var lastShowPreview = false
        var lastShowLineNumbers = false
        var lastBaseDirectory: URL?

        init(parent: MarkdownEditorWebView) {
            self.parent = parent
            self.pendingContent = parent.content
            super.init()
        }

        /// Tell the JavaScript editor about the active file's absolute
        /// directory so it can resolve relative asset paths like `images/x.png`.
        func sendBaseDirectory(_ dir: URL?, to webView: WKWebView) {
            if let path = dir?.path {
                webView.evaluateJavaScript("window.editorBridge.setBaseDir('\(path.jsSingleQuoteEscaped)')")
            } else {
                webView.evaluateJavaScript("window.editorBridge.setBaseDir(null)")
            }
        }

        /// Send content to the JavaScript editor with error logging.
        func sendContent(_ content: String, to webView: WKWebView) {
            let escaped = content.jsTemplateEscaped
            let js = """
            try { window.editorBridge.setContent(`\(escaped)`); 'ok'; } catch(e) { e.message + '\\n' + e.stack; }
            """
            webView.evaluateJavaScript(js) { result, error in
                if let error {
                    let nsError = error as NSError
                    let msg = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String ?? "unknown"
                    print("[Editor] setContent eval error: \(msg)")
                } else if let resultStr = result as? String, resultStr != "ok" {
                    print("[Editor] setContent JS exception (contentLen=\(content.count)): \(resultStr)")
                }
            }
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                isReady = true
                // Load initial content using pendingContent (kept in sync by updateNSView)
                // rather than parent.content which may be stale.
                let content = pendingContent
                lastSentContent = content
                logger.info("ready: sending pendingContent len=\(content.count) first80=\(String(content.prefix(80)))")
                if let webView {
                    sendContent(content, to: webView)
                    // Verify content was actually set by querying the editor
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        webView.evaluateJavaScript("window.editorBridge.getContent().length") { result, error in
                            if let len = result as? Int {
                                logger.info("ready verify: editor doc length=\(len)")
                            } else if let error {
                                logger.error("ready verify failed: \(error.localizedDescription)")
                            }
                        }
                    }
                } else {
                    logger.warning("ready: webView is nil!")
                }

                // Set initial font
                lastFontName = parent.fontName
                lastFontSize = parent.fontSize
                webView?.evaluateJavaScript("window.editorBridge.setFont('\(parent.fontName.jsSingleQuoteEscaped)', \(parent.fontSize))")

                // Set initial content width
                lastSocialMode = parent.socialMode
                let width = parent.socialMode ? 550 : 720
                webView?.evaluateJavaScript("window.editorBridge.setContentWidth(\(width))")

                // Set initial preview state
                lastShowPreview = parent.showPreview
                webView?.evaluateJavaScript("window.editorBridge.setPreviewVisible(\(parent.showPreview))")

                // Set initial line numbers state
                lastShowLineNumbers = parent.showLineNumbers
                webView?.evaluateJavaScript("window.editorBridge.setLineNumbers(\(parent.showLineNumbers))")

                // Set initial base directory
                lastBaseDirectory = parent.baseDirectory
                if let webView {
                    sendBaseDirectory(parent.baseDirectory, to: webView)
                }

            case "contentChanged":
                if let content = body["content"] as? String {
                    lastSentContent = content
                    parent.onContentChanged(content)
                }

            case "save":
                parent.onSave()

            case "wordCount":
                if let words = body["words"] as? Int,
                   let characters = body["characters"] as? Int {
                    parent.onWordCount(words, characters)
                }

            case "cursorPosition":
                if let line = body["line"] as? Int,
                   let col = body["col"] as? Int {
                    parent.onCursorPosition(line, col)
                }

            case "sendToTerminal":
                if let text = body["text"] as? String {
                    parent.onSendToTerminal(text)
                }

            case "log":
                let level = body["level"] as? String ?? "log"
                let msg = body["msg"] as? String ?? ""
                if level == "error" {
                    logger.error("[JS] \(msg, privacy: .public)")
                } else {
                    logger.warning("[JS \(level, privacy: .public)] \(msg, privacy: .public)")
                }

            case "renderD2":
                if let code = body["code"] as? String,
                   let requestId = body["requestId"] as? String {
                    renderD2Diagram(code: code, requestId: requestId)
                }

            case "uploadImage":
                if let name = body["name"] as? String,
                   let base64 = body["base64"] as? String,
                   let placeholder = body["placeholder"] as? String {
                    uploadImageToS3(name: name, base64: base64, placeholder: placeholder)
                }

            default:
                break
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow file:// loads for the bundled editor, block external navigation
            if navigationAction.navigationType == .other || navigationAction.request.url?.isFileURL == true {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

// MARK: - JavaScript string escaping

extension String {
    /// Escape for use inside JS template literals (backtick strings).
    var jsTemplateEscaped: String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }

    /// Escape for use inside JS single-quoted strings.
    var jsSingleQuoteEscaped: String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}

// MARK: - Bridge methods callable from Swift

extension MarkdownEditorWebView.Coordinator {
    func insertText(_ text: String) {
        webView?.evaluateJavaScript("window.editorBridge.insertText(`\(text.jsTemplateEscaped)`)")
    }

    func setFocusMode(_ enabled: Bool) {
        webView?.evaluateJavaScript("window.editorBridge.setFocusMode(\(enabled))")
    }

    func setPreviewVisible(_ visible: Bool) {
        webView?.evaluateJavaScript("window.editorBridge.setPreviewVisible(\(visible))")
    }

    func scrollToLine(_ line: Int) {
        webView?.evaluateJavaScript("window.editorBridge.scrollToLine(\(line))")
    }

    func focus() {
        webView?.evaluateJavaScript("window.editorBridge.focus()")
    }

    /// Upload an image to S3 and callback to JS with the URL.
    func uploadImageToS3(name: String, base64: String, placeholder: String) {
        guard let data = Data(base64Encoded: base64) else { return }

        // Read S3 config from EnvFileService (falls back to process environment)
        let envLookup = parent.envLookup
        guard let bucket = envLookup("S3_BUCKET"), !bucket.isEmpty else {
            replaceUploadPlaceholder(placeholder, with: "![Upload failed: S3_BUCKET not set]()")
            return
        }
        let region = envLookup("AWS_REGION") ?? "us-east-1"

        // Generate unique filename
        let timestamp = Int(Date().timeIntervalSince1970)
        let safeName = name.replacingOccurrences(of: " ", with: "-").lowercased()
        let s3Key = "images/\(timestamp)-\(safeName)"

        // Write to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        try? data.write(to: tempURL)

        // Find aws CLI on PATH
        let awsPath = ["/opt/homebrew/bin/aws", "/usr/local/bin/aws", "/usr/bin/aws"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }

        guard let awsPath else {
            replaceUploadPlaceholder(placeholder, with: "![Upload failed: aws CLI not found]()")
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        // Upload via aws CLI in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: awsPath)
            process.arguments = ["s3", "cp", tempURL.path, "s3://\(bucket)/\(s3Key)", "--region", region]

            // Pass through AWS credentials from EnvFileService + process environment
            var processEnv = ProcessInfo.processInfo.environment
            processEnv["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            for key in ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_REGION", "S3_BUCKET"] {
                if let value = envLookup(key) { processEnv[key] = value }
            }
            process.environment = processEnv

            do {
                try process.run()
                process.waitUntilExit()

                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        let url = "https://\(bucket).s3.\(region).amazonaws.com/\(s3Key)"
                        self?.replaceUploadPlaceholder(placeholder, with: "![](\(url))")
                    } else {
                        self?.replaceUploadPlaceholder(placeholder, with: "![Upload failed (exit \(process.terminationStatus))]()")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.replaceUploadPlaceholder(placeholder, with: "![Upload failed: \(error.localizedDescription)]()")
                }
            }

            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    private func replaceUploadPlaceholder(_ placeholder: String, with replacement: String) {
        webView?.evaluateJavaScript("window.editorImageUploaded('\(placeholder.jsSingleQuoteEscaped)', '\(replacement.jsSingleQuoteEscaped)')")
    }

    /// Render a D2 diagram by piping source through the `d2` CLI (`d2 - -`).
    /// Returns the SVG (or an error) to JS via `window.d2Rendered`.
    func renderD2Diagram(code: String, requestId: String) {
        let d2Path = ["/opt/homebrew/bin/d2", "/usr/local/bin/d2", "/usr/bin/d2"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }

        guard let d2Path else {
            replyD2(requestId: requestId, ok: false, payload: "d2 CLI not found — install with `brew install d2`")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: d2Path)
            process.arguments = ["-", "-"]

            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            process.environment = env

            do {
                try process.run()
                if let data = code.data(using: .utf8) {
                    try stdin.fileHandleForWriting.write(contentsOf: data)
                }
                try stdin.fileHandleForWriting.close()
                process.waitUntilExit()

                let svgData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus == 0, !svgData.isEmpty {
                    let svg = String(data: svgData, encoding: .utf8) ?? ""
                    self?.replyD2(requestId: requestId, ok: true, payload: svg)
                } else {
                    let msg = String(data: errData, encoding: .utf8) ?? "d2 exited with status \(process.terminationStatus)"
                    self?.replyD2(requestId: requestId, ok: false, payload: msg.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } catch {
                self?.replyD2(requestId: requestId, ok: false, payload: error.localizedDescription)
            }
        }
    }

    private func replyD2(requestId: String, ok: Bool, payload: String) {
        DispatchQueue.main.async { [weak self] in
            let key = ok ? "svg" : "error"
            // Use JSON to safely carry arbitrary SVG/error text into JS.
            let result: [String: Any] = ["ok": ok, key: payload]
            guard let data = try? JSONSerialization.data(withJSONObject: result),
                  let json = String(data: data, encoding: .utf8) else { return }
            let reqEsc = requestId.jsSingleQuoteEscaped
            self?.webView?.evaluateJavaScript("window.d2Rendered('\(reqEsc)', \(json))")
        }
    }
}

// MARK: - r2dasset:// URL scheme handler

/// Serves local files referenced by the active markdown file (relative images,
/// etc.) over a custom URL scheme so they aren't subject to file:// origin
/// restrictions imposed on the bundled editor page.
///
/// URL form: `r2dasset:///absolute/path/to/asset.png` — the path portion is
/// the absolute filesystem path (URL-encoded).
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        // The path component is the absolute filesystem path of the asset.
        // `url.path` already percent-decodes, which is what we want.
        let path = url.path
        let fileURL = URL(fileURLWithPath: path)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mime = mimeType(forExtension: fileURL.pathExtension)
            let headers = [
                "Content-Type": mime,
                "Content-Length": String(data.count),
                "Access-Control-Allow-Origin": "*",
            ]
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
                urlSchemeTask.didFailWithError(URLError(.cannotParseResponse))
                return
            }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "avif": return "image/avif"
        case "bmp": return "image/bmp"
        case "ico": return "image/x-icon"
        case "heic": return "image/heic"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }
}
