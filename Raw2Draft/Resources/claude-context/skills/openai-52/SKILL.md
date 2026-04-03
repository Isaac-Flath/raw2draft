---
name: openai-52
description: General-purpose OpenAI assistant for tasks requiring OpenAI-specific capabilities or GPT models. Use when you need OpenAI model features.
---

# /openai-52

Query OpenAI's GPT models for general-purpose tasks. Specifically configured for GPT-5.2 and other OpenAI models.

## Usage

```
/openai-52 [prompt]
```

## Prerequisites

- `uv` CLI: `brew install uv` or `pip install uv`
- `OPENAI_API_KEY` environment variable (or set in `~/.content/config.yaml`)

## Use Cases

- Tasks requiring OpenAI GPT-5.2 reasoning capabilities
- OpenAI-specific features (vision, structured outputs, tool use)
- Alternative perspective or second opinion on problems
- Cross-model testing and comparison
- Specialized OpenAI model features

## Working Directory

Content Conductor launches Claude from the project directory (`projects/<id>`). Paths below are relative to that directory.

## Run

```bash
# Basic query (uses GPT-4o by default)
uv run .claude/skills/openai-52/scripts/query.py "Your prompt here"

# With GPT-5.2 (when available)
uv run .claude/skills/openai-52/scripts/query.py "Your prompt here" --model gpt-5.2

# With image input (vision models)
uv run .claude/skills/openai-52/scripts/query.py "Analyze this image" --image path/to/image.png

# With system message for context
uv run .claude/skills/openai-52/scripts/query.py "Your prompt" --system "You are a helpful assistant specializing in..."
```

## Available Models

- `gpt-4o` (default) - Latest multimodal model currently available
- `gpt-5.2` - When available, use this for advanced reasoning
- `gpt-4o-mini` - Faster, cheaper variant
- `o1` - Reasoning model (if available)
- `o1-mini` - Smaller reasoning model

## Output

Prints response to stdout. Use shell redirection to save:
```bash
uv run .claude/skills/openai-52/scripts/query.py "prompt" > output.txt
```

## Note

This skill is named `openai-52` to indicate it's configured for OpenAI's GPT-5.2 model family. The script supports multiple OpenAI models via the `--model` parameter.
