---@file lua/plugins/editor/neogit.lua
---@description Neogit — Magit-like Git interface for Neovim
---@module "plugins.editor.neogit"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.diffview   Diff viewing integration
---@see plugins.editor.telescope  Branch/commit pickers
---@see plugins.editor.lazygit    Terminal-based Git (complementary)
---@see https://github.com/NeogitOrg/neogit
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/neogit.lua — Magit-like Git interface                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────┐     ║
--- ║  │  neogit                                                         │     ║
--- ║  │                                                                 │     ║
--- ║  │  • Magit-like interactive Git UI                                │     ║
--- ║  │  • Full staging/unstaging, commit, push/pull, rebase, stash     │     ║
--- ║  │  • Integrates with diffview.nvim for diff viewing               │     ║
--- ║  │  • Integrates with telescope.nvim for branch/commit pickers     │     ║
--- ║  │  • Icons from core/icons.lua (single source of truth)           │     ║
--- ║  │                                                                 │     ║
--- ║  │  Complements (does NOT replace):                                │     ║
--- ║  │  ├─ <leader>gg  Lazygit (terminal-based, quick operations)      │     ║
--- ║  │  ├─ <leader>gs  Git status (Snacks)                             │     ║
--- ║  │  ├─ <leader>gd  Diff index (Diffview)                           │     ║
--- ║  │  └─ <leader>gl  Blame line (Snacks)                             │     ║
--- ║  └─────────────────────────────────────────────────────────────────┘     ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • cmd + keys loading (zero startup cost)                                ║
--- ║  • Dependencies not forced (diffview/telescope load independently)       ║
--- ║  • Static opts table (no function wrapper needed)                        ║
--- ║  • No explicit config function (lazy.nvim auto-calls setup)              ║
--- ║  • All buffer-local mappings (zero global keymap pollution)              ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    <leader>gn   Open Neogit status (project root)            (n)         ║
--- ║    <leader>gN   Open Neogit status (file cwd)                (n)         ║
--- ║    <leader>gH   Open Neogit log                              (n)         ║
--- ║    <leader>gZ   Open Neogit stash                            (n)         ║
--- ║                                                                          ║
--- ║  Buffer-local keymaps (inside Neogit buffers only):                      ║
--- ║    q / <Esc>    Close                                                    ║
--- ║    s / S        Stage / Stage unstaged                                   ║
--- ║    u / U        Unstage / Unstage staged                                 ║
--- ║    <C-s>        Stage all                                                ║
--- ║    x            Discard                                                  ║
--- ║    <Tab>        Toggle section                                           ║
--- ║    1–4          Fold depth                                               ║
--- ║    <CR>         Go to file                                               ║
--- ║    <C-v>        Open in vsplit                                           ║
--- ║    <C-x>        Open in hsplit                                           ║
--- ║    <C-t>        Open in tab                                              ║
--- ║    { / }        Prev / next hunk header                                  ║
--- ║    Y            Yank selected                                            ║
--- ║    Popup keys:  ? b c d f l m p P r t v w X Z A B                        ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════
local settings = require("core.settings")
if not settings:is_plugin_enabled("neogit") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════
---@type Icons
local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAP HANDLERS
--
-- Extracted for consistency with other Elite specs.
-- Only the `<leader>gN` handler needs a function; the others use `<Cmd>`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open Neogit scoped to the current file's directory.
--- Useful when working in a monorepo or multi-project workspace.
---@private
local function open_neogit_cwd()
	require("neogit").open({ cwd = vim.fn.expand("%:p:h") })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"NeogitOrg/neogit",
	version = false,

	-- ═══════════════════════════════════════════════════════════════════
	-- DEPENDENCIES
	--
	-- plenary is a hard dependency (required for async operations).
	-- diffview and telescope are soft dependencies — they're already
	-- in the config and loaded separately. Declaring them here would
	-- force them to load whenever neogit loads, adding unnecessary
	-- startup cost.
	-- ═══════════════════════════════════════════════════════════════════
	dependencies = {
		"nvim-lua/plenary.nvim",
	},

	cmd = "Neogit",

	-- stylua: ignore
	keys = {
		{ "<leader>gn", "<Cmd>Neogit<CR>",       desc = icons.git.Git     .. " Neogit" },
		{ "<leader>gN", open_neogit_cwd,          desc = icons.git.Git     .. " Neogit (cwd)" },
		{ "<leader>gH", "<Cmd>Neogit log<CR>",    desc = icons.ui.History  .. " Neogit log" },
		{ "<leader>gZ", "<Cmd>Neogit stash<CR>",  desc = icons.git.Staged  .. " Neogit stash" },
	},

	opts = {
		-- ── Integrations ─────────────────────────────────────────────
		-- diffview and telescope are detected at runtime. If they're
		-- on the runtimepath (which they are in this config), neogit
		-- uses them automatically. No need to force-load via deps.
		integrations = {
			diffview = true,
			telescope = true,
		},

		-- ── Appearance ───────────────────────────────────────────────
		graph_style = "unicode",
		notification_icon = icons.git.Git,

		signs = {
			section = { icons.arrows.ArrowClosed, icons.arrows.ArrowOpen },
			item = { icons.arrows.ArrowClosed, icons.arrows.ArrowOpen },
			hunk = { "", "" },
		},

		-- ── Status buffer ────────────────────────────────────────────
		status = {
			show_head_commit_hash = true,
			recent_commit_count = 20,
			head_padding = 2,
			mode_padding = 2,
			-- stylua: ignore
			mode_text = {
				M    = icons.git.Modified,
				N    = icons.git.Untracked,
				A    = icons.git.Added,
				D    = icons.git.Removed,
				C    = icons.git.Conflict,
				U    = icons.git.Unmerged,
				R    = icons.git.Renamed,
				DD   = icons.git.Conflict,
				AU   = icons.git.Conflict,
				UD   = icons.git.Conflict,
				UA   = icons.git.Conflict,
				DU   = icons.git.Conflict,
				AA   = icons.git.Conflict,
				UU   = icons.git.Conflict,
				["?"] = icons.git.Untracked,
			},
		},

		-- ── Commit editor ────────────────────────────────────────────
		-- Tab: avoids disrupting current window layout.
		-- vsplit: commit message + staged diff side-by-side.
		commit_editor = {
			kind = "tab",
			show_staged_diff = true,
			staged_diff_split_kind = "vsplit",
		},

		-- ── Popup ────────────────────────────────────────────────────
		-- split: anchored to bottom, consistent with terminal splits.
		popup = {
			kind = "split",
		},

		-- ── Buffer-local keymaps ─────────────────────────────────────
		-- All scoped to neogit buffers — zero global keymap pollution.
		-- Follows the same remapping conventions as oil.lua:
		--   <C-v> = vsplit, <C-x> = hsplit (not <C-s>/<C-h>)
		mappings = {
			finder = {
				["<C-c>"] = "Close",
				["<CR>"] = "Select",
				["<Tab>"] = "MultiselectToggleNext",
			},

			-- stylua: ignore
			popup = {
				["?"] = "HelpPopup",
				["A"] = "CherryPickPopup",
				["B"] = "BisectPopup",
				["D"] = "DiffPopup",
				["M"] = "RemotePopup",
				["P"] = "PushPopup",
				["X"] = "ResetPopup",
				["Z"] = "StashPopup",
				["b"] = "BranchPopup",
				["c"] = "CommitPopup",
				["f"] = "FetchPopup",
				["l"] = "LogPopup",
				["m"] = "MergePopup",
				["p"] = "PullPopup",
				["r"] = "RebasePopup",
				["t"] = "TagPopup",
				["v"] = "RevertPopup",
				["w"] = "WorktreePopup",
			},

			status = {
				-- Close
				["q"] = "Close",
				["<Esc>"] = "Close",

				-- Fold depth
				["1"] = "Depth1",
				["2"] = "Depth2",
				["3"] = "Depth3",
				["4"] = "Depth4",

				-- Section toggle
				["<Tab>"] = "Toggle",

				-- Stage / unstage
				["s"] = "Stage",
				["S"] = "StageUnstaged",
				["<C-s>"] = "StageAll",
				["u"] = "Unstage",
				["U"] = "UnstageStaged",

				-- Actions
				["x"] = "Discard",
				["$"] = "CommandHistory",
				["Y"] = "YankSelected",
				["<C-r>"] = "RefreshBuffer",

				-- Open file
				["<CR>"] = "GoToFile",
				["<C-v>"] = "VSplitOpen",
				["<C-x>"] = "SplitOpen",
				["<C-t>"] = "TabOpen",

				-- Hunk navigation
				["{"] = "GoToPreviousHunkHeader",
				["}"] = "GoToNextHunkHeader",
				["[c"] = "OpenOrScrollUp",
				["]c"] = "OpenOrScrollDown",
			},
		},
	},
}
