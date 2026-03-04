---@file lua/config/lazyvim_shim.lua
---@description LazyVim shim — global API compatibility layer for LazyVim extras
---@module "config.lazyvim_shim"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see config.init Config entry point (calls shim.setup before lazy.setup)
---@see core.settings Settings provider (lazyvim_extras.enabled, lazyvim_extras.extras)
---@see core.icons Icon provider (LV.config.icons)
---@see core.logger Structured logging (shim initialization log)
---@see plugins.code.formatting.conform Formatting engine (LV.format fallback)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  config/lazyvim_shim.lua — LazyVim global API compatibility shim         ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  LazyVim Shim (global _G.LazyVim)                                │    ║
--- ║  │                                                                  │    ║
--- ║  │  Purpose:                                                        │    ║
--- ║  │  • Allow LazyVim extras to work without the full LazyVim         │    ║
--- ║  │    distribution installed                                        │    ║
--- ║  │  • Must be loaded BEFORE lazy.setup() so extras can reference    │    ║
--- ║  │    the global LazyVim table during spec processing               │    ║
--- ║  │  • Provides a minimal but complete API surface that LazyVim      │    ║
--- ║  │    extras expect to find on _G.LazyVim                           │    ║
--- ║  │                                                                  │    ║
--- ║  │  API Groups:                                                     │    ║
--- ║  │  ├─ Plugin Queries                                               │    ║
--- ║  │  │  ├─ LV.has(plugin)         Check if plugin is configured      │    ║
--- ║  │  │  ├─ LV.get_plugin(name)    Get plugin spec from lazy.nvim     │    ║
--- ║  │  │  ├─ LV.is_loaded(name)     Check if plugin is loaded          │    ║
--- ║  │  │  └─ LV.opts(name)          Get resolved plugin options        │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Lifecycle                                                    │    ║
--- ║  │  │  └─ LV.on_load(name, fn)   Execute callback when loaded       │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ LSP                                                          │    ║
--- ║  │  │  ├─ LV.on_attach(fn, name) LspAttach callback helper          │    ║
--- ║  │  │  └─ LV.lsp.get_clients()   Wrapper for vim.lsp.get_clients    │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Format                                                       │    ║
--- ║  │  │  └─ LV.format(opts)        conform → LSP fallback             │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Toggle                                                       │    ║
--- ║  │  │  ├─ LV.toggle(opts)        Generic toggle factory             │    ║
--- ║  │  │  ├─ LV.toggle.option()     vim.opt_local toggle               │    ║
--- ║  │  │  ├─ LV.toggle.format()     Auto-format toggle                 │    ║
--- ║  │  │  ├─ LV.toggle.inlay_hints() Inlay hints toggle                │    ║
--- ║  │  │  └─ LV.toggle.diagnostics() Diagnostics toggle                │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ UI                                                           │    ║
--- ║  │  │  └─ LV.ui.fg(name)         Extract fg color from highlight    │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Pick (Telescope)                                             │    ║
--- ║  │  │  ├─ LV.pick(kind, opts)    Telescope picker factory           │    ║
--- ║  │  │  ├─ LV.pick.open()         Direct picker call                 │    ║
--- ║  │  │  └─ LV.pick.wrap()         Wrapped picker for keymaps         │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Notifications                                                │    ║
--- ║  │  │  ├─ LV.notify(msg, level)  vim.notify with "LazyVim" title    │    ║
--- ║  │  │  ├─ LV.info/warn/error()   Convenience wrappers               │    ║
--- ║  │  │  └─ LV.lazy_notify()       No-op (LazyVim deferred notify)    │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Root                                                         │    ║
--- ║  │  │  ├─ LV.root()              Returns cwd                        │    ║
--- ║  │  │  └─ LV.root.cwd()          Same (callable + method)           │    ║
--- ║  │  │                                                               │    ║
--- ║  │  └─ Misc                                                         │    ║
--- ║  │     ├─ LV.safe_keymap_set()   vim.keymap.set with defaults       │    ║
--- ║  │     ├─ LV.has_extra(extra)    Check enabled LazyVim extras       │    ║
--- ║  │     ├─ LV.extend(tbl,k,vals)  Safe list_extend helper            │    ║
--- ║  │     ├─ LV.get_pkg_path()      Mason package path resolver        │    ║
--- ║  │     ├─ LV.config.icons        core.icons reference               │    ║
--- ║  │     └─ LV.cmp.actions         No-op metatable (safe fallback)    │    ║
--- ║  │                                                                  │    ║
--- ║  │  LazyFile Event:                                                 │    ║
--- ║  │  • Custom event used by LazyVim extras as deferred BufRead       │    ║
--- ║  │  • Mapped to: BufReadPost, BufNewFile, BufWritePre               │    ║
--- ║  │  • Registered via lazy.core.handler.event.mappings               │    ║
--- ║  │  • Bootstrap-safe: retries after LazyInstall if not available    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Bootstrap handling:                                                     ║
--- ║  • On first launch, LazyVim plugin directory doesn't exist yet           ║
--- ║  • is_bootstrap() detects this by checking for the LazyVim path          ║
--- ║  • LazyFile event registration retries after LazyInstall completes       ║
--- ║  • All API functions gracefully handle missing lazy.core modules         ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Early return if lazyvim_extras.enabled is false (zero cost)           ║
--- ║  • Idempotent: skips if _G.LazyVim already exists                        ║
--- ║  • All lazy.core requires wrapped in pcall (bootstrap-safe)              ║
--- ║  • LV.cmp.actions uses __index metatable (infinite safe no-ops)          ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

