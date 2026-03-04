---@file lua/plugins/ui/dressing.lua
---@description Dressing — Pro-grade vim.ui.input() and vim.ui.select() overrides
---@module "plugins.ui.dressing"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Plugin enable/disable guard, float_border preference
---@see core.icons               Icon provider (prompt prefix)
---@see config.colorscheme_manager ColorScheme autocmd triggers highlight refresh
---@see plugins.editor.telescope   Primary backend for vim.ui.select()
---@see plugins.editor.fzf-lua    Secondary backend for vim.ui.select()
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ui/dressing.lua — vim.ui override layer                         ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  dressing.nvim (stevearc/dressing.nvim)                          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Overrides:                                                      │    ║
--- ║  │  ├─ vim.ui.input()  → Floating input window                      │    ║
--- ║  │  │  ├─ Icon-prefixed prompt (✎ Input)                            │    ║
--- ║  │  │  ├─ Cursor-relative positioning                               │    ║
--- ║  │  │  ├─ Insert-mode start, Esc/q to cancel                        │    ║
--- ║  │  │  ├─ History navigation (C-p / C-n)                            │    ║
--- ║  │  │  ├─ Prompt trimming (trailing `:` and whitespace)             │    ║
--- ║  │  │  └─ Width override for rename prompts (pattern match)         │    ║
--- ║  │  │                                                               │    ║
--- ║  │  └─ vim.ui.select() → Floating select window                     │    ║
--- ║  │     ├─ Backend cascade: telescope → fzf_lua → nui → builtin      │    ║
--- ║  │     ├─ Per-kind overrides:                                       │    ║
--- ║  │     │  ├─ codeaction → cursor dropdown (telescope or builtin)    │    ║
--- ║  │     │  └─ confirm    → compact cursor popup (builtin only)       │    ║
--- ║  │     ├─ Builtin: numbered items, treesitter highlighting          │    ║
--- ║  │     └─ Telescope: cursor theme, minimal chrome                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Visual Layer:                                                   │    ║
--- ║  │  ├─ Theme-adaptive highlights (11 custom groups)                 │    ║
--- ║  │  │  ├─ DressingInput{Normal,Border,Title,Prompt,Text}            │    ║
--- ║  │  │  └─ DressingSelect{Normal,Border,Title,CursorLine,Match,Idx}  │    ║
--- ║  │  ├─ Colors derived from active colorscheme (with fallbacks)      │    ║
--- ║  │  ├─ Glass effect via winblend=8                                  │    ║
--- ║  │  └─ Refreshed on every ColorScheme event                         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Lazy-loading Strategy:                                          │    ║
--- ║  │  ├─ Plugin is lazy = true (never loaded at startup)              │    ║
--- ║  │  ├─ init() patches vim.ui.select and vim.ui.input                │    ║
--- ║  │  ├─ First call triggers require("lazy").load(dressing.nvim)      │    ║
--- ║  │  └─ Subsequent calls go directly to dressing                     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Autocmds:                                                       │    ║
--- ║  │  └─ ColorScheme → re-apply all 11 highlight groups               │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Defensive Design:                                                       ║
--- ║  • pcall on telescope.themes — graceful nil if not installed             ║
--- ║  • pcall on nvim_get_hl — safe color extraction with fallbacks           ║
--- ║  • Tokyo Night palette as ultimate fallback colors                       ║
--- ║  • Prompt trimming handles inconsistent caller formatting                ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_plugin_enabled("dressing") then return {} end

local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- COLOR EXTRACTION HELPERS
--
-- These extract fg/bg hex colors from existing highlight groups.
-- Used by apply_highlights() to derive dressing colors from the
-- active colorscheme, ensuring visual consistency across themes.
-- Falls back to nil when the group doesn't exist or has no color.
-- ═══════════════════════════════════════════════════════════════════════════

