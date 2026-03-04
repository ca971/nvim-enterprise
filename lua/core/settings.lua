---@file lua/core/settings.lua
---@description Settings — configuration loader, merger, accessor and persistence singleton
---@module "core.settings"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.class Base OOP system (Settings extends Class)
---@see core.utils Deep merge, table access, file I/O utilities
---@see core.platform Platform singleton (path resolution, config_dir)
---@see core.logger Structured logging (Logger:for_module)
---@see core.bootstrap Bootstrap calls Settings:load() during startup
---@see config.settings_manager SettingsManager wraps Settings for UI commands
---@see users.user_manager UserManager triggers Settings:reload() on user switch
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/settings.lua — Settings loader and accessor (singleton)            ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Settings (singleton, extends Class)                             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Load pipeline (executed once during bootstrap):                 │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  1. Load root settings.lua (defaults)                      │  │    ║
--- ║  │  │     ~/.config/nvim/settings.lua → dofile()                 │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  2. Determine active user                                  │  │    ║
--- ║  │  │     defaults.active_user → "bly" | "jane" | "default"      │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  3. Load user overrides (if any)                           │  │    ║
--- ║  │  │     users/<user>/settings.lua → safe_require()             │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  4. Deep-merge defaults ← user overrides                   │  │    ║
--- ║  │  │     utils.deep_merge() (user wins on conflicts)            │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  5. Populate _G.NvimConfig.settings                        │  │    ║
--- ║  │  │     Global access for legacy/non-module consumers          │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Accessor API (dot-notation):                                    │    ║
--- ║  │  ├─ :get("ui.colorscheme")           → "catppuccin"              │    ║
--- ║  │  ├─ :get("editor.tab_size", 4)       → 2 (or 4 fallback)         │    ║
--- ║  │  ├─ :is_plugin_enabled("telescope")  → true/false                │    ║
--- ║  │  ├─ :is_language_enabled("python")   → true/false                │    ║
--- ║  │  ├─ :is_ai_enabled("copilot")        → true/false                │    ║
--- ║  │  ├─ :defaults()                      → raw defaults table        │    ║
--- ║  │  ├─ :user_overrides()                → raw user overrides        │    ║
--- ║  │  └─ :all()                           → full merged table         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Persistence:                                                    │    ║
--- ║  │  ├─ :persist("ui.colorscheme", "tokyonight")                     │    ║
--- ║  │  │  Writes to disk AND updates in-memory merged settings         │    ║
--- ║  │  ├─ Parses settings.lua as text, finds active (uncommented)      │    ║
--- ║  │  │  field assignment, rewrites value preserving indent/commas    │    ║
--- ║  │  └─ Supports string, boolean, and number types                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Hot-reload:                                                     │    ║
--- ║  │  ├─ :reload()           Re-run the full load pipeline            │    ║
--- ║  │  └─ :reload("jane")    Switch active user + reload               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ Singleton pattern: one Settings object for the lifetime      │    ║
--- ║  │  ├─ dofile() for root settings (not require) so it's not cached  │    ║
--- ║  │  │  by Lua's module system — allows reload without cache bust    │    ║
--- ║  │  ├─ safe_require() for user settings — graceful missing files    │    ║
--- ║  │  ├─ _G.NvimConfig.settings for backward compat / global access   │    ║
--- ║  │  ├─ persist() does text-level surgery (not Lua serialization)    │    ║
--- ║  │  │  to preserve comments, formatting, and structure              │    ║
--- ║  │  └─ Built-in defaults as ultimate fallback if settings.lua is    │    ║
--- ║  │     missing or malformed — Neovim always starts                  │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Settings loaded once via :load(), guarded by _loaded flag             ║
--- ║  • Dot-notation accessor uses utils.tbl_get() (O(depth) lookup)          ║
--- ║  • Deep-merge runs once at load time, not on every access                ║
--- ║  • Module cached by require() — singleton returned directly              ║
--- ║  • persist() only reads/writes the file when explicitly called           ║
--- ║                                                                          ║
--- ║  Public API:                                                             ║
--- ║    settings:load()                        Run the full load pipeline     ║
--- ║    settings:reload(user?)                 Hot-reload (optional user swap)║
--- ║    settings:get(key, default?)            Dot-notation accessor          ║
--- ║    settings:is_plugin_enabled(name)       Plugin enable check            ║
--- ║    settings:is_language_enabled(lang)     Language enable check          ║
--- ║    settings:is_ai_enabled(provider?)      AI provider enable check       ║
--- ║    settings:defaults()                    Raw defaults table             ║
--- ║    settings:user_overrides()              Raw user overrides table       ║
--- ║    settings:all()                         Full merged table              ║
--- ║    settings:persist(key, value)           Write setting to disk          ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local Class = require("core.class")
local utils = require("core.utils")
local platform = require("core.platform")
local Logger = require("core.logger")

