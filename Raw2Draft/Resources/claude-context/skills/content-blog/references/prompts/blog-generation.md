# Blog Generation Prompt

Write a comprehensive curated article based on the provided source materials.

## Requirements

- Use standard Markdown format
- Start with # Title
- Include screenshots using ONLY the exact paths provided
- Preserve technical accuracy
- Include code blocks where relevant
- Add a conclusion with key takeaways

## Structure

If an outline is provided, follow it exactly. For each section:
- Use the section title as an H2 heading
- Incorporate the guidance notes from the outline
- Draw from the transcript and source materials

If no outline is provided:
- Create a logical structure based on the content
- Use clear H2 headers for main sections
- H3 for subsections if needed

## Format

- H1 for title only
- H2 for main sections
- H3 for subsections if needed
- Code blocks with language specification
- Bullet/numbered lists where appropriate
- Bold for emphasis (sparingly)

## Do NOT Include

- Generic filler content
- Excessive adjectives or hype
- Obvious statements
- Meta-commentary about the writing
- Throat-clearing introductions
- AI tells (see writing-style.md)

## Screenshot References

When visual aids would help comprehension, reference screenshots:
```markdown
![Description](screenshots/001-00m30s.png)
```

Only use screenshots that exist in the provided list. Do not hallucinate paths.

## Code Examples

Format code blocks properly:
```python
# Clear comment explaining what this does
def example():
    return "result"
```

Include language specification for syntax highlighting.
