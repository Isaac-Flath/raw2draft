/**
 * Markdown table editing for CodeMirror 6.
 *
 * Features:
 *   - Tab / Shift-Tab to navigate cells and auto-format
 *   - Enter to add a new row
 *   - Backspace on empty row to delete it
 *   - Auto-align columns on every navigation action
 *   - Visual line decorations for table rows
 *   - Cmd+Shift+T to insert a table template
 */

import { keymap, ViewPlugin, Decoration, EditorView } from "@codemirror/view";
import { Prec } from "@codemirror/state";

// ── Helpers ────────────────────────────────────────────────────────────

/** Parse a markdown table line into cell contents (strips leading/trailing pipes). */
function parseCells(line) {
  const trimmed = line.trim();
  if (!trimmed.startsWith("|")) return null;
  // Split on pipes, drop first empty and last empty from leading/trailing |
  const parts = trimmed.split("|");
  // Remove first (before leading |) and last (after trailing |)
  if (parts[0].trim() === "") parts.shift();
  if (parts.length && parts[parts.length - 1].trim() === "") parts.pop();
  return parts.map(p => p.trim());
}

/** Check if a line is a separator row (|---|---|). */
function isSeparatorRow(line) {
  return /^\s*\|[\s:]*-+[\s:]*(\|[\s:]*-*[\s:]*)*\|\s*$/.test(line);
}

/** Check if a doc line looks like a table row. */
function isTableRow(lineText) {
  const t = lineText.trim();
  return t.startsWith("|") && t.endsWith("|") && t.length > 1;
}

/**
 * Find the full extent of a table around a given line number.
 * Returns { startLine, endLine } (1-based CodeMirror line numbers) or null.
 */
function findTableRange(doc, lineNo) {
  const line = doc.line(lineNo);
  if (!isTableRow(line.text)) return null;

  let startLine = lineNo;
  while (startLine > 1 && isTableRow(doc.line(startLine - 1).text)) startLine--;

  let endLine = lineNo;
  const total = doc.lines;
  while (endLine < total && isTableRow(doc.line(endLine + 1).text)) endLine++;

  return { startLine, endLine };
}

/**
 * Reformat a table so every column is padded to the same width.
 * Returns the formatted string (no trailing newline).
 */
function formatTable(doc, startLine, endLine) {
  const rows = [];
  for (let i = startLine; i <= endLine; i++) {
    rows.push(doc.line(i).text);
  }

  // Parse every row into cells
  const parsed = rows.map(parseCells);
  const colCount = Math.max(...parsed.map(c => (c ? c.length : 0)));
  if (colCount === 0) return null;

  // Normalise each row to have exactly colCount cells
  const normalised = parsed.map(cells => {
    const c = cells ? cells.slice() : [];
    while (c.length < colCount) c.push("");
    return c;
  });

  // Compute max width per column (minimum 3 for separator dashes)
  const widths = Array.from({ length: colCount }, () => 3);
  normalised.forEach((cells, rowIdx) => {
    if (isSeparatorRow(rows[rowIdx])) return; // skip separator for width calc
    cells.forEach((cell, col) => {
      widths[col] = Math.max(widths[col], cell.length);
    });
  });

  // Rebuild each row
  const formatted = normalised.map((cells, rowIdx) => {
    if (isSeparatorRow(rows[rowIdx])) {
      // Preserve alignment colons
      const sepCells = cells.map((_, col) => {
        const orig = (parsed[rowIdx] || [])[col] || "";
        const leftColon = orig.startsWith(":");
        const rightColon = orig.endsWith(":");
        const dashes = "-".repeat(widths[col]);
        if (leftColon && rightColon) return ":" + "-".repeat(widths[col] - 2) + ":";
        if (leftColon) return ":" + "-".repeat(widths[col] - 1);
        if (rightColon) return "-".repeat(widths[col] - 1) + ":";
        return dashes;
      });
      return "| " + sepCells.join(" | ") + " |";
    }
    const padded = cells.map((cell, col) => cell.padEnd(widths[col]));
    return "| " + padded.join(" | ") + " |";
  });

  return formatted.join("\n");
}

/**
 * Find which cell the cursor is in.
 * Returns { row (0-based from startLine), col (0-based) } or null.
 */
function cellAtPos(doc, pos, startLine) {
  const line = doc.lineAt(pos);
  const lineNo = line.number;
  const row = lineNo - startLine;
  const text = line.text;
  if (!isTableRow(text)) return null;

  // Walk through the line character by character, counting pipe-separated cells
  let col = -1; // -1 until we pass the first |
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "|") col++;
    if (i >= pos - line.from) break;
  }
  return { row, col: Math.max(0, col) };
}

