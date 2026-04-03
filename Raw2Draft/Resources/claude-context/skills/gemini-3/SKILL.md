---
name: gemini-3
description: General-purpose Gemini assistant for tasks requiring multimodal analysis, long context, or specialized Gemini capabilities. Use when you need to leverage Gemini-specific features.
---

# /gemini-3

Query Google's Gemini 3 models for general-purpose tasks. Specifically configured for Gemini 3 and related Gemini models.

## Usage

```
/gemini-3 [prompt]
```

## Prerequisites

- `uv` CLI: `brew install uv` or `pip install uv`
- `GEMINI_API_KEY` environment variable (or set in `~/.content/config.yaml`)

## Use Cases

- Long context analysis (2M+ token context window)
- Multimodal tasks (text + images + PDFs + videos)
- Tasks requiring Gemini 3 reasoning capabilities
- Alternative perspective or second opinion on problems
- Cross-model testing and comparison
- Specialized Gemini features (native tool use, grounding)

## Working Directory

Content Conductor launches Claude from the project directory (`projects/<id>`). Paths below are relative to that directory.

## Run

```bash
# Basic query (uses gemini-2.5-pro by default)
uv run .claude/skills/gemini-3/scripts/query.py "Your prompt here"

# With Gemini 3 (when available)
uv run .claude/skills/gemini-3/scripts/query.py "Your prompt here" --model gemini-3-pro

# With image input
uv run .claude/skills/gemini-3/scripts/query.py "Analyze this image" --image path/to/image.png

# With PDF or document input
uv run .claude/skills/gemini-3/scripts/query.py "Summarize this document" --file path/to/document.pdf

# Multiple files
uv run .claude/skills/gemini-3/scripts/query.py "Compare these" --file doc1.pdf --file doc2.pdf --image chart.png
```

## Available Models

- `gemini-2.5-pro` (default) - Latest available multimodal model
- `gemini-3-pro` - When available, Gemini 3 with advanced reasoning
- `gemini-3-pro-image-preview` - For image generation tasks
- `gemini-2.0-flash-exp` - Experimental fast model

## Output

Prints response to stdout. Use shell redirection to save:
```bash
uv run .claude/skills/gemini-3/scripts/query.py "prompt" > output.txt
```

## Note

This skill is named `gemini-3` to indicate it's configured for Google's Gemini 3 model family. The script supports multiple Gemini models via the `--model` parameter, with Gemini 3 being the target model when it becomes available.