local log = Logger:for_module("core.settings")

-- ═══════════════════════════════════════════════════════════════════════
-- CLASS DEFINITION
-- ═══════════════════════════════════════════════════════════════════════

---@class Settings : Class
---@field _defaults table Raw default settings loaded from root `settings.lua`
---@field _user_overrides table User-specific overrides from `users/<user>/settings.lua`
---@field _merged table Final deep-merged settings (defaults ← user overrides)
---@field _loaded boolean Guard flag — `true` after first successful `:load()` call
local Settings = Class:extend("Settings")

--- Initialize a new Settings instance with empty state.
---
--- All tables start empty and are populated by `:load()`.
--- The `_loaded` flag prevents redundant loading.
function Settings:init()
	self._defaults = {}
	self._user_overrides = {}
	self._merged = {}
	self._loaded = false
end

-- ═══════════════════════════════════════════════════════════════════════
-- INTERNAL — FILE LOADING
--
-- Two-source loading strategy:
-- 1. Root settings.lua via dofile() (intentionally NOT require(),
--    so it's not cached by Lua's module system and can be reloaded)
-- 2. User settings via safe_require() (cached is fine — reload()
--    clears package.loaded before re-requiring)
-- ═══════════════════════════════════════════════════════════════════════

--- Get the absolute path to the root `settings.lua` file.
---
---@return string path Absolute path to `~/.config/nvim/settings.lua`
---@private
function Settings:_root_settings_path()
	return platform:path_join(platform.config_dir, "settings.lua")
end

