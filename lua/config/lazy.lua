---@file lua/config/lazy.lua
---@description Lazy — lazy.nvim bootstrap, plugin spec aggregation and initialization
---@module "config.lazy"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings singleton (protocol, performance, UI options)
---@see core.icons Centralized icon definitions (UI, misc, kinds, git)
---@see core.logger Structured logging (Logger:for_module)
---@see config.plugin_manager Plugin spec collector (PluginManager:collect_specs)
---@see config.lazyvim_shim LazyVim compatibility layer (initialized before lazy.setup)
---@see core.bootstrap Bootstrap calls this module after core initialization
---@see https://github.com/folke/lazy.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  config/lazy.lua — lazy.nvim bootstrap and initialization                ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────┐     ║
--- ║  │  Startup pipeline (executed once, top-level):                   │     ║
--- ║  │                                                                 │     ║
--- ║  │  Step 1 — Bootstrap lazy.nvim                                   │     ║
--- ║  │  ┌───────────────────────────────────────────────────────────┐  │     ║
--- ║  │  │  • Check if lazy.nvim exists at stdpath("data")/lazy/     │  │     ║
--- ║  │  │  • If missing: git clone (--filter=blob:none, --branch=   │  │     ║
--- ║  │  │    stable) using HTTPS or SSH per settings                │  │     ║
--- ║  │  │  • On clone failure: display error and exit(1)            │  │     ║
--- ║  │  │  • Prepend lazypath to vim.opt.rtp                        │  │     ║
--- ║  │  └───────────────────────────────────────────────────────────┘  │     ║
--- ║  │                                                                 │     ║
--- ║  │  Step 2 — Collect plugin specs                                  │     ║
--- ║  │  ┌───────────────────────────────────────────────────────────┐  │     ║
--- ║  │  │  • plugin_manager:collect_specs() aggregates all specs    │  │     ║
--- ║  │  │    from plugins/, langs/, users/<user>/plugins/           │  │     ║
--- ║  │  │  • Returns a flat array of lazy.PluginSpec tables         │  │     ║
--- ║  │  └───────────────────────────────────────────────────────────┘  │     ║
--- ║  │                                                                 │     ║
--- ║  │  Step 3 — Initialize LazyVim shim                               │     ║
--- ║  │  ┌───────────────────────────────────────────────────────────┐  │     ║
--- ║  │  │  • lazyvim_shim.setup() must run BEFORE lazy.setup()      │  │     ║
--- ║  │  │  • Populates global LazyVim table + package.preload       │  │     ║
--- ║  │  │    entries for LazyVim extras compatibility               │  │     ║
--- ║  │  └───────────────────────────────────────────────────────────┘  │     ║
--- ║  │                                                                 │     ║
--- ║  │  Step 4 — Call lazy.setup(specs, opts)                          │     ║
--- ║  │  ┌───────────────────────────────────────────────────────────┐  │     ║
--- ║  │  │  • defaults: lazy-load by default, no version pinning     │  │     ║
--- ║  │  │  • git: protocol-aware config (HTTPS/SSH), concurrency    │  │     ║
--- ║  │  │  • install: colorscheme from settings + "habamax" fallback│  │     ║
--- ║  │  │  • checker: daily update check (silent)                   │  │     ║
--- ║  │  │  • change_detection: auto-reload (silent)                 │  │     ║
--- ║  │  │  • ui: bordered window, custom icons from core/icons      │  │     ║
--- ║  │  │  • performance: bytecode cache, packpath reset, rtp reset │  │     ║
--- ║  │  │    disabled built-in plugins (gzip, netrw, tar, zip…)     │  │     ║
--- ║  │  │  • concurrency: capped at 8 to prevent fd exhaustion      │  │     ║
--- ║  │  └───────────────────────────────────────────────────────────┘  │     ║
--- ║  └─────────────────────────────────────────────────────────────────┘     ║
--- ║                                                                          ║
--- ║  Git protocol support:                                                   ║
--- ║  ├─ use_ssh()          Reads performance.git_protocol from settings      ║
--- ║  ├─ github_prefix()    Returns HTTPS or SSH prefix                       ║
--- ║  ├─ convert_url()      HTTPS → SSH conversion for arbitrary URLs         ║
--- ║  └─ build_git_config() Generates lazy.nvim git opts per protocol         ║
--- ║                                                                          ║
--- ║  Design decisions:                                                       ║
--- ║  ├─ Top-level execution (no setup() method) — runs on require()          ║
--- ║  ├─ SSH support for corporate firewalls / GitHub Enterprise              ║
--- ║  ├─ Shallow clone (--filter=blob:none) for minimal bootstrap time        ║
--- ║  ├─ Stable branch only — no bleeding edge during bootstrap               ║
--- ║  ├─ Fatal error on clone failure (exit 1)                                ║
--- ║  ├─ LazyVim shim initialized before lazy.setup()                         ║
--- ║  ├─ Concurrency capped at 8 (HTTPS) / 4 (SSH) to prevent                 ║
--- ║  │  macOS fd exhaustion ("Failed to spawn process git")                  ║
--- ║  ├─ Icons from core/icons.lua (single source of truth)                   ║
--- ║  └─ Built-in plugins disabled at the rtp level for fastest startup       ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════
local Logger = require("core.logger")
local log = Logger:for_module("config.lazy")
local settings = require("core.settings")
---@type Icons
local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════════

