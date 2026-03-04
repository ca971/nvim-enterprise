---@file lua/core/bootstrap.lua
---@description Bootstrap — boot sequence orchestrator for NvimEnterprise
---@module "core.bootstrap"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.platform Platform detection singleton (OS, arch, SSH, WSL, Docker, GUI)
---@see core.settings Settings loader and merger (user overrides, defaults)
---@see core.options Neovim native options applicator (vim.opt, vim.o, vim.g)
---@see core.keymaps Core keymaps registration (non-plugin keymaps)
---@see core.autocmds Core autocommands registration (non-plugin autocmds)
---@see config Plugin layer entry point (lazy.nvim bootstrap + plugin specs)
---@see core.logger Structured logging utility
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/bootstrap.lua — Boot sequence orchestrator                         ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Bootstrap Pipeline (sequential, order matters)                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Step 1 ─ core.platform                                          │    ║
--- ║  │  │  Detect OS, arch, SSH, WSL, Docker, GUI                       │    ║
--- ║  │  │  Populate _G.NvimConfig.platform for global access            │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Step 2 ─ core.settings                                          │    ║
--- ║  │  │  Load defaults + merge user overrides                         │    ║
--- ║  │  │  Exposes plugin-enabled checks, UI prefs, etc.                │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Step 3 ─ core.options                                           │    ║
--- ║  │  │  Apply vim.opt / vim.o / vim.g based on settings              │    ║
--- ║  │  │  Must run after settings are resolved                         │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Step 4 ─ config (lazy.nvim)                                     │    ║
--- ║  │  │  Bootstrap lazy.nvim package manager                          │    ║
--- ║  │  │  Load all plugin specs from lua/plugins/**                    │    ║
--- ║  │  │  Failure is caught + logged (non-fatal)                       │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Step 5 ─ core.keymaps                                           │    ║
--- ║  │  │  Register core keymaps (non-plugin)                           │    ║
--- ║  │  │  Must run after plugins to avoid keymap conflicts             │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Step 6 ─ core.autocmds                                          │    ║
--- ║  │  │  Register core autocommands (non-plugin)                      │    ║
--- ║  │  │  Must run last: depends on options + plugins being ready      │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ✓ _G.NvimConfig.state.bootstrap_done = true                     │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Error handling:                                                         ║
--- ║  • Config layer failure is caught with pcall (non-fatal)                 ║
--- ║  • Error is logged via core.logger AND shown via vim.notify              ║
--- ║  • Other steps are not wrapped: a failure there is intentionally         ║
--- ║    fatal — the editor cannot function without platform/settings/options  ║
--- ║                                                                          ║
--- ║  Global state:                                                           ║
--- ║  • _G.NvimConfig.platform   Populated in Step 1 (read-only after)        ║
--- ║  • _G.NvimConfig.state.bootstrap_done   Set to true on completion        ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

---@class BootstrapModule
---@field run fun() Execute the complete bootstrap pipeline
local M = {}

--- Execute the complete NvimEnterprise bootstrap pipeline.
---
--- Runs the initialization steps in strict sequential order.
--- Each step depends on the previous one being completed:
--- platform → settings → options → config (plugins) → keymaps → autocmds.
---
--- The config layer (lazy.nvim + plugins) is the only step wrapped in
--- `pcall` because plugin failures should not prevent the editor from
--- starting. All other steps are intentionally unwrapped — if platform
--- detection or options fail, the editor is in an unusable state anyway.
---
--- Sets `_G.NvimConfig.state.bootstrap_done = true` on successful completion.
---@return nil
function M.run()
	-- ── Step 1: Platform detection ───────────────────────────────────
	-- Singleton module — detection runs on first `require`.
	-- Results are copied to the global namespace for convenient
	-- access from any module without requiring core.platform again.
	local platform = require("core.platform")
	_G.NvimConfig.platform = {
		os = platform.os,
		arch = platform.arch,
		is_ssh = platform.is_ssh,
		is_wsl = platform.is_wsl,
		is_docker = platform.is_docker,
		is_gui = platform.is_gui,
		config_dir = platform.config_dir,
	}

	-- ── Step 2: Settings ─────────────────────────────────────────────
	-- Load default settings and merge any user overrides.
	-- Must run before options (Step 3) because options read from settings.
	local settings = require("core.settings")
	settings:load()

	-- ── Step 3: Neovim options ───────────────────────────────────────
	-- Apply vim.opt, vim.o, vim.g values derived from settings.
	-- Must run after settings are resolved (Step 2).
	require("core.options").setup()

	-- ── Step 4: Config layer (lazy.nvim + plugins) ───────────────────
	-- Bootstrap lazy.nvim and load all plugin specs.
	-- Wrapped in pcall: plugin failures should not prevent the editor
	-- from starting — the user can still edit files and fix configs.
	local ok, err = pcall(require, "config")
	if not ok then
		local Logger = require("core.logger")
		local log = Logger:for_module("core.bootstrap")
		log:error("Failed to load config layer: %s", tostring(err))
		vim.notify("NvimEnterprise: Failed to load config layer.\n" .. tostring(err), vim.log.levels.ERROR)
	end

	-- ── Step 5: Core keymaps ─────────────────────────────────────────
	-- Register non-plugin keymaps (navigation, window management, etc.).
	-- Must run after plugins (Step 4) to avoid conflicts with
	-- plugin-defined keymaps and to allow overrides.
	require("core.keymaps")

	-- ── Step 6: Core autocommands ────────────────────────────────────
	-- Register non-plugin autocommands (highlight on yank, etc.).
	-- Must run last: autocmds may reference options AND plugins.
	require("core.autocmds").setup()

	-- ── Bootstrap complete ───────────────────────────────────────────
	-- Signal to other modules that the full pipeline has finished.
	-- Modules can check this flag to defer work until boot is done.
	_G.NvimConfig.state.bootstrap_done = true
end

return M
