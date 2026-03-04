---@file lua/users/namespace.lua
---@description Namespace — Individual user namespace abstraction (directory, settings, keymaps, metadata)
---@module "users.namespace"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.class               OOP base class (Class:extend)
---@see core.utils               File I/O, string helpers, table utilities
---@see core.platform            Platform detection (path_join, config_dir)
---@see core.security            Namespace name validation (sanitization, traversal prevention)
---@see core.logger              Structured logging utility
---@see users.user_manager       CRUD operations orchestrator (uses Namespace internally)
---@see config.settings_manager  High-level user management (switch, create, delete commands)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  users/namespace.lua — User namespace class                              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Namespace (Class-based, one instance per user)                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Directory Structure:                                            │    ║
--- ║  │  └─ lua/users/<name>/                                            │    ║
--- ║  │     ├─ init.lua          Post-plugin initialization              │    ║
--- ║  │     ├─ settings.lua      User overrides (deep-merged over root)  │    ║
--- ║  │     ├─ keymaps.lua       User-specific key mappings              │    ║
--- ║  │     ├─ .meta.json        Metadata (profile, switches, tags)      │    ║
--- ║  │     ├─ .lock             Lock marker (prevents deletion)         │    ║
--- ║  │     └─ plugins/          Custom lazy.nvim plugin specs           │    ║
--- ║  │        └─ init.lua       Plugin spec return table                │    ║
--- ║  │                                                                  │    ║
--- ║  │  Lifecycle:                                                      │    ║
--- ║  │  ├─ create(profile?)  Build directory + template files           │    ║
--- ║  │  ├─ delete()          Remove directory (if unlocked, not default)│    ║
--- ║  │  ├─ clone(new_name)   Export → import with name substitution     │    ║
--- ║  │  ├─ lock() / unlock() Protect / unprotect against deletion       │    ║
--- ║  │  └─ _clear_module_cache() Purge package.loaded entries           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Data Access:                                                    │    ║
--- ║  │  ├─ exists()          Directory existence check                  │    ║
--- ║  │  ├─ has_settings()    Settings file existence                    │    ║
--- ║  │  ├─ has_keymaps()     Keymaps file existence                     │    ║
--- ║  │  ├─ has_plugins()     Plugin dir with ≥1 .lua file               │    ║
--- ║  │  ├─ is_locked()       Lock file existence                        │    ║
--- ║  │  ├─ load_settings()   Require and return settings table          │    ║
--- ║  │  ├─ load_keymaps()    Require and call setup()                   │    ║
--- ║  │  ├─ load_init()       Require and call setup()                   │    ║
--- ║  │  └─ info()            Detailed summary (size, counts, meta)      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Metadata (.meta.json):                                          │    ║
--- ║  │  ├─ load_meta()       Parse JSON → table                         │    ║
--- ║  │  ├─ save_meta(meta)   Table → pretty JSON → file                 │    ║
--- ║  │  ├─ record_switch()   Increment switch_count + update timestamp  │    ║
--- ║  │  └─ Fields:                                                      │    ║
--- ║  │     ├─ created_at     ISO timestamp                              │    ║
--- ║  │     ├─ profile        Profile name used at creation              │    ║
--- ║  │     ├─ description    Human-readable description                 │    ║
--- ║  │     ├─ switch_count   Number of times activated                  │    ║
--- ║  │     ├─ last_active    Last activation timestamp                  │    ║
--- ║  │     ├─ tags           User-defined tags array                    │    ║
--- ║  │     ├─ cloned_from    Source namespace (if cloned)               │    ║
--- ║  │     └─ imported_from  Source namespace (if imported)             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Export / Import:                                                │    ║
--- ║  │  ├─ export()              → JSON-serializable table              │    ║
--- ║  │  ├─ export_to_file(path)  → JSON file on disk                    │    ║
--- ║  │  └─ import_from_file(path, name?)  ← JSON file → new namespace   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Health Check:                                                   │    ║
--- ║  │  └─ health_check() → { ok, checks[] }                            │    ║
--- ║  │     ├─ Directory existence                                       │    ║
--- ║  │     ├─ init.lua loads without errors                             │    ║
--- ║  │     ├─ settings.lua returns a table                              │    ║
--- ║  │     ├─ keymaps.lua has setup() function                          │    ║
--- ║  │     ├─ plugins/ files all valid                                  │    ║
--- ║  │     └─ Metadata present and populated                            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Profiles (5 predefined templates):                              │    ║
--- ║  │  ├─ minimal    Fast startup, essential plugins only              │    ║
--- ║  │  ├─ developer  Full IDE features, copilot, animations            │    ║
--- ║  │  ├─ writer     Prose mode, soft wrap, spell check                │    ║
--- ║  │  ├─ devops     Docker, Helm, Terraform focus                     │    ║
--- ║  │  └─ presenter  Large font, clean UI, no distractions             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Template Generators (private):                                  │    ║
--- ║  │  ├─ _template_init()               → init.lua boilerplate        │    ║
--- ║  │  ├─ _template_settings(profile?)   → settings.lua with overrides │    ║
--- ║  │  ├─ _template_keymaps()            → keymaps.lua boilerplate     │    ║
--- ║  │  └─ _template_plugins()            → plugins/init.lua            │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Security:                                                               ║
--- ║  • Namespace names validated via core.security:validate_namespace()      ║
--- ║  • Prevents path traversal (../, absolute paths, special chars)          ║
--- ║  • "default" namespace cannot be deleted                                 ║
--- ║  • Locked namespaces cannot be deleted until unlocked                    ║
--- ║  • Import validates name before creating directories                     ║
--- ║  • Clone substitutes namespace name in file content                      ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local Class = require("core.class")
local utils = require("core.utils")
local platform = require("core.platform")
local security = require("core.security")
local Logger = require("core.logger")

