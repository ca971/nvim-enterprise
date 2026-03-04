---@file lua/plugins/ui/bufferline.lua
---@description Bufferline — Enterprise-grade buffer tabline with LSP diagnostics
---@module "plugins.ui.bufferline"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings          Plugin enable/disable guard
---@see core.icons             Icon provider (tab indicators, diagnostics, sidebar labels)
---@see plugins.ui.lualine     Statusline counterpart (bottom bar)
---@see plugins.editor.mini    mini.bufremove integration for safe buffer deletion
---@see config.colorscheme_manager Colorscheme changes trigger highlight refresh
---@see plugins.editor.neo-tree   Sidebar offset for file explorer
---@see plugins.editor.aerial     Sidebar offset for symbol outline
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ui/bufferline.lua — Buffer tabline management                   ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  bufferline.nvim (akinsho/bufferline.nvim)                       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Visual Layer:                                                   │    ║
--- ║  │  ├─ Custom highlights (Catppuccin Mocha palette, 60+ groups)     │    ║
--- ║  │  ├─ Gradient-style active/inactive tab distinction               │    ║
--- ║  │  ├─ Bold active tab with icon indicator (▎)                      │    ║
--- ║  │  ├─ Modified dot with accent color (peach)                       │    ║
--- ║  │  ├─ Colored diagnostics inline (error/warn/info/hint)            │    ║
--- ║  │  ├─ Pick letters with bold red highlight                         │    ║
--- ║  │  └─ Hover-reveal close button (150ms delay)                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer Management:                                              │    ║
--- ║  │  ├─ Pin/unpin with group separation                              │    ║
--- ║  │  ├─ Safe deletion via mini.bufremove (preserves layout)          │    ║
--- ║  │  ├─ Close others / left / right                                  │    ║
--- ║  │  ├─ Sort by directory or extension                               │    ║
--- ║  │  ├─ Pick buffer by letter                                        │    ║
--- ║  │  └─ Ordinal numbering (1, 2, 3…) in tabs                         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Sidebar Offsets:                                                │    ║
--- ║  │  ├─ neo-tree       "󰙅  File Explorer"                            │    ║
--- ║  │  ├─ NvimTree       "󰙅  File Explorer"                            │    ║
--- ║  │  ├─ aerial         "󰅩  Symbols"                                  │    ║
--- ║  │  └─ undotree       "󰄉  Undo History"                             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Dashboard Integration:                                          │    ║
--- ║  │  ├─ Hidden on no-args launch (showtabline=0)                     │    ║
--- ║  │  ├─ Auto-reveal on first BufReadPost for a real file             │    ║
--- ║  │  └─ Filters: alpha, dashboard, ministarter, snacks_dashboard     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Autocmds:                                                       │    ║
--- ║  │  ├─ BufReadPost  → reveal tabline after dashboard                │    ║
--- ║  │  ├─ BufAdd/Delete → refresh after session restore                │    ║
--- ║  │  └─ ColorScheme  → re-apply custom highlights                    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (27 bindings):                                          │    ║
--- ║  │  ├─ <leader>bp/bP   Pin toggle / Close unpinned                  │    ║
--- ║  │  ├─ <leader>bo/br/bl Close others / right / left                 │    ║
--- ║  │  ├─ <leader>bd/bj   Pick to delete / Pick to jump                │    ║
--- ║  │  ├─ <leader>bs/bS   Sort by dir / extension                      │    ║
--- ║  │  ├─ <S-h>/<S-l>     Cycle prev / next                            │    ║
--- ║  │  ├─ [b/]b           Cycle prev / next (bracket style)            │    ║
--- ║  │  ├─ [B/]B           Move buffer left / right                     │    ║
--- ║  │  └─ <A-1>..<A-9>    Direct buffer access (9 = last)              │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Custom Filter (hidden filetypes/buftypes):                              ║
--- ║  • buftype: terminal, quickfix                                           ║
--- ║  • filetype: qf, fugitive, gitcommit, dashboard variants                 ║
--- ║                                                                          ║
--- ║  Defensive Design:                                                       ║
--- ║  • icon() helper with fallback — never crashes on missing icons          ║
--- ║  • pcall on mini.bufremove — falls back to nvim_buf_delete               ║
--- ║  • pcall on BufferLineRefresh — safe during startup transitions          ║
--- ║  • pcall on bufferline.groups — compatible with v3 and v4                ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok and not settings:is_plugin_enabled("bufferline") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- SAFE REQUIRES
--
-- Icons are loaded defensively: if core.icons is unavailable (e.g.
-- during minimal startup or testing), a hardcoded fallback table is
-- used. This guarantees bufferline never crashes on missing icons.
-- ═══════════════════════════════════════════════════════════════════════════

