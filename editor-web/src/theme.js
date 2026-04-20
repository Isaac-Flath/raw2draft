import { EditorView } from "@codemirror/view";
import { HighlightStyle } from "@codemirror/language";
import { tags } from "@lezer/highlight";

export const editorTheme = EditorView.theme({
  "&": {
    height: "100%",
    fontSize: "var(--editor-font-size, 18px)",
    fontFamily: "var(--editor-font, 'Lora'), Georgia, serif",
    backgroundColor: "transparent",
    WebkitFontSmoothing: "antialiased",
  },
  ".cm-content": {
    maxWidth: "var(--editor-content-width, 740px)",
    margin: "0 auto",
    padding: "40px 24px",
    lineHeight: "1.95",
    caretColor: "var(--cm-cursor, #4f46e5)",
  },
  ".cm-scroller": {
    overflow: "auto",
    height: "100%",
  },
  ".cm-gutters": {
    backgroundColor: "transparent",
    borderRight: "none",
    color: "var(--cm-formatting, rgba(120, 113, 108, 0.5))",
  },
  ".cm-activeLine": {
    backgroundColor: "var(--cm-active-line, rgba(79, 70, 229, 0.04))",
  },
  ".cm-selectionBackground": {
    backgroundColor: "var(--cm-selection, rgba(79, 70, 229, 0.15)) !important",
  },
  "&.cm-focused .cm-selectionBackground": {
    backgroundColor: "var(--cm-selection, rgba(79, 70, 229, 0.15)) !important",
  },
  ".cm-cursor": {
    borderLeftColor: "var(--cm-cursor, #4f46e5)",
    borderLeftWidth: "2px",
  },

  // Live preview heading styles — Inter, matching website sizes
  ".cm-heading-1": { fontFamily: "'Inter', -apple-system, sans-serif", fontSize: "2.25rem", fontWeight: "700", lineHeight: "1.2", color: "var(--cm-text, rgb(17, 24, 39))" },
  ".cm-heading-2": { fontFamily: "'Inter', -apple-system, sans-serif", fontSize: "2rem", fontWeight: "700", lineHeight: "1.3", color: "var(--cm-text, rgb(17, 24, 39))" },
  ".cm-heading-3": { fontFamily: "'Inter', -apple-system, sans-serif", fontSize: "1.5rem", fontWeight: "700", lineHeight: "1.3", color: "var(--cm-text, rgb(17, 24, 39))" },
  ".cm-heading-4": { fontFamily: "'Inter', -apple-system, sans-serif", fontSize: "1.125rem", fontWeight: "600", lineHeight: "1.3", color: "var(--cm-text, rgb(17, 24, 39))" },

  // Live preview inline styles
  ".cm-strong": { fontWeight: "700" },
  ".cm-emphasis": { fontStyle: "italic" },
  ".cm-strikethrough": { textDecoration: "line-through" },
  ".cm-code": {
    fontFamily: "'JetBrains Mono', 'SF Mono', monospace",
    fontSize: "0.9em",
    backgroundColor: "var(--cm-code-bg, rgba(79, 70, 229, 0.06))",
    borderRadius: "3px",
    padding: "1px 4px",
  },

  // Inside code block lines, remove per-span background highlight
  ".cm-codeblock-line .cm-code": {
    backgroundColor: "transparent",
    padding: "0",
    borderRadius: "0",
  },

  // Code block line decorations — block-level styling
  ".cm-codeblock-line": {
    backgroundColor: "var(--cm-code-bg, rgba(79, 70, 229, 0.06))",
    fontFamily: "'JetBrains Mono', 'SF Mono', monospace",
    fontSize: "0.9em",
    paddingLeft: "16px !important",
    paddingRight: "16px !important",
  },
  ".cm-codeblock-first": {
    borderTopLeftRadius: "8px",
    borderTopRightRadius: "8px",
    paddingTop: "8px",
  },
  ".cm-codeblock-last": {
    borderBottomLeftRadius: "8px",
    borderBottomRightRadius: "8px",
    paddingBottom: "8px",
  },

  // Blockquotes — per-span style
  ".cm-blockquote": {
    color: "var(--cm-blockquote-text, #6b7280)",
    fontStyle: "italic",
  },

  // Blockquote line decorations — block-level styling
  ".cm-blockquote-line": {
    borderLeft: "4px solid var(--cm-blockquote-border, rgb(165, 180, 252))",
    backgroundColor: "var(--cm-blockquote-bg, rgba(79, 70, 229, 0.04))",
    paddingLeft: "20px !important",
    borderRadius: "0 6px 6px 0",
  },

  // Links
  ".cm-link": {
    color: "var(--cm-link, #818cf8)",
    textDecoration: "underline",
  },

  // Markdown syntax dim
  ".cm-formatting": {
    color: "var(--cm-formatting, rgba(120, 113, 108, 0.5))",
  },

  // Images
  ".cm-image-widget": {
    display: "block",
    maxWidth: "100%",
    borderRadius: "6px",
    margin: "8px 0",
  },

  // Mermaid / D2 live preview
  ".cm-mermaid-widget, .cm-d2-widget": {
    display: "block",
    padding: "16px",
    margin: "8px 0 16px",
    textAlign: "center",
    backgroundColor: "var(--cm-code-bg, rgba(79, 70, 229, 0.06))",
    borderRadius: "8px",
    overflowX: "auto",
    fontFamily: "'Inter', -apple-system, sans-serif",
    fontSize: "13px",
    color: "var(--cm-formatting, rgba(120, 113, 108, 0.6))",
  },
  ".cm-mermaid-widget svg, .cm-d2-widget svg": {
    maxWidth: "100%",
    height: "auto",
  },
  ".cm-mermaid-error": {
    color: "#dc2626",
    textAlign: "left",
    fontFamily: "'JetBrains Mono', 'SF Mono', monospace",
    whiteSpace: "pre-wrap",
  },

  // Frontmatter — compact monospace block, overrides body typography
  ".cm-frontmatter": {
    fontFamily: "'JetBrains Mono', 'SF Mono', Monaco, monospace",
    fontSize: "13px",
    lineHeight: "1.5",
    color: "var(--cm-frontmatter, #78716c)",
    backgroundColor: "var(--cm-code-bg, rgba(79, 70, 229, 0.06))",
    borderRadius: "4px",
  },
  // Prevent heading/bold styles from blowing up frontmatter lines
  ".cm-frontmatter .cm-heading-1, .cm-frontmatter .cm-heading-2, .cm-frontmatter .cm-heading-3, .cm-frontmatter .cm-heading-4": {
    fontSize: "inherit",
    fontFamily: "inherit",
    fontWeight: "inherit",
    lineHeight: "inherit",
    color: "inherit",
  },
  ".cm-frontmatter .cm-strong, .cm-frontmatter .cm-emphasis": {
    fontWeight: "inherit",
    fontStyle: "inherit",
  },

  // Tables — clean grid styling in the editor
  ".cm-table-row": {
    fontFamily: "'JetBrains Mono', 'SF Mono', monospace",
    fontSize: "0.85em",
    lineHeight: "1.7",
    whiteSpace: "pre",
    overflowWrap: "normal",
    wordBreak: "keep-all",
  },
  ".cm-table-header": {
    fontFamily: "'JetBrains Mono', 'SF Mono', monospace",
    fontSize: "0.85em",
    lineHeight: "1.7",
    fontWeight: "600",
    whiteSpace: "pre",
    overflowWrap: "normal",
    wordBreak: "keep-all",
  },
  ".cm-table-separator": {
    fontFamily: "'JetBrains Mono', 'SF Mono', monospace",
    fontSize: "0.85em",
    lineHeight: "1.7",
    color: "var(--cm-formatting, rgba(120, 113, 108, 0.4))",
    whiteSpace: "pre",
    overflowWrap: "normal",
    wordBreak: "keep-all",
  },

  // Focus mode: dim all lines except the active paragraph
  "&[data-focus-mode='true'] .cm-line": {
    opacity: "0.3",
    transition: "opacity 0.2s ease",
  },
  "&[data-focus-mode='true'] .cm-line.cm-paragraph-active": {
    opacity: "1",
  },
});

export const markdownHighlighting = HighlightStyle.define([
  { tag: tags.heading1, class: "cm-heading-1" },
  { tag: tags.heading2, class: "cm-heading-2" },
  { tag: tags.heading3, class: "cm-heading-3" },
  { tag: tags.heading4, class: "cm-heading-4" },
  { tag: tags.strong, class: "cm-strong" },
  { tag: tags.emphasis, class: "cm-emphasis" },
  { tag: tags.strikethrough, class: "cm-strikethrough" },
  { tag: tags.monospace, class: "cm-code" },
  { tag: tags.url, class: "cm-link" },
  { tag: tags.link, class: "cm-link" },
  { tag: tags.processingInstruction, class: "cm-formatting" },
  { tag: tags.contentSeparator, class: "cm-frontmatter" },
  { tag: tags.quote, class: "cm-blockquote" },
]);
