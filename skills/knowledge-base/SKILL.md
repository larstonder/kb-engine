---
name: knowledge-base
description: Manages the project knowledge base. Use proactively when capturing durable project knowledge (synonyms, repo facts, coding conventions, ADR-style decisions, gotchas, end-to-end recipes) AND when about to recommend something from the KB to verify it against current code first. Also triggered by phrases like "knowledge base", "remember this", "save to KB", "add to knowledge base", "capture this".
---

# Knowledge Base Skill

You orchestrate reads and writes against the KB. The skill resolves the KB location at runtime by reading `.kbconfig` (`KB_DIR`) from the project root, then reads `$KB_DIR/kb.json` for the category schema and available categories. The rules below are the source of truth; `$KB_DIR/CONVENTIONS.md` mirrors them for human readers.

## Your mandate

This KB is yours to evolve, not just fill in. Within the guardrails in this skill, you are encouraged to: create/split/merge/prune entries, reshape the structure (categories, `INDEX.md`, the conventions themselves) when it stops fitting, add to `BACKLOG.md` when you spot a gap and act on backlog items once ripe, and **propose and create new skills** when a recurring need emerges. Guardrails still hold: dedup before creating, validate, start at `confidence: observed`, announce-don't-ask.

## Autonomy contract (read before you reach for a question)

**Scope: the KB directory only.** Everything in this contract - the pre-authorization, the "auto-push is by design" reasoning - applies to the KB directory and nothing else. For every other repo or directory the normal rules stand in full: **do not commit or push without an explicit request, and confirm outward-facing actions.** If the file you are touching is not under `$KB_DIR`, this contract does not apply and none of the rebuttals below license autonomous commits, pushes, or edits there.

Within that scope, writing to this KB is **pre-authorized**. You do not ask permission to capture, update, or prune knowledge - you **announce and proceed**. A Claude-maintained KB only works if maintenance does not interrupt the user. Announcing the capture *is* the consent step: the user can interrupt, and silence is consent.

Two instincts will otherwise push you to ask. Both are wrong here:

