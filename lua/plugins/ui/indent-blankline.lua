---@file lua/plugins/ui/indent-blankline.lua
---@description IndentBlankline — Rainbow/muted/mono indentation guides with treesitter scope
---@module "plugins.ui.indent-blankline"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Plugin enable/disable guard
---@see core.icons                 Icon provider (toggle notifications, keymap descriptions)
---@see config.colorscheme_manager ColorScheme autocmd triggers highlight refresh
---@see plugins.treesitter         Treesitter scope detection for indent guides
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ui/indent-blankline.lua — Indentation guide system              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  indent-blankline.nvim v3 (lukas-reineke/indent-blankline.nvim)  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Indent Styles (4 modes, cycleable at runtime):                  │    ║
--- ║  │  ├─ rainbow  🌈  8 semantic colors blended at 75% toward bg      │    ║
--- ║  │  ├─ muted    🌫️   Comment color blended at 85% (subtle)          │    ║
--- ║  │  ├─ mono     ▏   Comment color blended at 70% (visible)          │    ║
--- ║  │  └─ off      🚫  Guide chars invisible (fg = bg)                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Visual Layer:                                                   │    ║
--- ║  │  ├─ 8 IndentRainbow{1..8} highlight groups                       │    ║
--- ║  │  ├─ Colors derived from active colorscheme (with fallbacks)      │    ║
--- ║  │  ├─ Scope highlight (IblScope) from Function fg                  │    ║
--- ║  │  ├─ Scope start/end underlines                                   │    ║
--- ║  │  ├─ Whitespace highlight (IblWhitespace) from NonText fg         │    ║
--- ║  │  └─ All colors refreshed on every ColorScheme event              │    ║
--- ║  │                                                                  │    ║
--- ║  │  Scope Detection:                                                │    ║
--- ║  │  ├─ Powered by treesitter (native IBL v3 integration)            │    ║
--- ║  │  ├─ show_start = true, show_end = false                          │    ║
--- ║  │  ├─ show_exact_scope = true                                      │    ║
--- ║  │  └─ Excludes top-level wrappers (source_file, program, etc.)     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Color Blending:                                                 │    ║
--- ║  │  ├─ blend(color, bg, factor) mixes toward background             │    ║
--- ║  │  ├─ 0.0 = original color, 1.0 = fully background                 │    ║
--- ║  │  └─ Ensures guides never overpower actual code                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Rainbow Color Sources (mapped to 8 semantic groups):            │    ║
--- ║  │  ├─ DiagnosticError  → IndentRainbow1                            │    ║
--- ║  │  ├─ DiagnosticWarn   → IndentRainbow2                            │    ║
--- ║  │  ├─ String           → IndentRainbow3                            │    ║
--- ║  │  ├─ DiagnosticInfo   → IndentRainbow4                            │    ║
--- ║  │  ├─ Special          → IndentRainbow5                            │    ║
--- ║  │  ├─ Constant         → IndentRainbow6                            │    ║
--- ║  │  ├─ Statement        → IndentRainbow7                            │    ║
--- ║  │  └─ Type             → IndentRainbow8                            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Commands:                                                       │    ║
--- ║  │  ├─ :IndentToggle    Toggle guides on/off (per-buffer)           │    ║
--- ║  │  ├─ :IndentStyle [s] Set or cycle style (rainbow→muted→mono→off) │    ║
--- ║  │  ├─ :IndentScope     Toggle scope highlighting (per-buffer)      │    ║
--- ║  │  └─ :IndentInfo      Show current style, filetype, shiftwidth    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps:                                                        │    ║
--- ║  │  ├─ <leader>uG  Toggle indent guides                             │    ║
--- ║  │  ├─ <leader>uO  Cycle indent style                               │    ║
--- ║  │  └─ <leader>uo  Toggle scope highlighting                        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Autocmds:                                                       │    ║
--- ║  │  ├─ ColorScheme  → re-apply all highlights + deferred refresh    │    ║
--- ║  │  └─ BufReadPost  → auto-disable on files > 10,000 lines          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Exclusions:                                                     │    ║
--- ║  │  ├─ buftypes: terminal, nofile, quickfix, prompt                 │    ║
--- ║  │  └─ filetypes: 40+ (dashboards, explorers, plugin UIs,           │    ║
--- ║  │     help, telescope, git, DAP, markup, etc.)                     │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Defensive Design:                                                       ║
--- ║  • pcall on nvim_get_hl — safe color extraction with fallbacks           ║
--- ║  • pcall on ibl.debounced_refresh — API may vary between versions        ║
--- ║  • pcall on ibl.setup_buffer — safe disable in large files               ║
--- ║  • Tokyo Night palette as ultimate color fallback                        ║
--- ║  • blend() handles any valid hex input (with or without #)               ║
--- ║  • Large file guard at 10,000 lines prevents performance degradation     ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_plugin_enabled("indent_blankline") then return {} end

local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE & CONSTANTS
--
-- Runtime state for the current indent style and static configuration.
-- The style is global (not per-buffer) — changing it affects all buffers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Available indent style modes.
--- • `rainbow`: 8 semantic colors blended toward background
--- • `muted`:   single muted color (very subtle)
--- • `mono`:    single visible color
--- • `off`:     guide characters invisible (fg matches bg)
---@alias IndentStyle "rainbow"|"muted"|"mono"|"off"

--- Current active indent style (global, affects all buffers).
---@type IndentStyle
local current_style = "rainbow"

--- Ordered list of styles for cycling via :IndentStyle.
---@type IndentStyle[]
local STYLES = { "rainbow", "muted", "mono", "off" }

--- Emoji icons displayed in notifications when cycling styles.
---@type table<IndentStyle, string>
local STYLE_ICONS = {
	rainbow = "🌈",
	muted = "🌫️",
	mono = "▏",
	off = "🚫",
}

--- Highlight group names for the 8 rainbow indent levels.
--- These groups are defined dynamically by apply_highlights()
--- and referenced by IBL's indent.highlight option.
---@type string[]
local RAINBOW_GROUPS = {
	"IndentRainbow1",
	"IndentRainbow2",
	"IndentRainbow3",
	"IndentRainbow4",
	"IndentRainbow5",
	"IndentRainbow6",
	"IndentRainbow7",
	"IndentRainbow8",
}

--- Maximum buffer line count before auto-disabling guides.
--- Files larger than this threshold have IBL disabled on BufReadPost
--- to prevent performance degradation.
---@type integer
local MAX_LINES = 10000

-- ═══════════════════════════════════════════════════════════════════════════
-- COLOR UTILITIES
--
-- Low-level color extraction and blending functions.
-- Used by apply_highlights() to derive guide colors from the active
-- colorscheme with fallbacks to Tokyo Night palette.
-- ═══════════════════════════════════════════════════════════════════════════

--- Extract a color attribute from an existing highlight group.
---
--- Uses pcall for safety — returns nil if the group doesn't exist
--- or doesn't have the requested attribute.
---@param name string Highlight group name (e.g. `"Normal"`, `"Comment"`)
---@param attr "fg"|"bg" Attribute to extract
---@return string|nil hex Hex color string (e.g. `"#1a1b26"`) or nil
---@private
local function hl_attr(name, attr)
	local ok, group = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok and group[attr] then return string.format("#%06x", group[attr]) end
end

--- Blend a hex color toward a background color by a given factor.
---
--- Linear interpolation in RGB space:
--- • `factor = 0.0` → original color (no blending)
--- • `factor = 0.5` → midpoint between color and background
--- • `factor = 1.0` → fully background color (invisible)
---
--- Used to create subtle indent guides that don't overpower code.
---@param hex string Source color in hex (e.g. `"#f7768e"`)
---@param bg_hex string Background color in hex (e.g. `"#1a1b26"`)
---@param factor number Blend factor (0.0 = original, 1.0 = bg)
---@return string blended Resulting hex color
---@private
local function blend(hex, bg_hex, factor)
	--- Parse a hex color string into RGB components.
	---@param h string Hex string with or without `#` prefix
	---@return integer r Red (0-255)
	---@return integer g Green (0-255)
	---@return integer b Blue (0-255)
	local function parse(h)
		h = h:gsub("#", "")
		return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
	end
	local r1, g1, b1 = parse(hex)
	local r2, g2, b2 = parse(bg_hex)
	return string.format(
		"#%02x%02x%02x",
		math.floor(r1 + (r2 - r1) * factor),
		math.floor(g1 + (g2 - g1) * factor),
		math.floor(b1 + (b2 - b1) * factor)
	)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HIGHLIGHT MANAGEMENT
--
-- Defines and applies all custom highlight groups used by IBL.
-- Colors are derived from the active colorscheme's semantic groups
-- (DiagnosticError, String, Function, etc.) and blended toward the
-- Normal background to create subtle, non-intrusive guides.
--
-- Groups managed (13 total):
--   Indent:     IndentRainbow{1..8}     (8 groups)
--   Scope:      IblScope, IblScopeStart, IblScopeEnd (3 groups)
--   Whitespace: IblWhitespace           (1 group)
--   (+ IblScopeStart/End cleared in "off" mode = 13 total)
-- ═══════════════════════════════════════════════════════════════════════════

--- Source highlight groups for rainbow color derivation.
--- Each entry maps a semantic highlight group to a fallback color
--- (Tokyo Night palette). The fg color is extracted and blended
--- at 75% toward background for the rainbow style.
---@type {group: string, fallback: string}[]
local RAINBOW_SOURCES = {
	{ group = "DiagnosticError", fallback = "#f7768e" },
	{ group = "DiagnosticWarn", fallback = "#e0af68" },
	{ group = "String", fallback = "#9ece6a" },
	{ group = "DiagnosticInfo", fallback = "#7aa2f7" },
	{ group = "Special", fallback = "#7dcfff" },
	{ group = "Constant", fallback = "#ff9e64" },
	{ group = "Statement", fallback = "#bb9af7" },
	{ group = "Type", fallback = "#2ac3de" },
}

--- Apply all indent guide highlight groups based on current_style.
---
--- Handles 4 style modes:
--- • `rainbow`: 8 colors from semantic groups, blended at 75%
--- • `muted`:   all 8 groups set to Comment fg blended at 85%
--- • `mono`:    all 8 groups set to Comment fg blended at 70%
--- • `off`:     all groups set to bg color (invisible)
---
--- Also applies scope highlights (IblScope, IblScopeStart, IblScopeEnd)
--- and whitespace highlight (IblWhitespace).
---
--- Called during initial setup and on every ColorScheme event.
---@return nil
---@private
local function apply_highlights()
	local set_hl = vim.api.nvim_set_hl
	local bg = hl_attr("Normal", "bg") or "#1a1b26"

	-- ── Indent line colors per style ──────────────────────────────────
	if current_style == "rainbow" then
		for i, src in ipairs(RAINBOW_SOURCES) do
			local color = blend(hl_attr(src.group, "fg") or src.fallback, bg, 0.75)
			set_hl(0, RAINBOW_GROUPS[i], { fg = color, nocombine = true })
		end
	elseif current_style == "muted" then
		local muted = blend(hl_attr("Comment", "fg") or "#565f89", bg, 0.85)
		for _, name in ipairs(RAINBOW_GROUPS) do
			set_hl(0, name, { fg = muted, nocombine = true })
		end
	elseif current_style == "mono" then
		local mono = blend(hl_attr("Comment", "fg") or "#565f89", bg, 0.70)
		for _, name in ipairs(RAINBOW_GROUPS) do
			set_hl(0, name, { fg = mono, nocombine = true })
		end
	else -- "off"
		for _, name in ipairs(RAINBOW_GROUPS) do
			set_hl(0, name, { fg = bg, nocombine = true })
		end
	end

	-- ── Scope highlight ───────────────────────────────────────────────
	local scope_fg = hl_attr("Function", "fg") or "#7aa2f7"
	local scope_dim = blend(scope_fg, bg, 0.3)

	if current_style ~= "off" then
		set_hl(0, "IblScope", { fg = scope_dim, nocombine = true })
		set_hl(0, "IblScopeStart", { sp = scope_dim, underline = true, nocombine = true })
		set_hl(0, "IblScopeEnd", { sp = scope_dim, underline = true, nocombine = true })
	else
		set_hl(0, "IblScope", { fg = bg, nocombine = true })
		set_hl(0, "IblScopeStart", { nocombine = true })
		set_hl(0, "IblScopeEnd", { nocombine = true })
	end

	-- ── Whitespace ────────────────────────────────────────────────────
	local ws = blend(hl_attr("NonText", "fg") or "#3b4261", bg, 0.80)
	set_hl(0, "IblWhitespace", { fg = ws, nocombine = true })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- IBL REFRESH HELPER
--
-- Triggers a debounced refresh of indent-blankline rendering.
-- Wrapped in pcall because the internal debounced_refresh API
-- may vary between IBL versions.
-- ═══════════════════════════════════════════════════════════════════════════

--- Safely refresh IBL rendering for a given buffer.
---@param bufnr? integer Buffer number (default: current buffer)
---@return nil
---@private
local function refresh_ibl(bufnr)
	local ok, ibl = pcall(require, "ibl")
	if ok then pcall(ibl.debounced_refresh, bufnr or 0) end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- NOTIFICATION HELPER
-- ═══════════════════════════════════════════════════════════════════════════

--- Send a notification with the indent-blankline title.
---@param msg string Notification message
---@param level? integer vim.log.levels value (default: INFO)
---@return nil
---@private
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "indent-blankline" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- USER COMMANDS
--
-- Registers 4 commands for runtime control:
--   :IndentToggle  — Toggle guides on/off (per-buffer)
--   :IndentStyle   — Set or cycle style (with tab-completion)
--   :IndentScope   — Toggle scope highlighting (per-buffer)
--   :IndentInfo    — Show current configuration summary
-- ═══════════════════════════════════════════════════════════════════════════

--- Register all indent-blankline user commands.
---
--- Called once during config() after IBL is initialized.
--- Commands operate on the current buffer (setup_buffer)
--- except :IndentStyle which is global.
---@return nil
---@private
local function setup_commands()
	local command = vim.api.nvim_create_user_command

	-- ── :IndentToggle — Toggle guides on/off (per-buffer) ─────────────
	command("IndentToggle", function()
		local ok, ibl = pcall(require, "ibl")
		if not ok then return end

		local enabled = require("ibl.config").get_config(0).enabled
		ibl.setup_buffer(0, { enabled = not enabled })
		notify(string.format("%s Indent guides %s", icons.ui.LineMiddle, enabled and "disabled" or "enabled"))
	end, { desc = "NvimEnterprise: Toggle indent guides" })

	-- ── :IndentStyle [style] — Set or cycle style ─────────────────────
	command("IndentStyle", function(opts)
		if opts.args ~= "" then
			if not vim.tbl_contains(STYLES, opts.args) then
				notify(
					string.format("Unknown style '%s'. Available: %s", opts.args, table.concat(STYLES, ", ")),
					vim.log.levels.WARN
				)
				return
			end
			current_style = opts.args
		else
			local idx = (vim.fn.index(STYLES, current_style) + 1) % #STYLES
			current_style = STYLES[idx + 1]
		end

		apply_highlights()
		refresh_ibl()
		notify(string.format("%s Indent style: %s", STYLE_ICONS[current_style] or "?", current_style))
	end, {
		nargs = "?",
		desc = "NvimEnterprise: Set or cycle indent style",
		complete = function()
			return STYLES
		end,
	})

	-- ── :IndentScope — Toggle scope highlighting (per-buffer) ─────────
	command("IndentScope", function()
		local ok, ibl = pcall(require, "ibl")
		if not ok then return end

		local scope_on = require("ibl.config").get_config(0).scope.enabled
		ibl.setup_buffer(0, { scope = { enabled = not scope_on } })
		notify(string.format("%s Scope %s", icons.ui.LineMiddle, scope_on and "disabled" or "enabled"))
	end, { desc = "NvimEnterprise: Toggle scope highlighting" })

	-- ── :IndentInfo — Show current configuration summary ──────────────
	command("IndentInfo", function()
		local config = require("ibl.config").get_config(0)
		local lines = {
			string.format("Style: %s | Enabled: %s | Scope: %s", current_style, config.enabled, config.scope.enabled),
			string.format(
				"Filetype: %s | Shiftwidth: %d | %s",
				vim.bo.filetype ~= "" and vim.bo.filetype or "(none)",
				vim.bo.shiftwidth,
				vim.bo.expandtab and "spaces" or "tabs"
			),
		}
		notify(table.concat(lines, "\n"))
	end, { desc = "NvimEnterprise: Show indent info" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- EXCLUSIONS
--
-- Filetypes where indent guides are distracting or meaningless.
-- Buftypes (terminal, nofile, quickfix, prompt) are excluded via
-- IBL's built-in buftype filter — only filetypes need explicit listing.
--
-- Categories: dashboards, file explorers, plugin UIs, diagnostics,
-- help/docs, telescope, notifications, git, misc tools, DAP, markup.
-- ═══════════════════════════════════════════════════════════════════════════

---@type string[] Filetypes excluded from indent guide rendering
local excluded_filetypes = {
	-- ── Dashboards ────────────────────────────────────────────────────
	"alpha",
	"dashboard",
	"starter",
	"snacks_dashboard",
	-- ── File explorers ────────────────────────────────────────────────
	"neo-tree",
	"NvimTree",
	"oil",
	-- ── Plugin UIs ────────────────────────────────────────────────────
	"lazy",
	"mason",
	-- ── Diagnostics ───────────────────────────────────────────────────
	"Trouble",
	"trouble",
	-- ── Help / docs ───────────────────────────────────────────────────
	"help",
	"man",
	"checkhealth",
	-- ── Telescope ─────────────────────────────────────────────────────
	"TelescopePrompt",
	"TelescopeResults",
	"TelescopePreview",
	-- ── Notifications ─────────────────────────────────────────────────
	"notify",
	"noice",
	"Noice",
	-- ── Git ───────────────────────────────────────────────────────────
	"fugitive",
	"gitcommit",
	"gitrebase",
	"NeogitStatus",
	-- ── Misc tools ────────────────────────────────────────────────────
	"aerial",
	"Outline",
	"undotree",
	"spectre_panel",
	"DressingInput",
	"DressingSelect",
	-- ── DAP ───────────────────────────────────────────────────────────
	"dapui_scopes",
	"dapui_breakpoints",
	"dapui_stacks",
	"dapui_watches",
	"dapui_console",
	"dap-repl",
	-- ── Markup (guides are distracting in prose) ──────────────────────
	"markdown",
	"norg",
	"org",
	"orgagenda",
	-- ── Empty filetype ────────────────────────────────────────────────
	"",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
--
-- Loaded on BufReadPost/BufNewFile — needs treesitter for scope detection.
-- Highlight groups are applied before IBL setup so the groups exist
-- when IBL references them in its configuration.
-- ═══════════════════════════════════════════════════════════════════════════

return {
	"lukas-reineke/indent-blankline.nvim",
	event = { "BufReadPost", "BufNewFile" },
	main = "ibl",
	dependencies = { "nvim-treesitter/nvim-treesitter" },

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYMAPS
	-- ═══════════════════════════════════════════════════════════════════

	keys = {
		{ "<leader>uG", "<cmd>IndentToggle<CR>", desc = icons.ui.LineMiddle .. " Toggle indent guides" },
		{ "<leader>uO", "<cmd>IndentStyle<CR>", desc = icons.ui.LineMiddle .. " Cycle indent style" },
		{ "<leader>uo", "<cmd>IndentScope<CR>", desc = icons.ui.LineMiddle .. " Toggle scope" },
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	-- ═══════════════════════════════════════════════════════════════════

	opts = {
		-- ── Indent guides ─────────────────────────────────────────────
		indent = {
			char = "│",
			tab_char = "│",
			highlight = RAINBOW_GROUPS,
			smart_indent_cap = true,
			priority = 1,
		},

		-- ── Whitespace rendering ──────────────────────────────────────
		whitespace = {
			highlight = { "IblWhitespace" },
			remove_blankline_trail = true,
		},

		-- ── Treesitter scope ──────────────────────────────────────────
		scope = {
			enabled = true,
			show_start = true,
			show_end = false,
			show_exact_scope = true,
			highlight = { "IblScope" },
			-- Treesitter handles scope detection natively in IBL v3.
			-- Only exclude top-level wrappers that aren't real scopes:
			exclude = {
				node_type = {
					["*"] = { "source_file", "program", "module", "chunk", "document" },
				},
			},
			priority = 1024,
		},

		-- ── Exclusions ────────────────────────────────────────────────
		exclude = {
			filetypes = excluded_filetypes,
			buftypes = { "terminal", "nofile", "quickfix", "prompt" },
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- CONFIG
	--
	-- Post-setup pipeline (5 steps):
	-- 1. Apply highlight groups (must exist before IBL references them)
	-- 2. Initialize IBL with merged options
	-- 3. Register user commands and keymaps
	-- 4. ColorScheme autocmd for highlight refresh
	-- 5. BufReadPost autocmd for large file auto-disable
	-- ═══════════════════════════════════════════════════════════════════

	config = function(_, opts)
		-- ── Step 1: Apply highlights (groups must exist first) ────────
		apply_highlights()

		-- ── Step 2: Initialize IBL ───────────────────────────────────
		require("ibl").setup(opts)

		-- ── Step 3: Register user commands ────────────────────────────
		setup_commands()

		local augroup = vim.api.nvim_create_augroup("NvimEnterprise_IndentBlankline", { clear = true })

		-- ── Step 4: Re-apply highlights on colorscheme change ─────────
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = augroup,
			callback = function()
				apply_highlights()
				vim.defer_fn(function()
					refresh_ibl()
				end, 50)
			end,
			desc = "NvimEnterprise: Refresh IBL highlights on colorscheme change",
		})

		-- ── Step 5: Auto-disable in large files ───────────────────────
		vim.api.nvim_create_autocmd("BufReadPost", {
			group = augroup,
			callback = function(ev)
				local lines = vim.api.nvim_buf_line_count(ev.buf)
				if lines > MAX_LINES then
					pcall(function()
						require("ibl").setup_buffer(ev.buf, { enabled = false })
					end)
				end
			end,
			desc = "NvimEnterprise: Disable IBL in files > " .. MAX_LINES .. " lines",
		})
	end,
}
