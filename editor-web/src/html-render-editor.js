const BASE_ID = "raw2draft-html-base";
const STYLE_ID = "raw2draft-html-editor-style";
const EDIT_ID_ATTR = "data-r2d-edit-id";
const EDITING_ATTR = "data-r2d-editing";
const ADDED_CONTENTEDITABLE_ATTR = "data-r2d-added-contenteditable";
const ORIGINAL_CONTENTEDITABLE_ATTR = "data-r2d-original-contenteditable";
const ADDED_SPELLCHECK_ATTR = "data-r2d-added-spellcheck";
const ORIGINAL_SPELLCHECK_ATTR = "data-r2d-original-spellcheck";

const NON_EDITABLE_SELECTOR = [
  "html",
  "head",
  "body",
  "script",
  "style",
  "template",
  "svg",
  "canvas",
  "iframe",
  "object",
  "embed",
  "img",
  "picture",
  "video",
  "audio",
  "input",
  "textarea",
  "select",
  "option",
].join(",");

const TEXT_CONTAINER_SELECTOR = [
  "a",
  "button",
  "caption",
  "cite",
  "code",
  "dd",
  "dt",
  "em",
  "figcaption",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "label",
  "legend",
  "li",
  "p",
  "pre",
  "q",
  "small",
  "span",
  "strong",
  "summary",
  "td",
  "th",
  "time",
  "[role='button']",
  "[role='tab']",
].join(",");

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
    removeEditorArtifacts(clone);
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

  removeEditorArtifacts(doc.documentElement);
  assignEditIds(doc);

  const baseHref = baseHrefForDirectory(baseDir);
  if (baseHref) {
    const base = doc.createElement("base");
    base.id = BASE_ID;
    base.href = baseHref;
    doc.head.prepend(base);
  }

  return serializeDocument(doc, { removeInjected: false });
}

function getMatchingElements(root, selector) {
  const elements = [];
  if (root.matches?.(selector)) elements.push(root);
  root.querySelectorAll?.(selector).forEach((element) => elements.push(element));
  return elements;
}

function restoreEditorManagedAttrs(element) {
  if (element.hasAttribute(ADDED_CONTENTEDITABLE_ATTR)) {
    element.removeAttribute("contenteditable");
  } else if (element.hasAttribute(ORIGINAL_CONTENTEDITABLE_ATTR)) {
    element.setAttribute("contenteditable", element.getAttribute(ORIGINAL_CONTENTEDITABLE_ATTR));
  }

  if (element.hasAttribute(ADDED_SPELLCHECK_ATTR)) {
    element.removeAttribute("spellcheck");
  } else if (element.hasAttribute(ORIGINAL_SPELLCHECK_ATTR)) {
    element.setAttribute("spellcheck", element.getAttribute(ORIGINAL_SPELLCHECK_ATTR));
  }

  element.removeAttribute(EDITING_ATTR);
  element.removeAttribute(ADDED_CONTENTEDITABLE_ATTR);
  element.removeAttribute(ORIGINAL_CONTENTEDITABLE_ATTR);
  element.removeAttribute(ADDED_SPELLCHECK_ATTR);
  element.removeAttribute(ORIGINAL_SPELLCHECK_ATTR);
}

function removeEditorArtifacts(root) {
  getMatchingElements(root, `#${cssEscape(BASE_ID)}, #${cssEscape(STYLE_ID)}`).forEach((node) => node.remove());
  getMatchingElements(root, `[${EDITING_ATTR}]`).forEach(restoreEditorManagedAttrs);
  getMatchingElements(root, `[${EDIT_ID_ATTR}]`).forEach((element) => element.removeAttribute(EDIT_ID_ATTR));
}

function canAssignEditId(element) {
  if (!element || element.matches(NON_EDITABLE_SELECTOR)) return false;
  return !element.closest("head,script,style,template,svg,canvas,iframe,object,embed");
}

function assignEditIds(doc) {
  let nextId = 0;
  doc.body?.querySelectorAll("*").forEach((element) => {
    if (!canAssignEditId(element)) return;
    element.setAttribute(EDIT_ID_ATTR, String(nextId));
    nextId += 1;
  });
}

function hasDirectText(element) {
  return Array.from(element.childNodes).some((node) => node.nodeType === 3 && node.nodeValue.trim());
}

function hasVisibleText(element) {
  return Boolean(element.textContent?.replace(/\s+/g, " ").trim());
}

