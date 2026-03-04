---@file lua/plugins/ui/snacks.lua
---@description Snacks — Swiss-army knife plugin (picker, notifier, terminal, git, UI toggles)
---@module "plugins.ui.snacks"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Plugin enable/disable guard, animation preferences
---@see core.icons                 Icon provider (notifications, keymaps, picker, toggles)
---@see plugins.ui.bufferline      Keymap conflict: <leader>bd reserved for BufferLinePickClose
---@see plugins.ui.noice           Keymap conflict: <leader>sn* reserved for noice prefix
---@see plugins.lsp                Keymap conflict: gd/gD/gr/gi/gy handled by LSP config
---@see plugins.editor.diffview    Keymap conflict: <leader>gd handled by DiffView
---@see plugins.editor.edgy        Keymap conflict: <leader>uE/ue handled by Edgy
---@see plugins.editor.gitsigns    Git signs integration (toggles, blame)
---@see plugins.treesitter         Treesitter scope detection for indent/scope modules
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ui/snacks.lua — Utility layer                                   ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  snacks.nvim (folke/snacks.nvim)                                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Modules (20):                                                   │    ║
--- ║  │  ├─ Picker      Files, grep, buffers, git, diagnostics, LSP      │    ║
--- ║  │  ├─ Notifier    Notification system (icons, timeout, compact)    │    ║
--- ║  │  ├─ Terminal    Floating terminal toggle                         │    ║
--- ║  │  ├─ Git         Browse, blame_line, log, status                  │    ║
--- ║  │  ├─ Lazygit     Full lazygit integration                         │    ║
--- ║  │  ├─ Bigfile     Auto-disable heavy features (>1.5MB)             │    ║
--- ║  │  ├─ Quickfile   Fast file open optimization                      │    ║
--- ║  │  ├─ Input       vim.ui.input replacement                         │    ║
--- ║  │  ├─ Indent      Animated indent guides (chunk + scope)           │    ║
--- ║  │  ├─ Scope       Treesitter scope detection & highlighting        │    ║
--- ║  │  ├─ Scroll      Smooth scrolling animations                      │    ║
--- ║  │  ├─ Zen         Distraction-free writing mode                    │    ║
--- ║  │  ├─ Dim         Dim inactive code sections                       │    ║
--- ║  │  ├─ Words       Word highlighting under cursor                   │    ║
--- ║  │  ├─ Dashboard   Startup screen (disabled — using separate)       │    ║
--- ║  │  ├─ Rename      LSP rename with file system update               │    ║
--- ║  │  ├─ Bufdelete   Safe buffer deletion                             │    ║
--- ║  │  ├─ Statuscolumn Custom status column (marks, signs, folds, git) │    ║
--- ║  │  ├─ Debug       Inspect & backtrace helpers (_G.dd, _G.bt)       │    ║
--- ║  │  └─ Profiler    Startup profiling scratch buffer                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (50+ bindings):                                         │    ║
--- ║  │  ├─ <leader>f*   Find/Files (6 bindings)                         │    ║
--- ║  │  │  ├─ ff  Find files       fg  Git files                        │    ║
--- ║  │  │  ├─ fr  Recent files     fp  Projects                         │    ║
--- ║  │  │  ├─ fb  Buffers          fc  Config files                     │    ║
--- ║  │  │  └─ Aliases: <leader>, (buffers)  / (grep)  : (cmd history)   │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ <leader>s*   Search (20 bindings)                            │    ║
--- ║  │  │  ├─ sa  Autocmds    sb  Buffer lines   sc  Cmd history        │    ║
--- ║  │  │  ├─ sC  Commands    sd  Buf diagnostics sD  WS diagnostics    │    ║
--- ║  │  │  ├─ sh  Help        sH  Highlights      sj  Jumps             │    ║
--- ║  │  │  ├─ sk  Keymaps     sl  Location list   sm  Marks             │    ║
--- ║  │  │  ├─ sM  Man pages   sq  Quickfix        sR  Resume            │    ║
--- ║  │  │  ├─ su  Undo        sw  Grep word       ss  LSP symbols       │    ║
--- ║  │  │  ├─ sS  WS symbols  st  Colorschemes    sN  Notifications     │    ║
--- ║  │  │  └─ un  Dismiss notifications                                 │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ <leader>g*   Git (7 bindings)                                │    ║
--- ║  │  │  ├─ ge  Browse    gl  Blame line   gf  Log (file)             │    ║
--- ║  │  │  ├─ gs  Status    gL  Log          gS  Stash                  │    ║
--- ║  │  │  └─ gg  Lazygit                                               │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ <leader>b*   Buffers (2 bindings)                            │    ║
--- ║  │  │  ├─ bx  Delete buffer   bD  Delete others                     │    ║
--- ║  │  │  └─ (bd reserved for BufferLinePickClose)                     │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ <leader>u*   UI toggles (13 bindings, via init)              │    ║
--- ║  │  │  ├─ us  Spelling      uw  Word wrap     uL  Relative nums     │    ║
--- ║  │  │  ├─ ul  Line numbers  ud  Diagnostics   uT  Treesitter        │    ║
--- ║  │  │  ├─ uh  Inlay hints   uD  Dim           uz  Zen               │    ║
--- ║  │  │  ├─ uZ  Zoom          uS  Scroll        uW  Words             │    ║
--- ║  │  │  └─ (uC/uI/ui/uE/ue/ua/ub/uc/uF/uf reserved)                  │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ <leader>cr   Rename file                                     │    ║
--- ║  │  ├─ <leader>z    Zen mode                                        │    ║
--- ║  │  ├─ <leader>dp*  Profiler (2 bindings)                           │    ║
--- ║  │  └─ <c-/>/<c-_>  Terminal toggle                                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymap Conflict Resolution:                                     │    ║
--- ║  │  ┌─────────────┬──────────────┬─────────────────────────────┐    │    ║
--- ║  │  │  Key        │  Remapped to │  Reason                     │    │    ║
--- ║  │  ├─────────────┼──────────────┼─────────────────────────────┤    │    ║
--- ║  │  │  gd/gD/gr   │  (not mapped)│  Handled by LSP config      │    │    ║
--- ║  │  │  <leader>bd │  <leader>bx  │  bd = BufferLinePickClose   │    │    ║
--- ║  │  │  <leader>uC │  <leader>st  │  uC = Toggle Cursor Line    │    │    ║
--- ║  │  │  <leader>sn │  <leader>sN  │  sn* = noice prefix         │    │    ║
--- ║  │  │  <leader>gd │  (not mapped)│  gd = DiffView              │    │    ║
--- ║  │  └─────────────┴──────────────┴─────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Debug Globals (set in init):                                    │    ║
--- ║  │  ├─ _G.dd(...)  → Snacks.debug.inspect(...)                      │    ║
--- ║  │  ├─ _G.bt()     → Snacks.debug.backtrace()                       │    ║
--- ║  │  └─ vim.print    → _G.dd (overridden)                            │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Defensive Design:                                                       ║
--- ║  • snacks_call() wrapper: checks Snacks global + module existence        ║
--- ║  • pick() shorthand: wraps snacks_call("picker", method)                 ║
--- ║  • icon() helper: fallback on missing icons                              ║
--- ║  • Fallback icons table if core.icons is unavailable                     ║
--- ║  • setting() helper: pcall on settings access                            ║
--- ║  • All toggle mappings only registered after Snacks is loaded            ║
--- ║  • pcall guards on every Snacks global access in keymaps                 ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok and not settings:is_plugin_enabled("snacks") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- SAFE REQUIRES
--
-- Icons are loaded defensively: if core.icons is unavailable (e.g.
-- during minimal startup or testing), a hardcoded fallback table
-- with all required icon categories is used. This guarantees snacks
-- keymaps and notifications never crash on missing icons.
-- ═══════════════════════════════════════════════════════════════════════════

