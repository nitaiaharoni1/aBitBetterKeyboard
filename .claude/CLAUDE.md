<!-- The project brief lives in AGENTS.md at the repo root so Cursor, Codex and Copilot read the same file. Add project instructions there, not here. This file is only for things that are true of Claude Code and nothing else. -->

@../AGENTS.md

## Claude Code

Area-specific findings live in `.claude/rules/`, each scoped with `paths:` frontmatter so it loads only when you open a file in that area. **Add a new finding to the rule that owns the area, not to this file and not to `AGENTS.md`** — `AGENTS.md` is only for things that change how you would approach *any* change in this repo, and it loads into every session.

Longer background that is read on demand, never loaded automatically, is in `.claude/docs/`. `AGENTS.md` has the table of which doc matches which change.
