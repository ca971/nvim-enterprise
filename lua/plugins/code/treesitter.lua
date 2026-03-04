---@file lua/plugins/code/treesitter.lua
---@description Treesitter — AST-based syntax highlighting, textobjects, sticky context and code navigation
---@module "plugins.code.treesitter"
---@author ca971
---@license MIT
---@version 1.4.0
---@since 2026-01
---
---@see core.platform  Compiler detection gates parser auto-install
---@see core.icons     UI icons referenced for borders and context separator
---@see langs          Language modules that contribute parsers via opts merge
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/code/treesitter.lua — Treesitter integration                    ║
--- ║                                                                          ║
--- ║  Hot-load architecture:                                                  ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │                                                                  │    ║
--- ║  │  This file provides BASE parsers + full module configuration.    │    ║
--- ║  │  Language-specific parsers are contributed by langs/*.lua files  │    ║
--- ║  │  via lazy.nvim opts merging — NOT hardcoded here.                │    ║
--- ║  │                                                                  │    ║
--- ║  │  Dual API support:                                               │    ║
--- ║  │  ├─ Old: require("nvim-treesitter.configs").setup(opts)          │    ║
--- ║  │  └─ New: vim.treesitter.start() + per-feature autocmds           │    ║
--- ║  │                                                                  │    ║
--- ║  │  ┌────────────────────┐   opts merge    ┌──────────────────┐     │    ║
--- ║  │  │  treesitter.lua    │ ◄──────────────►│  langs/python.lua│     │    ║
--- ║  │  │  BASE_PARSERS:     │                 │  ensure_installed│     │    ║
--- ║  │  │  • lua, vim, md…   │                 │  • python, rst…  │     │    ║
--- ║  │  └────────┬───────────┘                 └──────────────────┘     │    ║
--- ║  │           │              opts merge   ┌──────────────────┐       │    ║
--- ║  │           │ ◄────────────────────────►│  langs/rust.lua  │       │    ║
--- ║  │           │                           │  ensure_installed│       │    ║
--- ║  │           │                           │  • rust, toml…   │       │    ║
--- ║  │           │                           └──────────────────┘       │    ║
--- ║  │           ▼                                                      │    ║
--- ║  │  ┌────────────────────────────────────────────────────────┐      │    ║
--- ║  │  │  config(_, merged_opts)                                │      │    ║
--- ║  │  │  ├─ Deduplicate ensure_installed                       │      │    ║
--- ║  │  │  ├─ Detect API version (old vs new)                    │      │    ║
--- ║  │  │  ├─ Setup treesitter + textobjects                     │      │    ║
--- ║  │  │  └─ Register repeatable movements (; / ,)              │      │    ║
--- ║  │  └────────────────────────────────────────────────────────┘      │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Textobject keymap reference (conflict-free):                            ║
--- ║  ┌───────────┬───────────┬────────────────────────────────────────┐      ║
--- ║  │ Key       │ Mode      │ Action                                 │      ║
--- ║  ├───────────┼───────────┼────────────────────────────────────────┤      ║
--- ║  │ af / if   │ v, o      │ Around / inside function               │      ║
--- ║  │ ac / ic   │ v, o      │ Around / inside class                  │      ║
--- ║  │ aa / ia   │ v, o      │ Around / inside argument               │      ║
--- ║  │ ab / ib   │ v, o      │ Around / inside block                  │      ║
--- ║  │ aL / iL   │ v, o      │ Around / inside loop                   │      ║
--- ║  │ ao / io   │ v, o      │ Around / inside conditional            │      ║
--- ║  │ a= / i=   │ v, o      │ Around / inside assignment             │      ║
--- ║  │ l= / r=   │ v, o      │ Assignment LHS / RHS                   │      ║
--- ║  │ aR / iR   │ v, o      │ Around / inside return                 │      ║
--- ║  │ aF / iF   │ v, o      │ Around / inside function call          │      ║
--- ║  │ a/ / i/   │ v, o      │ Around / inside comment                │      ║
--- ║  ├───────────┼───────────┼────────────────────────────────────────┤      ║
--- ║  │ ]f / [f   │ n, x, o   │ Next / prev function start             │      ║
--- ║  │ ]F / [F   │ n, x, o   │ Next / prev function end               │      ║
--- ║  │ ]c / [c   │ n, x, o   │ Next / prev class start                │      ║
--- ║  │ ]C / [C   │ n, x, o   │ Next / prev class end                  │      ║
--- ║  │ ]m / [m   │ n, x, o   │ Next / prev argument (m = member)      │      ║
--- ║  │ ]o / [o   │ n, x, o   │ Next / prev conditional                │      ║
--- ║  │ ]r / [r   │ n, x, o   │ Next / prev return                     │      ║
--- ║  ├───────────┼───────────┼────────────────────────────────────────┤      ║
--- ║  │ ;         │ n, x, o   │ Repeat last TS move (next)             │      ║
--- ║  │ ,         │ n, x, o   │ Repeat last TS move (prev)             │      ║
--- ║  ├───────────┼───────────┼────────────────────────────────────────┤      ║
--- ║  │ <C-space> │ n → v     │ Init / expand selection by node        │      ║
--- ║  │ <BS>      │ v         │ Shrink selection by node               │      ║
--- ║  ├───────────┼───────────┼────────────────────────────────────────┤      ║
--- ║  │<leader>Sa │ n         │ Swap argument → next                   │      ║
--- ║  │<leader>SA │ n         │ Swap argument ← prev                   │      ║
--- ║  │<leader>Sf │ n         │ Swap function → next                   │      ║
--- ║  │<leader>SF │ n         │ Swap function ← prev                   │      ║
--- ║  ├───────────┼───────────┼────────────────────────────────────────┤      ║
--- ║  │<leader>cpf│ n         │ Peek function definition               │      ║
--- ║  │<leader>cpc│ n         │ Peek class definition                  │      ║
--- ║  ├───────────┼───────────┼────────────────────────────────────────┤      ║
--- ║  │<leader>ut │ n         │ Toggle treesitter context              │      ║
--- ║  │ [x        │ n         │ Jump to enclosing context              │      ║
--- ║  └───────────┴───────────┴────────────────────────────────────────┘      ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local platform = require("core.platform")
local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════
-- CONFIGURATION CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════

---@type table<string, number>
local PERF = {
	max_filesize = 100 * 1024,
	context_max_lines = 3,
	context_min_window = 20,
}

---@type boolean
local has_compiler = platform.runtimes.gcc
	or platform.runtimes.gpp
	or platform.runtimes.cpp
	or platform.runtimes.zig
	or platform:has_executable("cc")
	or platform:has_executable("clang")

-- ═══════════════════════════════════════════════════════════════════════
-- BASE PARSER REGISTRY
-- ═══════════════════════════════════════════════════════════════════════

---@type string[]
local BASE_PARSERS = {
	"lua",
	"luadoc",
	"luap",
	"vim",
	"vimdoc",
	"query",
	"regex",
	"markdown",
	"markdown_inline",
	"git_config",
	"git_rebase",
	"gitattributes",
	"gitcommit",
	"gitignore",
	"comment",
	"diff",
}

-- ═══════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════

---@param list string[]
---@return string[]
---@private
local function deduplicate(list)
	local seen = {}
	local result = {}
	for _, v in ipairs(list) do
		if not seen[v] then
			seen[v] = true
			result[#result + 1] = v
		end
	end
	return result
end

---@param _lang string
---@param buf number
---@return boolean
---@private
local function is_large_file(_lang, buf)
	local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
	if ok and stats and stats.size > PERF.max_filesize then
		if not vim.b[buf]._ts_large_file_warned then
			vim.b[buf]._ts_large_file_warned = true
			vim.notify(
				string.format("Treesitter disabled: file exceeds %dKB", PERF.max_filesize / 1024),
				vim.log.levels.WARN,
				{ title = "Treesitter" }
			)
		end
		return true
	end
	return false
end

---@return boolean
---@private
local function setup_repeatable_moves()
	local ok, ts_repeat = pcall(require, "nvim-treesitter.textobjects.repeatable_move")
	if not ok then return false end

	--stylua: ignore start
	vim.keymap.set({ "n", "x", "o" }, ";", ts_repeat.repeat_last_move_next,      { desc = "Repeat last TS move →" })
	vim.keymap.set({ "n", "x", "o" }, ",", ts_repeat.repeat_last_move_previous,   { desc = "Repeat last TS move ←" })
	vim.keymap.set({ "n", "x", "o" }, "f", ts_repeat.builtin_f_expr, { expr = true, desc = "Find char →" })
	vim.keymap.set({ "n", "x", "o" }, "F", ts_repeat.builtin_F_expr, { expr = true, desc = "Find char ←" })
	vim.keymap.set({ "n", "x", "o" }, "t", ts_repeat.builtin_t_expr, { expr = true, desc = "Till char →" })
	vim.keymap.set({ "n", "x", "o" }, "T", ts_repeat.builtin_T_expr, { expr = true, desc = "Till char ←" })
	--stylua: ignore end

	return true
end

-- ═══════════════════════════════════════════════════════════════════════
-- NEW API SETUP (post-2024 nvim-treesitter rewrite)
--
-- When require("nvim-treesitter.configs") doesn't exist, we set up
-- each feature manually using Neovim's built-in treesitter APIs
-- and the textobjects plugin's own setup function.
-- ═══════════════════════════════════════════════════════════════════════

--- Install parsers via :TSInstall (deferred to avoid blocking startup).
---
---@param parsers string[] List of parser names
---@param auto boolean Whether auto-install is enabled
---@private
local function new_api_install_parsers(parsers, auto)
	if not parsers or #parsers == 0 then return end
	if not auto then return end

	vim.defer_fn(function()
		-- Use :TSInstall! (bang = silent, no error if already installed)
		local cmd = "silent! TSInstall! " .. table.concat(parsers, " ")
		pcall(vim.cmd, cmd)
	end, 500)
end

--- Enable treesitter highlighting via Neovim's built-in vim.treesitter.start().
---
---@param highlight_opts table|nil Highlight options from user config
---@private
local function new_api_enable_highlight(highlight_opts)
	if not highlight_opts or highlight_opts.enable == false then return end

	local group = vim.api.nvim_create_augroup("TSHighlightCompat", { clear = true })

	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		callback = function(ev)
			local buf = ev.buf

			-- Skip if buffer is too large
			if type(highlight_opts.disable) == "function" then
				local ft = vim.bo[buf].filetype
				local lang = ft
				pcall(function()
					lang = vim.treesitter.language.get_lang(ft) or ft
				end)
				if highlight_opts.disable(lang, buf) then return end
			end

			-- Skip disabled filetypes (list form)
			if type(highlight_opts.disable) == "table" then
				local ft = vim.bo[buf].filetype
				if vim.tbl_contains(highlight_opts.disable, ft) then return end
			end

			-- Start treesitter highlighting (built-in Neovim API)
			pcall(vim.treesitter.start, buf)
		end,
	})
end

--- Enable treesitter-based indentation.
---
---@param indent_opts table|nil Indent options from user config
---@private
local function new_api_enable_indent(indent_opts)
	if not indent_opts or indent_opts.enable == false then return end

	local group = vim.api.nvim_create_augroup("TSIndentCompat", { clear = true })
	local disabled = indent_opts.disable or {}

	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		callback = function(ev)
			local ft = vim.bo[ev.buf].filetype
			if type(disabled) == "table" and vim.tbl_contains(disabled, ft) then return end
			vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
		end,
	})
end

--- Enable incremental selection keymaps.
---
---@param incr_opts table|nil Incremental selection options
---@private
local function new_api_enable_incremental_selection(incr_opts)
	if not incr_opts or incr_opts.enable == false then return end

	local keymaps = incr_opts.keymaps or {}
	local group = vim.api.nvim_create_augroup("TSIncrSelectCompat", { clear = true })

	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		callback = function(ev)
			local buf = ev.buf

			if keymaps.init_selection then
				vim.keymap.set("n", keymaps.init_selection, function()
					require("nvim-treesitter.incremental_selection").init_selection()
				end, { buffer = buf, desc = "Init TS selection" })
			end

			if keymaps.node_incremental then
				vim.keymap.set("v", keymaps.node_incremental, function()
					require("nvim-treesitter.incremental_selection").node_incremental()
				end, { buffer = buf, desc = "Expand TS selection" })
			end

			if keymaps.node_decremental then
				vim.keymap.set("v", keymaps.node_decremental, function()
					require("nvim-treesitter.incremental_selection").node_decremental()
				end, { buffer = buf, desc = "Shrink TS selection" })
			end
		end,
	})
end

--- Setup textobjects via the plugin's own API.
---
---@param full_opts table The full opts table (textobjects expects it at top level)
---@private
local function new_api_setup_textobjects(full_opts)
	if not full_opts.textobjects then return end

	vim.defer_fn(function()
		-- nvim-treesitter-textobjects may expose its own setup
		local ok, ts_to = pcall(require, "nvim-treesitter-textobjects")
		if ok and type(ts_to.setup) == "function" then ts_to.setup(full_opts) end
	end, 200)
end

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPECS
-- ═══════════════════════════════════════════════════════════════════════

return {

	-- ─────────────────────────────────────────────────────────────────
	-- nvim-treesitter — AST-based highlighting, indentation, selection
	-- ─────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		version = false,
		build = ":TSUpdate",
		lazy = false,

		cmd = { "TSUpdate", "TSInstall", "TSUninstall", "TSInstallInfo", "TSModuleInfo" },

		dependencies = {
			"nvim-treesitter/nvim-treesitter-textobjects",
		},

		---@param opts table Merged opts from this file + all langs/*.lua files
		config = function(_, opts)
			-- ── Deduplicate parsers from multi-source opts merge ──────
			if type(opts.ensure_installed) == "table" then opts.ensure_installed = deduplicate(opts.ensure_installed) end

			-- ── Dual API support ─────────────────────────────────────
			-- Old nvim-treesitter: require("nvim-treesitter.configs").setup()
			--   → all features configured in one call
			-- New nvim-treesitter (2025 rewrite):
			--   → configs module removed
			--   → highlighting via vim.treesitter.start() (Neovim built-in)
			--   → parser install via :TSInstall commands
			--   → textobjects plugin has its own setup
			local has_configs, ts_configs = pcall(require, "nvim-treesitter.configs")

			if has_configs and type(ts_configs.setup) == "function" then
				-- ── Old API: single setup call handles everything ─────
				ts_configs.setup(opts)
			else
				-- Try the new module's setup for parser management
				local ok_ts, nvim_ts = pcall(require, "nvim-treesitter")
				if ok_ts and type(nvim_ts.setup) == "function" then
					pcall(nvim_ts.setup, {
						ensure_install = opts.ensure_installed,
					})
				else
					-- Fallback: install parsers via command
					new_api_install_parsers(opts.ensure_installed, opts.auto_install ~= false)
				end

				-- Enable each feature individually
				new_api_enable_highlight(opts.highlight)
				new_api_enable_indent(opts.indent)
				new_api_enable_incremental_selection(opts.incremental_selection)
				new_api_setup_textobjects(opts)
			end

			-- ── which-key groups for swap & peek ─────────────────────
			local wk_ok, wk = pcall(require, "which-key")
			if wk_ok then
				wk.add({
					{ "<leader>S", group = "Swap (treesitter)" },
					{ "<leader>cp", group = "Peek definition" },
				})
			end
		end,

		opts = {
			ensure_installed = BASE_PARSERS,
			auto_install = has_compiler,

			highlight = {
				enable = true,
				disable = is_large_file,
				additional_vim_regex_highlighting = false,
			},

			indent = {
				enable = true,
				disable = { "python", "yaml" },
			},

			incremental_selection = {
				enable = true,
				keymaps = {
					init_selection = "<C-space>",
					node_incremental = "<C-space>",
					scope_incremental = false,
					node_decremental = "<bs>",
				},
			},

			textobjects = {

				select = {
					enable = true,
					lookahead = true,
					include_surrounding_whitespace = true,

					selection_modes = {
						["@parameter.outer"] = "v",
						["@function.outer"] = "V",
						["@class.outer"] = "V",
					},

					keymaps = {
						["af"] = { query = "@function.outer", desc = "Around function" },
						["if"] = { query = "@function.inner", desc = "Inside function" },
						["ac"] = { query = "@class.outer", desc = "Around class" },
						["ic"] = { query = "@class.inner", desc = "Inside class" },
						["aa"] = { query = "@parameter.outer", desc = "Around argument" },
						["ia"] = { query = "@parameter.inner", desc = "Inside argument" },
						["ab"] = { query = "@block.outer", desc = "Around block" },
						["ib"] = { query = "@block.inner", desc = "Inside block" },
						["aL"] = { query = "@loop.outer", desc = "Around loop" },
						["iL"] = { query = "@loop.inner", desc = "Inside loop" },
						["ao"] = { query = "@conditional.outer", desc = "Around conditional" },
						["io"] = { query = "@conditional.inner", desc = "Inside conditional" },
						["a="] = { query = "@assignment.outer", desc = "Around assignment" },
						["i="] = { query = "@assignment.inner", desc = "Inside assignment" },
						["l="] = { query = "@assignment.lhs", desc = "Assignment LHS" },
						["r="] = { query = "@assignment.rhs", desc = "Assignment RHS" },
						["aR"] = { query = "@return.outer", desc = "Around return" },
						["iR"] = { query = "@return.inner", desc = "Inside return" },
						["aF"] = { query = "@call.outer", desc = "Around function call" },
						["iF"] = { query = "@call.inner", desc = "Inside function call" },
						["a/"] = { query = "@comment.outer", desc = "Around comment" },
						["i/"] = { query = "@comment.inner", desc = "Inside comment" },
					},
				},

				move = {
					enable = true,
					set_jumps = true,

					goto_next_start = {
						["]f"] = { query = "@function.outer", desc = "Next function start" },
						["]c"] = { query = "@class.outer", desc = "Next class start" },
						["]m"] = { query = "@parameter.inner", desc = "Next argument" },
						["]o"] = { query = "@conditional.outer", desc = "Next conditional" },
						["]r"] = { query = "@return.outer", desc = "Next return" },
					},

					goto_next_end = {
						["]F"] = { query = "@function.outer", desc = "Next function end" },
						["]C"] = { query = "@class.outer", desc = "Next class end" },
					},

					goto_previous_start = {
						["[f"] = { query = "@function.outer", desc = "Prev function start" },
						["[c"] = { query = "@class.outer", desc = "Prev class start" },
						["[m"] = { query = "@parameter.inner", desc = "Prev argument" },
						["[o"] = { query = "@conditional.outer", desc = "Prev conditional" },
						["[r"] = { query = "@return.outer", desc = "Prev return" },
					},

					goto_previous_end = {
						["[F"] = { query = "@function.outer", desc = "Prev function end" },
						["[C"] = { query = "@class.outer", desc = "Prev class end" },
					},
				},

				swap = {
					enable = true,

					swap_next = {
						["<leader>Sa"] = { query = "@parameter.inner", desc = "Swap argument → next" },
						["<leader>Sf"] = { query = "@function.outer", desc = "Swap function → next" },
					},

					swap_previous = {
						["<leader>SA"] = { query = "@parameter.inner", desc = "Swap argument ← prev" },
						["<leader>SF"] = { query = "@function.outer", desc = "Swap function ← prev" },
					},
				},

				lsp_interop = {
					enable = true,
					border = icons.borders and icons.borders.Rounded or "rounded",
					floating_preview_opts = {},

					peek_definition_code = {
						["<leader>cpf"] = { query = "@function.outer", desc = "Peek function definition" },
						["<leader>cpc"] = { query = "@class.outer", desc = "Peek class definition" },
					},
				},
			},
		},
	},

	-- ─────────────────────────────────────────────────────────────────
	-- nvim-treesitter-context — Sticky code context at top of buffer
	-- ─────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter-context",
		event = { "BufReadPost", "BufNewFile" },

		keys = {
			{
				"<leader>ut",
				function()
					require("treesitter-context").toggle()
				end,
				desc = "Toggle treesitter context",
			},
			{
				"[x",
				function()
					require("treesitter-context").go_to_context(vim.v.count1)
				end,
				desc = "Jump to enclosing context",
			},
		},

		opts = {
			enable = true,
			max_lines = PERF.context_max_lines,
			min_window_height = PERF.context_min_window,
			line_numbers = true,
			multiline_threshold = 20,
			trim_scope = "outer",
			mode = "cursor",
			separator = "─",
			zindex = 20,
			on_attach = nil,
		},

		config = function(_, opts)
			require("treesitter-context").setup(opts)

			vim.api.nvim_set_hl(0, "TreesitterContext", { link = "CursorLine" })
			vim.api.nvim_set_hl(0, "TreesitterContextLineNumber", { link = "CursorLineNr" })
			vim.api.nvim_set_hl(0, "TreesitterContextSeparator", { link = "Comment" })

			-- sp requires #rrggbb, not a hl group name
			local comment_hl = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
			local sp_color = comment_hl.fg and string.format("#%06x", comment_hl.fg) or nil
			vim.api.nvim_set_hl(0, "TreesitterContextBottom", {
				underline = true,
				sp = sp_color,
			})
		end,
	},
}