- **"It writes a file and auto-pushes, so it's outward-facing - I should confirm."** No. This KB auto-commits and auto-pushes by design (the engine's Stop hook); that is the delivery mechanism the user opted into, not an outward-facing action awaiting sign-off.
- **"The global rule says never commit without explicit request."** That rule is explicitly overridden for this KB directory by the engine's design and the user's `.kbconfig` opt-in. It does not apply to KB writes.

**Never ask "should I add this?" / "want me to capture that?" / "should I update the entry?"** for anything in announce-and-write territory. Asking instead of announcing is a skill violation, not politeness.

### The only times you ask first

A closed list. If your situation is not on it, announce and write.

1. **Changing a *fact* in a `verified` entry** (body text, `repos`, `status`, `title`, `severity`, `superseded_by`): show the diff, ask. Annotations on verified entries (`aliases`, `tags`, `sources`, `related`) stay autonomous.
2. **Promoting `observed` -> `verified`**: propose it; the user completes the promotion.
3. **Deleting or merging away a *human-authored* entry** where content would be lost. Pruning your own `observed` entries is autonomous.
4. **A contradiction update** where current code disproves a `verified` entry's fact (same as case 1: show what changed, ask).

### Red flags - you are about to wrongly ask

| Thought | Reality |
|---|---|
| "This modifies files / pushes to a remote, I should check." | Auto-push is by design. Announce and write. |
| "The user likes to review changes." | Not for this KB. Announce and write. |
| "I'll just confirm the category/title first." | That's asking. Decide it yourself, announce, write. |
| "It's polite to ask before adding." | The KB is yours to maintain. Announcing is the courtesy. |
| "This feels like a commit, and I don't commit without asking." | KB writes are the documented exception. |

If a new entry or an `observed`-entry edit is in front of you, the answer is always announce-and-write. None of these excuses moves it onto the ask-first list.

## Write flow

When you observe durable knowledge worth capturing, follow this sequence.

### 1. Check write criteria

All three must hold:

- **Durable.** Still true next month. Not session-specific state.
- **Not trivially re-derivable.** A 30-second grep cannot recover it.
- **Likely to be re-encountered.** Another task will hit this concept.

If any criterion fails, do not write.

### 2. Search before creating

Grep `$KB_DIR` for:

- The candidate title and obvious keywords.
- Existing `aliases:` fields (search `**/*.md` for `aliases:.*<word>`).
- File names matching the slug.

If a match exists: propose updating that entry.
If no match: create a new entry.

### 3. Edits to existing entries

The branch is primarily on the entry's `confidence`:

- **`observed` entry**: any change is autonomous (body text, any frontmatter field, aliases, sources, tags). The entry is provisional by definition.
- **`verified` entry**: split by what you're changing:
  - **Annotations** (`aliases`, `tags`, `sources`, `related`): autonomous. These are additive metadata.
  - **Facts** (body text, `repos`, `status`, `replaced_by`, `severity`, `superseded_by`, `title`): ASK FIRST. Show the diff. A human signed off on the current value.

### 4. Announce-don't-ask (for new entries)

Per the Autonomy contract above: do not ask, announce. Emit one short line BEFORE writing, then proceed in the same turn:

```
Capturing observation: <category>/<slug>.md. Marked observed.
```

The user can interrupt; silence is consent. Do not pause for approval between this line and the write.

### 5. Write using a template

To create a new entry, run the engine's template generator for the category:

```bash
template.sh --root <KB_DIR> <category>
```

(Or use the vendored `.kb/bin/template.sh` if present in the project.) Then fill in the generated file. The categories are defined in `$KB_DIR/kb.json`.

Fill in:

- `created` and `updated`: today, format `DD.MM.YYYY`.
- `confidence`: `observed`.
- `verified_at`: leave blank (populated only on promotion).
- `repos`: list of submodule names this applies to. Empty if cross-cutting.
- `aliases`: every synonym / translation / abbreviation a future search might use. Be generous: this is the lookup engine.
- `tags`: hierarchical (`#area/X`, `#repo/Y`, `#lang/Z`, `#status/W`). **Always quote each tag**: `tags: ["#area/X", "#status/active"]`. A bare `#` in a YAML flow array starts a comment that breaks the array and shows up as Obsidian's red "invalid properties" banner; `validate.sh` rejects it at commit time.
- `sources`: file:line, PR#, commit SHA, or spec references. Empty array allowed but discouraged.
- **Connect it to the graph.** An entry with no `[[wikilink]]` is a graph orphan (`repos:` and `#repo/...` tags are metadata only - Obsidian draws edges from wikilinks, not frontmatter). If `repos:` is non-empty, the body MUST contain a `[[<repo>]]` wikilink to at least one listed repo. Cross-cutting entries (`repos: []`) link the related concept entries they belong with instead. `check-graph.sh` enforces this at commit time via the content repo's generated git pre-commit hook, so an unconnected entry will block the auto-commit.

### 6. Log the consult

After writing, append one line to `$KB_DIR/.usage.log`. Consult logging for reads is automatic via the PostToolUse(Read) hook; for writes you invoke the vendored script directly:

```bash
bash "$KB_DIR/.kb/bin/log-consult.sh" <relative-path> write <task-slug>
```

The `<task-slug>` is a short identifier for the current session's task (e.g. the feature branch name or a few keywords from the user prompt). Pass it explicitly; the script falls back to `$KB_TASK` env var or `unknown` if omitted.

## Read flow

This is the safety net for the autonomous-write model.

### When to consult the KB

- User mentions a domain term where ambiguity matters: check the glossary category.
- About to write code in a repo you have not touched this session: read the relevant repo and conventions entries.
- About to make a non-obvious design choice: check the decisions category.
- About to do bulk ops, regenerate a schema, or edit config files: skim the gotchas category.
- Multi-step operation that might already be a recipe: check the recipes category.

### Before recommending anything from a KB entry

1. **Check confidence and freshness.**
   - `verified` with `verified_at` < 90 days old (relative to today): trust on first read. Still grep any named symbol or file.
   - `verified` with `verified_at` >= 90 days: demote to `observed` for this read.
   - `observed`: treat as a hypothesis, not a fact.

2. **Verify against current code.**
   - If the entry names a model, function, file, flag, or endpoint: grep for it.
   - If the entry asserts a convention: spot-check 2-3 recent commits to confirm.

3. **Branch on result.**
   - **Confirmed**: use the entry. The consult itself is already auto-logged (`result=read`); when you actively confirmed an `observed` (or demoted-from-`verified`) entry against current code, also set `pending_promotion: true` in the frontmatter (single-line edit) and append `result=confirmed` to record the stronger signal.
   - **Contradicted**: do not use the entry. Propose an update to the entry (ask first; this is the "edit existing fact" case). Continue the task using current code as truth.
   - **Ambiguous**: treat as `observed`, surface inline ("KB says X, but code looks like Y. Going with code."). Log `result=ambiguous`.

### Promotion from observed to verified

- Read flow sets `pending_promotion: true` when an `observed` entry is confirmed.
- Next time the user explicitly touches the entry (opens it in Obsidian, asks about it, or you propose an edit), propose the promotion:
  - `confidence: verified`
  - `verified_at: <today>`
  - Remove `pending_promotion`.
- User confirms; apply.

## Log format

`$KB_DIR/.usage.log` (tracked and pushed; union-merged). One line per consult:

```
<ISO-8601 timestamp> <relative path> task=<short-slug> result=<read|confirmed|contradicted|ambiguous|write>
```

Append via `scripts/log-consult.sh`. `result=read` is appended **automatically** by the `PostToolUse(Read)` hook whenever you Read an entry under a category folder - deduped per session. You never log a plain consult by hand; the manual log line is reserved for the stronger judgment outcomes (`confirmed`/`contradicted`/`ambiguous`) and for `write`.

## Hard rules

- Filename: `kebab-case.md`.
- Date format: `DD.MM.YYYY`.
- Internal references: `[[wikilinks]]` only. Never markdown-style internal links between KB entries (rejected by the content repo's generated git pre-commit hook).
- Ghost-link discipline: never put an agent-paraphrased gloss next to a `[[link]]` whose target does not exist. Bare link, or real stub with a citation.
- Graph connectivity: no orphans. If `repos:` is non-empty, the entry must `[[link]]` at least one listed repo; `repos: []` entries link their related concept notes. The repo-type category entries are exempt. Enforced by `check-graph.sh`.
- Atomic notes: one concept per file. Past ~150 lines, split.
- Override: this KB auto-commits and auto-pushes on session end via the engine's Stop hook. That is the delivery mechanism the user opted into.
