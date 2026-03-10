# 📋 Versioning Strategy

## Semantic Versioning (SemVer)

NvimEnterprise follows [SemVer 2.0.0](https://semver.org/) with two distinct versioning levels.

```
MAJOR.MINOR.PATCH[-pre]
  │     │     │      └─ Pre-release: alpha, beta, rc.1
  │     │     └──────── Patch: fix, refactor, docs, style
  │     └────────────── Minor: new feature, module, command
  └──────────────────── Major: breaking change, architectural overhaul
```

## Two Versioning Levels

| Level | Scope | Location | Example |
| --- | --- | --- | --- |
| **Project** | Entire repository | `lua/core/version.lua` + Git tag | `v1.1.0` |
| **Module** | Individual file | `---@version` in the header | `@version 2.2.0` |

### Single Source of Truth: `lua/core/version.lua`

```lua
local M = {
    major = 1,
    minor = 1,
    patch = 0,
    pre = nil,
}
```

All other files **read** from this source:

* `init.lua` → `dofile("lua/core/version.lua")`
* `:Version` command → `require("core.version").show()`
* `release.sh` → Updates via `sed`
* CI → Parses via `grep`

### Per-Module Version (Independent)

```lua
-- lua/plugins/ui/lualine.lua
---@version 2.2.0  ← MODULE version, distinct from project version
```

A module can be at `v3.0.0` while the project itself is at `v1.2.0`.

## Involved Files

| File | Role |
| --- | --- |
| `lua/core/version.lua` | Single Source of Truth (major, minor, patch) |
| `init.lua` | `@version` in the LuaDoc header |
| `CHANGELOG.md` | Human-readable history |
| `scripts/release.sh` | Updates version.lua + init.lua |
| `.github/workflows/ci.yml` | Verifies Git tag matches version.lua |

## Architecture Flow

```
lua/core/version.lua  (Single Source of Truth)
        │
        ├──→ init.lua            dofile() → _G.NvimConfig.version
        ├──→ :Version            User command
        ├──→ :NvimVersion        Alias
        ├──→ release.sh          Updated via sed
        ├──→ CI                  Parsed via grep
        └──→ CHANGELOG.md        Human reference
```
