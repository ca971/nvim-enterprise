---@file lua/plugins/editor/harpoon.lua
---@description Harpoon 2 — fast file navigation with persistent per-project marks
---@module "plugins.editor.harpoon"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.gitsigns   Git hunk navigation (]h/[h — different scope)
---@see plugins.editor.telescope  Buffer/file pickers (complementary, fuzzy search)
---@see plugins.editor.persisted  Session management (complementary, project-level)
---@see plugins.ui.bufferline     Buffer tabs (positional jump via <M-1>–<M-9>)
---
---@see https://github.com/ThePrimeagen/harpoon/tree/harpoon2
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/harpoon.lua — Quick file switcher                        ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  harpoon2                                                        │    ║
--- ║  │                                                                  │    ║
--- ║  │  • Persistent file marks (survive nvim restarts)                 │    ║
--- ║  │  • Per-project mark lists (tied to git root / cwd)               │    ║
--- ║  │  • Quick menu for reordering / removing marks                    │    ║
--- ║  │  • Instant jump to marked files (1–5)                            │    ║
--- ║  │  • Circular next/prev navigation (]H / [H)                       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Project key resolution:                                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Search upward for root markers:                      │    │    ║
--- ║  │  │     .git, Makefile, package.json, Cargo.toml, go.mod     │    │    ║
--- ║  │  │  2. Fallback to vim.uv.cwd()                             │    │    ║
--- ║  │  │  3. Each unique key → separate harpoon mark list         │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Quick menu UI:                                                  │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │            ╭───── 󰃀 Harpoon ─────╮                       │    │    ║
--- ║  │  │            │ 1  lua/init.lua     │                       │    │    ║
--- ║  │  │            │ 2  lua/settings.lua │                       │    │    ║
--- ║  │  │            │ 3  lua/keymaps.lua  │                       │    │    ║
--- ║  │  │            ╰─────────────────────╯                       │    │    ║
--- ║  │  │  • Rounded borders from core/icons.lua                   │    │    ║
--- ║  │  │  • Line numbers ON, cursorline ON                        │    │    ║
--- ║  │  │  • Drag to reorder, dd to remove, q to close             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Complements (does NOT replace):                                 │    ║
--- ║  │  ├─ <M-1>–<M-9>  Bufferline positional jump (volatile, resets)   │    ║
--- ║  │  ├─ <Space>sm     Vim marks (snacks picker)                      │    ║
--- ║  │  ├─ <Space>bj     Buffer pick (bufferline — visual pick)         │    ║
--- ║  │  └─ <Space>fb     Buffer list (telescope — fuzzy search)         │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Keys-only loading (zero startup cost until first keymap)              ║
--- ║  • Harpoon list cached in closure (no repeated require)                  ║
--- ║  • No autocmds (pure on-demand architecture)                             ║
--- ║  • save_on_toggle + sync_on_ui_close (crash-safe persistence)            ║
--- ║  • Borders from core/icons.lua (single source of truth)                  ║
--- ║  • Icons from core/icons.lua (single source of truth)                    ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║  ┌─────────────────────────────────────────────────────────────────────┐ ║
--- ║  │  KEY          MODE   ACTION                     CONFLICT STATUS     │ ║
--- ║  │  <leader>ha   n      Add file to harpoon list   ✓ safe (h* owned)   │ ║
--- ║  │  <leader>hd   n      Remove file from list      ✓ safe              │ ║
--- ║  │  <leader>hh   n      Toggle quick menu          ✓ safe              │ ║
--- ║  │  <leader>h1   n      Jump to mark 1             ✓ safe              │ ║
--- ║  │  <leader>h2   n      Jump to mark 2             ✓ safe              │ ║
--- ║  │  <leader>h3   n      Jump to mark 3             ✓ safe              │ ║
--- ║  │  <leader>h4   n      Jump to mark 4             ✓ safe              │ ║
--- ║  │  <leader>h5   n      Jump to mark 5             ✓ safe              │ ║
--- ║  │  ]H           n      Next harpoon mark          ✓ safe              │ ║
--- ║  │  [H           n      Prev harpoon mark          ✓ safe              │ ║
--- ║  │                                                                     │ ║
--- ║  │  ⚠ NOTE: ]h/[h are reserved for gitsigns hunk navigation.           │ ║
--- ║  │  Harpoon uses ]H/[H (uppercase) to avoid the conflict.              │ ║
--- ║  └─────────────────────────────────────────────────────────────────────┘ ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Harpoon plugin is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_plugin_enabled("harpoon") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

---@type Icons
local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Get the harpoon list for the current project.
---
--- Wraps `require("harpoon"):list()` for use in lazy keymap functions.
--- The list is project-scoped via the `key` function in settings
--- (uses git root or CWD).
---
--- ```lua
--- harpoon_list():add()       -- add current file
--- harpoon_list():select(1)   -- jump to mark 1
--- harpoon_list():next()      -- circular next
--- ```
---
---@return table list Harpoon list instance for the current project
---@private
local function harpoon_list()
	return require("harpoon"):list()
end

--- Notify the user about a harpoon mark operation.
---
--- Displays the current filename with a Harpoon-titled notification.
--- Used for add/remove feedback.
---
--- ```lua
--- harpoon_notify("Harpooned")   -- → "Harpooned: init.lua"
--- harpoon_notify("Removed")     -- → "Removed: init.lua"
--- ```
---
---@param action string Action verb to display (e.g. "Harpooned", "Removed")
---@return nil
---@private
local function harpoon_notify(action)
	vim.notify(action .. ": " .. vim.fn.expand("%:t"), vim.log.levels.INFO, { title = "Harpoon" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPEC
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Trigger            │ Details                                      │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ keys               │ <leader>h{a,d,h,1-5}, ]H, [H (10 bindings) │
-- │ dependencies       │ plenary.nvim (async utilities)               │
-- │ branch             │ harpoon2 (v2 API with :list() methods)       │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"ThePrimeagen/harpoon",
	branch = "harpoon2",
	version = false,
	dependencies = { "nvim-lua/plenary.nvim" },

	-- ═══════════════════════════════════════════════════════════════════
	-- LAZY LOADING STRATEGY
	--
	-- Keys-only loading: harpoon has no events, no autocmds, no
	-- background processes. It only needs to load when the user
	-- explicitly interacts with it. Pure on-demand = zero startup cost.
	-- ═══════════════════════════════════════════════════════════════════
	keys = {
		-- ── Add / Remove ─────────────────────────────────────────────
		{
			"<leader>ha",
			function()
				harpoon_list():add()
				harpoon_notify("Harpooned")
			end,
			desc = icons.ui.BookMark .. " Harpoon add file",
		},
		{
			"<leader>hd",
			function()
				harpoon_list():remove()
				harpoon_notify("Removed")
			end,
			desc = icons.ui.BoldClose .. " Harpoon remove file",
		},

		-- ── Quick menu ───────────────────────────────────────────────
		{
			"<leader>hh",
			function()
				local harpoon = require("harpoon")
				harpoon.ui:toggle_quick_menu(harpoon:list())
			end,
			desc = icons.ui.List .. " Harpoon menu",
		},

		-- ── Direct jump (1–5) ────────────────────────────────────────
		-- Numbered marks for instant access to the most-used files.
		-- Indices correspond to the order in the quick menu.
		{
			"<leader>h1",
			function()
				harpoon_list():select(1)
			end,
			desc = icons.ui.Target .. " Harpoon file 1",
		},
		{
			"<leader>h2",
			function()
				harpoon_list():select(2)
			end,
			desc = icons.ui.Target .. " Harpoon file 2",
		},
		{
			"<leader>h3",
			function()
				harpoon_list():select(3)
			end,
			desc = icons.ui.Target .. " Harpoon file 3",
		},
		{
			"<leader>h4",
			function()
				harpoon_list():select(4)
			end,
			desc = icons.ui.Target .. " Harpoon file 4",
		},
		{
			"<leader>h5",
			function()
				harpoon_list():select(5)
			end,
			desc = icons.ui.Target .. " Harpoon file 5",
		},

		-- ── Circular navigation ──────────────────────────────────────
		-- Uses UPPERCASE ]H/[H to avoid conflict with gitsigns ]h/[h
		-- (hunk navigation). Follows the ] / [ convention:
		--   ]h/[h  → git hunks     (gitsigns, buffer-local)
		--   ]H/[H  → harpoon marks (global, persistent)
		--   ]d/[d  → diagnostics
		--   ]b/[b  → buffers
		--   ]t/[t  → TODOs
		{
			"]H",
			function()
				harpoon_list():next()
			end,
			desc = icons.ui.BookMark .. " Next harpoon mark",
		},
		{
			"[H",
			function()
				harpoon_list():prev()
			end,
			desc = icons.ui.BookMark .. " Prev harpoon mark",
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	--
	-- Settings control persistence and project scoping.
	-- ├─ save_on_toggle     Persist on menu close (crash-safe)
	-- ├─ sync_on_ui_close   Apply reordering/deletions immediately
	-- └─ key                Per-project function (git root / cwd)
	-- ═══════════════════════════════════════════════════════════════════
	opts = {
		settings = {
			-- ── Persistence ─────────────────────────────────────────
			-- save_on_toggle: persist list when closing the quick menu.
			-- Without this, marks added then menu-closed would be lost
			-- if nvim crashes before the next explicit save.
			save_on_toggle = true,

			-- sync_on_ui_close: sync the list state when the UI closes.
			-- Ensures reordering / deletions in the quick menu are
			-- immediately persisted to disk.
			sync_on_ui_close = true,

			-- ── Project key ─────────────────────────────────────────
			-- Each project gets its own independent harpoon list.
			-- The key is determined by searching upward for common
			-- project root markers. Falls back to CWD if none found.
			---@return string key Unique project identifier
			key = function()
				local root = vim.fs.root(0, {
					".git",
					"Makefile",
					"package.json",
					"Cargo.toml",
					"go.mod",
				})
				return root or vim.uv.cwd() or ""
			end,
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- CONFIG
	--
	-- Post-setup hook: customizes the quick menu floating window to
	-- match the rest of the configuration:
	-- • Rounded borders from core/icons.lua
	-- • Centered title with harpoon icon
	-- • Optimal width/height based on terminal dimensions
	-- • Line numbers ON, cursorline ON, signcolumn OFF
	-- ═══════════════════════════════════════════════════════════════════
	config = function(_, opts)
		local harpoon = require("harpoon")
		harpoon:setup(opts)

		-- ── Quick menu UI customization ──────────────────────────────
		local borders = icons.borders

		harpoon:extend({
			--- Customize the harpoon quick menu window on creation.
			---
			--- Applies rounded borders, centered title, optimal sizing,
			--- and clean display options (line numbers, cursorline).
			---
			---@param cx { win_id: integer, bufnr: integer } UI creation context
			UI_CREATE = function(cx)
				local win = cx.win_id
				local buf = cx.bufnr

				if not win or not vim.api.nvim_win_is_valid(win) then return end

				-- ── Borders and title ────────────────────────────
				vim.api.nvim_win_set_config(win, {
					border = borders.Rounded,
					title = { { " 󰃀 Harpoon ", "FloatTitle" } },
					title_pos = "center",
				})

				-- ── Optimal sizing ───────────────────────────────
				---@type integer
				local width = math.min(80, math.floor(vim.o.columns * 0.6))
				---@type integer
				local height = math.min(10, math.floor(vim.o.lines * 0.3))
				vim.api.nvim_win_set_config(win, {
					width = width,
					height = height,
				})

				-- ── Window display options ───────────────────────
				if buf and vim.api.nvim_buf_is_valid(buf) then
					vim.wo[win].number = true
					vim.wo[win].relativenumber = false
					vim.wo[win].cursorline = true
					vim.wo[win].signcolumn = "no"
				end
			end,
		})
	end,
}