local log = Logger:for_module("users.namespace")

-- ═══════════════════════════════════════════════════════════════════════════
-- CLASS DEFINITION
-- ═══════════════════════════════════════════════════════════════════════════

---@class Namespace : Class
---@field name string          User namespace name (alphanumeric + hyphens)
---@field path string          Absolute path to the user's directory
---@field settings_path string Absolute path to the user's settings.lua
---@field keymaps_path string  Absolute path to the user's keymaps.lua
---@field init_path string     Absolute path to the user's init.lua
---@field plugins_path string  Absolute path to the user's plugins/ directory
---@field meta_path string     Absolute path to the user's .meta.json
---@field lock_path string     Absolute path to the user's .lock file
local Namespace = Class:extend("Namespace")

-- ═══════════════════════════════════════════════════════════════════════════
-- PROFILES
--
-- Predefined settings templates applied during namespace creation.
-- Each profile defines a `description` (for :UserProfiles display)
-- and a `settings` table that is serialized into the user's
-- settings.lua template file.
--
-- Profiles available:
--   minimal    — Fast startup, essential plugins only
--   developer  — Full IDE features, copilot, animations
--   writer     — Prose mode, soft wrap, spell check
--   devops     — Docker, Helm, Terraform focus
--   presenter  — Large font, clean UI, no distractions
-- ═══════════════════════════════════════════════════════════════════════════

