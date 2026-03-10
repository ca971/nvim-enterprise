# 🏗️ Architecture

## Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                      NvimEnterprise Stack                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────┐   ┌──────────┐  ┌──────────┐  ┌─────────────────┐  │
│  │  Users   │   │  Langs   │  │ Plugins  │  │       AI        │  │
│  │Namespace │   │ Modules  │  │ Registry │  │    Providers    │  │
│  └────┬─────┘   └────┬─────┘  └────┬─────┘  └──────┬──────────┘  │
│       │              │             │               │             │
│  ┌────▼──────────────▼─────────────▼───────────────▼──────────┐  │
│  │        Config Layer (Settings · Plugin · Colorscheme)      │  │
│  └────────────────────────────┬───────────────────────────────┘  │
│                               │                                  │
│  ┌────────────────────────────▼───────────────────────────────┐  │
│  │         Core Engine (OOP / Class System / Lua)             │  │
│  │  bootstrap · class · settings · platform · security · log  │  │
│  │  version · icons · health · utils · secrets                │  │
│  └────────────────────────────┬───────────────────────────────┘  │
│                               │                                  │
│  ┌────────────────────────────▼───────────────────────────────┐  │
│  │               Neovim 0.10+ Runtime                         │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## Boot Pipeline (init.lua)

```
Phase 1 — Version Guard        Neovim >= 0.10.0?
Phase 2 — Disable Built-ins    ~15 built-in plugins disabled
Phase 3 — Cache References     Localize vim.uv, stdpath(), etc.
Phase 4 — Load Version         dofile(core/version.lua)
Phase 5 — Global Namespace     _G.NvimConfig = { ... }
Phase 6 — Secrets              .env sync + async loading
Phase 7 — Bootstrap Core       require("core")
```

## Directory Structure

```
lua/
├── core/            Framework engine (low-level)
│   ├── class.lua      OOP: inheritance, mixins, types
│   ├── platform.lua   Detection: OS, SSH, Docker, WSL, runtimes
│   ├── settings.lua   Defaults + schema
│   ├── version.lua    SemVer (Single Source of Truth)
│   ├── secrets.lua    Secure .env loader
│   ├── security.lua   Sandbox, path validation
│   ├── bootstrap.lua  Deterministic init sequence
│   ├── icons.lua      Centralized icon registry
│   ├── logger.lua     Structured logging
│   ├── health.lua     :checkhealth integration
│   └── utils.lua      Shared utilities
│
├── config/          Configuration layer
│   ├── settings_manager.lua    Deep-merge settings
│   ├── plugin_manager.lua      Per-plugin toggle logic
│   ├── colorscheme_manager.lua Runtime theme switching
│   ├── commands.lua            Enterprise commands
│   └── lazy.lua                Lazy.nvim bootstrap
│
├── langs/           1 file = 1 language
│   ├── _template.lua    Template for new languages
│   ├── lua.lua          Treesitter + LSP + formatter
│   ├── python.lua       ...
│   └── ...              45+ languages
│
├── plugins/         Specs by category
│   ├── ai/            Copilot, Avante, CodeCompanion
│   ├── code/          CMP, Conform, Treesitter, LSP
│   ├── editor/        Telescope, Neo-tree, Flash
│   ├── ui/            Lualine, Bufferline, Noice
│   ├── tools/         LazyGit, ToggleTerm
│   └── misc/          StartupTime, Wakatime
│
└── users/           Isolated namespaces
    ├── namespace.lua      Isolation engine
    ├── user_manager.lua    User CRUD
    ├── default/           Default profile
    ├── jane/              Example profile
    └── john/              Example profile
```

## Design Principles

| Principle | Implementation |
| --- | --- |
| **Single Responsibility** | Each file has one dedicated role |
| **Defensive Programming** | `pcall()` on all external access/requires |
| **Single Source of Truth** | `version.lua`, `settings.lua`, `icons.lua` |
| **Lazy Loading** | Plugins loaded via event/cmd/ft/keys |
| **Caching** | Costly data cached (versions, env, hostname) |
| **Fallbacks** | Every module provides default values |

## Singletons & Access Patterns

| Module | Pattern | Access |
| --- | --- | --- |
| `platform` | Singleton via `get_instance()` | `require("core.platform")` |
| `settings` | Singleton via `Class:extend()` | `require("core.settings")` |
| `version` | Table module (non-OOP) | `require("core.version")` |
| `icons` | Table module (non-OOP) | `require("core.icons")` |

