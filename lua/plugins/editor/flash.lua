---@file lua/plugins/editor/flash.lua
---@description Flash — label-based motion plugin for jumping anywhere with minimal keystrokes
---@module "plugins.editor.flash"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.telescope   Fuzzy finder (complementary, different navigation scope)
---@see plugins.editor.harpoon     Per-file marks (complementary, bookmark-based)
---
---@see https://github.com/folke/flash.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/flash.lua — Enterprise-grade navigation                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  flash.nvim                                                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Motion modes:                                                   │    ║
--- ║  │  ├─ Jump           Type chars → labels appear → press label      │    ║
--- ║  │  │                 Works in normal, visual, operator-pending     │    ║
--- ║  │  ├─ Treesitter     Select entire AST nodes by label              │    ║
--- ║  │  │                 Labels show before/after node boundaries      │    ║
--- ║  │  ├─ Remote         Operate on distant text objects               │    ║
--- ║  │  │                 (e.g. `yr<label>iw` to yank a remote word)    │    ║
--- ║  │  ├─ Treesitter     Search treesitter nodes across windows        │    ║
--- ║  │  │  Search         with operator-pending support                 │    ║
--- ║  │  ├─ Char           Enhanced f/F/t/T with labels & multi-line     │    ║
--- ║  │  │                 Replaces built-in char motions                │    ║
--- ║  │  └─ Search         Labels appear during / and ? search           │    ║
--- ║  │                    Jump directly to any match by label           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Rainbow labels:                                                 │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Labels use rainbow coloring (shade=5) for visual        │    │    ║
--- ║  │  │  distinction. Lowercase only (uppercase=false) to avoid  │    │    ║
--- ║  │  │  accidental Shift-key errors.                            │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • VeryLazy loading (available immediately but deferred init)            ║
--- ║  • VSCode compatible (works in vscode-neovim extension)                  ║
--- ║  • Defensive imports (pcall for core modules — VSCode safety)            ║
--- ║  • backdrop=true for jump focus (dims non-target areas)                  ║
--- ║  • Priority 5000 for highlight groups (above most plugins)               ║
--- ║  • Icons from core/icons.lua with fallback defaults                      ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║  ┌─────────────────────────────────────────────────────────────────────┐ ║
--- ║  │  KEY    MODE         ACTION              OVERRIDES                  │ ║
--- ║  │  s      n, x, o     Flash jump           s (substitute) → use cl    │ ║
--- ║  │  S      n, x, o     Flash Treesitter     S (sub line)  → use cc     │ ║
--- ║  │  r      o            Remote flash         (safe, no conflict)       │ ║
--- ║  │  R      o, x         Treesitter search    R in visual (rare usage)  │ ║
--- ║  │  <C-s>  c            Toggle flash search  (safe, no conflict)       │ ║
--- ║  └─────────────────────────────────────────────────────────────────────┘ ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Flash plugin is disabled in core/settings.lua.
-- Uses pcall because this plugin is VSCode-compatible and core modules
-- may not be available in all environments.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok and not settings:is_plugin_enabled("flash") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
--
-- Defensive pcall imports for VSCode compatibility. When running inside
-- vscode-neovim, core modules may not be present. Fallback icon tables
-- ensure keymaps always have descriptive labels regardless of environment.
-- ═══════════════════════════════════════════════════════════════════════════

local icons_ok, icons = pcall(require, "core.icons")

if not icons_ok or not icons then
	---@type table Fallback icon definitions for VSCode / minimal environments
	icons = {
		ui = { Search = " ", Code = "󰅩", Rocket = "󰓅", Target = "󰓾" },
	}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps and configuration.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Safely retrieve an icon from a table with a fallback default.
