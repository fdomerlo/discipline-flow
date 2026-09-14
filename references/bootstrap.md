# Flow A — Bootstrap a repository

## Steps

### Option 1 — Automated via script (Recommended)

Run `scripts/init.sh` from this skill (resolves templates and paths automatically):

```bash
bash <path-to-skill>/scripts/init.sh --test-cmd "<TEST_COMMAND>" [--project-name "<NAME>"]
```

Options:
- `-t, --test-cmd`: Test suite command (e.g. `pytest`, `npm test`, `cargo test`).
- `-p, --project-name`: Explicit project name (defaults to target directory name).
- `-d, --target-dir`: Target repository root (defaults to `.`).
- `--no-hooks`: Skip git hooks installation (by default, both `pre-commit` and `commit-msg` hooks are installed).
- `-f, --force`: Overwrite existing contract files completely (by default, `init.sh` safely appends/updates the delimited block).

**What gets installed:**
1. `AGENTS.md` and `CLAUDE.md` with managed contract markers.
2. Runtime scripts in `scripts/`:
   - `scripts/sdd.sh` (unified CLI controller).
   - `scripts/verify-crit.sh` (CRIT-XX determinism gate).
   - `scripts/new-plan.sh` (plan scaffolding).
3. Deterministic Git hooks in `.git/hooks/`:
   - `pre-commit`: Blocks code commits during `sdd_state: plan`.
   - `commit-msg`: Enforces Conventional Commits and reference to the active phase (e.g. `F1`).

**Handling pre-existing `AGENTS.md` and `CLAUDE.md`:**
- If `AGENTS.md` exists, `init.sh` appends the Discipline Flow contract inside managed delimiters (`<!-- BEGIN DISCIPLINE-FLOW -->` ... `<!-- END DISCIPLINE-FLOW -->`), preserving all pre-existing project rules. If re-run, it updates only that section in place.
- If `CLAUDE.md` exists, `init.sh` appends `@AGENTS.md` if not already present.

### Option 2 — Manual step-by-step (Fallback)

1. Confirm repo root (git init if needed — ask first, don't init silently
   over an existing non-git project).
2. Fill `assets/AGENTS.md.template` placeholders:
   - `{{PROJECT_NAME}}` — name of the repository/project.
   - `{{TEST_COMMAND}}` — the project's actual test invocation. Ask if not
     obvious from the stack (don't guess `pytest` for a project that turns
     out to use `unittest` or `go test`).
   - `{{COMMIT_TYPES}}` — default: `feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert, release`.
     Ask only if the project has an existing convention to match.
3. Write or append to `AGENTS.md` at the repo root:
   - If `AGENTS.md` does not exist: write the filled template directly.
   - If `AGENTS.md` already exists: do NOT overwrite it. Append the filled template enclosed between `<!-- BEGIN DISCIPLINE-FLOW -->` and `<!-- END DISCIPLINE-FLOW -->` at the end of the file.
4. Set up `CLAUDE.md` at the repo root:
   - If `CLAUDE.md` does not exist: create it with `@AGENTS.md`.
   - If `CLAUDE.md` exists: ensure it includes `@AGENTS.md` (append if missing).

   Claude Code uses `CLAUDE.md` as its entry point; this `@AGENTS.md`
   import is Anthropic's documented pattern to include external markdown
   rules without duplicate maintenance. A symlink (`ln -s AGENTS.md CLAUDE.md`)
   also works and is equally valid, but needs developer mode or elevated
   permissions on Windows — prefer the import directive unless requested otherwise.

   **Never copy the contract prose into both files.** Two copies of a
   contract is two contracts, and they will diverge.
5. Install git hooks (`pre-commit` and `commit-msg`):
   - Copy `<skill-dir>/scripts/pre-commit` to `.git/hooks/pre-commit`, `chmod +x`.
   - Copy `<skill-dir>/scripts/commit-msg-hook.sh` to `.git/hooks/commit-msg`, `chmod +x`.
   - Inform the user that in an emergency, hooks can be bypassed with `git commit --no-verify`.
6. Copy `<skill-dir>/scripts/sdd.sh` and `<skill-dir>/scripts/verify-crit.sh` to `scripts/`.
7. Report what was written and stop. Don't start writing project code in
   the same turn unless the user asked for that too.

## Why each rule in the contract exists (for when the user asks)

- **Conventional commits** — makes the history itself a queryable log of
  intent; a `git log --oneline` becomes a changelog draft for free.
- **Active phase in commits** — guarantees traceability between git history and the plan.
- **Pre-commit blocking during plan mode** — guarantees that no code is written before specs and criteria are approved.
- **Test before first change, after every logical unit** — the cheapest
  possible check against an agent's unstated assumption that something
  still works.
- **Never leave the suite red at a commit boundary** — a red commit means
  the next session (agent or human) inherits a broken baseline with no
  signal of whose change broke it.
- **Atomic commits, one concern each** — makes `git revert` a real option
  instead of a surgical mess.
- **The plan-mode clause** (see `plan-cycle.md`) — is what upgrades this
  contract from "good habits" to "governs multi-session work," the moment
  the task outgrows a single sitting.
