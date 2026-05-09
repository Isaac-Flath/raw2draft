---
name: publish
description: Prepare or run the repo's publishing workflow for blog content and site deployment.
---

Use this skill when publishing content or deploying the site.

Workflow:

1. Inspect the repo's `justfile`, README, and scripts for canonical publish commands.
2. Check git status before modifying or deploying.
3. Prefer existing `just` recipes such as post deploy or app deploy commands.
4. Explain what will be published before running commands that affect remote services.

Do not publish drafts unless the user explicitly asks.
