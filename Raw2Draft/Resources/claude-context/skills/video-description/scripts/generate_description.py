"""Generate YouTube description, tags, and metadata from transcript.

Input: <stem>_analysis.json, optionally <stem>_mentions.json and <stem>_chapters.txt
Output: <stem>_description.md
"""

import json
import math
import os
import re
import sys
from collections import Counter
from pathlib import Path


# Common English stop words to exclude from tag extraction
STOP_WORDS = {
    "a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for",
    "of", "with", "by", "from", "is", "was", "are", "were", "be", "been",
    "being", "have", "has", "had", "do", "does", "did", "will", "would",
    "could", "should", "may", "might", "can", "shall", "it", "its",
    "i", "we", "you", "he", "she", "they", "me", "us", "him", "her",
    "them", "my", "our", "your", "his", "their", "this", "that", "these",
    "those", "what", "which", "who", "when", "where", "how", "why",
    "not", "no", "so", "if", "then", "than", "just", "also", "very",
    "really", "actually", "basically", "like", "um", "uh", "gonna",
    "going", "get", "got", "thing", "things", "know", "think", "about",
    "there", "here", "some", "all", "any", "each", "every", "much",
    "many", "more", "most", "other", "into", "over", "out", "up", "down",
    "way", "kind", "sort", "lot", "bit", "something", "right", "well",
    "now", "want", "need", "make", "take", "give", "come", "go", "see",
    "look", "say", "said", "tell", "use", "try", "let", "put",
}

# Minimum word frequency to consider as a tag
MIN_TAG_FREQUENCY = 3
MAX_TAGS = 20


def extract_tags(text, max_tags=MAX_TAGS):
    """Extract relevant tags/keywords from transcript text."""
    # Tokenize and clean
    words = re.sub(r"[^\w\s-]", "", text.lower()).split()
    words = [w for w in words if w not in STOP_WORDS and len(w) > 2]

    # Count word frequencies
    freq = Counter(words)

    # Extract bigrams too
    for i in range(len(words) - 1):
        bigram = f"{words[i]} {words[i + 1]}"
        freq[bigram] += 1

    # Filter by minimum frequency and sort
    tags = [
        (word, count) for word, count in freq.items()
        if count >= MIN_TAG_FREQUENCY
    ]
    tags.sort(key=lambda x: x[1], reverse=True)

    return [tag for tag, _ in tags[:max_tags]]


def extract_resource_links(mentions_data):
    """Extract resource links from mentions data."""
    if not mentions_data:
        return []

    links = []
    for mention in mentions_data.get("mentions", []):
        url = mention.get("url")
        if url:
            label = mention.get("metadata", {}).get("og_title") or mention.get("label", url)
            links.append({"label": label, "url": url, "type": mention["type"]})

    # Deduplicate by URL
    seen = set()
    deduped = []
    for link in links:
        if link["url"] not in seen:
            seen.add(link["url"])
            deduped.append(link)

    return deduped


def generate_summary_sentences(text, max_sentences=3):
    """Extract key sentences from the transcript for a summary.

    Uses a simple extractive approach: pick sentences with the highest
    density of important words.
    """
    # Split into sentences
    sentences = re.split(r"[.!?]+", text)
    sentences = [s.strip() for s in sentences if len(s.strip()) > 30]

    if not sentences:
        return text[:500]

    # Score sentences by keyword density
    all_words = re.sub(r"[^\w\s]", "", text.lower()).split()
    word_freq = Counter(w for w in all_words if w not in STOP_WORDS and len(w) > 2)

    scored = []
    for i, sent in enumerate(sentences):
        sent_words = re.sub(r"[^\w\s]", "", sent.lower()).split()
        score = sum(word_freq.get(w, 0) for w in sent_words if w not in STOP_WORDS)
        # Boost earlier sentences slightly (introduction is important)
        position_bonus = 1.0 + max(0, (0.3 - i / len(sentences)))
        scored.append((sent, score * position_bonus, i))

    # Take top sentences, sorted by original position
    scored.sort(key=lambda x: x[1], reverse=True)
    top = sorted(scored[:max_sentences], key=lambda x: x[2])

    return ". ".join(s[0].strip() for s in top) + "."


