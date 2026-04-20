import { ViewPlugin, Decoration, WidgetType, EditorView } from "@codemirror/view";
import { StateField, StateEffect } from "@codemirror/state";
import { syntaxTree } from "@codemirror/language";
import { resolveAssetURL } from "./asset-url.js";
import { renderMermaid, nextMermaidId } from "./mermaid-renderer.js";
import { renderD2 } from "./d2-renderer.js";

/**
 * Live preview decorations for markdown.
 * - Inline image widgets and line decorations for fenced code / blockquotes
 *   live in a ViewPlugin.
 * - Block-level mermaid widgets live in a separate StateField because CM6
 *   disallows block decorations coming from plugins.
 */

class ImageWidget extends WidgetType {
  constructor(src, alt) {
    super();
    this.src = src;
    this.alt = alt;
  }

  toDOM() {
    const wrap = document.createElement("div");
    wrap.className = "cm-image-widget";
    wrap.style.display = "block";
    const img = document.createElement("img");
    img.src = resolveAssetURL(this.src);
    img.alt = this.alt;
    img.loading = "lazy";
    img.style.maxWidth = "100%";
    img.style.height = "auto";
    img.onerror = () => { wrap.style.display = "none"; };
    wrap.appendChild(img);
    return wrap;
  }

  eq(other) {
    return this.src === other.src && this.alt === other.alt;
  }
}

// Cache rendered mermaid SVGs keyed by source so widget rebuilds don't
// re-trigger rendering.
const mermaidCache = new Map();

class MermaidWidget extends WidgetType {
  constructor(code) {
    super();
    this.code = code;
  }

  eq(other) {
    return this.code === other.code;
  }

  toDOM() {
    const wrap = document.createElement("div");
    wrap.className = "cm-mermaid-widget";
    wrap.contentEditable = "false";

    const cached = mermaidCache.get(this.code);
    if (cached) {
      wrap.innerHTML = cached;
      return wrap;
    }

    wrap.textContent = "Rendering diagram…";
    const id = nextMermaidId();
    renderMermaid(this.code, id).then((result) => {
      if (result.ok) {
        mermaidCache.set(this.code, result.svg);
        wrap.innerHTML = result.svg;
      } else {
        wrap.className = "cm-mermaid-widget cm-mermaid-error";
        wrap.textContent = `Mermaid error: ${result.error}`;
      }
    });
    return wrap;
  }

  ignoreEvent() {
    return false;
  }

  get estimatedHeight() {
    return 200;
  }
}

// Cache rendered D2 SVGs keyed by source.
const d2Cache = new Map();

class D2Widget extends WidgetType {
  constructor(code) {
    super();
    this.code = code;
  }

  eq(other) {
    return this.code === other.code;
  }

  toDOM() {
    const wrap = document.createElement("div");
    wrap.className = "cm-d2-widget";
    wrap.contentEditable = "false";

    const cached = d2Cache.get(this.code);
    if (cached) {
      wrap.innerHTML = cached;
      return wrap;
    }

    wrap.textContent = "Rendering D2 diagram…";
    renderD2(this.code).then((result) => {
      if (result.ok) {
        d2Cache.set(this.code, result.svg);
        wrap.innerHTML = result.svg;
      } else {
        wrap.className = "cm-d2-widget cm-mermaid-error";
        wrap.textContent = `D2 error: ${result.error}`;
      }
    });
    return wrap;
  }

  ignoreEvent() { return false; }
  get estimatedHeight() { return 200; }
}

// Line decoration classes for block elements
const codeBlockLine = Decoration.line({ class: "cm-codeblock-line" });
const codeBlockFirstLine = Decoration.line({ class: "cm-codeblock-line cm-codeblock-first" });
const codeBlockLastLine = Decoration.line({ class: "cm-codeblock-line cm-codeblock-last" });
const codeBlockOnlyLine = Decoration.line({ class: "cm-codeblock-line cm-codeblock-first cm-codeblock-last" });
const blockquoteLine = Decoration.line({ class: "cm-blockquote-line" });

function getFenceInfo(state, node) {
  let info = "";
  const cur = node.node.cursor();
  if (cur.firstChild()) {
    do {
      if (cur.name === "CodeInfo") {
        info = state.doc.sliceString(cur.from, cur.to).trim();
        break;
      }
    } while (cur.nextSibling());
  }
  return info;
}

function getFenceCode(state, node) {
  const cur = node.node.cursor();
  if (cur.firstChild()) {
    do {
      if (cur.name === "CodeText") {
        return state.doc.sliceString(cur.from, cur.to);
      }
    } while (cur.nextSibling());
  }
  return "";
}