---
--- Used throughout this module to handle environments where
--- `core.icons` may not be fully loaded (VSCode, minimal configs).
---
--- ```lua
--- safe_icon(icons.ui, "Search", "")   -- → " " or ""
--- safe_icon(nil, "Search", "⚡")        -- → "⚡"
--- ```
---
---@param tbl table|nil Icon table to look up (may be nil)
---@param key string Key name to retrieve from the table
---@param fallback string Default value if table or key is missing
---@return string icon The resolved icon string
---@private
local function safe_icon(tbl, key, fallback)
	if type(tbl) == "table" and tbl[key] ~= nil then return tbl[key] end
	return fallback or ""
end

---@type table UI icon subtable (may be fallback)
local ui = icons.ui or {}

--- Create a lazy-safe flash method caller.
---
--- Returns a function that, when invoked, requires `flash` and calls
--- the named method. Uses pcall to prevent errors if the plugin is
--- not yet loaded or if the method doesn't exist.
---
--- This pattern avoids eager `require("flash")` at module load time,
--- which would defeat lazy.nvim's deferred loading strategy.
---
--- ```lua
--- local jump = flash_call("jump")
--- jump()  -- equivalent to require("flash").jump()
---
--- local ts = flash_call("treesitter")
--- ts()    -- equivalent to require("flash").treesitter()
--- ```
---
---@param method string Name of the flash module method to call
---@return function caller Deferred function that calls `flash.<method>()`
---@private
local function flash_call(method)
	return function()
		local ok, mod = pcall(require, "flash")
		if ok and mod[method] then mod[method]() end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPEC
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Trigger            │ Details                                      │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ event              │ VeryLazy (deferred init, always available)   │
-- │ keys               │ s, S, r, R, <C-s> (primary entry points)    │
-- │ vscode             │ true (works in vscode-neovim extension)     │
-- │ dependencies       │ none                                         │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"folke/flash.nvim",
	event = "VeryLazy",
	vscode = true,

	-- ═══════════════════════════════════════════════════════════════════
	-- GLOBAL KEYMAPS
	--
	-- ⚠ CONFLICT NOTES:
	-- • s in normal — overrides default s (substitute char), use cl instead
	-- • S in normal — overrides default S (substitute line), use cc instead
	-- • r in operator-pending — safe, no conflict with normal r (replace)
	-- • R in visual/op — overrides default R in visual (rare usage)
	-- • <C-s> in command — safe, no default binding in command mode
	-- ═══════════════════════════════════════════════════════════════════
	keys = {
		-- ── Jump (primary motion) ────────────────────────────────────
		{
			"s",
			mode = { "n", "x", "o" },
			flash_call("jump"),
			desc = safe_icon(ui, "Search", "") .. " Flash",
		},

		-- ── Treesitter selection ─────────────────────────────────────
		{
			"S",
			mode = { "n", "x", "o" },
			flash_call("treesitter"),
			desc = safe_icon(ui, "Code", "󰅩") .. " Flash Treesitter",
		},

		-- ── Remote flash (operator-pending only) ─────────────────────
		{
			"r",
			mode = "o",
			flash_call("remote"),
			desc = safe_icon(ui, "Target", "󰓾") .. " Remote Flash",
		},

		-- ── Treesitter search (operator-pending + visual) ────────────
		{
			"R",
			mode = { "o", "x" },
			flash_call("treesitter_search"),
			desc = safe_icon(ui, "Code", "󰅩") .. " Treesitter search",
		},

		-- ── Toggle flash in search command line ──────────────────────
		{
			"<c-s>",
			mode = { "c" },
			flash_call("toggle"),
			desc = safe_icon(ui, "Search", "") .. " Toggle Flash search",
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	--
	-- Organized into logical sections:
	-- ├─ Labels     Character set and display style
	-- ├─ Search     Multi-window, direction, matching mode
	-- ├─ Jump       Jumplist integration, cursor positioning
	-- ├─ Highlight  Backdrop, match highlighting, priority
	-- ├─ Modes      Per-mode overrides (search, char, treesitter, remote)
	-- └─ Prompt     Search prompt icon and styling
	-- ═══════════════════════════════════════════════════════════════════
	opts = {
		-- ── Labels ──────────────────────────────────────────────────
		-- Home row first (asdf…) for ergonomic label selection.
		-- Lowercase only: prevents accidental Shift-key misses.
		-- Rainbow coloring for instant visual distinction.
		labels = "asdfghjklqwertyuiopzxcvbnm",
		label = {
			uppercase = false,
			rainbow = {
				enabled = true,
				shade = 5,
			},
			style = "overlay", ---@type "eol"|"overlay"|"right_align"|"inline"
		},

		-- ── Search ──────────────────────────────────────────────────
		-- Multi-window: jump targets span all visible windows.
		-- Exact mode: no fuzzy matching (predictable behavior).
		-- Wrap: search wraps around buffer boundaries.
		search = {
			multi_window = true,
			forward = true,
			wrap = true,
			mode = "exact", ---@type "exact"|"search"|"fuzzy"
			incremental = false,
		},

		-- ── Jump ────────────────────────────────────────────────────
		-- Jumplist: adds entries for <C-o> / <C-i> navigation.
		-- pos=start: cursor lands at the start of the match.
		-- No autojump: always show labels (even for single match).
		jump = {
			jumplist = true,
			pos = "start", ---@type "start"|"end"|"range"
			history = false,
			register = false,
			nohlsearch = false,
			autojump = false,
		},

		-- ── Highlight ───────────────────────────────────────────────
		-- Backdrop dims non-target areas for focus.
		-- Priority 5000 ensures labels render above other highlights.
		highlight = {
			backdrop = true,
			matches = true,
			priority = 5000,
			groups = {
				match = "FlashMatch",
				current = "FlashCurrent",
				backdrop = "FlashBackdrop",
				label = "FlashLabel",
			},
		},

		-- ── Modes ───────────────────────────────────────────────────
		-- Per-mode configuration overrides.
		modes = {
			-- Search mode: integrates with / and ? search
			-- History/register enabled for search consistency.
			-- nohlsearch clears highlights after jumping.
			search = {
				enabled = true,
				highlight = { backdrop = false },
				jump = { history = true, register = true, nohlsearch = true },
			},

			-- Char mode: enhanced f/F/t/T motions
			-- Multi-line enabled for cross-line char jumps.
			-- hjkliardc excluded from labels (common motions).
			-- ; and , for next/prev (Vim-native feel).
			char = {
				enabled = true,
				autohide = false,
				jump_labels = false,
				multi_line = true,
				label = { exclude = "hjkliardc" },
				keys = { "f", "F", "t", "T", ";", "," },
				char_actions = function(motion)
					return {
						[";"] = "next",
						[","] = "prev",
						[motion:lower()] = "next",
						[motion:upper()] = "prev",
					}
				end,
				search = { wrap = false },
				highlight = { backdrop = true },
			},

			-- Treesitter mode: select entire AST nodes
			-- pos=range: selects the full node (not just start).
			-- autojump: instant jump when only one match exists.
			-- Inline labels shown before AND after node boundaries.
			treesitter = {
				labels = "abcdefghijklmnop",
				jump = { pos = "range", autojump = true },
				search = { incremental = false },
				label = {
					before = true,
					after = true,
					style = "inline",
				},
				highlight = {
					backdrop = false,
					matches = false,
				},
			},

			-- Treesitter search: find treesitter nodes across windows
			-- Remote operations restore cursor after action.
			treesitter_search = {
				jump = { pos = "range" },
				search = { multi_window = true, wrap = true, incremental = false },
				remote_op = { restore = true },
				label = { before = true, after = true, style = "inline" },
			},

			-- Remote mode: operate on text at a distance
			-- restore=true: cursor returns after remote operation.
			-- motion=true: allows motion commands in remote context.
			remote = {
				remote_op = {
					restore = true,
					motion = true,
				},
			},
		},

		-- ── Prompt ──────────────────────────────────────────────────
		-- Custom search prompt with icon for visual consistency.
		prompt = {
			enabled = true,
			prefix = { { safe_icon(ui, "Search", "⚡"), "FlashPromptIcon" } },
		},
	},
}