// ── Commands ───────────────────────────────────────────────────────────

/** Format the table under the cursor (if any). Returns true if formatted. */
function formatTableAtCursor(view) {
  const pos = view.state.selection.main.head;
  const lineNo = view.state.doc.lineAt(pos).number;
  const range = findTableRange(view.state.doc, lineNo);
  if (!range) return false;

  const formatted = formatTable(view.state.doc, range.startLine, range.endLine);
  if (!formatted) return false;

  const from = view.state.doc.line(range.startLine).from;
  const to = view.state.doc.line(range.endLine).to;
  const oldText = view.state.doc.sliceString(from, to);
  if (formatted === oldText) return true; // already formatted

  // Compute where cursor should land in the new text
  const offsetInTable = pos - from;
  // Map offset through the reformat — find same row/col position
  const cell = cellAtPos(view.state.doc, pos, range.startLine);

  view.dispatch({ changes: { from, to, insert: formatted } });

  // Restore cursor to the same cell
  if (cell) {
    placeCursorInCell(view, range.startLine, cell.row, cell.col);
  }

  return true;
}

/** Place cursor at the start of content in a given cell. */
function placeCursorInCell(view, tableStartLine, row, col) {
  const lineNo = tableStartLine + row;
  if (lineNo < 1 || lineNo > view.state.doc.lines) return;
  const line = view.state.doc.line(lineNo);
  const text = line.text;

  // Find the position just after the col-th pipe
  let pipeCount = 0;
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "|") {
      if (pipeCount === col) {
        // Move past pipe and space
        let start = i + 1;
        if (text[start] === " ") start++;
        // Find end of cell content (before next pipe, trimming trailing space)
        let end = text.indexOf("|", start);
        if (end === -1) end = text.length;
        // Trim trailing spaces for selection end
        let contentEnd = end;
        while (contentEnd > start && text[contentEnd - 1] === " ") contentEnd--;

        view.dispatch({
          selection: { anchor: line.from + start, head: line.from + contentEnd },
        });
        return;
      }
      pipeCount++;
    }
  }
}

/** Tab: move to next cell, auto-format. */
function tableTab(view) {
  const pos = view.state.selection.main.head;
  const doc = view.state.doc;
  const lineNo = doc.lineAt(pos).number;
  const range = findTableRange(doc, lineNo);
  if (!range) return false;

  // Format first
  const formatted = formatTable(doc, range.startLine, range.endLine);
  if (formatted) {
    const from = doc.line(range.startLine).from;
    const to = doc.line(range.endLine).to;
    if (formatted !== doc.sliceString(from, to)) {
      view.dispatch({ changes: { from, to, insert: formatted } });
    }
  }

  // Find current cell and move to next
  const cell = cellAtPos(view.state.doc, view.state.selection.main.head, range.startLine);
  if (!cell) return false;

  const totalRows = range.endLine - range.startLine + 1;
  const firstRowCells = parseCells(view.state.doc.line(range.startLine).text);
  const colCount = firstRowCells ? firstRowCells.length : 1;

  let nextRow = cell.row;
  let nextCol = cell.col + 1;

  if (nextCol >= colCount) {
    nextCol = 0;
    nextRow++;
  }
  // Skip separator rows
  while (nextRow < totalRows && isSeparatorRow(view.state.doc.line(range.startLine + nextRow).text)) {
    nextRow++;
  }
  if (nextRow >= totalRows) {
    // At end of table — add a new row with matching column widths
    const lastLine = view.state.doc.line(range.endLine);
    const headerParts = parseCells(view.state.doc.line(range.startLine).text);
    const widths = headerParts ? headerParts.map(p => Math.max(p.length, 3)) : [3];
    const newRow = "| " + widths.map(w => " ".repeat(w)).join(" | ") + " |";

    view.dispatch({
      changes: { from: lastLine.to, insert: "\n" + newRow },
    });
    placeCursorInCell(view, range.startLine, totalRows, 0);
    return true;
  }

  placeCursorInCell(view, range.startLine, nextRow, nextCol);
  return true;
}

