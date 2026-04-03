# Search Reference

## FTS5 Query Syntax

Full-text search uses SQLite FTS5. Useful query patterns:

```
"exact phrase"           # Phrase match
word1 AND word2          # Both terms required
word1 OR word2           # Either term
word1 NOT word2          # Exclude term
word*                    # Prefix match
NEAR(word1 word2, 10)   # Terms within 10 tokens of each other
```

## Semantic Search

Semantic search uses ColBERT multi-vector embeddings via next-plaid. It finds conceptually similar content even when exact terms differ. Best for:

- Finding discussions about a topic when you don't know the exact words used
- Discovering related conversations across different projects
- Conceptual queries like "times I had to rethink an architecture"

## Search Flags

| Flag | Description |
|------|-------------|
| `--mode` | `fts`, `semantic`, or `hybrid` (default: `hybrid`) |
| `--since` | Only results after this date (YYYY-MM-DD) |
| `--limit` | Max results (default: 10) |
| `--context` | Messages before/after each match (default: 2) |
| `--project` | Filter by project name substring |
| `--json` | Output raw JSON for programmatic use |

## Search Strategy Tips

1. **Start broad, then narrow.** A semantic search with a general query gives you the landscape. Then use FTS with specific terms from those results.
2. **Use `--since` to scope by time.** "What did I work on last week?" → `--since 2026-03-17`.
3. **Use `--project` to scope by codebase.** Filters by the project directory name.
4. **Increase `--context`** when you need more surrounding conversation to understand a match.
5. **Multiple searches are cheap.** Don't try to write the perfect query — run several and combine what you learn.

## Result Format (JSON)

Each result is a conversation excerpt:

```json
{
  "match_ordinal": 42,
  "score": 0.85,
  "messages": [
    {
      "session_id": "abc123",
      "ordinal": 40,
      "role": "user",
      "content": "...",
      "tool_name": null,
      "timestamp": "2026-03-10T14:30:00Z",
      "project": "my-project",
      "first_prompt": "...",
      "date_start": "2026-03-10T14:00:00Z"
    }
  ]
}
```

## Database Schema

The database at `~/.claude/cc.db` contains:

- **sessions**: One row per conversation. Fields: `session_id`, `project`, `first_prompt`, `summary`, `date_start`, `date_end`, `message_count`, `source_file`, `source_mtime`.
- **messages**: One row per message. Fields: `session_id`, `ordinal`, `role`, `content`, `tool_name`, `timestamp`. Full content is stored — no truncation.
- **messages_fts**: FTS5 virtual table over message content, auto-maintained by triggers.
- **semantic_index_state**: Tracks which messages have been semantically indexed for incremental updates.
