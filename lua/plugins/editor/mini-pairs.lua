---@file lua/plugins/editor/mini-pairs.lua
---@description mini.pairs — smart auto-pairing for brackets, quotes, and delimiters
---@module "plugins.editor.mini-pairs"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.mini-align  Alignment module (sibling mini config)
---@see plugins.ui.mini-icons      Icon provider (sibling mini config)
---@see https://github.com/echasnovski/mini.pairs
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/mini-pairs.lua — Smart auto-pairing                      ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────┐     ║
--- ║  │  mini.pairs                                                     │     ║
--- ║  │                                                                 │     ║
--- ║  │  • Auto-close brackets, quotes, backticks                       │     ║
--- ║  │  • Skip closing char when already present                       │     ║
--- ║  │  • Treesitter-aware: skip pairing inside strings                │     ║
--- ║  │  • Skip when next char is alphanumeric (avoids false pairs)     │     ║
--- ║  │  • Works in insert & command mode, disabled in terminal         │     ║
--- ║  │  • Handles unbalanced pairs gracefully                          │     ║
--- ║  │  • Markdown-aware (backtick fences, inline code)                │     ║
--- ║  │  • No keymaps to conflict — purely automatic behavior           │     ║
--- ║  └─────────────────────────────────────────────────────────────────┘     ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • VeryLazy event loading (zero startup cost)                            ║
--- ║  • Static opts (no config function needed)                               ║
--- ║  • No global keymaps — purely insert-mode internal mappings              ║
--- ║                                                                          ║
--- ║  Internal mappings (created by mini.pairs, not by us):                   ║
--- ║    ( ) [ ] { } " ' `    auto-pair open/close                   (i)       ║
--- ║    <BS>                  smart backspace (remove pair)          (i)      ║
--- ║    <CR>                  smart enter (expand pair)              (i)      ║
--- ║                                                                          ║
--- ║  ⚠ CONFLICT AUDIT:                                                       ║
--- ║    <BS> (i) — overrides default backspace (intentional, compatible       ║
--- ║              with blink.cmp / nvim-cmp)                                  ║
--- ║    <CR> (i) — overrides default enter (intentional, compatible           ║
--- ║              with completion plugins)                                    ║
--- ║    No <leader> or normal-mode keymaps — zero conflict risk               ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════
local settings = require("core.settings")
if not settings:is_plugin_enabled("mini_pairs") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"echasnovski/mini.pairs",
	event = "VeryLazy",

	opts = {
		-- ── Modes ────────────────────────────────────────────────────
		modes = {
			insert = true, -- normal typing in insert mode
			command = true, -- command line (: prompt)
			terminal = false, -- disabled (interferes with shell)
		},

		-- ── Skip rules ───────────────────────────────────────────────

		-- Don't auto-pair when next char matches this pattern.
		-- Prevents: typing ( before a word → won't auto-close.
		-- Matches: alphanumeric, %, ', [, ", ., `, $
		skip_next = [=[[%w%%%'%[%"%.%`%$]]=],

		-- Don't auto-pair inside these treesitter node types.
		-- Prevents: typing ' inside a string from creating ''
		skip_ts = { "string" },

		-- Handle unbalanced pairs gracefully.
		-- If there's already an unmatched closer, skip adding another.
		skip_unbalanced = true,

		-- Markdown-specific handling.
		-- Properly handles ``` code fences, `inline code`, etc.
		markdown = true,
	},
}