function isEditableCandidate(element) {
  if (!element?.hasAttribute?.(EDIT_ID_ATTR)) return false;
  if (element.matches(NON_EDITABLE_SELECTOR)) return false;
  if (element.closest("script,style,template,svg,canvas,iframe,object,embed,input,textarea,select")) return false;
  return hasVisibleText(element);
}

function textNodeFromPoint(doc, x, y) {
  const range = doc.caretRangeFromPoint?.(x, y);
  if (range?.startContainer?.nodeType === 3) return range.startContainer;

  const position = doc.caretPositionFromPoint?.(x, y);
  if (position?.offsetNode?.nodeType === 3) return position.offsetNode;

  return null;
}

function findTextEditTarget(doc, event) {
  const pointNode = textNodeFromPoint(doc, event.clientX, event.clientY);
  const start = pointNode?.parentElement || event.target?.closest?.(`[${EDIT_ID_ATTR}]`);
  for (let element = start; element && element !== doc.body; element = element.parentElement) {
    if (!isEditableCandidate(element)) continue;
    if (element.matches(TEXT_CONTAINER_SELECTOR) || hasDirectText(element)) return element;
  }
  return null;
}

function cleanEditedElement(element) {
  const clone = element.cloneNode(true);
  removeEditorArtifacts(clone);
  return clone;
}

function patchSourceElementContent(sourceHtml, editId, editedElement) {
  if (!editId) return null;

  const parser = new DOMParser();
  const doc = parser.parseFromString(sourceHtml || "", "text/html");
  removeEditorArtifacts(doc.documentElement);
  assignEditIds(doc);

  const selector = `[${EDIT_ID_ATTR}='${cssEscape(editId)}']`;
  const sourceElement = doc.querySelector(selector);
  if (!sourceElement) return null;

  sourceElement.innerHTML = cleanEditedElement(editedElement).innerHTML;
  return serializeDocument(doc);
}