--- Extract the foreground color from an existing highlight group.
---@param name string Highlight group name (e.g. `"NormalFloat"`, `"Special"`)
---@return string|nil hex Hex color string (e.g. `"#c0caf5"`) or nil if unavailable
---@private
local function fg_of(name)
	local ok, group = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok and group.fg then return string.format("#%06x", group.fg) end
	return nil
end

--- Extract the background color from an existing highlight group.
---@param name string Highlight group name (e.g. `"NormalFloat"`, `"Visual"`)
---@return string|nil hex Hex color string (e.g. `"#1a1b26"`) or nil if unavailable
---@private
local function bg_of(name)
	local ok, group = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok and group.bg then return string.format("#%06x", group.bg) end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HIGHLIGHT MANAGEMENT
--
-- 11 custom highlight groups are defined for dressing windows.
-- Colors are derived from the active colorscheme using fg_of/bg_of
-- with Tokyo Night palette as ultimate fallback.
--
-- Groups are split into two categories:
--   Input:  DressingInput{Normal,Border,Title,Prompt,Text}
--   Select: DressingSelect{Normal,Border,Title,CursorLine,Match,Idx}
--
-- Called during initial setup and on every ColorScheme event.
-- ═══════════════════════════════════════════════════════════════════════════

--- Apply theme-adaptive highlights for dressing.nvim floating windows.
---
--- Derives colors from the active colorscheme's highlight groups
--- (NormalFloat, FloatBorder, Special, Visual, etc.) with curated
--- Tokyo Night fallbacks for missing groups.
---
--- Covers 11 highlight groups across input and select windows.
---@return nil
---@private
local function apply_highlights()
	local hl = vim.api.nvim_set_hl

	-- ── Derive colors from active colorscheme ─────────────────────────
	local float_bg = bg_of("NormalFloat") or bg_of("Normal") or "#1a1b26"
	local float_fg = fg_of("NormalFloat") or fg_of("Normal") or "#c0caf5"
	local border_fg = fg_of("FloatBorder") or "#29a4bd"
	local title_fg = fg_of("FloatTitle") or fg_of("Function") or "#7dcfff"
	local prompt_fg = fg_of("Special") or "#7dcfff"
	local selection_bg = bg_of("Visual") or "#364a82"
	local match_fg = fg_of("Special") or "#7dcfff"

	-- ── Input window (5 groups) ───────────────────────────────────────
	hl(0, "DressingInputNormal", { fg = float_fg, bg = float_bg })
	hl(0, "DressingInputBorder", { fg = border_fg, bg = float_bg })
	hl(0, "DressingInputTitle", { fg = title_fg, bg = float_bg, bold = true })
	hl(0, "DressingInputPrompt", { fg = prompt_fg, bold = true })
	hl(0, "DressingInputText", { fg = float_fg, bg = float_bg })

	-- ── Select window (6 groups) ──────────────────────────────────────
	hl(0, "DressingSelectNormal", { fg = float_fg, bg = float_bg })
	hl(0, "DressingSelectBorder", { fg = border_fg, bg = float_bg })
	hl(0, "DressingSelectTitle", { fg = title_fg, bg = float_bg, bold = true })
	hl(0, "DressingSelectCursorLine", { bg = selection_bg, bold = true })
	hl(0, "DressingSelectMatch", { fg = match_fg, bold = true })
	hl(0, "DressingSelectIdx", { fg = fg_of("Number") or "#ff9e64", bold = true })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
--
-- Lazy-loading strategy: dressing.nvim is never loaded at startup.
-- init() patches vim.ui.select and vim.ui.input with trampolines
-- that trigger lazy-loading on first invocation, then forward the
-- call to the real dressing implementation.
-- ═══════════════════════════════════════════════════════════════════════════

