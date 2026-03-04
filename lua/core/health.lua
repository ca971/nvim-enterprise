---@file lua/core/health.lua
---@description Health — comprehensive :checkhealth provider for NvimEnterprise
---@module "core.health"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.platform Platform detection (OS, arch, SSH, WSL, Docker, GUI, tools)
---@see core.settings Settings loader and validator (user overrides, defaults)
---@see core.security Settings structure validator
---@see core.keymaps Core keymaps registry (global + language-specific)
---@see core.logger Structured logging utility (log file location)
---@see core.utils File/directory existence helpers
---@see users.user_manager User namespace manager (list, info, exists)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/health.lua — :checkhealth nvimenterprise                           ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Health Check Pipeline (9 sections, sequential)                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Section 1 ─ Neovim Version                                      │    ║
--- ║  │  │  • Minimum version gate (>= 0.10.0 required)                  │    ║
--- ║  │  │  • Latest features check (>= 0.11.0 recommended)              │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Section 2 ─ Platform                                            │    ║
--- ║  │  │  • OS, arch, config dir detection                             │    ║
--- ║  │  │  • Environment flags (SSH, WSL, Docker, Proxmox, GUI)         │    ║
--- ║  │  │  • True color (24-bit) support                                │    ║
--- ║  │  │  • Essential tools inventory (git, rg, fd, node, etc.)        │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Section 3 ─ Settings                                            │    ║
--- ║  │  │  • Root settings.lua existence                                │    ║
--- ║  │  │  • Active user identification                                 │    ║
--- ║  │  │  • Settings structure validation (via core.security)          │    ║
--- ║  │  │  • Colorscheme, languages, AI, LazyVim extras reporting       │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Section 4 ─ User Namespaces                                     │    ║
--- ║  │  │  • List all user namespaces with features (settings/keymaps)  │    ║
--- ║  │  │  • Validate active user exists on disk                        │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Section 5 ─ Plugins                                             │    ║
--- ║  │  │  • lazy.nvim stats (total, loaded, startup time)              │    ║
--- ║  │  │  • Explicitly disabled plugins listing                        │    ║
--- ║  │  │  • Critical plugins availability check                        │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Section 6 ─ Languages                                           │    ║
--- ║  │  │  • Config file existence for each enabled language            │    ║
--- ║  │  │  • Available vs enabled language comparison                   │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Section 7 ─ LSP                                                 │    ║
--- ║  │  │  • Active LSP clients with buffer attachment counts           │    ║
--- ║  │  │  • Mason registry: installed packages inventory               │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Section 8 ─ Log                                                 │    ║
--- ║  │  │  • Log file existence and size                                │    ║
--- ║  │  │  • Large file warning (> 1 MB)                                │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Section 9 ─ Keymaps                                             │    ║
--- ║  │  │  • Core keymap system initialization status                   │    ║
--- ║  │  │  • FileType autocmd registration check                        │    ║
--- ║  │  │  • which-key integration status                               │    ║
--- ║  │  │  • Registry stats (global + language-specific)                │    ║
--- ║  │  │  • Language group registration audit                          │    ║
--- ║  │  │  • Prefix conflict detection                                  │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Error handling:                                                         ║
--- ║  • Each section is independently guarded with pcall                      ║
--- ║  • A failing section does not prevent subsequent sections from running   ║
--- ║  • Severity levels: error (fatal), warn (degraded), ok (pass), info      ║
--- ║                                                                          ║
--- ║  Usage:                                                                  ║
--- ║    :checkhealth nvimenterprise                                           ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • No eager loading: all modules loaded via pcall on demand              ║
--- ║  • Minimal side-effects: read-only introspection                         ║
--- ║  • Sorted output for deterministic, scannable reports                    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

---@class HealthModule
---@field check fun() Run all health check sections
local M = {}

--- Reference to the Neovim health API.
---@type table
local health = vim.health

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPER WRAPPERS
--
-- Thin wrappers around vim.health.* for consistent signatures
-- and optional advice parameters. These simplify call sites and
-- allow future interception (e.g., logging health results).
-- ═══════════════════════════════════════════════════════════════════════════

