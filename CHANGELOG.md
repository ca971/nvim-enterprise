# Changelog

All notable changes to **nvim-enterprise** are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- …

## [1.1.1] - 2026-03-10

### Changed
- **versioning**: `core/version.lua` is now the single source of truth
- **init.lua**: reads version from `core/version.lua` via `dofile()` (was `settings.lua`)
- **settings.lua**: removed `version` field (was duplicated)
- **version.lua**: command registration deferred via `setup_commands()` guard

### Removed
- **settings.lua**: `version = "1.0.0"` field (duplicated source of truth)
## [1.1.0] - 2026-03-10

### Changed
- **lualine**: Refactored statusline — contextual `lang_runtime` component replaces
  hardcoded `python_version`, `node_version`, and `runtimes_component`
- **lualine**: Section B always visible (git branch or CWD fallback)
- **lualine**: Section X anchor pattern — `user_component` always last for clean X→Y separator
- **lualine**: `comp()` factory reduces per-component boilerplate from 6 lines to 1
- **platform**: `lua` runtime entry now prefers `luajit` over `lua`

### Fixed
- **lualine**: Separator glitch when section B empty (no git repo)
- **lualine**: Separator glitch between sections X→Y (no LSP attached)
- **lualine**: Missing diagnostics display (`sources`, `sections`, `colored` options)
- **lualine**: Missing space between powerline separator and filename
- **secrets**: `luac` 5.4 error — `attempt to assign to const variable 'line'` in for loop
- **hooks**: `pre-push` now prefers `luajit` over system `luac` for syntax checking

### Added
- **lualine**: `lang_runtime()` — icon + version for 17 languages, driven by platform registry
- **lualine**: `diag_summary()` — compact diagnostic count in section X
- **lualine**: `branch_or_cwd()` — always-visible section B with project dir fallback
- **lualine**: Elite LuaDoc annotations (`@class`, `@field`, `@param`, `@return`, `@nodiscard`)
- **platform**: `Platform:get_runtime_executable()` — resolve first available executable
- **platform**: `Platform.RUNTIME_EXECUTABLES` — exposed as public class property
- **versioning**: `lua/core/version.lua` — single source of truth for project version
- **versioning**: `CHANGELOG.md` — Keep a Changelog format
- **versioning**: `scripts/release.sh` — semi-automated release workflow
- **versioning**: SemVer strategy documented in README

## [1.0.0] - 2026-03-04

### Added
- Initial release
- **Core modules**: bootstrap, class, settings, platform, security, secrets, icons, logger, utils
- **Config layer**: settings_manager, plugin_manager, colorscheme_manager, commands
- **Plugin specs**: 35+ plugins across ai/, code/, editor/, ui/, tools/, misc/
- **Language modules**: 45+ languages with Treesitter, LSP, formatters, linters, DAP
- **User system**: Multi-user namespaces with hot-swap, CRUD, isolation
- **AI integration**: Copilot, Avante, CodeCompanion, Continue
- **Platform detection**: OS, architecture, SSH, WSL, Docker, Proxmox, VPS, GUI, runtimes
- **Security**: Sandbox loading, path validation, .env secrets with permission checks
- **CI**: GitHub Actions — lint, syntax check, startup test, auto-release

[Unreleased]: https://github.com/ca971/nvim-enterprise/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/ca971/nvim-enterprise/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/ca971/nvim-enterprise/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ca971/nvim-enterprise/releases/tag/v1.0.0