local icons_ok, icons = pcall(require, "core.icons")

if not icons_ok or not icons then
	icons = {
		ui = {
			BoldLineLeft = "▎",
			Pencil = "●",
			BoldArrowLeft = "",
			BoldArrowRight = "",
			BoldClose = "×",
			Tree = "󰙅",
			Close = "×",
			BookMark = "󰃀",
			Code = "󰅩",
			History = "󰄉",
			Folder = "📁",
			File = "📄",
			Target = "🎯",
		},
		diagnostics = { Error = " ", Warn = " ", Info = " ", Hint = "󰌵 " },
	}
end

--- Safely access an icon from a table with fallback.
---
--- Used throughout this file to prevent crashes when icon tables
--- are partially populated or when a key is renamed upstream.
---@param tbl table|nil Icon category table (e.g. `icons.ui`)
---@param key string Icon key name (e.g. `"BookMark"`)
---@param fallback string Fallback string if key is missing
---@return string icon The resolved icon or fallback
local function icon(tbl, key, fallback)
	if type(tbl) == "table" and tbl[key] ~= nil then return tbl[key] end
	return fallback or ""
end

--- Cached icon category references for repeated use in keymaps and options.
---@type table<string, string>
local ui = icons.ui or {}

--- Cached diagnostics icon category reference.
---@type table<string, string>
local dg = icons.diagnostics or {}

-- ═══════════════════════════════════════════════════════════════════════════
-- DASHBOARD DETECTION
--
-- On no-args launch (nvim without files), the tabline is hidden
-- to give the dashboard full visual space. It auto-reveals on the
-- first real file open via a one-shot BufReadPost autocmd.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check if Neovim was launched without file arguments.
---@return boolean is_dashboard True if argc == 0 (dashboard mode)
local function is_dashboard_launch()
	return vim.fn.argc(-1) == 0
end

