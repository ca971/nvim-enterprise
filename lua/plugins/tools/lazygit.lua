---@file lua/plugins/tools/lazygit.lua
---@description LazyGit — full Git UI inside Neovim via snacks.nvim floating terminal
---@module "plugins.tools.lazygit"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings singleton (plugins.lazygit.enabled)
---@see core.platform Platform singleton (has_executable for lazygit detection)
---@see core.icons Centralized icon definitions (git.Logo, git.Branch, git.Diff)
---@see plugins.ui.snacks Snacks.nvim base configuration (lazygit module)
---@see plugins.editor.gitsigns Complementary in-buffer git indicators
---@see plugins.editor.neogit Complementary Magit-like git interface
---@see plugins.editor.diffview Complementary git diff viewer
---
---@see https://github.com/jesseduffield/lazygit
---@see https://github.com/folke/snacks.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/tools/lazygit.lua — Full Git UI via snacks.nvim                 ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard chain (2-level):                                          │    ║
--- ║  │  ├─ plugins.lazygit.enabled = false → return {}                  │    ║
--- ║  │  └─ lazygit not on PATH             → return {}                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Executable detection:                                           │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  1. Try platform:has_executable("lazygit") via pcall       │  │    ║
--- ║  │  │  2. Fallback: vim.fn.executable("lazygit") == 1            │  │    ║
--- ║  │  │  3. If not found → return {} (silent skip)                 │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Integration via snacks.nvim:                                    │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • No separate plugin — uses Snacks.lazygit module         │  │    ║
--- ║  │  │  • Snacks.lazygit() → opens lazygit in floating terminal   │  │    ║
--- ║  │  │  • Snacks.lazygit.log() → git log for cwd                  │  │    ║
--- ║  │  │  • Snacks.lazygit.log_file() → git log for current file    │  │    ║
--- ║  │  │  • configure = true → auto-sets lazygit Neovim integration │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    <leader>gg   Open Lazygit                           (n)               ║
--- ║    <leader>gG   Lazygit log (cwd scope)                (n)               ║
--- ║    <leader>gF   Lazygit log (current file)             (n)               ║
--- ║                                                                          ║
--- ║  Design decisions:                                                       ║
--- ║  ├─ Uses snacks.nvim — no separate lazygit.nvim plugin needed            ║
--- ║  ├─ Executable check before spec return — no broken keymaps if           ║
--- ║  │  lazygit is not installed                                             ║
--- ║  ├─ pcall-wrapped platform check with vim.fn.executable fallback         ║
--- ║  ├─ lazygit() helper validates Snacks availability at runtime            ║
--- ║  │  (pcall + nil checks) for safe deferred invocation                    ║
--- ║  ├─ configure = true auto-creates lazygit config for Neovim              ║
--- ║  │  integration (edit-in-nvim, correct $EDITOR, etc.)                    ║
--- ║  └─ Icon fallbacks ensure keymaps display correctly without core.icons   ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • keys-only loading (zero startup cost until first keymap use)          ║
--- ║  • Executable check at spec evaluation time (not at runtime)             ║
--- ║  • No separate plugin install — leverages existing snacks.nvim           ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════
-- GUARD — SETTINGS
--
-- Checks if the lazygit plugin is enabled in settings.
-- Uses pcall for graceful degradation during bootstrap.
-- ═══════════════════════════════════════════════════════════════════════

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok and not settings:is_plugin_enabled("lazygit") then return {} end

-- ═══════════════════════════════════════════════════════════════════════
-- GUARD — EXECUTABLE
--
-- Checks if lazygit is available on PATH. Tries platform module
-- first (cached detection), falls back to vim.fn.executable.
-- Returns empty spec if lazygit is not installed (silent skip).
-- ═══════════════════════════════════════════════════════════════════════

local platform_ok, platform = pcall(require, "core.platform")

---@type boolean
local has_lazygit = false
if platform_ok and platform and platform.has_executable then
	local ok, result = pcall(platform.has_executable, platform, "lazygit")
	has_lazygit = ok and result
else
	has_lazygit = vim.fn.executable("lazygit") == 1
end

if not has_lazygit then return {} end

-- ═══════════════════════════════════════════════════════════════════════
-- SAFE REQUIRES
--
-- Icons loaded via pcall with fallback table. Ensures keymaps
-- display correctly even during bootstrap.
-- ═══════════════════════════════════════════════════════════════════════

local icons_ok, icons = pcall(require, "core.icons")

if not icons_ok or not icons then icons = {
	git = { Logo = "󰊢", Branch = "", Diff = "" },
} end

--- Safely get an icon from a table with a fallback value.
---
---@param tbl table|nil Icon group table
---@param key string Icon key within the group
---@param fallback string Fallback string if key is missing
---@return string icon The icon string
---@private
local function icon(tbl, key, fallback)
	if type(tbl) == "table" and tbl[key] ~= nil then return tbl[key] end
	return fallback or ""
end

---@type table
local gi = icons.git or {}

-- ═══════════════════════════════════════════════════════════════════════
-- SNACKS LAZYGIT WRAPPER
--
-- Creates safe closures for Snacks.lazygit calls. Each closure
-- validates that Snacks and Snacks.lazygit are available before
-- invoking the method. Shows a warning if not.
-- ═══════════════════════════════════════════════════════════════════════

--- Create a safe Snacks.lazygit caller.
---
--- Returns a closure that validates Snacks availability at runtime
--- and invokes the specified lazygit method. Shows a warning
--- notification if Snacks or Snacks.lazygit is not available.
---
--- ```lua
--- lazygit()          --> calls Snacks.lazygit()
--- lazygit("log")     --> calls Snacks.lazygit.log()
--- lazygit("log_file") --> calls Snacks.lazygit.log_file()
--- ```
---
---@param method? string Snacks.lazygit method name (nil for default lazygit())
---@return function executor Closure suitable for lazy.nvim `keys[]` entries
---@private
local function lazygit(method)
	return function()
		local ok = pcall(function()
			return Snacks
		end)
		if not ok or not Snacks then
			vim.notify("Snacks not loaded", vim.log.levels.WARN)
			return
		end
		if not Snacks.lazygit then
			vim.notify("Snacks.lazygit not available", vim.log.levels.WARN)
			return
		end
		if method and method ~= "" then
			if type(Snacks.lazygit[method]) == "function" then Snacks.lazygit[method]() end
		else
			Snacks.lazygit()
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"folke/snacks.nvim",

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYMAPS
	-- ═══════════════════════════════════════════════════════════════════

	keys = {
		{
			"<leader>gg",
			lazygit(),
			desc = icon(gi, "Logo", "󰊢") .. " Lazygit",
		},
		{
			"<leader>gG",
			lazygit("log"),
			desc = icon(gi, "Branch", "") .. " Lazygit log (cwd)",
		},
		{
			"<leader>gF",
			lazygit("log_file"),
			desc = icon(gi, "Diff", "") .. " Lazygit log (file)",
		},
	},

	opts = {
		lazygit = {
			enabled = true,
			configure = true,
		},
	},
}