---@class LazyVimShimModule
local M = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOTSTRAP DETECTION
-- ═══════════════════════════════════════════════════════════════════════════

--- Check if we are in a bootstrap scenario (first launch).
---
--- On first launch, lazy.nvim has just been cloned but LazyVim's
--- plugin directory doesn't exist yet. This affects LazyFile event
--- registration and other lazy.core calls.
---@return boolean is_bootstrap Whether this is the first launch
function M.is_bootstrap()
	local lazyvim_path = vim.fn.stdpath("data") .. "/lazy/LazyVim"
	return not vim.uv.fs_stat(lazyvim_path)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SETUP
--
-- Creates the global _G.LazyVim table with all API functions that
-- LazyVim extras expect. Must be called BEFORE lazy.setup() so that
-- extras can reference LazyVim.has(), LazyVim.opts(), etc. during
-- spec processing.
-- ═══════════════════════════════════════════════════════════════════════════

--- Initialize the LazyVim compatibility shim.
---
--- Creates `_G.LazyVim` with a complete API surface matching what
--- LazyVim extras expect. Idempotent: skips if `_G.LazyVim` already
--- exists. No-ops if `lazyvim_extras.enabled` is false in settings.
---@return nil
function M.setup()
	local settings = require("core.settings")

	-- ── Early exit if extras disabled ────────────────────────────────
	if not settings:get("lazyvim_extras.enabled", false) then return end

	-- Disable LazyVim import order check — we manage our own loading order
	vim.g.lazyvim_check_order = false

	-- ── Idempotent guard ─────────────────────────────────────────────
	if _G.LazyVim then return end

	_G.LazyVim = {}
	local LV = _G.LazyVim

	-- ═══════════════════════════════════════════════════════════════════
	-- PLUGIN QUERIES
	--
	-- These functions query lazy.nvim's internal plugin registry.
	-- All calls to lazy.core are wrapped in pcall because during
	-- bootstrap or early startup, these modules may not be available.
	-- ═══════════════════════════════════════════════════════════════════

	--- Check if a plugin is configured (present in lazy.nvim's spec).
	---@param plugin string Plugin name
	---@return boolean
	LV.has = function(plugin)
		local ok, cfg = pcall(require, "lazy.core.config")
		if ok and cfg.plugins then return cfg.plugins[plugin] ~= nil end
		return false
	end

	--- Get a plugin's spec table from lazy.nvim.
	---@param name string Plugin name
	---@return table|nil plugin Plugin spec or nil
	LV.get_plugin = function(name)
		local ok, cfg = pcall(require, "lazy.core.config")
		if ok and cfg.plugins then return cfg.plugins[name] end
		return nil
	end

	--- Check if a plugin has been loaded (not just configured).
	---@param name string Plugin name
	---@return boolean
	LV.is_loaded = function(name)
		local ok, cfg = pcall(require, "lazy.core.config")
		if ok and cfg.plugins[name] then return cfg.plugins[name]._.loaded ~= nil end
		return false
	end

	--- Get a plugin's resolved options (after all opts merging).
	---@param plugin_name string Plugin name
	---@return table opts Resolved options (empty table if not found)
	LV.opts = function(plugin_name)
		local plugin = LV.get_plugin(plugin_name)
		if not plugin then return {} end
		local ok, Plugin = pcall(require, "lazy.core.plugin")
		if ok then return Plugin.values(plugin, "opts", false) end
		return {}
	end

	-- ═══════════════════════════════════════════════════════════════════
	-- LIFECYCLE
	-- ═══════════════════════════════════════════════════════════════════

	--- Execute a callback when a plugin is loaded.
	---
	--- If the plugin is already loaded, the callback fires immediately.
	--- Otherwise, it listens for the `User LazyLoad` event and fires
	--- when the matching plugin name appears.
	---@param name string Plugin name to watch
	---@param fn fun(name: string) Callback to execute
	---@return nil
	LV.on_load = function(name, fn)
		local ok, cfg = pcall(require, "lazy.core.config")
		if ok and cfg.plugins and cfg.plugins[name] and cfg.plugins[name]._.loaded then
			fn(name)
			return
		end

		vim.api.nvim_create_autocmd("User", {
			pattern = "LazyLoad",
			callback = function(event)
				if event.data == name then
					fn(name)
					return true -- Remove autocmd after firing
				end
			end,
		})
	end

	-- ═══════════════════════════════════════════════════════════════════
	-- LSP
	-- ═══════════════════════════════════════════════════════════════════

	--- Register a callback for LspAttach, optionally filtered by server name.
	---@param fn fun(client: vim.lsp.Client, buffer: integer) Callback
	---@param name? string Optional server name filter
	---@return nil
	LV.on_attach = function(fn, name)
		vim.api.nvim_create_autocmd("LspAttach", {
			callback = function(args)
				local buffer = args.buf
				local client = vim.lsp.get_client_by_id(args.data.client_id)
				if client and (not name or client.name == name) then return fn(client, buffer) end
			end,
		})
	end

	--- LSP utilities namespace.
	---@type table
	LV.lsp = {}

	--- Wrapper for vim.lsp.get_clients().
	---@param opts? table Filter options passed to vim.lsp.get_clients
	---@return vim.lsp.Client[]
	LV.lsp.get_clients = function(opts)
		return vim.lsp.get_clients(opts or {})
	end

	-- ═══════════════════════════════════════════════════════════════════
	-- FORMAT
	-- ═══════════════════════════════════════════════════════════════════

	--- Format the current buffer using conform (with LSP fallback).
	---@param opts? table Options: bufnr, async
	---@return nil
	LV.format = function(opts)
		opts = opts or {}
		local conform_ok, conform = pcall(require, "conform")
		if conform_ok then
			conform.format({
				bufnr = opts.bufnr or 0,
				lsp_format = "fallback",
				async = opts.async or false,
			})
		else
			vim.lsp.buf.format({ bufnr = opts.bufnr or 0, async = opts.async or false })
		end
	end

	-- ═══════════════════════════════════════════════════════════════════
	-- TOGGLE
	--
	-- Generic toggle system used by LazyVim extras for boolean options.
	-- Toggle.new() creates a toggle with get/set functions.
	-- Toggle:map() binds a keymap that toggles and notifies.
	-- Convenience factories: option, format, inlay_hints, diagnostics.
	-- ═══════════════════════════════════════════════════════════════════

	---@class LazyVimToggle
	---@field name string Toggle display name
	---@field get fun(): boolean Getter
	---@field set fun(state: boolean) Setter
	local Toggle = {}
	Toggle.__index = Toggle

	--- Create a new toggle instance.
	---@param opts table Toggle definition: name, get, set
	---@return LazyVimToggle
	function Toggle.new(opts)
		local self = setmetatable({}, Toggle)
		self.name = opts.name or "Toggle"
		self.get = opts.get
		self.set = opts.set
		return self
	end

	--- Bind a keymap that toggles the state and shows a notification.
	---@param lhs string Keymap left-hand side
	---@return LazyVimToggle self For chaining
	function Toggle:map(lhs)
		vim.keymap.set("n", lhs, function()
			self.set(not self.get())
			local state = self.get() and "enabled" or "disabled"
			vim.notify(self.name .. ": " .. state, vim.log.levels.INFO, { title = "Toggle" })
		end, { desc = "Toggle " .. self.name })
		return self
	end

	--- Toggle factory (callable as `LV.toggle(opts)`).
	LV.toggle = setmetatable({}, {
		---@param _ table Metatable self
		---@param opts table Toggle definition: name, get, set
		---@return LazyVimToggle
		__call = function(_, opts)
			return Toggle.new(opts)
		end,
	})

	--- Create a toggle for a vim.opt_local option.
	---@param option string Option name (e.g. "wrap", "number")
	---@param opts? table Optional: name override
	---@return LazyVimToggle
	LV.toggle.option = function(option, opts)
		opts = opts or {}
		return Toggle.new({
			name = opts.name or option,
			get = function()
				return vim.opt_local[option]:get()
			end,
			set = function(state)
				vim.opt_local[option] = state
			end,
		})
	end

	--- Create a toggle for auto-format (per-buffer).
	---@param bufnr? integer Buffer number (default: current)
	---@return LazyVimToggle
	LV.toggle.format = function(bufnr)
		return Toggle.new({
			name = "Auto Format",
			get = function()
				return not vim.b[bufnr or 0].disable_autoformat
			end,
			set = function(state)
				vim.b[bufnr or 0].disable_autoformat = not state
			end,
		})
	end

	--- Create a toggle for inlay hints (global).
	---@return LazyVimToggle
	LV.toggle.inlay_hints = function()
		return Toggle.new({
			name = "Inlay Hints",
			get = function()
				return vim.lsp.inlay_hint.is_enabled()
			end,
			set = function(state)
				vim.lsp.inlay_hint.enable(state)
			end,
		})
	end

	--- Create a toggle for diagnostics (global).
	---@return LazyVimToggle
	LV.toggle.diagnostics = function()
		local enabled = true
		return Toggle.new({
			name = "Diagnostics",
			get = function()
				return enabled
			end,
			set = function(state)
				enabled = state
				vim.diagnostic.enable(state)
			end,
		})
	end

	-- ═══════════════════════════════════════════════════════════════════
	-- UI
	-- ═══════════════════════════════════════════════════════════════════

	--- UI utilities namespace.
	---@type table
	LV.ui = {}

	--- Extract the foreground color from a highlight group.
	---@param name string Highlight group name
	---@return table|nil color Table with `fg` hex string, or nil
	LV.ui.fg = function(name)
		local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
		local fg = hl and hl.fg
		return fg and { fg = string.format("#%06x", fg) } or nil
	end

	-- ═══════════════════════════════════════════════════════════════════
	-- PICK (Telescope wrapper)
	--
	-- LazyVim extras use LV.pick() as an abstraction over Telescope.
	-- This shim maps directly to telescope.builtin calls.
	-- ═══════════════════════════════════════════════════════════════════

	--- Telescope picker factory (callable as `LV.pick(kind, opts)`).
	--- Returns a zero-argument function that opens the picker.
	LV.pick = setmetatable({}, {
		---@param _ table Metatable self
		---@param kind string Telescope builtin name (e.g. "find_files")
		---@param opts? table Options passed to the builtin
		---@return fun() picker Zero-argument function that opens the picker
		__call = function(_, kind, opts)
			opts = opts or {}
			return function()
				local ok_t, builtin = pcall(require, "telescope.builtin")
				if ok_t and builtin[kind] then builtin[kind](opts) end
			end
		end,
	})

	--- Open a Telescope picker directly.
	---@param cmd string Telescope builtin name
	---@param opts? table Options passed to the builtin
	---@return nil
	LV.pick.open = function(cmd, opts)
		local ok_t, builtin = pcall(require, "telescope.builtin")
		if ok_t and builtin[cmd] then builtin[cmd](opts or {}) end
	end

	--- Wrap a Telescope picker call for use in keymap definitions.
	---@param cmd string Telescope builtin name
	---@param opts? table Options passed to the builtin
	---@return fun() picker Zero-argument function
	LV.pick.wrap = function(cmd, opts)
		return function()
			LV.pick.open(cmd, opts)
		end
	end

	-- ═══════════════════════════════════════════════════════════════════
	-- NOTIFICATIONS
	-- ═══════════════════════════════════════════════════════════════════

	--- Send a notification with the "LazyVim" title.
	---@param msg string Message body
	---@param level? integer vim.log.levels.* constant (default: INFO)
	---@return nil
	LV.notify = function(msg, level)
		vim.notify(msg, level or vim.log.levels.INFO, { title = "LazyVim" })
	end

	--- Send an INFO notification.
	---@param msg string Message body
	---@return nil
	LV.info = function(msg)
		LV.notify(msg, vim.log.levels.INFO)
	end

	--- Send a WARN notification.
	---@param msg string Message body
	---@return nil
	LV.warn = function(msg)
		LV.notify(msg, vim.log.levels.WARN)
	end

	--- Send an ERROR notification.
	---@param msg string Message body
	---@return nil
	LV.error = function(msg)
		LV.notify(msg, vim.log.levels.ERROR)
	end

	--- No-op placeholder for LazyVim's deferred notification system.
	---@return nil
	LV.lazy_notify = function() end

	-- ═══════════════════════════════════════════════════════════════════
	-- ROOT
	--
	-- LazyVim uses LV.root() to determine the project root.
	-- This shim simply returns cwd. The metatable allows both
	-- LV.root() (callable) and LV.root.cwd() (method) syntax.
	-- ═══════════════════════════════════════════════════════════════════

	--- Root directory resolver (returns cwd).
	--- Supports both `LV.root()` and `LV.root.cwd()` calling conventions.
	LV.root = setmetatable({
		--- Get the current working directory.
		---@return string cwd Current working directory
		cwd = function()
			return vim.fn.getcwd()
		end,
	}, {
		---@return string cwd Current working directory
		__call = function()
			return vim.fn.getcwd()
		end,
	})
	LV.root.get = LV.root

	-- ═══════════════════════════════════════════════════════════════════
	-- MISC UTILITIES
	-- ═══════════════════════════════════════════════════════════════════

	--- Set a keymap with sensible defaults (silent = true).
	---@param mode string|string[] Mode(s)
	---@param lhs string Left-hand side
	---@param rhs string|function Right-hand side
	---@param opts? table Keymap options
	---@return nil
	LV.safe_keymap_set = function(mode, lhs, rhs, opts)
		opts = opts or {}
		opts.silent = opts.silent ~= false
		vim.keymap.set(mode, lhs, rhs, opts)
	end

	--- Check if a LazyVim extra is enabled in settings.
	---@param extra string Extra name (partial match supported)
	---@return boolean enabled Whether the extra is in the enabled list
	LV.has_extra = function(extra)
		local extras = settings:get("lazyvim_extras.extras", {})
		for _, e in ipairs(extras) do
			if e:find(extra, 1, true) then return true end
		end
		return false
	end

	--- Safely extend a list-like table field.
	--- Creates the field if it doesn't exist.
	---@param tbl table Target table
	---@param key string Field name to extend
	---@param values table Values to append
	---@return nil
	LV.extend = function(tbl, key, values)
		tbl[key] = tbl[key] or {}
		vim.list_extend(tbl[key], values)
	end

	--- Get the installation path of a Mason package.
	---@param pkg string Mason package name
	---@param path? string Relative path within the package
	---@return string install_path Full path (empty string if not found)
	LV.get_pkg_path = function(pkg, path)
		local ok_m, registry = pcall(require, "mason-registry")
		if ok_m then
			local pkg_ok, p = pcall(registry.get_package, pkg)
			if pkg_ok and p then return p:get_install_path() .. "/" .. (path or "") end
		end
		return ""
	end

	--- Config namespace (exposes core.icons to LazyVim extras).
	---@type table
	LV.config = { icons = require("core.icons") }

	--- Completion actions namespace (no-op metatable).
	--- LazyVim extras reference `LazyVim.cmp.actions.*` for keymap
	--- definitions. The __index metamethod returns a no-op function
	--- for any key, preventing errors when specific actions don't exist.
	---@type table
	LV.cmp = {}
	LV.cmp.actions = setmetatable({}, {
		---@param _ table Metatable self
		---@param _ string Key name (unused)
		---@return fun() noop No-op function
		__index = function()
			return function() end
		end,
	})

	-- ═══════════════════════════════════════════════════════════════════
	-- LAZYFILE EVENT
	--
	-- LazyVim extras use "LazyFile" as a custom event that maps to
	-- BufReadPost + BufNewFile + BufWritePre. This provides deferred
	-- loading similar to LazyVim's own event system.
	--
	-- During bootstrap, lazy.core.handler.event may not be available
	-- yet (lazy.nvim was just cloned). We protect with pcall and
	-- retry after the LazyInstall event fires.
	-- ═══════════════════════════════════════════════════════════════════

	--- Register the LazyFile → BufReadPost/BufNewFile/BufWritePre mapping.
	---@return boolean success Whether registration succeeded
	---@private
	local function register_lazy_file_event()
		local ok_ev, Event = pcall(require, "lazy.core.handler.event")
		if ok_ev and Event and Event.mappings then
			Event.mappings.LazyFile = {
				id = "LazyFile",
				event = { "BufReadPost", "BufNewFile", "BufWritePre" },
			}
			Event.mappings["User LazyFile"] = Event.mappings.LazyFile
			return true
		end
		return false
	end

	if not register_lazy_file_event() then
		-- During bootstrap: retry after lazy.nvim finishes installing plugins
		vim.api.nvim_create_autocmd("User", {
			pattern = "LazyInstall",
			once = true,
			callback = function()
				vim.schedule(function()
					register_lazy_file_event()
				end)
			end,
		})
	end

	-- ── Log initialization ───────────────────────────────────────────
	local log_ok, logger = pcall(require, "core.logger")
	if log_ok then
		logger
			:for_module("lazyvim_shim")
			:info("LazyVim compatibility shim initialized (bootstrap: %s)", tostring(M.is_bootstrap()))
	end
end

return M
