---@file lua/plugins/editor/which-key.lua
---@description Which-key — pro-grade keymap discovery with custom icon rules
---@module "plugins.editor.which-key"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.keymaps     Centralized group definitions and keymap setup
---@see core.icons       Icon source of truth (used by icon_rules)
---@see core.settings    Settings for float_border, lazyvim_extras
---@see https://github.com/folke/which-key.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/which-key.lua — Pro-grade keymap discovery               ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────┐     ║
--- ║  │  which-key.nvim                                                 │     ║
--- ║  │                                                                 │     ║
--- ║  │  • Modern preset with custom layout and centered title          │     ║
--- ║  │  • Theme-adaptive highlights with ColorScheme autocmd           │     ║
--- ║  │  • 9-color icon tint palette (azure..yellow)                    │     ║
--- ║  │  • 60+ custom icon rules for auto-matching descriptions         │     ║
--- ║  │  • Inline spec decorations for root shortcuts                   │     ║
--- ║  │  • Pretty key labels and description cleanup patterns           │     ║
--- ║  │  • Plugin integration (marks, registers, spelling, presets)     │     ║
--- ║  │  • Extensible spec via lazy.nvim opts_extend                    │     ║
--- ║  │  • LazyVim <leader>l conflict resolution                        │     ║
--- ║  └─────────────────────────────────────────────────────────────────┘     ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • VeryLazy event loading                                                ║
--- ║  • Highlight colors derived from active colorscheme (theme-adaptive)     ║
--- ║  • Icon rules ordered most-specific → least-specific                     ║
--- ║  • Groups registered from core.keymaps (single source of truth)          ║
--- ║  • Centralized hl_color() helper (shared pattern with neo-tree)          ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════
local settings = require("core.settings")
---@type Icons
local icons = require("core.icons")
---@type fun(name: string): integer
local augroup = require("core.utils").augroup

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS: Color Extraction
-- ═══════════════════════════════════════════════════════════════════════════

--- Extract a color component from an existing highlight group.
--- Resolves through highlight links to find the actual color.
---@param name string Highlight group name (e.g. `"Function"`)
---@param component "fg"|"bg" Which color component to extract
---@return string|nil hex Hex color string (e.g. `"#7aa2f7"`) or `nil`
---@private
local function hl_color(name, component)
	local ok, group = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok and group[component] then return string.format("#%06x", group[component]) end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HIGHLIGHTS
-- ═══════════════════════════════════════════════════════════════════════════

