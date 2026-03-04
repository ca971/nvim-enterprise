---@file lua/plugins/editor/mini-ai.lua
---@description mini.ai — extended text objects with treesitter awareness and custom patterns
---@module "plugins.editor.mini-ai"
---@author ca971
---@license MIT
---@version 2.0.0
---@since 2026-01
---
---@see plugins.editor.mini-surround  Surround operations (complementary)
---@see plugins.editor.mini-pairs     Auto-pairing (sibling mini config)
---@see https://github.com/echasnovski/mini.ai
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/mini-ai.lua — Enhanced a/i text objects                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────┐     ║
--- ║  │  mini.ai                                                        │     ║
--- ║  │                                                                 │     ║
--- ║  │  • Treesitter-based text objects for functions, classes, blocks │     ║
--- ║  │  • HTML tag text objects (inner/around)                         │     ║
--- ║  │  • Digit sequences, camelCase word parts                        │     ║
--- ║  │  • Function call text objects (with/without dot notation)       │     ║
--- ║  │  • next/last variants for all text objects (in/an, il/al)       │     ║
--- ║  │  • Edge navigation with g[ / g]                                 │     ║
--- ║  │  • 500-line search scope for large files                        │     ║
--- ║  └─────────────────────────────────────────────────────────────────┘     ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • VeryLazy event loading (zero startup cost)                            ║
--- ║  • No explicit keymaps — mini.ai creates a/i objects automatically       ║
--- ║  • Treesitter specs generated once at setup time                         ║
--- ║                                                                          ║
--- ║  Text objects (all work with a = around, i = inside):                    ║
--- ║    o   Code block (if/for/while)     f   Function              (o,x)     ║
--- ║    c   Class                         t   HTML tag              (o,x)     ║
--- ║    d   Digit sequence                e   CamelCase word part   (o,x)     ║
--- ║    u   Function call (dot.notation)  U   Function call (no dot)(o,x)     ║
--- ║                                                                          ║
--- ║  Variants:                                                               ║
--- ║    an/in + obj    next text object                             (o,x)     ║
--- ║    al/il + obj    last (previous) text object                  (o,x)     ║
--- ║    g[ / g]        move to left/right edge of text object       (n)       ║
--- ║                                                                          ║
--- ║  Usage examples:                                                         ║
--- ║    vaf   select around function      dif   delete inside function        ║
--- ║    vic   select inside class         dao   delete around code block      ║
--- ║    vid   select inside digits        ciu   change inside function call   ║
--- ║    vat   select around HTML tag      die   delete inside camelCase part  ║
--- ║    vanf  select around next function vilc  select inside last class      ║
--- ║                                                                          ║
--- ║  ⚠ CONFLICT AUDIT:                                                       ║
--- ║    ai/ii (o,x) — mini.indentscope uses `ii` (double i), mini.ai          ║
--- ║                  uses `i` + char (e.g. `if`, `ic`). No conflict.         ║
--- ║    at/it (o,x) — overrides built-in tag text object (intentional,        ║
--- ║                  better treesitter-aware version)                        ║
--- ║    g[ / g] (n) — no conflict (not mapped elsewhere)                      ║
--- ║    All other text objects (o,f,c,d,e,u,U) — no conflicts                 ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════
local settings = require("core.settings")
if not settings:is_plugin_enabled("mini_ai") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"echasnovski/mini.ai",
	event = "VeryLazy",

	dependencies = {
		{ "nvim-treesitter/nvim-treesitter-textobjects" },
	},

	opts = function()
		local ai = require("mini.ai")

		return {
			n_lines = 500,

			-- ── Custom text objects ──────────────────────────────────
			-- stylua: ignore
			custom_textobjects = {
				-- Code blocks: if/for/while/loops/conditionals
				o = ai.gen_spec.treesitter({
					a = { "@block.outer", "@conditional.outer", "@loop.outer" },
					i = { "@block.inner", "@conditional.inner", "@loop.inner" },
				}),

				-- Functions
				f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),

				-- Classes
				c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),

				-- HTML/JSX tags: <div class="x">...</div>
				t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().googletag()-()$" },

				-- Digit sequences: 42, 3.14, 0xFF
				d = { "%f[%d]%d+" },

				-- CamelCase / snake_case word parts: "get" in "getUser"
				e = {
					{ "%u[%l%d]+%f[^%l%d]", "%f[%S][%l%d]+%f[^%l%d]", "%f[%P][%l%d]+%f[^%l%d]", "^[%l%d]+%f[^%l%d]" },
					"^().*()$",
				},

				-- Function calls including dot notation: vim.fn.expand()
				u = ai.gen_spec.function_call(),

				-- Function calls without dot notation: expand()
				U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
			},

			-- ── Mappings ─────────────────────────────────────────────
			mappings = {
				around = "a",
				inside = "i",
				around_next = "an",
				inside_next = "in",
				around_last = "al",
				inside_last = "il",
				goto_left = "g[",
				goto_right = "g]",
			},

			-- ── Behavior ─────────────────────────────────────────────
			search_method = "cover_or_next",
			silent = false,
		}
	end,
}