def generate_title_suggestions(text, tags):
    """Generate a few title variations from the content."""
    # Use the most frequent meaningful terms
    core_terms = tags[:5] if tags else ["Video"]

    suggestions = []

    # Direct topic title
    if core_terms:
        title = " ".join(w.title() for w in core_terms[0].split())
        suggestions.append(title)

    # "How to" / "Guide" style
    if len(core_terms) >= 2:
        suggestions.append(f"{core_terms[0].title()}: A Deep Dive")
        suggestions.append(f"Understanding {core_terms[0].title()}")

    return suggestions


def generate_description(analysis, mentions_data=None, chapters_text=None):
    """Generate full YouTube description.

    Args:
        analysis: Parsed analysis JSON
        mentions_data: Optional parsed mentions JSON
        chapters_text: Optional chapter text (YouTube format)

    Returns:
        Description markdown string
    """
    text = analysis["transcript"]["text"]
    duration = analysis["metadata"]["duration"]
    stem = Path(analysis["source_file"]).stem

    # Extract components
    tags = extract_tags(text)
    links = extract_resource_links(mentions_data)
    summary = generate_summary_sentences(text)
    title_suggestions = generate_title_suggestions(text, tags)

    # Build description
    lines = []

    # Title suggestions (commented as suggestions)
    lines.append("<!-- TITLE SUGGESTIONS (pick one or write your own) -->")
    for i, title in enumerate(title_suggestions):
        lines.append(f"<!-- {i + 1}. {title} -->")
    lines.append("")

    # Summary
    lines.append("## Summary")
    lines.append("")
    lines.append(summary)
    lines.append("")

    # Chapters
    if chapters_text:
        lines.append("## Chapters")
        lines.append("")
        lines.append(chapters_text)
        lines.append("")

    # Resources/links
    if links:
        lines.append("## Resources")
        lines.append("")
        for link in links:
            lines.append(f"- {link['label']}: {link['url']}")
        lines.append("")

    # Tags
    if tags:
        lines.append("## Tags")
        lines.append("")
        lines.append(", ".join(tags))
        lines.append("")

    # Duration info
    minutes = int(duration // 60)
    seconds = int(duration % 60)
    lines.append(f"<!-- Duration: {minutes}:{seconds:02d} | Generated from: {stem} -->")

    return "\n".join(lines)


# ── CLI ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: uv run generate_description.py <analysis_json> "
              "[<mentions_json>] [<chapters_txt>] [--output-dir <dir>]")
        sys.exit(1)

    analysis_path = sys.argv[1]
    mentions_path = None
    chapters_path = None
    output_dir = None

    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == "--output-dir" and i + 1 < len(args):
            output_dir = args[i + 1]
            i += 2
        elif args[i].endswith("_mentions.json"):
            mentions_path = args[i]
            i += 1
        elif args[i].endswith("_chapters.txt"):
            chapters_path = args[i]
            i += 1
        else:
            i += 1

    with open(analysis_path) as f:
        analysis = json.load(f)

    mentions_data = None
    if mentions_path and os.path.exists(mentions_path):
        with open(mentions_path) as f:
            mentions_data = json.load(f)

    chapters_text = None
    if chapters_path and os.path.exists(chapters_path):
        with open(chapters_path) as f:
            chapters_text = f.read().strip()

    stem = Path(analysis["source_file"]).stem

    if output_dir is None:
        output_dir = os.path.dirname(os.path.abspath(analysis_path))
    os.makedirs(output_dir, exist_ok=True)

    print(f"Generating description for: {stem}")
    description = generate_description(analysis, mentions_data, chapters_text)

    output_path = os.path.join(output_dir, f"{stem}_description.md")
    with open(output_path, "w") as f:
        f.write(description)

    print(f"Description saved to {output_path}")
    print("\nPreview:")
    print("─" * 60)
    print(description)
    print("─" * 60)
    print("\nReview and edit this description before using it.")
