---@file init.lua
---@description NvimEnterprise — Root entry point and boot sequence orchestrator
---@module "init"
---@author ca971
---@license MIT
---@version 1.1.1
---@since 2026-01
---
---@see core            Core bootstrap orchestrator (platform, settings, lazy, plugins)
---@see core.class      Base OOP system (ExtrasBrowser extends Class)
---@see core.platform   Platform singleton (detection: OS, paths, capabilities)
---@see core.icons      Centralized icon definitions (UI, git, misc)
---@see core.logger     Structured logging (Logger:for_module)
---@see core.settings   Settings singleton (extras enabled state, float_border)
---@see core.secrets    Environment variable and .env file management
---@see core.security   Path validation, namespace sanitization, safe loading, and settings validation
---@see core.utils      File I/O, deep copy, table contains utilities
---@see core.bootstrap  Core bootstrap (loads before this module)
---@see core.health     Comprehensive :checkhealth provider for NvimEnterprise
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  init.lua — Root entry point & boot sequence                             ║
--- ║                                                                          ║
--- ║  Boot Pipeline (sequential, ~15-25ms total):                             ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │                                                                  │    ║
--- ║  │  Phase 1 — Version Guard                                         │    ║
--- ║  │  ├─ Check Neovim >= 0.10.0                                       │    ║
--- ║  │  └─ Fast exit with error message if incompatible                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Phase 2 — Disable Built-in Plugins                              │    ║
--- ║  │  ├─ File format plugins (gzip, zip, tar)                         │    ║
--- ║  │  ├─ Remote/network plugins (netrw, getscript)                    │    ║
--- ║  │  ├─ Unused utility plugins (vimball, 2html, tutor)               │    ║
--- ║  │  ├─ Match plugins (matchit, matchparen → treesitter)             │    ║
--- ║  │  └─ Language providers (python3, ruby, perl, node)               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Phase 3 — Performance: Cache & Fast Paths                       │    ║
--- ║  │  ├─ Cache vim.uv / vim.loop reference                            │    ║
--- ║  │  └─ Cache stdpath("config") result                               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Phase 4 — Load Version                                          │    ║
--- ║  │  ├─ Read settings.lua via dofile() (faster than require)         │    ║
--- ║  │  └─ Extract version string for global namespace                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Phase 5 — Global Namespace (_G.NvimConfig)                      │    ║
--- ║  │  ├─ version   — SemVer from settings.lua                         │    ║
--- ║  │  ├─ settings  — Populated lazily by core.settings                │    ║
--- ║  │  ├─ platform  — Populated lazily by core.platform                │    ║
--- ║  │  └─ state     — Runtime flags (active_user, plugins_loaded, …)   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Phase 6 — Secrets (two-phase loading)                           │    ║
--- ║  │  ├─ Sync:  Load ~/.config/nvim/.env                              │    ║
--- ║  │  │         (plugins need API keys available at setup() time)     │    ║
--- ║  │  └─ Async: Load project .env + register :AI* commands            │    ║
--- ║  │            (deferred via vim.schedule, saves ~2-3ms)             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Phase 7 — Bootstrap Core                                        │    ║
--- ║  │  └─ require("core") → core/init.lua                              │    ║
--- ║  │     ├─ Platform detection                                        │    ║
--- ║  │     ├─ Settings loading & merging                                │    ║
--- ║  │     ├─ Lazy.nvim bootstrap                                       │    ║
--- ║  │     └─ Plugin loading                                            │    ║
--- ║  │                                                                  │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Performance Notes:                                                      ║
--- ║  • Built-in plugin disabling saves ~10-15ms (no file I/O)                ║
--- ║  • dofile() used instead of require() for data-only settings.lua         ║
--- ║  • uv.fs_stat() used instead of vim.fn.filereadable()                    ║
--- ║    (avoids vimscript boundary crossing)                                  ║
--- ║  • Local references to vim.uv, vim.fn.stdpath avoid repeated lookups     ║
--- ║  • Secrets Phase 2 deferred to keep critical path minimal                ║
--- ║  • vim.g assignments are direct C calls — no Lua overhead                ║
--- ║                                                                          ║
--- ║  Compatibility:                                                          ║
--- ║  • Requires Neovim >= 0.10.0 (vim.uv, native LSP, treesitter)            ║
--- ║  • Cross-platform: Linux, macOS, Windows, WSL, Termux                    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 1 — VERSION GUARD
--
-- Fast exit if Neovim version is incompatible. Uses vim.fn.has() only
-- once — it is a vimscript call and should not be repeated in hot paths.
-- ═══════════════════════════════════════════════════════════════════════════

if vim.fn.has("nvim-0.10.0") ~= 1 then
	vim.api.nvim_echo({
		{ "NvimEnterprise requires Neovim >= 0.10.0\n", "ErrorMsg" },
		{ "Current: " .. tostring(vim.version()) .. "\n", "WarningMsg" },
	}, true, {})
	return
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 2 — DISABLE BUILT-IN PLUGINS
--
-- Direct table assignment is faster than iterating a list.
-- Each vim.g assignment is a single C call — no Lua overhead.
-- Disabling these avoids unnecessary file I/O at startup (~10-15ms saved).
-- ═══════════════════════════════════════════════════════════════════════════

