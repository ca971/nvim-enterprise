---@file lua/plugins/misc/wakatime.lua
---@description WakaTime — automatic coding time tracking via the WakaTime service
---@module "plugins.misc.wakatime"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings singleton (plugins.wakatime.enabled)
---
---@see https://github.com/wakatime/vim-wakatime
---@see https://wakatime.com/dashboard
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/misc/wakatime.lua — Automatic coding metrics                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Pure background service — zero keymaps, zero UI, zero config.   │    ║
--- ║  │  Runs silently after VeryLazy event, tracking coding activity    │    ║
--- ║  │  per project, language, file, and branch.                        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Features:                                                       │    ║
--- ║  │  ├─ Automatic time tracking per project, language, file          │    ║
--- ║  │  ├─ Git branch awareness                                         │    ║
--- ║  │  ├─ Runs silently in background (no UI interruptions)            │    ║
--- ║  │  ├─ Dashboard at https://wakatime.com/dashboard                  │    ║
--- ║  │  └─ Requires API key: run :WakaTimeApiKey on first use           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Setup (one-time):                                               │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  1. Install wakatime-cli: pip install wakatime             │  │    ║
--- ║  │  │     (or brew install wakatime-cli on macOS)                │  │    ║
--- ║  │  │  2. Get API key: https://wakatime.com/settings/api-key     │  │    ║
--- ║  │  │  3. Run :WakaTimeApiKey and paste your key                 │  │    ║
--- ║  │  │  4. Key stored in ~/.wakatime.cfg (never in Neovim config) │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Commands:                                                       │    ║
--- ║  │  ├─ :WakaTimeApiKey          Set/update API key                  │    ║
--- ║  │  ├─ :WakaTimeDebugEnable     Enable debug logging                │    ║
--- ║  │  ├─ :WakaTimeDebugDisable    Disable debug logging               │    ║
--- ║  │  └─ :WakaTimeToday           Show today's coding time            │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Design decisions:                                                       ║
--- ║  ├─ Disabled by default in settings (wakatime.enabled = false)           ║
--- ║  ├─ No keymaps — wakatime is a background service                        ║
--- ║  ├─ No opts — configured via :WakaTimeApiKey and ~/.wakatime.cfg         ║
--- ║  ├─ VeryLazy + cmd loading — minimal startup impact                      ║
--- ║  ├─ pcall guard on settings — degrades gracefully during bootstrap       ║
--- ║  └─ API key stored in ~/.wakatime.cfg, NOT in Neovim config (security)   ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • VeryLazy event loading (no startup cost)                              ║
--- ║  • cmd loading as fallback (commands available before VeryLazy fires)    ║
--- ║  • Zero runtime overhead (wakatime-cli runs as external process)         ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Uses pcall for settings access — degrades gracefully during
-- bootstrap when core modules may not be available yet.
-- Disabled by default in settings (plugins.wakatime.enabled = false).
-- ═══════════════════════════════════════════════════════════════════════

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok and not settings:is_plugin_enabled("wakatime") then
	return {}
end

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"wakatime/vim-wakatime",
	event = "VeryLazy",
	cmd = { "WakaTimeApiKey", "WakaTimeDebugEnable", "WakaTimeDebugDisable", "WakaTimeToday" },

	-- No keymaps — wakatime is a background service
	-- No opts — configured via :WakaTimeApiKey and ~/.wakatime.cfg
}
