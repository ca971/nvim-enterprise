---@file lua/plugins/editor/gitsigns.lua
---@description Gitsigns — inline git signs, hunk actions, blame & diff integration
---@module "plugins.editor.gitsigns"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.diffview   Full diff viewer & merge tool (complementary)
---@see plugins.editor.neogit     Interactive git UI (complementary)
---@see plugins.editor.lazygit    Full git TUI (complementary)
---@see plugins.ui.lualine        Statusline git integration (consumes gitsigns_status_dict)
---
---@see https://github.com/lewis6991/gitsigns.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/gitsigns.lua — Git gutter signs & hunk operations        ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  gitsigns.nvim                                                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  • Gutter signs for added/changed/deleted lines                  │    ║
--- ║  │  • Staged changes shown with separate sign style                 │    ║
--- ║  │  • Hunk navigation with native diff-mode awareness               │    ║
--- ║  │    (]h/[h → gitsigns hunks, ]c/[c in diff mode)                  │    ║
--- ║  │  • Stage/unstage/reset hunks (normal + visual range)             │    ║
--- ║  │  • Inline blame & full blame popup (author, date, summary)       │    ║
--- ║  │  • Diff against index or HEAD~ (opens in split)                  │    ║
--- ║  │  • Toggle deleted lines visibility                               │    ║
--- ║  │  • `ih` text object for selecting hunks (operator + visual)      │    ║
--- ║  │  • Provides `b:gitsigns_status_dict` for lualine integration     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Sign rendering:                                                 │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  ▎  Added        (BoldLineLeft — unstaged & staged)      │    │    ║
--- ║  │  │  ▎  Changed      (BoldLineLeft — unstaged & staged)      │    │    ║
--- ║  │  │  _  Deleted      (bottom of removed region)              │    │    ║
--- ║  │  │  ‾  Top-delete   (top of removed region)                 │    │    ║
--- ║  │  │  ~  Change+del   (changed line with deletions)           │    │    ║
--- ║  │  │  ▏  Untracked    (LineLeft — new files not yet staged)   │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Blame format:                                                   │    ║
--- ║  │    <author>, <relative_time> — <summary>                         │    ║
--- ║  │    (displayed as virtual text at EOL, 300ms delay)               │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Event-based loading (BufReadPost/BufNewFile/BufWritePre)              ║
--- ║  • max_file_length=40000 (skip huge files for performance)               ║
--- ║  • update_debounce=100ms (batches rapid git state changes)               ║
--- ║  • Defensive pcall imports (VSCode / minimal environment safety)         ║
--- ║  • Icons from core/icons.lua with fallback defaults                      ║
--- ║  • watch_gitdir.follow_files for branch-switching awareness              ║
--- ║                                                                          ║
--- ║  Buffer-local keymaps (applied via on_attach):                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────────┐ ║
--- ║  │  KEY             MODE    ACTION              CONFLICT STATUS        │ ║
--- ║  │  ]h / [h         n       Next/prev hunk      ✓ safe (unique)        │ ║
--- ║  │  <leader>ghs     n, v    Stage hunk          ✓ safe (gh* owned)     │ ║
--- ║  │  <leader>ghr     n, v    Reset hunk          ✓ safe                 │ ║
--- ║  │  <leader>ghS     n       Stage buffer        ✓ safe                 │ ║
--- ║  │  <leader>ghu     n       Undo stage hunk     ✓ safe                 │ ║
--- ║  │  <leader>ghR     n       Reset buffer        ✓ safe                 │ ║
--- ║  │  <leader>ghp     n       Preview hunk        ✓ safe                 │ ║
--- ║  │  <leader>ghb     n       Blame line (full)   ✓ safe                 │ ║
--- ║  │  <leader>ghd     n       Diff this           ✓ safe                 │ ║
--- ║  │  <leader>ghD     n       Diff this (HEAD~)   ✓ safe                 │ ║
--- ║  │  <leader>tb      n       Toggle line blame   ✓ safe (t* toggles)    │ ║
--- ║  │  <leader>tD      n       Toggle deleted      ✓ safe                 │ ║
--- ║  │  ih              o, x    Select hunk         ✓ safe (text object)   │ ║
--- ║  └─────────────────────────────────────────────────────────────────────┘ ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Gitsigns plugin is disabled in core/settings.lua.
-- Uses pcall because this plugin uses defensive imports for VSCode
-- compatibility. Returns an empty table so lazy.nvim receives a valid
-- (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok and not settings:is_plugin_enabled("gitsigns") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
--
-- Defensive pcall imports for VSCode compatibility. When running inside
-- vscode-neovim, core modules may not be present. Fallback icon tables
-- ensure signs and keymap descriptions always have proper labels.
-- ═══════════════════════════════════════════════════════════════════════════

local icons_ok, icons = pcall(require, "core.icons")

if not icons_ok or not icons then
	---@type table Fallback icon definitions for VSCode / minimal environments
	icons = {
		ui = {
			BoldLineLeft = "▎",
			LineLeft = "▏",
		},
		git = {
			Added = "",
			Modified = "",
			Removed = "",
			Branch = "",
			Diff = "",
		},
		diagnostics = {},
	}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by signs, keymaps, and configuration.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Safely retrieve an icon from a table with a fallback default.
---
--- Used throughout this module to handle environments where
--- `core.icons` may not be fully loaded (VSCode, minimal configs).
---
--- ```lua
--- safe_icon(icons.ui, "BoldLineLeft", "▎")   -- → "▎"
--- safe_icon(nil, "Search", "⚡")               -- → "⚡"
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

---@type table Git icon subtable (may be fallback)
local gi = icons.git or {}

-- ═══════════════════════════════════════════════════════════════════════════
-- SIGN CHARACTERS
--
-- Sign characters used in the gutter column. Extracted here so they can
-- be reused across both `signs` (unstaged) and `signs_staged` tables
-- without duplication.
-- ═══════════════════════════════════════════════════════════════════════════

---@type string Gutter sign for added / changed lines
local sign_bold = safe_icon(ui, "BoldLineLeft", "▎")

---@type string Gutter sign for untracked files
local sign_untrack = safe_icon(ui, "LineLeft", "▏")

-- ═══════════════════════════════════════════════════════════════════════════
-- ON_ATTACH CALLBACK
--
-- Buffer-local keymaps applied when gitsigns attaches to a buffer.
-- Extracted as a named function for readability and documentation.
--
-- All keymaps are under the `<leader>gh` sub-group (Git → Hunks),
-- which is exclusively owned by gitsigns — no conflicts with other
-- plugins. Toggle keymaps use `<leader>t` (Toggle group).
--
-- Navigation keymaps (]h / [h) are diff-mode aware: they fall back
-- to native ]c / [c when vim diff mode is active.
-- ═══════════════════════════════════════════════════════════════════════════

--- Apply buffer-local gitsigns keymaps.
---
--- Called by gitsigns for each buffer where git information is available.
--- Sets up:
--- - Hunk navigation (]h / [h) with diff-mode fallback
--- - Stage / reset operations (normal + visual range)
--- - Preview, blame, and diff commands
--- - Toggle keymaps for inline blame and deleted lines
--- - `ih` text object for hunk selection
---
--- Uses `package.loaded.gitsigns` to get the module reference without
--- triggering a new `require()` (the module is already loaded by this
--- point since `on_attach` is called by the plugin itself).
---
---@param bufnr integer Buffer number to attach keymaps to
---@return nil
---@private
local function on_attach(bufnr)
	local ok, gs = pcall(function()
		return package.loaded.gitsigns
	end)
	if not ok or not gs then return end

	--- Set a buffer-local keymap with the given buffer number.
	---@param mode string|string[] Vim mode(s)
	---@param lhs string Left-hand side (key sequence)
	---@param rhs string|function Right-hand side (action)
	---@param opts? table Additional keymap options
	local function map(mode, lhs, rhs, opts)
		opts = opts or {}
		opts.buffer = bufnr
		vim.keymap.set(mode, lhs, rhs, opts)
	end

	-- ── Navigation ──────────────────────────────────────────────────
	-- Diff-aware: in native diff mode, use ]c/[c for diff hunks;
	-- otherwise use gitsigns next_hunk/prev_hunk.
	map("n", "]h", function()
		if vim.wo.diff then return "]c" end
		vim.schedule(function() gs.next_hunk() end)
		return "<Ignore>"
	end, {
		expr = true,
		desc = safe_icon(gi, "Modified", "") .. " Next hunk",
	})

	map("n", "[h", function()
		if vim.wo.diff then return "[c" end
		vim.schedule(function() gs.prev_hunk() end)
		return "<Ignore>"
	end, {
		expr = true,
		desc = safe_icon(gi, "Modified", "") .. " Prev hunk",
	})

	-- ── Stage / Reset ───────────────────────────────────────────────
	-- Normal mode: operate on the hunk under cursor.
	map("n", "<leader>ghs", gs.stage_hunk, {
		desc = safe_icon(gi, "Added", "") .. " Stage hunk",
	})
	map("n", "<leader>ghr", gs.reset_hunk, {
		desc = safe_icon(gi, "Removed", "") .. " Reset hunk",
	})

	-- Visual mode: operate on the selected line range.
	map("v", "<leader>ghs", function()
		gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
	end, {
		desc = safe_icon(gi, "Added", "") .. " Stage hunk (visual)",
	})
	map("v", "<leader>ghr", function()
		gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
	end, {
		desc = safe_icon(gi, "Removed", "") .. " Reset hunk (visual)",
	})

	-- ── Buffer-level operations ─────────────────────────────────────
	map("n", "<leader>ghS", gs.stage_buffer, {
		desc = safe_icon(gi, "Added", "") .. " Stage buffer",
	})
	map("n", "<leader>ghu", gs.undo_stage_hunk, {
		desc = safe_icon(gi, "Modified", "") .. " Undo stage hunk",
	})
	map("n", "<leader>ghR", gs.reset_buffer, {
		desc = safe_icon(gi, "Removed", "") .. " Reset buffer",
	})

	-- ── Preview / Blame / Diff ──────────────────────────────────────
	map("n", "<leader>ghp", gs.preview_hunk, {
		desc = safe_icon(gi, "Diff", "") .. " Preview hunk",
	})
	map("n", "<leader>ghb", function()
		gs.blame_line({ full = true })
	end, {
		desc = safe_icon(gi, "Branch", "") .. " Blame line (full)",
	})
	map("n", "<leader>ghd", gs.diffthis, {
		desc = safe_icon(gi, "Diff", "") .. " Diff this",
	})
	map("n", "<leader>ghD", function()
		gs.diffthis("~")
	end, {
		desc = safe_icon(gi, "Diff", "") .. " Diff this (HEAD~)",
	})

	-- ── Toggles ─────────────────────────────────────────────────────
	map("n", "<leader>tb", gs.toggle_current_line_blame, {
		desc = safe_icon(gi, "Branch", "") .. " Toggle line blame",
	})
	map("n", "<leader>tD", gs.toggle_deleted, {
		desc = safe_icon(gi, "Removed", "") .. " Toggle deleted",
	})

	-- ── Text object ─────────────────────────────────────────────────
	-- `ih` selects the current hunk in operator-pending and visual mode.
	-- Works with operators: `dih` (delete hunk), `yih` (yank hunk), etc.
	map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", {
		desc = safe_icon(gi, "Diff", "") .. " Select hunk",
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPEC
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Trigger            │ Details                                      │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ event              │ BufReadPost, BufNewFile, BufWritePre         │
-- │                    │ (loads when any file buffer is opened)       │
-- │ dependencies       │ none                                         │
-- │ keymaps            │ buffer-local via on_attach (not lazy keys)   │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"lewis6991/gitsigns.nvim",

	-- ═══════════════════════════════════════════════════════════════════
	-- LAZY LOADING STRATEGY
	--
	-- Event-based loading on buffer events ensures gitsigns is ready
	-- as soon as any file is opened. Cannot use cmd/keys because
	-- gitsigns needs to render signs immediately on buffer load.
	-- ═══════════════════════════════════════════════════════════════════
	event = { "BufReadPost", "BufNewFile", "BufWritePre" },

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	--
	-- Organized into logical sections:
	-- ├─ Signs (unstaged)     Gutter characters for working tree changes
	-- ├─ Signs (staged)       Gutter characters for index changes
	-- ├─ Sign column          Display behavior
	-- ├─ Watch                Git directory monitoring
	-- ├─ Attach               Auto-attach behavior
	-- ├─ Blame                Inline blame configuration
	-- ├─ Preview              Floating preview window
	-- ├─ Performance          File size limits and debouncing
	-- └─ on_attach            Buffer-local keymaps
	-- ═══════════════════════════════════════════════════════════════════
	opts = {
		-- ── Signs (unstaged) ────────────────────────────────────────
		-- Working tree changes shown in the sign column.
		-- Bold left bar for adds/changes, thin bar for untracked.
		signs = {
			add = { text = sign_bold },
			change = { text = sign_bold },
			delete = { text = "_" },
			topdelete = { text = "‾" },
			changedelete = { text = "~" },
			untracked = { text = sign_untrack },
		},

		-- ── Signs (staged) ──────────────────────────────────────────
		-- Index (staged) changes shown with the same sign style.
		-- Gitsigns uses different highlight groups to distinguish
		-- staged vs unstaged visually.
		signs_staged = {
			add = { text = sign_bold },
			change = { text = sign_bold },
			delete = { text = "_" },
			topdelete = { text = "‾" },
			changedelete = { text = "~" },
		},

		-- ── Sign column behavior ────────────────────────────────────
		-- signcolumn=true:  always reserve the sign column
		-- numhl=false:      don't highlight line numbers
		-- linehl=false:     don't highlight entire lines
		-- word_diff=false:  don't show inline word-level diffs
		signcolumn = true,
		numhl = false,
		linehl = false,
		word_diff = false,

		-- ── Watch .git for changes ──────────────────────────────────
		-- follow_files=true: update signs when files move across
		-- branches (e.g. git checkout).
		watch_gitdir = {
			follow_files = true,
		},

		-- ── Auto attach ─────────────────────────────────────────────
		-- auto_attach=true:        attach to every git-tracked buffer
		-- attach_to_untracked=true: also show signs for new files
		auto_attach = true,
		attach_to_untracked = true,

		-- ── Blame ───────────────────────────────────────────────────
		-- Inline blame is OFF by default (toggled with <leader>tb).
		-- When enabled: shows author, relative time, and commit
		-- summary as virtual text at EOL with 300ms delay.
		-- ignore_whitespace: prevents blame flicker on indent changes.
		current_line_blame = false,
		current_line_blame_opts = {
			virt_text = true,
			virt_text_pos = "eol",
			delay = 300,
			ignore_whitespace = true,
		},
		current_line_blame_formatter = "  <author>, <author_time:%R> — <summary>",

		-- ── Preview ─────────────────────────────────────────────────
		-- Floating window for hunk preview (<leader>ghp).
		-- Positioned relative to cursor for contextual awareness.
		preview_config = {
			border = "rounded",
			style = "minimal",
			relative = "cursor",
			row = 0,
			col = 1,
		},

		-- ── Performance ─────────────────────────────────────────────
		-- max_file_length: skip files larger than 40K lines (perf).
		-- update_debounce: batch rapid changes (100ms window).
		max_file_length = 40000,
		update_debounce = 100,

		-- ── Buffer-local keymaps ────────────────────────────────────
		on_attach = on_attach,
	},
}
