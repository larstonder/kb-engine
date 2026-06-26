# kb-engine

A Claude-maintained, self-syncing knowledge base engine for code teams. It targets code knowledge: conventions, decisions, gotchas, recipes, glossary terms, and repo inventory. It is not a PARA or second-brain note system.

The engine ships two parts that stay separate:

- **Engine** - the scripts, hooks, presets, and skill that live in this repo.
- **Content** - a standalone git repo (or submodule) scaffolded by the engine and owned by your project.

---

## Install

### Option A: Claude Code plugin (primary)

```sh
/plugin marketplace add larstonder/kb-engine
/plugin install knowledge-base
```

This registers the engine as a plugin: it wires the five lifecycle hooks automatically (via `hooks/hooks.json`, resolved through `${CLAUDE_PLUGIN_ROOT}`) and adds the `/kb` slash command used to scaffold content (below).

To develop against a local checkout instead, point the marketplace at the directory: `/plugin marketplace add ~/path/to/kb-engine`. (Prefer the GitHub source for normal use — a local directory source copies untracked files into the plugin cache.)

### Option B: install.sh (non-plugin fallback)

```sh
./install.sh --project <project-dir>
```

This copies `hooks/`, `lib/`, and `skills/knowledge-base/` under `<project-dir>/.claude/kb-engine/` and merges the hook entries into `<project-dir>/.claude/settings.json`. Re-running is idempotent.

---

## Set up a content repo

With the plugin installed, run the `/kb` slash command from inside the project you want a KB for:

```
/kb init <kb-dir> --preset general|monorepo [--mode standalone|submodule] [--branch <branch>]
/kb sync
```

`/kb` wraps the bundled CLI (the plugin doesn't put `kb` on your `PATH`). If you installed via `install.sh` or a plain clone instead, call the CLI directly from the engine repo, passing `--project`:

```sh
./bin/kb init <kb-dir> --preset general|monorepo \
            [--categories a,b,c] \
            [--mode standalone|submodule] \
            [--branch <branch>] \
            --project <project-dir>
./bin/kb sync --project <project-dir>
```

`init` creates the category folders, copies content-template files (CONVENTIONS.md, INDEX.md, BACKLOG.md, README.md, .gitignore, .gitattributes), vendors the validators into `<kb-dir>/.kb/bin/`, installs the git pre-commit hook, and writes `.kbconfig` in the project root. `sync` re-vendors the validators and re-installs the pre-commit hook after an engine update. The lifecycle hooks no-op in any project without a `.kbconfig`, so the KB only becomes active once `init` has run (and from the next session start).

---

## Configuration

Two config files are involved.

### `.kbconfig` (project root)

Written by `kb init`. Read by every hook and `kb sync` at runtime.

```sh
KB_DIR=".knowledge"   # relative (or absolute) path from project root to the content repo
MODE="standalone"     # standalone | submodule
BRANCH="main"
```

### `kb.json` (content repo root)

Written by `kb init` from the chosen preset. Defines the category schema and enables/disables the opt-in checks.

```json
{
  "version": 1,
  "categories": [
    { "name": "glossary", "type": "glossary" },
    { "name": "decisions", "type": "decision",
      "extraFields": [{ "name": "status", "allowed": ["active", "superseded"] }] }
  ],
  "checks": {
    "frontmatter": true,
    "wikilinks": false,
    "ghostLinks": false,
    "graphConnectivity": false
  },
  "staleMonths": 3
}
```

---

## Presets

| Preset | Categories | Checks enabled |
|--------|-----------|----------------|
| `general` | glossary, conventions, decisions, recipes, gotchas | frontmatter only |
| `monorepo` | glossary, conventions, decisions, recipes, gotchas, **repos** | frontmatter + wikilinks + ghostLinks + graphConnectivity |

Use `--categories a,b,c` to override the category list from a preset.

---

## Lifecycle hooks

All hooks guard on `.kbconfig` and exit 0 immediately if the project has no KB configured.

| Event | Hook | Behaviour |
|-------|------|-----------|
| `SessionStart` | `kb-pull.sh` | Fast-forwards the content repo to `origin/<branch>`. Skips silently if offline, dirty tree, or local commits are ahead. |
| `SessionStart` | `kb-stale-sweep.sh` | Flags entries whose `updated` frontmatter date is older than `staleMonths`. |
| `Stop` | `kb-capture-checkpoint.sh` | Once per session, blocks the stop with a self-check nudge when no KB changes have been made. |
| `Stop` | `kb-auto-push.sh` | Validates staged entries; quarantines invalid ones; commits and pushes the clean remainder. |
| `PostToolUse(Read)` | `kb-log-read.sh` | Logs a consult entry to `.usage.log` when Claude reads a KB entry file. De-duplicates per session. |

---

## Validators

The entry validator (`validate.sh`) and opt-in checks (`check-wikilinks.sh`, `check-ghostlinks.sh`, `check-graph.sh`) are vendored into `<kb-dir>/.kb/bin/` at `init` and `sync` time. The git pre-commit hook in the content repo calls `validate.sh` so entries are checked locally before any commit, without requiring the engine repo to be on `PATH`.

Validation reads category types, allowed extra-field values, and enabled checks directly from `kb.json`. No hardcoded category names.

`validate.sh` uses a plain generated git `pre-commit` hook (not lefthook or any external hook manager).

Strict YAML parsing uses `ruby` or `python3` when available; falls back to grep-based parsing otherwise.

---

## Dependencies

- `bash` (>= 3.2)
- `jq`
- `git`
- `python3` or `ruby` (optional - for strict YAML frontmatter parsing; falls back to grep)

---

## Repository layout

```
bin/kb                        # init and sync CLI
content-template/             # files copied into every new content repo
hooks/                        # five lifecycle hook scripts + hooks.json
hooks/hooks.json              # plugin hook wiring (uses ${CLAUDE_PLUGIN_ROOT})
lib/                          # config.sh, gitops.sh, validate.sh, check-*.sh,
                              #   template.sh, precommit.tmpl
presets/general.json          # preset: code team, frontmatter check only
presets/monorepo.json         # preset: multi-repo, all checks enabled
skills/knowledge-base/        # SKILL.md + scripts/log-consult.sh
.claude-plugin/plugin.json    # plugin metadata
.claude-plugin/marketplace.json
install.sh                    # non-plugin install path
tests/                        # test_*.sh + run.sh
```
