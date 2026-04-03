---
name: cc-history
description: >
  Search and retrieve the user's Claude Code conversation history from a SQLite database.
  Use when the user asks about past conversations, wants to find something they discussed before,
  needs examples from their coding history, references prior work sessions, or wants to research
  patterns in how they work. Supports full-text search, semantic search, and reading full conversations.
---

# Claude Code History Search

Search and retrieve conversations from the user's Claude Code history. The history is stored in a SQLite database at `~/.claude/cc.db` with full-text and semantic search indexes.

## Quick start

Before searching, always sync to pick up new conversations:

```bash
uv run ${CLAUDE_SKILL_DIR}/scripts/sync.py
```

Then search:

```bash
# Full-text search (exact terms, code snippets, error messages)
uv run ${CLAUDE_SKILL_DIR}/scripts/search.py "search query" --mode fts --json

# Semantic search (concepts, themes, "conversations where I discussed X")
uv run ${CLAUDE_SKILL_DIR}/scripts/search.py "search query" --mode semantic --json

# Hybrid (both, merged by reciprocal rank fusion)
uv run ${CLAUDE_SKILL_DIR}/scripts/search.py "search query" --mode hybrid --json
```

Read a full conversation or slice:

```bash
# Read a specific session
uv run ${CLAUDE_SKILL_DIR}/scripts/read.py SESSION_ID

# Read messages around a specific match
uv run ${CLAUDE_SKILL_DIR}/scripts/read.py SESSION_ID --around 42 --context 10

# List recent sessions
uv run ${CLAUDE_SKILL_DIR}/scripts/read.py --list --limit 20
```

## Workflow

1. **Sync first** — always run `sync.py` before searching. It's fast (skips unchanged files) and ensures new conversations are indexed.
2. **Choose search mode** — use FTS for exact terms, code, or error messages. Use semantic for conceptual queries. Use hybrid when unsure.
3. **Iterate** — search, read promising sessions, refine your query if needed. Broaden or narrow with `--since`, `--limit`, and `--context` flags.
4. **Cite sources** — when presenting findings, include session IDs and dates so the user can verify or drill deeper.

## When to use each search mode

- **FTS**: You know the exact words — a function name, error message, tool name, or specific phrase.
- **Semantic**: You want conceptual matches — "conversations about architecture decisions" or "times I debugged deployment issues."
- **Hybrid**: You're not sure what terms were used, or want both exact and conceptual matches.

For detailed search syntax and tips, see [SEARCH.md](SEARCH.md).

## Semantic search server (next-plaid)

Semantic search requires a [next-plaid](https://github.com/lightonai/next-plaid) ColBERT server running locally via Docker.

### Start the server

```bash
docker run -d --name next-plaid \
  -p 8080:8080 \
  -v ~/.local/share/next-plaid:/data/indices \
  ghcr.io/lightonai/next-plaid:cpu-1.0.6 \
  --host 0.0.0.0 --port 8080 --index-dir /data/indices \
  --model lightonai/GTE-ModernColBERT-v1 --int8
```

First run downloads the model (~500 MB). Server is ready when `curl http://localhost:8080/health` returns `{"status": "healthy"}`.

### Stop / restart

```bash
docker stop next-plaid      # stop
docker start next-plaid     # restart (keeps data)
docker rm -f next-plaid     # remove entirely
```

### Model choice

The server uses [GTE-ModernColBERT-v1](https://huggingface.co/lightonai/GTE-ModernColBERT-v1) (~130M params, INT8 quantized). This is near-SOTA for ColBERT retrieval with good long-context support. Other options:

- `lightonai/answerai-colbert-small-v1-onnx` — smaller/faster, less accurate, no long-context
- `lightonai/ColBERT-Zero` — latest SOTA but no INT8 ONNX weights yet (use without `--int8`)

If you change models, delete and rebuild the semantic index (`sync.py --force`).

### Docker must be running

If semantic indexing fails with "Connection refused", start Docker Desktop (`open -a Docker`) then start the container.

## Archive

To back up raw traces and the database to S3 for long-term storage:

```bash
uv run ${CLAUDE_SKILL_DIR}/scripts/archive.py
```

Default bucket: `agent-history-repo`. See `archive.py --help` for options. This syncs raw JSONL files (the lossless source of truth) and the database to S3.
