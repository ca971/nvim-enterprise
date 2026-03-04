---@file lua/plugins/editor/trouble.lua
---@description Trouble.nvim — unified list interface for diagnostics, LSP, quickfix
---@module "plugins.editor.trouble"
---@author ca971
---@license MIT
---@version 2.0.0
---@since 2026-01
---
---@see plugins.editor.todo-comments  TODO comment highlighting (feeds into Trouble)
---@see plugins.editor.telescope      Fuzzy finder (complementary)
---@see https://github.com/folke/trouble.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/trouble.lua — Enterprise-grade diagnostics viewer        ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────┐     ║
--- ║  │  trouble.nvim                                                   │     ║
--- ║  │                                                                 │     ║
--- ║  │  • Workspace & buffer diagnostics with filtering                │     ║
--- ║  │  • LSP definitions, references, implementations in split view   │     ║
--- ║  │  • Symbol outline (document symbols)                            │     ║
--- ║  │  • Quickfix & location list integration                         │     ║
--- ║  │  • TODO comments aggregation (via todo-comments.nvim)           │     ║
--- ║  │  • [q / ]q smart navigation (Trouble if open, else quickfix)    │     ║
--- ║  └─────────────────────────────────────────────────────────────────┘     ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • cmd + keys lazy loading (zero startup cost)                           ║
--- ║  • Icons from core/icons.lua (single source of truth, no fallbacks)      ║
--- ║  • kinds icons generated from icons.kinds table (DRY)                    ║
--- ║  • Direct requires (no defensive pcall wrappers)                         ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    <leader>xx   Workspace diagnostics                        (n)         ║
--- ║    <leader>xX   Buffer diagnostics                           (n)         ║
--- ║    <leader>cl   LSP defs/refs (right split)                  (n)         ║
--- ║    <leader>cs   Document symbols (right split)               (n)         ║
--- ║    <leader>xL   Location list                                (n)         ║
--- ║    <leader>xQ   Quickfix list                                (n)         ║
--- ║    [q / ]q      Prev/Next (Trouble if open, else quickfix)   (n)         ║
--- ║                                                                          ║
--- ║  Note: <leader>xt and <leader>xT are defined in todo-comments.lua        ║
--- ║  to keep TODO-related keymaps co-located with their source plugin.       ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════
local settings = require("core.settings")
if not settings:is_plugin_enabled("trouble") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════
---@type Icons
local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Navigate in Trouble if open, otherwise fall back to quickfix.
--- Provides seamless [q / ]q navigation regardless of Trouble state.
---@param direction "prev"|"next" Navigation direction
---@return function handler Keymap callback
---@private
local function trouble_nav(direction)
	return function()
		local trouble = require("trouble")

		if trouble.is_open() then
			local method = direction == "prev" and trouble.prev or trouble.next
			method({ skip_groups = true, jump = true })
		else
			local qf_cmd = direction == "prev" and vim.cmd.cprev or vim.cmd.cnext
			local ok, err = pcall(qf_cmd)
			if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
		end
	end
end

