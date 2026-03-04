---@file lua/plugins/ui/mini-icons.lua
---@description mini.nvim monorepo — sole icon provider + module host
---@module "plugins.ui.mini-icons"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.icons Central icon definitions (glyphs)
---@see plugins.editor.mini Core editing modules (ai, pairs, surround, etc.)
---@see plugins.editor.mini-align Alignment module (separate config)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ui/mini-icons.lua — mini.nvim monorepo entry point              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  mini.nvim (monorepo)                                            │    ║
--- ║  │                                                                  │    ║
--- ║  │  This single repo provides ALL mini.* modules:                   │    ║
--- ║  │  ├─ mini.icons     (this file — icon engine, sole provider)      │    ║
--- ║  │  ├─ mini.ai        (configured in plugins/editor/mini.lua)       │    ║
--- ║  │  ├─ mini.pairs     (configured in plugins/editor/mini.lua)       │    ║
--- ║  │  ├─ mini.surround  (configured in plugins/editor/mini.lua)       │    ║
--- ║  │  ├─ mini.align     (configured in plugins/editor/mini-align.lua) │    ║
--- ║  │  └─ (40+ other modules available on-demand)                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  mini.icons specifics:                                           │    ║
--- ║  │  • ONLY icon provider in this config                             │    ║
--- ║  │  • nvim-web-devicons fully eliminated                            │    ║
--- ║  │  • Mocks nvim-web-devicons via package.preload                   │    ║
--- ║  │  • specs disables nvim-web-devicons at the lazy.nvim level       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Two layers of protection:                                       │    ║
--- ║  │  1. specs { enabled = false } → lazy.nvim won't install it       │    ║
--- ║  │  2. package.preload mock → require() calls get redirected        │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • lazy = true (loaded on-demand when first icon is requested)           ║
--- ║  • package.preload mock (zero-cost until require() is called)            ║
--- ║  • specs disables nvim-web-devicons (no duplicate icon provider)         ║
--- ║  • Monorepo: 1 repo instead of 5 separate mini.* repos                   ║
--- ║  • Unused modules have ZERO cost (only require'd modules load)           ║
--- ║  • No keymaps (pure UI utility)                                          ║
--- ║                                                                          ║
--- ║  Custom glyphs:                                                          ║
--- ║    .keep              → 󰊢  (git placeholder)                             ║
--- ║    devcontainer.json  →   (dev container)                                ║
--- ║    dotenv             →   (environment file)                             ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
if not settings:is_plugin_enabled("mini_icons") then return {} end

return {
	"echasnovski/mini.nvim",
	version = false,
	lazy = true,

	specs = {
		{ "nvim-tree/nvim-web-devicons", enabled = false, optional = true },
	},

	---@param _ table Plugin spec (unused)
	---@param opts table Resolved options (unused, setup below)
	config = function(_, opts)
		require("mini.icons").setup({
			file = {
				[".keep"] = { glyph = "󰊢", hl = "MiniIconsGrey" },
				["devcontainer.json"] = { glyph = "", hl = "MiniIconsAzure" },
			},
			filetype = {
				dotenv = { glyph = "", hl = "MiniIconsYellow" },
			},
		})
	end,

	-- ═══════════════════════════════════════════════════════════════════
	-- INIT — package.preload mock (runs before plugin loads)
	--
	-- Intercepts require("nvim-web-devicons") from ANY plugin and
	-- redirects to mini.icons' compatibility layer. This is the
	-- runtime counterpart to the specs block above:
	--
	--   specs  → prevents installation/loading by lazy.nvim
	--   mock   → prevents runtime errors from require() calls
	--
	-- Why package.preload and not package.loaded?
	-- • package.preload is a function — mini.icons loads ONLY when
	--   the first require() call happens (true lazy loading)
	-- • package.loaded would require mini.icons to be already loaded
	--
	-- The mock is idempotent: subsequent require() calls return
	-- the cached module from package.loaded automatically.
	-- ═══════════════════════════════════════════════════════════════════
	init = function()
		---@diagnostic disable-next-line: duplicate-set-field
		package.preload["nvim-web-devicons"] = function()
			require("mini.icons").mock_nvim_web_devicons()
			return package.loaded["nvim-web-devicons"]
		end
	end,
}
