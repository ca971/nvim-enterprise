---@file lua/plugins/ui/tiny-inline-diagnostic.lua
---@description TinyInlineDiagnostic — Pretty inline diagnostics replacing vim's virtual_text
---@module "plugins.ui.tiny-inline-diagnostic"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Plugin enable/disable guard
---@see core.icons                 Icon provider (diagnostic severity signs, keymap description)
---@see plugins.lsp                LSP client attachment triggers plugin loading
---@see plugins.ui.snacks          <leader>ud toggles vim.diagnostic (complements, not conflicts)
---@see plugins.editor.trouble     <leader>xx opens Trouble panel (separate window, not inline)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ui/tiny-inline-diagnostic.lua — Inline diagnostic renderer      ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  tiny-inline-diagnostic.nvim (rachartier/tiny-inline-diagnostic) │    ║
--- ║  │                                                                  │    ║
--- ║  │  Purpose:                                                        │    ║
--- ║  │  ├─ Fully replaces vim.diagnostic virtual_text renderer          │    ║
--- ║  │  ├─ Renders diagnostics as decorated inline boxes                │    ║
--- ║  │  └─ "modern" preset: rounded box-drawing characters              │    ║
--- ║  │                                                                  │    ║
--- ║  │  Features:                                                       │    ║
--- ║  │  ├─ Multiline support (e.g. Rust borrow checker messages)        │    ║
--- ║  │  ├─ Soft wrap at 40 columns for long messages                    │    ║
--- ║  │  ├─ Overflow wrapping (no horizontal scroll)                     │    ║
--- ║  │  ├─ Show source (LSP server / linter name)                       │    ║
--- ║  │  ├─ Multiple diagnostics under cursor (all shown)                │    ║
--- ║  │  ├─ Severity icons from core.icons                               │    ║
--- ║  │  └─ Link-based highlights (survive :colorscheme switches)        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Loading Strategy:                                               │    ║
--- ║  │  ├─ Event: LspAttach (no load on non-LSP buffers)                │    ║
--- ║  │  ├─ Priority: 1000 (disables virtual_text before other plugins)  │    ║
--- ║  │  └─ init(): sets virtual_text = false immediately                │    ║
--- ║  │                                                                  │    ║
--- ║  │  Performance:                                                    │    ║
--- ║  │  ├─ Throttled at 200ms (batches rapid LSP diagnostic events)     │    ║
--- ║  │  ├─ Disabled in insert mode (no re-renders while typing)         │    ║
--- ║  │  └─ virt_texts priority = 2048 (above other extmarks)            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Complements (does NOT conflict with):                           │    ║
--- ║  │  ├─ <leader>ud  → Toggle vim.diagnostic entirely (Snacks)        │    ║
--- ║  │  ├─ <leader>cd  → Float diagnostic detail (vim.diagnostic)       │    ║
--- ║  │  ├─ <leader>xx  → Trouble panel (separate window)                │    ║
--- ║  │  └─ <leader>ux  → Toggle THIS plugin's inline rendering          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymap:                                                         │    ║
--- ║  │  └─ <leader>ux  Toggle inline diagnostics (n)                    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Highlight Strategy:                                                     ║
--- ║  • All highlights are link-based (hi.error → DiagnosticError, etc.)      ║
--- ║  • No hardcoded colors — adapts to any colorscheme automatically         ║
--- ║  • Background uses CursorLine for subtle contrast                        ║
--- ║  • Arrow/vertical guides use NonText for muted appearance                ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_plugin_enabled("tiny_inline_diagnostic") then return {} end

local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
--
-- Loaded on LspAttach with priority 1000. The init() function disables
-- vim's built-in virtual_text renderer before the plugin sets up its
-- own, preventing duplicate diagnostic display.
-- ═══════════════════════════════════════════════════════════════════════════

return {
	"rachartier/tiny-inline-diagnostic.nvim",
	version = false,
	event = "LspAttach",
	priority = 1000,

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYMAPS
	-- ═══════════════════════════════════════════════════════════════════

	keys = {
		{
			"<leader>ux",
			function()
				require("tiny-inline-diagnostic").toggle()
			end,
			desc = icons.diagnostics.Info .. " Toggle inline diagnostics",
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- INIT — Disable built-in virtual_text BEFORE plugin loads
	--
	-- tiny-inline-diagnostic fully replaces vim's virtual_text renderer.
	-- If both are active simultaneously, diagnostics are displayed twice.
	--
	-- Setting this in init() (not config()) ensures virtual_text is off
	-- even if diagnostics appear between LspAttach and plugin setup.
	-- ═══════════════════════════════════════════════════════════════════

	init = function()
		vim.diagnostic.config({ virtual_text = false })
	end,

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	-- ═══════════════════════════════════════════════════════════════════

	opts = {
		-- ── Visual preset ─────────────────────────────────────────────
		-- "modern" uses rounded box-drawing characters consistent
		-- with icons.borders.Rounded used across the config.
		preset = "modern",

		-- ── Severity signs ────────────────────────────────────────────
		-- Box-drawing characters for the inline diagnostic frame.
		-- Uses the same glyph style as core/icons.lua diagnostics.
		signs = {
			left = "",
			right = "",
			diag = "●",
			arrow = "    ",
			up_arrow = "    ",
			vertical = " │",
			vertical_end = " └",
		},

		-- ── Highlight groups ──────────────────────────────────────────
		-- All link-based: adapts to any colorscheme without hardcoded
		-- colors. Survives :colorscheme switches automatically.
		hi = {
			error = "DiagnosticError",
			warn = "DiagnosticWarn",
			info = "DiagnosticInfo",
			hint = "DiagnosticHint",
			arrow = "NonText",
			background = "CursorLine",
			mixing_color = "None",
		},

		-- ── Behavior ──────────────────────────────────────────────────
		options = {
			-- ── Content ───────────────────────────────────────────────
			-- Show which LSP server / linter produced the diagnostic
			show_source = true,

			-- Show all diagnostics under the cursor, not just the first
			multiple_diag_under_cursor = true,

			-- Show all diagnostics on the current line, not just
			-- the one closest to the cursor
			show_all_diags_on_cursorline = false,

			-- ── Multiline support ─────────────────────────────────────
			-- Enables rendering of multi-line diagnostic messages
			-- (e.g. Rust borrow checker, TypeScript complex errors)
			multilines = {
				enabled = true,
				always_show = false,
			},

			-- ── Text wrapping ─────────────────────────────────────────
			-- Soft wrap long messages at 40 columns
			softwrap = 40,

			-- How to handle messages that overflow the window width
			overflow = {
				mode = "wrap",
			},

			-- Line break configuration
			break_line = {
				enabled = false,
				after = 30,
			},

			-- ── Performance ───────────────────────────────────────────
			-- Throttle rendering (ms) — batches rapid updates from
			-- LSP servers that fire many textDocument/diagnostic
			throttle = 200,

			-- Disable in insert mode — avoids visual noise and
			-- re-renders while typing (performance + UX)
			enable_on_insert = false,

			-- ── Rendering priority ────────────────────────────────────
			-- Virtual text extmark priority — set high so inline
			-- diagnostics render above other extmarks (git signs,
			-- indent guides, etc.)
			virt_texts = {
				priority = 2048,
			},
		},
	},
}
