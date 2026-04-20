import { EditorView, keymap, drawSelection, highlightActiveLine, dropCursor, lineNumbers } from "@codemirror/view";
import { EditorState, Compartment } from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search";
import { syntaxHighlighting } from "@codemirror/language";
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete";

import { editorTheme, markdownHighlighting } from "./theme.js";

// Forward browser errors to the Swift host so they show up in Xcode's console
// (open the Safari Web Inspector for richer debugging: Develop → <App> → index.html).
function postLog(level, args) {
  try {
    const msg = args.map((a) => {
      if (a instanceof Error) return `${a.name}: ${a.message}\n${a.stack || ""}`;
      if (typeof a === "object") { try { return JSON.stringify(a); } catch { return String(a); } }
      return String(a);
    }).join(" ");
    window.webkit?.messageHandlers?.editor?.postMessage({ type: "log", level, msg });
  } catch { /* no-op */ }
}
window.addEventListener("error", (e) => postLog("error", [e.message, e.filename + ":" + e.lineno, e.error || ""]));
window.addEventListener("unhandledrejection", (e) => postLog("error", ["unhandledrejection", e.reason]));
const origErr = console.error.bind(console);
console.error = (...args) => { postLog("error", args); origErr(...args); };
const origWarn = console.warn.bind(console);
console.warn = (...args) => { postLog("warn", args); origWarn(...args); };
import { livePreview, mermaidBlocks, wireMermaidThemeRefresh } from "./live-preview.js";
import { focusMode } from "./focus-mode.js";
import { wordCountPlugin } from "./word-count.js";
import { frontmatterFolding } from "./frontmatter.js";
import { boldCommand, italicCommand, linkCommand } from "./formatting.js";
import { tableEditing, insertTableCommand } from "./table.js";
import { createPreviewPane, updatePreview, setPreviewVisible, syncPreviewScroll } from "./preview.js";
import { createBridge } from "./bridge.js";
import { resolveD2Render } from "./d2-renderer.js";

window.d2Rendered = (requestId, result) => resolveD2Render(requestId, result);

let view;
let bridge;
const lineNumbersCompartment = new Compartment();

function createEditor(parent) {
  const state = EditorState.create({
    doc: "",
    extensions: [
      history(),
      drawSelection(),
      dropCursor(),
      highlightActiveLine(),
      highlightSelectionMatches(),
      closeBrackets(),
      markdown({ base: markdownLanguage }),
      lineNumbersCompartment.of([]),
      editorTheme,
      syntaxHighlighting(markdownHighlighting),
      livePreview(),
      mermaidBlocks,
      focusMode(),
      wordCountPlugin,
      frontmatterFolding(),
      tableEditing(),
      EditorView.contentAttributes.of({ spellcheck: "true" }),
      keymap.of([
        ...closeBracketsKeymap,
        ...defaultKeymap,
        ...historyKeymap,
        ...searchKeymap,
        indentWithTab,
        { key: "Mod-s", run: () => { bridge.notifySave(); return true; } },
        { key: "Mod-b", run: boldCommand },
        { key: "Mod-i", run: italicCommand },
        { key: "Mod-k", run: linkCommand },
      ]),
      EditorView.updateListener.of((update) => {
        if (update.docChanged) {
          const content = update.state.doc.toString();
          bridge.notifyContentChanged(content);
          updatePreview(content);
        }
        if (update.selectionSet) {
          const sel = update.state.selection.main;
          bridge.notifySelectionChanged(sel.from, sel.to);
        }
      }),
      EditorView.lineWrapping,
    ],
  });

  view = new EditorView({ state, parent });
  bridge = createBridge(view);
  wireMermaidThemeRefresh(view);

  // Add preview pane after editor
  const container = parent.parentElement;
  if (container) {
    container.appendChild(createPreviewPane());
  }

  // Sync preview scroll when editor scrolls
  view.scrollDOM.addEventListener("scroll", () => { syncPreviewScroll(view); });

  // Image drop handler — intercept image drops, upload to S3 via Swift bridge
  view.dom.addEventListener("drop", (e) => {
    const files = e.dataTransfer?.files;
    if (!files || files.length === 0) return;

    const imageFile = Array.from(files).find(f => f.type.startsWith("image/"));
    if (!imageFile) return;

    e.preventDefault();
    e.stopPropagation();

    // Insert placeholder at drop position
    const pos = view.posAtCoords({ x: e.clientX, y: e.clientY }) ?? view.state.selection.main.head;
    const placeholder = `![Uploading ${imageFile.name}...]()`;
    view.dispatch({ changes: { from: pos, insert: placeholder } });

    // Read file and send to Swift for S3 upload
    const reader = new FileReader();
    reader.onload = () => {
      const base64 = reader.result?.split(",")[1];
      if (base64) {
        bridge.notifyImageUpload(imageFile.name, base64, placeholder);
      }
    };
    reader.onerror = () => {
      // Remove the placeholder on read failure
      const doc = view.state.doc.toString();
      const idx = doc.indexOf(placeholder);
      if (idx !== -1) {
        view.dispatch({ changes: { from: idx, to: idx + placeholder.length, insert: "" } });
      }
    };
    reader.readAsDataURL(imageFile);
  }, true);

  // Callback for when Swift completes the S3 upload
  window.editorImageUploaded = (placeholder, url) => {
    const doc = view.state.doc.toString();
    const idx = doc.indexOf(placeholder);
    if (idx === -1) return;
    const markdown = `![](${url})`;
    view.dispatch({ changes: { from: idx, to: idx + placeholder.length, insert: markdown } });
  };

  // Expose bridge globally for Swift -> JS calls
  window.editorBridge = bridge;
  window.editorBridge.setPreviewVisible = (visible) => {
    setPreviewVisible(visible, () => view.state.doc.toString());
  };

  window.editorBridge.setLineNumbers = (show) => {
    view.dispatch({
      effects: lineNumbersCompartment.reconfigure(show ? lineNumbers() : []),
    });
  };

  // Notify Swift that the editor is ready
  bridge.notifyReady();
}

createEditor(document.getElementById("editor"));
