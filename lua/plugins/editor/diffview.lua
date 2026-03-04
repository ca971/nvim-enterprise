---@file lua/plugins/editor/diffview.lua
---@description Diffview — enterprise-grade git diff viewer, file history & merge tool
---@module "plugins.editor.diffview"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.gitsigns   Inline git hunks (complementary, buffer-level)
---@see plugins.editor.lazygit    Full git TUI (complementary, interactive)
---@see plugins.editor.neo-tree   Git status in file explorer sidebar
---@see plugins.editor.telescope  Git branches/commits pickers
---
---@see https://github.com/sindrets/diffview.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/diffview.lua — Git diff viewer & merge tool              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  diffview.nvim                                                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  • Side-by-side diff for all modified files (diff2_horizontal)   │    ║
--- ║  │  �� File history: git log for any file, directory, or selection  │    ║
--- ║  │  • 3-way merge tool with conflict resolution keymaps             │    ║
--- ║  │  • File panel: stage/unstage/restore with tree-style listing     │    ║
--- ║  │  • Enhanced diff highlighting (beyond built-in diff mode)        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Diff targets:                                                   │    ║
--- ║  │  ├─ Working tree vs index      (DiffviewOpen)                    │    ║
--- ║  │  ├─ HEAD~1 vs HEAD             (DiffviewOpen HEAD~1)             │    ║
--- ║  │  ├─ Branch vs origin/main      (DiffviewOpen origin/main...HEAD) │    ║
--- ║  │  └─ Branch vs origin/master    (DiffviewOpen origin/master...HEAD│    ║
--- ║  │                                                                  │    ║
--- ║  │  File history modes:                                             │    ║
--- ║  │  ├─ Current file               (DiffviewFileHistory %)           │    ║
--- ║  │  ├─ Entire repo                (DiffviewFileHistory)             │    ║
--- ║  │  ├─ Visual selection           ('<,'>DiffviewFileHistory)        │    ║
--- ║  │  └─ Branch range vs main/master (--range=origin/main...HEAD)     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Merge conflict resolution (buffer-local in diff view):          │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  [x / ]x      Navigate conflicts (prev / next)           │    │    ║
--- ║  │  │  <leader>co    Choose OURS                               │    │    ║
--- ║  │  │  <leader>ct    Choose THEIRS                             │    │    ║
--- ║  │  │  <leader>cb    Choose BASE                               │    │    ║
--- ║  │  │  <leader>ca    Choose ALL (merge both sides)             │    │    ║
--- ║  │  │  <leader>cO/T/B/A  Same for ALL conflicts in file        │    │    ║
--- ║  │  │  dx            Delete conflict region entirely           │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Cmd-based lazy loading (never loaded until a :Diffview* command)      ║
--- ║  • Diagnostics disabled in diff buffers (reduces noise)                  ║
--- ║  • wrap/list/colorcolumn disabled in diff buffers (cleaner display)      ║
--- ║  • GC triggered on view_closed to free diff buffer memory                ║
--- ║  • Icons from core/icons.lua (single source of truth)                    ║
--- ║  • `q` mapped in DiffviewFiles/History for quick close                   ║
--- ║                                                                          ║
--- ║  Key allocation (under <leader>g — Git group):                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────────┐ ║
--- ║  │  OCCUPIED KEYS (do NOT use — claimed by other plugins)              │ ║
--- ║  │    Telescope:  gb gc gC gt                                          │ ║
--- ║  │    Lazygit:    gg gG gF                                             │ ║
--- ║  │    Gitsigns:   gh* (sub-group)                                      │ ║
--- ║  │    Neo-tree:   ge                                                   │ ║
--- ║  │    Snacks:     gB gf gl gL gs                                       │ ║
--- ║  ├─────────────────────────────────────────────────────────────────────┤ ║
--- ║  │  DIFFVIEW KEYS                                                      │ ║
--- ║  │    gd  Diff index (working tree)    gD  Diff last commit            │ ║
--- ║  │    gm  Diff vs main                 gM  Diff vs master              │ ║
--- ║  │    gv  File history (current)       gV  File history (repo)         │ ║
--- ║  │    gv  Selection history (visual)                                   │ ║
--- ║  │    go  Branch history vs main       gO  Branch history vs master    │ ║
--- ║  │    gq  Close diff view              gp  Toggle file panel           │ ║
--- ║  │    gR  Refresh diff view                                            │ ║
--- ║  └─────────────────────────────────────────────────────────────────────┘ ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Diffview plugin is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_plugin_enabled("diffview") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

---@type Icons
local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by hooks and autocommands in this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Configure a diff buffer for optimal viewing.
---
--- Disables wrap, list, and colorcolumn to provide a clean,
--- distraction-free diff reading experience. Called by the
--- `diff_buf_read` hook for every buffer opened in a diff view.
---
--- ```lua
--- hooks = {
---   diff_buf_read = function() configure_diff_buffer() end,
--- }
--- ```
---
---@return nil
---@private
local function configure_diff_buffer()
	vim.opt_local.wrap = false
	vim.opt_local.list = false
	vim.opt_local.colorcolumn = ""
end

--- Trigger garbage collection to free diff buffer memory.
---
--- Scheduled via `vim.schedule` to run after the view is fully
--- closed, preventing stale diff data from accumulating in memory
--- across multiple view open/close cycles.
---
--- ```lua
--- hooks = {
---   view_closed = function() schedule_gc() end,
--- }
--- ```
---
---@return nil
---@private
local function schedule_gc()
	vim.schedule(function()
		collectgarbage("collect")
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPEC
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Trigger            │ Details                                      │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ cmd                │ All :Diffview* commands (true lazy load)     │
-- │ keys               │ <leader>g{d,D,m,M,v,V,o,O,q,p,R} mappings    │
-- │ dependencies       │ plenary.nvim (async utilities)               │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"sindrets/diffview.nvim",

	-- ═══════════════════════════════════════════════════════════════════
	-- LAZY LOADING STRATEGY
	--
	-- Cmd-based loading ensures the plugin is never loaded until a
	-- :Diffview* command is triggered (via keymap or cmdline).
	-- This is optimal because diffview is used infrequently and
	-- its initialization cost is non-trivial.
	-- ═══════════════════════════════════════════════════════════════════
	cmd = {
		"DiffviewOpen",
		"DiffviewClose",
		"DiffviewToggleFiles",
		"DiffviewFocusFiles",
		"DiffviewRefresh",
		"DiffviewFileHistory",
		"DiffviewLog",
	},

	dependencies = {
		"nvim-lua/plenary.nvim",
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- GLOBAL KEYMAPS
	--
	-- All keymaps live under <leader>g (Git group, defined in
	-- which-key.lua). Keys are chosen to avoid conflicts with
	-- Telescope, Lazygit, Gitsigns, Neo-tree, and Snacks.
	-- ═══════════════════════════════════════════════════════════════════
	keys = {
		-- ── Diff View ────────────────────────────────────────────────
		{
			"<leader>gd",
			"<cmd>DiffviewOpen<cr>",
			desc = icons.git.Diff .. " Diff index (working tree)",
		},
		{
			"<leader>gD",
			"<cmd>DiffviewOpen HEAD~1<cr>",
			desc = icons.git.Diff .. " Diff last commit",
		},
		{
			"<leader>gm",
			"<cmd>DiffviewOpen origin/main...HEAD<cr>",
			desc = icons.git.Branch .. " Diff vs main",
		},
		{
			"<leader>gM",
			"<cmd>DiffviewOpen origin/master...HEAD<cr>",
			desc = icons.git.Branch .. " Diff vs master",
		},

		-- ── File History ─────────────────────────────────────────────
		{
			"<leader>gv",
			"<cmd>DiffviewFileHistory %<cr>",
			desc = icons.git.Commit .. " File history (current)",
		},
		{
			"<leader>gV",
			"<cmd>DiffviewFileHistory<cr>",
			desc = icons.git.Commit .. " File history (repo)",
		},
		{
			"<leader>gv",
			"<cmd>'<,'>DiffviewFileHistory<cr>",
			mode = "v",
			desc = icons.git.Commit .. " Selection history",
		},
		{
			"<leader>go",
			"<cmd>DiffviewFileHistory --range=origin/main...HEAD<cr>",
			desc = icons.git.Branch .. " Branch history vs main",
		},
		{
			"<leader>gO",
			"<cmd>DiffviewFileHistory --range=origin/master...HEAD<cr>",
			desc = icons.git.Branch .. " Branch history vs master",
		},

		-- ── Controls ─────────────────────────────────────────────────
		{
			"<leader>gq",
			"<cmd>DiffviewClose<cr>",
			desc = icons.ui.Close .. " Close diff view",
		},
		{
			"<leader>gp",
			"<cmd>DiffviewToggleFiles<cr>",
			desc = icons.ui.Folder .. " Toggle file panel",
		},
		{
			"<leader>gR",
			"<cmd>DiffviewRefresh<cr>",
			desc = icons.ui.Refresh .. " Refresh diff view",
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	--
	-- Returned as a function to defer `require("diffview.actions")`
	-- until the plugin is actually loaded (lazy-safe).
	-- ═══════════════════════════════════════════════════════════════════
	opts = function()
		local actions = require("diffview.actions")

		return {
			-- ── Diff Algorithm ─────────────────────────────────────────
			diff_binaries = false,
			enhanced_diff_hl = true,
			use_icons = true,
			show_help_hints = true,

			git_cmd = { "git" },
			hg_cmd = { "hg" },

			-- ── View Configuration ─────────────────────────────────────
			-- All views use horizontal layout with diagnostics disabled
			-- and winbar info enabled for context awareness.
			view = {
				default = {
					layout = "diff2_horizontal",
					disable_diagnostics = true,
					winbar_info = true,
				},
				merge_tool = {
					layout = "diff3_horizontal",
					disable_diagnostics = true,
					winbar_info = true,
				},
				file_history = {
					layout = "diff2_horizontal",
					disable_diagnostics = true,
					winbar_info = true,
				},
			},

			-- ── File Panel ─────────────────────────────────────────────
			-- Tree-style listing with flattened single-child directories
			-- for compact display. Positioned on the left at 35 columns.
			file_panel = {
				listing_style = "tree",
				tree_options = {
					flatten_dirs = true,
					folder_statuses = "only_folded",
				},
				win_config = {
					position = "left",
					width = 35,
					win_opts = {},
				},
			},

			-- ── File History Panel ─────────────────────────────────────
			-- Single-file history follows renames; multi-file uses
			-- first-parent for cleaner merge commit display.
			file_history_panel = {
				log_options = {
					git = {
						single_file = {
							diff_merges = "combined",
							follow = true,
						},
						multi_file = {
							diff_merges = "first-parent",
						},
					},
				},
				win_config = {
					position = "bottom",
					height = 16,
					win_opts = {},
				},
			},

			-- ── Commit Log Panel ───────────────────────────────────────
			commit_log_panel = {
				win_config = {
					win_opts = {},
				},
			},

			-- ── Icons (from core/icons.lua — single source of truth) ──
			icons = {
				folder_closed = icons.ui.FolderClosed,
				folder_open = icons.ui.FolderOpen,
			},
			signs = {
				fold_closed = "",
				fold_open = "",
				done = icons.ui.Check,
			},

			-- ── Hooks ──────────────────────────────────────────────────
			-- diff_buf_read:  clean display for every diff buffer
			-- view_closed:    free memory after closing the diff view
			hooks = {
				diff_buf_read = function(_)
					configure_diff_buffer()
				end,
				view_closed = function(_)
					schedule_gc()
				end,
			},

			-- ═══════════════════════════════════════════════════════════
			-- PANEL-LOCAL KEYMAPS
			--
			-- These keymaps are buffer-local to Diffview panels only.
			-- They do NOT conflict with global which-key groups.
			--
			-- Sections:
			-- ├─ view              Diff buffer keymaps (conflicts, nav)
			-- ├─ file_panel        File list keymaps (stage, fold, nav)
			-- ├─ file_history_panel  History keymaps (log, hash, nav)
			-- └─ option_panel      Settings panel keymaps
			-- ═══════════════════════════════════════════════════════════
			keymaps = {
				disable_defaults = false,

				-- ── Diff View ───────────────────────────────────────
				view = {
					-- Conflict navigation
					{ "n", "[x", actions.prev_conflict, { desc = "Previous conflict" } },
					{ "n", "]x", actions.next_conflict, { desc = "Next conflict" } },

					-- Conflict resolution
					-- (buffer-local: won't clash with global <leader>c Code group)
					{ "n", "<leader>co", actions.conflict_choose("ours"), { desc = "Choose OURS" } },
					{ "n", "<leader>ct", actions.conflict_choose("theirs"), { desc = "Choose THEIRS" } },
					{ "n", "<leader>cb", actions.conflict_choose("base"), { desc = "Choose BASE" } },
					{ "n", "<leader>ca", actions.conflict_choose("all"), { desc = "Choose ALL" } },
					{ "n", "<leader>cO", actions.conflict_choose_all("ours"), { desc = "Choose OURS (all)" } },
					{ "n", "<leader>cT", actions.conflict_choose_all("theirs"), { desc = "Choose THEIRS (all)" } },
					{ "n", "<leader>cB", actions.conflict_choose_all("base"), { desc = "Choose BASE (all)" } },
					{ "n", "<leader>cA", actions.conflict_choose_all("all"), { desc = "Choose ALL (all)" } },
					{ "n", "dx", actions.conflict_choose("none"), { desc = "Delete conflict region" } },

					-- Focus / Toggle
					{ "n", "<leader>e", actions.focus_files, { desc = "Focus file panel" } },
					{ "n", "<leader>b", actions.toggle_files, { desc = "Toggle file panel" } },

					-- Layout
					{ "n", "g<C-x>", actions.cycle_layout, { desc = "Cycle diff layout" } },

					-- Open file
					{ "n", "gf", actions.goto_file_edit, { desc = "Open file" } },
					{ "n", "<C-w><C-f>", actions.goto_file_split, { desc = "Open file (split)" } },
					{ "n", "<C-w>gf", actions.goto_file_tab, { desc = "Open file (tab)" } },
				},

				-- ── File Panel ──────────────────────────────────────
				file_panel = {
					-- Navigation
					{ "n", "j", actions.next_entry, { desc = "Next entry" } },
					{ "n", "k", actions.prev_entry, { desc = "Previous entry" } },
					{ "n", "<down>", actions.next_entry, { desc = "Next entry" } },
					{ "n", "<up>", actions.prev_entry, { desc = "Previous entry" } },
					{ "n", "<cr>", actions.select_entry, { desc = "Open diff" } },
					{ "n", "o", actions.select_entry, { desc = "Open diff" } },
					{ "n", "l", actions.select_entry, { desc = "Open diff" } },
					{ "n", "<2-LeftMouse>", actions.select_entry, { desc = "Open diff" } },

					-- Staging
					{ "n", "s", actions.toggle_stage_entry, { desc = "Stage / unstage" } },
					{ "n", "S", actions.stage_all, { desc = "Stage all" } },
					{ "n", "U", actions.unstage_all, { desc = "Unstage all" } },
					{ "n", "X", actions.restore_entry, { desc = "Restore entry" } },

					-- Misc
					{ "n", "R", actions.refresh_files, { desc = "Refresh files" } },
					{ "n", "L", actions.open_commit_log, { desc = "Open commit log" } },
					{ "n", "i", actions.listing_style, { desc = "Toggle listing style" } },
					{ "n", "f", actions.toggle_flatten_dirs, { desc = "Toggle flatten dirs" } },

					-- Folding
					{ "n", "zo", actions.open_fold, { desc = "Open fold" } },
					{ "n", "zc", actions.close_fold, { desc = "Close fold" } },
					{ "n", "za", actions.toggle_fold, { desc = "Toggle fold" } },
					{ "n", "zR", actions.open_all_folds, { desc = "Open all folds" } },
					{ "n", "zM", actions.close_all_folds, { desc = "Close all folds" } },
					{ "n", "h", actions.close_fold, { desc = "Close fold" } },

					-- Conflict navigation
					{ "n", "[x", actions.prev_conflict, { desc = "Previous conflict" } },
					{ "n", "]x", actions.next_conflict, { desc = "Next conflict" } },

					-- Focus / Toggle
					{ "n", "<leader>e", actions.focus_files, { desc = "Focus file panel" } },
					{ "n", "<leader>b", actions.toggle_files, { desc = "Toggle file panel" } },
					{ "n", "g<C-x>", actions.cycle_layout, { desc = "Cycle diff layout" } },

					-- Open file
					{ "n", "gf", actions.goto_file_edit, { desc = "Open file" } },
					{ "n", "<C-w><C-f>", actions.goto_file_split, { desc = "Open file (split)" } },
					{ "n", "<C-w>gf", actions.goto_file_tab, { desc = "Open file (tab)" } },

					-- Help
					{ "n", "g?", actions.help("file_panel"), { desc = "Open help" } },
				},

				-- ── File History Panel ───────────────────────────────
				file_history_panel = {
					-- Navigation
					{ "n", "j", actions.next_entry, { desc = "Next entry" } },
					{ "n", "k", actions.prev_entry, { desc = "Previous entry" } },
					{ "n", "<down>", actions.next_entry, { desc = "Next entry" } },
					{ "n", "<up>", actions.prev_entry, { desc = "Previous entry" } },
					{ "n", "<cr>", actions.select_entry, { desc = "Open diff" } },
					{ "n", "o", actions.select_entry, { desc = "Open diff" } },
					{ "n", "l", actions.select_entry, { desc = "Open diff" } },
					{ "n", "<2-LeftMouse>", actions.select_entry, { desc = "Open diff" } },

					-- Log
					{ "n", "L", actions.open_commit_log, { desc = "Open commit log" } },
					{ "n", "g!", actions.options, { desc = "Open option panel" } },
					{ "n", "y", actions.copy_hash, { desc = "Copy commit hash" } },

					-- Folding
					{ "n", "zo", actions.open_fold, { desc = "Open fold" } },
					{ "n", "zc", actions.close_fold, { desc = "Close fold" } },
					{ "n", "za", actions.toggle_fold, { desc = "Toggle fold" } },
					{ "n", "zR", actions.open_all_folds, { desc = "Open all folds" } },
					{ "n", "zM", actions.close_all_folds, { desc = "Close all folds" } },
					{ "n", "h", actions.close_fold, { desc = "Close fold" } },

					-- Focus / Toggle
					{ "n", "<leader>e", actions.focus_files, { desc = "Focus file panel" } },
					{ "n", "<leader>b", actions.toggle_files, { desc = "Toggle file panel" } },
					{ "n", "g<C-x>", actions.cycle_layout, { desc = "Cycle diff layout" } },

					-- Open file
					{ "n", "gf", actions.goto_file_edit, { desc = "Open file" } },
					{ "n", "<C-w><C-f>", actions.goto_file_split, { desc = "Open file (split)" } },
					{ "n", "<C-w>gf", actions.goto_file_tab, { desc = "Open file (tab)" } },

					-- Help
					{ "n", "g?", actions.help("file_history_panel"), { desc = "Open help" } },
				},

				-- ── Option Panel ────────────────────────────────────
				option_panel = {
					{ "n", "<tab>", actions.select_entry, { desc = "Change option" } },
					{ "n", "q", actions.close, { desc = "Close panel" } },
					{ "n", "g?", actions.help("option_panel"), { desc = "Open help" } },
				},
			},
		}
	end,

	-- ═══════════════════════════════════════════════════════════════════
	-- CONFIG
	--
	-- Post-setup hook: registers an autocommand to map `q` for quick
	-- close in DiffviewFiles and DiffviewFileHistory buffers.
	-- This provides a consistent "press q to quit" experience across
	-- all Diffview panel types.
	-- ═══════════════════════════════════════════════════════════════════
	config = function(_, opts)
		require("diffview").setup(opts)

		-- ── Quick-close with `q` from any Diffview panel ─────────
		vim.api.nvim_create_autocmd("FileType", {
			pattern = { "DiffviewFiles", "DiffviewFileHistory" },
			desc = "Map q to close Diffview in panel buffers",
			callback = function(event)
				vim.keymap.set("n", "q", "<cmd>DiffviewClose<cr>", {
					buffer = event.buf,
					desc = "Close Diffview",
					silent = true,
				})
			end,
		})
	end,
}
