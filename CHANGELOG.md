# Changelog

All notable changes to research-engine.
Versions follow [semver](https://semver.org/) — MAJOR.MINOR.PATCH.

## 0.2.0 — 2026-04-18

### Changed
- **Notion layout is now a single database with one consolidated row per session** (breaking vs 0.1.0's page tree). Each row's body holds the main report, with toggle blocks for transcript, followups, and related materials.
- `/research-followup` updates the row in place (clear-and-reappend) rather than creating subpages.

### Added
- `scripts/push_to_notion.sh --archive-page <page_id>` subcommand for one-off cleanup.
- Database properties: Title, Slug, Input URL, Input Type, Created, Purpose, Audience, Sources — enabling filter/sort in Notion.
- `NOTION_DATABASE_ID` cache env variable to skip the database search on every run.

### Fixed
- `md_to_blocks` parser used a heredoc that hijacked stdin — the markdown never reached Python. Script now stores the Python source in a bash variable and runs via `python3 -c`, leaving stdin available.

### Removed
- `install.sh` — superseded by marketplace-based installation documented in the README.

## 0.1.0 — 2026-04-17

Initial release. Plugin scaffolding, seven source adapters (YouTube, arXiv, GitHub, blog, context7, HuggingFace, community), `/research` + `/research-followup` slash commands, bash utilities with bats coverage, and Notion mirroring (page-tree layout).