// -------------------------- Inline / line decorations --------------------------

function buildInlineDecorations(view) {
  const decorations = [];

  for (const { from, to } of view.visibleRanges) {
    syntaxTree(view.state).iterate({
      from,
      to,
      enter(node) {
        // Inline images: ![alt](url)
        if (node.name === "Image") {
          const text = view.state.doc.sliceString(node.from, node.to);
          const match = text.match(/!\[([^\]]*)\]\(([^)]+)\)/);
          if (match) {
            const [, alt, src] = match;
            decorations.push(
              Decoration.widget({
                widget: new ImageWidget(src, alt),
              }).range(node.to)
            );
          }
        }

        // Fenced code blocks — line decorations for block styling.
        if (node.name === "FencedCode") {
          const startLine = view.state.doc.lineAt(node.from).number;
          const endLineNum = view.state.doc.lineAt(node.to).number;
          for (let i = startLine; i <= endLineNum; i++) {
            const line = view.state.doc.line(i);
            let deco;
            if (startLine === endLineNum) {
              deco = codeBlockOnlyLine;
            } else if (i === startLine) {
              deco = codeBlockFirstLine;
            } else if (i === endLineNum) {
              deco = codeBlockLastLine;
            } else {
              deco = codeBlockLine;
            }
            decorations.push(deco.range(line.from));
          }
        }

        // Blockquotes — line decorations
        if (node.name === "Blockquote") {
          const startLine = view.state.doc.lineAt(node.from).number;
          const endLine = view.state.doc.lineAt(node.to).number;
          for (let i = startLine; i <= endLine; i++) {
            const line = view.state.doc.line(i);
            decorations.push(blockquoteLine.range(line.from));
          }
        }
      },
    });
  }

  try {
    return Decoration.set(decorations, true);
  } catch (err) {
    console.error("livePreview: inline Decoration.set failed", err && err.message);
    return Decoration.none;
  }
}

export function livePreview() {
  return ViewPlugin.fromClass(
    class {
      constructor(view) {
        this.decorations = buildInlineDecorations(view);
        this.baseDirListener = () => {
          this.decorations = buildInlineDecorations(view);
          view.requestMeasure();
        };
        window.addEventListener("asset-base-dir-changed", this.baseDirListener);
      }
      update(update) {
        if (update.docChanged || update.viewportChanged) {
          this.decorations = buildInlineDecorations(update.view);
        }
      }
      destroy() {
        window.removeEventListener("asset-base-dir-changed", this.baseDirListener);
      }
    },
    { decorations: (v) => v.decorations }
  );
}

// -------------------------- Mermaid block widgets (StateField) -------------------------

function buildMermaidBlocks(state) {
  const decorations = [];
  try {
    syntaxTree(state).iterate({
      enter(node) {
        if (node.name !== "FencedCode") return;
        const lang = getFenceInfo(state, node).toLowerCase();
        const code = getFenceCode(state, node).trim();
        if (!code) return;

        let widget = null;
        if (lang === "mermaid") widget = new MermaidWidget(code);
        else if (lang === "d2") widget = new D2Widget(code);
        if (!widget) return;

        const endLineNum = state.doc.lineAt(node.to).number;
        const endPos = state.doc.line(endLineNum).to;
        decorations.push(
          Decoration.widget({ widget, block: true, side: 1 }).range(endPos)
        );
      },
    });
    return Decoration.set(decorations, true);
  } catch (err) {
    console.error("diagramBlocks: build failed", err && err.message);
    return Decoration.none;
  }
}

const themeRefreshEffect = StateEffect.define();

export const mermaidBlocks = StateField.define({
  create(state) {
    return buildMermaidBlocks(state);
  },
  update(decorations, tr) {
    if (tr.docChanged) return buildMermaidBlocks(tr.state);
    for (const e of tr.effects) {
      if (e.is(themeRefreshEffect)) {
        mermaidCache.clear();
        return buildMermaidBlocks(tr.state);
      }
    }
    return decorations;
  },
  provide: (f) => EditorView.decorations.from(f),
});

// When the mermaid theme changes externally, dispatch an effect to rebuild
// the block decorations on all active editor views.
export function wireMermaidThemeRefresh(view) {
  const handler = () => {
    view.dispatch({ effects: themeRefreshEffect.of(null) });
  };
  window.addEventListener("mermaid-theme-changed", handler);
  return () => window.removeEventListener("mermaid-theme-changed", handler);
}