/** Shift-Tab: move to previous cell, auto-format. */
function tableShiftTab(view) {
  const pos = view.state.selection.main.head;
  const doc = view.state.doc;
  const lineNo = doc.lineAt(pos).number;
  const range = findTableRange(doc, lineNo);
  if (!range) return false;

  // Format first
  const formatted = formatTable(doc, range.startLine, range.endLine);
  if (formatted) {
    const from = doc.line(range.startLine).from;
    const to = doc.line(range.endLine).to;
    if (formatted !== doc.sliceString(from, to)) {
      view.dispatch({ changes: { from, to, insert: formatted } });
    }
  }

  const cell = cellAtPos(view.state.doc, view.state.selection.main.head, range.startLine);
  if (!cell) return false;

  const firstRowCells = parseCells(view.state.doc.line(range.startLine).text);
  const colCount = firstRowCells ? firstRowCells.length : 1;

  let prevRow = cell.row;
  let prevCol = cell.col - 1;

  if (prevCol < 0) {
    prevCol = colCount - 1;
    prevRow--;
  }
  // Skip separator rows
  while (prevRow >= 0 && isSeparatorRow(view.state.doc.line(range.startLine + prevRow).text)) {
    prevRow--;
  }
  if (prevRow < 0) return true; // Already at the start

  placeCursorInCell(view, range.startLine, prevRow, prevCol);
  return true;
}

/** Enter in a table: add a new row below the current one. */
function tableEnter(view) {
  const pos = view.state.selection.main.head;
  const doc = view.state.doc;
  const lineNo = doc.lineAt(pos).number;
  const range = findTableRange(doc, lineNo);
  if (!range) return false;

  // Format first
  const formatted = formatTable(doc, range.startLine, range.endLine);
  if (formatted) {
    const from = doc.line(range.startLine).from;
    const to = doc.line(range.endLine).to;
    if (formatted !== doc.sliceString(from, to)) {
      view.dispatch({ changes: { from, to, insert: formatted } });
    }
  }

  // Build empty row matching column widths
  const headerCells = parseCells(view.state.doc.line(range.startLine).text);
  const colCount = headerCells ? headerCells.length : 1;

  // Get widths from the formatted header
  const parts = parseCells(view.state.doc.line(range.startLine).text);
  const widths = parts ? parts.map(p => Math.max(p.length, 3)) : [3];
  const newRow = "| " + widths.map(w => " ".repeat(w)).join(" | ") + " |";

  // Insert after current line
  const currentLine = view.state.doc.lineAt(view.state.selection.main.head);
  view.dispatch({
    changes: { from: currentLine.to, insert: "\n" + newRow },
  });

  // Place cursor in first cell of new row
  const newRowLineNo = currentLine.number + 1;
  const rowIdx = newRowLineNo - range.startLine;
  placeCursorInCell(view, range.startLine, rowIdx, 0);
  return true;
}

/** Backspace at start of an empty table data row — delete the row. */
function tableBackspace(view) {
  const { from, to } = view.state.selection.main;
  if (from !== to) return false; // has selection, use default

  const doc = view.state.doc;
  const lineNo = doc.lineAt(from).number;
  const range = findTableRange(doc, lineNo);
  if (!range) return false;

  // Only act on empty data rows (not header or separator)
  const line = doc.line(lineNo);
  if (isSeparatorRow(line.text)) return false;

  const cells = parseCells(line.text);
  if (!cells || cells.some(c => c.trim() !== "")) return false;

  // Don't delete if it's the header row
  if (lineNo === range.startLine) return false;

  // Delete the entire line (including the preceding newline)
  const deleteFrom = line.from - 1; // the \n before this line
  view.dispatch({
    changes: { from: Math.max(0, deleteFrom), to: line.to },
  });
  return true;
}

/** Insert a new 3×2 table at cursor. */
export function insertTableCommand(view) {
  const pos = view.state.selection.main.head;
  const doc = view.state.doc;
  const line = doc.lineAt(pos);

  const prefix = line.text.trim() !== "" ? "\n\n" : "";
  const insertPos = line.text.trim() !== "" ? line.to : line.from;

  const table = [
    "| Header 1 | Header 2 | Header 3 |",
    "| -------- | -------- | -------- |",
    "|          |          |          |",
  ].join("\n");

  // Position cursor in first cell of data row (after "| ")
  const dataRowOffset = prefix.length + table.indexOf("|          |") + 2;

  view.dispatch({
    changes: { from: insertPos, insert: prefix + table + "\n" },
    selection: { anchor: insertPos + dataRowOffset, head: insertPos + dataRowOffset },
  });

  return true;
}

// ── Line decorations ───────────────────────────────────────────────────

