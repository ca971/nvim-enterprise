---@file lua/core/options.lua
---@description Options — apply all Neovim vim.opt/vim.g settings from merged configuration
---@module "core.options"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings singleton (provides all option values via :get())
---@see core.platform Platform singleton (capabilities: true color, SSH, GUI, executables)
---@see core.bootstrap Bootstrap calls Options.setup() during startup sequence
---@see core.keymaps Keymaps module (depends on leader keys set here)
---@see plugins.ui.bufferline Bufferline respects showtabline set here
---@see plugins.ui.lualine Lualine respects laststatus set here
---@see plugins.ui.dashboard Dashboard triggers UI bar toggle set up here
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/options.lua — Neovim options from settings (vim.opt / vim.g)       ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Options (module table — setup function + dashboard UI logic)    │    ║
--- ║  │                                                                  │    ║
--- ║  │  M.setup() pipeline:                                             │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  1. Ensure required directories (cache/data/state)         │  │    ║
--- ║  │  │  2. Leaders (must be set before any keymap registration)   │  │    ║
--- ║  │  │  3. General options (encoding, mouse, clipboard)           │  │    ║
--- ║  │  │  4. Line numbers & cursor (number, relativenumber, etc.)   │  │    ║
--- ║  │  │  5. Tabs & indentation (tabstop, shiftwidth, expandtab)    │  │    ║
--- ║  │  │  6. Display (wrap, scrolloff, termguicolors, listchars)    │  │    ║
--- ║  │  │  7. Search (ignorecase, smartcase, inccommand)             │  │    ║
--- ║  │  │  8. Splits (splitright, splitbelow, splitkeep)             │  │    ║
--- ║  │  │  9. Files & backup (undofile, swapfile, shada)             │  │    ║
--- ║  │  │  10. Folding (treesitter foldexpr)                         │  │    ║
--- ║  │  │  11. Completion & grep (rg integration)                    │  │    ║
--- ║  │  │  12. Session & terminal shell                              │  │    ║
--- ║  │  │  13. GUI / Neovide settings (conditional)                  │  │    ║
--- ║  │  │  14. Performance (lazyredraw, vim.loader, SSH opts)        │  │    ║
--- ║  │  │  15. Provider disabling (perl, ruby, node, python)         │  │    ║
--- ║  │  │  16. Dashboard-aware UI bar toggle (autocommands)          │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Dashboard UI toggle system:                                     │    ║
--- ║  │  ├─ Scans visible windows to classify: dashboard / real / tool   │    ║
--- ║  │  ├─ Dashboard visible + no real buffers → HIDE bars (clean mode) │    ║
--- ║  │  ├─ Real buffer visible → SHOW bars (full mode)                  │    ║
--- ║  │  ├─ Tool windows only → SHOW bars                                │    ║
--- ║  │  ├─ Lookup tables for filetypes built once from settings         │    ║
--- ║  │  │  (hash maps for O(1) classification)                          │    ║
--- ║  │  ├─ Debounced schedule_update() prevents rapid flickering        │    ║
--- ║  │  └─ Events: BufEnter, WinEnter, FileType, WinClosed, VimEnter    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ All option values read from settings:get() — no hardcoded    │    ║
--- ║  │  │  values except sensible fallback defaults                     │    ║
--- ║  │  ├─ Leaders set FIRST (before any keymaps load) because Neovim   │    ║
--- ║  │  │  resolves <leader> at keymap definition time, not invocation  │    ║
--- ║  │  ├─ Provider disabling happens here (not in plugins/) because    │    ║
--- ║  │  │  it must run before any plugin loads                          │    ║
--- ║  │  ├─ Neovide settings gated behind platform.is_gui check          │    ║
--- ║  │  ├─ SSH optimization reduces visual overhead for remote sessions │    ║
--- ║  │  └─ setup() is idempotent — safe to call on settings reload      │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Lookup tables built once (lazy-init), cached with _lookup_tables_built║
--- ║  • Window scanner skips floating windows (relative ~= "")                ║
--- ║  • Debounced UI update prevents rapid BufEnter/WinEnter flickering       ║
--- ║  • vim.loader.enable() called here for earliest possible cache activation║
--- ║  • Provider globals set to 0 to skip provider detection entirely         ║
--- ║                                                                          ║
--- ║  Public API:                                                             ║
--- ║    M.setup()                           Apply all options from settings   ║
--- ║    M.setup_dashboard_ui_toggle()       Set up dashboard bar autocommands ║
--- ║    M.is_dashboard_filetype(ft)         Check if ft is a dashboard        ║
--- ║    M.is_tool_filetype(ft)              Check if ft is a tool/sidebar     ║
--- ║    M.is_float_command(cmd)             Check if cmd opens a float        ║
--- ║    M.invalidate_cache()                Clear lookup table cache          ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
local platform = require("core.platform")