local icons_ok, icons = pcall(require, "core.icons")

if not icons_ok or not icons then
	icons = {
		diagnostics = { Error = " ", Warn = " ", Info = " ", Hint = "󰌵 " },
		ui = {
			Bug = " ",
			Pencil = "●",
			Search = " ",
			File = "󰈔",
			Folder = "󰉋",
			Gear = "󰒓",
			Terminal = "󰞷",
			Code = "󰅩",
			History = "󰄉",
			BookMark = "󰃀",
			List = "󰗚",
			Star = "󰓎",
			Keyboard = "",
			Close = "×",
			Rocket = "󰓅",
			Target = "󰓾",
			Telescope = "󰭎",
			Dashboard = "󰕮",
			Project = "󰉏",
		},
		git = { Branch = "", Git = "󰊢", Diff = "" },
		misc = { Lazy = "󰒲", Neovim = "" },
	}
end

--- Safely access an icon from a table with fallback.
---@param tbl table|nil Icon category table (e.g. `icons.ui`)
---@param key string Icon key name (e.g. `"Search"`)
---@param fallback string Fallback string if key is missing
---@return string icon The resolved icon or fallback
local function icon(tbl, key, fallback)
	if type(tbl) == "table" and tbl[key] ~= nil then return tbl[key] end
	return fallback or ""
