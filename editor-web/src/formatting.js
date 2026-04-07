/**
 * Markdown formatting commands for CodeMirror 6.
 * Cmd+B (bold), Cmd+I (italic), Cmd+K (link).
 */

function toggleWrap(view, marker) {
  const { from, to } = view.state.selection.main;
  const selected = view.state.doc.sliceString(from, to);
  const len = marker.length;

  // Check if selection is already wrapped
  const before = view.state.doc.sliceString(Math.max(0, from - len), from);
  const after = view.state.doc.sliceString(to, to + len);

  if (before === marker && after === marker) {
    // Unwrap: remove markers around selection
    view.dispatch({
      changes: [
        { from: from - len, to: from, insert: "" },
        { from: to, to: to + len, insert: "" },
      ],
      selection: { anchor: from - len, head: to - len },
    });
  } else if (selected.startsWith(marker) && selected.endsWith(marker) && selected.length >= len * 2) {
    // Unwrap: markers inside selection
    view.dispatch({
      changes: { from, to, insert: selected.slice(len, -len) },
      selection: { anchor: from, head: to - len * 2 },
    });
  } else {
    // Wrap selection with markers
    const wrapped = `${marker}${selected}${marker}`;
    view.dispatch({
      changes: { from, to, insert: wrapped },
      selection: { anchor: from + len, head: to + len },
    });
  }

  return true;
}

export function boldCommand(view) {
  return toggleWrap(view, "**");
}

export function italicCommand(view) {
  return toggleWrap(view, "_");
}

export function linkCommand(view) {
  const { from, to } = view.state.selection.main;
  const selected = view.state.doc.sliceString(from, to);

  if (selected) {
    // Wrap selected text as link, place cursor in URL
    const insert = `[${selected}](url)`;
    view.dispatch({
      changes: { from, to, insert },
      selection: { anchor: from + selected.length + 2, head: from + selected.length + 5 },
    });
  } else {
    // Insert empty link template, place cursor in text
    const insert = "[text](url)";
    view.dispatch({
      changes: { from, insert },
      selection: { anchor: from + 1, head: from + 5 },
    });
  }

  return true;
}
