# Knowledge Base

Project knowledge base managed by the kb-engine. Categories and checks are configured in `kb.json`.

## What lives here

Atomic markdown notes with YAML frontmatter, organized by the categories defined in `kb.json`.

Start with `INDEX.md`. Read individual entries on demand.

## How to use this as a human

Open the folder as an Obsidian vault. Tags and wiki-links resolve. Backlinks pane works. Graph view shows the relationship structure.

## How Claude uses this

A skill orchestrates reads and writes. Claude proposes new entries autonomously when it observes durable knowledge during a session; the safety net is the read-verify step (Claude greps current code before recommending anything from a KB entry).

A `Stop` hook commits and pushes this KB on session end. This is the engine's delivery mechanism.

## The hard rules

See `CONVENTIONS.md`. Two non-negotiable ones:

1. Before recommending anything from a KB entry, grep current code to confirm it still exists.
2. Before creating a new entry, search the KB; if a related entry exists, update it instead.
