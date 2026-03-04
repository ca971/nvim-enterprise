---@file lua/plugins/editor/persisted.lua
---@description Persisted — enterprise-grade session management with git branch awareness
---@module "plugins.editor.persisted"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.telescope Telescope persisted extension for session browsing
---@see plugins.editor.harpoon Per-file marks (complementary, different scope)
---
---@see https://github.com/olimorris/persisted.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/persisted.lua — Session management (git-aware)           ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  persisted.nvim                                                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  • Auto-save session on exit (per-directory + per-branch)        │    ║
--- ║  │  • Auto-restore session on startup (if no file args)             │    ║
--- ║  │  • Git branch awareness: each branch has its own session         │    ║
--- ║  │    main → session_main, feat/auth → session_feat-auth            │    ║
--- ║  │  • Telescope picker for session selection                        │    ║
--- ║  │  • Pre/post hooks: closes special buffers before save            │    ║
--- ║  │    (neo-tree, aerial, DAP UI, toggleterm, oil, trouble, etc.)    │    ║
--- ║  │  • Custom events: PersistedSave*, PersistedLoad*,                │    ║
--- ║  │    PersistedDelete*, PersistedToggle* for extensions             │    ║
--- ║  │  • Session toggle: pause/resume auto-saving                      │    ║
--- ║  │  • Manual save with vim.notify feedback                          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Complements:                                                    │    ║
--- ║  │  ├─ <leader>qq  Quit All (core keymap)                           │    ║
--- ║  │  ├─ harpoon     Per-file marks (different scope)                 │    ║
--- ║  │  ├─ telescope   Used as picker backend for session selection     │    ║
--- ║  │  └─ project.nvim Project detection (separate, complementary)     │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • VeryLazy loading (session restored before user interacts)             ║
--- ║  • Telescope extension loaded lazily via :Telescope persisted            ║
--- ║  • Special buffers closed before save (prevents stale state)             ║
--- ║  • Allowed dirs restrict session creation to real projects               ║
--- ║  • Icons from core/icons.lua (single source of truth)                    ║
--- ║  • Borders from core/icons.lua (single source of truth)                  ║
--- ║  • Git branch detection via vim.fn.system (no external deps)             ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    <leader>qs   Load session for current dir (+ branch)      (n)         ║
--- ║    <leader>ql   Load last session (any dir)                  (n)         ║
--- ║    <leader>qw   Save current session manually                (n)         ║
--- ║    <leader>qd   Stop auto-saving (current session)           (n)         ║
--- ║    <leader>qt   Toggle auto-save on/off                      (n)         ║
--- ║    <leader>qS   Telescope session picker                     (n)         ║
--- ║    <leader>qD   Delete current session                       (n)         ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Persisted plugin is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════
local settings = require("core.settings")
if not settings:is_plugin_enabled("persisted") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════
---@type Icons
local icons = require("core.icons")
---@type fun(name: string): integer
local augroup = require("core.utils").augroup

-- ═══════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════

--- Get the current git branch name.
--- Used for display in notifications. Actual branch-based session naming
--- is handled internally by persisted.nvim when `use_git_branch = true`.
---@return string branch Current branch name, or `"none"` if not in a git repo
---@private
local function get_git_branch()
	local branch = vim.fn.system("git branch --show-current 2>/dev/null"):gsub("\n", "")
	if vim.v.shell_error ~= 0 or branch == "" then return "none" end
	return branch
end

