---@file lua/plugins/misc/vim-startuptime.lua
---@description StartupTime — Neovim boot performance profiler with multi-sample averaging
---@module "plugins.misc.vim-startuptime"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings singleton (plugins.startuptime.enabled)
---
---@see https://github.com/dstein64/vim-startuptime
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/misc/vim-startuptime.lua — Boot profiler                        ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Pure diagnostic tool — no keymaps, no runtime overhead.         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Usage:                                                          │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  :StartupTime                                              │  │    ║
--- ║  │  │  • Launches 10 separate Neovim instances in the background │  │    ║
--- ║  │  │  • Measures startup time for each (--startuptime flag)     │  │    ║
--- ║  │  │  • Aggregates and averages results                         │  │    ║
--- ║  │  │  • Displays a sorted breakdown by file/plugin              │  │    ║
--- ║  │  │  • Highlights slow items for quick identification          │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Configuration:                                                  │    ║
--- ║  │  ├─ vim.g.startuptime_tries = 10 (set in init, before load)      │    ║
--- ║  │  └─ cmd-only loading (zero startup cost until :StartupTime)      │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Design decisions:                                                       ║
--- ║  ├─ cmd-only loading — zero impact on the startup time being measured    ║
--- ║  ├─ vim.g set in init() — must be available before plugin loads,         ║
--- ║  │  config() would be too late                                           ║
--- ║  ├─ No keymaps — diagnostic tool, invoked manually                       ║
--- ║  ├─ 10 samples — enough for statistical significance, not too slow       ║
--- ║  └─ Guard via settings:is_plugin_enabled — disabled by default           ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • cmd-only loading (zero startup cost)                                  ║
--- ║  • vim.g set in init (not config — correct timing guarantee)             ║
--- ║  • Disabled by default in settings (startuptime.enabled = false)         ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
if not settings:is_plugin_enabled("startuptime") then
	return {}
end

---@type lazy.PluginSpec
return {
	"dstein64/vim-startuptime",
	cmd = "StartupTime",

	-- ═══════════════════════════════════════════════════════════════════
	-- INIT — vim.g variables must be set BEFORE the plugin loads
	--
	-- vim.g.startuptime_tries is read by the plugin when :StartupTime
	-- executes. Setting it in init (not config) ensures the value is
	-- available regardless of load timing.
	-- ═══════════════════════════════════════════════════════════════════

	init = function()
		vim.g.startuptime_tries = 10
	end,
}
