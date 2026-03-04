---@file lua/core/autocmds.lua
---@description Autocmds — universal autocommands for editor behavior, UX polish, and performance guards
---@module "core.autocmds"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.utils Provides augroup() helper with NvimEnterprise_ prefix
---@see core.options Options module sets base vim.opt values; autocmds refine per-context
---@see core.bootstrap Bootstrap calls Autocmds.setup() during startup
---@see plugins.ui.dashboard Dashboard-specific autocmds complement clean_dashboard here
---@see plugins.editor.persisted Session autocmds are in persisted.lua (plugin-specific)
---@see langs Language-specific autocmds belong in langs/*.lua (not here)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/autocmds.lua — Universal autocommands                              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Autocmds (module table — M.setup() registers all autocmds)      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Scope rules:                                                    │    ║
--- ║  │  ├─ THIS FILE: universal autocmds (apply to all filetypes)       │    ║
--- ║  │  ├─ plugins/**/*.lua: plugin-specific autocmds                   │    ║
--- ║  │  └─ langs/*.lua: language-specific autocmds                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Autocmd categories (12 groups):                                 │    ║
--- ║  │  ├─ highlight_yank         Briefly highlight yanked text         │    ║
--- ║  │  ├─ resize_splits          Equalize splits on terminal resize    │    ║
--- ║  │  ├─ last_position          Restore cursor on BufReadPost         │    ║
--- ║  │  ├─ close_with_q           Map q to close special buffers        │    ║
--- ║  │  ├─ auto_create_dir        Create parent dirs on BufWritePre     │    ║
--- ║  │  ├─ checktime              Detect external file changes          │    ║
--- ║  │  ├─ wrap_spell             Enable wrap+spell for prose FTs       │    ║
--- ║  │  ├─ json_conceal           Disable conceallevel in JSON files    │    ║
--- ║  │  ├─ relative_number        Toggle relativenumber in insert mode  │    ║
--- ║  │  ├─ large_file             Disable heavy features for >1MB files │    ║
--- ║  │  ├─ spell_prose            Enable spell with en+fr for prose FTs │    ║
--- ║  │  └─ clean_dashboard        Clean UI for dashboard/start screens  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ All augroups use utils.augroup() which prefixes with         │    ║
--- ║  │  │  "NvimEnterprise_" and sets clear=true (idempotent)           │    ║
--- ║  │  ├─ setup() can be called multiple times safely (augroups are    │    ║
--- ║  │  │  cleared on creation, preventing duplicate autocmds)          │    ║
--- ║  │  ├─ close_with_q sets buflisted=false to prevent special         │    ║
--- ║  │  │  buffers from appearing in buffer lists / bufferline          │    ║
--- ║  │  ├─ auto_create_dir skips URL-like paths (scp://, http://)       │    ║
--- ║  │  ├─ last_position excludes VCS filetypes where the mark is       │    ║
--- ║  │  │  meaningless (gitcommit always starts at line 1)              │    ║
--- ║  │  ├─ large_file uses BufReadPre (before content loads) and        │    ║
--- ║  │  │  sets vim.b.large_file flag for other modules to check        │    ║
--- ║  │  ├─ relative_number toggle uses vim.b._relative_number flag      │    ║
--- ║  │  │  to restore only if it was previously enabled                 │    ║
--- ║  │  └─ spell_prose has markdown commented out because markview      │    ║
--- ║  │     and other markdown plugins handle spell separately           │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • All augroups cleared on creation (safe to re-call setup())            ║
--- ║  • large_file check uses pcall(vim.uv.fs_stat) — zero cost if no file    ║
--- ║  • checktime only runs for non-nofile buftypes (skip special buffers)    ║
--- ║  • close_with_q pattern list avoids per-buffer filetype checks           ║
--- ║  • Yank highlight uses vim.hl (0.10+) with fallback to vim.highlight     ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════
-- MODULE DEFINITION
-- ═══════════════════════════════════════════════════════════════════════

---@class AutocmdsModule
local M = {}

local augroup = require("core.utils").augroup

-- ═══════════════════════════════════════════════════════════════════════
-- SETUP
--
-- Registers all universal autocommands. Each autocmd uses a dedicated
-- augroup via utils.augroup() which:
-- 1. Prefixes with "NvimEnterprise_" for namespace isolation
-- 2. Sets clear=true so re-calling setup() is safe (no duplicates)
--
-- Called once during bootstrap. Can be re-called on user hot-swap
-- without side effects.
-- ═══════════════════════════════════════════════════════════════════════

--- Register all universal autocommands.
---
--- Called once during bootstrap via `core/bootstrap.lua`. Safe to
--- re-call (all augroups are cleared before re-registration).
---
--- Each autocommand uses a dedicated augroup for granular control
--- and clear separation of concerns.
function M.setup()
	-- ── Highlight on Yank ────────────────────────────────────────────
	-- Brief visual feedback when text is yanked. Uses vim.hl (0.10+)
	-- with fallback to vim.highlight for older versions.
	vim.api.nvim_create_autocmd("TextYankPost", {
		group = augroup("highlight_yank"),
		desc = "Briefly highlight yanked text",
		callback = function()
			(vim.hl or vim.highlight).on_yank({ higroup = "IncSearch", timeout = 200 })
		end,
	})

	-- ── Resize Splits on Window Resize ───────────────────────────────
	-- When the terminal window is resized (e.g., tiling WM, tmux pane),
	-- equalize all split sizes across all tabs to prevent layout breakage.
	vim.api.nvim_create_autocmd("VimResized", {
		group = augroup("resize_splits"),
		desc = "Equalize splits when the terminal window is resized",
		callback = function()
			local current_tab = vim.fn.tabpagenr()
			vim.cmd("tabdo wincmd =")
			vim.cmd("tabnext " .. current_tab)
		end,
	})

	-- ── Go to Last Cursor Position ───────────────────────────────────
	-- Restore the cursor to its last known position when re-opening a
	-- file. Skips VCS filetypes where the mark is meaningless (e.g.,
	-- gitcommit always starts at line 1).
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = augroup("last_position"),
		desc = "Restore cursor to last known position",
		callback = function(event)
			local exclude = { "gitcommit", "gitrebase", "svn", "hgcommit" }
			if vim.tbl_contains(exclude, vim.bo[event.buf].filetype) then return end
			local mark = vim.api.nvim_buf_get_mark(event.buf, '"')
			local lcount = vim.api.nvim_buf_line_count(event.buf)
			if mark[1] > 0 and mark[1] <= lcount then pcall(vim.api.nvim_win_set_cursor, 0, mark) end
		end,
	})

	-- ── Close Special Buffers with q ─────────────────────────────────
	-- Map `q` to close read-only/informational buffers that don't need
	-- editing. Also sets buflisted=false to prevent them from appearing
	-- in buffer lists and bufferline.
	vim.api.nvim_create_autocmd("FileType", {
		group = augroup("close_with_q"),
		desc = "Close special buffers with <q>",
		pattern = {
			"checkhealth",
			"dbout",
			"gitsigns.blame",
			"help",
			"lspinfo",
			"man",
			"neotest-output",
			"neotest-output-panel",
			"neotest-summary",
			"notify",
			"PlenaryTestPopup",
			"qf",
			"spectre_panel",
			"startuptime",
			"tsplayground",
		},
		callback = function(event)
			vim.bo[event.buf].buflisted = false
			vim.keymap.set("n", "q", "<cmd>close<cr>", {
				buffer = event.buf,
				silent = true,
				desc = "Close buffer",
			})
		end,
	})

	-- ── Auto-create Parent Directories on Save ───────────────────────
	-- When saving a file to a path that doesn't exist yet (e.g.,
	-- `nvim new/dir/file.lua`), create the parent directories
	-- automatically. Skips URL-like paths (scp://, http://).
	vim.api.nvim_create_autocmd("BufWritePre", {
		group = augroup("auto_create_dir"),
		desc = "Create parent directories when saving a file",
		callback = function(event)
			-- Skip URL-like paths (scp://, http://, ftp://, etc.)
			if event.match:match("^%w%w+:[\\/][\\/]") then return end
			local file = vim.uv.fs_realpath(event.match) or event.match
			vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
		end,
	})

	-- ── Check for External File Changes ──────────────────────────────
	-- When returning to Neovim after another program modified a file,
	-- prompt to reload. Skips nofile buffers (special/scratch buffers).
	vim.api.nvim_create_autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
		group = augroup("checktime"),
		desc = "Check if files were modified externally",
		callback = function()
			if vim.o.buftype ~= "nofile" then vim.cmd("checktime") end
		end,
	})

	-- ── Wrap and Spell in Text Filetypes ─────────────────────────────
	-- Enable word wrap and spellcheck for prose filetypes where
	-- hard line breaks are not expected.
	vim.api.nvim_create_autocmd("FileType", {
		group = augroup("wrap_spell"),
		desc = "Enable wrap and spell for text filetypes",
		pattern = { "text", "plaintex", "typst", "gitcommit", "markdown" },
		callback = function()
			vim.opt_local.wrap = true
			vim.opt_local.spell = true
		end,
	})

	-- ── Fix Conceallevel for JSON ────────────────────────────────────
	-- JSON files use conceallevel=0 to show all characters (quotes,
	-- commas, brackets). The global conceallevel=2 set in options.lua
	-- hides these, making JSON hard to read.
	vim.api.nvim_create_autocmd("FileType", {
		group = augroup("json_conceal"),
		desc = "Show all characters in JSON files",
		pattern = { "json", "jsonc", "json5" },
		callback = function()
			vim.opt_local.conceallevel = 0
		end,
	})

	-- ── Auto-toggle Relative Numbers ─────────────────────────────────
	-- Disable relative numbers in insert mode (absolute numbers are
	-- more useful when typing). Restore on leaving insert mode, but
	-- only if relativenumber was previously enabled (respects user
	-- preference for absolute-only mode).
	vim.api.nvim_create_autocmd({ "InsertEnter" }, {
		group = augroup("relative_number"),
		desc = "Disable relative numbers in insert mode",
		callback = function()
			if vim.wo.relativenumber then
				vim.wo.relativenumber = false
				vim.b._relative_number = true
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "InsertLeave" }, {
		group = augroup("relative_number_restore"),
		desc = "Restore relative numbers after leaving insert mode",
		callback = function()
			if vim.b._relative_number then
				vim.wo.relativenumber = true
				vim.b._relative_number = nil
			end
		end,
	})

	-- ── Large File Detection ─────────────────────────────────────────
	-- Files larger than 1MB get heavy features disabled to prevent
	-- editor slowdowns. Uses BufReadPre (before content loads) and
	-- sets vim.b.large_file flag so other modules (treesitter, LSP,
	-- completion) can check it and skip expensive operations.
	vim.api.nvim_create_autocmd("BufReadPre", {
		group = augroup("large_file"),
		desc = "Disable heavy features for large files",
		callback = function(event)
			local max_size = 1024 * 1024 -- 1MB
			local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(event.buf))
			if ok and stats and stats.size > max_size then
				vim.b[event.buf].large_file = true
				vim.opt_local.foldmethod = "manual"
				vim.opt_local.spell = false
				vim.opt_local.swapfile = false
				vim.opt_local.undofile = false
				vim.opt_local.breakindent = false
				vim.opt_local.colorcolumn = ""
				vim.opt_local.statuscolumn = ""
				vim.opt_local.signcolumn = "no"
				vim.cmd("syntax clear")
				vim.opt_local.syntax = ""
			end
		end,
	})

	-- ── Spell Check for Prose Filetypes ──────────────────────────────
	-- Enable spellcheck with English and French dictionaries for
	-- prose-oriented filetypes. Markdown is commented out because
	-- markview and other markdown plugins handle spell separately.
	vim.api.nvim_create_autocmd("FileType", {
		group = augroup("spell_prose"),
		desc = "Enable spell with en+fr for prose filetypes",
		pattern = {
			-- "markdown",     -- handled by markview/markdown plugins
			-- "markdown.mdx", -- handled by markview/markdown plugins
			"text",
			"plaintex",
			"rst",
			"org",
			"norg",
			"gitcommit",
			"mail",
		},
		callback = function()
			vim.opt_local.spell = true
			vim.opt_local.spelllang = { "en", "fr" }
		end,
	})

	-- ── Clean Dashboard UI ───────────────────────────────────────────
	-- Hide line numbers, sign column, and tabline for dashboard/start
	-- screen filetypes to provide a clean, distraction-free appearance.
	-- Complements the dashboard UI toggle system in core/options.lua.
	vim.api.nvim_create_autocmd("FileType", {
		group = augroup("clean_dashboard"),
		desc = "Clean UI for dashboard/start screen filetypes",
		pattern = { "dashboard", "alpha", "starter", "snacks_dashboard" },
		callback = function()
			vim.opt_local.number = false
			vim.opt_local.relativenumber = false
			vim.opt_local.signcolumn = "no"
			vim.opt_local.showtabline = 0
		end,
	})

	vim.filetype.add({
		filename = {
			[".env"] = "sh",
			[".env.local"] = "sh",
			[".env.development"] = "sh",
			[".env.production"] = "sh",
			[".env.staging"] = "sh",
			[".env.test"] = "sh",
			[".env.example"] = "sh",
		},
		pattern = {
			-- Catch all .env.* (fallback for no listed variants)
			["%.env%.[%w_.-]+"] = "sh",
		},
	})
end

return M
