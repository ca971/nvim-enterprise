---@file lua/plugins/editor/todo-comments.lua
---@description todo-comments.nvim — highlight and search TODO/FIX/HACK/NOTE in code
---@module "plugins.editor.todo-comments"
---@author ca971
---@license MIT
---@version 2.0.0
---@since 2026-01
---
---@see plugins.editor.trouble    Trouble integration for TODO list
---@see plugins.editor.telescope  Telescope picker for fuzzy TODO search
---@see https://github.com/folke/todo-comments.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/todo-comments.lua — TODO comment management              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────┐     ║
--- ║  │  todo-comments.nvim                                             │     ║
--- ║  │                                                                 │     ║
--- ║  │  • Highlight TODO, FIX, HACK, WARN, PERF, NOTE, TEST            │     ║
--- ║  │  • Sign column indicators per keyword category                  │     ║
--- ║  │  • Jump to next/prev with ]t / [t                               │     ║
--- ║  │  • Trouble integration for project-wide TODO list               │     ║
--- ║  │  • Telescope picker for fuzzy searching TODOs                   │     ║
--- ║  │  • Custom colors per keyword (theme-adaptive via hl groups)     │     ║
--- ║  │  • Alt keywords (FIXME → FIX, WARNING → WARN, etc.)             │     ║
--- ║  └─────────────────────────────────────────────────────────────────┘     ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • LazyFile event loading (BufReadPost + BufNewFile)                     ║
--- ║  • Direct function references (no pcall wrappers)                        ║
--- ║  • Icons from core/icons.lua (single source of truth, no fallbacks)      ║
--- ║  • ripgrep for fast project-wide search                                  ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    ]t              Next TODO comment                          (n)        ║
--- ║    [t              Previous TODO comment                      (n)        ║
--- ║    <leader>xt      TODO list (Trouble)                        (n)        ║ 
--- ║    <leader>xT      TODO/FIX/FIXME only (Trouble)              (n)        ║
--- ║    <leader>st      Search TODOs (Telescope)                   (n)        ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════
local settings = require("core.settings")
if not settings:is_plugin_enabled("todo_comments") then return {} end

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
	"folke/todo-comments.nvim",

	event = { "BufReadPost", "BufNewFile" },
	cmd = { "TodoTrouble", "TodoTelescope", "TodoQuickFix", "TodoLocList" },

	dependencies = { "nvim-lua/plenary.nvim" },

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYMAPS
	--
	-- ⚠ CONFLICT AUDIT (verified against global keymap registry):
	--   ]t              → "Next TODO"           ✅ no conflict
	--   [t              → "Previous TODO"       ✅ no conflict
	--   <leader>xt      → "TODOs (Trouble)"     ✅ no conflict
	--   <leader>xT      → "TODO/FIX/FIXME"      ✅ no conflict
	--   <leader>st      → "Search TODOs"         ✅ no conflict
	-- ═══════════════════════════════════════════════════════════════════

	-- stylua: ignore
	keys = {
		{ "]t",          function() require("todo-comments").jump_next() end, desc = icons.ui.Check  .. " Next TODO" },
		{ "[t",          function() require("todo-comments").jump_prev() end, desc = icons.ui.Check  .. " Prev TODO" },
		{ "<leader>xt",  "<Cmd>Trouble todo toggle<CR>",                      desc = icons.ui.Check  .. " TODOs (Trouble)" },
		{ "<leader>xT",  "<Cmd>Trouble todo toggle filter = {tag = {TODO,FIX,FIXME}}<CR>", desc = icons.ui.Bug .. " TODO/FIX/FIXME (Trouble)" },
		{ "<leader>st",  "<Cmd>TodoTelescope<CR>",                            desc = icons.ui.Search .. " Search TODOs" },
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	-- ═══════════════════════════════════════════════════════════════════
	opts = {
		-- ── Signs ────────────────────────────────────────────────────
		signs         = true,
		sign_priority = 8,

		-- ── Keywords ─────────────────────────────────────────────────
		-- stylua: ignore
		keywords = {
			FIX  = { icon = icons.ui.Bug,    color = "error",   alt = { "FIXME", "BUG", "FIXIT", "ISSUE" } },
			TODO = { icon = icons.ui.Check,  color = "info" },
			HACK = { icon = icons.ui.Fire,   color = "warning" },
			WARN = { icon = icons.diagnostics.Warn, color = "warning", alt = { "WARNING", "XXX" } },
			PERF = { icon = icons.ui.Rocket, color = "default", alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" } },
			NOTE = { icon = icons.ui.Note,   color = "hint",    alt = { "INFO" } },
			TEST = { icon = icons.ui.Target, color = "test",    alt = { "TESTING", "PASSED", "FAILED" } },
		},

		-- ── Colors ───────────────────────────────────────────────────
		-- Each entry is a priority list: highlight group → fallback hex.
		-- The plugin uses the first available match.
		colors = {
			error   = { "DiagnosticError", "ErrorMsg",   "#f38ba8" },
			warning = { "DiagnosticWarn",  "WarningMsg", "#f9e2af" },
			info    = { "DiagnosticInfo",  "#89b4fa" },
			hint    = { "DiagnosticHint",  "#94e2d5" },
			default = { "Identifier",     "#cba6f7" },
			test    = { "Identifier",     "#a6e3a1" },
		},

		-- ── Highlight ────────────────────────────────────────────────
		highlight = {
			multiline         = true,
			multiline_pattern = "^.",
			multiline_context = 10,
			before            = "",     ---@type "fg"|"bg"|""
			keyword           = "wide", ---@type "fg"|"bg"|"wide"|""
			after             = "fg",   ---@type "fg"|"bg"|""
			pattern           = [[.*<(KEYWORDS)\s*:]],
			comments_only     = true,
			max_line_len      = 400,
			exclude           = {},
		},

		-- ── Search ───────────────────────────────────────────────────
		search = {
			command = "rg",
			args = {
				"--color=never",
				"--no-heading",
				"--with-filename",
				"--line-number",
				"--column",
			},
			pattern = [[\b(KEYWORDS):]],
		},

		-- ── Behavior ─────────────────────────────────────────────────
		merge_keywords = true,

		-- ── GUI style ────────────────────────────────────────────────
		gui_style = {
			fg = "NONE",
			bg = "BOLD",
		},
	},
}