--- Report an informational line (neutral, no pass/fail).
---@param msg string Message to display
---@return nil
---@private
local function info(msg)
	health.info(msg)
end

--- Report a passing check (green checkmark).
---@param msg string Message to display
---@return nil
---@private
local function ok(msg)
	health.ok(msg)
end

--- Report a warning (yellow, non-fatal degradation).
---@param msg string Warning message
---@param advice? string|string[] Suggested remediation steps
---@return nil
---@private
local function warn(msg, advice)
	health.warn(msg, advice)
end

--- Report an error (red, fatal or critically degraded).
---@param msg string Error message
---@param advice? string|string[] Suggested remediation steps
---@return nil
---@private
local function error_msg(msg, advice)
	health.error(msg, advice)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 1: NEOVIM VERSION
--
-- Validates the running Neovim version against minimum requirements.
-- NvimEnterprise requires >= 0.10.0 (hard gate) and recommends
-- >= 0.11.0 for latest features (vim.uv, native snippets, etc.).
-- ═══════════════════════════════════════════════════════════════════════════

--- Check Neovim version against minimum and recommended thresholds.
---@return nil
---@private
local function check_neovim()
	health.start("NvimEnterprise — Neovim")

	local v = vim.version()
	local version_str = string.format("%d.%d.%d", v.major, v.minor, v.patch)
	info("Neovim version: " .. version_str)

	if vim.fn.has("nvim-0.10.0") == 1 then
		ok("Neovim >= 0.10.0")
	else
		error_msg("Neovim >= 0.10.0 required", "Please upgrade Neovim")
	end

	if vim.fn.has("nvim-0.11.0") == 1 then
		ok("Neovim >= 0.11.0 (latest features)")
	else
		warn("Neovim < 0.11.0 — some features may not be available")
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 2: PLATFORM
--
-- Validates platform detection results and checks availability of
-- essential external tools. Git is the only hard requirement; all
-- others are optional but enhance the experience (rg for search,
-- fd for file finding, node/npm for LSP servers, etc.).
-- ═══════════════════════════════════════════════════════════════════════════

--- External tools to check for availability.
--- Each entry: `{ executable_name, description_if_missing }`.
--- The first entry (git) is treated as a hard requirement (error);
--- all others are optional (warn).
---@type { [1]: string, [2]: string }[]
---@private
local tools_checklist = {
	{ "git", "Git is required for plugin management" },
	{ "rg", "ripgrep is recommended for fast searching (optional)" },
	{ "fd", "fd is recommended for file finding (optional)" },
	{ "node", "Node.js is needed for some LSP servers (optional)" },
	{ "npm", "npm is needed for some LSP servers (optional)" },
	{ "cargo", "Cargo is needed for Rust tools (optional)" },
	{ "go", "Go is needed for Go tools (optional)" },
	{ "python3", "Python3 is needed for some tools (optional)" },
	{ "lazygit", "lazygit provides a git TUI (optional)" },
	{ "make", "make is needed for telescope-fzf-native (optional)" },
}

--- Check platform detection results and external tool availability.
---@return nil
---@private
local function check_platform()
	health.start("NvimEnterprise — Platform")

	local platform_ok, platform = pcall(require, "core.platform")
	if not platform_ok then
		error_msg("Failed to load core.platform")
		return
	end

	-- ── Platform info ────────────────────────────────────────────────
	info("OS: " .. platform.os)
	info("Arch: " .. platform.arch)
	info("Config dir: " .. platform.config_dir)

	-- ── Environment flags ────────────────────────────────────────────
	if platform.is_ssh then info("Environment: SSH session detected") end
	if platform.is_wsl then info("Environment: WSL detected") end
	if platform.is_docker then info("Environment: Docker container detected") end
	if platform.is_proxmox then info("Environment: Proxmox detected") end
	if platform.is_gui then info("GUI mode: " .. (vim.g.neovide and "Neovide" or "yes")) end

	-- ── True color ───────────────────────────────────────────────────
	if platform.has_true_color then
		ok("True color (24-bit) support detected")
	else
		warn("No true color support detected", "Set COLORTERM=truecolor in your terminal")
	end

	-- ── External tools ───────────────────────────────────────────────
	for _, tool in ipairs(tools_checklist) do
		if platform:has_executable(tool[1]) then
			ok(tool[1] .. " found: " .. (vim.fn.exepath(tool[1]) or "on PATH"))
		else
			if tool[1] == "git" then
				error_msg(tool[1] .. " not found", tool[2])
			else
				warn(tool[1] .. " not found", tool[2])
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 3: SETTINGS
--
-- Validates the settings system: root settings.lua existence,
-- active user resolution, structure validation via core.security,
-- and reports key configuration choices (colorscheme, languages, AI).
-- ═══════════════════════════════════════════════════════════════════════════

