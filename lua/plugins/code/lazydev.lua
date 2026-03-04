---@file lua/plugins/code/lazydev.lua
---@description lazydev.nvim — Lua development support for Neovim config files
---@module "plugins.code.lazydev"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.code.lspconfig  LSP configuration (lazydev feeds into lua_ls)
---@see types                   Global type definitions for lua_ls
---@see https://github.com/folke/lazydev.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/code/lazydev.lua — Lua development for Neovim config            ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────┐     ║
--- ║  │  lazydev.nvim                                                   │     ║
--- ║  │                                                                 │     ║
--- ║  │  • Injects Neovim runtime + plugin type annotations into lua_ls │     ║
--- ║  │  • Enables autocompletion for vim.*, Snacks.*, LazyVim.*, etc.  │     ║
--- ║  │  • Adds luv (vim.uv) type definitions                           │     ║
--- ║  │  • Library entries loaded lazily (only when keyword detected)   │     ║
--- ║  │  • Zero runtime cost outside Lua files                          │     ║
--- ║  └─────────────────────────────────────────────────────────────────┘     ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • ft = "lua" (only loads for Lua files)                                 ║
--- ║  • Library entries use `words` filter (keyword-triggered)                ║
--- ║  • No keymaps — purely automatic behavior                                ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════
local settings = require("core.settings")
if not settings:is_plugin_enabled("lazydev") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"folke/lazydev.nvim",

	ft = "lua",
	cmd = "LazyDev",

	opts = {
		library = {
			-- Luv (vim.uv) type definitions
			{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
			-- Plugin APIs (loaded when keyword appears in buffer)
			{ path = "snacks.nvim", words = { "Snacks" } },
			{ path = "lazy.nvim", words = { "lazy", "LazyVim" } },
		},
	},
}