-- ═══════════════════════════════════════════════════════════════════════
-- MODULE DEFINITION
-- ═══════════════════════════════════════════════════════════════════════

---@class Options
local M = {}

-- ═══════════════════════════════════════════════════════════════════════
-- DASHBOARD UI — LOOKUP TABLES
--
-- Hash maps built once from settings arrays for O(1) filetype
-- classification. Used by the window scanner to determine whether
-- to show or hide UI bars (tabline, statusline, cmdheight).
-- Lazy-initialized on first access, invalidated on settings reload.
-- ═══════════════════════════════════════════════════════════════════════

--- Dashboard/start screen filetypes → hash map for O(1) lookup.
---@type table<string, boolean>
---@private
local _dashboard_ft_map = {}

--- Tool/sidebar filetypes → hash map for O(1) lookup.
---@type table<string, boolean>
---@private
local _tool_ft_map = {}

--- Commands that open floating windows → hash map for O(1) lookup.
---@type table<string, boolean>
---@private
local _float_cmd_map = {}

--- Guard flag: `true` after lookup tables have been built.
---@type boolean
---@private
local _lookup_tables_built = false

--- Build lookup hash maps from settings arrays (lazy-initialized, cached).
---
--- Converts the `dashboard_ui.*` settings arrays into hash maps
--- for O(1) filetype/command classification. Called automatically
--- on first access via `ensure_lookup_tables()`.
---@private
local function ensure_lookup_tables()
	if _lookup_tables_built then return end

	_dashboard_ft_map = {}
	for _, ft in ipairs(settings:get("dashboard_ui.dashboard_filetypes", {})) do
		_dashboard_ft_map[ft] = true
	end

	_tool_ft_map = {}
	for _, ft in ipairs(settings:get("dashboard_ui.tool_filetypes", {})) do
		_tool_ft_map[ft] = true
	end

	_float_cmd_map = {}
	for _, cmd in ipairs(settings:get("dashboard_ui.float_commands", {})) do
		_float_cmd_map[cmd] = true
	end

	_lookup_tables_built = true
end

--- Check if a filetype is a dashboard/start screen.
---
---@param ft string Filetype to check (e.g. `"snacks_dashboard"`, `"alpha"`)
---@return boolean is_dashboard `true` if `ft` is a known dashboard filetype
function M.is_dashboard_filetype(ft)
	ensure_lookup_tables()
	return _dashboard_ft_map[ft] == true
end

--- Check if a filetype is a tool/sidebar window.
---
---@param ft string Filetype to check (e.g. `"neo-tree"`, `"aerial"`, `"Trouble"`)
---@return boolean is_tool `true` if `ft` is a known tool filetype
function M.is_tool_filetype(ft)
	ensure_lookup_tables()
	return _tool_ft_map[ft] == true
end

--- Check if a command opens a floating window (should not close dashboard).
---
--- Extracts the first word from the command string and checks it
--- against the float commands hash map.
---
---@param cmd string Full command string (first word is extracted for matching)
---@return boolean is_float `true` if the command opens a floating window
function M.is_float_command(cmd)
	ensure_lookup_tables()
	local first = cmd:match("^(%S+)")
	return first ~= nil and _float_cmd_map[first] == true
end