---@type table<string, {description: string, settings: table}>
Namespace.PROFILES = {
	minimal = {
		description = "Minimal setup — fast startup, essential plugins only",
		settings = {
			ui = {
				colorscheme = "habamax",
				animations = false,
				transparent_background = false,
			},
			editor = {
				relative_number = false,
				cursor_column = false,
				wrap = false,
			},
			ai = { enabled = false },
			performance = { lazy_load = true },
		},
	},
	developer = {
		description = "Full development setup — all IDE features enabled",
		settings = {
			ui = {
				colorscheme = "tokyonight",
				colorscheme_style = "storm",
				animations = true,
			},
			editor = {
				relative_number = true,
				cursor_column = true,
				tab_size = 2,
				wrap = false,
			},
			ai = { enabled = true, provider = "copilot" },
		},
	},
	writer = {
		description = "Writing & prose — soft wrap, spell check, minimal UI",
		settings = {
			ui = {
				colorscheme = "kanagawa",
				animations = false,
			},
			editor = {
				relative_number = false,
				cursor_column = false,
				wrap = true,
				tab_size = 4,
				number = false,
			},
			ai = { enabled = false },
		},
	},
	devops = {
		description = "DevOps & Infrastructure — Docker, Helm, Terraform focus",
		settings = {
			ui = {
				colorscheme = "catppuccin",
				colorscheme_style = "mocha",
			},
			editor = {
				relative_number = true,
				tab_size = 2,
			},
			languages = {
				enabled = {
					"lua",
					"yaml",
					"json",
					"toml",
					"bash",
					"docker",
					"helm",
					"terraform",
					"python",
					"go",
				},
			},
		},
	},
	presenter = {
		description = "Presentation mode — large font, clean UI, no distractions",
		settings = {
			ui = {
				colorscheme = "tokyonight",
				colorscheme_style = "day",
				gui_font = "JetBrainsMono Nerd Font:h20",
				animations = false,
			},
			editor = {
				relative_number = false,
				number = true,
				cursor_column = false,
				wrap = true,
				scroll_off = 4,
			},
			ai = { enabled = false },
		},
	},
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTRUCTOR
-- ═══════════════════════════════════════════════════════════════════════════

--- Initialize a user namespace instance.
---
--- Computes all file and directory paths from the namespace name.
--- Does NOT create the directory structure — use :create() for that.
---@param name string User namespace name (alphanumeric + hyphens)
---@return nil
function Namespace:init(name)
	self.name = name
	self.path = platform:path_join(platform.config_dir, "lua", "users", name)
	self.init_path = platform:path_join(self.path, "init.lua")
	self.settings_path = platform:path_join(self.path, "settings.lua")
	self.keymaps_path = platform:path_join(self.path, "keymaps.lua")
	self.plugins_path = platform:path_join(self.path, "plugins")
	self.meta_path = platform:path_join(self.path, ".meta.json")
	self.lock_path = platform:path_join(self.path, ".lock")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EXISTENCE CHECKS
--
-- Fast boolean queries for namespace directory and file existence.
-- Used by user_manager for listing, settings_manager for validation,
-- and health_check for detailed reporting.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check if this namespace directory exists.
---@return boolean exists True if the directory exists on disk
function Namespace:exists()
	return utils.dir_exists(self.path)
end

--- Check if the namespace has a settings.lua file.
---@return boolean has_settings True if settings.lua exists
function Namespace:has_settings()
	return utils.file_exists(self.settings_path)
end

--- Check if the namespace has a keymaps.lua file.
---@return boolean has_keymaps True if keymaps.lua exists
function Namespace:has_keymaps()
	return utils.file_exists(self.keymaps_path)
end

--- Check if the namespace has a plugins directory with at least one .lua file.
---@return boolean has_plugins True if plugins/ contains ≥1 .lua file
function Namespace:has_plugins()
	if not utils.dir_exists(self.plugins_path) then return false end
	local files = utils.list_dir(self.plugins_path, "file")
	for _, f in ipairs(files) do
		if utils.ends_with(f, ".lua") then return true end
	end
	return false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LOCK MANAGEMENT
--
-- Lock files (.lock) protect namespaces against accidental deletion.
-- The lock file contains the timestamp of when it was created.
-- Locking is advisory — it is enforced by delete() and the
-- :UserDelete command, not by file system permissions.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check if the namespace is locked (protected against deletion).
---@return boolean is_locked True if .lock file exists
function Namespace:is_locked()
	return utils.file_exists(self.lock_path)
end

--- Lock the namespace (prevent deletion).
---
--- Creates a .lock file containing the current timestamp.
--- Fails if the namespace doesn't exist or is already locked.
---@return boolean success Whether the lock was created
---@return string|nil error Error message if failed
function Namespace:lock()
	if not self:exists() then return false, string.format("Namespace '%s' does not exist", self.name) end
	if self:is_locked() then return false, string.format("Namespace '%s' is already locked", self.name) end
	local ok, err = utils.write_file(self.lock_path, os.date("%Y-%m-%d %H:%M:%S") .. "\n")
	if ok then log:info("Locked namespace '%s'", self.name) end
	return ok, err
end

--- Unlock the namespace (allow deletion).
---
--- Removes the .lock file. Fails if the namespace is not locked.
---@return boolean success Whether the lock was removed
---@return string|nil error Error message if failed
function Namespace:unlock()
	if not self:is_locked() then return false, string.format("Namespace '%s' is not locked", self.name) end
	local result = vim.fn.delete(self.lock_path)
	if result == 0 then
		log:info("Unlocked namespace '%s'", self.name)
		return true, nil
	end
	return false, "Failed to remove lock file"
end

-- ═══════════════════════════════════════════════════════════════════════════
-- METADATA
--
-- Metadata is stored as .meta.json in the namespace directory.
-- It tracks creation info, profile, switch count, timestamps,
-- tags, and provenance (cloned_from, imported_from).
--
-- Metadata is never required for the namespace to function —
-- legacy namespaces without .meta.json get sensible defaults.
-- ═══════════════════════════════════════════════════════════════════════════

--- Load namespace metadata from .meta.json.
---
--- Returns a table with sensible defaults if the file doesn't exist
--- or cannot be parsed (legacy namespace support).
---@return table meta Metadata table with fields: created_at, profile, description, switch_count, last_active, tags
function Namespace:load_meta()
	if not utils.file_exists(self.meta_path) then
		return {
			created_at = nil,
			profile = nil,
			description = "",
			switch_count = 0,
			last_active = nil,
			tags = {},
		}
	end
	local content, err = utils.read_file(self.meta_path)
	if not content then
		log:warn("Cannot read metadata for '%s': %s", self.name, err)
		return {}
	end
	local ok, data = pcall(vim.json.decode, content)
	if ok and type(data) == "table" then return data end
	return {}
end

--- Save namespace metadata to .meta.json.
---
--- Encodes the table as pretty-printed JSON (one field per line).
---@param meta table Metadata table to persist
---@return boolean success Whether the file was written
function Namespace:save_meta(meta)
	local ok_encode, json = pcall(vim.json.encode, meta)
	if not ok_encode then
		log:error("Cannot encode metadata for '%s'", self.name)
		return false
	end
	-- Pretty-print JSON for human readability
	local formatted = json:gsub(",", ",\n  "):gsub("{", "{\n  "):gsub("}", "\n}")
	local ok, err = utils.write_file(self.meta_path, formatted)
	if not ok then
		log:error("Cannot write metadata for '%s': %s", self.name, err)
		return false
	end
	return true
end

--- Record a switch event in metadata.
---
--- Increments switch_count and updates last_active timestamp.
--- Called by settings_manager:switch_user() after a successful switch.
---@return nil
function Namespace:record_switch()
	local meta = self:load_meta()
	meta.switch_count = (meta.switch_count or 0) + 1
	meta.last_active = os.date("%Y-%m-%d %H:%M:%S")
	self:save_meta(meta)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- MODULE LOADING
--
-- Functions to load user-specific Lua modules (settings, keymaps, init).
-- All loading is done via safe_require to prevent errors in one
-- namespace from breaking the entire configuration.
-- ═══════════════════════════════════════════════════════════════════════════

--- Load user settings (returns the table or empty table).
---
--- Uses safe_require to load `users.<name>.settings`.
--- Returns an empty table if the module doesn't exist or errors.
---@return table settings User settings table (may be empty)
function Namespace:load_settings()
	local modname = string.format("users.%s.settings", self.name)
	local mod, err = utils.safe_require(modname)
	if mod and type(mod) == "table" then return mod end
	if err then log:debug("No settings for namespace '%s': %s", self.name, err) end
	return {}
end

--- Load and execute user keymaps.
---
--- Requires `users.<name>.keymaps` and calls its `setup()` function
--- if the module exists and has one. Called during user switch.
---@return nil
function Namespace:load_keymaps()
	local modname = string.format("users.%s.keymaps", self.name)
	local mod, _ = utils.safe_require(modname)
	if mod and type(mod) == "table" and mod.setup then
		mod.setup()
		log:debug("Loaded keymaps for namespace '%s'", self.name)
	end
end

--- Load and execute user init module.
---
--- Requires `users.<name>` and calls its `setup()` function
--- if the module exists and has one. Called during bootstrap
--- for the active user.
---@return nil
function Namespace:load_init()
	local modname = string.format("users.%s", self.name)
	local mod, _ = utils.safe_require(modname)
	if mod and type(mod) == "table" and mod.setup then
		mod.setup()
		log:debug("Loaded init for namespace '%s'", self.name)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HEALTH CHECK
--
-- Validates the integrity of a namespace by checking:
-- 1. Directory existence
-- 2. init.lua loads without errors
-- 3. settings.lua returns a table
-- 4. keymaps.lua has a setup() function
-- 5. All plugin files are valid Lua
-- 6. Metadata is present and populated
--
-- Used by :UserHealth command and during namespace diagnostics.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run a health check on this namespace.
---
--- Validates directory structure, file syntax, module contracts,
--- and metadata presence. Returns a structured report with
--- per-check status (ok/error) and detail strings.
---@return table report `{ ok: boolean, checks: { name: string, status: string, detail: string }[] }`
function Namespace:health_check()
	local checks = {}

	--- Add a check result to the report.
	---@param name string Check name
	---@param ok boolean Whether the check passed
	---@param detail string Human-readable detail
	local function add(name, ok, detail)
		checks[#checks + 1] = {
			name = name,
			status = ok and "ok" or "error",
			detail = detail,
		}
	end

	-- ── Check 1: Directory exists ─────────────────────────────────────
	add("Directory", self:exists(), self.path)

	-- ── Check 2: init.lua ─────────────────────────────────────────────
	if utils.file_exists(self.init_path) then
		local ok, err = pcall(dofile, self.init_path)
		add("init.lua", ok, ok and "Loads without errors" or tostring(err))
	else
		add("init.lua", false, "File missing")
	end

	-- ── Check 3: settings.lua ─────────────────────────────────────────
	if utils.file_exists(self.settings_path) then
		local ok, result = pcall(dofile, self.settings_path)
		if ok and type(result) == "table" then
			add("settings.lua", true, string.format("Valid table (%d keys)", utils.tbl_count(result)))
		else
			add("settings.lua", false, ok and "Does not return a table" or tostring(result))
		end
	else
		add("settings.lua", false, "File missing")
	end

	-- ── Check 4: keymaps.lua ──────────────────────────────────────────
	if utils.file_exists(self.keymaps_path) then
		local ok, result = pcall(dofile, self.keymaps_path)
		if ok and type(result) == "table" and result.setup then
			add("keymaps.lua", true, "Valid module with setup()")
		else
			add("keymaps.lua", false, ok and "Missing setup() function" or tostring(result))
		end
	else
		add("keymaps.lua", false, "File missing")
	end

	-- ── Check 5: plugins/ ─────────────────────────────────────────────
	if utils.dir_exists(self.plugins_path) then
		local files = utils.list_dir(self.plugins_path, "file")
		local lua_count = 0
		local errors = {}
		for _, f in ipairs(files) do
			if utils.ends_with(f, ".lua") then
				lua_count = lua_count + 1
				local fpath = platform:path_join(self.plugins_path, f)
				local ok, err = pcall(dofile, fpath)
				if not ok then errors[#errors + 1] = f .. ": " .. tostring(err) end
			end
		end
		if #errors > 0 then
			add("plugins/", false, string.format("%d files, %d errors: %s", lua_count, #errors, errors[1]))
		else
			add("plugins/", true, string.format("%d plugin files, all valid", lua_count))
		end
	else
		add("plugins/", false, "Directory missing")
	end

	-- ── Check 6: Metadata ─────────────────────────────────────────────
	local meta = self:load_meta()
	add(
		"Metadata",
		meta.created_at ~= nil,
		meta.created_at and string.format("Created %s, %d switches", meta.created_at, meta.switch_count or 0)
			or "No metadata (legacy namespace)"
	)

	-- ── Overall result ────────────────────────────────────────────────
	local all_ok = true
	for _, c in ipairs(checks) do
		if c.status ~= "ok" then
			all_ok = false
			break
		end
	end

	return { ok = all_ok, checks = checks }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EXPORT / IMPORT
--
-- Serializes/deserializes a namespace to/from JSON.
-- Export captures: version, name, timestamp, metadata, and all
-- file contents (init, settings, keymaps, plugins/*.lua).
-- Import recreates the directory structure and writes all files.
--
-- The export format is self-contained — it includes file contents
-- as strings, not file paths, so it can be transferred between
-- machines or stored in version control.
-- ═══════════════════════════════════════════════════════════════════════════

--- Export namespace to a JSON-serializable table.
---
--- Captures all files (init.lua, settings.lua, keymaps.lua, plugins/*.lua)
--- as string content, plus metadata and version information.
---@return table export_data Serializable table with `version`, `name`, `exported_at`, `meta`, `files`
function Namespace:export()
	local data = {
		version = _G.NvimConfig and _G.NvimConfig.version or "unknown",
		name = self.name,
		exported_at = os.date("%Y-%m-%d %H:%M:%S"),
		meta = self:load_meta(),
		files = {},
	}

	-- ── Collect all files ─────────────────────────────────────────────
	local all_files = {
		{ key = "init.lua", path = self.init_path },
		{ key = "settings.lua", path = self.settings_path },
		{ key = "keymaps.lua", path = self.keymaps_path },
	}

	-- ── Add plugin files ──────────────────────────────────────────────
	if utils.dir_exists(self.plugins_path) then
		local plugin_files = utils.list_dir(self.plugins_path, "file")
		for _, f in ipairs(plugin_files) do
			if utils.ends_with(f, ".lua") then
				all_files[#all_files + 1] = {
					key = "plugins/" .. f,
					path = platform:path_join(self.plugins_path, f),
				}
			end
		end
	end

	-- ── Read file contents ────────────────────────────────────────────
	for _, entry in ipairs(all_files) do
		if utils.file_exists(entry.path) then
			local content = utils.read_file(entry.path)
			if content then data.files[entry.key] = content end
		end
	end

	return data
end

--- Export namespace to a JSON file on disk.
---@param output_path string Absolute path for the output JSON file
---@return boolean success Whether the file was written
---@return string|nil error Error message if failed
function Namespace:export_to_file(output_path)
	local data = self:export()
	local ok_encode, json = pcall(vim.json.encode, data)
	if not ok_encode then return false, "JSON encode failed" end
	return utils.write_file(output_path, json)
end

--- Import namespace from a JSON file.
---
--- Creates a new namespace from the exported data. Validates the
--- target name, creates directory structure, writes all files,
--- and saves import provenance in metadata.
---@param import_path string Path to the JSON file to import
---@param target_name? string Override the namespace name (default: name from JSON)
---@return boolean success Whether the import completed
---@return string|nil error Error message if failed
function Namespace:import_from_file(import_path, target_name)
	-- ── Read and parse JSON ───────────────────────────────────────────
	local content, read_err = utils.read_file(import_path)
	if not content then return false, "Cannot read import file: " .. (read_err or "unknown") end

	local ok_decode, data = pcall(vim.json.decode, content)
	if not ok_decode or type(data) ~= "table" then return false, "Invalid JSON in import file" end

	-- ── Resolve and validate name ─────────────────────────────────────
	local name = target_name or data.name
	if not name then return false, "No namespace name in import data" end

	local valid, err = security:validate_namespace(name)
	if not valid then return false, err end

	-- ── Create namespace structure ────────────────────────────────────
	local ns = Namespace:new(name)
	if ns:exists() then return false, string.format("Namespace '%s' already exists", name) end

	vim.fn.mkdir(ns.path, "p")
	vim.fn.mkdir(ns.plugins_path, "p")

	-- ── Write all files ───────────────────────────────────────────────
	if data.files then
		for key, file_content in pairs(data.files) do
			local target_path
			if utils.starts_with(key, "plugins/") then
				target_path = platform:path_join(ns.plugins_path, key:sub(9))
			else
				target_path = platform:path_join(ns.path, key)
			end
			local write_ok, write_err = utils.write_file(target_path, file_content)
			if not write_ok then log:warn("Failed to write %s: %s", key, write_err) end
		end
	end

	-- ── Save metadata with import provenance ──────────────────────────
	local meta = data.meta or {}
	meta.imported_at = os.date("%Y-%m-%d %H:%M:%S")
	meta.imported_from = data.name
	meta.switch_count = 0
	ns:save_meta(meta)

	log:info("Imported namespace '%s' from '%s'", name, import_path)
	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CLONE
--
-- Creates a deep copy of a namespace under a new name.
-- Uses export() → import pattern with name substitution in file
-- content (replaces all occurrences of the old name with the new one).
-- ═══════════════════════════════════════════════════════════════════════════

--- Clone this namespace to a new name.
---
--- Exports all files, substitutes the namespace name in content,
--- writes to the target directory, and saves provenance metadata.
---@param new_name string Target namespace name
---@return boolean success Whether the clone completed
---@return string|nil error Error message if failed
function Namespace:clone(new_name)
	-- ── Validate target name ──────────────────────────────────────────
	local valid, err = security:validate_namespace(new_name)
	if not valid then return false, err end

	local target = Namespace:new(new_name)
	if target:exists() then return false, string.format("Namespace '%s' already exists", new_name) end

	if not self:exists() then return false, string.format("Source namespace '%s' does not exist", self.name) end

	-- ── Export source ─────────────────────────────────────────────────
	local data = self:export()
	data.name = new_name

	-- ── Create target structure ───────────────────────────────────────
	vim.fn.mkdir(target.path, "p")
	vim.fn.mkdir(target.plugins_path, "p")

	-- ── Write files with name substitution ────────────────────────────
	if data.files then
		for key, content in pairs(data.files) do
			local updated_content = content:gsub(self.name, new_name)
			local target_path
			if utils.starts_with(key, "plugins/") then
				target_path = platform:path_join(target.plugins_path, key:sub(9))
			else
				target_path = platform:path_join(target.path, key)
			end
			utils.write_file(target_path, updated_content)
		end
	end

	-- ── Save metadata with clone provenance ───────────────────────────
	local meta = self:load_meta()
	meta.created_at = os.date("%Y-%m-%d %H:%M:%S")
	meta.cloned_from = self.name
	meta.switch_count = 0
	meta.last_active = nil
	target:save_meta(meta)

	log:info("Cloned namespace '%s' → '%s'", self.name, new_name)
	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE / DELETE
--
-- Lifecycle operations that create or destroy namespace directories.
-- create() generates the full directory structure with template files.
-- delete() removes the directory recursively after safety checks.
-- ═══════════════════════════════════════════════════════════════════════════

--- Create the namespace directory structure and template files.
---
--- Generates: init.lua, settings.lua (with optional profile overrides),
--- keymaps.lua, plugins/init.lua, and .meta.json.
---
--- Validates the namespace name via core.security before creating
--- any files to prevent path traversal or invalid names.
---@param profile? string Optional profile name from PROFILES table
---@return boolean success Whether creation completed
---@return string|nil error Error message if failed
function Namespace:create(profile)
	-- ── Validate name ─────────────────────────────────────────────────
	local valid, err = security:validate_namespace(self.name)
	if not valid then return false, err end

	if self:exists() then return false, string.format("Namespace '%s' already exists", self.name) end

	-- ── Create directories ────────────────────────────────────────────
	vim.fn.mkdir(self.path, "p")
	vim.fn.mkdir(self.plugins_path, "p")

	-- ── Resolve profile settings ──────────────────────────────────────
	local profile_settings = nil
	local profile_data = profile and self.PROFILES[profile]
	if profile_data then profile_settings = profile_data.settings end

	-- ── Write template files ──────────────────────────────────────────
	local ok, write_err

	-- init.lua
	ok, write_err = utils.write_file(self.init_path, self:_template_init())
	if not ok then return false, write_err end

	-- settings.lua (with profile overrides if specified)
	ok, write_err = utils.write_file(self.settings_path, self:_template_settings(profile_settings))
	if not ok then return false, write_err end

	-- keymaps.lua
	ok, write_err = utils.write_file(self.keymaps_path, self:_template_keymaps())
	if not ok then return false, write_err end

	-- plugins/init.lua
	local plugins_init = platform:path_join(self.plugins_path, "init.lua")
	ok, write_err = utils.write_file(plugins_init, self:_template_plugins())
	if not ok then return false, write_err end

	-- ── Save metadata ─────────────────────────────────────────────────
	self:save_meta({
		created_at = os.date("%Y-%m-%d %H:%M:%S"),
		profile = profile,
		description = profile_data and profile_data.description or "",
		switch_count = 0,
		last_active = nil,
		tags = {},
	})

	log:info("Created namespace '%s' (profile: %s) at %s", self.name, profile or "none", self.path)
	return true, nil
end

--- Delete the namespace directory.
---
--- Safety checks:
--- 1. Cannot delete the "default" namespace
--- 2. Namespace must exist
--- 3. Namespace must not be locked
---
--- After deletion, clears all cached Lua modules for this namespace.
---@return boolean success Whether deletion completed
---@return string|nil error Error message if failed
function Namespace:delete()
	-- ── Safety checks ─────────────────────────────────────────────────
	if self.name == "default" then return false, "Cannot delete the 'default' namespace" end

	if not self:exists() then return false, string.format("Namespace '%s' does not exist", self.name) end

	if self:is_locked() then
		return false, string.format("Namespace '%s' is locked. Unlock it first with :UserUnlock %s", self.name, self.name)
	end

	-- ── Remove directory recursively ──────────────────────────────────
	local ok = vim.fn.delete(self.path, "rf")
	if ok ~= 0 then return false, string.format("Failed to delete namespace directory: %s", self.path) end

	-- ── Clear cached modules ──────────────────────────────────────────
	self:_clear_module_cache()

	log:info("Deleted namespace '%s'", self.name)
	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INTERNAL HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Clear Lua require cache for this namespace's modules.
---
--- Removes all `package.loaded` entries prefixed with `users.<name>`.
--- This ensures that a recreated or switched namespace loads fresh
--- modules instead of stale cached versions.
---@return nil
---@private
function Namespace:_clear_module_cache()
	local prefix = "users." .. self.name
	for modname, _ in pairs(package.loaded) do
		if utils.starts_with(modname, prefix) then package.loaded[modname] = nil end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INFO
-- ═══════════════════════════════════════════════════════════════════════════

--- Get a detailed summary of this namespace.
---
--- Aggregates existence checks, file counts, directory size,
--- and all metadata into a single table for display by
--- :UserInfo and :UserList commands.
---@return table info Summary table with all namespace properties
function Namespace:info()
	local meta = self:load_meta()

	-- ── Count plugin files ────────────────────────────────────────────
	local plugin_count = 0
	if utils.dir_exists(self.plugins_path) then
		for _, f in ipairs(utils.list_dir(self.plugins_path, "file")) do
			if utils.ends_with(f, ".lua") then plugin_count = plugin_count + 1 end
		end
	end

	-- ── Calculate directory size ──────────────────────────────────────
	local total_size = 0
	if self:exists() then
		local files = utils.list_files_recursive(self.path, "%.lua$")
		for _, f in ipairs(files) do
			local size = utils.file_size(platform:path_join(self.path, f))
			if size then total_size = total_size + size end
		end
	end

	return {
		-- ── Identity ──────────────────────────────────────────────────
		name = self.name,
		path = self.path,
		-- ── Status ────────────────────────────────────────────────────
		exists = self:exists(),
		has_settings = self:has_settings(),
		has_keymaps = self:has_keymaps(),
		has_plugins = self:has_plugins(),
		is_locked = self:is_locked(),
		-- ── Metrics ───────────────────────────────────────────────────
		plugin_count = plugin_count,
		total_size = total_size,
		-- ── Metadata ──────────────────────────────────────────────────
		created_at = meta.created_at,
		profile = meta.profile,
		description = meta.description or "",
		switch_count = meta.switch_count or 0,
		last_active = meta.last_active,
		tags = meta.tags or {},
		cloned_from = meta.cloned_from,
		imported_from = meta.imported_from,
	}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TEMPLATE GENERATORS
--
-- Private methods that produce boilerplate file content for new
-- namespaces. Each returns a string that is written to disk by create().
--
-- Templates include:
--   _template_init()             → init.lua with setup() stub
--   _template_settings(profile?) → settings.lua with profile overrides
--   _template_keymaps()          → keymaps.lua with setup() stub
--   _template_plugins()          → plugins/init.lua with examples
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate init.lua template content.
---@return string content Template file content
---@private
function Namespace:_template_init()
	return string.format(
		[=[-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  User namespace: %s
-- ║  This file is loaded when this user is active.
-- ╚══════════════════════════════════════════════════════════════════╝

local M = {}

--- Called after plugins are loaded when this user is active.
function M.setup()
  -- Add any post-plugin initialization here.
  -- Example: custom highlights, autocmds, etc.
end

return M
]=],
		self.name
	)
end

--- Generate settings.lua template content.
---
--- If a profile is specified, its settings are serialized as Lua
--- code and embedded in the template. Otherwise, commented-out
--- examples are provided.
---@param profile_settings? table Profile settings table to embed
---@return string content Template file content
---@private
function Namespace:_template_settings(profile_settings)
	local overrides = ""
	if profile_settings then
		-- ── Generate Lua code from profile settings ───────────────────
		local lines = {}
		for section, values in pairs(profile_settings) do
			if type(values) == "table" then
				lines[#lines + 1] = string.format("  %s = {", section)
				for k, v in pairs(values) do
					if type(v) == "string" then
						lines[#lines + 1] = string.format('    %s = "%s",', k, v)
					elseif type(v) == "table" then
						local items = {}
						for _, item in ipairs(v) do
							items[#items + 1] = string.format('"%s"', item)
						end
						lines[#lines + 1] = string.format("    %s = { %s },", k, table.concat(items, ", "))
					else
						lines[#lines + 1] = string.format("    %s = %s,", k, tostring(v))
					end
				end
				lines[#lines + 1] = "  },"
			end
		end
		overrides = table.concat(lines, "\n")
	end

	return string.format(
		[=[-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  User settings: %s
-- ║                                                                  ║
-- ║  These values are deep-merged over the root settings.lua.        ║
-- ║  Only include keys you want to override.                         ║
-- ╚══════════════════════════════════════════════════════════════════╝

---@type NvimEnterpriseSettings
return {
%s
}
]=],
		self.name,
		overrides ~= "" and overrides
			or [[  -- Add your overrides here
  -- Example:
  -- ui = {
  --   colorscheme = "tokyonight",
  -- },]]
	)
end

--- Generate keymaps.lua template content.
---@return string content Template file content
---@private
function Namespace:_template_keymaps()
	return string.format(
		[=[-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  User keymaps: %s
-- ║                                                                  ║
-- ║  Applied AFTER default keymaps. Can override or extend them.     ║
-- ╚══════════════════════════════════════════════════════════════════╝

local M = {}

--- Set up user-specific key mappings.
function M.setup()
  -- local map = vim.keymap.set

  -- Example:
  -- map("n", "<leader>xx", function()
  --   vim.notify("Hello from %s!")
  -- end, { desc = "Custom greeting" })
end

return M
]=],
		self.name,
		self.name
	)
end

--- Generate plugins/init.lua template content.
---@return string content Template file content
---@private
function Namespace:_template_plugins()
	return string.format(
		[=[-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  User plugins: %s
-- ║                                                                  ║
-- ║  Add custom lazy.nvim plugin specs here.                         ║
-- ║  These are loaded IN ADDITION to the default plugins.            ║
-- ║  To override a default plugin's config, use the same repo name. ║
-- ╚══════════════════════════════════════════════════════════════════╝

return {
  -- Example: add a new plugin
  -- {
  --   "tpope/vim-fugitive",
  --   cmd = { "Git", "Gstatus", "Gblame" },
  -- },
}
]=],
		self.name
	)
end

return Namespace
