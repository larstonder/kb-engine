---
description: Scaffold or sync this project's knowledge-base content repo (wraps the kb CLI)
argument-hint: "init <dir> [--preset general|monorepo] [--mode standalone|submodule] [--branch <b>]  |  sync"
allowed-tools: Bash
---

The user invoked the knowledge-base engine CLI with arguments: `$ARGUMENTS`

If `$ARGUMENTS` is empty, do NOT run anything - just print the usage:
`/kb init <dir> [--preset general|monorepo] [--mode standalone|submodule] [--branch <b>]` and `/kb sync`.

Otherwise run the engine's bundled CLI from the current project root so the relative content dir and `.kbconfig` land in the right place:

```bash
cd "${CLAUDE_PROJECT_DIR:-$PWD}" && "${CLAUDE_PLUGIN_ROOT}/bin/kb" $ARGUMENTS
```

Then report concisely:

- **`init` succeeded** - confirm what was created: the category folders, `kb.json`, the vendored validators in `<kb-dir>/.kb/bin/`, the git pre-commit hook, and `.kbconfig` in the project root. Remind the user that the engine's lifecycle hooks load at **session start**, so they take effect on the **next** session in this project. If they want the KB to sync to a remote, tell them to add one to the content repo (`git -C <kb-dir> remote add origin <url>` and push once) - after that the Stop hook auto-commits and pushes, and SessionStart fast-forwards.
- **`sync` succeeded** - confirm the vendored validators + pre-commit hook were refreshed and any newly-added category folders were created.
- **Failed** - show the error and the fix: valid `--preset` is `general` or `monorepo`; valid `--mode` is `standalone` or `submodule`.