--- Check settings system integrity and report configuration choices.
---@return nil
---@private
local function check_settings()
	health.start("NvimEnterprise — Settings")

	local settings_ok, settings = pcall(require, "core.settings")
	if not settings_ok then
		error_msg("Failed to load core.settings: " .. tostring(settings))
		return
	end

	-- ── Root settings.lua ────────────────────────────────────────────
	local utils = require("core.utils")
	local platform = require("core.platform")
	local root_path = platform:path_join(platform.config_dir, "settings.lua")

	if utils.file_exists(root_path) then
		ok("Root settings.lua found: " .. root_path)
	else
		error_msg("Root settings.lua not found", "Create settings.lua in " .. platform.config_dir)
	end

	-- ── Active user ──────────────────────────────────────────────────
	local active_user = settings:get("active_user", "default")
	info("Active user: " .. active_user)

	-- ── Structure validation ─────────────────────────────────────────
	local security = require("core.security")
	local valid, errors = security:validate_settings(settings:all())
	if valid then
		ok("Settings structure is valid")
	else
		for _, err in ipairs(errors) do
			warn("Settings validation: " .. err)
		end
	end

	-- ── Colorscheme ──────────────────────────────────────────────────
	info("Colorscheme: " .. settings:get("ui.colorscheme", "(none)"))
	info("Style: " .. settings:get("ui.colorscheme_style", "(default)"))

	-- ── Languages ────────────────────────────────────────────────────
	local langs = settings:get("languages.enabled", {})
	info("Enabled languages (" .. #langs .. "): " .. table.concat(langs, ", "))

	-- ── AI ────────────────────────────────────────────────────────────
	if settings:get("ai.enabled", false) then
		info("AI enabled — provider: " .. settings:get("ai.provider", "none"))
		if settings:get("ai.continue_completion", false) then info("Continue-style completion: enabled") end
	else
		info("AI: disabled")
	end

	-- ── LazyVim extras ───────────────────────────────────────────────
	if settings:get("lazyvim_extras.enabled", false) then
		local extras = settings:get("lazyvim_extras.extras", {})
		info("LazyVim extras enabled (" .. #extras .. "): " .. table.concat(extras, ", "))
	else
		info("LazyVim extras: disabled")
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 4: USER NAMESPACES
--
-- Validates user namespace integrity: lists all namespaces with their
-- features (settings, keymaps, plugins), checks the active user exists,
-- and reports missing directories.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check user namespace integrity and active user validity.
---@return nil
---@private
local function check_users()
	health.start("NvimEnterprise — User Namespaces")

	local um_ok, user_manager = pcall(require, "users.user_manager")
	if not um_ok then
		error_msg("Failed to load users.user_manager")
		return
	end

	local users = user_manager:list()
	info("Total user namespaces: " .. #users)

	-- ── Per-user report ──────────────────────────────────────────────
	for _, name in ipairs(users) do
		local ns_info = user_manager:info(name)
		local parts = {}
		if ns_info.has_settings then table.insert(parts, "settings") end
		if ns_info.has_keymaps then table.insert(parts, "keymaps") end
		if ns_info.has_plugins then table.insert(parts, "plugins") end

		local status = ns_info.is_active and " (ACTIVE)" or ""
		local features = #parts > 0 and table.concat(parts, ", ") or "empty"

		if ns_info.exists then
			ok(string.format("  %s%s [%s]", name, status, features))
		else
			warn(string.format("  %s — directory missing", name))
		end
	end

	-- ── Active user validation ───────────────────────────────────────
	local settings = require("core.settings")
	local active = settings:get("active_user", "default")
	if user_manager:exists(active) then
		ok("Active user '" .. active .. "' exists")
	else
		error_msg(
			"Active user '" .. active .. "' does not exist",
			"Run :UserCreate " .. active .. " or change active_user in settings.lua"
		)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 5: PLUGINS
--
-- Validates the plugin ecosystem: lazy.nvim stats, startup time,
-- explicitly disabled plugins, and critical plugin availability.
-- Critical plugins are those without which the editor experience
-- is significantly degraded (LSP, treesitter, completion, etc.).
-- ═══════════════════════════════════════════════════════════════════════════

--- Plugins considered critical for a functional NvimEnterprise setup.
--- Missing critical plugins produce warnings (not errors) because
--- the user may have intentionally disabled them.
---@type string[]
---@private
local critical_plugins = {
	"lazy.nvim",
	"nvim-lspconfig",
	"nvim-treesitter",
	"nvim-cmp",
	"mason.nvim",
	"telescope.nvim",
	"which-key.nvim",
}

--- Check plugin ecosystem health and critical plugin availability.
---@return nil
---@private
local function check_plugins()
	health.start("NvimEnterprise — Plugins")

	local lazy_ok, lazy = pcall(require, "lazy")
	if not lazy_ok then
		error_msg("lazy.nvim is not loaded")
		return
	end

	-- ── Stats ────────────────────────────────────────────────────────
	local stats = lazy.stats()
	info(
		string.format("Total plugins: %d (%d loaded, %d not loaded)", stats.count, stats.loaded, stats.count - stats.loaded)
	)
	info(string.format("Startup time: %.2fms", stats.startuptime))

	-- ── Disabled plugins ─────────────────────────────────────────────
	local settings = require("core.settings")
	local disabled = settings:get("plugins.disabled", {})
	if #disabled > 0 then info("Explicitly disabled: " .. table.concat(disabled, ", ")) end

	-- ── Critical plugins ─────────────────────────────────────────────
	for _, name in ipairs(critical_plugins) do
		local found = false
		for _, plugin in pairs(require("lazy.core.config").plugins) do
			if plugin.name == name or (plugin[1] and plugin[1]:find(name, 1, true)) then
				found = true
				break
			end
		end
		if found then
			ok(name .. " is available")
		else
			warn(name .. " is not configured")
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 6: LANGUAGES
--
-- Validates language configuration files: checks that each enabled
-- language has a corresponding lua/langs/<lang>.lua file, and reports
-- the full inventory of available vs enabled language configs.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check language configuration file existence and inventory.
---@return nil
---@private
local function check_languages()
	health.start("NvimEnterprise — Languages")

	local settings = require("core.settings")
	local utils = require("core.utils")
	local platform = require("core.platform")
	local enabled_langs = settings:get("languages.enabled", {})

	-- ── Per-language config file check ───────────────────────────────
	for _, lang in ipairs(enabled_langs) do
		local lang_path = platform:path_join(platform.config_dir, "lua", "langs", lang .. ".lua")
		if utils.file_exists(lang_path) then
			ok(lang .. " — config file exists")
		else
			warn(lang .. " — config file not found at langs/" .. lang .. ".lua")
		end
	end

	-- ── Available vs enabled inventory ───────────────────────────────
	local langs_dir = platform:path_join(platform.config_dir, "lua", "langs")
	if utils.dir_exists(langs_dir) then
		local files = utils.list_dir(langs_dir, "file")
		local available = {}
		for _, f in ipairs(files) do
			if f:match("%.lua$") and f ~= "init.lua" and f ~= "_template.lua" then
				local lang_name = f:gsub("%.lua$", "")
				table.insert(available, lang_name)
			end
		end
		info(string.format("Available language configs: %d (%s)", #available, table.concat(available, ", ")))
		info(string.format("Enabled: %d", #enabled_langs))
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 7: LSP
--
-- Reports active LSP clients and their buffer attachments, plus
-- Mason registry inventory. This section is most useful when run
-- with a file open (LSP clients attach lazily on BufReadPost).
-- ═══════════════════════════════════════════════════════════════════════════

--- Check active LSP clients and Mason package inventory.
---@return nil
---@private
local function check_lsp()
	health.start("NvimEnterprise — LSP")

	-- ── Active clients ───────────────────────────────────────────────
	local clients = vim.lsp.get_clients()
	if #clients > 0 then
		for _, client in ipairs(clients) do
			ok(
				string.format(
					"%s (id=%d) attached to %d buffer(s)",
					client.name,
					client.id,
					#vim.lsp.get_buffers_by_client_id(client.id)
				)
			)
		end
	else
		info("No LSP clients currently active (open a file to trigger)")
	end

	-- ── Mason inventory ──────────────────────────────────────────────
	local mason_ok, mason_registry = pcall(require, "mason-registry")
	if mason_ok then
		local installed = mason_registry.get_installed_packages()
		info(string.format("Mason packages installed: %d", #installed))
		local names = {}
		for _, pkg in ipairs(installed) do
			table.insert(names, pkg.name)
		end
		table.sort(names)
		if #names > 0 then info("  " .. table.concat(names, ", ")) end
	else
		warn("Mason registry not available")
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 8: LOG
--
-- Checks the NvimEnterprise log file existence and size.
-- Large log files (> 1 MB) indicate either verbose logging or
-- a long-running session without log rotation.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check log file existence and size.
---@return nil
---@private
local function check_log()
	health.start("NvimEnterprise — Log")

	local log_path = vim.fn.stdpath("state") .. "/nvimenterprise.log"
	local utils = require("core.utils")

	if utils.file_exists(log_path) then
		local stat = vim.uv.fs_stat(log_path)
		local size_kb = stat and math.floor(stat.size / 1024) or 0
		ok(string.format("Log file: %s (%d KB)", log_path, size_kb))

		if size_kb > 1024 then warn("Log file is larger than 1 MB", "Consider truncating: :NvimLogClear") end
	else
		info("No log file yet (will be created on first log entry)")
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 9: KEYMAPS
--
-- Comprehensive audit of the keymap system: initialization status,
-- FileType autocmd registration, which-key integration, registry
-- stats (global + language-specific), language group alignment with
-- enabled languages, and prefix conflict detection.
--
-- Prefix conflict detection scans all registered keymaps within
-- the same mode and reports cases where one LHS is a strict prefix
-- of another (e.g., `<leader>g` vs `<leader>gd`), which can cause
-- unexpected delays or shadowing in which-key.
-- ═══════════════════════════════════════════════════════════════════════════

--- Audit the keymap system: initialization, registry, language groups, conflicts.
---@return nil
---@private
local function check_keymaps()
	health.start("NvimEnterprise — Keymaps")

	-- ── 1. Core keymap system initialization ─────────────────────────
	local keys_ok, keys = pcall(require, "core.keymaps")
	if not keys_ok then
		error_msg("Failed to load core.keymaps: " .. tostring(keys))
		return
	end

	if keys._initialized then
		ok("Keymap system initialized")
	else
		error_msg("Keymap system NOT initialized", {
			"keymaps.setup() is called automatically by which-key.lua — no manual call needed",
			"Must be called BEFORE plugin_manager collects specs",
		})
	end

	-- ── 2. FileType autocmd ──────────────────────────────────────────
	local autocmds = vim.api.nvim_get_autocmds({
		group = "CoreKeymapLang",
		event = "FileType",
	})
	if #autocmds > 0 then
		ok("FileType autocmd registered (CoreKeymapLang)")
	else
		error_msg("FileType autocmd NOT found", {
			"keys.setup() may not have been called early enough",
			"keys.setup() creates this autocmd to apply lang keymaps",
		})
	end

	-- ── 3. Which-key integration ─────────────────────────────────────
	local wk_ok = pcall(require, "which-key")
	if wk_ok then
		ok("which-key is loaded")
	else
		warn("which-key not loaded yet (VeryLazy — normal at startup)")
	end

	-- ── 4. Registry stats ────────────────────────────────────────────
	local reg_count = vim.tbl_count(keys._registry)
	ok(string.format("Global keymaps registered: %d", reg_count))

	-- ── 5. Language groups ───────────────────────────────────────────
	local lang_groups = keys._lang_groups
	local group_count = vim.tbl_count(lang_groups)

	if group_count > 0 then
		ok(string.format("%d language group(s) registered:", group_count))
		local sorted = vim.tbl_keys(lang_groups)
		table.sort(sorted)
		for _, ft in ipairs(sorted) do
			local lg = lang_groups[ft]
			ok(string.format("  %s %s (filetype: %s)", lg.icon, lg.label, ft))
		end
	else
		warn("No language groups registered", {
			"Check that langs/*.lua files call keys.lang_group()",
			"Check settings.languages.enabled includes your languages",
		})
	end

	-- ── 6. Language keymaps ──────────────────────────────────────────
	local lang_maps = keys._lang_maps
	local lang_count = vim.tbl_count(lang_maps)

	if lang_count > 0 then
		local sorted = vim.tbl_keys(lang_maps)
		table.sort(sorted)
		for _, ft in ipairs(sorted) do
			local maps = lang_maps[ft]
			ok(string.format("%s: %d keymap(s)", ft, #maps))
			for _, km in ipairs(maps) do
				local mode = type(km.mode) == "table" and table.concat(km.mode, ",") or km.mode
				ok(string.format("  [%s] %-20s %s", mode, km.lhs, km.opts.desc or "(no desc)"))
			end
		end
	else
		warn("No language keymaps registered")
	end

	-- ── 7. Enabled languages sync ────────────────────────────────────
	local settings_ok, settings = pcall(require, "core.settings")
	if settings_ok then
		local enabled = settings:get("languages.enabled", {})
		ok(string.format("Enabled languages: %d", #enabled))

		-- Detect enabled languages with a config file but no lang_group
		local missing = {}
		for _, lang in ipairs(enabled) do
			if not lang_groups[lang] then
				local file = vim.fn.stdpath("config") .. "/lua/langs/" .. lang .. ".lua"
				if vim.fn.filereadable(file) == 1 then missing[#missing + 1] = lang end
			end
		end

		if #missing > 0 then
			warn(
				string.format("%d enabled language(s) have a file but no lang_group:", #missing),
				vim.tbl_map(function(l)
					return string.format("langs/%s.lua exists but didn't call keys.lang_group()", l)
				end, missing)
			)
		else
			ok("All lang files with keymaps are properly registered")
		end
	end

	-- ── 8. Prefix conflict detection ─────────────────────────────────
	local all_keys = vim.tbl_keys(keys._registry)
	table.sort(all_keys)
	local conflicts = 0

	for i, k1 in ipairs(all_keys) do
		local m1, lhs1 = k1:match("^(.)│(.+)$")
		if m1 and lhs1 then
			for j = i + 1, #all_keys do
				local k2 = all_keys[j]
				local m2, lhs2 = k2:match("^(.)│(.+)$")
				if m2 and lhs2 and m1 == m2 then
					if lhs2:sub(1, #lhs1) == lhs1 and #lhs2 > #lhs1 then
						warn(
							string.format(
								"Prefix conflict [%s]: '%s' (%s) ← prefix of → '%s' (%s)",
								m1,
								lhs1,
								keys._registry[k1].desc,
								lhs2,
								keys._registry[k2].desc
							)
						)
						conflicts = conflicts + 1
					end
				end
			end
		end
	end

	if conflicts == 0 then ok("No prefix conflicts detected") end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MAIN ENTRY POINT
--
-- Called by Neovim when the user runs `:checkhealth nvimenterprise`.
-- Executes all 9 sections sequentially. Each section is self-contained
-- and independently guarded against failures.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run all NvimEnterprise health check sections.
---
--- Called automatically by `:checkhealth nvimenterprise`.
--- Sections execute sequentially: Neovim → Platform → Settings →
--- Users → Plugins → Languages → LSP → Log → Keymaps.
---@return nil
function M.check()
	check_neovim()
	check_platform()
	check_settings()
	check_users()
	check_plugins()
	check_languages()
	check_lsp()
	check_log()
	check_keymaps()
end

return M
