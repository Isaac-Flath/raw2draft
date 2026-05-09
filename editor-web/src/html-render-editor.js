const BASE_ID = "raw2draft-html-base";
const STYLE_ID = "raw2draft-html-editor-style";

function postLog(level, msg) {
  try {
    window.webkit?.messageHandlers?.editor?.postMessage({ type: "log", level, msg });
  } catch {
    // Not running inside WKWebView.
  }
}

function serializeDoctype(doctype) {
  if (!doctype) return "";

  let value = `<!DOCTYPE ${doctype.name}`;
  if (doctype.publicId) {
    value += ` PUBLIC "${doctype.publicId}"`;
    if (doctype.systemId) value += ` "${doctype.systemId}"`;
  } else if (doctype.systemId) {
    value += ` SYSTEM "${doctype.systemId}"`;
  }
  return `${value}>`;
}

function cssEscape(value) {
  if (window.CSS?.escape) return window.CSS.escape(value);
  return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
}

function serializeDocument(doc, { removeInjected = true } = {}) {
  const clone = doc.documentElement.cloneNode(true);
  if (removeInjected) {
    const injected = clone.querySelectorAll(`#${cssEscape(BASE_ID)}, #${cssEscape(STYLE_ID)}`);
    injected.forEach((node) => node.remove());
  }

  const doctype = serializeDoctype(doc.doctype);
  return `${doctype ? `${doctype}\n` : ""}${clone.outerHTML}`;
}

function baseHrefForDirectory(dir) {
  if (!dir) return null;
  const clean = dir.endsWith("/") ? dir : `${dir}/`;
  return `r2dasset://${clean.split("/").map(encodeURIComponent).join("/")}`;
}

function buildFrameDocument(html, baseDir) {
  const parser = new DOMParser();
  const doc = parser.parseFromString(html || "", "text/html");

  doc.getElementById(BASE_ID)?.remove();
  doc.getElementById(STYLE_ID)?.remove();

  const baseHref = baseHrefForDirectory(baseDir);
  if (baseHref) {
    const base = doc.createElement("base");
    base.id = BASE_ID;
    base.href = baseHref;
    doc.head.prepend(base);
  }

  return serializeDocument(doc, { removeInjected: false });
}

function installEditorStyle(doc) {
  doc.getElementById(STYLE_ID)?.remove();
  const style = doc.createElement("style");
  style.id = STYLE_ID;
  style.textContent = `
    html {
      -webkit-user-modify: read-write-plaintext-only;
    }
    body {
      min-height: 100vh;
    }
    :focus {
      outline-color: rgba(79, 70, 229, 0.55);
      outline-offset: 2px;
    }
    ::selection {
      background: rgba(79, 70, 229, 0.18);
    }
  `;
  doc.head.appendChild(style);
}

export function createHtmlRenderEditor({ onContentChanged, onSave } = {}) {
  const host = document.createElement("div");
  host.id = "html-editor";
  host.className = "html-editor";
  host.style.display = "none";

  const iframe = document.createElement("iframe");
  iframe.title = "Rendered HTML editor";
  // Keep the iframe same-origin so Raw2Draft can serialize edits, but do not
  // allow page scripts to execute. User HTML can contain scripts and they are
  // preserved on save, but edit mode must not let arbitrary page JS hijack or
  // hang the WebView.
  iframe.setAttribute("sandbox", "allow-same-origin");
  host.appendChild(iframe);

  let visible = false;
  let baseDir = null;
  let currentContent = "";
  let debounceTimer = null;
  let hasPendingChange = false;

  function flushChanges() {
    if (!hasPendingChange) return currentContent;

    const doc = iframe.contentDocument;
    if (!doc?.documentElement) return currentContent;

    const nextContent = serializeDocument(doc);
    hasPendingChange = false;
    if (nextContent !== currentContent) {
      currentContent = nextContent;
      onContentChanged?.(currentContent);
    }
    return currentContent;
  }

  function scheduleChange() {
    hasPendingChange = true;
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(flushChanges, 160);
  }

  function installFrameEditing() {
    const doc = iframe.contentDocument;
    if (!doc?.body) return;

    try {
      installEditorStyle(doc);
      doc.designMode = "on";

      doc.addEventListener("input", scheduleChange, true);
      doc.addEventListener("paste", scheduleChange, true);
      doc.addEventListener("focusout", flushChanges, true);

      doc.addEventListener("keydown", (event) => {
        const wantsSave = (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s";
        if (!wantsSave) return;
        event.preventDefault();
        flushChanges();
        onSave?.();
      }, true);

      doc.addEventListener("click", (event) => {
        if (event.target?.closest?.("a")) {
          event.preventDefault();
        }
      }, true);
    } catch (error) {
      postLog("error", `Failed to enable HTML editing: ${error?.message || error}`);
    }
  }

  iframe.addEventListener("load", installFrameEditing);

  return {
    element: host,

    setVisible(nextVisible) {
      visible = nextVisible;
      host.style.display = visible ? "block" : "none";
      if (visible) {
        if (currentContent && !iframe.srcdoc) {
          iframe.removeAttribute("src");
          iframe.srcdoc = buildFrameDocument(currentContent, baseDir);
        }
        this.focus();
      } else {
        flushChanges();
        iframe.removeAttribute("srcdoc");
        iframe.src = "about:blank";
      }
    },

    setBaseDir(dir) {
      flushChanges();
      const nextBaseDir = dir || null;
      if (nextBaseDir === baseDir) return;
      baseDir = nextBaseDir;
      if (currentContent || visible) {
        iframe.srcdoc = buildFrameDocument(currentContent, baseDir);
      }
    },

    setContent(html) {
      const nextContent = html || "";
      if (nextContent === currentContent && iframe.srcdoc) return;
      currentContent = nextContent;
      hasPendingChange = false;
      clearTimeout(debounceTimer);
      iframe.srcdoc = buildFrameDocument(currentContent, baseDir);
    },

    getContent() {
      clearTimeout(debounceTimer);
      return flushChanges();
    },

    focus() {
      iframe.contentWindow?.focus();
    },
  };
}
