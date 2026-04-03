# Editing Principles

These videos are educational/technical content (screen recordings + voiceover/webcam). The editing style should preserve the natural, thoughtful pacing of someone explaining their workflow.

## Core Philosophy
- **Conservative on substance, aggressive on noise.** Keep every unique idea. Cut every repeated take, filler, false start, and dead air.
- Preserve the speaker's natural rhythm and personality
- Educational content needs breathing room — don't make it "punchy"

## How to Propose Edits

Read the transcript from `_analysis.json` (which has word-level timestamps). For each passage, decide: keep or cut? The transcript words have `start` and `end` timestamps in seconds — use these to build the EDL segments.

### What to cut
1. **Repeated takes** — Speaker says the same thing multiple times. Keep the best version (usually the last complete one). Use your judgment: which version is clearest? Most concise? Sometimes the first attempt is better if the later ones trail off.
2. **Filler words** — "um", "uh", standalone "like", "you know", "so", "and so". Cut by splitting the segment around the filler. But "like" meaning "such as" stays. "So" beginning a new thought stays.
3. **False starts** — Speaker begins a thought, abandons it, starts over. Cut the abandoned start.
4. **Extended silences** — Reduce gaps longer than ~2s down to ~0.8s.
5. **Trailing incomplete thoughts** — "...and then, um" or "...so, like, the" at the end of a segment with no completion.
6. **Pre/post-roll dead air** — Keep ~1s before first word and ~1s after last word.

### What to keep
- All substantive content, even if imperfect delivery
- Natural pauses between thoughts (up to ~2s)
- Deliberate emphasis pauses
- Topic transitions
- When unsure, keep it

## Building the EDL

The EDL is a JSON file with kept segments:

```json
{
  "source_file": "/path/to/video.mp4",
  "total_duration": 658.6,
  "kept_duration": 530.2,
  "retention_pct": 80.5,
  "segments": [
    {"start": 6.12, "end": 7.505, "action": "keep", "label": "Segment 1"},
    {"start": 7.505, "end": 16.25, "action": "keep", "label": "Segment 2"}
  ]
}
```

Each segment's `start` and `end` are source-file timestamps in seconds. Derive these from the word-level timestamps in the transcript:
- Segment `start` = first kept word's `start` minus ~0.12s padding (but not before previous segment ends + 0.3s gap)
- Segment `end` = last kept word's `end` plus ~0.25s padding (to preserve natural audio tail)
- Never overlap segments
- Minimum segment length: 0.25s

## Timing Rules
- Never cut mid-word
- Find natural pause points (end of phrase, breath)
- When reducing silence, keep at least 0.3s gap between segments
- Ground every segment boundary in word-level timestamps

## Expected Retention
- **Multi-take recordings** (frequent restarts): **30–45%** retention
- **Single-take recordings** (clean delivery): **70–90%** retention
- **Mixed recordings**: **50–65%** retention

## Review Document

Also produce `_review.md` listing:
- Stats (original duration, kept duration, retention %)
- Each kept segment with its text (for human review)
- Cut summary grouped by reason (repeated takes, fillers, incomplete sentences)