--- Invalidate cached lookup tables.
---
--- Call after settings reload or user swap to force re-reading
--- of `dashboard_ui.*` settings on next access.
function M.invalidate_cache()
	_dashboard_ft_map = {}
	_tool_ft_map = {}
	_float_cmd_map = {}
	_lookup_tables_built = false
end

-- ═══════════════════════════════════════════════════════════════════════
-- WINDOW SCANNER
--
-- Scans all visible (non-floating) windows in the current tabpage
-- and classifies each by filetype. Used by the dashboard UI toggle
-- to determine the correct bar visibility state.
-- ═══════════════════════════════════════════════════════════════════════

--- Scan all visible windows in the current tabpage and classify them.
---
--- Iterates non-floating windows and categorizes each buffer:
--- • Dashboard filetype → `has_dashboard = true`
--- • Tool filetype → `has_tool = true`
--- • Normal buffer with content → `has_real_buffer = true`
---
--- Empty unnamed buffers are checked for content to avoid false positives
--- (Neovim opens with an empty buffer before the dashboard loads).
---
---@return { has_dashboard: boolean, has_real_buffer: boolean, has_tool: boolean } state
---@private
local function scan_visible_windows()
	ensure_lookup_tables()

	local result = {
		has_dashboard = false,
		has_real_buffer = false,
		has_tool = false,
	}

	for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win_id) then
			local win_cfg = vim.api.nvim_win_get_config(win_id)

			-- Skip floating windows entirely (Lazy, Mason, Telescope, etc.)
			if win_cfg.relative == "" then
				local buf = vim.api.nvim_win_get_buf(win_id)
				local ft = vim.bo[buf].filetype or ""
				local bt = vim.bo[buf].buftype or ""

				if _dashboard_ft_map[ft] then
					result.has_dashboard = true
				elseif _tool_ft_map[ft] then
					result.has_tool = true
				elseif bt == "" and ft ~= "" then
					result.has_real_buffer = true
				elseif bt == "" and ft == "" then
					-- Empty unnamed buffer: check if it has actual content
					local lines = vim.api.nvim_buf_get_lines(buf, 0, 2, false)
					local has_content = #lines > 1 or (#lines == 1 and lines[1] ~= "")
					if has_content then result.has_real_buffer = true end
				end
			end
		end
	end

	return result
end

-- ═══════════════════════════════════════════════════════════════════════
-- UI BAR VISIBILITY
--
-- Determines and applies the correct UI bar state based on
-- the window scanner results. Three modes:
-- 1. Real buffer visible → SHOW bars (normal editing)
-- 2. Dashboard only      → HIDE bars (clean startup screen)
-- 3. Tool windows only   → SHOW bars (sidebar without file)
-- ═══════════════════════════════════════════════════════════════════════

--- Determine and apply the correct UI bar visibility.
---
--- Rules:
--- 1. Real code buffer visible        → SHOW bars (showtabline, laststatus, cmdheight=1)
--- 2. Dashboard visible, no real code → HIDE bars (clean mode: all = 0)
--- 3. Only tool windows, no dashboard → SHOW bars
---
---@param target_showtabline integer Desired showtabline value when bars are shown
---@param target_laststatus integer Desired laststatus value when bars are shown
---@private
local function update_ui_bars(target_showtabline, target_laststatus)
	local state = scan_visible_windows()

	if state.has_real_buffer then
		vim.opt.showtabline = target_showtabline
		vim.opt.laststatus = target_laststatus
		vim.opt.cmdheight = 1
	elseif state.has_dashboard then
		vim.opt.showtabline = 0
		vim.opt.laststatus = 0
		vim.opt.cmdheight = 0
	else
		vim.opt.showtabline = target_showtabline
		vim.opt.laststatus = target_laststatus
		vim.opt.cmdheight = 1
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- DIRECTORY MANAGEMENT
--
-- Ensures all required subdirectories exist under cache/, data/,
-- and state/ before any file I/O operations. Reads directory lists
-- from settings.directories configuration.
-- ═══════════════════════════════════════════════════════════════════════