end

--- Cached icon category references for repeated use.
---@type table<string, string>
local ui = icons.ui or {}
---@type table<string, string>
local gi = icons.git or {}
---@type table<string, string>
local dg = icons.diagnostics or {}
---@type table<string, string>
local mi = icons.misc or {}

-- ═══════════════════════════════════════════════════════════════════════════
-- SAFE SETTINGS
-- ═══════════════════════════════════════════════════════════════════════════

--- Safely read a setting value with fallback.
---
--- Wraps settings:get() in pcall to handle cases where
--- core.settings failed to load or the key doesn't exist.
---@param key string Settings key path (e.g. `"ui.animations"`)
---@param default any Fallback value if setting is unavailable
---@return any value The setting value or default
---@private
local function setting(key, default)
	if not settings_ok or not settings then return default end
	local ok, val = pcall(settings.get, settings, key, default)
	return ok and val or default
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SAFE SNACKS CALLER
--
-- Factory functions that produce safe callbacks for keymaps.
-- Each callback checks that the Snacks global exists and the
-- requested module/method is available before calling it.
-- This prevents errors when keymaps are triggered before
-- snacks.nvim has fully initialized.
-- ═══════════════════════════════════════════════════════════════════════════

--- Create a safe callback that calls Snacks[module][method](...).
---
--- The returned function checks that the `Snacks` global exists and
--- the requested module is available before invoking the method.
--- Shows a warning notification if Snacks is not loaded.
---@param module string Snacks module name (e.g. `"picker"`, `"terminal"`)
---@param method string Method name (e.g. `"files"`, `"grep"`) or `""` for direct call
---@param ... any Arguments forwarded to the method
---@return function callback Safe keymap callback
---@private
local function snacks_call(module, method, ...)
	local args = { ... }
	return function()
		local ok = pcall(function()
			return Snacks
		end)
		if not ok or not Snacks then
			vim.notify("Snacks not loaded yet", vim.log.levels.WARN)
			return
		end
		local mod = Snacks[module]
		if not mod then
			vim.notify("Snacks." .. module .. " not available", vim.log.levels.WARN)
			return
		end
		if method and method ~= "" then
			if type(mod[method]) == "function" then mod[method](unpack(args)) end
		else
			if type(mod) == "function" then mod(unpack(args)) end
		end
	end
end

--- Shorthand for `snacks_call("picker", method)`.
---
--- Creates a safe callback that opens a Snacks picker source.
---@param method string Picker source name (e.g. `"files"`, `"grep"`, `"git_status"`)
---@return function callback Safe keymap callback
---@private
local function pick(method)
	return snacks_call("picker", method)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
--
-- Priority 1000 + lazy = false: snacks.nvim loads at startup because
-- it provides core infrastructure (notifier, statuscolumn, bigfile,
-- quickfile) that must be available before other plugins.
-- ═══════════════════════════════════════════════════════════════════════════

