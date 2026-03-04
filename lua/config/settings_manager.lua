---@file lua/config/settings_manager.lua
---@description SettingsManager — high-level settings & user namespace management
---@module "config.settings_manager"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings loader and accessor (low-level)
---@see core.options Neovim native options applicator
---@see core.icons Icon provider (command descriptions, notifications)
---@see core.class OOP base class (Class:extend)
---@see core.utils File I/O, string helpers, table utilities
---@see core.platform Platform detection (path_join, config_dir)
---@see core.logger Structured logging utility
---@see users.user_manager User namespace CRUD operations
---@see users.namespace Individual namespace abstraction (lock, meta, paths)
---@see config.colorscheme_manager Colorscheme application and commands
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  config/settings_manager.lua — High-level settings & user management     ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  SettingsManager (singleton, Class-based)                        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Orchestrates:                                                   │    ║
--- ║  │  ├─ User hot-swap at runtime (switch_user)                       │    ║
--- ║  │  │  1. Update active_user in root settings.lua                   │    ║
--- ║  │  │  2. Reload settings in memory                                 │    ║
--- ║  │  │  3. Re-apply Neovim options (deferred if special buffer)      │    ║
--- ║  │  │  4. Invalidate options cache                                  │    ║
--- ║  │  │  5. Load new user's keymaps                                   │    ║
--- ║  │  │  6. Apply new colorscheme                                     │    ║
--- ║  │  │  7. Record switch in metadata                                 │    ║
--- ║  │  │  8. Notify user                                               │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ User CRUD                                                    │    ║
--- ║  │  │  ├─ create_user(name, profile)                                │    ║
--- ║  │  │  ├─ delete_user(name)                                         │    ║
--- ║  │  │  ├─ list_users()                                              │    ║
--- ║  │  │  ├─ edit_user(name)                                           │    ║
--- ║  │  │  └─ edit_global_settings()                                    │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Vim Commands (21 commands)                                   │    ║
--- ║  │  │  ├─ :UserCreate <name> [profile]  Create namespace            │    ║
--- ║  │  │  ├─ :UserSwitch <name>            Hot-swap user               │    ║
--- ║  │  │  ├─ :UserDelete <name>            Delete namespace            │    ║
--- ║  │  │  ├─ :UserClone <src> <dst>        Clone namespace             │    ║
--- ║  │  │  ├─ :UserExport [name] [path]     Export to JSON              │    ║
--- ║  │  │  ├─ :UserImport <path> [name]     Import from JSON            │    ║
--- ║  │  │  ├─ :UserDiff [a] [b]             Compare settings            │    ║
--- ║  │  │  ├─ :UserLock <name>              Prevent deletion            │    ║
--- ║  │  │  ├─ :UserUnlock <name>            Allow deletion              │    ║
--- ║  │  │  ├─ :UserHealth [name]            Namespace health check      │    ║
--- ║  │  │  ├─ :UserStats                    Aggregate statistics        │    ║
--- ║  │  │  ├─ :UserList                     List all namespaces         │    ║
--- ║  │  │  ├─ :UserEdit [name]              Edit settings file          │    ║
--- ║  │  │  ├─ :UserInfo [name]              Detailed namespace info     │    ║
--- ║  │  │  ├─ :UserProfiles                 Available profiles          │    ║
--- ║  │  │  ├─ :Settings                     Open root settings.lua      │    ║
--- ║  │  │  └─ :SettingsReload               Reload settings from disk   │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Settings persistence                                         │    ║
--- ║  │  │  └─ _update_active_user_in_file (regex replace in .lua)       │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Project auto-switch (.nvimuser)                              │    ║
--- ║  │  │  └─ Delegated to user_manager:setup_auto_switch()             │    ║
--- ║  │  │                                                               │    ║
--- ║  │  └─ Colorscheme commands                                         │    ║
--- ║  │     └─ Delegated to colorscheme_manager:register_commands()      │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Special buffer handling:                                                ║
--- ║  • When switching users from a special buffer (dashboard, lazy, mason),  ║
--- ║    options.setup() is deferred to the next BufEnter on a normal buffer   ║
--- ║  • Leader keys are updated immediately regardless of buffer type         ║
--- ║  • This prevents errors from setting buffer-local options on nofile bufs ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Singleton pattern: one instance per session                           ║
--- ║  • user_manager accessed via lazy getter (not stored)                    ║
--- ║  • All commands use pcall for error resilience                           ║
--- ║  • Interactive mode (vim.ui.select/input) when args are omitted          ║
--- ║  • Completion functions return relevant lists for tab-completion         ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local Class = require("core.class")
local utils = require("core.utils")
local platform = require("core.platform")
local icons = require("core.icons")
local Logger = require("core.logger")

