/**
 * Bridge between Swift (WKWebView) and CodeMirror 6.
 *
 * JS -> Swift: window.webkit.messageHandlers.editor.postMessage({...})
 * Swift -> JS: window.editorBridge.setContent(markdown), etc.
 */

import { EditorView } from "@codemirror/view";
import { scrollPreviewToHeading } from "./preview.js";

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
      view.dispatch({
        changes: { from: 0, to: view.state.doc.length, insert: markdown },
      });
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