--- Maximum number of concurrent git operations.
--- Prevents macOS file descriptor exhaustion when updating 100+ plugins.
--- SSH uses a lower value because each connection is heavier.
---@type table<string, integer>
---@private
local GIT_CONCURRENCY = {
	https = 8,
	ssh = 4,
}

--- Built-in Vim plugins to disable for faster startup.
--- These are removed from the runtime path by lazy.nvim.
---@type string[]
---@private
local DISABLED_BUILTINS = {
	"gzip",
	"matchit",
	"matchparen",
	"netrwPlugin",
	"tarPlugin",
	"tohtml",
	"tutor",
	"zipPlugin",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS: Icons
-- ═══════════════════════════════════════════════════════════════════════════

--- Build the icon map for lazy.nvim's UI from the centralized icons module.
--- Maps lazy.nvim's icon slots to Nerd Font glyphs from `core.icons`.
---@return table<string, string|table> icons_map Icon mapping for `lazy.setup({ ui = { icons } })`
---@private
local function build_ui_icons()
	return {
		cmd = icons.ui.Terminal,
		config = icons.ui.Gear,
		event = icons.ui.Fire,
		ft = icons.ui.File,
		import = icons.documents.Import,
		init = icons.ui.Rocket,
		keys = icons.kinds.Key,
		lazy = icons.misc.Lazy,
		loaded = icons.ui.Check,
		not_loaded = icons.misc.Ghost,
		plugin = icons.ui.Package,
		require = icons.ui.Search,
		runtime = icons.misc.Neovim,
		source = icons.ui.Code,
		start = icons.ui.Triangle,
		task = icons.ui.Check,
		list = {
			icons.ui.BigCircle,
			icons.ui.BigUnfilledCircle,
			icons.ui.Square,
			icons.arrows.ChevronRight_alt,
		},
	}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS: Git Protocol
--
-- Supports both HTTPS and SSH protocols for git operations.
-- SSH is useful behind corporate firewalls or with GitHub Enterprise.
-- Protocol determined by `performance.git_protocol` setting (default: "https").
-- ═══════════════════════════════════════════════════════════════════════════

--- Check if SSH protocol is configured for git operations.
---@return boolean is_ssh `true` if git protocol is set to `"ssh"`
---@private
local function use_ssh()
	return settings:get("performance.git_protocol", "https") == "ssh"
end

--- Get the GitHub URL prefix for the configured protocol.
---@return string prefix `"https://github.com/"` or `"git@github.com:"`
---@private
local function github_prefix()
	return use_ssh() and "git@github.com:" or "https://github.com/"
end

--- Convert a GitHub HTTPS URL to SSH format if SSH protocol is configured.
--- No-op when HTTPS protocol is active.
---@param url string Original GitHub HTTPS URL
---@return string url Converted URL (or original if HTTPS mode)
---@private
local function convert_url(url)
	if not use_ssh() then return url end
	return url:gsub("https://github%.com/", "git@github.com:")
end

--- Build the lazy.nvim git configuration table for the active protocol.
--- Includes concurrency limits to prevent fd exhaustion on macOS.
---@return table git_config Configuration table for `lazy.setup({ git = ... })`
---@private
local function build_git_config()
	local protocol = use_ssh() and "ssh" or "https"

	local config = {
		url_format = use_ssh() and "git@github.com:%s.git" or "https://github.com/%s.git",
		timeout = use_ssh() and 300 or 120,
		concurrency = GIT_CONCURRENCY[protocol],
	}

	-- SSH-specific: throttle to prevent concurrent clone storms
	if use_ssh() then
		config.throttle = {
			enabled = true,
			rate = 2,
			duration = 5 * 1000, -- 5 seconds
		}
	end

	return config
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 1 — BOOTSTRAP LAZY.NVIM
--
-- Checks if lazy.nvim is installed. If missing, clones it from GitHub
-- using the configured protocol with shallow clone and stable branch.
-- On clone failure, displays an error and exits(1).
-- ═══════════════════════════════════════════════════════════════════════════

---@type string Absolute path to the lazy.nvim installation directory
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local repo_url = github_prefix() .. "folke/lazy.nvim.git"
	log:info("Cloning lazy.nvim via %s...", use_ssh() and "SSH" or "HTTPS")

	local out = vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"--branch=stable",
		repo_url,
		lazypath,
	})

	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
			{ "\nRepo URL: " .. repo_url .. "\n", "WarningMsg" },
			{ "\nPress any key to exit...", "MoreMsg" },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end

	log:info("lazy.nvim cloned successfully via %s", use_ssh() and "SSH" or "HTTPS")
