import { EditorView, keymap, drawSelection, highlightActiveLine, dropCursor, lineNumbers } from "@codemirror/view";
import { EditorState, Compartment } from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { searchKeymap, highlightSelectionMatches } from "@codemirror/search";
import { syntaxHighlighting } from "@codemirror/language";
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete";

import { editorTheme, markdownHighlighting } from "./theme.js";
import { livePreview } from "./live-preview.js";
import { focusMode } from "./focus-mode.js";
import { wordCountPlugin } from "./word-count.js";
import { frontmatterFolding } from "./frontmatter.js";
import { boldCommand, italicCommand, linkCommand } from "./formatting.js";
import { createPreviewPane, updatePreview, setPreviewVisible, syncPreviewScroll } from "./preview.js";
import { createBridge } from "./bridge.js";

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
      focusMode(),
      wordCountPlugin,
      frontmatterFolding(),
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