return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYMAPS
	--
	-- 50+ bindings organized by function group.
	--
	-- ⚠ CONFLICT AVOIDANCE RULES:
	-- • gd/gD/gr/gi/gy → handled by LSP config, NOT here
	-- • <leader>bd     → <leader>bx (bd = BufferLinePickClose)
	-- • <leader>uC     → <leader>st (uC = Toggle Cursor Line)
	-- • <leader>sn     → <leader>sN (sn* = noice submenu prefix)
	-- • <leader>gd     → NOT here (gd = DiffView)
	-- • <leader>sd     = buffer diagnostics (matches Telescope convention)
	-- • <leader>sD     = workspace diagnostics (matches Telescope convention)
	-- ═══════════════════════════════════════════════════════════════════

	keys = {

		-- ── Find / Files ──────────────────────────────────────────────
		{ "<leader>ff", pick("files"), desc = icon(ui, "File", "󰈔") .. " Find files" },
		{ "<leader>fg", pick("git_files"), desc = icon(gi, "Git", "󰊢") .. " Git files" },
		{ "<leader>fr", pick("recent"), desc = icon(ui, "History", "󰄉") .. " Recent files" },
		{ "<leader>fp", pick("projects"), desc = icon(ui, "Project", "󰉏") .. " Projects" },
		{ "<leader>fb", pick("buffers"), desc = icon(ui, "List", "󰗚") .. " Buffers" },
		{
			"<leader>fc",
			function()
				local ok = pcall(function()
					return Snacks
				end)
				if ok and Snacks and Snacks.picker then Snacks.picker.files({ cwd = vim.fn.stdpath("config") }) end
			end,
			desc = icon(ui, "Gear", "󰒓") .. " Config files",
		},

		-- ── Shortcut aliases ──────────────────────────────────────────
		{ "<leader>,", pick("buffers"), desc = icon(ui, "List", "󰗚") .. " Buffers" },
		{ "<leader>/", pick("grep"), desc = icon(ui, "Search", "") .. " Grep" },
		{ "<leader>:", pick("command_history"), desc = icon(ui, "History", "󰄉") .. " Command history" },

		-- ── Search ────────────────────────────────────────────────────
		{ "<leader>sa", pick("autocmds"), desc = icon(ui, "Gear", "󰒓") .. " Autocmds" },
		{ "<leader>sb", pick("lines"), desc = icon(ui, "List", "󰗚") .. " Buffer lines" },
		{ "<leader>sc", pick("command_history"), desc = icon(ui, "History", "󰄉") .. " Command history" },
		{ "<leader>sC", pick("commands"), desc = icon(ui, "Terminal", "󰞷") .. " Commands" },

		-- sd/sD: buffer (narrow) vs workspace (broad) diagnostics
		{ "<leader>sd", pick("diagnostics_buffer"), desc = icon(dg, "Warn", " ") .. " Buffer diagnostics" },
		{ "<leader>sD", pick("diagnostics"), desc = icon(dg, "Info", " ") .. " Workspace diagnostics" },

		{ "<leader>sh", pick("help"), desc = icon(ui, "BookMark", "󰃀") .. " Help pages" },
		{ "<leader>sH", pick("highlights"), desc = icon(ui, "Star", "󰓎") .. " Highlights" },
		{ "<leader>sj", pick("jumps"), desc = icon(ui, "Rocket", "󰓅") .. " Jumps" },
		{ "<leader>sk", pick("keymaps"), desc = icon(ui, "Keyboard", "") .. " Keymaps" },
		{ "<leader>sl", pick("loclist"), desc = icon(ui, "List", "󰗚") .. " Location list" },
		{ "<leader>sm", pick("marks"), desc = icon(ui, "BookMark", "󰃀") .. " Marks" },
		{ "<leader>sM", pick("man"), desc = icon(ui, "File", "󰈔") .. " Man pages" },
		{ "<leader>sq", pick("qflist"), desc = icon(ui, "List", "󰗚") .. " Quickfix list" },
		{ "<leader>sR", pick("resume"), desc = icon(ui, "Rocket", "󰓅") .. " Resume last" },
		{ "<leader>su", pick("undo"), desc = icon(ui, "History", "󰄉") .. " Undo history" },

		-- ── Word grep (normal + visual) ───────────────────────────────
		{
			"<leader>sw",
			pick("grep_word"),
			mode = { "n", "x" },
			desc = icon(ui, "Search", "") .. " Grep word",
		},

		-- ── LSP symbols (via picker, NOT gd/gr/gi) ───────────────────
		{ "<leader>ss", pick("lsp_symbols"), desc = icon(ui, "Code", "󰅩") .. " LSP symbols" },
		{ "<leader>sS", pick("lsp_workspace_symbols"), desc = icon(ui, "Code", "󰅩") .. " Workspace symbols" },

		-- ── Colorschemes ──────────────────────────────────────────────
		-- <leader>st avoids conflict with <leader>uC (Toggle Cursor Line)
		{ "<leader>st", pick("colorschemes"), desc = icon(ui, "Star", "󰓎") .. " Colorschemes" },

		-- ── Notifications ─────────────────────────────────────────────
		-- <leader>sN (capital N) avoids conflict with <leader>sn* (noice prefix)
		{ "<leader>sN", pick("notifications"), desc = icon(dg, "Info", " ") .. " Notification history" },
		{ "<leader>un", snacks_call("notifier", "hide"), desc = icon(ui, "Close", "×") .. " Dismiss notifications" },

		-- ── Terminal ──────────────────────────────────────────────────
		{ "<c-/>", snacks_call("terminal", ""), desc = icon(ui, "Terminal", "󰞷") .. " Toggle terminal" },
		{ "<c-_>", snacks_call("terminal", ""), desc = icon(ui, "Terminal", "󰞷") .. " Toggle terminal" },

		-- ── Git ───────────────────────────────────────────────────────
		-- NOTE: <leader>gd NOT mapped here — handled by DiffView plugin
		{
			"<leader>ge",
			snacks_call("gitbrowse", ""),
			mode = { "n", "v" },
			desc = icon(gi, "Git", "󰊢") .. " Git browse (Snacks)",
		},
		{
			"<leader>gl",
			function()
				local ok = pcall(function()
					return Snacks
				end)
				if ok and Snacks and Snacks.git then Snacks.git.blame_line() end
			end,
			desc = icon(gi, "Branch", "") .. " Blame line",
		},
		{ "<leader>gf", pick("git_log_file"), desc = icon(gi, "Diff", "") .. " Git log (file)" },
		{ "<leader>gs", pick("git_status"), desc = icon(gi, "Git", "󰊢") .. " Git status" },
		{ "<leader>gL", pick("git_log"), desc = icon(gi, "Branch", "") .. " Git log" },
		{ "<leader>gS", pick("git_stash"), desc = icon(gi, "Git", "󰊢") .. " Git stash" },

		-- ── Lazygit ───────────────────────────────────────────────────
		{
			"<leader>gg",
			function()
				local ok = pcall(function()
					return Snacks
				end)
				if ok and Snacks and Snacks.lazygit then Snacks.lazygit() end
			end,
			desc = icon(gi, "Git", "󰊢") .. " Lazygit",
		},

		-- ── Buffer delete ─────────────────────────────────────────────
		-- <leader>bx avoids conflict with <leader>bd (BufferLinePickClose)
		{
			"<leader>bx",
			function()
				local ok = pcall(function()
					return Snacks
				end)
				if ok and Snacks and Snacks.bufdelete then Snacks.bufdelete() end
			end,
			desc = icon(ui, "Close", "×") .. " Delete buffer (snacks)",
		},
		{
			"<leader>bD",
			function()
				local ok = pcall(function()
					return Snacks
				end)
				if ok and Snacks and Snacks.bufdelete then Snacks.bufdelete.other() end
			end,
			desc = icon(ui, "Close", "×") .. " Delete other buffers",
		},

		-- ── Rename ────────────────────────────────────────────────────
		{
			"<leader>cr",
			function()
				local ok = pcall(function()
					return Snacks
				end)
				if ok and Snacks and Snacks.rename then Snacks.rename.rename_file() end
			end,
			desc = icon(ui, "Pencil", "●") .. " Rename file",
		},

		-- ── Zen mode ──────────────────────────────────────────────────
		{
			"<leader>z",
			function()
				local ok = pcall(function()
					return Snacks
				end)
				if ok and Snacks and Snacks.zen then Snacks.zen() end
			end,
			desc = "Zen mode",
		},

		-- ── Profiler ──────────────────────────────────────────────────
		{
			"<leader>dps",
			function()
				local ok = pcall(function()
					return Snacks
				end)
				if ok and Snacks and Snacks.profiler then Snacks.profiler.scratch() end
			end,
			desc = icon(ui, "Rocket", "󰓅") .. " Profiler scratch",
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	--
	-- Module-by-module configuration. Each module can be independently
	-- enabled/disabled. Animation-dependent modules (indent, scroll)
	-- read from settings("ui.animations") at load time.
	-- ═══════════════════════════════════════════════════════════════════

	---@type snacks.Config
	opts = {
		-- ── Dashboard (disabled — using separate dashboard plugin) ─────
		dashboard = {
			enabled = false,
		},

		-- ── Bigfile (auto-disable heavy features on large files) ──────
		bigfile = {
			enabled = true,
			size = 1.5 * 1024 * 1024, -- 1.5 MB threshold
			notify = true,
		},

		-- ── Notifier (notification system) ────────────────────────────
		notifier = {
			enabled = true,
			timeout = 10000,
			width = { min = 40, max = 80 },
			height = { min = 1, max = 10 },
			margin = { top = 0, right = 1, bottom = 0 },
			padding = true,
			sort = { "level", "added" },
			level = vim.log.levels.TRACE,
			icons = {
				error = icon(dg, "Error", " "),
				warn = icon(dg, "Warn", " "),
				info = icon(dg, "Info", " "),
				debug = icon(ui, "Bug", " "),
				trace = icon(ui, "Pencil", "●"),
			},
			style = "compact",
			top_down = true,
		},

		-- ── Picker (files, grep, buffers, git, diagnostics, LSP) ──────
		picker = {
			enabled = true,
			sources = {
				files = {
					hidden = true,
					ignored = false,
					follow = true,
				},
				grep = {
					hidden = true,
					ignored = false,
					follow = true,
				},
			},
			formatters = {
				file = {
					filename_first = true,
				},
			},
			win = {
				input = {
					keys = {
						["<Esc>"] = { "close", mode = { "n", "i" } },
					},
				},
			},
			icons = {
				files = {
					enabled = true,
				},
			},
		},

		-- ── Quickfile (fast file open optimization) ───────────────────
		quickfile = { enabled = true },

		-- ── Statuscolumn (custom sign/fold/git column) ────────────────
		statuscolumn = {
			enabled = true,
			left = { "mark", "sign" },
			right = { "fold", "git" },
			folds = {
				open = true,
				githl = true,
			},
		},

		-- ── Words (highlight word under cursor) ───────────────────────
		words = {
			enabled = true,
			debounce = 200,
			notify_jump = true,
			notify_end = true,
		},

		-- ── Input (vim.ui.input replacement) ──────────────────────────
		input = {
			enabled = true,
			icon = icon(ui, "Pencil", "✏"),
		},

		-- ── Indent (animated indent guides) ───────────────────────────
		indent = {
			enabled = true,
			animate = {
				enabled = setting("ui.animations", true),
				style = "out",
				easing = "linear",
				duration = {
					step = 20,
					total = 200,
				},
			},
			scope = {
				enabled = true,
				underline = false,
				only_current = true,
			},
			chunk = {
				enabled = true,
				only_current = true,
				hl = "SnacksIndentChunk",
			},
		},

		-- ── Scope (treesitter scope detection) ────────────────────────
		scope = {
			enabled = true,
			treesitter = {
				enabled = true,
			},
		},

		-- ── Scroll (smooth scrolling animations) ──────────────────────
		scroll = {
			enabled = setting("ui.animations", true),
			animate = {
				duration = { step = 15, total = 150 },
				easing = "linear",
			},
		},

		-- ── Zen (distraction-free writing mode) ───────────────────────
		zen = {
			enabled = true,
			toggles = {
				dim = true,
				git_signs = false,
				mini_diff_signs = false,
				diagnostics = false,
				inlay_hints = false,
			},
			show = {
				statusline = false,
				tabline = false,
			},
		},

		-- ── Dim (dim inactive code sections) ──────────────────────────
		dim = {
			enabled = true,
			scope = {
				min_size = 5,
				max_size = 20,
				siblings = true,
			},
		},

		-- ── Rename (LSP rename with file system update) ───────────────
		rename = { enabled = true },

		-- ── Lazygit (full lazygit integration) ────────────────────────
		lazygit = {
			enabled = true,
			configure = true,
		},

		-- ── Terminal (floating terminal) ──────────────────────────────
		terminal = {
			win = {
				style = "terminal",
				position = "float",
				border = "rounded",
				width = 0.85,
				height = 0.8,
			},
		},

		-- ── Profiler (startup profiling) ──────────────────────────────
		profiler = { enabled = true },

		-- ── Styles (shared visual settings) ───────────────────────────
		styles = {
			notification = {
				border = "rounded",
				wo = { wrap = true },
			},
			terminal = {
				border = "rounded",
			},
			input = {
				border = "rounded",
				relative = "cursor",
				row = -3,
				col = 0,
			},
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- INIT — Debug globals & UI toggle mappings
	--
	-- Deferred to VeryLazy autocmd to ensure Snacks is fully loaded
	-- before accessing its toggle API.
	--
	-- Toggle mappings are registered here (not in `keys`) because
	-- Snacks.toggle returns a chainable object with :map(), which
	-- doesn't fit the lazy.nvim keys spec format.
	--
	-- ⚠ RESERVED TOGGLE KEYS (not mapped here):
	-- • <leader>uC  — Toggle Cursor Line (existing config)
	-- • <leader>uI  — Inspect Tree (existing config)
	-- • <leader>ui  — Inspect Pos (existing config)
	-- • <leader>uE/ue — Edgy toggle
	-- • <leader>ua  — Toggle Animations
	-- • <leader>ub  — Toggle Dark Background
	-- • <leader>uc  — Toggle Conceal Level
	-- • <leader>uF/uf — Toggle Auto Format
	-- ═══════════════════════════════════════════════════════════════════

	init = function()
		vim.api.nvim_create_autocmd("User", {
			pattern = "VeryLazy",
			callback = function()
				-- ── Debug helpers (global) ─────────────────────────────
				local ok = pcall(function()
					return Snacks
				end)
				if not ok or not Snacks then return end

				_G.dd = function(...)
					Snacks.debug.inspect(...)
				end
				_G.bt = function()
					Snacks.debug.backtrace()
				end
				vim.print = _G.dd

				-- ── Toggle mappings ───────────────────────────────────
				local toggle = Snacks.toggle
				if not toggle then return end

				-- ── Appearance toggles ────────────────────────────────
				toggle
					.option("spell", {
						name = icon(ui, "BookMark", "󰃀") .. " Spelling",
					})
					:map("<leader>us")

				toggle
					.option("wrap", {
						name = icon(ui, "List", "󰗚") .. " Word Wrap",
					})
					:map("<leader>uw")

				toggle
					.option("relativenumber", {
						name = "  Relative Numbers",
					})
					:map("<leader>uL")

				-- ── Neovim feature toggles ────────────────────────────
				toggle.line_number():map("<leader>ul")
				toggle.diagnostics():map("<leader>ud")
				toggle.treesitter():map("<leader>uT")
				toggle.inlay_hints():map("<leader>uh")

				-- ── Snacks feature toggles ────────────────────────────
				toggle.dim():map("<leader>uD")
				toggle.zen():map("<leader>uz")
				toggle.zoom():map("<leader>uZ")
				toggle.scroll():map("<leader>uS")
				toggle.words():map("<leader>uW")

				-- ── Profiler toggles ──────────────────────────────────
				toggle.profiler():map("<leader>dpp")
				toggle.profiler_highlights():map("<leader>dph")
			end,
		})
	end,
}
