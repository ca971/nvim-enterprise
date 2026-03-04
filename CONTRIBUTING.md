```markdown
# Contributing to NvimEnterprise

First off, **thank you** for considering contributing to NvimEnterprise! 🎉
Every contribution helps make this framework better for the entire community.

---

## 📑 Table of Contents

- [Code of Conduct](#-code-of-conduct)
- [How Can I Contribute?](#-how-can-i-contribute)
- [Getting Started](#-getting-started)
- [Development Workflow](#-development-workflow)
- [Project Architecture](#-project-architecture)
- [Coding Standards](#-coding-standards)
- [Commit Convention](#-commit-convention)
- [Pull Request Process](#-pull-request-process)
- [Adding a Language Module](#-adding-a-language-module)
- [Adding a Plugin](#-adding-a-plugin)
- [Adding a User Profile](#-adding-a-user-profile)
- [Reporting Bugs](#-reporting-bugs)
- [Requesting Features](#-requesting-features)
- [Community](#-community)

---

## 📜 Code of Conduct

This project adheres to a [Code of Conduct](CODE_OF_CONDUCT.md). By participating,
you are expected to uphold this code. Please report unacceptable behavior by
[opening an issue](https://github.com/ca971/nvim-enterprise/issues/new).

---

## 🤔 How Can I Contribute?

| Type | Description | Difficulty |
| :--- | :--- | :---: |
| 🐛 **Bug Report** | Found something broken? [Report it](#-reporting-bugs) | Easy |
| 💡 **Feature Request** | Have an idea? [Suggest it](#-requesting-features) | Easy |
| 🌍 **Language Module** | Add support for a new language | Medium |
| 🔌 **Plugin Integration** | Add and configure a new plugin | Medium |
| 📖 **Documentation** | Fix typos, improve guides, add examples | Easy |
| 🧪 **Testing** | Test on different platforms and environments | Easy |
| 🏗️ **Core Architecture** | Improve the framework engine | Advanced |
| 🛡️ **Security** | Audit and harden the sandbox system | Advanced |

---

## 🚀 Getting Started

### Prerequisites

- Neovim `≥ 0.10.0` (nightly recommended)
- Git `≥ 2.30`
- A [Nerd Font](https://www.nerdfonts.com/) installed
- Basic knowledge of Lua and Neovim plugin architecture

### Fork & Clone

```bash
# 1. Fork the repo on GitHub (click the Fork button)

# 2. Clone your fork
git clone https://github.com/<your-username>/nvim-enterprise.git ~/.config/nvim

# 3. Add upstream remote
cd ~/.config/nvim
git remote add upstream https://github.com/ca971/nvim-enterprise.git

# 4. Launch Neovim — plugins will auto-install
nvim
```

### Verify Your Setup

```vim
:NvimHealth
:NvimInfo
```

---

## 🔄 Development Workflow

```
main (stable)
  │
  ├── feat/add-zig-language      ← Feature branches
  ├── fix/telescope-keybind      ← Bug fix branches
  ├── docs/update-readme         ← Documentation branches
  └── refactor/core-bootstrap    ← Refactoring branches
```

### Step-by-Step

```bash
# 1. Sync with upstream
git fetch upstream
git checkout main
git merge upstream/main

# 2. Create a feature branch
git checkout -b feat/your-feature-name

# 3. Make your changes
# ... edit files ...

# 4. Test your changes
nvim  # Verify everything works
# Run :NvimHealth to check for issues

# 5. Commit (see commit convention below)
git add .
git commit -m "feat(langs): add Zig language module"

# 6. Push to your fork
git push origin feat/your-feature-name

# 7. Open a Pull Request on GitHub
```

---

## 🏗️ Project Architecture

Understanding the architecture helps you contribute effectively:

```
lua/
├── config/          # Configuration layer — settings engine, plugin manager
├── core/            # Framework engine — bootstrap, OOP, platform detection
├── langs/           # Language modules — one file per language
├── plugins/         # Plugin specs — categorized by domain
│   ├── ai/          #   AI integrations
│   ├── code/        #   Code intelligence (LSP, completion, treesitter)
│   ├── editor/      #   Editor enhancements (telescope, neo-tree)
│   ├── ui/          #   Visual plugins (statusline, colorschemes)
│   ├── tools/       #   Developer tools (terminal, git)
│   └── misc/        #   Miscellaneous
└── users/           # User namespace system
```

### Key Principles

1. **One file = one concern** — never mix unrelated functionality
2. **Everything is toggleable** — plugins and languages can be enabled/disabled from `settings.lua`
3. **Protected loading** — all modules are loaded via `pcall()` with error logging
4. **No side effects on require** — modules return tables, setup happens explicitly
5. **User overrides always win** — deep-merge cascade: `core → global → user`

---

## 📝 Coding Standards

### Lua Style

We use [StyLua](https://github.com/JohnnyMorganz/StyLua) for formatting. Configuration is in `stylua.toml`.

```bash
# Install StyLua
cargo install stylua

