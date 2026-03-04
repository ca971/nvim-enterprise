---@file lua/plugins/editor/mini-surround.lua
---@description mini.surround — fast surround operations (add, delete, replace, find)
---@module "plugins.editor.mini-surround"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.mini-ai     Text objects (complementary)
---@see plugins.editor.mini-pairs  Auto-pairing (sibling mini config)
---@see https://github.com/echasnovski/mini.surround
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/mini-surround.lua — Fast surround operations             ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────┐     ║
--- ║  │  mini.surround                                                  │     ║
--- ║  │                                                                 │     ║
--- ║  │  • Add surroundings (brackets, quotes, tags, custom)            │     ║
--- ║  │  • Delete surroundings                                          │     ║
--- ║  │  • Replace surroundings (change " to ', ( to [, etc.)           │     ║
--- ║  │  • Find next/previous surrounding                               │     ║
--- ║  │  • Highlight surroundings under cursor                          │     ║
--- ║  │  • Works with treesitter for intelligent matching               │     ║
--- ║  │  • All mappings under gs prefix (avoids s conflict with flash)  │     ║
--- ║  └─────────────────────────────────────────────────────────────────┘     ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Lazy-loaded via keys (gs* prefix triggers)                            ║
--- ║  • Static opts (no config function needed)                               ║
--- ║  • Icons from core/icons.lua (single source of truth)                    ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    gsa   Add surrounding                                   (n,v)         ║
--- ║    gsd   Delete surrounding                                (n)           ║
--- ║    gsr   Replace surrounding                               (n)           ║
--- ║    gsf   Find right surrounding                            (n)           ║
--- ║    gsF   Find left surrounding                             (n)           ║
--- ║    gsh   Highlight surrounding                             (n)           ║
--- ║    gsn   Update n_lines scope                              (n)           ║
--- ║                                                                          ║
--- ║  Usage examples:                                                         ║
--- ║    gsa iw "    surround word with "                                      ║
--- ║    gsd "       delete surrounding "                                      ║
--- ║    gsr " '     replace " with '                                          ║
--- ║    gsf )       find next )                                               ║
--- ║                                                                          ║
--- ║  ⚠ CONFLICT AUDIT:                                                       ║
--- ║    gs* prefix — avoids conflict with flash.nvim (s/S)                    ║
--- ║    gsa (n,v)  — no conflict ✅                                           ║
--- ║    gsd (n)    — no conflict ✅                                           ║
--- ║    gsr (n)    — no conflict ✅                                           ║
--- ║    gsf (n)    — no conflict ✅                                           ║
--- ║    gsF (n)    — no conflict ✅                                           ║
--- ║    gsh (n)    — no conflict ✅                                           ║
--- ║    gsn (n)    — no conflict ✅                                           ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════
local settings = require("core.settings")
if not settings:is_plugin_enabled("mini_surround") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════
---@type Icons
local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"echasnovski/mini.surround",

	-- stylua: ignore
	keys = {
		{ "gsa", mode = { "n", "v" }, desc = icons.ui.Code   .. " Add surrounding" },
		{ "gsd",                       desc = icons.ui.Code   .. " Delete surrounding" },
		{ "gsr",                       desc = icons.ui.Pencil .. " Replace surrounding" },
		{ "gsf",                       desc = icons.ui.Search .. " Find right surrounding" },
		{ "gsF",                       desc = icons.ui.Search .. " Find left surrounding" },
		{ "gsh",                       desc = icons.ui.Code   .. " Highlight surrounding" },
		{ "gsn",                       desc = icons.ui.Code   .. " Update n_lines scope" },
	},

	opts = {
		-- ── Mappings ─────────────────────────────────────────────────
		-- gs prefix keeps s/S free for flash.nvim
		mappings = {
			add = "gsa",
			delete = "gsd",
			find = "gsf",
			find_left = "gsF",
			highlight = "gsh",
			replace = "gsr",
			update_n_lines = "gsn",
			suffix_last = "l",
			suffix_next = "n",
		},

		-- ── Behavior ─────────────────────────────────────────────────
		n_lines = 50,
		respect_selection_type = false,
		custom_surroundings = nil,
		highlight_duration = 500,
		search_method = "cover",
	},
}