end

---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 2 — COLLECT PLUGIN SPECS
-- ═══════════════════════════════════════════════════════════════════════════

local plugin_manager = require("config.plugin_manager")
local specs = plugin_manager:collect_specs()

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 3 — INITIALIZE LAZYVIM SHIM
--
-- Must run BEFORE lazy.setup() so that LazyVim extras can reference
-- the global LazyVim table during spec evaluation.
-- ═══════════════════════════════════════════════════════════════════════════

require("config.lazyvim_shim").setup()

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 4 — CONFIGURE AND START LAZY.NVIM
-- ═══════════════════════════════════════════════════════════════════════════

require("lazy").setup(specs, {
	-- ── Defaults ─────────────────────────────────────────────────
	defaults = {
		lazy = settings:get("performance.lazy_load", true),
		version = false,
	},

	-- ── Git (protocol-aware, with concurrency cap) ───────────────
	git = build_git_config(),

	-- ── Concurrency (global cap for all operations) ──────────────
	-- Prevents "Failed to spawn process git" on macOS by limiting
	-- the number of simultaneous git operations during :Lazy update.
	concurrency = GIT_CONCURRENCY[use_ssh() and "ssh" or "https"],

	-- ── Install ──────────────────────────────────────────────────
	install = {
		colorscheme = {
			settings:get("ui.colorscheme", "habamax"),
			"habamax",
		},
		missing = true,
	},

	-- ── Plugin Update Checker ────────────────────────────────────
	checker = {
		enabled = true,
		notify = false,
		frequency = 86400, -- 24 hours
	},

	-- ── Change Detection ─────────────────────────────────────────
	change_detection = {
		enabled = true,
		notify = false,
	},

	-- ── UI ───────────────────────────────────────────────────────
	ui = {
		size = { width = 0.85, height = 0.85 },
		wrap = true,
		border = settings:get("ui.float_border", "rounded"),
		backdrop = 60,
		title = " " .. icons.misc.Lazy .. "Lazy ",
		icons = build_ui_icons(),
	},

	-- ── Performance ──────────────────────────────────────────────
	performance = {
		cache = {
			enabled = settings:get("performance.cache", true),
			path = vim.fn.stdpath("cache") .. "/lazy/cache",
		},
		reset_packpath = settings:get("performance.reset_packpath", true),
		rtp = {
			reset = settings:get("performance.reset", true),
			disabled_plugins = DISABLED_BUILTINS,
		},
	},

	-- ── Profiling ────────────────────────────────────────────────
	profiling = {
		loader = false,
		require = false,
	},
})

log:info(
	"lazy.nvim setup complete — %d plugins configured (git: %s, concurrency: %d)",
	#specs,
	use_ssh() and "SSH" or "HTTPS",
	GIT_CONCURRENCY[use_ssh() and "ssh" or "https"]
)
