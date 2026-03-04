---@file lua/config/init.lua
---@description Config — configuration layer entry point and orchestration
---@module "config"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.bootstrap Core bootstrap (loads before this module)
---@see core.logger Structured logging (Logger:for_module)
---@see core.settings Settings singleton (active_user, version)
---@see core.platform Platform singleton (OS, summary)
---@see core.icons Centralized icon definitions
---@see config.lazy lazy.nvim bootstrap and plugin initialization
---@see config.settings_manager Settings UI commands registration
---@see config.commands Advanced NvimEnterprise command registration
---@see users User module loader (user-specific keymaps, plugins, settings)
---@see users.user_manager User lifecycle management (ensure_default)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  config/init.lua — Configuration layer entry point                       ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Orchestration pipeline (executed once on require("config")):    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Step 1 — Ensure default user namespace                          │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • pcall(require, "users.user_manager")                    │  │    ║
--- ║  │  │  • user_manager:ensure_default() creates users/default/    │  │    ║
--- ║  │  │    directory structure if missing                          │  │    ║
--- ║  │  │  • Graceful degradation: warns on failure, continues       │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Step 2 — Bootstrap lazy.nvim and load all plugins               │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • require("config.lazy") runs the full lazy.nvim pipeline │  │    ║
--- ║  │  │  • Clones lazy.nvim if missing, collects specs, calls      │  │    ║
--- ║  │  │    lazy.setup() — see config.lazy for details              │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Step 3 — Register settings management commands                  │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • pcall(require, "config.settings_manager")               │  │    ║
--- ║  │  │  • settings_manager:register_commands() creates :NvimUser, │  │    ║
--- ║  │  │    :NvimColorscheme, :NvimSettings and similar commands    │  │    ║
--- ║  │  │  • Error-level log on failure (commands are important)     │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Step 4 — Register advanced NvimEnterprise commands              │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • pcall(require, "config.commands")                       │  │    ║
--- ║  │  │  • commands.setup() creates :NvimInfo, :NvimHealth,        │  │    ║
--- ║  │  │    :NvimExtras, :NvimReload and similar commands           │  │    ║
--- ║  │  │  • Warn-level log on failure (non-critical)                │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Step 5 — Load active user's customizations                      │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • pcall(require, "users")                                 │  │    ║
--- ║  │  │  • users.setup() loads the active user's keymaps,          │  │    ║
--- ║  │  │    plugins, and settings overrides                         │  │    ║
--- ║  │  │  • Warn-level log on failure (falls back to defaults)      │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Step 6 — Startup notification (deferred to VeryLazy)            │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • Autocommand on User:VeryLazy (once)                     │  │    ║
--- ║  │  │  • Logs: version, active user, OS, platform summary        │  │    ║
--- ║  │  │  • Sets vim.g.nvim_enterprise_ready = true                 │  │    ║
--- ║  │  │  • Signals to other modules that startup is complete       │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Error handling strategy:                                                ║
--- ║  ├─ All module loads wrapped in pcall() for graceful degradation         ║
--- ║  ├─ user_manager failure  → warn (user can still use defaults)           ║
--- ║  ├─ config.lazy failure   → NOT wrapped (fatal — no plugin manager)      ║
--- ║  ├─ settings_manager fail → error (commands are important for UX)        ║
--- ║  ├─ config.commands fail  → warn (non-critical utility commands)         ║
--- ║  └─ users module failure  → warn (falls back to default user)            ║
--- ║                                                                          ║
--- ║  Design decisions:                                                       ║
--- ║  ├─ Top-level execution (no setup() method) — this module runs its       ║
--- ║  │  entire pipeline on require("config"), following the same pattern     ║
--- ║  │  as config.lazy                                                       ║
--- ║  ├─ config.lazy is NOT pcall-wrapped because lazy.nvim is a hard         ║
--- ║  │  dependency — if it fails, nothing else can work                      ║
--- ║  ├─ Startup notification deferred to VeryLazy to avoid blocking          ║
--- ║  │  the UI during initial render                                         ║
--- ║  ├─ vim.g.nvim_enterprise_ready serves as a global readiness flag        ║
--- ║  │  for external integrations and health checks                          ║
--- ║  └─ checkhealth bridge registered implicitly via lua/nvimenterprise/     ║
--- ║     health.lua (Neovim auto-discovers it)                                ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Each step is independent — failure in step N does not block step N+1  ║
--- ║  • Startup notification runs after VeryLazy (no startup time impact)     ║
--- ║  • Module cached by require() — pipeline runs exactly once               ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local Logger = require("core.logger")
local log = Logger:for_module("config")

