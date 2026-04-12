# Raw2Draft Editor Context

You are running inside Raw2Draft, a markdown editor for content creation. The user is editing a file in the app and may ask you to help with writing, editing, or publishing.

## Active File

The file the user currently has open in the editor is written to `~/.raw2draft/active-file`. Read this file to know what the user is looking at. When the user says "this file" or "the current file", they mean the file listed there.

## Skills and References

Skills and reference documents are managed separately from the app:

- **Skills**: Agent skills are in the `skills/` directory (cloned from [agentkb-skills](https://github.com/Isaac-Flath/agentkb-skills) on first launch). These provide `/slash-command` workflows for content creation, transcription, social media, video editing, and more.
- **References**: Writing style guides and reference docs are in the `wiki/` directory (cloned from [agent-starter-wiki](https://github.com/Isaac-Flath/agent-starter-wiki) on first launch).

For a richer setup, install [agentkb](https://github.com/Isaac-Flath/agentkb) and configure your own skills and wiki repos. agentkb provides semantic search across your knowledge base, chat history, and code.

## Writing

Before writing or editing any text content, invoke `/writing-style` first. If agentkb is available, search for writing guidance:

```bash
agentkb search -s wiki "Zinsser writing style principles"
```

Otherwise, read `wiki/writing-with-zinsser.md` in this context directory.