--- Ensure all required cache/data/state directories exist.
---
--- Reads directory lists from `settings.directories.*` and creates
--- any missing subdirectories under the corresponding stdpath.
---
---@private
local function ensure_directories()
	local bases = {
		cache = vim.fn.stdpath("cache") --[[@as string]],
		data = vim.fn.stdpath("data") --[[@as string]],
		state = vim.fn.stdpath("state") --[[@as string]],
	}

	for base_name, base_path in pairs(bases) do
		local subdirs = settings:get("directories." .. base_name, {})
		for _, subdir in ipairs(subdirs) do
			local full_path = base_path .. "/" .. subdir
			local stat = vim.uv.fs_stat(full_path)
			if not stat then pcall(vim.fn.mkdir, full_path, "p") end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- DASHBOARD UI TOGGLE
--
-- Autocommand-based system that automatically shows/hides the
-- tabline, statusline, and cmdheight based on what's visible.
-- Uses a debounced schedule to prevent rapid flickering during
-- buffer/window transitions.
-- ═══════════════════════════════════════════════════════════════════════

--- Set up autocommands for dashboard-aware UI bar toggling.
---
--- When the dashboard/start screen is the only visible buffer,
--- hides all UI bars for a clean aesthetic. As soon as a real
--- file buffer becomes visible, bars are restored.
---
--- Events monitored:
--- • `BufEnter`, `WinEnter`, `FileType` — buffer/window changes
--- • `WinClosed` — window close (deferred to avoid stale state)
--- • `VimEnter` — initial startup (deferred to let dashboard load)
function M.setup_dashboard_ui_toggle()
	if not settings:get("dashboard_ui.enabled", true) then return end

	local target_showtabline = settings:get("editor.show_tab_line", 2)
	local target_laststatus = settings:get("ui.global_statusline", true) and 3 or 2

	local augroup = vim.api.nvim_create_augroup("NvimEnterprise_DashboardUI", { clear = true })

	-- Debounced update to avoid rapid flickering during transitions
	local pending = false
	local function schedule_update()
		if pending then return end
		pending = true
		vim.schedule(function()
			pending = false
			update_ui_bars(target_showtabline, target_laststatus)
		end)
	end

	-- ── Core events that trigger re-evaluation ───────────────────────
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FileType" }, {
		group = augroup,
		callback = schedule_update,
		desc = "NvimEnterprise: Update UI bars on buffer/window change",
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function()
			-- Defer slightly because the window is still valid during the event
			vim.defer_fn(function()
				update_ui_bars(target_showtabline, target_laststatus)
			end, 10)
		end,
		desc = "NvimEnterprise: Re-evaluate UI bars when a window closes",
	})

	-- ── Initial startup ──────────────────────────────────────────────
	vim.api.nvim_create_autocmd("VimEnter", {
		group = augroup,
		once = true,
		callback = function()
			-- Defer to let dashboard plugin set its filetype
			vim.defer_fn(function()
				update_ui_bars(target_showtabline, target_laststatus)
			end, 80)
		end,
		desc = "NvimEnterprise: Clean UI on startup dashboard",
	})
end

-- ═══════════════════════════════════════════════════════════════════════
-- MAIN SETUP
--
-- Applies all vim.opt and vim.g settings from the merged settings.
-- Called once during bootstrap and can be re-called on user hot-swap.
-- The order matters: leaders must be set before keymaps, providers
-- must be disabled before plugins load, etc.
-- ═══════════════════════════════════════════════════════════════════════

