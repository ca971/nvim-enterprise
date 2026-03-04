---@file lua/users/user_manager.lua
---@description UserManager — CRUD operations and orchestration for user namespaces
---@module "users.user_manager"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.class               OOP base class (Class:extend)
---@see core.utils               File I/O, string helpers, table utilities, deep_equal
---@see core.platform            Platform detection (path_join, config_dir)
---@see core.security            Namespace name validation
---@see core.logger              Structured logging utility
---@see users.namespace          Individual namespace abstraction (Namespace class)
---@see config.settings_manager  High-level settings orchestrator (uses UserManager)
---@see core.settings            Active user resolution, auto_switch preference
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  users/user_manager.lua — Namespace CRUD & orchestration                 ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  UserManager (singleton, Class-based)                            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Relationship to Namespace:                                      │    ║
--- ║  │  ├─ UserManager = orchestrator (operations across namespaces)    │    ║
--- ║  │  └─ Namespace   = data object (single namespace abstraction)     │    ║
--- ║  │                                                                  │    ║
--- ║  │  CRUD Operations:                                                │    ║
--- ║  │  ├─ create(name, profile?)   Validate + delegate to Namespace    │    ║
--- ║  │  ├─ delete(name)             Safety checks + delegate            │    ║
--- ║  │  ├─ clone(source, target)    Delegate to Namespace:clone()       │    ║
--- ║  │  ├─ exists(name)             Existence check                     │    ║
--- ║  │  ├─ get(name)                Get Namespace instance              │    ║
--- ║  │  ├─ list()                   Sorted list of namespace names      │    ║
--- ║  │  ├─ list_detailed()          Full info for all namespaces        │    ║
--- ║  │  └─ info(name)               Detailed info + is_active flag      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Export / Import:                                                │    ║
--- ║  │  ├─ export(name, path?)      → JSON file (default: ~/Downloads)  │    ║
--- ║  │  └─ import(path, name?)      ← JSON file → new namespace         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Comparison:                                                     │    ║
--- ║  │  └─ diff(name_a, name_b)     Flatten + compare settings          │    ║
--- ║  │     → { only_a, only_b, different, same }                        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Health & Stats:                                                 │    ║
--- ║  │  ├─ health_check(name)       Delegate to Namespace               │    ║
--- ║  │  ├─ stats()                  Aggregated statistics               │    ║
--- ║  │  │  ├─ total_namespaces, total_switches, total_size              │    ║
--- ║  │  │  ├─ most_used (name + count)                                  │    ║
--- ║  │  │  ├─ last_switch (name + time)                                 │    ║
--- ║  │  │  ├─ profiles_used (profile → count)                           │    ║
--- ║  │  │  └─ available_profiles                                        │    ║
--- ║  │  └─ list_profiles()          Profile names + descriptions        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Project Auto-Switch:                                            │    ║
--- ║  │  ├─ detect_project_user()    Search for .nvimuser / .nvim-user   │    ║
--- ║  │  │  └─ Walks upward from cwd to root                             │    ║
--- ║  │  └─ setup_auto_switch()      DirChanged autocmd registration     │    ║
--- ║  │     └─ Triggers settings_manager:switch_user() on match          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Bootstrap:                                                      │    ║
--- ║  │  └─ ensure_default()         Create "default" if missing         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Reserved Files (excluded from namespace listing):               │    ║
--- ║  │  ├─ init.lua                                                     │    ║
--- ║  │  ├─ user_manager.lua                                             │    ║
--- ║  │  └─ namespace.lua                                                │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Diff Algorithm:                                                         ║
--- ║  ├─ Both settings tables are flattened to dot-notation keys              ║
--- ║  │  (e.g. `ui.colorscheme`, `editor.tab_size`)                           ║
--- ║  ├─ Lists are NOT flattened (compared as atomic values)                  ║
--- ║  ├─ Comparison uses utils.deep_equal for value equality                  ║
--- ║  └─ Result: { only_a, only_b, different: {a,b}, same }                   ║
--- ║                                                                          ║
--- ║  Auto-Switch Flow:                                                       ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  DirChanged event                                                │    ║
--- ║  │  └─ detect_project_user()                                        │    ║
--- ║  │     ├─ Search .nvimuser / .nvim-user upward from cwd             │    ║
--- ║  │     ├─ Read file content → trim → validate existence             │    ║
--- ║  │     └─ If found and different from current:                      │    ║
--- ║  │        └─ vim.schedule → settings_manager:switch_user()          │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Singleton:                                                              ║
--- ║  • One instance per session via get_instance()                           ║
--- ║  • Accessed by settings_manager via require("users.user_manager")        ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local Class = require("core.class")
local utils = require("core.utils")
local platform = require("core.platform")
local security = require("core.security")
local Namespace = require("users.namespace")
local Logger = require("core.logger")