# Format before committing
stylua lua/
```

### Rules

```lua
-- ✅ Good: Descriptive names, consistent style
local function get_active_languages()
  local settings = require("config.settings_manager")
  return settings.get("languages.enabled") or {}
end

-- ❌ Bad: Abbreviated, unclear
local function get_langs()
  local s = require("config.settings_manager")
  return s.get("languages.enabled") or {}
end
```

| Rule | Convention |
| :--- | :--- |
| Indentation | 2 spaces (no tabs) |
| Quotes | Double quotes `"string"` |
| Line length | 120 characters max |
| Naming | `snake_case` for variables/functions, `PascalCase` for classes |
| Modules | Return a table, no global pollution |
| Comments | `-- Single line` or `--- Doc comment` for public APIs |
| Error handling | Always wrap with `pcall()` or `xpcall()` |
| Type hints | Use `--- @param` and `--- @return` annotations |

### File Header

Every new Lua file should include a brief header:

```lua
---
-- @module langs.zig
-- @description Zig language support — Treesitter, LSP (zls), formatter
-- @see langs/_template.lua
---
```

---

## 📏 Commit Convention

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Types

| Type | Usage |
| :--- | :--- |
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no code change |
| `refactor` | Code restructuring, no feature change |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Maintenance, dependencies, CI |

### Scopes

| Scope | Covers |
| :--- | :--- |
| `core` | `lua/core/*` |
| `config` | `lua/config/*` |
| `langs` | `lua/langs/*` |
| `plugins` | `lua/plugins/*` |
| `ui` | `lua/plugins/ui/*` |
| `editor` | `lua/plugins/editor/*` |
| `code` | `lua/plugins/code/*` |
| `ai` | `lua/plugins/ai/*` |
| `users` | `lua/users/*` |
| `lsp` | `lua/plugins/code/lsp/*` |

### Examples

```bash
# Feature
git commit -m "feat(langs): add Zig language module with zls support"

# Bug fix
git commit -m "fix(core): resolve bootstrap race condition on Windows"

# Documentation
git commit -m "docs: update installation instructions for Fedora"

# Refactor
git commit -m "refactor(config): simplify settings deep-merge logic"

# Performance
git commit -m "perf(core): lazy-load platform detection module"

# Breaking change
git commit -m "feat(users)!: rename UserSwap to UserSwitch

BREAKING CHANGE: The :UserSwap command has been renamed to :UserSwitch
for consistency."
```

---

## 🔀 Pull Request Process

### Before Submitting

- [ ] Code follows the [coding standards](#-coding-standards)
- [ ] Files are formatted with StyLua (`stylua lua/`)
- [ ] No `.bak`, `.old`, or `.last` files included
- [ ] `:NvimHealth` passes without errors
- [ ] Changes tested on at least one platform
- [ ] Commit messages follow [convention](#-commit-convention)
- [ ] Documentation updated if applicable

### PR Template

When opening a PR, please include:

```markdown
## Description

Brief description of what this PR does.

## Type of Change

- [ ] 🐛 Bug fix (non-breaking change that fixes an issue)
- [ ] ✨ New feature (non-breaking change that adds functionality)
- [ ] 💥 Breaking change (fix or feature that would break existing functionality)
- [ ] 📖 Documentation update
- [ ] ♻️ Refactor (no functional changes)

## Checklist

- [ ] Tested locally with `nvim` (clean startup, no errors)
- [ ] `:NvimHealth` passes
- [ ] StyLua formatting applied
- [ ] Relevant documentation updated

## Screenshots (if applicable)

<!-- Add screenshots for UI changes -->

## Related Issues

Closes #(issue number)
```

### Review Process

1. A maintainer will review your PR within **48 hours**
2. Automated checks (if configured) must pass
3. At least **1 approving review** is required
4. The maintainer may request changes — this is normal and collaborative
5. Once approved, your PR will be squash-merged into `main`

---

## 🌍 Adding a Language Module

This is one of the easiest and most impactful contributions.

### Step 1: Copy the Template

```bash
cp lua/langs/_template.lua lua/langs/your-language.lua
```

### Step 2: Edit the Module

```lua
---
-- @module langs.your_language
-- @description YourLanguage support — Treesitter, LSP, formatter, linter
---

return {
  -- Treesitter parsers
  treesitter = { "your_language" },

  -- LSP server configuration
  lsp = {
    servers = {
      your_lsp_server = {
        -- Server-specific settings
      },
    },
  },

  -- Formatter (conform.nvim)
  formatter = {
    your_language = { "your_formatter" },
  },

  -- Linter (nvim-lint)
  linter = {
    your_language = { "your_linter" },
  },

  -- DAP (optional)
  dap = {
    -- Debug adapter configuration
  },

  -- Mason packages to auto-install
  mason = {
    "your_lsp_server",
    "your_formatter",
    "your_linter",
  },
}
```

### Step 3: Test

1. Add `"your_language"` to `settings.lua` → `languages.enabled`
2. Open a file of that language type
3. Verify: `:LspInfo`, `:TSInstallInfo`, formatting on save

### Step 4: Submit

```bash
git add lua/langs/your-language.lua
git commit -m "feat(langs): add YourLanguage support with LSP and formatter"
```

---

## 🔌 Adding a Plugin

### Step 1: Choose the Right Category

| Category | Directory | Use Case |
| :--- | :--- | :--- |
| AI | `lua/plugins/ai/` | AI-powered tools |
| Code | `lua/plugins/code/` | LSP, completion, treesitter, linting |
| Editor | `lua/plugins/editor/` | Navigation, file management, editing |
| UI | `lua/plugins/ui/` | Statusline, colorschemes, notifications |
| Tools | `lua/plugins/tools/` | Terminal, git integration, utilities |
| Misc | `lua/plugins/misc/` | Everything else |

### Step 2: Create the Plugin File

```lua
---
-- @module plugins.editor.your-plugin
-- @description Brief description of what this plugin does
-- @see https://github.com/author/your-plugin.nvim
---

local PluginManager = require("config.plugin_manager")

-- Respect the user's settings toggle
if not PluginManager.is_enabled("your_plugin") then
  return {}
end

return {
  {
    "author/your-plugin.nvim",
    event = "VeryLazy",           -- or cmd, ft, keys
    dependencies = {
      -- list dependencies here
    },
    opts = {
      -- plugin configuration
    },
  },
}
```

### Step 3: Register in Category Loader

Edit `lua/plugins/<category>/init.lua` to include your plugin:

```lua
return {
  { import = "plugins.<category>.your-plugin" },
}
```

### Step 4: Test & Submit

```bash
nvim  # Verify plugin loads correctly
git add lua/plugins/<category>/your-plugin.lua
git commit -m "feat(plugins): add your-plugin.nvim for <purpose>"
```

---

## 👤 Adding a User Profile

### Step 1: Create the Directory Structure

```bash
mkdir -p lua/users/your-name/plugins
```

### Step 2: Create Required Files

**`lua/users/your-name/init.lua`**

```lua
return {
  settings = require("users.your-name.settings"),
  keymaps = require("users.your-name.keymaps"),
  plugins = require("users.your-name.plugins"),
}
```

**`lua/users/your-name/settings.lua`**

```lua
return {
  ui = {
    colorscheme = "tokyonight",
  },
  languages = {
    enabled = { "lua", "python", "rust" },
  },
}
```

**`lua/users/your-name/keymaps.lua`**

```lua
-- User-specific keybindings
```

**`lua/users/your-name/plugins/init.lua`**

```lua
-- User-specific plugin overrides
return {}
```

---

## 🐛 Reporting Bugs

### Before Reporting

1. Update to the latest version: `git pull`
2. Run `:NvimHealth` and check for known issues
3. Search [existing issues](https://github.com/ca971/nvim-enterprise/issues)
4. Try with a clean config: `nvim --clean`

### Bug Report Template

Open a [new issue](https://github.com/ca971/nvim-enterprise/issues/new) with:

```
**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
1. Open Neovim
2. Run command '...'
3. See error

**Expected behavior**
What you expected to happen.

**Environment**
- OS: [e.g. macOS 14.5, Ubuntu 24.04]
- Neovim version: [output of `nvim --version`]
- Terminal: [e.g. WezTerm, Alacritty, iTerm2]

**NvimHealth output**
Paste output of :NvimHealth

**Screenshots / Logs**
If applicable
```

---

## 💡 Requesting Features

Open a [new issue](https://github.com/ca971/nvim-enterprise/issues/new) with:

```
**Is your feature request related to a problem?**
A clear description of the problem. Ex: "I'm always frustrated when..."

**Describe the solution you'd like**
What you want to happen.

**Describe alternatives you've considered**
Other solutions or features you've considered.

**Additional context**
Any other context, mockups, or screenshots.
```

---

## 💬 Community

- 🐛 [Issues](https://github.com/ca971/nvim-enterprise/issues) — Bug reports and feature requests
- 💬 [Discussions](https://github.com/ca971/nvim-enterprise/discussions) — Questions, ideas, show and tell
- 📖 [Wiki](https://github.com/ca971/nvim-enterprise/wiki) — Extended documentation

---

<div align="center">

**Thank you for helping make NvimEnterprise better!** 🚀

Every contribution — no matter how small — is valued and appreciated.

</div>
```