function installEditorStyle(doc) {
  doc.getElementById(STYLE_ID)?.remove();
  const style = doc.createElement("style");
  style.id = STYLE_ID;
  style.textContent = `
    body {
      min-height: 100vh;
    }
    [${EDITING_ATTR}="true"] {
      outline: 2px solid rgba(79, 70, 229, 0.62) !important;
      outline-offset: 2px !important;
      cursor: text !important;
      -webkit-user-modify: read-write-plaintext-only;
      user-select: text;
    }
    [${EDITING_ATTR}="true"] * {
      cursor: text !important;
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

function isExternalNavigation(anchor, doc) {
  const href = anchor.getAttribute("href")?.trim();
  if (!href || href.startsWith("#")) return false;
  if (/^(javascript:|mailto:|tel:)/i.test(href)) return false;

  try {
    const url = new URL(anchor.href, doc.location.href);
    const current = new URL(doc.location.href);
    return url.origin !== current.origin || url.pathname !== current.pathname || url.search !== current.search;
  } catch {
    return true;
  }
}

export function createHtmlRenderEditor({ onContentChanged, onSave } = {}) {
  const host = document.createElement("div");
  host.id = "html-editor";
  host.className = "html-editor";
  host.style.display = "none";

  const iframe = document.createElement("iframe");
  iframe.title = "Rendered HTML editor";
  // Same-origin access lets Raw2Draft save targeted text edits back into the
  // source document. Scripts are enabled so trusted static HTML behaves like it
  // does in a browser while editing is entered deliberately per element.
  iframe.setAttribute("sandbox", "allow-same-origin allow-scripts allow-forms");
  host.appendChild(iframe);

  let visible = false;
  let baseDir = null;
  let currentContent = "";
  let debounceTimer = null;
  let hasPendingChange = false;
  let activeEditable = null;

  function flushChanges() {
    clearTimeout(debounceTimer);

    if (activeEditable) return syncActiveEdit();
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

  function syncActiveEdit() {
    if (!activeEditable) return currentContent;

    const editId = activeEditable.getAttribute(EDIT_ID_ATTR);
    const nextContent = patchSourceElementContent(currentContent, editId, activeEditable);
    hasPendingChange = false;
    if (nextContent && nextContent !== currentContent) {
      currentContent = nextContent;
      onContentChanged?.(currentContent);
    }
    return currentContent;
  }

  function deactivateActiveEdit({ sync = true } = {}) {
    if (!activeEditable) return;
    const element = activeEditable;
    if (sync) syncActiveEdit();
    activeEditable = null;
    restoreEditorManagedAttrs(element);
  }

  function placeCaretFromPoint(doc, x, y, fallbackElement) {
    const selection = doc.getSelection();
    if (!selection) return;

    let range = doc.caretRangeFromPoint?.(x, y);
    if (!range) {
      const position = doc.caretPositionFromPoint?.(x, y);
      if (position) {
        range = doc.createRange();
        range.setStart(position.offsetNode, position.offset);
        range.collapse(true);
      }
    }

    if (!range || !fallbackElement.contains(range.startContainer)) {
      range = doc.createRange();
      range.selectNodeContents(fallbackElement);
      range.collapse(false);
    }

    selection.removeAllRanges();
    selection.addRange(range);
  }

  function activateTextEdit(element, event) {
    if (!element) return false;
    if (activeEditable && activeEditable !== element) deactivateActiveEdit();

    activeEditable = element;
    if (element.hasAttribute("contenteditable")) {
      element.setAttribute(ORIGINAL_CONTENTEDITABLE_ATTR, element.getAttribute("contenteditable"));
    } else {
      element.setAttribute(ADDED_CONTENTEDITABLE_ATTR, "true");
    }

    if (element.hasAttribute("spellcheck")) {
      element.setAttribute(ORIGINAL_SPELLCHECK_ATTR, element.getAttribute("spellcheck"));
    } else {
      element.setAttribute(ADDED_SPELLCHECK_ATTR, "true");
    }

    element.setAttribute("contenteditable", "plaintext-only");
    element.setAttribute("spellcheck", "true");
    element.setAttribute(EDITING_ATTR, "true");
    element.focus({ preventScroll: true });
    placeCaretFromPoint(element.ownerDocument, event.clientX, event.clientY, element);
    return true;
  }

  function activateTextEditFromEvent(event) {
    const doc = iframe.contentDocument;
    if (!doc?.body) return false;
    return activateTextEdit(findTextEditTarget(doc, event), event);
  }

  function installFrameEditing() {
    const doc = iframe.contentDocument;
    if (!doc?.body) return;

    try {
      installEditorStyle(doc);
      doc.designMode = "off";

      doc.addEventListener("beforeinput", (event) => {
        if (!activeEditable?.contains(event.target)) return;
        event.stopPropagation();
      }, true);

      doc.addEventListener("input", (event) => {
        if (!activeEditable?.contains(event.target)) return;
        event.stopPropagation();
        scheduleChange();
      }, true);

      doc.addEventListener("paste", (event) => {
        if (!activeEditable?.contains(event.target)) return;
        event.stopPropagation();
        scheduleChange();
      }, true);

      doc.addEventListener("focusout", (event) => {
        if (!activeEditable?.contains(event.target)) return;
        setTimeout(() => {
          if (activeEditable && !activeEditable.contains(doc.activeElement)) {
            deactivateActiveEdit();
          }
        }, 0);
      }, true);

      doc.addEventListener("keydown", (event) => {
        const wantsSave = (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s";
        if (wantsSave) {
          event.preventDefault();
          flushChanges();
          onSave?.();
          return;
        }

        if (!activeEditable) return;
        if (event.key === "Escape") {
          event.preventDefault();
          deactivateActiveEdit();
        }
        event.stopPropagation();
      }, true);

      doc.addEventListener("click", (event) => {
        if (activeEditable) {
          if (activeEditable.contains(event.target)) {
            event.stopPropagation();
            return;
          }
          deactivateActiveEdit();
        }

        if (event.altKey && activateTextEditFromEvent(event)) {
          event.preventDefault();
          event.stopPropagation();
          return;
        }

        const anchor = event.target?.closest?.("a[href]");
        if (anchor && isExternalNavigation(anchor, doc)) {
          event.preventDefault();
        }
      }, true);

      doc.addEventListener("dblclick", (event) => {
        if (!activateTextEditFromEvent(event)) return;
        event.preventDefault();
        event.stopPropagation();
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
        deactivateActiveEdit();
        flushChanges();
        iframe.removeAttribute("srcdoc");
        iframe.src = "about:blank";
      }
    },

    setBaseDir(dir) {
      deactivateActiveEdit();
      flushChanges();
      const nextBaseDir = dir || null;
      if (nextBaseDir === baseDir) return;
      baseDir = nextBaseDir;
      if (currentContent || visible) {
        iframe.srcdoc = buildFrameDocument(currentContent, baseDir);
      }
    },

    setContent(html) {
      deactivateActiveEdit();
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
