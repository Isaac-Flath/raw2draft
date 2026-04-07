import { ViewPlugin } from "@codemirror/view";

/**
 * Reports word and character counts to Swift via the bridge.
 */
export const wordCountPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.report(view);
    }
    update(update) {
      if (update.docChanged) {
        this.report(update.view);
      }
    }
    report(view) {
      const text = view.state.doc.toString();
      const words = text.trim() ? text.trim().split(/\s+/).length : 0;
      const characters = text.length;
      window.editorBridge?.notifyWordCount(words, characters);
    }
  }
);