local log = Logger:for_module("users.user_manager")

-- ═══════════════════════════════════════════════════════════════════════════
-- CLASS DEFINITION
-- ═══════════════════════════════════════════════════════════════════════════

---@class UserManager : Class
local UserManager = Class:extend("UserManager")

-- ═══════════════════════════════════════════════════════════════════════════
-- INTERNAL HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Get the base directory for all user namespaces.
---
--- Returns the absolute path to `lua/users/` inside the Neovim
--- config directory.
---@return string path Absolute path to the users directory
---@private
function UserManager:_users_dir()
	return platform:path_join(platform.config_dir, "lua", "users")
end

--- Files in the users directory that are NOT namespace directories.
--- Used by list() to exclude framework files from namespace listing.
---@type table<string, boolean>
UserManager.RESERVED_FILES = {
	["init.lua"] = true,
	["user_manager.lua"] = true,
	["namespace.lua"] = true,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- LISTING & ACCESS
--
-- Functions to enumerate and access user namespaces.
-- list() scans the users directory for subdirectories,
-- filtering out reserved files and hidden directories.
-- ═══════════════════════════════════════════════════════════════════════════

--- List all existing user namespace names.
---
--- Scans the `lua/users/` directory for subdirectories, filtering out
--- reserved files (init.lua, user_manager.lua, namespace.lua) and
--- hidden directories (prefixed with `.`).
---@return string[] names Sorted list of namespace names
function UserManager:list()
	local users_dir = self:_users_dir()
	if not utils.dir_exists(users_dir) then return {} end

	local entries = utils.list_dir(users_dir, "directory")
	local names = {}
	for _, entry in ipairs(entries) do
		if not self.RESERVED_FILES[entry] and not utils.starts_with(entry, ".") then table.insert(names, entry) end
	end

	table.sort(names)
	return names
end

--- Get a Namespace instance for a given user.
---
--- Does NOT check if the namespace exists — use exists() for that.
---@param name string User namespace name
---@return Namespace ns Namespace instance (may not exist on disk)
function UserManager:get(name)
	return Namespace:new(name)
end

--- Check if a user namespace exists on disk.
---@param name string User namespace name
---@return boolean exists True if the namespace directory exists
function UserManager:exists(name)
	local ns = Namespace:new(name)
	return ns:exists()
end

--- Get detailed info about a specific user namespace.
---
--- Delegates to Namespace:info() and adds the `is_active` flag
--- based on the current NvimConfig state.
---@param name string User namespace name
---@return table info Detailed namespace info with `is_active` field
function UserManager:info(name)
	local ns = Namespace:new(name)
	local info_data = ns:info()
	info_data.is_active = (_G.NvimConfig.state.active_user == name)
	return info_data
end

--- Get detailed info about all user namespaces.
---
--- Calls info() for each namespace returned by list().
---@return table[] infos Array of info tables (one per namespace)
function UserManager:list_detailed()
	local names = self:list()
	local infos = {}
	for _, name in ipairs(names) do
		table.insert(infos, self:info(name))
	end
	return infos
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CRUD OPERATIONS
--
-- Create, Delete, and Clone operations. Each validates inputs,
-- performs safety checks, and delegates to the Namespace class
-- for the actual file system operations.
-- ═══════════════════════════════════════════════════════════════════════════

--- Create a new user namespace.
---
--- Validates the namespace name and profile (if specified) before
--- delegating to Namespace:create(). Profile validation checks
--- against Namespace.PROFILES and provides helpful error messages.
---@param name string User namespace name (alphanumeric + hyphens)
---@param profile? string Optional profile name from Namespace.PROFILES
---@return boolean success Whether creation succeeded
---@return string|nil error Error message if failed
function UserManager:create(name, profile)
	-- ── Validate name ─────────────────────────────────────────────────
	local valid, err = security:validate_namespace(name)
	if not valid then return false, err end

	-- ── Validate profile ──────────────────────────────────────────────
	if profile and not Namespace.PROFILES[profile] then
		local available = vim.tbl_keys(Namespace.PROFILES)
		table.sort(available)
		return false, string.format("Unknown profile '%s'. Available: %s", profile, table.concat(available, ", "))
	end

	local ns = Namespace:new(name)
	return ns:create(profile)
end

--- Delete a user namespace.
---
--- Safety checks:
--- 1. Cannot delete the "default" namespace
--- 2. Namespace must exist
--- 3. Delegates lock check to Namespace:delete()
---@param name string User namespace name
---@return boolean success Whether deletion succeeded
---@return string|nil error Error message if failed
function UserManager:delete(name)
	if name == "default" then return false, "Cannot delete the 'default' namespace" end

	local ns = Namespace:new(name)
	if not ns:exists() then return false, string.format("User '%s' does not exist", name) end

	return ns:delete()
end

--- Clone a user namespace to a new name.
---
--- Validates source existence and delegates to Namespace:clone().
---@param source string Source namespace name
---@param target string Target namespace name
---@return boolean success Whether the clone completed
---@return string|nil error Error message if failed
function UserManager:clone(source, target)
	local ns = Namespace:new(source)
	if not ns:exists() then return false, string.format("Source namespace '%s' does not exist", source) end
	return ns:clone(target)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EXPORT / IMPORT
--
-- Serializes namespaces to/from JSON files for backup, sharing,
-- or transfer between machines. Export defaults to ~/Downloads/
-- if no output path is specified.
-- ═══════════════════════════════════════════════════════════════════════════

--- Export a user namespace to a JSON file.
---
--- Default output path: `~/Downloads/<name>.nvimuser.json`
---@param name string Namespace name to export
---@param output_path? string Output file path (default: ~/Downloads/<name>.nvimuser.json)
---@return boolean success Whether the export completed
---@return string|nil error_or_path Output path on success, error message on failure
function UserManager:export(name, output_path)
	local ns = Namespace:new(name)
	if not ns:exists() then return false, string.format("Namespace '%s' does not exist", name) end

	output_path = output_path
		or platform:path_join(vim.env.HOME or vim.fn.expand("~"), "Downloads", name .. ".nvimuser.json")

	local ok, err = ns:export_to_file(output_path)
	if ok then return true, output_path end
	return false, err
end

--- Import a user namespace from a JSON file.
---
--- Creates a temporary Namespace instance to call import_from_file().
--- The actual namespace name is resolved from the JSON content
--- or overridden by `target_name`.
---@param import_path string Path to the JSON file
---@param target_name? string Override namespace name (default: name from JSON)
---@return boolean success Whether the import completed
---@return string|nil error Error message if failed
function UserManager:import(import_path, target_name)
	local ns = Namespace:new(target_name or "import")
	return ns:import_from_file(import_path, target_name)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HEALTH CHECK
-- ═══════════════════════════════════════════════════════════════════════════

--- Run health check on a namespace.
---
--- Returns early with a failure report if the namespace doesn't exist.
--- Otherwise delegates to Namespace:health_check().
---@param name string Namespace name to check
---@return table report `{ ok: boolean, checks: { name, status, detail }[] }`
function UserManager:health_check(name)
	local ns = Namespace:new(name)
	if not ns:exists() then
		return {
			ok = false,
			checks = { { name = "Exists", status = "error", detail = "Namespace does not exist" } },
		}
	end
	return ns:health_check()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DIFF
--
-- Compares settings between two namespaces by:
-- 1. Loading both settings tables
-- 2. Flattening to dot-notation keys (e.g. "ui.colorscheme")
-- 3. Categorizing keys into: only_a, only_b, different, same
--
-- Lists (tables with integer keys) are compared as atomic values,
-- not flattened. This prevents false diffs on ordered collections
-- like `languages.enabled = { "lua", "python" }`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Diff settings between two namespaces.
---
--- Flattens both settings tables to dot-notation keys and compares
--- values using utils.deep_equal. Returns four categories:
--- • `only_a`: keys present only in namespace A
--- • `only_b`: keys present only in namespace B
--- • `different`: keys present in both with different values (`{ a, b }`)
--- • `same`: keys present in both with identical values
---@param name_a string First namespace name
---@param name_b string Second namespace name
---@return table diff `{ only_a: table, only_b: table, different: table<string, {a: any, b: any}>, same: table }`
function UserManager:diff(name_a, name_b)
	local ns_a = Namespace:new(name_a)
	local ns_b = Namespace:new(name_b)

	local settings_a = ns_a:load_settings()
	local settings_b = ns_b:load_settings()

	local result = {
		only_a = {},
		only_b = {},
		different = {},
		same = {},
	}

	--- Flatten a nested table to dot-notation keys.
	---
	--- Lists (integer-keyed tables) are kept as atomic values.
	---@param tbl table Table to flatten
	---@param prefix string|nil Key prefix for recursion
	---@return table<string, any> flat Flattened key-value pairs
	local function flatten(tbl, prefix)
		local flat = {}
		for k, v in pairs(tbl) do
			local key = prefix and (prefix .. "." .. k) or k
			if type(v) == "table" and not utils.is_list(v) then
				local sub = flatten(v, key)
				for sk, sv in pairs(sub) do
					flat[sk] = sv
				end
			else
				flat[key] = v
			end
		end
		return flat
	end

	local flat_a = flatten(settings_a)
	local flat_b = flatten(settings_b)

	-- ── Compare A against B ───────────────────────────────────────────
	for k, v in pairs(flat_a) do
		if flat_b[k] == nil then
			result.only_a[k] = v
		elseif not utils.deep_equal(v, flat_b[k]) then
			result.different[k] = { a = v, b = flat_b[k] }
		else
			result.same[k] = v
		end
	end

	-- ── Find keys only in B ───────────────────────────────────────────
	for k, v in pairs(flat_b) do
		if flat_a[k] == nil then result.only_b[k] = v end
	end

	return result
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STATISTICS
--
-- Aggregated metrics across all namespaces. Used by the :UserStats
-- command to display usage patterns and profile distribution.
-- ═══════════════════════════════════════════════════════════════════════════

--- Get aggregated statistics for all namespaces.
---
--- Iterates all namespaces and computes:
--- • Total count, switches, and disk size
--- • Most used namespace (by switch count)
--- • Last switched namespace (by timestamp)
--- • Profile distribution (profile name → user count)
--- • Available profile templates
---@return table stats Aggregated statistics table
function UserManager:stats()
	local names = self:list()
	local total_switches = 0
	local total_size = 0
	local most_used = { name = "none", count = 0 }
	local last_switch = { name = "none", time = nil }
	local profiles_used = {}

	for _, name in ipairs(names) do
		local info_data = self:info(name)

		-- ── Accumulate totals ─────────────────────────────────────────
		total_switches = total_switches + (info_data.switch_count or 0)
		total_size = total_size + (info_data.total_size or 0)

		-- ── Track most used ───────────────────────────────────────────
		if (info_data.switch_count or 0) > most_used.count then
			most_used = { name = name, count = info_data.switch_count }
		end

		-- ── Track last switch ─────────────────────────────────────────
		if info_data.last_active then
			if not last_switch.time or info_data.last_active > last_switch.time then
				last_switch = { name = name, time = info_data.last_active }
			end
		end

		-- ── Count profile usage ───────────────────────────────────────
		if info_data.profile then profiles_used[info_data.profile] = (profiles_used[info_data.profile] or 0) + 1 end
	end

	return {
		total_namespaces = #names,
		total_switches = total_switches,
		total_size = total_size,
		most_used = most_used,
		last_switch = last_switch,
		profiles_used = profiles_used,
		available_profiles = vim.tbl_keys(Namespace.PROFILES),
	}
end

--- Get available profile names and descriptions.
---
--- Returns a sorted list of profile metadata for display
--- by :UserProfiles and :UserCreate interactive mode.
---@return {name: string, description: string}[] profiles Sorted profile list
function UserManager:list_profiles()
	local profiles = {}
	for name, data in pairs(Namespace.PROFILES) do
		profiles[#profiles + 1] = {
			name = name,
			description = data.description,
		}
	end
	table.sort(profiles, function(a, b)
		return a.name < b.name
	end)
	return profiles
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PROJECT AUTO-SWITCH
--
-- Detects `.nvimuser` or `.nvim-user` files in the project hierarchy
-- and automatically switches to the specified user namespace when
-- changing directories. The file contains a single line: the namespace
-- name to activate.
--
-- Flow:
--   DirChanged event → detect_project_user() → settings_manager:switch_user()
--
-- Disabled by setting `users.auto_switch = false` in settings.lua.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect a project-specific user from `.nvimuser` or `.nvim-user` file.
---
--- Searches upward from the current working directory for marker files.
--- Reads the file content, trims whitespace, and validates that the
--- specified namespace exists.
---@return string|nil user_name Namespace name if found and valid, nil otherwise
function UserManager:detect_project_user()
	local markers = { ".nvimuser", ".nvim-user" }
	for _, marker in ipairs(markers) do
		local found = vim.fs.find(marker, {
			path = vim.fn.getcwd(),
			upward = true,
			type = "file",
		})[1]
		if found then
			local content = utils.read_file(found)
			if content then
				local name = utils.trim(content)
				if name ~= "" and self:exists(name) then return name end
			end
		end
	end
	return nil
end

--- Setup auto-switch based on `.nvimuser` project file.
---
--- Registers a `DirChanged` autocmd that calls detect_project_user()
--- on every directory change. If a project user is found and differs
--- from the current active user, triggers a switch via settings_manager.
---
--- Respects `users.auto_switch` setting (default: true).
---@return nil
function UserManager:setup_auto_switch()
	local curr_settings = require("core.settings")
	if not curr_settings:get("users.auto_switch", true) then return end

	vim.api.nvim_create_autocmd("DirChanged", {
		group = vim.api.nvim_create_augroup("NvimEnterprise_AutoUserSwitch", { clear = true }),
		callback = function()
			local project_user = self:detect_project_user()
			if project_user then
				local current = curr_settings:get("active_user", "default")
				if project_user ~= current then
					vim.schedule(function()
						local sm = require("config.settings_manager")
						local ok, err = sm:switch_user(project_user)
						if ok then
							log:info("Auto-switched to user '%s' (project .nvimuser)", project_user)
						else
							log:warn("Auto-switch failed: %s", err)
						end
					end)
				end
			end
		end,
		desc = "NvimEnterprise: Auto-switch user on directory change (.nvimuser)",
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOTSTRAP
--
-- Ensures the "default" namespace exists on first launch.
-- Called during core bootstrap before any user-related operations.
-- ═══════════════════════════════════════════════════════════════════════════

--- Ensure the default namespace exists.
---
--- Creates the "default" namespace with no profile if it doesn't
--- exist on disk. This guarantees there is always a valid fallback
--- namespace for the configuration to use.
---@return nil
function UserManager:ensure_default()
	local ns = Namespace:new("default")
	if not ns:exists() then
		log:info("Creating default user namespace...")
		local ok, err = ns:create()
		if not ok then log:error("Failed to create default namespace: %s", err) end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SINGLETON
--
-- Only one UserManager instance exists per session. The singleton
-- is created on first require and reused thereafter. Accessed by
-- settings_manager via require("users.user_manager").
-- ═══════════════════════════════════════════════════════════════════════════

---@type UserManager|nil
local _instance = nil

--- Get or create the singleton UserManager instance.
---@return UserManager instance The singleton instance
local function get_instance()
	if not _instance then _instance = UserManager:new() end
	return _instance --[[@as UserManager]]
end

return get_instance()