--- Apply all Neovim options derived from the merged settings.
---
--- Called once during bootstrap. Can be re-called on user hot-swap
--- to apply the new user's option preferences. All option values
--- are read from `settings:get()` with sensible fallback defaults.
---
--- IMPORTANT: Leader keys are set FIRST because Neovim resolves
--- `<leader>` at keymap definition time, not at invocation time.
function M.setup()
	ensure_directories()

	local s = settings
	local opt = vim.opt
	local g = vim.g

	-- ── Leaders (must be set before any keymaps) ─────────────────────
	g.mapleader = s:get("keymaps.leader", " ")
	g.maplocalleader = s:get("keymaps.local_leader", "\\")

	-- ── General ──────────────────────────────────────────────────────
	opt.encoding = s:get("editor.encoding", "utf-8")
	opt.fileencoding = s:get("editor.file_encoding", "utf-8")
	opt.mouse = s:get("editor.mouse", "a")
	opt.clipboard = s:get("editor.clipboard", "unnamedplus")
	opt.confirm = s:get("editor.confirm", true)
	opt.autowrite = s:get("editor.auto_write", true)
	opt.hidden = true

	-- ── Line Numbers ─────────────────────────────────────────────────
	opt.number = s:get("editor.number", true)
	opt.relativenumber = s:get("editor.relative_number", true)
	opt.cursorline = s:get("editor.cursor_line", true)
	opt.cursorcolumn = s:get("editor.cursor_column", true)
	opt.signcolumn = s:get("editor.sign_column", "yes")

	-- ── Tabs / Indentation ───────────────────────────────────────────
	local tab_size = s:get("editor.tab_size", 2)
	opt.tabstop = tab_size
	opt.shiftwidth = tab_size
	opt.softtabstop = tab_size
	opt.expandtab = s:get("editor.use_spaces", true)
	opt.smartindent = true
	opt.autoindent = true
	opt.shiftround = true

	-- ── Display ──────────────────────────────────────────────────────
	opt.wrap = s:get("editor.wrap", false)
	opt.wrapscan = s:get("editor.wrap_scan", false)
	opt.linebreak = true
	opt.scrolloff = s:get("editor.scroll_off", 8)
	opt.sidescrolloff = s:get("editor.side_scroll_off", 8)
	opt.pumheight = s:get("editor.pumheight", 10)
	opt.pumblend = 10
	opt.showmode = false
	opt.showcmd = false
	opt.showbreak = "↳  "
	opt.cmdheight = 1
	opt.termguicolors = platform.has_true_color
	opt.list = true
	opt.listchars = s:get("editor.list_chars")
	opt.conceallevel = 2

	-- ── Tabline & Statusline (initial — managed by dashboard toggle) ─
	opt.showtabline = s:get("editor.show_tab_line", 2)
	opt.laststatus = s:get("ui.global_statusline", true) and 3 or 2

	-- ── Fill Characters ──────────────────────────────────────────────
	local fill = s:get("editor.fill_chars")
	if fill then opt.fillchars = fill end

	-- ── Search ───────────────────────────────────────────────────────
	opt.ignorecase = s:get("editor.search_ignore_case", true)
	opt.smartcase = s:get("editor.search_smart_case", true)
	opt.hlsearch = true
	opt.incsearch = true
	opt.inccommand = "nosplit"

	-- ── Splits ───────────────────────────────────────────────────────
	opt.splitright = s:get("editor.split_right", true)
	opt.splitbelow = s:get("editor.split_below", true)
	opt.splitkeep = "screen"

	-- ── Files / Backup ───────────────────────────────────────────────
	local cache_dir = vim.fn.stdpath("cache") --[[@as string]]
	local state_dir = vim.fn.stdpath("state") --[[@as string]]

	opt.undofile = s:get("editor.undo_file", true)
	opt.undolevels = 10000
	opt.undodir = cache_dir .. "/undo"

	opt.swapfile = s:get("editor.swap_file", false)
	opt.directory = cache_dir .. "/swap//"

	opt.backup = s:get("editor.backup", false)
	opt.writebackup = false
	opt.backupdir = cache_dir .. "/backup//"

	opt.shadafile = state_dir .. "/shada/main.shada"

	opt.updatetime = s:get("editor.update_time", 200)
	opt.timeoutlen = s:get("editor.timeout_len", 300)

	-- ── Folding ──────────────────────────────────────────────────────
	opt.foldlevel = s:get("editor.fold_level", 99)
	opt.foldlevelstart = 99
	opt.foldmethod = s:get("editor.fold_method", "expr")
	if s:get("editor.fold_method") == "expr" then
		opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
		opt.foldtext = ""
	end

	-- ── Completion ───────────────────────────────────────────────────
	opt.completeopt = "menu,menuone,noselect"
	opt.wildmode = "longest:full,full"

	-- ── Grep (rg integration) ────────────────────────────────────────
	if platform:has_executable("rg") then
		opt.grepprg = "rg --vimgrep --no-heading --smart-case"
		opt.grepformat = "%f:%l:%c:%m"
	end

	-- ── Session ──────────────────────────────────────────────────────
	opt.sessionoptions = s:get("editor.session_options")

	-- ── Terminal ─────────────────────────────────────────────────────
	local shell = s:get("editor.terminal_shell")
	if shell then opt.shell = shell end

	-- ── Format Options (prevent auto-comment on new lines) ───────────
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "*",
		callback = function()
			vim.opt_local.formatoptions:remove({ "r", "o" })
		end,
	})

	-- ── GUI / Neovide Settings ───────────────────────────────────────
	if platform.is_gui then
		opt.guifont = s:get("ui.gui_font", "JetBrainsMono Nerd Font:h14")

		if vim.g.neovide then
			-- Window & Rendering
			vim.g.neovide_opacity = s:get("neovide.opacity", 0.8)
			vim.g.neovide_background_color = s:get("neovide.background_color", "#0f1117")
			vim.g.neovide_window_blurred = s:get("neovide.window_blurred", true)
			vim.g.neovide_remember_window_size = s:get("neovide.remember_window_size", true)
			vim.g.neovide_floating_shadow = s:get("neovide.floating_shadow", true)
			vim.g.neovide_light_radius = s:get("neovide.light_radius", 5)

			-- Padding
			vim.g.neovide_padding_left = s:get("neovide.padding_left", 20)
			vim.g.neovide_padding_top = s:get("neovide.padding_top", 20)

			-- Cursor Effects
			vim.g.neovide_cursor_animation_length = s:get("neovide.cursor_animation_length", 0.03)
			vim.g.neovide_cursor_trail_size = s:get("neovide.cursor_trail_size", 0.05)
			vim.g.neovide_cursor_antialiasing = s:get("neovide.cursor_antialiasing", true)
			vim.g.neovide_cursor_vfx_mode = s:get("neovide.cursor_vfx_mode", "railgun")
			vim.g.neovide_cursor_vfx_particle_speed = s:get("neovide.cursor_vfx_particle_speed", 20.0)
			vim.g.neovide_cursor_vfx_particle_density = s:get("neovide.cursor_vfx_particle_density", 5.0)

			-- Input Behavior
			vim.g.neovide_input_use_logo = s:get("neovide.input_time", true)
			vim.g.neovide_hide_mouse_when_typing = s:get("neovide.hide_mouse_when_typing", true)
			vim.g.neovide_input_macos_alt_is_meta = s:get("neovide.input_macos_alt_is_meta", false)

			-- Transparency Integration
			if s:get("ui.transparent_background", false) then
				vim.g.neovide_opacity = s:get("neovide.opacity", 0.8)
			else
				vim.g.neovide_opacity = 1.0
			end
		end
	end

	-- ── Performance ──────────────────────────────────────────────────
	opt.lazyredraw = s:get("editor.lazy_redraw", false)
	opt.synmaxcol = 240
	opt.redrawtime = 1500

	if s:get("performance.cache", true) then
		if vim.loader then vim.loader.enable() end
	end

	-- ── SSH Optimizations ────────────────────────────────────────────
	if platform.is_ssh and s:get("performance.ssh_optimization", true) then
		opt.ttyfast = true
		opt.lazyredraw = false
		opt.synmaxcol = 240
	end

	-- ── Fonts, Icons & Advanced UI ───────────────────────────────────
	g.have_nerd_font = s:get("editor.have_nerd_font", true)
	g.netrw_liststyle = s:get("editor.netrw_list_style", 3)

	-- ── Providers (disable unused for faster startup) ────────────────
	g.loaded_perl_provider = 0
	g.loaded_ruby_provider = 0
	g.loaded_node_provider = 0
	g.loaded_python3_provider = 0

	-- ── Dashboard-Aware UI Toggle ────────────────────────────────────
	M.setup_dashboard_ui_toggle()
end

return M