--- Filetypes that produce non-serializable buffers/windows.
--- These must be closed before saving a session, otherwise
--- restoring the session will show broken or empty panes.
---@type string[]
---@private
local filetypes_to_close = {
	-- File explorers
	"neo-tree",
	"NvimTree",
	"oil",
	-- Code navigation
	"aerial",
	"Outline",
	-- Debug
	"dapui_watches",
	"dapui_stacks",
	"dapui_breakpoints",
	"dapui_scopes",
	"dapui_console",
	"dap-repl",
	-- Terminal
	"toggleterm",
	-- Trouble / diagnostics
	"Trouble",
	"trouble",
	-- Notifications / UI
	"noice",
	"notify",
	"snacks_notif",
	-- Diff
	"DiffviewFiles",
	"DiffviewFileHistory",
	-- Plugin managers
	"lazy",
	"mason",
	-- Misc
	"help",
	"qf",
	"harpoon",
	"TelescopePrompt",
	"DressingInput",
	"edgy",
	"grug-far",
	"presenting",
}

--- Close all windows whose buffer filetype matches `filetypes_to_close`.
--- Returns the number of windows that were successfully closed.
---@return integer closed_count Number of windows closed
---@private
local function close_special_buffers()
	local closed_count = 0
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local ft = vim.bo[buf].filetype
		for _, excluded_ft in ipairs(filetypes_to_close) do
			if ft == excluded_ft then
				local ok = pcall(vim.api.nvim_win_close, win, true)
				if ok then closed_count = closed_count + 1 end
				break
			end
		end
	end
	return closed_count
end

--- Send a notification with the "Persisted" title and icon.
---@param msg string Notification message body
---@param level? integer vim.log.levels.* constant (default: INFO)
---@private
local function notify(msg, level)
	level = level or vim.log.levels.INFO
	vim.notify(msg, level, { title = icons.ui.Settings .. "  Persisted" })
end

--- Build a formatted session context string for notifications.
--- Includes the project directory name and git branch.
---@return string cwd Short project directory name
---@return string branch_display Formatted branch info or "no git"
---@private
local function session_context()
	local cwd = vim.fn.fnamemodify(vim.uv.cwd() or "", ":t")
	local branch = get_git_branch()
	local branch_display = branch ~= "none" and (icons.git.Branch .. " " .. branch) or "no git"
	return cwd, branch_display
end

