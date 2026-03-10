# 🪝 Git Hooks Reference

## Overview

| Hook | When | Blocking | Checks |
| --- | --- | --- | --- |
| `pre-commit` | Before commit | Yes | Code quality |
| `commit-msg` | After message | Yes | Message format |
| `pre-push` | Before push | Yes | Syntax + formatting |
| `post-merge` | After pull/merge | No | Notifications |

## pre-commit

Verifies code quality **before** every commit.

| # | Check | Impact | Description |
| --- | --- | --- | --- |
| 1 | Debug markers | ⚠️ Warning | TODO, FIXME, console.log, debugger |
| 2 | Backup files | 🚫 Block | .bak, .old, .swp, .tmp |
| 3 | Large files | 🚫 Block | > 5MB |
| 4 | Secrets | 🚫 Block | Passwords, API keys, tokens |
| 5 | Conflict markers | 🚫 Block | `<<<<<<<`, `=======`, `>>>>>>>` |
| 6 | StyLua | 🚫 Block | Lua formatting |
| 7 | Lua syntax | 🚫 Block | luajit > luac5.1 > luac |
| 8 | ShellCheck | ⚠️ Warning | Shell scripts |
| 9 | YAML/JSON | ⚠️/🚫 | Syntax validation |
| 10 | Trailing whitespace | ⚠️ Warning | Spaces at end of lines |
| 11 | .env files | 🚫 Block | Must not be committed |

## commit-msg

Validates the **Conventional Commits** format.

```conf
<type>(<scope>): <subject>
```

Accepted types:
feat | fix | docs | style | refactor | perf | test
build | ci | chore | revert | release

Breaking change: `feat!` or `BREAKING CHANGE:` in footer.

| Check | Blocking | Description |
| --- | --- | --- |
| Format | 🚫 | `type(scope): subject` |
| Subject length | ⚠️ | ≤ 72 characters |
| Ending period | ⚠️ | No `.` at the end |
| Imperative mood | ⚠️ | Use "add" instead of "added" |
| Blank line | ⚠️ | Between subject and body |
| Body length | ⚠️ | ≤ 100 per line |

Auto-skip: merge commits, WIP, fixup!, squash!, `Revert "..."`

## pre-push

The final gatekeeper **before** code leaves your machine.

| # | Check | Blocking | Description |
| --- | --- | --- | --- |
| 1 | WIP commits | 🚫 | fixup!, squash!, wip |
| 2 | Lua syntax | 🚫 | All .lua files |
| 3 | StyLua | 🚫 | Formatting check |
| 4 | Version (tags) | 🚫 | Tag must match version.lua |
| 5 | CHANGELOG (tags) | ⚠️ | Entry must exist |
| 6 | Protected branch | 🚫/✅ | Interactive confirmation |
| 7 | Dirty tree | ⚠️ | Uncommitted changes |

## post-merge

Smart notifications **after** a pull or merge.

| Info | Description |
| --- | --- |
| Files by area | core/, plugins/, langs/, config/ |
| lazy-lock.json | → Reminder to run `:Lazy sync` |
| version.lua | → Displays new version |
| CHANGELOG.md | → Displays latest entry |
| New/deleted Lua files | → Lists modules |
| Core config | → Restart reminder for settings/options/keymaps |
| Commit count + authors | → Summary |

## Location

.git/hooks/
├── pre-commit    ← Code quality
├── commit-msg    ← Message format
├── pre-push      ← Final gate
└── post-merge    ← Notifications

## Bypass (Emergency)

```bash
git commit --no-verify -m "hotfix: urgent"
git push --no-verify
```