-- ═══════════════════════════════════════════════════════════════════════
-- STEP 1 — ENSURE DEFAULT USER NAMESPACE
--
-- The default user directory (users/default/) must exist before any
-- user-related operations. user_manager:ensure_default() creates
-- the directory structure and skeleton files if missing.
-- ═══════════════════════════════════════════════════════════════════════

local um_ok, user_manager = pcall(require, "users.user_manager")
if um_ok then
	user_manager:ensure_default()
else
	log:warn("Could not load user_manager: %s", tostring(user_manager))
end

-- ═══════════════════════════════════════════════════════════════════════
-- STEP 2 — BOOTSTRAP LAZY.NVIM AND LOAD ALL PLUGINS
--
-- This is the only step NOT wrapped in pcall(). lazy.nvim is a hard
-- dependency — if it fails to bootstrap or initialize, the entire
-- configuration is non-functional and the error should propagate
-- immediately for visibility.
-- ═══════════════════════════════════════════════════════════════════════

require("config.lazy")

-- ═══════════════════════════════════════════════════════════════════════
-- STEP 3 — REGISTER SETTINGS MANAGEMENT COMMANDS
--
-- Creates user-facing commands for managing settings, colorschemes,
-- and user profiles. Logged at error level on failure because these
-- commands are important for the configuration UX.
-- ═══════════════════════════════════════════════════════════════════════

local sm_ok, settings_manager = pcall(require, "config.settings_manager")
if sm_ok then
	settings_manager:register_commands()
else
	log:error("Failed to load settings_manager: %s", tostring(settings_manager))
end

-- ═══════════════════════════════════════════════════════════════════════
-- STEP 4 — REGISTER ADVANCED NVIMENTERPRISE COMMANDS
--
-- Creates utility commands (:NvimInfo, :NvimHealth, :NvimExtras,
-- :NvimReload, etc.). Logged at warn level on failure because
-- these are convenience commands, not critical functionality.
-- ═══════════════════════════════════════════════════════════════════════

local cmd_ok, commands = pcall(require, "config.commands")
if cmd_ok then
	commands.setup()
else
	log:warn("Failed to load config.commands: %s", tostring(commands))
end

-- ═══════════════════════════════════════════════════════════════════════
-- STEP 5 — LOAD ACTIVE USER'S CUSTOMIZATIONS
--
-- Loads the active user's keymaps, plugin overrides, and settings.
-- On failure, the configuration falls back to the default user
-- profile which is guaranteed to exist after Step 1.
-- ═══════════════════════════════════════════════════════════════════════

local users_ok, users = pcall(require, "users")
if users_ok then
	users.setup()
else
	log:warn("Could not load users module: %s", tostring(users))
end

-- ═══════════════════════════════════════════════════════════════════════
-- STEP 6 — STARTUP NOTIFICATION (DEFERRED)
--
-- Deferred to the User:VeryLazy event to avoid blocking the initial
-- UI render. Logs a summary of the active configuration and sets
-- the global readiness flag for external integrations.
-- ═══════════════════════════════════════════════════════════════════════

vim.api.nvim_create_autocmd("User", {
	pattern = "VeryLazy",
	once = true,
	callback = function()
		local settings = require("core.settings")
		local platform = require("core.platform")

		log:info(
			"NvimEnterprise v%s ready — User: %s — OS: %s — %s",
			_G.NvimConfig.version,
			settings:get("active_user", "default"),
			platform.os,
			platform:summary()
		)

		-- Global readiness flag for external integrations and health checks
		vim.g.nvim_enterprise_ready = true
	end,
})

log:info("Config layer initialized")