---@type lazy.PluginSpec
return {
	"olimorris/persisted.nvim",

	-- ═══════════════════════════════════════════════════════════════════
	-- LAZY LOADING STRATEGY
	--
	-- VeryLazy ensures the session system initializes after core
	-- plugins but before the user starts working. The smart
	-- auto_load function handles startup restoration while
	-- avoiding conflicts with the dashboard.
	-- ═══════════════════════════════════════════════════════════════════
	event = "VeryLazy",
	cmd = {
		"SessionToggle",
		"SessionSave",
		"SessionLoad",
		"SessionLoadLast",
		"SessionDelete",
		"SessionStart",
		"SessionStop",
	},

	dependencies = {
		{ "nvim-telescope/telescope.nvim", optional = true },
	},

	keys = {
		-- ── Load session (current dir + branch) ──────────────────────
		{
			"<leader>qs",
			function()
				require("persisted").load()
				local cwd, branch_display = session_context()
				notify(string.format("%s  Session restored [%s] (%s)", icons.ui.Check, cwd, branch_display))
			end,
			desc = icons.ui.BookMark .. " Restore session",
		},

		-- ── Load last session (any directory) ────────────────────────
		{
			"<leader>ql",
			function()
				require("persisted").load({ last = true })
				notify(icons.ui.History .. "  Last session restored")
			end,
			desc = icons.ui.History .. " Restore last session",
		},

		-- ── Save session manually ────────────────────────────────────
		{
			"<leader>qw",
			function()
				local closed = close_special_buffers()
				require("persisted").save()
				local cwd, branch_display = session_context()
				notify(
					string.format(
						"%s  Session saved [%s] (%s)%s",
						icons.ui.Check,
						cwd,
						branch_display,
						closed > 0 and string.format(" — closed %d special buffer(s)", closed) or ""
					)
				)
			end,
			desc = icons.ui.Check .. " Save session",
		},

		-- ── Stop auto-saving ─────────────────────────────────────────
		{
			"<leader>qd",
			function()
				require("persisted").stop()
				notify(icons.ui.BoldClose .. "  Session recording stopped")
			end,
			desc = icons.ui.BoldClose .. " Stop session recording",
		},

		-- ── Toggle auto-save ─────────────────────────────────────────
		{
			"<leader>qt",
			function()
				require("persisted").toggle()
				local is_active = require("persisted").session_is_active and require("persisted").session_is_active() or false
				notify(
					is_active and (icons.ui.Check .. "  Auto-save enabled") or (icons.ui.BoldClose .. "  Auto-save disabled")
				)
			end,
			desc = icons.ui.Refresh .. " Toggle auto-save",
		},

		-- ── Telescope session picker ─────────────────────────────────
		{
			"<leader>qS",
			function()
				local ok = pcall(require("telescope").load_extension, "persisted")
				if ok then
					vim.cmd("Telescope persisted")
				else
					local sessions = require("persisted").list()
					if not sessions or #sessions == 0 then
						notify(icons.ui.BoldClose .. "  No sessions found", vim.log.levels.WARN)
						return
					end
					vim.ui.select(sessions, {
						prompt = icons.ui.Settings .. "  Select session:",
						---@param session table|string Session entry
						---@return string
						format_item = function(session)
							return session.name or tostring(session)
						end,
					}, function(choice)
						if choice then
							require("persisted").load({ session = choice })
							notify(icons.ui.Check .. "  Session loaded: " .. (choice.name or tostring(choice)))
						end
					end)
				end
			end,
			desc = icons.ui.List .. " Select session",
		},

		-- ── Delete current session ───────────────────────────────────
		{
			"<leader>qD",
			function()
				local cwd, branch_display = session_context()
				vim.ui.select({ "Yes", "No" }, {
					prompt = string.format("%s  Delete session for [%s] (%s)?", icons.ui.BoldClose, cwd, branch_display),
				}, function(choice)
					if choice == "Yes" then
						require("persisted").delete()
						notify(string.format("%s  Session deleted [%s] (%s)", icons.ui.BoldClose, cwd, branch_display))
					end
				end)
			end,
			desc = icons.ui.BoldClose .. " Delete session",
		},
	},

	opts = {
		save_dir = vim.fn.expand(vim.fn.stdpath("data") .. "/sessions/"),

		-- ═══════════════════════════════════════════════════════════════
		-- AUTO BEHAVIOR
		--
		-- auto_save: persist session on VimLeavePre (never lose work).
		-- auto_load: smart function that skips when the dashboard is
		-- active, preventing the visual "flash" caused by restoring
		-- buffers before the dashboard renders.
		-- ═══════════════════════════════════════════════════════════════
		auto_save = true,

		--- Determine whether to auto-load a session on startup.
		--- Returns false when a dashboard is active or file arguments
		--- were passed to nvim, preventing visual flicker and unwanted
		--- session restoration.
		---@return boolean should_load Whether to auto-load a session
		auto_load = function()
			-- If file arguments were passed (e.g., `nvim file.lua`),
			-- do not auto-load a session — the user wants that file.
			if vim.fn.argc() > 0 then return false end

			-- If a dashboard/starter plugin is active, skip auto-load
			-- to prevent the "flash" where buffers appear then disappear.
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(buf) then
					local ft = vim.bo[buf].filetype
					if ft == "snacks_dashboard" or ft == "dashboard" or ft == "alpha" then return false end
				end
			end

			return true
		end,

		on_autoload_no_session = nil,

		-- ═══════════════════════════════════════════════════════════════
		-- GIT BRANCH AWARENESS
		--
		-- Each git branch gets its own session file:
		--   ~/project (main)        → session_main
		--   ~/project (feat/auth)   → session_feat-auth
		--   ~/project (fix/bug-123) → session_fix-bug-123
		-- Switching branches automatically loads the correct session.
		-- ═══════════════════════════════════════════════════════════════
		use_git_branch = true,
		follow_cwd = true,

		--- Determine whether the current session should be saved.
		--- Prevents saving empty sessions (only special buffers open)
		--- or dashboard-only sessions.
		---@return boolean should_save Whether the session should be saved
		should_save = function()
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
					local ft = vim.bo[buf].filetype
					local bt = vim.bo[buf].buftype
					if bt == "" and ft ~= "" and ft ~= "snacks_dashboard" and ft ~= "dashboard" and ft ~= "alpha" then
						return true
					end
				end
			end
			return false
		end,

		---@type string[]
		ignored_filetypes = {
			"neo-tree",
			"NvimTree",
			"oil",
			"aerial",
			"Outline",
			"dapui_watches",
			"dapui_stacks",
			"dapui_breakpoints",
			"dapui_scopes",
			"dapui_console",
			"dap-repl",
			"toggleterm",
			"Trouble",
			"trouble",
			"noice",
			"notify",
			"lazy",
			"mason",
			"harpoon",
			"TelescopePrompt",
			"DressingInput",
			"DiffviewFiles",
			"DiffviewFileHistory",
			"snacks_dashboard",
			"dashboard",
			"alpha",
			"edgy",
			"qf",
			"help",
			"gitcommit",
			"gitrebase",
			"grug-far",
			"presenting",
		},

		allowed_dirs = nil,

		telescope = {
			mappings = {
				copy_session = "<C-b>",
				change_branch = "<C-c>",
				delete_session = "<C-d>",
			},
			icons = {
				branch = icons.git.Branch .. " ",
				dir = icons.ui.FolderOpen .. " ",
				selected = icons.ui.Check .. " ",
			},
		},
	},

	---@param _ table Plugin spec (unused)
	---@param opts table Resolved options
	config = function(_, opts)
		local persisted = require("persisted")
		persisted.setup(opts)

		-- ── Telescope extension ──────────────────────────────────────
		local tel_ok = pcall(require, "telescope")
		if tel_ok then pcall(require("telescope").load_extension, "persisted") end

		-- ── Autocommand hooks ────────────────────────────────────────
		local group = augroup("Persisted")

		vim.api.nvim_create_autocmd("User", {
			group = group,
			pattern = "PersistedSavePre",
			desc = "Close special buffers before session save",
			callback = function()
				close_special_buffers()
			end,
		})

		vim.api.nvim_create_autocmd("User", {
			group = group,
			pattern = "PersistedLoadPost",
			desc = "Notify user after session load",
			callback = function()
				vim.defer_fn(function()
					local cwd, branch_display = session_context()
					notify(string.format("%s  Session loaded [%s] %s", icons.ui.Check, cwd, branch_display))
				end, 200)
			end,
		})

		vim.api.nvim_create_autocmd("User", {
			group = group,
			pattern = "PersistedSavePost",
			desc = "Subtle echo after auto-save (no popup)",
			callback = function()
				vim.schedule(function()
					vim.api.nvim_echo({ { icons.ui.Check .. "  Session saved", "DiagnosticOk" } }, false, {})
				end)
			end,
		})

		vim.api.nvim_create_autocmd("User", {
			group = group,
			pattern = "PersistedDeletePost",
			desc = "Notify user after session deletion",
			callback = function()
				notify(icons.ui.BoldClose .. "  Session deleted", vim.log.levels.WARN)
			end,
		})

		vim.api.nvim_create_autocmd("User", {
			group = group,
			pattern = "PersistedTelescopeLoadPre",
			desc = "Close special buffers before Telescope session picker",
			callback = function()
				close_special_buffers()
			end,
		})

		-- ── Which-key group ──────────────────────────────────────────
		local wk_ok, wk = pcall(require, "which-key")
		if wk_ok then
			wk.add({
				{
					"<leader>q",
					group = icons.ui.Settings .. " Session/Quit",
					icon = { icon = icons.ui.Settings, color = "cyan" },
				},
			})
		end
	end,
}