--- Load the root `settings.lua` file via `dofile()`.
---
--- Uses `dofile()` instead of `require()` so the file is always
--- read fresh from disk (not cached by Lua's module system).
--- Falls back to `_builtin_defaults()` if the file is missing,
--- fails to parse, or returns a non-table value.
---
---@return table defaults Parsed settings table or built-in fallback
---@private
function Settings:_load_defaults()
	local path = self:_root_settings_path()
	if not utils.file_exists(path) then
		log:warn("Root settings.lua not found at: %s — using built-in defaults", path)
		return self:_builtin_defaults()
	end

	local ok, result = pcall(dofile, path)
	if not ok then
		log:error("Failed to load settings.lua: %s", tostring(result))
		return self:_builtin_defaults()
	end

	if type(result) ~= "table" then
		log:error("settings.lua must return a table, got %s", type(result))
		return self:_builtin_defaults()
	end

	log:debug("Root settings.lua loaded successfully")
	return result
end

--- Load a user's settings overrides from `users/<username>/settings.lua`.
---
--- Uses `utils.safe_require()` which returns `nil` + error message
--- on failure, allowing graceful degradation when a user profile
--- has no settings file.
---
---@param username string User profile name (e.g. `"bly"`, `"jane"`, `"default"`)
---@return table overrides User settings table, or empty table if not found
---@private
function Settings:_load_user_settings(username)
	if not username or username == "" then return {} end

	local modname = string.format("users.%s.settings", username)
	local mod, err = utils.safe_require(modname)

	if mod and type(mod) == "table" then
		log:info("Loaded settings for user '%s'", username)
		return mod
	end

	if err then log:debug("No settings override for user '%s': %s", username, err) end

	return {}
end

--- Minimal built-in defaults — ultimate fallback.
---
--- Used when `settings.lua` is missing, malformed, or unreadable.
--- Provides the minimum configuration needed for Neovim to start
--- with a functional (if basic) setup.
---
---@return table defaults Minimal viable configuration table
---@private
function Settings:_builtin_defaults()
	return {
		active_user = "default",
		ui = {
			colorscheme = "habamax",
			colorscheme_style = "",
			transparent_background = false,
			float_border = "rounded",
		},
		editor = { tab_size = 2, use_spaces = true, relative_number = true, number = true, wrap = false },
		keymaps = { leader = " ", local_leader = "\\" },
		plugins = { disabled = {} },
		languages = { enabled = { "lua" } },
		lsp = { format_on_save = true, auto_install = true },
		ai = { enabled = false, provider = "copilot" },
		lazyvim_extras = { enabled = false, extras = {} },
		colorschemes = {},
		performance = { lazy_load = true, cache = true, ssh_optimization = true },
	}
end

-- ═══════════════════════════════════════════════════════════════════════
-- LOAD & RELOAD
--
-- :load() is the main entry point — called once by core/bootstrap.lua.
-- :reload() supports hot-switching users without restarting Neovim.
-- Both methods follow the same 5-step pipeline but reload() first
-- clears the Lua module cache for the affected user modules.
-- ═══════════════════════════════════════════════════════════════════════

--- Load and merge all settings — main entry point.
---
--- Executes the full 5-step pipeline:
--- 1. Load root `settings.lua` defaults
--- 2. Determine active user from defaults
--- 3. Load user-specific overrides
--- 4. Deep-merge (user overrides win on conflicts)
--- 5. Populate `_G.NvimConfig.settings` for global access
---
--- Guarded by `_loaded` flag — calling multiple times is safe (no-op).
---
--- ```lua
--- local settings = require("core.settings")
--- settings:load()  -- Called by bootstrap, not by consumers
--- ```
---
---@return Settings self For method chaining
function Settings:load()
	if self._loaded then return self end

	-- Step 1: Load defaults from root settings.lua
	self._defaults = self:_load_defaults()

	-- Step 2: Determine active user
	local active_user = self._defaults.active_user or "default"

	-- Step 3: Load user overrides
	-- Even "default" user can have overrides in users/default/settings.lua
	if active_user ~= "default" then
		self._user_overrides = self:_load_user_settings(active_user)
	else
		self._user_overrides = self:_load_user_settings("default")
	end

	-- Step 4: Deep-merge (user overrides win on key conflicts)
	self._merged = utils.deep_merge(self._defaults, self._user_overrides)

	-- Step 5: Populate global for legacy / non-module consumers
	_G.NvimConfig.settings = self._merged
	_G.NvimConfig.state.active_user = self._merged.active_user or active_user

	self._loaded = true
	log:info("Settings loaded for user '%s'", _G.NvimConfig.state.active_user)

	return self
end

--- Reload settings, optionally switching the active user.
---
--- Clears the Lua `package.loaded` cache for the old and new user
--- settings modules before re-running the full load pipeline.
--- This enables hot-switching users without restarting Neovim.
---
--- ```lua
--- settings:reload()         -- Re-read same user's settings
--- settings:reload("jane")   -- Switch to user "jane" and reload
--- ```
---
---@param new_user? string If provided, switch active user before reloading
---@return Settings self For method chaining
function Settings:reload(new_user)
	-- Clear cached modules so re-require picks up fresh data
	if self._merged.active_user then
		local old_mod = string.format("users.%s.settings", self._merged.active_user)
		package.loaded[old_mod] = nil
	end
	if new_user then
		local new_mod = string.format("users.%s.settings", new_user)
		package.loaded[new_mod] = nil
		self._defaults.active_user = new_user
	end

	self._loaded = false
	return self:load()
end

-- ═══════════════════════════════════════════════════════════════════════
-- ACCESSOR API
--
-- Clean, typed accessors for reading merged settings. All methods
-- operate on the deep-merged table (_merged) so consumers never
-- need to worry about defaults vs overrides.
-- ═══════════════════════════════════════════════════════════════════════

--- Get a setting value using dot-notation path.
---
--- Traverses the merged settings table using `utils.tbl_get()`.
--- Returns `default` if any segment of the path is `nil`.
---
--- ```lua
--- settings:get("ui.colorscheme")            --> "catppuccin"
--- settings:get("editor.tab_size")           --> 2
--- settings:get("nonexistent.key", "fallback") --> "fallback"
--- ```
---
---@param key string Dot-separated path (e.g. `"ui.colorscheme"`)
---@param default? any Fallback value if the key resolves to `nil`
---@return any value The resolved value, or `default` if not found
function Settings:get(key, default)
	local val = utils.tbl_get(self._merged, key)
	if val == nil then return default end
	return val
end

--- Check if a plugin is enabled.
---
--- Two-level check:
--- 1. `plugins.disabled` list — repo names or short names
--- 2. Per-plugin `plugins.<name>.enabled` flag
---
--- A plugin is considered enabled unless explicitly disabled
--- by either mechanism.
---
--- ```lua
--- settings:is_plugin_enabled("telescope")                      --> true
--- settings:is_plugin_enabled("nvim-telescope/telescope.nvim")  --> true
--- ```
---
---@param name string Plugin key (e.g. `"telescope"`) or repo (e.g. `"nvim-telescope/telescope.nvim"`)
---@return boolean enabled `true` unless explicitly disabled
function Settings:is_plugin_enabled(name)
	-- Check disabled list first (supports both short names and repo names)
	local disabled = self:get("plugins.disabled", {})
	if utils.tbl_contains(disabled, name) then return false end

	-- Check per-plugin enabled flag (e.g., plugins.telescope.enabled = false)
	local plugin_cfg = self:get("plugins." .. name)
	if type(plugin_cfg) == "table" and plugin_cfg.enabled == false then return false end

	return true
end

--- Check if a language is enabled for LSP/Treesitter/linting support.
---
--- Checks against the `languages.enabled` list in merged settings.
---
--- ```lua
--- settings:is_language_enabled("python")  --> true
--- settings:is_language_enabled("cobol")   --> false
--- ```
---
---@param lang string Language key matching a `langs/*.lua` filename (e.g. `"python"`, `"rust"`)
---@return boolean enabled `true` if the language is in the enabled list
function Settings:is_language_enabled(lang)
	local enabled = self:get("languages.enabled", {})
	return utils.tbl_contains(enabled, lang)
end

--- Check if AI assistance is enabled (master switch or specific provider).
---
--- Without a `provider` argument, checks the master `ai.enabled` switch.
--- With a `provider`, also checks the provider-specific `ai.<provider>.enabled` flag.
---
--- ```lua
--- settings:is_ai_enabled()           --> true/false (master switch)
--- settings:is_ai_enabled("copilot")  --> true/false (copilot specifically)
--- ```
---
---@param provider? string Specific AI provider to check (e.g. `"copilot"`, `"codeium"`)
---@return boolean enabled `true` if AI (and optionally the specific provider) is enabled
function Settings:is_ai_enabled(provider)
	if not self:get("ai.enabled", false) then return false end
	if provider then return self:get("ai." .. provider .. ".enabled", false) end
	return true
end

--- Get the raw defaults table (before user merge).
---
---@return table defaults The unmerged default settings from root `settings.lua`
function Settings:defaults()
	return self._defaults
end

--- Get the raw user overrides table (before merge).
---
---@return table overrides The user-specific settings (empty table if none)
function Settings:user_overrides()
	return self._user_overrides
end

--- Get the full merged settings table.
---
---@return table merged Complete settings (defaults + user overrides)
function Settings:all()
	return self._merged
end

-- ═══════════════════════════════════════════════════════════════════════
-- PERSISTENCE
--
-- Writes a setting value to the root settings.lua file on disk.
-- Uses text-level surgery (not Lua serialization) to preserve
-- comments, formatting, indentation, and file structure.
--
-- Strategy:
-- 1. Read settings.lua as raw text
-- 2. Split into lines
-- 3. Find the ACTIVE (uncommented) assignment for the field
-- 4. Rewrite the value preserving indent and trailing comma
-- 5. Write the modified text back to disk
-- 6. Update in-memory _merged table
-- ═══════════════════════════════════════════════════════════════════════

--- Persist a setting value to the root `settings.lua` file on disk.
---
--- Performs text-level surgery on the file to update a single field
--- while preserving comments, indentation, and file structure.
--- Also updates the in-memory merged settings immediately.
---
--- ```lua
--- settings:persist("ui.colorscheme", "catppuccin")      -- string
--- settings:persist("ui.transparent_background", true)    -- boolean
--- settings:persist("editor.tab_size", 4)                 -- number
--- ```
---
--- Supported types: `string`, `boolean`, `number`.
--- Tables and functions are not supported (use the settings file directly).
---
---@param key string Dot-separated path (e.g. `"ui.colorscheme"`)
---@param value any The value to write (string, boolean, or number)
---@return boolean success `true` if the value was written to disk and memory
---@return string|nil error Error message on failure, `nil` on success
function Settings:persist(key, value)
	local path = self:_root_settings_path()
	local content, read_err = utils.read_file(path)
	if not content then
		log:error("Cannot read settings.lua: %s", read_err or "unknown")
		return false, read_err
	end

	-- Extract the leaf field name from the dot path
	-- e.g., "ui.colorscheme" → "colorscheme"
	local parts = vim.split(key, ".", { plain = true })
	local field_name = parts[#parts]

	-- Format value as valid Lua source code
	---@type string
	local formatted
	if type(value) == "string" then
		formatted = '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
	elseif type(value) == "boolean" then
		formatted = value and "true" or "false"
	elseif type(value) == "number" then
		formatted = tostring(value)
	else
		log:error("Cannot persist type %s for key %s", type(value), key)
		return false, "unsupported type: " .. type(value)
	end

	-- Find and replace the active (uncommented) field assignment.
	-- Must skip commented lines (-- field = ...) and handle
	-- trailing commas and inline comments.
	local lines = vim.split(content, "\n", { plain = true })
	local found = false
	local field_pattern = "^(%s*)" .. field_name .. "%s*="

	for i, line in ipairs(lines) do
		-- Skip commented lines
		local stripped = line:match("^%s*(.-)$")
		if stripped and not stripped:match("^%-%-") then
			if line:match(field_pattern) then
				-- Preserve leading whitespace (indentation)
				local indent = line:match("^(%s*)")
				-- Detect trailing comma (with or without inline comment)
				local has_comma = line:match(",%s*$") or line:match(",%s*%-%-")
				-- Rebuild the line preserving indent and trailing comma
				local new_line = indent .. field_name .. " = " .. formatted
				if has_comma then new_line = new_line .. "," end
				lines[i] = new_line
				found = true
				break
			end
		end
	end

	if not found then
		log:warn("Could not find active field '%s' in settings.lua", field_name)
		return false, "field not found: " .. field_name
	end

	-- Write modified content back to disk
	local new_content = table.concat(lines, "\n")
	local ok, write_err = utils.write_file(path, new_content)
	if not ok then
		log:error("Cannot write settings.lua: %s", write_err or "unknown")
		return false, write_err
	end

	-- Update in-memory merged settings immediately
	utils.tbl_set(self._merged, key, value)

	log:info("Persisted %s = %s to settings.lua", key, formatted)
	return true
end

-- ═══════════════════════════════════════════════════════════════════════
-- SINGLETON
--
-- Settings is instantiated once and returned directly by require().
-- The _loaded guard in :load() prevents double-loading.
-- ═══════════════════════════════════════════════════════════════════════

---@type Settings|nil
---@private
local _instance = nil

--- Get or create the Settings singleton instance.
---
--- On first call, creates a new `Settings` instance (empty state).
--- The caller must then call `:load()` to populate settings.
--- On subsequent calls, returns the cached instance.
---
---@return Settings instance The global Settings singleton
---@private
local function get_instance()
	if not _instance then
		_instance = Settings:new() --[[@as Settings]]
	end
	return _instance
end

return get_instance()
