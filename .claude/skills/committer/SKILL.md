---
name: committer
description: Split the working tree into micro commits using Arlo Belshee's Commit Notation (risk symbol + intent letter). Use when the user types /committer or asks to commit changes in this WowMods repo. Drafts a commit plan, waits for approval, then stages and commits. Never pushes.
---

# Committer (WowMods)

Turn the current changes into small, single-purpose commits written in Arlo's Commit Notation. Optional arguments after `/committer` are hints (e.g. a focus area or intent); treat them as guidance, not commands.

## Message format

```
<risk> <intent> <description>

<optional short body>

Co-Authored-By: <current model name and version> <noreply@anthropic.com>
```

The first three characters are the notation: a risk symbol, a space, an intent letter.

### Risk symbol (how sure are we nothing broke?)

| Symbol | Meaning | Use when |
|---|---|---|
| `.` | Proven safe | Provable no-behavior-change: tool-driven rename, comment-only, formatting, docs. |
| `^` | Validated | Automated tests exist, cover the change, and passed. **Never claim `^` without tests that were actually run.** |
| `!` | Risky | Some risk unverified, e.g. only checked by hand or by compiling. Default when unsure. |
| `@` | Probably broken | Savepoint or work in progress. May not compile or run. |

### Intent letter

| Letter | Meaning |
|---|---|
| `F` / `f` | Feature |
| `B` / `b` | Bugfix |
| `R` / `r` | Refactoring |
| `D` / `d` | Documentation |
| `T` / `t` | Tests |
| `C` / `c` | Config, tooling, build, repo housekeeping |

### Casing

- **Uppercase** = the commit intends to change behavior.
- **Lowercase** = the commit intends to change no behavior.

So `F` and `B` are normally uppercase; `R`, `D`, `T` and `C` are normally lowercase. Flag a mismatch (e.g. a lowercase `r` whose diff changes behavior) and fix it before committing: either correct the letter or split the commit.

### Examples

- `. r Rename isMiner to hasMining`
- `! F Restore last gather tracker after Hunter Track`
- `. d Fix typo in README`
- `! c Add package script`
- `@ F WIP tracker toggle button`

## Micro-commit rules

- One logical change per commit. Never mix a refactor with a behavior change.
- Order: refactors and prep first (`r`, `c`, `t`), then the behavior change (`F`/`B`) on top.
- If one file holds changes for several commits, split by hunk. Interactive `git add -p` is not available here, so build a patch and use `git apply --cached`, or stage the file whole in the commit where it fits best and say so in the plan.
- Subject line: imperative mood, about 50 characters, no trailing period.
- Body: usually omit it. Add one or two short lines only when the *why* isn't obvious from the subject. Short and trite beats long and wordy.

## Workflow

1. Run `git status`, `git diff` and `git diff --staged`, and `git log --oneline -5` to see the changes and recent style.
2. If there is nothing to commit, say so and stop.
3. Group the changes into micro commits in a sensible order.
4. Show the plan as a numbered list: the full subject line, any body, and the files (or hunks) for each commit. Ask the user to approve, edit, or reject. **Do not stage or commit before approval.**
5. For each approved commit, in order: stage only that commit's files with explicit paths (never `git add -A` or `git add .`), then commit using a heredoc for the message.
6. After the last commit, run `git log --oneline` for the new commits and `git status`, and report the result.

## Hard rules

- Never push. The user pushes.
- Never amend, rebase, or force anything unless the user asks.
- Never skip hooks (`--no-verify`). If a hook fails, report it and fix the cause.
- Never commit files that look like secrets (`.env`, credentials, keys). Warn instead.
- Always include the `Co-Authored-By` trailer naming the current model and version. If the session context supplies an exact attribution line, use it verbatim.

## Project specifics (WowMods)

- This repo holds World of Warcraft addons, one folder per addon under `addons/`. There is no automated test setup, so `^` is essentially never right here. Use `.` for provable no-behavior changes and `!` for changes checked in game.
- Changes inside one addon folder usually belong together, but still split a refactor from a behavior change. Changes to different addons go in different commits.
- A `.toc` edit that changes the load list or `## Interface:` number is behavior-affecting: use `C` (uppercase) and mention the addon in the subject.
- Repo-level files (`README.md`, `.gitignore`, `tools/`, `docs/`) use `d`, `c`, or `C` as fits. Keep them out of addon commits.
- Note the addon in the description when it isn't obvious, e.g. `! F Gatherer: restore last tracker`.
