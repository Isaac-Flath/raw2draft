/**
 * Mermaid renderer — statically bundled (vite-plugin-singlefile chokes on
 * dynamic chunks). Handles theme sync and unique IDs.
 */

import mermaid from "mermaid";

let counter = 0;
let initialized = false;
let currentTheme = "default";

function detectTheme() {
  const t = document.documentElement.getAttribute("data-theme");
  return t === "dark" ? "dark" : "default";
}

function ensureInit() {
  if (initialized) return;
  currentTheme = detectTheme();
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "loose",
    theme: currentTheme,
    fontFamily: "'Inter', -apple-system, sans-serif",
  });
  initialized = true;
}

export function nextMermaidId() {
  counter += 1;
  return `mm-${counter}`;
}

export async function renderMermaid(code, id) {
  try {
    ensureInit();
    const theme = detectTheme();
    if (theme !== currentTheme) {
      currentTheme = theme;
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: "loose",
        theme: currentTheme,
        fontFamily: "'Inter', -apple-system, sans-serif",
      });
    }
    const { svg } = await mermaid.render(id, code);
    return { ok: true, svg };
  } catch (err) {
    const msg = err && err.message ? err.message : String(err);
    return { ok: false, error: msg };
  }
}

export function refreshMermaidTheme() {
  const theme = detectTheme();
  if (theme === currentTheme) return;
  currentTheme = theme;
  initialized = false;
  window.dispatchEvent(new CustomEvent("mermaid-theme-changed"));
}