do
	local g = vim.g

	-- ── File format plugins (never used with modern tooling) ─────────
	g.loaded_gzip = 1
	g.loaded_zip = 1
	g.loaded_zipPlugin = 1
	g.loaded_tar = 1
	g.loaded_tarPlugin = 1

	-- ── Remote/network plugins (replaced by nvim-tree, oil, etc.) ────
	g.loaded_netrw = 1
	g.loaded_netrwPlugin = 1
	g.loaded_netrwSettings = 1
	g.loaded_netrwFileHandlers = 1
	g.loaded_getscript = 1
	g.loaded_getscriptPlugin = 1

	-- ── Unused utility plugins ───────────────────────────────────────
	g.loaded_vimball = 1
	g.loaded_vimballPlugin = 1
	g.loaded_2html_plugin = 1
	g.loaded_logiPat = 1
	g.loaded_rrhelper = 1
	g.loaded_tohtml = 1
	g.loaded_tutor = 1

	-- ── Match plugins (replaced by nvim-treesitter) ──────────────────
	g.loaded_matchit = 1
	g.loaded_matchparen = 1

	-- ── Language providers (unused — saves ~5-10ms each) ─────────────
	g.loaded_python3_provider = 0
	g.loaded_ruby_provider = 0
	g.loaded_perl_provider = 0
	g.loaded_node_provider = 0
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 3 — PERFORMANCE: CACHE & FAST PATHS
--
-- Cache frequently used functions to avoid repeated table lookups.
-- In hot paths, local references are ~30% faster than global lookups.
-- ═══════════════════════════════════════════════════════════════════════════

--- Libuv binding (vim.uv on 0.10+, vim.loop on older)
local uv = vim.uv or vim.loop

---@type fun(what: string): string Cached reference to vim.fn.stdpath
local stdpath = vim.fn.stdpath

---@type string Absolute path to the Neovim configuration directory
local config_dir = stdpath("config") --[[@as string]]

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 4 — LOAD VERSION
--
-- Single source of truth: lua/core/version.lua
-- Uses dofile() for zero-overhead loading before require() is warm.
-- No dependency on vim.* — version.lua is pure Lua data + functions.
-- ═══════════════════════════════════════════════════════════════════════════

---@type string SemVer configuration version (fallback: "0.0.0")
local config_version = "0.0.0"

do
	local version_path = config_dir .. "/lua/core/version.lua"

	if uv.fs_stat(version_path) then
		-- version.lua uses vim.* only in show() and command registration.
		-- At this stage vim.api is available, so dofile() is safe.
		local ok, version_mod = pcall(dofile, version_path)
		if ok and type(version_mod) == "table" and version_mod.string then
			local sok, ver = pcall(version_mod.string, version_mod)
			if sok and type(ver) == "string" then config_version = ver end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 5 — GLOBAL NAMESPACE
--
-- Minimal global namespace populated lazily by core modules.
-- Version comes from core/version.lua (single source of truth).
-- ═══════════════════════════════════════════════════════════════════════════

---@class NvimConfig
---@field version string  Configuration version (from core/version.lua)
---@field settings table  Merged settings (populated by core.settings:load)
---@field platform table  Platform information (populated by core.platform:detect)
---@field state NvimConfigState Runtime state flags
_G.NvimConfig = {
	version = config_version,
	settings = {},
	platform = {},
	state = {
		active_user = "default",
		plugins_loaded = false,
		bootstrap_done = false,
		secrets_loaded = false,
	},
}

---@class NvimConfigState
---@field active_user string   Current active user namespace name
---@field plugins_loaded boolean Whether lazy.nvim has finished loading plugins
---@field bootstrap_done boolean Whether core bootstrap has completed
---@field secrets_loaded boolean Whether .env secrets have been loaded

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 6 — SECRETS (TWO-PHASE LOADING)
--
-- Secrets are loaded in two phases to balance correctness and speed:
--
--   Phase 6a (sync, immediate): Load ~/.config/nvim/.env
--     → Required because plugins check vim.env.* during their setup()
--     → Must happen before require("core") triggers lazy.nvim
--
--   Phase 6b (async, deferred): Load project .env + register commands
--     → User commands (:AIStatus, :SecretsReload) are non-critical
--     → Project .env may override global keys per-project
--     → Deferring saves ~2-3ms on the critical startup path
-- ═══════════════════════════════════════════════════════════════════════════

do
	local env_path = config_dir .. "/.env"

	if uv.fs_stat(env_path) then
		-- ── Phase 6a: Synchronous load of global secrets ─────────────
		-- Plugins need API keys available during their setup() call
		local secrets_ok, secrets = pcall(require, "core.secrets")
		if secrets_ok then
			secrets.load_dotenv(env_path, { silent = true })
			_G.NvimConfig.state.secrets_loaded = true

			-- ── Phase 6b: Deferred project .env + commands ───────────
			vim.schedule(function()
				secrets.load_dotenv(".env", { silent = true })
				secrets.setup_commands()
			end)
		end
	else
		-- ── No .env file — still register commands for discoverability
		vim.schedule(function()
			local ok, secrets = pcall(require, "core.secrets")
			if ok then
				secrets.load_dotenv(".env", { silent = true })
				secrets.setup_commands()
			end
		end)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 7 — BOOTSTRAP CORE
--
-- Loads core/init.lua which orchestrates the remainder of startup:
--   1. Platform detection   → core.platform
--   2. Settings loading     → core.settings (global + user merge)
--   3. Neovim options       → core.options
--   4. Lazy.nvim bootstrap  → config.lazy
--   5. Plugin loading       → plugins/**/*.lua
--   6. User keymaps         → users/<active_user>/keymaps.lua
--   7. Colorscheme          → config.colorscheme_manager
--   8. User commands        → config.settings_manager
--
-- After this call, _G.NvimConfig.state.bootstrap_done = true.
-- ═══════════════════════════════════════════════════════════════════════════

require("core")
