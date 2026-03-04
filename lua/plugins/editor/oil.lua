---@file lua/plugins/editor/oil.lua
---@description Oil.nvim — edit filesystem like a buffer
---@module "plugins.editor.oil"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.neo-tree  Tree-style explorer (complementary)
---@see plugins.editor.telescope Fuzzy file finder (complementary)
---@see https://github.com/stevearc/oil.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/oil.lua — File explorer as a buffer                      ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────┐     ║
--- ║  │  oil.nvim                                                       │     ║
--- ║  │                                                                 │     ║
--- ║  │  • Edit filesystem like a Vim buffer (create/delete/rename)     │     ║
--- ║  │  • Replaces netrw completely (disabled in init)                 │     ║
--- ║  │  • Icons via mini.icons (sole icon provider)                    │     ║
--- ║  │  • LSP-aware file rename (willRenameFiles)                      │     ║
--- ║  │  • Trash support (safe deletes, toggle with g\)                 │     ║
--- ║  │  • Float mode for quick navigation (<leader>eo)                 │     ║
--- ║  │  • Auto-refresh on external filesystem changes                  │     ║
--- ║  └─────────────────────────────────────────────────────────────────┘     ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Lazy-loaded via keys (-) and cmd (Oil)                                ║
--- ║  • Auto-loads only when nvim opens a directory (uv.fs_stat)              ║
--- ║  • netrw fully disabled in init (4 globals)                              ║
--- ║  • Conflicting buffer-local keymaps remapped (C-s, C-h, C-l)             ║
--- ║  • Colorscheme-agnostic highlights (link-based, survive :colorscheme)    ║
--- ║  • Borders from core/icons.lua (single source of truth)                  ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    -            Open parent directory                         (n)        ║
--- ║    <leader>eo   Open oil float                                (n)        ║
--- ║                                                                          ║
--- ║  Buffer-local keymaps (inside oil buffer):                               ║
--- ║    <CR>         Open file / enter directory                              ║
--- ║    -            Go to parent directory                                   ║
--- ║    _            Open cwd                                                 ║
--- ║    `            :cd to directory                                         ║
--- ║    ~            :tcd to directory                                        ║
--- ║    q            Close oil                                                ║
--- ║    g?           Show keymap help                                         ║
--- ║    g.           Toggle hidden files                                      ║
--- ║    g\           Toggle trash view                                        ║
--- ║    gs           Change sort order                                        ║
--- ║    gp           Preview file                                             ║
--- ║    gx           Open in system app                                       ║
--- ║    gy           Yank absolute path to clipboard                          ║
--- ║    gY           Yank relative path to clipboard                          ║
--- ║    <C-v>        Open in vsplit        (replaces default <C-s>)           ║
--- ║    <C-x>        Open in hsplit        (replaces default <C-h>)           ║
--- ║    <C-r>        Refresh               (replaces default <C-l>)           ║
--- ║    <C-t>        Open in new tab                                          ║
--- ║    <C-p>        Preview                                                  ║
--- ║    <C-c>        Close                                                    ║
--- ║                                                                          ║
--- ║  Disabled defaults (conflict with global keymaps):                       ║
--- ║    <C-s>  → global: Save file       → replaced by <C-v>                  ║
--- ║    <C-h>  → global: Left window     → replaced by <C-x>                  ║
--- ║    <C-l>  → global: Right window    → replaced by <C-r>                  ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════
local settings = require("core.settings")
if not settings:is_plugin_enabled("oil") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════
---@type Icons
local icons = require("core.icons")
local uv = vim.uv or vim.loop

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════════

--- Files that should always be hidden in oil buffers.
--- Uses a set for O(1) lookup.
---@type table<string, true>
---@private
local ALWAYS_HIDDEN = {
	[".."] = true,
	[".git"] = true,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Send a notification with the "Oil" title and icon.
---@param msg string Notification message body
---@param level? integer vim.log.levels.* constant (default: INFO)
---@private
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, {
		title = icons.documents.FileTree .. "  Oil",
	})
end

--- Yank the path of the file under cursor to the system clipboard.
--- Supports absolute and relative formats.
---@param fmt "absolute"|"relative" Path format
---@private
local function yank_path(fmt)
	local oil = require("oil")
	local entry = oil.get_cursor_entry()
	local dir = oil.get_current_dir()
	if not entry or not dir then return end

	local path = dir .. entry.name
	if fmt == "relative" then path = vim.fn.fnamemodify(path, ":~:.") end

	vim.fn.setreg("+", path)
	notify(string.format("%s  Copied: %s", icons.ui.Check, path))
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAP HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Open oil in a floating window.
---@private
local function open_float()
	require("oil").open_float()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"stevearc/oil.nvim",
	version = false,

	dependencies = { "echasnovski/mini.icons" },

	cmd = "Oil",

	-- stylua: ignore
	keys = {
		{ "-",           "<Cmd>Oil<CR>", desc = icons.ui.FolderOpen    .. " Open parent directory" },
		{ "<leader>eo",  open_float,     desc = icons.documents.FileTree .. " Oil (float)" },
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- INIT — runs before plugin loads
	--
	-- 1. Disable netrw completely (4 globals)
	-- 2. Detect if nvim opened a directory → auto-load oil
	--
	-- The directory detection uses uv.fs_stat (cheap syscall) and
	-- defers the require("oil") to VimEnter to avoid race conditions
	-- with lazy.nvim's plugin resolution.
	-- ═══════════════════════════════════════════════════════════════════
	init = function()
		vim.g.loaded_netrw = 1
		vim.g.loaded_netrwPlugin = 1
		vim.g.loaded_netrwSettings = 1
		vim.g.loaded_netrwFileHandlers = 1

		if vim.fn.argc(-1) == 1 then
			local arg = tostring(vim.fn.argv(0))
			local stat = uv.fs_stat(arg)
			if stat and stat.type == "directory" then
				vim.api.nvim_create_autocmd("VimEnter", {
					once = true,
					callback = function()
						require("oil")
					end,
				})
			end
		end
	end,

	opts = {
		default_file_explorer = true,
		columns = { "icon" },
		delete_to_trash = true,
		skip_confirm_for_simple_edits = true,
		prompt_save_on_select_new_entry = true,
		watch_for_changes = true,
		constrain_cursor = "name",

		-- ── LSP file rename awareness ────────────────────────────────
		lsp_file_methods = {
			enabled = true,
			timeout_ms = 1000,
			autosave_changes = false,
		},

		-- ── Oil buffer window options ────────────────────────────────
		win_options = {
			signcolumn = "no",
			number = false,
			relativenumber = false,
			wrap = false,
			cursorcolumn = false,
			foldcolumn = "0",
			spell = false,
			list = false,
			conceallevel = 3,
			concealcursor = "nvic",
		},

		-- ── Buffer-local keymaps ─────────────────────────────────────
		-- use_default_keymaps = true (default) merges these with
		-- oil's built-in keymaps. Setting a key to `false` disables
		-- the corresponding default.
		keymaps = {
			-- Disable defaults that conflict with global keymaps
			["<C-s>"] = false, -- conflicts with global Save (<C-s>)
			["<C-h>"] = false, -- conflicts with global Left window (<C-h>)
			["<C-l>"] = false, -- conflicts with global Right window (<C-l>)

			-- Replacements for disabled defaults
			["<C-v>"] = { "actions.select", opts = { vertical = true }, desc = icons.ui.Window .. " Open in vsplit" },
			["<C-x>"] = { "actions.select", opts = { horizontal = true }, desc = icons.ui.Window .. " Open in hsplit" },
			["<C-r>"] = { "actions.refresh", desc = icons.ui.Refresh .. " Refresh" },

			-- Close
			["q"] = { "actions.close", desc = icons.ui.Close .. " Close" },

			-- Preview
			["gp"] = { "actions.preview", desc = icons.ui.Search .. " Preview" },

			-- Yank path variants
			["gy"] = {
				desc = icons.ui.Copy .. " Yank absolute path",
				callback = function()
					yank_path("absolute")
				end,
			},
			["gY"] = {
				desc = icons.ui.Copy .. " Yank relative path",
				callback = function()
					yank_path("relative")
				end,
			},
		},

		-- ── Floating window ──────────────────────────────────────────
		float = {
			padding = 2,
			max_width = 120,
			max_height = 40,
			border = icons.borders.Rounded,
			win_options = { winblend = 0 },
		},

		-- ── Preview window ───────────────────────────────────────────
		preview = {
			max_width = 0.9,
			min_width = { 40, 0.4 },
			border = icons.borders.Rounded,
			win_options = { winblend = 0 },
		},

		-- ── Progress window ──────────────────────────────────────────
		progress = {
			max_width = 0.9,
			min_width = { 40, 0.4 },
			border = icons.borders.Rounded,
			minimized_border = "none",
			win_options = { winblend = 0 },
		},

		-- ── Confirmation dialog ──────────────────────────────────────
		confirmation = {
			border = icons.borders.Rounded,
		},

		-- ── Keymap help window ───────────────────────────────────────
		keymaps_help = {
			border = icons.borders.Rounded,
		},

		-- ── File view options ────────────────────────────────────────
		view_options = {
			show_hidden = false,
			natural_order = true,
			---@param name string File or directory name
			---@return boolean hidden Whether to hide this entry
			is_always_hidden = function(name)
				return ALWAYS_HIDDEN[name] or false
			end,
		},
	},

	---@param _ table Plugin spec (unused)
	---@param opts table Resolved options
	config = function(_, opts)
		require("oil").setup(opts)

		-- ── Colorscheme-agnostic highlights ──────────────────────────
		-- All use `link` — they follow the target dynamically.
		-- No ColorScheme autocmd needed; these survive :colorscheme.
		local hl = vim.api.nvim_set_hl

		-- File operation indicators
		hl(0, "OilCreate", { link = "DiagnosticOk" })
		hl(0, "OilDelete", { link = "DiagnosticError" })
		hl(0, "OilMove", { link = "DiagnosticWarn" })
		hl(0, "OilCopy", { link = "DiagnosticInfo" })
		hl(0, "OilChange", { link = "DiagnosticHint" })
		hl(0, "OilRestore", { link = "DiagnosticOk" })
		hl(0, "OilPurge", { link = "DiagnosticError" })

		-- Trash and links
		hl(0, "OilTrash", { link = "NonText" })
		hl(0, "OilTrashSourcePath", { link = "Comment" })
		hl(0, "OilLink", { link = "Constant" })
		hl(0, "OilLinkTarget", { link = "Comment" })
	end,
}
