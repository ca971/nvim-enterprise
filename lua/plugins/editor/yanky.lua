---@file lua/plugins/editor/yanky.lua
---@description Yanky.nvim — improved yank/put with ring history and telescope integration
---@module "plugins.editor.yanky"
---@version 1.0.0
---@since 2026-03
---@see https://github.com/gbprod/yanky.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/yanky.lua — Yank ring & enhanced put                     ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  yanky.nvim                                                      │    ║
--- ║  │  ├─ Ring storage         (sqlite or memory-backed)               │    ║
--- ║  │  ├─ Enhanced put         (p/P with highlight feedback)           │    ║
--- ║  │  ├─ Yank history cycle   ([y / ]y after paste)                   │    ║
--- ║  │  ├─ System clipboard     (synced with ring)                      │    ║
--- ║  │  └─ Telescope picker     (<Space>sy — search yank history)       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps:                                                        │    ║
--- ║  │  ┌────────────┬──────────────────────────────────────────┐       │    ║
--- ║  │  │ Key        │ Action                                   │       │    ║
--- ║  │  ├────────────┼──────────────────────────────────────────┤       │    ║
--- ║  │  │ p          │ Yanky put after (replaces default)       │       │    ║
--- ║  │  │ P          │ Yanky put before (replaces default)      │       │    ║
--- ║  │  │ gp         │ Yanky gput after (cursor after text)     │       │    ║
--- ║  │  │ gP         │ Yanky gput before (cursor after text)    │       │    ║
--- ║  │  │ [y         │ Cycle yank ring backward                 │       │    ║
--- ║  │  │ ]y         │ Cycle yank ring forward                  │       │    ║
--- ║  │  │ <Space>sy  │ Telescope: yank history                  │       │    ║
--- ║  │  └────────────┴──────────────────────────────────────────┘       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Note: Visual mode p retains the "_dP behavior via remap.        │    ║
--- ║  │  The <Space>p / <Space>P clipboard keymaps are preserved         │    ║
--- ║  │  (yanky handles the default p/P only).                           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ Ring stored in shada (persists across sessions)              │    ║
--- ║  │  ├─ Highlight on put (brief flash confirms paste location)       │    ║
--- ║  │  ├─ System clipboard synced to ring (no lost clipboard)          │    ║
--- ║  │  ├─ Telescope integration for browsing full history              │    ║
--- ║  │  └─ Visual mode p still uses "_dP (no overwrite of yanked)       │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
if not settings:is_plugin_enabled("yanky") then return {} end

-- ═══════════════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════

--- Number of entries to keep in the yank ring.
---@type integer
---@private
local RING_SIZE = 100

--- Duration in ms for the highlight flash on put.
---@type integer
---@private
local HIGHLIGHT_DURATION = 200

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════

return {
	"gbprod/yanky.nvim",
	event = { "TextYankPost" },
	dependencies = {
		"nvim-telescope/telescope.nvim",
	},

	-- ── Keymaps ──────────────────────────────────────────────────────
	keys = {
		-- Enhanced put (replaces default p/P in normal + visual)
		{
			"p",
			"<Plug>(YankyPutAfter)",
			mode = { "n", "x" },
			desc = "Put after (yanky)",
		},
		{
			"P",
			"<Plug>(YankyPutBefore)",
			mode = { "n", "x" },
			desc = "Put before (yanky)",
		},

		-- gput variants (cursor positioned after pasted text)
		{
			"gp",
			"<Plug>(YankyGPutAfter)",
			mode = { "n", "x" },
			desc = "GPut after (yanky)",
		},
		{
			"gP",
			"<Plug>(YankyGPutBefore)",
			mode = { "n", "x" },
			desc = "GPut before (yanky)",
		},

		-- Cycle through yank ring (only works after a put)
		{
			"[y",
			"<Plug>(YankyCycleForward)",
			desc = "󰄬 Cycle yank ring forward",
		},
		{
			"]y",
			"<Plug>(YankyCycleBackward)",
			desc = "󰄬 Cycle yank ring backward",
		},

		-- Telescope picker
		{
			"<leader>sy",
			function()
				require("telescope").extensions.yank_history.yank_history()
			end,
			desc = "󰗚 Yank history",
		},
	},

	---@type table
	opts = {
		ring = {
			history_length = RING_SIZE,
			storage = "shada",
			sync_with_numbered_registers = true,
			cancel_event = "update",
			ignore_registers = { "_" },
		},

		system_clipboard = {
			sync_with_ring = true,
			clipboard_register = "+",
		},

		highlight = {
			on_put = true,
			on_yank = true,
			timer = HIGHLIGHT_DURATION,
		},

		preserve_cursor_position = {
			enabled = true,
		},

		textobj = {
			enabled = true,
		},

		picker = {
			telescope = {
				use_default_mappings = true,
				mappings = nil,
			},
		},
	},

	---@param _ table Plugin spec (unused)
	---@param opts YankyConfig Resolved options
	config = function(_, opts)
		require("yanky").setup(opts)

		-- ── Telescope integration ────────────────────────────────────
		local ok, telescope = pcall(require, "telescope")
		if ok then telescope.load_extension("yank_history") end

		-- ── Highlight group ──────────────────────────────────────────
		local api = vim.api
		local function set_highlight()
			local bg = "#364a82"
			local hl = api.nvim_get_hl(0, { name = "Visual", link = false })
			if hl.bg then bg = string.format("#%06x", hl.bg) end
			api.nvim_set_hl(0, "YankyPut", { bg = bg, bold = true })
			api.nvim_set_hl(0, "YankyYanked", { bg = bg, bold = true })
		end

		set_highlight()
		api.nvim_create_autocmd("ColorScheme", {
			group = api.nvim_create_augroup("Yanky_HL", { clear = true }),
			desc = "Re-apply yanky highlights after colorscheme change",
			callback = set_highlight,
		})
	end,
}
