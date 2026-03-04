---@file lua/plugins/lazyvim_extras/extras_loader.lua
---@description ExtrasLoader — LazyVim dependency loader for extras compatibility layer
---@module "plugins.lazyvim_extras.extras_loader"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings singleton (lazyvim_extras.enabled)
---@see config.lazyvim_shim LazyVim global shim (created BEFORE lazy.setup)
---@see config.plugin_manager Plugin spec collector (handles actual extras imports)
---@see config.extras_browser Interactive extras toggle UI
---@see plugins.lazyvim_extras Extras subsystem entry point
---
---@see https://github.com/LazyVim/LazyVim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/lazyvim_extras/extras_loader.lua — LazyVim dependency loader   ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Purpose:                                                        │    ║
--- ║  │  Ensures LazyVim is available as a dependency so that LazyVim    │    ║
--- ║  │  extras (e.g., lazyvim.plugins.extras.lang.python) can resolve   │    ║
--- ║  │  their imports during lazy.setup(). This file does NOT import    │    ║
--- ║  │  the extras themselves — that is handled by plugin_manager.lua.  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Load pipeline:                                                  │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  1. Check lazyvim_extras.enabled in settings               │  │    ║
--- ║  │  │     → false: return {} (no LazyVim dependency)             │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  2. Detect bootstrap state                                 │  │    ║
--- ║  │  │     Check if stdpath("data")/lazy/LazyVim exists           │  │    ║
--- ║  │  │     → missing: is_bootstrap = true                         │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  3. Build LazyVim plugin spec                              │  │    ║
--- ║  │  │     ├─ priority = 10000 (load before all extras)           │  │    ║
--- ║  │  │     ├─ lazy = false (must be available immediately)        │  │    ║
--- ║  │  │     ├─ Bootstrap: minimal spec (just clone)                │  │    ║
--- ║  │  │     └─ Normal: spec with opts = {} (allow config)          │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  4. Return { lazyvim_spec }                                │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Relationship to other modules:                                  │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  config/lazyvim_shim.lua                                   │  │    ║
--- ║  │  │  └─ Creates global LazyVim table + package.preload         │  │    ║
--- ║  │  │     entries BEFORE lazy.setup()                             │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  extras_loader.lua (THIS FILE)                             │  │    ║
--- ║  │  │  └─ Ensures LazyVim repo is cloned and available as a      │  │    ║
--- ║  │  │     lazy.nvim dependency                                   │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  config/plugin_manager.lua                                 │  │    ║
--- ║  │  │  └─ Generates { import = "lazyvim.plugins.extras.xxx" }    │  │    ║
--- ║  │  │     specs from the enabled extras list in settings          │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  config/extras_browser.lua                                 │  │    ║
--- ║  │  │  └─ UI for toggling extras on/off (writes to settings)     │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Design decisions:                                                       ║
--- ║  ├─ Minimal spec during bootstrap — avoids config errors when            ║
--- ║  │  LazyVim modules aren't available yet (first clone)                   ║
--- ║  ├─ priority = 10000 — LazyVim must load before any extra that          ║
--- ║  │  imports from lazyvim.plugins.extras.*                                ║
--- ║  ├─ lazy = false — extras reference LazyVim at spec evaluation time,    ║
--- ║  │  so it must be on the runtimepath immediately                        ║
--- ║  ├─ opts injected only after bootstrap — prevents errors from           ║
--- ║  │  referencing LazyVim config modules that don't exist yet              ║
--- ║  ├─ fs_stat check (not pcall require) — faster and doesn't pollute     ║
--- ║  │  the module cache during detection                                   ║
--- ║  └─ Actual extras imports are NOT in this file — separation of          ║
--- ║     concerns between "make LazyVim available" and "import extras"       ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Early return when extras disabled (no LazyVim overhead)               ║
--- ║  • fs_stat is a single syscall (O(1) bootstrap detection)                ║
--- ║  • Minimal spec during bootstrap reduces clone + setup time              ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")

-- ═══════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if LazyVim extras are disabled in settings.
-- No LazyVim dependency is added, saving clone time and disk space.
-- ═══════════════════════════════════════════════════════════════════════

---@type table|boolean
local extras_enabled = settings:get("lazyvim_extras.enabled", false)

if not extras_enabled then return {} end

-- ═══════════════════════════════════════════════════════════════════════
-- BOOTSTRAP DETECTION
--
-- Checks if the LazyVim directory exists on disk. On first launch
-- (bootstrap), the directory is missing and we use a minimal spec
-- to ensure a clean clone without attempting to reference LazyVim
-- config modules that don't exist yet.
-- ═══════════════════════════════════════════════════════════════════════

---@diagnostic disable-next-line: undefined-field
local uv = vim.uv or vim.loop

---@type string Absolute path to the LazyVim installation directory
local lazyvim_path = vim.fn.stdpath("data") .. "/lazy/LazyVim"

---@type boolean Whether this is the first launch (LazyVim not yet cloned)
local is_bootstrap = not uv.fs_stat(lazyvim_path)

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
--
-- Builds the LazyVim dependency spec. During bootstrap, opts is nil
-- (not present). After bootstrap, opts = {} allows configuration.
-- ═══════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
local lazyvim_spec = {
	"LazyVim/LazyVim",
	priority = 10000,
	lazy = false,
	-- opts is included only after bootstrap (LazyVim already cloned).
	-- During bootstrap, nil opts keeps the spec minimal for a clean clone.
	opts = not is_bootstrap and {} or nil,
}

return { lazyvim_spec }