--- Filetypes considered "dashboard" — bufferline is hidden on these.
--- Maps filetype → true for O(1) lookup in custom_filter and autocmds.
---@type table<string, boolean>
local dashboard_filetypes = {
	alpha = true,
	dashboard = true,
	ministarter = true,
	snacks_dashboard = true,
	starter = true,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Safely delete a buffer using mini.bufremove or native API.
---
--- mini.bufremove preserves window layout when closing buffers.
--- Falls back to nvim_buf_delete if mini.bufremove is not installed.
---@param bufnr integer Buffer number to delete
---@param force boolean|nil Force deletion even if buffer is modified
---@return nil
local function safe_buf_delete(bufnr, force)
	local ok, bufremove = pcall(require, "mini.bufremove")
	if ok then
		bufremove.delete(bufnr, force or false)
	else
		pcall(vim.api.nvim_buf_delete, bufnr, { force = force or false })
	end
end

--- Build the diagnostics indicator string for a buffer tab.
---
--- Displays error/warning/info counts inline in the tab, using
--- the appropriate diagnostic icon for each severity level.
--- Returns an empty string if no diagnostics are present.
---@param _count integer Total diagnostic count (unused — we use per-level)
---@param _level integer Highest severity level (unused)
---@param diag table<string, integer> Per-level counts: `{ error, warning, info, hint }`
---@return string indicator Formatted diagnostics string (e.g. " 2  1")
local function diagnostics_indicator(_count, _level, diag)
	local parts = {}
	if diag.error and diag.error > 0 then parts[#parts + 1] = icon(dg, "Error", " ") .. diag.error end
	if diag.warning and diag.warning > 0 then parts[#parts + 1] = icon(dg, "Warn", " ") .. diag.warning end
	if diag.info and diag.info > 0 then parts[#parts + 1] = icon(dg, "Info", " ") .. diag.info end
	return #parts > 0 and (" " .. table.concat(parts, " ")) or ""
end

-- ═══════════════════════════════════════════════════════════════════════════
-- COLOR PALETTE
--
-- Catppuccin Mocha inspired palette — works well on dark themes.
-- Used exclusively for custom highlight groups below.
-- If using a Catppuccin colorscheme with bufferline integration,
-- these may be overridden by the theme — the ColorScheme autocmd
-- handles refresh in that case.
--
-- Reference: https://github.com/catppuccin/catppuccin
-- ═══════════════════════════════════════════════════════════════════════════

---@type table<string, string> Hex color codes for highlight groups
local palette = {
	-- ── Base tones ────────────────────────────────────────────────────
	bg_dark = "#11111b", -- crust
	bg = "#1e1e2e", -- base
	bg_light = "#181825", -- mantle
	surface0 = "#313244",
	surface1 = "#45475a",
	surface2 = "#585b70",
	overlay0 = "#6c7086",
	overlay1 = "#7f849c",

	-- ── Text tones ───────────────────────────────────────────────────
	text = "#cdd6f4",
	subtext0 = "#a6adc8",
	subtext1 = "#bac2de",

	-- ── Accent colors ────────────────────────────────────────────────
	red = "#f38ba8",
	peach = "#fab387",
	yellow = "#f9e2af",
	green = "#a6e3a1",
	teal = "#94e2d5",
	blue = "#89b4fa",
	lavender = "#b4befe",
	mauve = "#cba6f7",
	flamingo = "#f2cdcd",
	sapphire = "#74c7ec",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- CUSTOM HIGHLIGHTS
--
-- 60+ highlight groups organized by UI element. Each group defines
-- three states: default (inactive), visible (visible but not focused),
-- and selected (active/focused tab).
--
-- Color mapping:
--   • Active tab:    bg=base,   fg=text,    bold
--   • Visible tab:   bg=mantle, fg=overlay1
--   • Inactive tab:  bg=mantle, fg=overlay0
--   • Indicators:    blue (active), surface1 (visible)
--   • Modified dot:  peach (accent)
--   • Close button:  red (selected), surface2 (inactive)
--   • Diagnostics:   red/yellow/sapphire/teal per severity
--   • Pick letters:  red bold
--   • Group labels:  blue bg with dark fg (inverted)
-- ═══════════════════════════════════════════════════════════════════════════

--- Build the complete highlights table for bufferline.setup().
---
--- Returns a table mapping highlight group names to their fg/bg/bold/italic
--- attributes. Groups are organized by UI element with three states each:
--- default (inactive), visible, and selected.
---@return table<string, table> highlights Bufferline highlight configuration
local function build_highlights()
	return {
		-- ── Fill (empty space between tabs and edges) ──────────────────
		fill = {
			bg = palette.bg_dark,
		},

		-- ── Tab bar background ────────────────────────────────────────
		background = {
			fg = palette.overlay0,
			bg = palette.bg_light,
		},

		-- ── Buffers (inactive / visible / selected) ───────────────────
		buffer_visible = {
			fg = palette.overlay1,
			bg = palette.bg_light,
		},
		buffer_selected = {
			fg = palette.text,
			bg = palette.bg,
			bold = true,
			italic = false,
		},

		-- ── Close button ──────────────────────────────────────────────
		close_button = {
			fg = palette.surface2,
			bg = palette.bg_light,
		},
		close_button_visible = {
			fg = palette.overlay0,
			bg = palette.bg_light,
		},
		close_button_selected = {
			fg = palette.red,
			bg = palette.bg,
		},

		-- ── Modified dot ──────────────────────────────────────────────
		modified = {
			fg = palette.surface2,
			bg = palette.bg_light,
		},
		modified_visible = {
			fg = palette.peach,
			bg = palette.bg_light,
		},
		modified_selected = {
			fg = palette.peach,
			bg = palette.bg,
		},

		-- ── Separators ────────────────────────────────────────────────
		separator = {
			fg = palette.bg_dark,
			bg = palette.bg_light,
		},
		separator_visible = {
			fg = palette.bg_dark,
			bg = palette.bg_light,
		},
		separator_selected = {
			fg = palette.bg_dark,
			bg = palette.bg,
		},

		-- ── Indicator (left bar on active tab) ────────────────────────
		indicator_visible = {
			fg = palette.surface1,
			bg = palette.bg_light,
		},
		indicator_selected = {
			fg = palette.blue,
			bg = palette.bg,
		},

		-- ── Tab numbers ───────────────────────────────────────────────
		numbers = {
			fg = palette.surface2,
			bg = palette.bg_light,
		},
		numbers_visible = {
			fg = palette.overlay0,
			bg = palette.bg_light,
		},
		numbers_selected = {
			fg = palette.blue,
			bg = palette.bg,
			bold = true,
		},

		-- ── Duplicate prefix ──────────────────────────────────────────
		duplicate = {
			fg = palette.surface2,
			bg = palette.bg_light,
			italic = true,
		},
		duplicate_visible = {
			fg = palette.overlay0,
			bg = palette.bg_light,
			italic = true,
		},
		duplicate_selected = {
			fg = palette.lavender,
			bg = palette.bg,
			italic = true,
		},

		-- ── Diagnostics (generic) ─────────────────────────────────────
		diagnostic = {
			fg = palette.surface2,
			bg = palette.bg_light,
		},
		diagnostic_visible = {
			fg = palette.overlay0,
			bg = palette.bg_light,
		},
		diagnostic_selected = {
			fg = palette.text,
			bg = palette.bg,
		},

		-- ── Diagnostics: Error (red) ──────────────────────────────────
		error = {
			fg = palette.surface2,
			bg = palette.bg_light,
		},
		error_visible = {
			fg = palette.red,
			bg = palette.bg_light,
		},
		error_selected = {
			fg = palette.red,
			bg = palette.bg,
			bold = true,
		},
		error_diagnostic = {
			fg = palette.surface2,
			bg = palette.bg_light,
		},
		error_diagnostic_visible = {
			fg = palette.red,
			bg = palette.bg_light,
		},
		error_diagnostic_selected = {
			fg = palette.red,
			bg = palette.bg,
		},

		-- ── Diagnostics: Warning (yellow) ─────────────────────────────
		warning = {
			fg = palette.surface2,
			bg = palette.bg_light,
		},
		warning_visible = {
			fg = palette.yellow,
			bg = palette.bg_light,
		},
		warning_selected = {
			fg = palette.yellow,
			bg = palette.bg,
			bold = true,
		},
		warning_diagnostic = {
			fg = palette.surface2,
			bg = palette.bg_light,
		},
		warning_diagnostic_visible = {
			fg = palette.yellow,
			bg = palette.bg_light,
		},
		warning_diagnostic_selected = {
			fg = palette.yellow,
			bg = palette.bg,
		},

		-- ── Diagnostics: Info (sapphire) ──────────────────────────────
		info = {
			fg = palette.surface2,
			bg = palette.bg_light,
		},
		info_visible = {
			fg = palette.sapphire,
			bg = palette.bg_light,
		},
		info_selected = {
			fg = palette.sapphire,
			bg = palette.bg,
		},
		info_diagnostic = {
			fg = palette.surface2,
			bg = palette.bg_light,
		},
		info_diagnostic_visible = {
			fg = palette.sapphire,
			bg = palette.bg_light,
		},
		info_diagnostic_selected = {
			fg = palette.sapphire,
			bg = palette.bg,
		},

		-- ── Diagnostics: Hint (teal) ──────────────────────────────────
		hint = {
			fg = palette.surface2,
			bg = palette.bg_light,
		},
		hint_visible = {
			fg = palette.teal,
			bg = palette.bg_light,
		},
		hint_selected = {
			fg = palette.teal,
			bg = palette.bg,
		},
		hint_diagnostic = {
			fg = palette.surface2,
			bg = palette.bg_light,
		},
		hint_diagnostic_visible = {
			fg = palette.teal,
			bg = palette.bg_light,
		},
		hint_diagnostic_selected = {
			fg = palette.teal,
			bg = palette.bg,
		},

		-- ── Pick letter ───────────────────────────────────────────────
		pick = {
			fg = palette.red,
			bg = palette.bg_light,
			bold = true,
		},
		pick_visible = {
			fg = palette.red,
			bg = palette.bg_light,
			bold = true,
		},
		pick_selected = {
			fg = palette.red,
			bg = palette.bg,
			bold = true,
		},

		-- ── Tab pages (right side) ────────────────────────────────────
		tab = {
			fg = palette.overlay0,
			bg = palette.bg_light,
		},
		tab_selected = {
			fg = palette.text,
			bg = palette.bg,
			bold = true,
		},
		tab_separator = {
			fg = palette.bg_dark,
			bg = palette.bg_light,
		},
		tab_separator_selected = {
			fg = palette.bg_dark,
			bg = palette.bg,
		},
		tab_close = {
			fg = palette.red,
			bg = palette.bg_light,
		},

		-- ── Truncation marker ─────────────────────────────────────────
		trunc_marker = {
			fg = palette.overlay0,
			bg = palette.bg_dark,
		},

		-- ── Offset (sidebar) ──────────────────────────────────────────
		offset_separator = {
			fg = palette.surface0,
			bg = palette.bg_dark,
		},

		-- ── Groups ────────────────────────────────────────────────────
		group_label = {
			fg = palette.bg_dark,
			bg = palette.blue,
			bold = true,
		},
		group_separator = {
			fg = palette.blue,
			bg = palette.bg_dark,
		},
	}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
--
-- Lazy.nvim plugin specification. Loading strategy:
-- • With files: loads on VeryLazy (after UI is painted)
-- • Without files (dashboard): deferred until first BufReadPost
-- ═══════════════════════════════════════════════════════════════════════════

return {
	"akinsho/bufferline.nvim",

	--- Dynamic event: skip loading entirely on dashboard launches.
	--- Returns empty table (no events) for dashboard, VeryLazy otherwise.
	---@return string[] events Event list for lazy.nvim
	event = function()
		if is_dashboard_launch() then return {} end
		return { "VeryLazy" }
	end,

	dependencies = { "nvim-mini/mini.icons" },

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYMAPS
	--
	-- 27 keybindings organized by function:
	-- • Buffer lifecycle:  pin, close, delete, pick
	-- • Navigation:        cycle, move, direct access
	-- • Organization:      sort by directory/extension
	-- ═══════════════════════════════════════════════════════════════════

	keys = {
		-- ── Pin & Close ───────────────────────────────────────────────
		{
			"<leader>bp",
			"<cmd>BufferLineTogglePin<cr>",
			desc = icon(ui, "BookMark", "📌") .. " Pin buffer",
		},
		{
			"<leader>bP",
			"<cmd>BufferLineGroupClose ungrouped<cr>",
			desc = icon(ui, "BoldClose", "×") .. " Close unpinned",
		},
		{ "<leader>bo", "<cmd>BufferLineCloseOthers<cr>", desc = icon(ui, "Close", "×") .. " Close others" },
		{
			"<leader>br",
			"<cmd>BufferLineCloseRight<cr>",
			desc = icon(ui, "BoldArrowRight", "→") .. " Close to right",
		},
		{
			"<leader>bl",
			"<cmd>BufferLineCloseLeft<cr>",
			desc = icon(ui, "BoldArrowLeft", "←") .. " Close to left",
		},

		-- ── Navigation: Cycle ─────────────────────────────────────────
		{ "<S-h>", "<cmd>BufferLineCyclePrev<cr>", desc = "Previous buffer" },
		{ "<S-l>", "<cmd>BufferLineCycleNext<cr>", desc = "Next buffer" },
		{ "[b", "<cmd>BufferLineCyclePrev<cr>", desc = "Previous buffer" },
		{ "]b", "<cmd>BufferLineCycleNext<cr>", desc = "Next buffer" },

		-- ── Navigation: Move ──────────────────────────────────────────
		{ "[B", "<cmd>BufferLineMovePrev<cr>", desc = "Move buffer left" },
		{ "]B", "<cmd>BufferLineMoveNext<cr>", desc = "Move buffer right" },

		-- ── Sort ──────────────────────────────────────────────────────
		{
			"<leader>bs",
			"<cmd>BufferLineSortByDirectory<cr>",
			desc = icon(ui, "Folder", "📁") .. " Sort by directory",
		},
		{
			"<leader>bS",
			"<cmd>BufferLineSortByExtension<cr>",
			desc = icon(ui, "File", "📄") .. " Sort by extension",
		},

		-- ── Pick ──────────────────────────────────────────────────────
		{
			"<leader>bj",
			"<cmd>BufferLinePick<cr>",
			desc = icon(ui, "Target", "🎯") .. " Pick buffer",
		},
		{
			"<leader>bd",
			"<cmd>BufferLinePickClose<cr>",
			desc = icon(ui, "BoldClose", "×") .. " Pick buffer to close",
		},

		-- ── Direct access: Alt+1..9 ──────────────────────────────────
		{ "<A-1>", "<cmd>BufferLineGoToBuffer 1<cr>", desc = "Buffer 1" },
		{ "<A-2>", "<cmd>BufferLineGoToBuffer 2<cr>", desc = "Buffer 2" },
		{ "<A-3>", "<cmd>BufferLineGoToBuffer 3<cr>", desc = "Buffer 3" },
		{ "<A-4>", "<cmd>BufferLineGoToBuffer 4<cr>", desc = "Buffer 4" },
		{ "<A-5>", "<cmd>BufferLineGoToBuffer 5<cr>", desc = "Buffer 5" },
		{ "<A-6>", "<cmd>BufferLineGoToBuffer 6<cr>", desc = "Buffer 6" },
		{ "<A-7>", "<cmd>BufferLineGoToBuffer 7<cr>", desc = "Buffer 7" },
		{ "<A-8>", "<cmd>BufferLineGoToBuffer 8<cr>", desc = "Buffer 8" },
		{ "<A-9>", "<cmd>BufferLineGoToBuffer -1<cr>", desc = "Last buffer" },
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	-- ═══════════════════════════════════════════════════════════════════

	opts = {
		highlights = build_highlights(),

		options = {
			-- ── Buffer management ─────────────────────────────────────
			close_command = function(n)
				safe_buf_delete(n, false)
			end,
			right_mouse_command = function(n)
				safe_buf_delete(n, false)
			end,
			middle_mouse_command = function(n)
				safe_buf_delete(n, false)
			end,

			-- ── Tab numbering ─────────────────────────────────────────
			--- Show ordinal position (1, 2, 3…) in each tab.
			--- Uses raise() for superscript rendering if supported.
			---@param opts table Bufferline number options (ordinal, id, raise, lower)
			---@return string formatted Formatted ordinal string
			numbers = function(opts)
				return string.format("%s", opts.raise(opts.ordinal))
			end,

			-- ── Appearance ────────────────────────────────────────────
			mode = "buffers",
			themable = true,
			always_show_bufferline = true,
			show_buffer_close_icons = true,
			show_close_icon = false,
			show_tab_indicators = true,
			show_duplicate_prefix = true,
			color_icons = true,
			enforce_regular_tabs = false,
			truncate_names = true,

			-- ── Tab sizing ────────────────────────────────────────────
			tab_size = 20,
			max_name_length = 22,
			max_prefix_length = 15,
			padding = 1,

			-- ── Separator style ───────────────────────────────────────
			-- Available styles:
			-- "slant"        :  ╱  tabs with angled edges
			-- "padded_slant" :  ╱  with extra padding
			-- "slope"        :  ╲  diagonal
			-- "thick"        :  ▌▐ solid blocks
			-- "thin"         :  │  minimal lines
			-- { '▏', '▕' }  :  custom thin bars
			separator_style = "thin",

			-- ── Indicator (active tab marker) ─────────────────────────
			indicator = {
				style = "icon",
				icon = icon(ui, "BoldLineLeft", "▎"),
			},

			-- ── Icons ─────────────────────────────────────────────────
			modified_icon = icon(ui, "Pencil", "●"),
			left_trunc_marker = icon(ui, "BoldArrowLeft", ""),
			right_trunc_marker = icon(ui, "BoldArrowRight", ""),
			buffer_close_icon = icon(ui, "BoldClose", "󰅖"),

			-- ── Diagnostics ───────────────────────────────────────────
			diagnostics = "nvim_lsp",
			diagnostics_update_in_insert = false,
			diagnostics_indicator = diagnostics_indicator,

			-- ── Sidebar offsets ───────────────────────────────────────
			offsets = {
				{
					filetype = "neo-tree",
					text = icon(ui, "Tree", "󰙅") .. "  File Explorer",
					highlight = "Directory",
					text_align = "center",
					separator = true,
				},
				{
					filetype = "NvimTree",
					text = icon(ui, "Tree", "󰙅") .. "  File Explorer",
					highlight = "Directory",
					text_align = "center",
					separator = true,
				},
				{
					filetype = "aerial",
					text = icon(ui, "Code", "󰅩") .. "  Symbols",
					highlight = "Directory",
					text_align = "center",
					separator = true,
				},
				{
					filetype = "undotree",
					text = icon(ui, "History", "󰄉") .. "  Undo History",
					highlight = "Directory",
					text_align = "center",
					separator = true,
				},
			},

			-- ── Hover ─────────────────────────────────────────────────
			hover = {
				enabled = true,
				delay = 150,
				reveal = { "close" },
			},

			-- ── Custom filter ─────────────────────────────────────────
			--- Filter out non-file buffers from the tabline.
			---
			--- Excludes terminal, quickfix, dashboard variants,
			--- fugitive, and gitcommit buffers.
			---@param buf_number integer Buffer number to evaluate
			---@return boolean visible Whether the buffer should appear in tabline
			custom_filter = function(buf_number)
				local bt = vim.bo[buf_number].buftype
				local ft = vim.bo[buf_number].filetype

				if bt == "terminal" or bt == "quickfix" then return false end
				if dashboard_filetypes[ft] then return false end

				local hidden = { qf = true, fugitive = true, gitcommit = true, [""] = true }
				return not hidden[ft]
			end,
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- CONFIG
	--
	-- Post-setup configuration:
	-- 1. Register pinned buffer group (v3/v4 compatible)
	-- 2. Dashboard mode: hide tabline, reveal on first real file
	-- 3. Session restore: refresh on BufAdd/BufDelete
	-- 4. ColorScheme change: re-apply custom highlights
	-- ═══════════════════════════════════════════════════════════════════

	config = function(_, opts)
		-- ── Step 1: Pinned group (v3/v4 compatible) ───────────────────
		local groups_ok, bl_groups = pcall(require, "bufferline.groups")
		if groups_ok and bl_groups.builtin and bl_groups.builtin.pinned then
			opts.options.groups = {
				items = {
					bl_groups.builtin.pinned:with({
						icon = icon(ui, "BookMark", "󰃀"),
					}),
				},
			}
		end

		require("bufferline").setup(opts)

		-- ── Step 2: Dashboard mode — hide tabline, reveal on file ─────
		if is_dashboard_launch() then
			vim.o.showtabline = 0

			vim.api.nvim_create_autocmd("BufReadPost", {
				group = vim.api.nvim_create_augroup("BufferlineDashboardShow", { clear = true }),
				once = true,
				callback = function(ev)
					local ft = vim.bo[ev.buf].filetype
					local bt = vim.bo[ev.buf].buftype

					if dashboard_filetypes[ft] or bt == "nofile" then return false end

					vim.o.showtabline = 2
					vim.schedule(function()
						pcall(function()
							vim.cmd.BufferLineRefresh()
						end)
					end)
					return true
				end,
				desc = "NvimEnterprise: Show bufferline on first real file",
			})
		end

		-- ── Step 3: Session restore fix ───────────────────────────────
		vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete" }, {
			group = vim.api.nvim_create_augroup("BufferlineSessionFix", { clear = true }),
			callback = function()
				vim.schedule(function()
					pcall(function()
						vim.cmd.BufferLineRefresh()
					end)
				end)
			end,
			desc = "NvimEnterprise: Refresh bufferline after buffer add/delete",
		})

		-- ── Step 4: Re-apply highlights on colorscheme change ─────────
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("BufferlineColorScheme", { clear = true }),
			callback = function()
				vim.schedule(function()
					pcall(function()
						vim.cmd.BufferLineRefresh()
					end)
				end)
			end,
			desc = "NvimEnterprise: Refresh bufferline highlights on colorscheme change",
		})
	end,
}