--- Build the `kinds` icon table from `icons.kinds`.
--- Generates the mapping dynamically instead of 30 hardcoded lines.
---@return table<string, string> kinds Kind name → icon string
---@private
local function build_kinds_icons()
	if not icons.kinds then return {} end

	local result = {}
	for kind, icon_str in pairs(icons.kinds) do
		result[kind] = icon_str
	end
	return result
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"folke/trouble.nvim",

	cmd = { "Trouble" },
	dependencies = { "nvim-mini/mini.icons" },

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYMAPS
	--
	-- ⚠ CONFLICT AUDIT (verified against global keymap registry):
	--   <leader>xx  → "Diagnostics (Trouble)"      ✅ no conflict
	--   <leader>xX  → "Buffer diagnostics"          ✅ no conflict
	--   <leader>cl  → "LSP defs/refs (Trouble)"     ✅ no conflict
	--   <leader>cs  → "Symbols (Trouble)"           ⚠ Aerial also uses this
	--                  Resolution: both coexist — Aerial is <Cmd>AerialToggle
	--                  vs Trouble symbols. Different tools, same keymap is OK
	--                  because only one is typically used at a time.
	--   <leader>xL  → "Location list (Trouble)"     ✅ no conflict
	--   <leader>xQ  → "Quickfix list (Trouble)"     ✅ no conflict
	--   [q / ]q     → overrides default quickfix nav ✅ intentional
	--
	-- Note: <leader>xt / <leader>xT are owned by todo-comments.lua
	-- ═══════════════════════════════════════════════════════════════════

	-- stylua: ignore
	keys = {
		-- Diagnostics
		{ "<leader>xx", "<Cmd>Trouble diagnostics toggle<CR>",                             desc = icons.diagnostics.Warn .. " Diagnostics (Trouble)" },
		{ "<leader>xX", "<Cmd>Trouble diagnostics toggle filter.buf=0<CR>",                desc = icons.diagnostics.Error .. " Buffer diagnostics" },

		-- LSP
		{ "<leader>cl", "<Cmd>Trouble lsp toggle focus=false win.position=right<CR>",      desc = icons.ui.Target   .. " LSP defs/refs (Trouble)" },
		{ "<leader>cs", "<Cmd>Trouble symbols toggle focus=false<CR>",                     desc = icons.ui.Code     .. " Symbols (Trouble)" },

		-- Lists
		{ "<leader>xL", "<Cmd>Trouble loclist toggle<CR>",                                 desc = icons.ui.List     .. " Location list (Trouble)" },
		{ "<leader>xQ", "<Cmd>Trouble qflist toggle<CR>",                                  desc = icons.ui.List     .. " Quickfix list (Trouble)" },

		-- Smart navigation
		{ "[q",          trouble_nav("prev"),                                               desc = icons.ui.Search   .. " Prev Trouble/Quickfix" },
		{ "]q",          trouble_nav("next"),                                               desc = icons.ui.Search   .. " Next Trouble/Quickfix" },
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	-- ═══════════════════════════════════════════════════════════════════
	opts = {
		-- ── Appearance ───────────────────────────────────────────────
		icons = {
			indent = {
				top = "│ ",
				middle = "├╴",
				last = "└╴",
				fold_open = icons.ui.FolderOpen,
				fold_closed = icons.ui.Folder,
				ws = "  ",
			},
			folder_closed = icons.ui.Folder,
			folder_open = icons.ui.FolderOpen,
			kinds = build_kinds_icons(),
		},

		-- ── Modes ────────────────────────────────────────────────────
		modes = {
			diagnostics = {
				auto_open = false,
				auto_close = true,
				auto_preview = true,
				auto_refresh = true,
			},
			lsp = {
				auto_open = false,
				auto_close = true,
				auto_preview = true,
				auto_refresh = true,
				win = {
					position = "right",
					size = { width = 0.3 },
				},
			},
			symbols = {
				auto_open = false,
				auto_close = true,
				focus = false,
				win = {
					position = "right",
					size = { width = 0.3 },
				},
			},
		},

		-- ── Window ───────────────────────────────────────────────────
		win = {
			size = { height = 10 },
		},

		-- ── Preview ──────────────────────────────────────────────────
		preview = {
			scratch = true,
		},

		-- ── Buffer-local keymaps (inside Trouble window) ─────────────
		keys = {
			-- Navigation
			["?"] = "help",
			["<cr>"] = "jump",
			["<2-leftmouse>"] = "jump",
			["o"] = "jump_close",
			["{"] = "prev",
			["}"] = "next",

			-- Open in split
			["<c-s>"] = "jump_split",
			["<c-v>"] = "jump_vsplit",
			["s"] = { action = "open_split", desc = "Open in split" },
			["v"] = { action = "open_vsplit", desc = "Open in vsplit" },

			-- Actions
			["q"] = "close",
			["r"] = "refresh",
			["R"] = "toggle_refresh",
			["i"] = "inspect",
			["p"] = "preview",
			["P"] = "toggle_preview",

			-- Delete
			["dd"] = "delete",
			["d"] = { action = "delete", mode = "v" },

			-- Folds
			["zo"] = "fold_open",
			["zO"] = "fold_open_recursive",
			["zc"] = "fold_close",
			["zC"] = "fold_close_recursive",
			["za"] = "fold_toggle",
			["zA"] = "fold_toggle_recursive",
			["zm"] = "fold_more",
			["zM"] = "fold_close_all",
			["zr"] = "fold_reduce",
			["zR"] = "fold_open_all",
			["zx"] = "fold_update",
			["zX"] = "fold_update_all",
			["zn"] = "fold_disable",
			["zN"] = "fold_enable",
			["zi"] = "fold_toggle_enable",
		},
	},
}