const tableRowDeco = Decoration.line({ class: "cm-table-row" });
const tableSeparatorDeco = Decoration.line({ class: "cm-table-row cm-table-separator" });
const tableHeaderDeco = Decoration.line({ class: "cm-table-row cm-table-header" });

function buildTableDecorations(view) {
  const decorations = [];
  const doc = view.state.doc;

  for (const { from, to } of view.visibleRanges) {
    let lineNo = doc.lineAt(from).number;
    const endLineNo = doc.lineAt(to).number;

    while (lineNo <= endLineNo) {
      const line = doc.line(lineNo);
      if (isTableRow(line.text)) {
        // Find the full table range to identify header vs separator vs data
        const range = findTableRange(doc, lineNo);
        if (range) {
          for (let i = range.startLine; i <= range.endLine && i <= endLineNo; i++) {
            const tLine = doc.line(i);
            if (i === range.startLine) {
              decorations.push(tableHeaderDeco.range(tLine.from));
            } else if (isSeparatorRow(tLine.text)) {
              decorations.push(tableSeparatorDeco.range(tLine.from));
            } else {
              decorations.push(tableRowDeco.range(tLine.from));
            }
          }
          lineNo = range.endLine + 1;
          continue;
        }
      }
      lineNo++;
    }
  }

  return Decoration.set(decorations, true);
}

// ── Auto-format on cursor enter ────────────────────────────────────────

/**
 * When the cursor moves into a table that hasn't been formatted yet,
 * auto-align it. Tracks the last-formatted table range to avoid loops.
 */
function autoFormatListener() {
  let lastFormatted = null; // "startLine:endLine:docLength" key

  return EditorView.updateListener.of((update) => {
    if (!update.selectionSet && !update.docChanged) return;

    const view = update.view;
    const pos = view.state.selection.main.head;
    const lineNo = view.state.doc.lineAt(pos).number;
    const range = findTableRange(view.state.doc, lineNo);

    if (!range) {
      lastFormatted = null;
      return;
    }

    // Build a key to identify this table + its content
    const from = view.state.doc.line(range.startLine).from;
    const to = view.state.doc.line(range.endLine).to;
    const content = view.state.doc.sliceString(from, to);
    const key = `${range.startLine}:${range.endLine}:${content.length}`;

    if (key === lastFormatted) return; // already formatted this version

    const formatted = formatTable(view.state.doc, range.startLine, range.endLine);
    if (!formatted || formatted === content) {
      lastFormatted = key;
      return;
    }

    // Remember the cell the cursor is in before reformatting
    const cell = cellAtPos(view.state.doc, pos, range.startLine);

    // Use requestAnimationFrame to avoid dispatching during an update
    requestAnimationFrame(() => {
      const currentPos = view.state.selection.main.head;
      const currentLineNo = view.state.doc.lineAt(currentPos).number;
      const currentRange = findTableRange(view.state.doc, currentLineNo);
      if (!currentRange || currentRange.startLine !== range.startLine) return;

      const curFrom = view.state.doc.line(currentRange.startLine).from;
      const curTo = view.state.doc.line(currentRange.endLine).to;
      const curContent = view.state.doc.sliceString(curFrom, curTo);
      const newFormatted = formatTable(view.state.doc, currentRange.startLine, currentRange.endLine);
      if (!newFormatted || newFormatted === curContent) return;

      view.dispatch({ changes: { from: curFrom, to: curTo, insert: newFormatted } });

      if (cell) {
        placeCursorInCell(view, currentRange.startLine, cell.row, cell.col);
      }

      lastFormatted = `${currentRange.startLine}:${currentRange.endLine}:${newFormatted.length}`;
    });
  });
}

// ── Exports ────────────────────────────────────────────────────────────

export function tableEditing() {
  return [
    Prec.high(keymap.of([
      {
        key: "Tab",
        run: tableTab,
      },
      {
        key: "Shift-Tab",
        run: tableShiftTab,
      },
      {
        key: "Enter",
        run: tableEnter,
      },
      {
        key: "Backspace",
        run: tableBackspace,
      },
      {
        key: "Mod-Shift-t",
        run: insertTableCommand,
      },
    ])),
    autoFormatListener(),
    ViewPlugin.fromClass(
      class {
        constructor(view) {
          this.decorations = buildTableDecorations(view);
        }
        update(update) {
          if (update.docChanged || update.viewportChanged) {
            this.decorations = buildTableDecorations(update.view);
          }
        }
      },
      { decorations: (v) => v.decorations }
    ),
  ];
}