local log = Logger:for_module("config.settings_manager")

-- ═══════════════════════════════════════════════════════════════════════════
-- CLASS DEFINITION
-- ═══════════════════════════════════════════════════════════════════════════

---@class SettingsManager : Class
local SettingsManager = Class:extend("SettingsManager")

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTRUCTOR
-- ═══════════════════════════════════════════════════════════════════════════

--- Initialize the SettingsManager instance.
--- Loads the core.settings reference for all subsequent operations.
---@return nil
function SettingsManager:init()
	self._settings = require("core.settings")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INTERNAL HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Get the user_manager instance (lazy accessor).
---
--- Not stored as a field to avoid circular dependency issues
--- during early initialization.
---@return UserManager
---@private
function SettingsManager:_user_manager()
	return require("users.user_manager")
end

--- Update the `active_user` field in root `settings.lua` on disk.
---
--- Uses regex replacement to find `active_user = "..."` and replace
--- the value. This preserves all other settings and formatting.
---@param new_user string New user name to write
---@return boolean success Whether the file was updated
---@return string|nil error Error message if failed
---@private
function SettingsManager:_update_active_user_in_file(new_user)
	local path = platform:path_join(platform.config_dir, "settings.lua")
	local content, read_err = utils.read_file(path)
	if not content then return false, "Cannot read settings.lua: " .. (read_err or "unknown") end

	local new_content, count = content:gsub('(active_user%s*=%s*)"[^"]*"', '%1"' .. new_user .. '"')

	if count == 0 then return false, "Could not find 'active_user' field in settings.lua" end

	local ok, write_err = utils.write_file(path, new_content)
	if not ok then return false, "Cannot write settings.lua: " .. (write_err or "unknown") end

	log:info("Updated active_user in settings.lua to '%s'", new_user)
	return true, nil
end

