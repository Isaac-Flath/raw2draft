# Mixedbread Semantic Search for Reference Docs

Use Mixedbread vector stores to search over reference documentation (like the Fusion 8 Scripting Guide) with natural language queries. This is how to look things up when debugging or learning an API.

## Setup

The `mxbai` CLI is pre-installed. API key is configured via:
```bash
mxbai config keys add <your_key>
```

Or set `MXBAI_API_KEY` environment variable.

## Workflow: Indexing a new reference doc

### 1. Create a store
```bash
mxbai store create "store-name"
```

### 2. Upload documents
```bash
# Upload a PDF with high quality chunking
mxbai store upload "store-name" "/path/to/document.pdf" --strategy high_quality

# Upload multiple files with glob patterns
mxbai store upload "store-name" "docs/**/*.md" "*.pdf"
```

The `high_quality` strategy produces better chunks but takes longer to process (~3-5 minutes for a 200-page PDF).

### 3. Wait for processing
```bash
# Check status
mxbai store files list "store-name" --format json

# Status will be "in_progress" then "completed"
```

### 4. Search
```bash
# Semantic search
mxbai store search "store-name" "how to animate an ellipse mask"

# Get JSON output for programmatic use
mxbai store search "store-name" "Merge blend modes" --format json

# Ask a question (includes AI-generated answer)
mxbai store qa "store-name" "What are the valid ApplyMode values for a Merge tool?"
```

## Existing stores

| Store name | Contents | Use case |
|-----------|----------|----------|
| `fusion-scripting-docs` | Fusion 8 Scripting Guide PDF | DaVinci Resolve Fusion API reference |
| `mgrep` | Various project files | General codebase search |

## Management commands
```bash
mxbai store list                              # List all stores
mxbai store get "store-name"                  # Get store details
mxbai store files list "store-name"           # List files in store
mxbai store files delete "store-name" <id>    # Delete a file
mxbai store delete "store-name"               # Delete entire store
```

## When to use this

- **Debugging Fusion scripting**: Search for tool properties, connection patterns, animation APIs
- **Learning a new API**: Index the docs, then ask natural language questions
- **Any reference PDF/doc**: Works with PDF, Markdown, text files
- **Grounding AI answers**: Search for specific API details rather than guessing

## Tips

- Use `--strategy high_quality` for technical docs — it produces better chunks for code-heavy content
- The `qa` command gives an AI-synthesized answer; `search` returns raw chunks. Use `search` when you want exact doc text, `qa` when you want a direct answer.
- Processing large PDFs takes 3-5 minutes. Check with `mxbai store files list` until status shows "completed".
