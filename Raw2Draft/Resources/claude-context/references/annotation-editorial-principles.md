# Annotation Editorial Principles

These principles guide WHAT to annotate and WHY. Getting the animation technically right is worthless if it annotates the wrong thing. Every annotation must add clarity to the speaker's message.

## The Core Rule

**Annotations must add meaning, not decoration.** If an annotation doesn't help the viewer understand what the speaker is saying, it shouldn't exist. Sometimes no annotation is the best annotation.

## Types of Annotations (ranked by value)

### 1. Text that reinforces the speaker's words (highest value)
When the speaker says key terms or a sequence of concepts, write those words on screen. This is the most powerful annotation because it creates NEW visual content that directly matches the audio.

Example: Speaker says "more legible, more understandable, more shareable" — animate each word appearing on screen as they say it. Don't circle random things in the background.

### 2. Emphasis on the KEY word (high value)
When a specific word carries the weight of a sentence, circle or underline THAT word. Not the whole sentence — the word that matters.

Example: "provenance that reviewers can **fully understand**" — circle or highlight "Fully Understand", not the whole subtitle. The viewer should feel the emphasis land on the same beat as the speaker.

### 3. Emotional/conceptual additions (high value)
Draw something that doesn't exist in the frame but adds emotional or conceptual meaning. Hearts, checkmarks, X marks, thought bubbles, connection lines between concepts.

Example: Speaker says "plays nice with others" while showing a robot and human shaking hands — draw a heart between them. This adds warmth and meaning that the illustration alone doesn't convey.

### 4. Relationship arrows (medium value)
Arrows showing flow, causation, or connection between elements — but only when the speaker is describing a relationship.

Example: "AI generated code that your teammates can read" — arrow from AI to teammates, showing the flow of code.

### 5. Circling/boxing existing elements (lowest value)
This is the weakest form of annotation. Only do it when:
- The element is small and the viewer might miss it
- The speaker is explicitly naming something visible on screen
- The element is one of several and you need to direct attention to a specific one

**Never circle something just because the speaker mentions a topic and something related happens to be on screen.** That's decoration, not communication.

## When NOT to annotate

- **Mood-setting slides/illustrations**: If the visual is just setting a tone (like a cartoon), don't circle random parts of it. The illustration IS the annotation — adding circles on top of it is redundant.
- **When the speaker's words ARE the content**: If the speaker is explaining a concept and the visual is just a static backdrop, the best annotation is putting their key words on screen as text, not circling background elements.
- **When it would distract from the speaker**: If the viewer should be watching the speaker's face/expression, adding annotations pulls attention away.

## The Transcript Test

Before placing any annotation, read the transcript at that timestamp and ask:
1. What is the speaker's **key point** right now?
2. Does this annotation **reinforce** that exact point?
3. Would a viewer who ONLY saw the annotation (no audio) understand the message?

If the answer to #3 is no, the annotation isn't adding enough meaning.

## Mobile-First Design (70%+ of YouTube views are on phones)

All annotations MUST be designed for a 6-inch phone screen first.

### Minimum sizes for mobile visibility
- **Underlines**: 7px+ stroke width. Thinner than this disappears on mobile.
- **Circles/ovals**: 9px+ stroke width. Thin circles look like compression artifacts on phones.
- **Hearts/symbols**: 120px+ size minimum. Smaller than this becomes an unrecognizable blob.
- **Text overlays**: 80px+ font size at 1080p. Anything smaller requires squinting on mobile.
- **Text must have shadow or background**: White text needs `textShadow` or a dark background bar. Never put unshadowed text on a busy illustration.

### Safe positioning
- Keep annotations 50px+ from frame edges — mobile players crop slightly.
- Place text in black letterbox bars when available — guaranteed contrast.
- Don't put annotations near the bottom-right corner where YouTube's progress bar lives.

## Practical Workflow

1. Transcribe first (AssemblyAI word-level timestamps)
2. Read the transcript and identify 3-6 moments where annotation would ADD CLARITY
3. For each moment, decide the annotation TYPE based on the hierarchy above
4. Prefer creating new visual content (text, symbols) over circling existing elements
5. If the on-screen content doesn't support the narration, use text overlays or conceptual drawings instead of forcing circles onto irrelevant visuals
6. Use Gemini to verify placement, but YOU make the editorial decisions about what to annotate
7. Always do a mobile readability pass with Gemini — ask specifically about phone-screen visibility

## Common Mistakes

- Circling things just because they're mentioned (decoration, not communication)
- Annotating every sentence (visual clutter, exhausting to watch)
- Putting circles on illustrations that are already doing their job
- Ignoring the transcript and annotating based on what's visually interesting
- Using the same annotation type (circles) for everything instead of choosing the right tool
- Making annotations too thin/small for mobile viewing
- Putting text overlays on busy backgrounds without contrast treatment
