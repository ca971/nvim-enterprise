---@file lua/config/plugin_manager.lua
---@description PluginManager — central plugin spec collector for lazy.nvim
---@module "config.plugin_manager"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see config.init Config entry point (calls collect_specs for lazy.setup)
---@see config.colorscheme_manager Colorscheme spec builder
---@see config.lazyvim_shim LazyVim global API compatibility layer
---@see core.settings Settings provider (languages.enabled, plugins.disabled, lazyvim_extras)
---@see core.platform Platform detection (path_join, config_dir)
---@see core.utils File/directory helpers (dir_exists, list_dir, ends_with)
---@see core.class OOP base class (Class:extend)
---@see core.logger Structured logging utility
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  config/plugin_manager.lua — Central plugin spec collector               ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  PluginManager (singleton, Class-based)                          │    ║
--- ║  │                                                                  │    ║
--- ║  │  collect_specs() assembles ALL lazy.nvim specs in order:         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Step 1 ─ Disabled overrides                                     │    ║
--- ║  │  │  • settings.plugins.disabled → { repo, enabled = false }      │    ║
--- ║  │  │  • Must come first: lazy.nvim processes disables early        │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Step 2 ─ Colorscheme specs                                      │    ║
--- ║  │  │  • Delegated to config.colorscheme_manager:specs()            │    ║
--- ║  │  │  • Includes active + fallback colorschemes                    │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Step 3 ─ Plugin categories                                      │    ║
--- ║  │  │  • plugins.ui, plugins.editor, plugins.code, etc.             │    ║
--- ║  │  │  • Each category is an { import = "plugins.<cat>" }           │    ║
--- ║  │  │  • Skipped if directory doesn't exist or has no .lua files    │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Step 4 ─ Language modules                                       │    ║
--- ║  │  │  • Only enabled languages (settings.languages.enabled)        │    ║
--- ║  │  │  • Each langs/<lang>.lua is required and its specs merged     │    ║
--- ║  │  │  • Disabled languages are never loaded (zero cost)            │    ║
--- ║  │  │  • Module cache cleared before require (hot-reload safe)      │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Step 5 ─ User namespace plugins                                 │    ║
--- ║  │  │  • users/<active_user>/plugins/ directory                     │    ║
--- ║  │  │  • Added as { import = "users.<name>.plugins" }               │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Step 6 ─ LazyVim extras (bootstrap-safe)                        │    ║
--- ║  │  │  • LazyVim/LazyVim added as lazy dependency                   │    ║
--- ║  │  │  • Bootstrap mode: no extras imported (files don't exist)     │    ║
--- ║  │  │  • Normal mode: each extra added as { import = extra }        │    ║
--- ║  │  │  • Custom loaders from plugins.lazyvim_extras/                │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Result: flat list of specs + imports for lazy.setup()           │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Language loading strategy:                                              ║
--- ║  • langs/*.lua files are NOT imported via { import = "langs" }           ║
--- ║  • Instead, each file is individually required with pcall                ║
--- ║  • This allows filtering by settings.languages.enabled                   ║
--- ║  • Files starting with "_" are ignored (templates, helpers)              ║
--- ║  • Module cache is cleared before require (package.loaded[modpath]=nil)  ║
--- ║  • This ensures fresh evaluation (important after settings changes)      ║
--- ║                                                                          ║
--- ║  Bootstrap handling (LazyVim extras):                                    ║
--- ║  • On first launch, LazyVim plugin directory doesn't exist               ║
--- ║  • Only the LazyVim dependency is added (for cloning)                    ║
--- ║  • Extras are NOT imported (their files don't exist yet)                 ║
--- ║  • User is notified to restart after installation completes              ║
--- ║  • On second launch, extras are fully loaded                             ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Singleton pattern: only one instance per session                      ║
--- ║  • Directory existence checked before import (avoids lazy.nvim errors)   ║
--- ║  • Disabled languages never touched (zero I/O, zero require)             ║
--- ║  • Structured logging at every decision point (debug + info + warn)      ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local Class = require("core.class")
local utils = require("core.utils")
local platform = require("core.platform")
local Logger = require("core.logger")

local log = Logger:for_module("config.plugin_manager")

-- ═══════════════════════════════════════════════════════════════════════════
-- CLASS DEFINITION
-- ═══════════════════════════════════════════════════════════════════════════

---@class PluginManager : Class
local PluginManager = Class:extend("PluginManager")

--- Default plugin category directories (under lua/plugins/).
--- Each category is checked for existence before being added as an import.
--- Order does not matter — lazy.nvim resolves dependencies internally.
---@type string[]
PluginManager.CATEGORIES = {
	"plugins.ui",
	"plugins.editor",
	"plugins.code",
	"plugins.code.lsp",
	"plugins.ai",
	"plugins.tools",
	"plugins.misc",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTRUCTOR
-- ═══════════════════════════════════════════════════════════════════════════

--- Initialize the PluginManager instance.
--- Loads settings reference and prepares the specs accumulator.
---@return nil
function PluginManager:init()
	self._settings = require("core.settings")
	self._specs = {}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INTERNAL HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Check if a dot-separated import path has a corresponding directory
--- containing at least one `.lua` file.
---
--- This prevents adding `{ import = "..." }` entries for directories
--- that don't exist, which would cause lazy.nvim warnings.
---@param import_path string Dot-separated module path (e.g. "plugins.ui")
---@return boolean exists Whether the directory exists and contains .lua files
---@private
function PluginManager:_import_path_exists(import_path)
	local rel_path = import_path:gsub("%.", "/")
	local abs_path = platform:path_join(platform.config_dir, "lua", rel_path)
	if not utils.dir_exists(abs_path) then return false end
	local files = utils.list_dir(abs_path, "file")
	for _, f in ipairs(files) do
		if utils.ends_with(f, ".lua") then return true end
	end
	return false
end

--- Check if LazyVim is already installed (not bootstrapping).
---@return boolean installed Whether the LazyVim plugin directory exists
---@private
function PluginManager:_is_lazyvim_installed()
	local lazyvim_path = vim.fn.stdpath("data") .. "/lazy/LazyVim"
	return vim.uv.fs_stat(lazyvim_path) ~= nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SPEC BUILDERS
--
-- Each _build_* method returns a list of lazy.nvim spec tables.
-- They are called sequentially by collect_specs() and their results
-- are concatenated into a single flat list.
-- ═══════════════════════════════════════════════════════════════════════════

--- Build import entries for default plugin categories.
---
--- Iterates over `CATEGORIES` and creates `{ import = category }`
--- entries for each category whose directory exists and contains
--- at least one `.lua` file.
---@return table[] specs List of `{ import = "..." }` entries
---@private
function PluginManager:_build_category_imports()
	local specs = {}
	for _, category in ipairs(self.CATEGORIES) do
		if self:_import_path_exists(category) then
			table.insert(specs, { import = category })
			log:debug("Added plugin category: %s", category)
		else
			log:debug("Skipped plugin category (not found): %s", category)
		end
	end
	return specs
end

--- Build specs for enabled language modules.
---
--- Scans `lua/langs/` for `.lua` files, filters by
--- `settings.languages.enabled`, and requires each enabled file
--- individually. The module cache is cleared before require to
--- ensure fresh evaluation after settings changes.
---
--- Files starting with `_` (templates, helpers) and `init.lua`
--- are always skipped.
---@return table[] specs Flat list of plugin specs from all enabled languages
---@private
function PluginManager:_build_lang_imports()
	local specs = {}
	local langs_dir = platform:path_join(platform.config_dir, "lua", "langs")

	if not utils.dir_exists(langs_dir) then
		log:warn("langs directory not found: %s", langs_dir)
		return specs
	end

	-- ── Build enabled set for O(1) lookups ───────────────────────────
	local enabled_list = self._settings:get("languages.enabled", {})
	local enabled_set = {}
	for _, lang in ipairs(enabled_list) do
		enabled_set[lang] = true
	end

	local files = utils.list_dir(langs_dir, "file")
	local loaded_count = 0
	local skipped_count = 0
	local disabled_count = 0

	-- ── Process each lang file ───────────────────────────────────────
	for _, filename in ipairs(files) do
		if utils.ends_with(filename, ".lua") and filename ~= "init.lua" and not vim.startswith(filename, "_") then
			local lang_name = filename:gsub("%.lua$", "")

			if not enabled_set[lang_name] then
				disabled_count = disabled_count + 1
				log:debug("Skipped language (not enabled): %s", lang_name)
				goto continue
			end

			-- Clear module cache to ensure fresh evaluation
			local modpath = "langs." .. lang_name
			package.loaded[modpath] = nil

			local ok, lang_specs = pcall(require, modpath)

			if ok and type(lang_specs) == "table" and #lang_specs > 0 then
				for _, spec in ipairs(lang_specs) do
					specs[#specs + 1] = spec
				end
				loaded_count = loaded_count + 1
				log:debug("Loaded language module: %s (%d specs)", lang_name, #lang_specs)
			elseif ok then
				skipped_count = skipped_count + 1
				log:debug("Language module returned empty specs: %s", lang_name)
			else
				log:warn("Failed to load language module '%s': %s", lang_name, tostring(lang_specs))
			end

			::continue::
		end
	end

	log:info(
		"Languages: %d loaded, %d skipped, %d disabled, %d specs total",
		loaded_count,
		skipped_count,
		disabled_count,
		#specs
	)
	return specs
end

--- Build import entry for the active user's plugins directory.
---
--- Looks for `lua/users/<active_user>/plugins/` and adds it as an
--- import if it exists and contains `.lua` files.
---@return table[] specs List with zero or one `{ import = "..." }` entry
---@private
function PluginManager:_build_user_imports()
	local specs = {}
	local active_user = self._settings:get("active_user", "default")
	local import_path = string.format("users.%s.plugins", active_user)

	if self:_import_path_exists(import_path) then
		table.insert(specs, { import = import_path })
		log:info("Added user plugins for '%s'", active_user)
	else
		log:debug("No user plugins found for '%s'", active_user)
	end

	return specs
end

--- Build specs for LazyVim extras (if enabled).
---
--- Handles two scenarios:
--- - **Bootstrap** (first launch): Only adds LazyVim as a lazy dependency
---   for cloning. Does NOT import extras (their files don't exist yet).
---   Registers a notification to prompt restart after install.
--- - **Normal**: Adds LazyVim dependency + each configured extra as an
---   `{ import = extra }` entry.
---
--- In both cases, the custom `plugins.lazyvim_extras/` directory is
--- added if it exists (for local overrides/patches).
---@return table[] specs LazyVim dependency + extra imports
---@private
function PluginManager:_build_lazyvim_extras()
	local specs = {}

	if not self._settings:get("lazyvim_extras.enabled", false) then return specs end

	local is_bootstrap = not self:_is_lazyvim_installed()

	-- ── LazyVim dependency (always) ──────────────────────────────────
	table.insert(specs, {
		"LazyVim/LazyVim",
		lazy = true,
		priority = 900,
		opts = {},
	})

	if is_bootstrap then
		-- ── BOOTSTRAP MODE ───────────────────────────────────────────
		-- LazyVim is not installed yet. Only add the dependency so
		-- lazy.nvim clones it. Do NOT import extras — their Lua files
		-- don't exist on disk yet and would crash.
		log:warn("LazyVim bootstrap detected — extras will load on next launch")

		vim.api.nvim_create_autocmd("User", {
			pattern = "LazyInstall",
			once = true,
			callback = function()
				vim.schedule(function()
					vim.notify(
						"LazyVim installed successfully!\n\n"
							.. "Please restart Neovim to activate LazyVim extras.\n"
							.. "Run: nvim",
						vim.log.levels.WARN,
						{ title = "NvimEnterprise — Bootstrap" }
					)
				end)
			end,
		})

		-- Custom loaders (our own code, safe even during bootstrap)
		if self:_import_path_exists("plugins.lazyvim_extras") then
			table.insert(specs, { import = "plugins.lazyvim_extras" })
		end

		return specs
	end

	-- ── NORMAL MODE (LazyVim is installed) ───────────────────────────
	log:info("LazyVim extras enabled — adding imports")

	local extras = self._settings:get("lazyvim_extras.extras", {})
	for _, extra in ipairs(extras) do
		table.insert(specs, { import = extra })
		log:info("Added LazyVim extra: %s", extra)
	end

	-- Custom loaders
	if self:_import_path_exists("plugins.lazyvim_extras") then
		table.insert(specs, { import = "plugins.lazyvim_extras" })
	end

	return specs
end

--- Build disabled plugin overrides.
---
--- Each disabled plugin becomes `{ repo, enabled = false }` which
--- lazy.nvim processes to prevent the plugin from loading.
---@return table[] specs List of `{ repo, enabled = false }` entries
---@private
function PluginManager:_build_disabled_overrides()
	local specs = {}
	local disabled = self._settings:get("plugins.disabled", {})

	for _, repo in ipairs(disabled) do
		table.insert(specs, { repo, enabled = false })
		log:debug("Disabled plugin: %s", repo)
	end

	return specs
end

--- Build colorscheme specs via the colorscheme manager.
---@return table[] specs Colorscheme plugin specs (active + fallback)
---@private
function PluginManager:_build_colorscheme_specs()
	local ok, cs_manager = pcall(require, "config.colorscheme_manager")
	if not ok then
		log:warn("Failed to load colorscheme_manager: %s", tostring(cs_manager))
		return {}
	end
	return cs_manager:specs()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

--- Collect all plugin specs for lazy.nvim.
---
--- Assembles specs from all sources in a defined order:
--- 1. Disabled overrides (must come first for precedence)
--- 2. Colorscheme specs
--- 3. Plugin categories (ui, editor, code, ai, tools, misc)
--- 4. Language modules (only enabled languages)
--- 5. User namespace plugins
--- 6. LazyVim extras (bootstrap-safe)
---
--- The returned list is passed directly to `lazy.setup()`.
---@return table[] specs Complete flat list of lazy.nvim specs and imports
function PluginManager:collect_specs()
	self._specs = {}

	-- ── Step 1: Disabled overrides (first for precedence) ────────────
	vim.list_extend(self._specs, self:_build_disabled_overrides())

	-- ── Step 2: Colorscheme specs ────────────────────────────────────
	vim.list_extend(self._specs, self:_build_colorscheme_specs())

	-- ── Step 3: Plugin categories ────────────────────────────────────
	vim.list_extend(self._specs, self:_build_category_imports())

	-- ── Step 4: Language modules ─────────────────────────────────────
	vim.list_extend(self._specs, self:_build_lang_imports())

	-- ── Step 5: User namespace plugins ───────────────────────────────
	vim.list_extend(self._specs, self:_build_user_imports())

	-- ── Step 6: LazyVim extras ───────────────────────────────────────
	vim.list_extend(self._specs, self:_build_lazyvim_extras())

	log:info("Collected %d spec entries total", #self._specs)
	return self._specs
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SINGLETON
--
-- Only one PluginManager instance exists per session. The singleton
-- is created on first require and reused thereafter.
-- ═══════════════════════════════════════════════════════════════════════════

---@type PluginManager
local _instance

--- Get or create the singleton PluginManager instance.
---@return PluginManager instance The singleton instance
local function get_instance()
	if not _instance then
		---@diagnostic disable-next-line: cast-type-mismatch
		---@type PluginManager
		_instance = PluginManager:new() --[[@as PluginManager]]
	end
	return _instance
end

return get_instance()