return {
	"stevearc/dressing.nvim",
	lazy = true,

	-- ── Lazy-load trampolines ─────────────────────────────────────────
	-- Patch vim.ui.select and vim.ui.input before any plugin calls them.
	-- On first invocation, load dressing.nvim and replay the call.
	init = function()
		---@diagnostic disable-next-line: duplicate-set-field
		vim.ui.select = function(...)
			require("lazy").load({ plugins = { "dressing.nvim" } })
			return vim.ui.select(...)
		end
		---@diagnostic disable-next-line: duplicate-set-field
		vim.ui.input = function(...)
			require("lazy").load({ plugins = { "dressing.nvim" } })
			return vim.ui.input(...)
		end
	end,

	opts = {
		-- ═══════════════════════════════════════════════════════════════
		-- vim.ui.input() OVERRIDE
		--
		-- Replaces the default input prompt with a floating window.
		-- Positioned relative to cursor for contextual feel.
		-- Starts in insert mode with history navigation support.
		-- ═══════════════════════════════════════════════════════════════
		input = {
			enabled = true,
			default_prompt = icons.ui.Pencil .. " Input",
			trim_prompt = true,
			title_pos = "center",
			start_in_insert = true,
			border = settings:get("ui.float_border", "rounded"),
			relative = "cursor",

			-- ── Size constraints ──────────────────────────────────────
			prefer_width = 50,
			min_width = { 30, 0.25 },
			max_width = { 100, 0.8 },

			-- ── Window highlights ─────────────────────────────────────
			winhighlight = table.concat({
				"Normal:DressingInputNormal",
				"FloatBorder:DressingInputBorder",
				"FloatTitle:DressingInputTitle",
			}, ","),

			-- ── Window-local options ──────────────────────────────────
			win_options = {
				winblend = 8,
				cursorline = false,
				number = false,
				relativenumber = false,
				signcolumn = "no",
				wrap = true,
			},

			-- ── Keymaps ───────────────────────────────────────────────
			mappings = {
				n = {
					["<Esc>"] = "Close",
					["q"] = "Close",
					["<CR>"] = "Confirm",
				},
				i = {
					["<C-c>"] = "Close",
					["<CR>"] = "Confirm",
					["<C-p>"] = "HistoryPrev",
					["<C-n>"] = "HistoryNext",
				},
			},

			-- ── Per-prompt overrides ──────────────────────────────────
			--- Widen the input window for rename prompts.
			---@param conf table Dressing input configuration
			---@return table conf Modified configuration
			override = function(conf)
				if conf.prompt and conf.prompt:match("[Rr]ename") then conf.min_width = { 40, 0.3 } end
				return conf
			end,
		},

		-- ═══════════════════════════════════════════════════════════════
		-- vim.ui.select() OVERRIDE
		--
		-- Replaces the default select menu with a cascading backend
		-- system. Tries telescope first (best UX), then fzf_lua,
		-- then nui, then the built-in floating window.
		--
		-- Per-kind overrides route specific callers to optimal backends:
		-- • codeaction: cursor dropdown for quick LSP actions
		-- • confirm:    compact popup for yes/no decisions
		-- ═══════════════════════════════════════════════════════════════
		select = {
			enabled = true,
			backend = { "telescope", "fzf_lua", "nui", "builtin" },
			trim_prompt = true,

			-- ── Telescope backend ─────────────────────────────────────
			telescope = (function()
				local ok, themes = pcall(require, "telescope.themes")
				if ok then
					return themes.get_cursor({
						layout_config = {
							width = 0.5,
							height = 0.4,
						},
						borderchars = {
							prompt = { "─", "│", " ", "│", "╭", "╮", "│", "│" },
							results = { "─", "│", "─", "│", "├", "┤", "╯", "╰" },
							preview = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
						},
					})
				end
				return nil
			end)(),

			-- ── fzf_lua backend ───────────────────────────────────────
			fzf_lua = {
				winopts = {
					height = 0.4,
					width = 0.5,
				},
			},

			-- ── Nui backend ───────────────────────────────────────────
			nui = {
				position = "50%",
				size = nil,
				relative = "editor",
				border = {
					style = settings:get("ui.float_border", "rounded"),
					text = {
						top_align = "center",
					},
				},
				buf_options = {
					swapfile = false,
					filetype = "DressingSelect",
				},
				win_options = {
					winblend = 8,
				},
				min_width = 40,
				max_width = 100,
				min_height = 5,
				max_height = 20,
			},

			-- ── Builtin backend (fallback) ────────────────────────────
			builtin = {
				show_numbers = true,
				border = settings:get("ui.float_border", "rounded"),
				relative = "editor",
				title_pos = "center",

				winhighlight = table.concat({
					"Normal:DressingSelectNormal",
					"FloatBorder:DressingSelectBorder",
					"FloatTitle:DressingSelectTitle",
					"CursorLine:DressingSelectCursorLine",
				}, ","),

				min_width = { 40, 0.3 },
				max_width = { 120, 0.8 },
				min_height = { 5, 0.2 },
				max_height = { 30, 0.7 },

				win_options = {
					winblend = 8,
					cursorline = true,
					cursorlineopt = "both",
					number = true,
					relativenumber = false,
					signcolumn = "no",
					wrap = false,
				},

				mappings = {
					["<Esc>"] = "Close",
					["q"] = "Close",
					["<C-c>"] = "Close",
					["<CR>"] = "Confirm",
				},
			},

			-- ── Per-kind backend overrides ────────────────────────────
			--- Route specific vim.ui.select() kinds to optimal backends.
			---
			--- • `codeaction`: cursor-relative dropdown (telescope preferred)
			--- • `confirm`:    compact cursor popup (builtin only)
			--- • All others:   standard backend cascade
			---@param opts table Select options with `kind` field
			---@return table|nil config Backend override or nil for default cascade
			get_config = function(opts)
				-- ── Code actions: cursor dropdown ─────────────────────
				if opts.kind == "codeaction" then
					return {
						backend = { "telescope", "builtin" },
						telescope = (function()
							local ok, themes = pcall(require, "telescope.themes")
							if ok then
								return themes.get_cursor({
									layout_config = {
										width = 0.6,
										height = 0.35,
									},
								})
							end
							return nil
						end)(),
						builtin = {
							show_numbers = true,
							relative = "cursor",
							min_width = { 30, 0.2 },
							max_width = { 80, 0.6 },
							min_height = { 3, 0.1 },
							max_height = { 15, 0.4 },
							winhighlight = table.concat({
								"Normal:DressingSelectNormal",
								"FloatBorder:DressingSelectBorder",
								"FloatTitle:DressingSelectTitle",
								"CursorLine:DressingSelectCursorLine",
							}, ","),
							win_options = {
								winblend = 8,
								cursorline = true,
							},
						},
					}
				end

				-- ── Confirmations: compact popup ──────────────────────
				if opts.kind == "confirm" or opts.kind == "confirmx" then
					return {
						backend = { "builtin" },
						builtin = {
							show_numbers = false,
							relative = "cursor",
							min_width = { 20, 0.15 },
							max_width = { 50, 0.4 },
							min_height = { 2, 0 },
							max_height = { 8, 0.3 },
							win_options = {
								winblend = 8,
								cursorline = true,
							},
						},
					}
				end

				-- ── Default: standard cascade ─────────────────────────
				return nil
			end,
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- CONFIG
	--
	-- Post-setup:
	-- 1. Initialize dressing.nvim with merged options
	-- 2. Apply theme-adaptive highlights (11 groups)
	-- 3. Register ColorScheme autocmd for highlight refresh
	-- ═══════════════════════════════════════════════════════════════════

	config = function(_, opts)
		-- ── Step 1: Setup dressing.nvim ───────────────────────────────
		require("dressing").setup(opts)

		-- ── Step 2: Apply theme-adaptive highlights ───────────────────
		apply_highlights()

		-- ── Step 3: Re-apply on colorscheme change ────────────────────
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("NvimEnterprise_DressingHL", { clear = true }),
			desc = "NvimEnterprise: Re-apply dressing.nvim highlights after colorscheme change",
			callback = apply_highlights,
		})
	end,
}