--- Display a diff between two user namespaces.
---@param name_a string First user name
---@param name_b string Second user name
---@return nil
---@private
function SettingsManager:_show_diff(name_a, name_b)
	local diff = self:_user_manager():diff(name_a, name_b)
	local lines = {
		string.format("%s Settings Diff: %s vs %s", icons.ui.Diff, name_a, name_b),
		string.rep("─", 55),
	}

	local only_a_count = utils.tbl_count(diff.only_a)
	local only_b_count = utils.tbl_count(diff.only_b)
	local diff_count = utils.tbl_count(diff.different)
	local same_count = utils.tbl_count(diff.same)

	lines[#lines + 1] = string.format(
		"  %s %d same  %s %d different  %s %d only in %s  %s %d only in %s",
		icons.ui.Check,
		same_count,
		icons.diagnostics.Warn,
		diff_count,
		icons.ui.BoldArrowRight,
		only_a_count,
		name_a,
		icons.ui.BoldArrowLeft,
		only_b_count,
		name_b
	)
	lines[#lines + 1] = ""

	if diff_count > 0 then
		lines[#lines + 1] = "  Different values:"
		for k, v in pairs(diff.different) do
			lines[#lines + 1] = string.format("    %s:", k)
			lines[#lines + 1] = string.format("      %s: %s", name_a, vim.inspect(v.a):gsub("\n", " "))
			lines[#lines + 1] = string.format("      %s: %s", name_b, vim.inspect(v.b):gsub("\n", " "))
		end
		lines[#lines + 1] = ""
	end

	if only_a_count > 0 then
		lines[#lines + 1] = string.format("  Only in %s:", name_a)
		for k, v in pairs(diff.only_a) do
			lines[#lines + 1] = string.format("    %s = %s", k, vim.inspect(v):gsub("\n", " "))
		end
		lines[#lines + 1] = ""
	end

	if only_b_count > 0 then
		lines[#lines + 1] = string.format("  Only in %s:", name_b)
		for k, v in pairs(diff.only_b) do
			lines[#lines + 1] = string.format("    %s = %s", k, vim.inspect(v):gsub("\n", " "))
		end
	end

	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "NvimEnterprise — User Diff" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- USER MANAGEMENT
--
-- High-level user operations that orchestrate multiple subsystems:
-- settings, options, keymaps, colorscheme, metadata, notifications.
-- These are the methods called by Vim commands and external APIs.
-- ═══════════════════════════════════════════════════════════════════════════

--- Switch the active user at runtime (hot-swap).
---
--- Executes an 8-step pipeline:
--- 1. Update `active_user` in root `settings.lua` on disk
--- 2. Reload settings in memory
--- 3. Re-apply Neovim options (deferred if in a special buffer)
--- 4. Invalidate options cache
--- 5. Load new user's keymaps
--- 6. Apply new colorscheme
--- 7. Record switch in namespace metadata
--- 8. Notify user with summary
---@param name string Target user namespace name
---@return boolean success Whether the switch completed
---@return string|nil error Error message if failed
function SettingsManager:switch_user(name)
	local um = self:_user_manager()

	if not um:exists(name) then
		return false, string.format("User '%s' does not exist. Create it first with :UserCreate %s", name, name)
	end

	local current = self._settings:get("active_user", "default")
	if current == name then return false, string.format("User '%s' is already active", name) end

	-- ── Step 1: Update settings.lua on disk ──────────────────────────
	local ok, err = self:_update_active_user_in_file(name)
	if not ok then return false, err end

	-- ── Step 2: Reload settings in memory ────────────────────────────
	self._settings:reload(name)

	-- ── Step 3: Re-apply options (deferred if special buffer) ────────
	local cur_buf = vim.api.nvim_get_current_buf()
	local cur_bt = vim.bo[cur_buf].buftype
	local cur_ft = vim.bo[cur_buf].filetype
	local is_special = cur_bt == "nofile"
		or cur_ft == "dashboard"
		or cur_ft == "lazy"
		or cur_ft == "mason"
		or not vim.bo[cur_buf].modifiable

	if is_special then
		-- Defer options.setup() to next normal buffer
		local options_applied = false
		vim.api.nvim_create_autocmd("BufEnter", {
			once = true,
			callback = function()
				if not options_applied then
					options_applied = true
					local buf = vim.api.nvim_get_current_buf()
					if vim.bo[buf].buftype == "" and vim.bo[buf].modifiable then require("core.options").setup() end
				end
			end,
			desc = "NvimEnterprise: Deferred options.setup() after user switch",
		})
		-- Leader keys must be set immediately regardless
		vim.g.mapleader = self._settings:get("keymaps.leader", " ")
		vim.g.maplocalleader = self._settings:get("keymaps.local_leader", "\\")
	else
		require("core.options").setup()
	end

	-- ── Step 4: Invalidate options cache ─────────────────────────────
	local options = require("core.options")
	if options.invalidate_cache then options.invalidate_cache() end

	-- ── Step 5: Load new user's keymaps ──────────────────────────────
	local Namespace = require("users.namespace")
	local ns = Namespace:new(name)
	ns:load_keymaps()

	-- ── Step 6: Apply new colorscheme ────────────────────────────────
	local cs_ok, cs_manager = pcall(require, "config.colorscheme_manager")
	if cs_ok then cs_manager:apply() end

	-- ── Step 7: Record switch in metadata ────────────────────────────
	ns:record_switch()

	-- ── Step 8: Notify ───────────────────────────────────────────────
	vim.schedule(function()
		vim.notify(
			string.format(
				"%s Switched to user '%s'\n\n"
					.. "  %s Options & keymaps reloaded\n"
					.. "  %s Colorscheme applied\n"
					.. "  %s Plugin changes require :NvimRestart",
				icons.ui.User,
				name,
				icons.ui.Check,
				icons.ui.Check,
				icons.ui.Fire
			),
			vim.log.levels.INFO,
			{ title = "NvimEnterprise — User Switch" }
		)
	end)

	log:info("Switched active user from '%s' to '%s'", current, name)
	return true, nil
end

--- Create a new user namespace.
---@param name string Namespace name (alphanumeric + hyphens)
---@param profile? string Optional profile template to apply
---@return boolean success Whether creation succeeded
---@return string|nil error Error message if failed
function SettingsManager:create_user(name, profile)
	local um = self:_user_manager()
	local ok, err = um:create(name, profile)
	if ok then
		local profile_info = profile and (" (profile: " .. profile .. ")") or ""
		vim.schedule(function()
			vim.notify(
				string.format(
					"%s Created user namespace '%s'%s\n\n"
						.. "  Edit settings: :UserEdit %s\n"
						.. "  Switch to it:  :UserSwitch %s",
					icons.ui.Plus,
					name,
					profile_info,
					name,
					name
				),
				vim.log.levels.INFO,
				{ title = "NvimEnterprise — User Created" }
			)
		end)
	end
	return ok, err
end

--- Delete a user namespace.
---
--- If the target user is currently active, switches to "default" first.
---@param name string Namespace name to delete
---@return boolean success Whether deletion succeeded
---@return string|nil error Error message if failed
function SettingsManager:delete_user(name)
	local um = self:_user_manager()
	local current = self._settings:get("active_user", "default")

	-- Switch away if deleting the active user
	if current == name then
		local switch_ok, switch_err = self:switch_user("default")
		if not switch_ok then return false, "Cannot switch to default before deletion: " .. (switch_err or "unknown") end
	end

	local ok, err = um:delete(name)
	if ok then
		vim.schedule(function()
			vim.notify(
				string.format("%s Deleted user namespace '%s'", icons.ui.BoldClose, name),
				vim.log.levels.INFO,
				{ title = "NvimEnterprise — User Deleted" }
			)
		end)
	end
	return ok, err
end

--- List all user namespaces with status and features.
---@return nil
function SettingsManager:list_users()
	local um = self:_user_manager()
	local infos = um:list_detailed()
	local current = self._settings:get("active_user", "default")

	local lines = { "User Namespaces:\n" }
	for _, info in ipairs(infos) do
		local marker = info.name == current and icons.ui.BoldArrowRight or "  "
		local status = info.name == current and "(active)" or ""
		local features = {}
		if info.has_settings then table.insert(features, "settings") end
		if info.has_keymaps then table.insert(features, "keymaps") end
		if info.has_plugins then table.insert(features, "plugins") end
		if info.is_locked then table.insert(features, icons.ui.Lock .. "locked") end

		local meta_info = ""
		if info.profile then meta_info = meta_info .. " profile:" .. info.profile end
		if info.switch_count and info.switch_count > 0 then meta_info = meta_info .. " switches:" .. info.switch_count end

		table.insert(
			lines,
			string.format(
				"%s %s %s [%s]%s",
				marker,
				info.name,
				status,
				#features > 0 and table.concat(features, ", ") or "empty",
				meta_info
			)
		)
	end

	vim.schedule(function()
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = icons.ui.User .. " NvimEnterprise — Users" })
	end)
end

--- Open a user's settings file for editing.
---@param name? string User name (defaults to active user)
---@return nil
function SettingsManager:edit_user(name)
	name = name or self._settings:get("active_user", "default")
	local Namespace = require("users.namespace")
	local ns = Namespace:new(name)

	if not ns:exists() then
		vim.notify(
			string.format("User '%s' does not exist. Create it first with :UserCreate %s", name, name),
			vim.log.levels.WARN,
			{ title = "NvimEnterprise" }
		)
		return
	end

	vim.cmd("edit " .. ns.settings_path)
end

--- Open the root `settings.lua` for editing.
---@return nil
function SettingsManager:edit_global_settings()
	local path = platform:path_join(platform.config_dir, "settings.lua")
	vim.cmd("edit " .. path)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- VIM COMMANDS
--
-- Registers all user management commands. Each command supports both
-- direct invocation (:UserSwitch john) and interactive mode (omit args
-- to get a vim.ui.select/input prompt). Tab-completion is provided
-- where applicable.
--
-- Commands are registered once by config/init.lua after lazy.setup().
-- ═══════════════════════════════════════════════════════════════════════════

--- Register all user management and settings Vim commands.
---
--- Registers 17+ commands covering user CRUD, import/export,
--- diff, lock/unlock, health, stats, settings, and colorscheme.
--- Also sets up project-based auto-switch (.nvimuser) and
--- colorscheme commands via their respective managers.
---@return nil
function SettingsManager:register_commands()
	local self_ref = self
	local Namespace = require("users.namespace")

	-- ── :UserCreate <name> [profile] ─────────────────────────────────
	vim.api.nvim_create_user_command("UserCreate", function(cmd)
		local args = vim.split(utils.trim(cmd.args), "%s+")
		local name = args[1] or ""
		local profile = args[2]

		if name == "" then
			-- Interactive mode with profile selection
			vim.ui.input({ prompt = icons.ui.User .. " New user name: " }, function(input_name)
				if not input_name or input_name == "" then return end

				local profiles = self_ref:_user_manager():list_profiles()
				local choices = { "none (blank template)" }
				for _, p in ipairs(profiles) do
					choices[#choices + 1] = string.format("%s — %s", p.name, p.description)
				end

				vim.ui.select(choices, {
					prompt = icons.ui.Gear .. " Select profile:",
				}, function(_, idx)
					local selected_profile = nil
					if idx and idx > 1 then selected_profile = profiles[idx - 1].name end
					local create_ok, create_err = self_ref:create_user(input_name, selected_profile)
					if not create_ok then
						vim.notify(create_err or "Unknown error", vim.log.levels.ERROR, { title = "NvimEnterprise" })
					end
				end)
			end)
		else
			local create_ok, create_err = self_ref:create_user(name, profile)
			if not create_ok then
				vim.notify(create_err or "Unknown error", vim.log.levels.ERROR, { title = "NvimEnterprise" })
			end
		end
	end, {
		nargs = "*",
		desc = icons.ui.Plus .. " Create a new user namespace (optional: with profile)",
		complete = function(_, cmd_line)
			local args = vim.split(cmd_line, "%s+")
			if #args >= 3 then return vim.tbl_keys(Namespace.PROFILES) end
			return {}
		end,
	})

	-- ── :UserSwitch <name> ───────────────────────────────────────────
	vim.api.nvim_create_user_command("UserSwitch", function(cmd)
		local name = utils.trim(cmd.args)
		if name == "" then
			local users = self_ref:_user_manager():list()
			local current = self_ref._settings:get("active_user", "default")

			vim.ui.select(users, {
				prompt = icons.ui.User .. " Switch to user:",
				format_item = function(item)
					local ns = Namespace:new(item)
					local meta = ns:load_meta()
					local marker = item == current and "● " or "○ "
					local profile_tag = meta.profile and (" [" .. meta.profile .. "]") or ""
					local switch_info = meta.switch_count
							and meta.switch_count > 0
							and string.format(" (%d switches)", meta.switch_count)
						or ""
					return marker .. item .. profile_tag .. switch_info
				end,
			}, function(selected)
				if selected then
					local switch_ok, switch_err = self_ref:switch_user(selected)
					if not switch_ok then
						vim.notify(switch_err or "Unknown error", vim.log.levels.ERROR, { title = "NvimEnterprise" })
					end
				end
			end)
		else
			local switch_ok, switch_err = self_ref:switch_user(name)
			if not switch_ok then
				vim.notify(switch_err or "Unknown error", vim.log.levels.ERROR, { title = "NvimEnterprise" })
			end
		end
	end, {
		nargs = "?",
		desc = icons.ui.SignIn .. " Switch active user namespace",
		complete = function()
			return require("users.user_manager"):list()
		end,
	})

	-- ── :UserDelete <name> ───────────────────────────────────────────
	vim.api.nvim_create_user_command("UserDelete", function(cmd)
		local name = utils.trim(cmd.args)
		if name == "" then
			vim.notify("Usage: :UserDelete <name>", vim.log.levels.WARN, { title = "NvimEnterprise" })
			return
		end
		vim.ui.select({ "Yes, delete '" .. name .. "'", "No, cancel" }, {
			prompt = icons.ui.Fire .. " Delete user '" .. name .. "'? This cannot be undone.",
		}, function(choice)
			if choice and utils.starts_with(choice, "Yes") then
				local del_ok, del_err = self_ref:delete_user(name)
				if not del_ok then
					vim.notify(del_err or "Unknown error", vim.log.levels.ERROR, { title = "NvimEnterprise" })
				end
			else
				vim.notify("Deletion cancelled", vim.log.levels.INFO, { title = "NvimEnterprise" })
			end
		end)
	end, {
		nargs = "?",
		desc = icons.ui.BoldClose .. " Delete a user namespace",
		complete = function()
			local users = require("users.user_manager"):list()
			return vim.tbl_filter(function(u)
				return u ~= "default"
			end, users)
		end,
	})

	-- ── :UserClone <source> <target> ─────────────────────────────────
	vim.api.nvim_create_user_command("UserClone", function(cmd)
		local args = vim.split(utils.trim(cmd.args), "%s+")
		local source = args[1] or ""
		local target = args[2] or ""

		if source == "" or target == "" then
			-- Interactive mode
			local users = self_ref:_user_manager():list()
			vim.ui.select(users, {
				prompt = icons.ui.Copy .. " Clone from:",
			}, function(selected_source)
				if not selected_source then return end
				vim.ui.input({ prompt = "New namespace name: " }, function(new_name)
					if not new_name or new_name == "" then return end
					local clone_ok, clone_err = self_ref:_user_manager():clone(selected_source, new_name)
					if clone_ok then
						vim.notify(
							string.format("%s Cloned '%s' → '%s'", icons.ui.Check, selected_source, new_name),
							vim.log.levels.INFO,
							{ title = "NvimEnterprise" }
						)
					else
						vim.notify(clone_err or "Unknown error", vim.log.levels.ERROR, { title = "NvimEnterprise" })
					end
				end)
			end)
		else
			local clone_ok, clone_err = self_ref:_user_manager():clone(source, target)
			if clone_ok then
				vim.notify(
					string.format("%s Cloned '%s' → '%s'", icons.ui.Check, source, target),
					vim.log.levels.INFO,
					{ title = "NvimEnterprise" }
				)
			else
				vim.notify(clone_err or "Unknown error", vim.log.levels.ERROR, { title = "NvimEnterprise" })
			end
		end
	end, {
		nargs = "*",
		desc = icons.ui.Copy .. " Clone a user namespace",
		complete = function()
			return require("users.user_manager"):list()
		end,
	})

	-- ── :UserExport [name] [path] ────────────────────────────────────
	vim.api.nvim_create_user_command("UserExport", function(cmd)
		local args = vim.split(utils.trim(cmd.args), "%s+")
		local name = args[1] or self_ref._settings:get("active_user", "default")
		local output_path = args[2]

		local export_ok, result = self_ref:_user_manager():export(name, output_path)
		if export_ok then
			vim.notify(
				string.format("%s Exported '%s' to:\n  %s", icons.ui.Check, name, result),
				vim.log.levels.INFO,
				{ title = "NvimEnterprise — Export" }
			)
		else
			vim.notify(result or "Unknown error", vim.log.levels.ERROR, { title = "NvimEnterprise" })
		end
	end, {
		nargs = "*",
		desc = icons.documents.Export .. " Export user namespace to JSON",
		complete = function()
			return require("users.user_manager"):list()
		end,
	})

	-- ── :UserImport <path> [name] ────────────────────────────────────
	vim.api.nvim_create_user_command("UserImport", function(cmd)
		local args = vim.split(utils.trim(cmd.args), "%s+")
		local import_path = args[1] or ""
		local target_name = args[2]

		if import_path == "" then
			vim.notify("Usage: :UserImport <file.json> [name]", vim.log.levels.WARN, { title = "NvimEnterprise" })
			return
		end

		local import_ok, import_err = self_ref:_user_manager():import(import_path, target_name)
		if import_ok then
			vim.notify(
				string.format("%s Imported namespace from '%s'", icons.ui.Check, import_path),
				vim.log.levels.INFO,
				{ title = "NvimEnterprise — Import" }
			)
		else
			vim.notify(import_err or "Unknown error", vim.log.levels.ERROR, { title = "NvimEnterprise" })
		end
	end, {
		nargs = "+",
		desc = icons.documents.Import .. " Import user namespace from JSON",
		complete = "file",
	})

	-- ── :UserDiff [a] [b] ────────────────────────────────────────────
	vim.api.nvim_create_user_command("UserDiff", function(cmd)
		local args = vim.split(utils.trim(cmd.args), "%s+")
		local name_a = args[1]
		local name_b = args[2]

		if not name_a or not name_b then
			-- Interactive mode
			local users = self_ref:_user_manager():list()
			vim.ui.select(users, { prompt = "First user:" }, function(a)
				if not a then return end
				vim.ui.select(users, { prompt = "Compare with:" }, function(b)
					if not b then return end
					self_ref:_show_diff(a, b)
				end)
			end)
		else
			self_ref:_show_diff(name_a, name_b)
		end
	end, {
		nargs = "*",
		desc = icons.ui.Diff .. " Compare settings between two users",
		complete = function()
			return require("users.user_manager"):list()
		end,
	})

	-- ── :UserLock <name> ─────────────────────────────────────────────
	vim.api.nvim_create_user_command("UserLock", function(cmd)
		local name = utils.trim(cmd.args)
		if name == "" then name = self_ref._settings:get("active_user", "default") end
		local ns = Namespace:new(name)
		local lock_ok, lock_err = ns:lock()
		if lock_ok then
			vim.notify(
				string.format("%s Locked namespace '%s'", icons.ui.Lock, name),
				vim.log.levels.INFO,
				{ title = "NvimEnterprise" }
			)
		else
			vim.notify(lock_err or "Unknown error", vim.log.levels.ERROR, { title = "NvimEnterprise" })
		end
	end, {
		nargs = "?",
		desc = icons.ui.Lock .. " Lock a namespace (prevent deletion)",
		complete = function()
			return require("users.user_manager"):list()
		end,
	})

	-- ── :UserUnlock <name> ───────────────────────────────────────────
	vim.api.nvim_create_user_command("UserUnlock", function(cmd)
		local name = utils.trim(cmd.args)
		if name == "" then name = self_ref._settings:get("active_user", "default") end
		local ns = Namespace:new(name)
		local unlock_ok, unlock_err = ns:unlock()
		if unlock_ok then
			vim.notify(
				string.format("%s Unlocked namespace '%s'", icons.ui.Unlock, name),
				vim.log.levels.INFO,
				{ title = "NvimEnterprise" }
			)
		else
			vim.notify(unlock_err or "Unknown error", vim.log.levels.ERROR, { title = "NvimEnterprise" })
		end
	end, {
		nargs = "?",
		desc = icons.ui.Unlock .. " Unlock a namespace (allow deletion)",
		complete = function()
			return require("users.user_manager"):list()
		end,
	})

	-- ── :UserHealth [name] ───────────────────────────────────────────
	vim.api.nvim_create_user_command("UserHealth", function(cmd)
		local name = utils.trim(cmd.args)
		if name == "" then name = self_ref._settings:get("active_user", "default") end

		local report = self_ref:_user_manager():health_check(name)
		local lines = {
			string.format(
				"%s Health Check: %s  %s",
				icons.ui.User,
				name,
				report.ok and (icons.ui.Check .. " PASS") or (icons.diagnostics.Error .. " FAIL")
			),
			string.rep("─", 50),
		}

		for _, check in ipairs(report.checks) do
			local status_icon = check.status == "ok" and icons.ui.Check or icons.diagnostics.Error
			lines[#lines + 1] = string.format("  %s %-15s %s", status_icon, check.name, check.detail)
		end

		vim.notify(
			table.concat(lines, "\n"),
			report.ok and vim.log.levels.INFO or vim.log.levels.WARN,
			{ title = "NvimEnterprise — User Health" }
		)
	end, {
		nargs = "?",
		desc = icons.diagnostics.Info .. " Run health check on a namespace",
		complete = function()
			return require("users.user_manager"):list()
		end,
	})

	-- ── :UserStats ───────────────────────────────────────────────────
	vim.api.nvim_create_user_command("UserStats", function()
		local stats = self_ref:_user_manager():stats()
		local lines = {
			string.format("%s User Statistics", icons.ui.Dashboard),
			string.rep("─", 45),
			string.format("  Namespaces:     %d", stats.total_namespaces),
			string.format("  Total switches: %d", stats.total_switches),
			string.format("  Total size:     %s", utils.format_bytes(stats.total_size)),
			string.format("  Most used:      %s (%d switches)", stats.most_used.name, stats.most_used.count),
			string.format("  Last switch:    %s (%s)", stats.last_switch.name, stats.last_switch.time or "never"),
			"",
			"  Available profiles:",
		}

		for _, profile_name in ipairs(stats.available_profiles) do
			local used = stats.profiles_used[profile_name] or 0
			lines[#lines + 1] = string.format("    • %s (%d users)", profile_name, used)
		end

		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "NvimEnterprise — User Stats" })
	end, {
		nargs = 0,
		desc = icons.ui.Dashboard .. " Show user namespace statistics",
	})

	-- ── :UserList ────────────────────────────────────────────────────
	vim.api.nvim_create_user_command("UserList", function()
		self_ref:list_users()
	end, {
		nargs = 0,
		desc = icons.ui.List .. " List all user namespaces",
	})

	-- ── :UserEdit [name] ─────────────────────────────────────────────
	vim.api.nvim_create_user_command("UserEdit", function(cmd)
		local name = utils.trim(cmd.args)
		self_ref:edit_user(name ~= "" and name or nil)
	end, {
		nargs = "?",
		desc = icons.ui.Pencil .. " Edit user settings (default: active user)",
		complete = function()
			return require("users.user_manager"):list()
		end,
	})

	-- ── :UserInfo [name] ─────────────────────────────────────────────
	vim.api.nvim_create_user_command("UserInfo", function(cmd)
		local name = utils.trim(cmd.args)
		if name == "" then name = self_ref._settings:get("active_user", "default") end
		local info = self_ref:_user_manager():info(name)
		local lines = {
			string.format("%s User: %s", icons.ui.User, info.name),
			string.rep("─", 40),
			string.format("  Path:        %s", info.path),
			string.format("  Exists:      %s", info.exists and "yes" or "no"),
			string.format("  Active:      %s", info.is_active and "yes" or "no"),
			string.format("  Locked:      %s", info.is_locked and "yes" or "no"),
			string.format("  Settings:    %s", info.has_settings and "yes" or "no"),
			string.format("  Keymaps:     %s", info.has_keymaps and "yes" or "no"),
			string.format("  Plugins:     %s (%d files)", info.has_plugins and "yes" or "no", info.plugin_count or 0),
			string.format("  Size:        %s", utils.format_bytes(info.total_size or 0)),
		}

		if info.created_at then lines[#lines + 1] = string.format("  Created:     %s", info.created_at) end
		if info.profile then lines[#lines + 1] = string.format("  Profile:     %s", info.profile) end
		if info.description and info.description ~= "" then
			lines[#lines + 1] = string.format("  Description: %s", info.description)
		end
		if info.switch_count and info.switch_count > 0 then
			lines[#lines + 1] = string.format("  Switches:    %d", info.switch_count)
		end
		if info.last_active then lines[#lines + 1] = string.format("  Last active: %s", info.last_active) end
		if info.cloned_from then lines[#lines + 1] = string.format("  Cloned from: %s", info.cloned_from) end
		if info.tags and #info.tags > 0 then
			lines[#lines + 1] = string.format("  Tags:        %s", table.concat(info.tags, ", "))
		end

		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "NvimEnterprise — User Info" })
	end, {
		nargs = "?",
		desc = icons.ui.User .. " Show user namespace info",
		complete = function()
			return require("users.user_manager"):list()
		end,
	})

	-- ── :UserProfiles ────────────────────────────────────────────────
	vim.api.nvim_create_user_command("UserProfiles", function()
		local profiles = self_ref:_user_manager():list_profiles()
		local lines = {
			string.format("%s Available Profiles", icons.ui.Gear),
			string.rep("─", 50),
		}
		for _, p in ipairs(profiles) do
			lines[#lines + 1] = string.format("  %s %-12s %s", icons.ui.BoldArrowRight, p.name, p.description)
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = "  Usage: :UserCreate <name> <profile>"

		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "NvimEnterprise — Profiles" })
	end, {
		nargs = 0,
		desc = icons.ui.Gear .. " Show available user profiles",
	})

	-- ── :Settings ────────────────────────────────────────────────────
	vim.api.nvim_create_user_command("Settings", function()
		self_ref:edit_global_settings()
	end, {
		nargs = 0,
		desc = icons.ui.Gear .. " Open root settings.lua",
	})

	-- ── :SettingsReload ──────────────────────────────────────────────
	vim.api.nvim_create_user_command("SettingsReload", function()
		self_ref._settings:reload()

		-- Re-apply options (deferred if special buffer)
		local buf = vim.api.nvim_get_current_buf()
		if vim.bo[buf].buftype == "" and vim.bo[buf].modifiable then
			require("core.options").setup()
		else
			vim.api.nvim_create_autocmd("BufEnter", {
				once = true,
				callback = function()
					local b = vim.api.nvim_get_current_buf()
					if vim.bo[b].buftype == "" and vim.bo[b].modifiable then require("core.options").setup() end
				end,
			})
			vim.g.mapleader = self_ref._settings:get("keymaps.leader", " ")
			vim.g.maplocalleader = self_ref._settings:get("keymaps.local_leader", "\\")
		end

		require("users").setup()
		local cs_ok, cs_mgr = pcall(require, "config.colorscheme_manager")
		if cs_ok then cs_mgr:apply() end
		vim.notify(icons.ui.Check .. " Settings reloaded", vim.log.levels.INFO, { title = "NvimEnterprise" })
	end, {
		nargs = 0,
		desc = icons.ui.Gear .. " Reload settings from disk",
	})

	-- ── Colorscheme commands (delegated) ─────────────────────────────
	local cs_ok, cs_mgr = pcall(require, "config.colorscheme_manager")
	if cs_ok then cs_mgr:register_commands() end

	-- ── Project auto-switch (.nvimuser) ──────────────────────────────
	self_ref:_user_manager():setup_auto_switch()

	log:debug("Registered all user management commands")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SINGLETON
--
-- Only one SettingsManager instance exists per session. The singleton
-- is created on first require and reused thereafter.
-- ═══════════════════════════════════════════════════════════════════════════

---@type SettingsManager
local _instance

--- Get or create the singleton SettingsManager instance.
---@return SettingsManager instance The singleton instance
local function get_instance()
	if not _instance then
		---@diagnostic disable-next-line: assign-type-mismatch
		_instance = SettingsManager:new()
	end
	return _instance
end

return get_instance()