--- Apply custom highlight groups for a polished which-key appearance.
---
--- Derives base colors from the active colorscheme via `hl_color()`,
--- with curated fallback values (Tokyo Night / Catppuccin palette).
--- Called on setup and on every `ColorScheme` event.
---
--- Groups: WhichKey, WhichKeyGroup, WhichKeyDesc, WhichKeySeparator,
--- WhichKeyValue, WhichKeyNormal, WhichKeyFloat, WhichKeyBorder,
--- WhichKeyTitle, WhichKeyIcon{Azure..Yellow} (9 tint colors).
---@private
local function apply_highlights()
	local hl = vim.api.nvim_set_hl
	local fg = function(name)
		return hl_color(name, "fg")
	end
	local bg = function(name)
		return hl_color(name, "bg")
	end

	local float_bg = bg("NormalFloat")

	-- ── Base which-key highlights ────────────────────────────────────
	hl(0, "WhichKey", { fg = fg("Function") or "#7dcfff", bold = true })
	hl(0, "WhichKeyGroup", { fg = fg("Keyword") or "#bb9af7", bold = true })
	hl(0, "WhichKeyDesc", { fg = fg("Identifier") or "#c0caf5" })
	hl(0, "WhichKeySeparator", { fg = fg("Comment") or "#565f89" })
	hl(0, "WhichKeyValue", { fg = fg("Comment") or "#565f89", italic = true })

	-- Popup background
	hl(0, "WhichKeyNormal", { link = "NormalFloat" })
	hl(0, "WhichKeyFloat", { link = "NormalFloat" })

	-- Border and title
	hl(0, "WhichKeyBorder", { fg = fg("FloatBorder") or "#29a4bd", bg = float_bg })
	hl(0, "WhichKeyTitle", { fg = fg("FloatTitle") or "#7dcfff", bg = float_bg, bold = true })

	-- ── Icon tint palette ────────────────────────────────────────────
	-- Which-key v3 maps `color` in icon specs to WhichKeyIcon<Color>.
	-- Each tries to inherit from a semantically appropriate hl group.
	-- stylua: ignore
	hl(0, "WhichKeyIconAzure",  { fg = fg("DiagnosticInfo")  or "#73daca" })
	hl(0, "WhichKeyIconBlue", { fg = fg("Function") or "#7aa2f7" })
	hl(0, "WhichKeyIconCyan", { fg = fg("Special") or "#7dcfff" })
	hl(0, "WhichKeyIconGreen", { fg = fg("String") or "#9ece6a" })
	hl(0, "WhichKeyIconGrey", { fg = fg("NonText") or "#545c7e" })
	hl(0, "WhichKeyIconOrange", { fg = fg("Constant") or "#ff9e64" })
	hl(0, "WhichKeyIconPurple", { fg = fg("Statement") or "#9d7cd8" })
	hl(0, "WhichKeyIconRed", { fg = fg("DiagnosticError") or "#f7768e" })
	hl(0, "WhichKeyIconYellow", { fg = fg("DiagnosticWarn") or "#e0af68" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ICON RULES
--
-- Custom icon-matching rules for which-key v3.
-- Each rule matches against the mapping's `desc` field (lowercased).
-- First match wins — ordered most-specific to least-specific.
-- These supplement which-key's built-in rules with patterns specific
-- to plugins and actions used in this configuration.
-- ═══════════════════════════════════════════════════════════════════════════

---@type table[] -- which-key IconRule type
local icon_rules = {
	-- ── Plugin-specific (not in which-key defaults) ──────────────────
	-- stylua: ignore start
	{ pattern = "lazygit",     icon = icons.git.Logo,         color = "orange" },
	{ pattern = "trouble",     icon = icons.diagnostics.Warn, color = "red" },
	{ pattern = "noice",       icon = icons.ui.Fire,          color = "orange" },
	{ pattern = "flash",       icon = "󰉁",                    color = "yellow" },
	{ pattern = "aerial",      icon = "󰀘",                    color = "purple" },
	{ pattern = "mason",       icon = icons.misc.Mason,       color = "orange" },
	{ pattern = "treesitter",  icon = icons.misc.Treesitter,  color = "green" },
	{ pattern = "diffview",    icon = icons.git.Diff,         color = "orange" },
	{ pattern = "frecency",    icon = icons.ui.History,       color = "cyan" },
	{ pattern = "zoxide",      icon = icons.ui.Folder,        color = "cyan" },
	{ pattern = "copilot",     icon = icons.kinds.Copilot,    color = "green" },
	{ pattern = "supermaven",  icon = icons.kinds.Supermaven,  color = "purple" },
	{ pattern = "edgy",        icon = icons.ui.Window,        color = "blue" },
	{ pattern = "bufferline",  icon = icons.ui.Tab,           color = "blue" },

	-- ── Git actions ──────────────────────────────────────────────────
	{ pattern = "hunk",    icon = icons.git.Diff,     color = "orange" },
	{ pattern = "blame",   icon = icons.git.Git,      color = "orange" },
	{ pattern = "stash",   icon = "󰆓",                color = "orange" },
	{ pattern = "branch",  icon = icons.git.Branch,   color = "orange" },
	{ pattern = "commit",  icon = icons.git.Commit,   color = "orange" },
	{ pattern = "status",  icon = icons.git.Modified,  color = "orange" },

	-- ── LSP / code intelligence ──────────────────────────────────────
	{ pattern = "inlay",          icon = icons.ui.Lightbulb,     color = "purple" },
	{ pattern = "code.?lens",     icon = "󰄄",                    color = "blue" },
	{ pattern = "symbol",         icon = "󰀘",                    color = "purple" },
	{ pattern = "reference",      icon = icons.kinds.Reference,  color = "blue" },
	{ pattern = "implementation", icon = icons.kinds.Interface,  color = "blue" },
	{ pattern = "snippet",        icon = icons.kinds.Snippet,    color = "green" },

	-- ── UI / editor actions ──────────────────────────────────────────
	{ pattern = "explorer",    icon = icons.tree.Explorer, color = "green" },
	{ pattern = "surround",    icon = icons.type.Array,    color = "yellow" },
	{ pattern = "colorscheme", icon = icons.ui.Art,        color = "purple" },
	{ pattern = "profiler",    icon = icons.ui.History,    color = "red" },
	{ pattern = "zen",         icon = icons.misc.Yoga,     color = "cyan" },
	{ pattern = "dim",         icon = icons.ui.Lightbulb,  color = "purple" },
	{ pattern = "zoom",        icon = icons.ui.Search,     color = "cyan" },
	{ pattern = "undo",        icon = "󰕌",                 color = "orange" },

	-- ── Text / editing actions ───────────────────────────────────────
	{ pattern = "clipboard", icon = icons.ui.Copy,     color = "yellow" },
	{ pattern = "yank",      icon = icons.ui.Copy,     color = "yellow" },
	{ pattern = "paste",     icon = "󰅌",               color = "yellow" },
	{ pattern = "indent",    icon = "󰉶",               color = "grey" },
	{ pattern = "wrap",      icon = icons.ui.WordWrap, color = "grey" },
	{ pattern = "fold",      icon = "󰘖",               color = "grey" },
	{ pattern = "spell",     icon = "󰓆",               color = "green" },
	{ pattern = "comment",   icon = icons.ui.Comment,  color = "grey" },

	-- ── Navigation ───────────────────────────────────────────────────
	{ pattern = "alternate", icon = "󰒮",               color = "blue" },
	{ pattern = "jump",      icon = "󰆽",               color = "cyan" },
	{ pattern = "scroll",    icon = "󰠳",               color = "cyan" },
	{ pattern = "mark",      icon = icons.ui.BookMark, color = "yellow" },
	{ pattern = "pin",       icon = "󰐃",               color = "yellow" },

	-- ── Lists ────────────────────────────────────────────────────────
	{ pattern = "quickfix",  icon = "󰁨",               color = "red" },
	{ pattern = "location",  icon = "󰍉",               color = "red" },
	{ pattern = "todo",      icon = "󰗡",               color = "yellow" },

	-- ── Notifications / messages ─────────────────────────────────────
	{ pattern = "dismiss",      icon = icons.ui.BoldClose, color = "grey" },
	{ pattern = "notification", icon = icons.misc.Bell,    color = "yellow" },
	{ pattern = "message",      icon = "󰍡",               color = "yellow" },
	{ pattern = "history",      icon = icons.ui.History,   color = "orange" },

	-- ── Discovery ────────────────────────────────────────────────────
	{ pattern = "register",    icon = "󰀫",               color = "yellow" },
	{ pattern = "highlight",   icon = "󰸱",               color = "yellow" },
	{ pattern = "autocommand", icon = "󰁨",               color = "orange" },
	{ pattern = "command",     icon = "",                color = "orange" },
	{ pattern = "filetype",    icon = icons.ui.File,     color = "purple" },
	{ pattern = "keymap",      icon = icons.ui.Keyboard, color = "purple" },
	{ pattern = "resume",      icon = icons.ui.Refresh,  color = "green" },
	{ pattern = "picker",      icon = icons.ui.Telescope, color = "green" },
	{ pattern = "project",     icon = icons.ui.Project,  color = "cyan" },
	-- stylua: ignore end
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"folke/which-key.nvim",
	event = "VeryLazy",

	-- Allow other plugin specs to extend `spec` without overwriting it.
	opts_extend = { "spec" },

	---@type wk.Opts
	opts = {
		-- ── Preset ───────────────────────────────────────────────────
		preset = "modern",

		-- ── Delay ────────────────────────────────────────────────────
		-- Shorter for <leader> (most common), longer for other prefixes.
		---@type number|fun(ctx: {keys:string, mode:string, plugin?:string}):number
		delay = function(ctx)
			return ctx.keys == "<leader>" and 200 or 400
		end,

		-- ── Inline Spec ──────────────────────────────────────────────
		-- Key-specific overrides that don't match icon_rules well.
		---@type wk.Spec
		spec = {
			-- Hidden noise mappings
			{ "<C-/>", hidden = true },
			{ "<C-_>", hidden = true },
			{ "<C-\\>", hidden = true },

			-- Root leader shortcuts (explicit icons)
			-- stylua: ignore start
			{ "<leader>/", icon = { icon = icons.documents.FileFind, color = "green" } },
			{ "<leader>,", icon = { icon = icons.ui.Tab,             color = "blue" } },
			{ "<leader>:", icon = { icon = "",                       color = "orange" } },
			{ "<leader>`", icon = { icon = "󰒮",                      color = "blue" } },
			{ "<leader>-", icon = { icon = "",                       color = "blue" } },
			{ "<leader>|", icon = { icon = "",                       color = "blue" } },
			{ "<leader>K", icon = { icon = icons.ui.List,            color = "cyan" } },
			-- stylua: ignore end

			-- Clipboard (multi-mode)
			{
				mode = { "n", "v" },
				{ "<leader>y", icon = { icon = icons.ui.Copy, color = "yellow" } },
				{ "<leader>p", icon = { icon = "󰅌", color = "yellow" } },
				{ "<leader>P", icon = { icon = "󰅌", color = "yellow" } },
			},
			{ "<leader>Y", icon = { icon = icons.ui.Copy, color = "yellow" } },

			-- Session / quit
			{ "<leader>qq", icon = { icon = icons.ui.SignOut, color = "red" } },

			-- Flash (multi-mode)
			{
				mode = { "n", "x", "o" },
				{ "s", icon = { icon = "󰉁", color = "yellow" } },
				{ "S", icon = { icon = "󰉁", color = "purple" } },
			},
		},

		-- ── Defer ────────────────────────────────────────────────────
		-- Suppress in visual-line and visual-block modes.
		---@type fun(ctx: wk.Context):boolean
		defer = function(ctx)
			return ctx.mode == "V" or ctx.mode == "<C-V>"
		end,

		notify = true,

		-- ── Plugins ──────────────────────────────────────────────────
		plugins = {
			marks = true,
			registers = true,
			spelling = { enabled = true, suggestions = 20 },
			presets = {
				operators = true,
				motions = true,
				text_objects = true,
				windows = true,
				nav = true,
				z = true,
				g = true,
			},
		},

		-- ── Window ───────────────────────────────────────────────────
		---@type wk.Win
		win = {
			no_overlap = true,
			border = settings:get("ui.float_border", "rounded"),
			padding = { 1, 2, 1, 2 },
			title = true,
			title_pos = "center",
			zindex = 1000,
			wo = { winblend = 8 },
		},

		-- ── Layout ───────────────────────────────────────────────────
		layout = {
			width = { min = 20 },
			spacing = 3,
		},

		-- ── Popup navigation ─────────────────────────────────────────
		keys = {
			scroll_down = "<C-d>",
			scroll_up = "<C-u>",
		},

		-- ── Sort ─────────────────────────────────────────────────────
		---@type (string|wk.Sorter)[]
		sort = { "local", "order", "group", "alphanum", "mod" },

		-- ── Expand ───────────────────────────────────────────────────
		-- Show group contents inline if ≤ 1 item.
		expand = 1,

		-- ── Replace ──────────────────────────────────────────────────
		-- Transform key labels and descriptions for cleaner display.
		replace = {
			key = {
				function(key)
					local pretty = {
						["<C-/>"] = "^/",
						["<C-\\>"] = "^\\",
					}
					return pretty[key] or require("which-key.view").format(key)
				end,
			},
			desc = {
				{ "<Plug>%(?(.*)%)?", "%1" },
				{ "^%+", "" },
				{ "<[cC]md>", "" },
				{ "<[cC][rR]>", "" },
				{ "^%s+", "" },
				{ "%s+$", "" },
			},
		},

		-- ── Icons ────────────────────────────────────────────────────
		icons = {
			breadcrumb = icons.ui.ChevronRight,
			separator = icons.ui.ArrowRight,
			group = "",
			ellipsis = icons.ui.Ellipsis,
			mappings = true,
			rules = icon_rules,
			colors = true,
			---@type table<string, string>
			keys = {},
		},

		-- ── Display ──────────────────────────────────────────────────
		show_help = true,
		show_keys = true,

		-- ── Disable ──────────────────────────────────────────────────
		disable = {
			ft = {},
			bt = { "terminal" },
		},

		debug = false,
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- CONFIG
	-- ═══════════════════════════════════════════════════════════════════
	---@param _ table Plugin spec (unused)
	---@param opts wk.Opts Resolved options
	config = function(_, opts)
		local wk = require("which-key")
		wk.setup(opts)

		-- ── Apply custom highlights ──────────────────────────────────
		apply_highlights()

		vim.api.nvim_create_autocmd("ColorScheme", {
			group = augroup("WhichKeyHL"),
			desc = "Re-apply which-key custom highlights after colorscheme change",
			callback = apply_highlights,
		})

		-- ── Fix: remove LazyVim's <leader>l → :Lazy conflict ─────────
		-- LazyVim binds <leader>l to :Lazy, which conflicts with our
		-- <leader>l "Lang" group. We relocate it to <leader>up.
		if settings:get("lazyvim_extras.enabled", false) then
			pcall(vim.keymap.del, "n", "<leader>l")
			vim.keymap.set("n", "<leader>up", "<cmd>Lazy<cr>", {
				desc = icons.misc.Lazy .. " Plugins (Lazy)",
				silent = true,
			})
		end

		-- ── Register centralized groups & keymaps from core ──────────
		local keys = require("core.keymaps")
		wk.add(keys.groups)
		keys.setup()
	end,
}
