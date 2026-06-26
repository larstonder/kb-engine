# Conventions

Rules for adding to and reading from this knowledge base. Enforced partially by the pre-commit hook (commit-time) and partially by the `knowledge-base` skill (mid-session).

## Claude's mandate to evolve the KB

This KB is maintained by Claude, and Claude is explicitly authorized - and encouraged - to evolve it, not merely fill it in. Within the guardrails below, you may:

- Create, split, merge, refactor, and prune entries as knowledge changes.
- Reshape the structure itself - categories, `INDEX.md`, even these conventions - when the current shape stops fitting.
- Add to `BACKLOG.md` whenever you spot a deferred idea or a gap, and act on backlog items once they're ripe.
- **Propose and create new skills** when a recurring need emerges (a repeated task, a missing automation, a validation worth enforcing), and wire them into hooks when that's what the need calls for.

Guardrails that still hold: search/dedup before creating, validate frontmatter and links, new entries start at `confidence: observed`, and follow the announce-don't-ask write protocol.

**Announce-don't-ask is non-negotiable.** Inside this KB directory, writes are pre-authorized: Claude announces a capture and proceeds; it does not ask "should I add this?". The auto-commit/auto-push is *by design* (the engine's delivery mechanism), so it does not trigger "confirm before outward-facing actions" instincts. Claude asks first only for a closed list of cases: changing a fact in a `verified` entry, promoting `observed` -> `verified`, deleting a human-authored entry, or a contradiction update.

## Frontmatter (required on every entry)

```yaml
---
type: glossary | repo | convention | decision | recipe | gotcha
title: Human Readable Title
aliases: []           # synonyms; Obsidian indexes them; Claude greps them
tags: []              # cross-cutting; hierarchical, ALWAYS quoted: ["#area/auth", "#lang/ruby"]
related: []           # optional; only when not already linked from body
confidence: observed | verified
verified_at:          # DD.MM.YYYY; absent until promoted to confidence: verified
sources: []           # file:line, PR#, commit SHA, conversation refs
created: DD.MM.YYYY
updated: DD.MM.YYYY
---
```

**Always quote `#` tags.** A bare `#` inside a YAML flow array is read as a comment that swallows the rest of the line. Write `tags: ["#area/auth", "#status/active"]`. The pre-commit `validate.sh` parses every entry's YAML and rejects this.

Type-specific extras defined in `kb.json` `categories[].extraFields` (e.g. `status` on decisions, `severity` on gotchas, `status` on repos). Refer to the categories in `kb.json` for the full list.

Transient field: `pending_promotion: true` is added by the read flow when an `observed` entry is confirmed against current code. Removed on promotion to `verified`.

## Consult logging

`.usage.log` records one line per consult: `<timestamp> <relative path> task=<slug> result=<read|confirmed|contradicted|ambiguous|write>`. Reads are captured automatically by a `PostToolUse(Read)` hook. Manual `log-consult.sh` calls are reserved for stronger outcomes (`confirmed`/`contradicted`/`ambiguous`) and for `write`. This is the frequency signal used by stale-sweep and future curation tools.

The log is **tracked and pushed**. It accumulates consults across every machine and session so frequency signals reflect real total usage, not just the local checkout. `.gitattributes` marks it `merge=union` so concurrent appends from parallel sessions concatenate instead of conflicting.

## Write criteria (the skill enforces these)

A claim is worth writing to the KB only if all three hold:

1. **Durable.** Still true next month. Not session-specific state.
2. **Not trivially re-derivable.** A 30-second grep cannot recover it.
3. **Likely to be re-encountered.** Another task will hit this concept.

If any criterion fails, do not write.

## Confidence and verification

- New entries default to `confidence: observed` and leave `verified_at` blank.
- The read flow promotes by setting `pending_promotion: true` when an `observed` entry is confirmed against current code. The next human touch completes the promotion: `confidence: verified`, `verified_at: today`, remove `pending_promotion`.
- A `verified` entry with `verified_at` >= 90 days old is demoted to `observed` for the duration of the read; the read flow re-verifies and refreshes `verified_at` if confirmed.

## Janitor (SessionStart sweep)

A stale-sweep script runs once per session at SessionStart. It is the automated counterpart to the read-flow demotion above, plus a deletion scout. Never deletes anything itself.

- **Demote.** Any `verified` entry whose `verified_at` is older than `staleMonths` (from `kb.json`, default 3) is written back to `confidence: observed` with `verified_at` cleared, so the next read re-verifies it.
- **Recommend for deletion.** Entries that look dead are surfaced as a worklist. A note is a candidate if: its body is empty; it is `observed`, never verified, and `updated` older than `2 * staleMonths`; or it has zero consults in `.usage.log` and is stale. Deletion stays human-gated and one file at a time.

## Linking rules

- `[[wiki links]]` for internal references. Markdown-style internal links are rejected by the wikilinks check.
- Ghost-link discipline: a `[[wiki link]]` to a non-existent target is fine as a placeholder, but never adjacent to an agent-paraphrased gloss claiming a fact about that target. Enforced when `ghostLinks` is enabled in `kb.json`.
- Graph connectivity: every entry must be reachable in the graph, not an orphan. Enforced when `graphConnectivity` is enabled in `kb.json`.
- Atomic notes: one concept per file. Entries past ~150 lines should be split.

## Tags

Hierarchical, cross-cutting. Examples:

- Area: `#area/auth`, `#area/payments`
- Language: `#lang/ruby`, `#lang/typescript`
- Status: `#status/active`, `#status/deprecated`

Tags answer "what kind of thing is this?". Links answer "what is this related to?".

## Filenames

`kebab-case.md`. The `title:` field carries the human display name.

## Date format

`DD.MM.YYYY` in frontmatter and prose.

## Auto-commit (by design)

The kb-engine commits and pushes this KB directory on every Claude turn-end via a `Stop` hook. This is the engine's delivery mechanism, not a user-specific override. Every write by Claude lands in the remote without requiring a manual commit.

The auto-push never:

- Force-pushes.
- Skips the pre-commit validation step.
- Creates PRs, merges, or edits PR metadata.

Recovery from a persistent pre-commit rejection: edit the offending entry to satisfy validation, or `git checkout <file>` to discard the bad write.

## Searching before creating

Search the KB for keywords and `aliases:` fields before creating any new entry. Match found means propose an update; no match means create new.
