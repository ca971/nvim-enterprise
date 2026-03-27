---@file lua/plugins/code/luasnip.lua
---@description LuaSnip — snippet engine with VSCode and Lua snippet loaders
---@module "plugins.code.luasnip"
---@version 1.0.0
---@since 2026-03
---@see plugins.code.cmp Blink.cmp consumes LuaSnip as its snippet engine
---@see https://github.com/L3MON4D3/LuaSnip
---@see https://github.com/rafamadriz/friendly-snippets
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/code/luasnip.lua — Snippet engine                               ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  LuaSnip                                                         │    ║
--- ║  │  ├─ VSCode loader     (friendly-snippets collection)             │    ║
--- ║  │  ├─ VSCode loader     (custom: ~/.config/nvim/snippets/)         │    ║
--- ║  │  ├─ Lua loader        (custom: ~/.config/nvim/lua/snippets/)     │    ║
--- ║  │  │                                                               │    ║
--- ║  │  Consumed by:                                                    │    ║
--- ║  │  └─ blink.cmp         (opts.snippets.expand/active/jump)         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Snippet navigation:                                             │    ║
--- ║  │  ┌────────────┬──────────────────────────────────────────┐       │    ║
--- ║  │  │ Key        │ Action                                   │       │    ║
--- ║  │  ├────────────┼──────────────────────────────────────────┤       │    ║
--- ║  │  │ <Tab>      │ Accept/jump forward (blink handles)      │       │    ║
--- ║  │  │ <S-Tab>    │ Jump backward (blink handles)            │       │    ║
--- ║  │  │ <M-l>      │ Expand or jump forward (LuaSnip direct)  │       │    ║
--- ║  │  │ <M-h>      │ Jump backward (LuaSnip direct)           │       │    ║
--- ║  │  │ <M-n>      │ Cycle choice node                        │       │    ║
--- ║  │  └────────────┴──────────────────────────────────────────┘       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ history=true: can re-enter recently exited snippets          │    ║
--- ║  │  ├─ delete_check_events: cleans up deleted snippet nodes         │    ║
--- ║  │  ├─ region_check_events: auto-exit when cursor leaves snippet    │    ║
--- ║  │  ├─ Keymaps use <M-*> to avoid conflicts with blink/windows      │    ║
--- ║  │  ├─ Keymaps only active when snippet is jumpable (safe)          │    ║
--- ║  │  └─ lazy=true: loaded on demand by blink.cmp dependency          │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
if not settings:is_plugin_enabled("cmp") then return {} end

local uv = vim.uv or vim.loop

-- ═══════════════════════════════════════════════════════════════════════
-- CUSTOM SNIPPET PATHS
--
-- LuaSnip supports two loader formats:
--   1. VSCode format (JSON/JSONC in package.json structure)
--      → ~/.config/nvim/snippets/
--   2. Lua format (programmatic, full LuaSnip API)
--      → ~/.config/nvim/lua/snippets/
--
-- Both paths are checked at startup. Missing directories are silently
-- ignored (no error, no empty load).
-- ═══════════════════════════════════════════════════════════════════════

--- Base path for custom VSCode-format snippets.
---@type string
---@private
local VSCODE_SNIPPETS_PATH = vim.fn.stdpath("config") .. "/snippets"

--- Base path for custom Lua-format snippets.
---@type string
---@private
local LUA_SNIPPETS_PATH = vim.fn.stdpath("config") .. "/lua/snippets"

--- Check if a directory exists on disk.
---
---@param path string Absolute path to check
---@return boolean exists `true` if path is a directory
---@private
local function dir_exists(path)
	local stat = uv.fs_stat(path)
	return stat ~= nil and stat.type == "directory"
end

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════

return {
	"L3MON4D3/LuaSnip",
	version = "v2.*",
	build = "make install_jsregexp",
	lazy = true,

	dependencies = {
		-- ── Community snippet collection ───────────────────────────
		-- 300+ VSCode-format snippets for all major languages.
		-- Loaded lazily: only parsed when a filetype is first opened.
		{
			"rafamadriz/friendly-snippets",
			lazy = true,
		},
	},

	---@type luasnip.Config
	opts = {
		-- Re-enter recently exited snippets with jump keys
		history = true,

		-- Clean up deleted snippet nodes on text change
		delete_check_events = "TextChanged",

		-- Auto-exit snippet when cursor moves outside region
		region_check_events = "CursorMoved",

		-- Update dynamic/function nodes in real-time
		update_events = { "TextChanged", "TextChangedI" },

		-- Visual selection stored in ls.env.TM_SELECTED_TEXT
		store_selection_keys = "<Tab>",

		-- Enable virtual text hints for choice nodes
		ext_opts = {
			[require("luasnip.util.types").choiceNode] = {
				active = {
					virt_text = { { " 󰧑 choices", "DiagnosticHint" } },
				},
			},
		},
	},

	---@param _ table Plugin spec (unused)
	---@param opts table Resolved LuaSnip options
	config = function(_, opts)
		local ls = require("luasnip")
		ls.setup(opts)

		-- ── Loaders ──────────────────────────────────────────────────
		local from_vscode = require("luasnip.loaders.from_vscode")
		local from_lua = require("luasnip.loaders.from_lua")

		-- Community VSCode snippets (friendly-snippets)
		from_vscode.lazy_load()

		-- Custom VSCode snippets (~/.config/nvim/snippets/)
		if dir_exists(VSCODE_SNIPPETS_PATH) then from_vscode.lazy_load({ paths = { VSCODE_SNIPPETS_PATH } }) end

		-- Custom Lua snippets (~/.config/nvim/lua/snippets/)
		if dir_exists(LUA_SNIPPETS_PATH) then from_lua.lazy_load({ paths = { LUA_SNIPPETS_PATH } }) end

		-- ── Navigation keymaps ───────────────────────────────────────
		-- These complement blink.cmp's Tab/S-Tab handling.
		-- <M-*> keys are free across all modes (verified against keymap audit).

		vim.keymap.set({ "i", "s" }, "<M-l>", function()
			if ls.expand_or_locally_jumpable() then ls.expand_or_jump() end
		end, { silent = true, desc = "Snippet: expand or jump forward" })

		vim.keymap.set({ "i", "s" }, "<M-h>", function()
			if ls.locally_jumpable(-1) then ls.jump(-1) end
		end, { silent = true, desc = "Snippet: jump backward" })

		vim.keymap.set({ "i", "s" }, "<M-n>", function()
			if ls.choice_active() then ls.change_choice(1) end
		end, { silent = true, desc = "Snippet: cycle choice node" })
	end,
}
