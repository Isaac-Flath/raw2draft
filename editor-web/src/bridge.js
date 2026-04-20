/**
 * Bridge between Swift (WKWebView) and CodeMirror 6.
 *
 * JS -> Swift: window.webkit.messageHandlers.editor.postMessage({...})
 * Swift -> JS: window.editorBridge.setContent(markdown), etc.
 */

import { EditorView } from "@codemirror/view";
import { scrollPreviewToHeading } from "./preview.js";
import { setAssetBaseDir } from "./asset-url.js";
import { refreshMermaidTheme } from "./mermaid-renderer.js";

function postToSwift(type, payload = {}) {
  try {
    window.webkit?.messageHandlers?.editor?.postMessage({ type, ...payload });
  } catch {
    // Not in WKWebView (dev mode)
  }
}

export function createBridge(view) {
  return {
    // --- Swift -> JS ---

    setContent(markdown) {
      const oldContent = view.state.doc.toString();
      if (oldContent === markdown) return;

      // Compute a minimal diff (common prefix + common suffix) so CodeMirror
      // can map the cursor through unchanged regions. A full replace would
      // reset the cursor to 0 and yank scroll to top/bottom.
      let prefix = 0;
      const maxPre = Math.min(oldContent.length, markdown.length);
      while (prefix < maxPre && oldContent.charCodeAt(prefix) === markdown.charCodeAt(prefix)) {
        prefix++;
      }
      let suffix = 0;
      const maxSuf = Math.min(oldContent.length - prefix, markdown.length - prefix);
      while (
        suffix < maxSuf &&
        oldContent.charCodeAt(oldContent.length - 1 - suffix) ===
          markdown.charCodeAt(markdown.length - 1 - suffix)
      ) {
        suffix++;
      }

      const from = prefix;
      const to = oldContent.length - suffix;
      const insert = markdown.slice(prefix, markdown.length - suffix);

      // Preserve scroll position across the transaction — CM maps selections
      // through changes, but large rewrites can still shift the viewport.
      const scrollTop = view.scrollDOM.scrollTop;
      view.dispatch({ changes: { from, to, insert } });
      view.scrollDOM.scrollTop = scrollTop;
    },

    getContent() {
      return view.state.doc.toString();
    },

    insertText(text) {
      const cursor = view.state.selection.main.head;
      view.dispatch({
        changes: { from: cursor, insert: text },
        selection: { anchor: cursor + text.length },
      });
      view.focus();
    },

    setTheme(theme) {
      document.documentElement.setAttribute("data-theme", theme);
      refreshMermaidTheme();
    },

    setBaseDir(dir) {
      setAssetBaseDir(dir);
    },

    setFont(name, size) {
      document.documentElement.style.setProperty("--editor-font", name);
      document.documentElement.style.setProperty("--editor-font-size", size + "px");
      // Force CM6 to remeasure
      view.requestMeasure();
    },

    setContentWidth(width) {
      document.documentElement.style.setProperty("--editor-content-width", width + "px");
      view.requestMeasure();
    },

    setFocusMode(enabled) {
      document.documentElement.setAttribute("data-focus-mode", enabled ? "true" : "false");
    },

    focus() {
      view.focus();
    },

    scrollToLine(line) {
      const lineInfo = view.state.doc.line(Math.min(line, view.state.doc.lines));
      view.dispatch({
        effects: EditorView.scrollIntoView(lineInfo.from, { y: "start" }),
      });
    },

    scrollToHeading(index) {
      scrollPreviewToHeading(index);
    },

    // --- JS -> Swift ---

    notifyReady() {
      postToSwift("ready");
    },

    notifyContentChanged(content) {
      postToSwift("contentChanged", { content });
    },

    notifySelectionChanged(from, to) {
      postToSwift("selectionChanged", { from, to });
    },

    notifySave() {
      postToSwift("save");
    },

    notifyWordCount(words, characters) {
      postToSwift("wordCount", { words, characters });
    },

    sendToTerminal(text) {
      postToSwift("sendToTerminal", { text });
    },

    notifyImageUpload(name, base64, placeholder) {
      postToSwift("uploadImage", { name, base64, placeholder });
    },
  };
}
