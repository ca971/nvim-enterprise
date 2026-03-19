---@file lua/langs/fish.lua
---@description Fish shell — LSP (fish-lsp), formatter (fish_indent), linter (fish -n), treesitter & keymaps
---@module "langs.fish"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard
---@see core.keymaps             Buffer-local keymap API
---@see core.icons               Shared icon definitions
---@see core.mini-align-registry Alignment preset registration
---@see langs.sh                 Shell language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/fish.lua — Fish shell language support                            ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("fish") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = {"fish"}):                   │    ║
--- ║  │  ├─ LSP          fish-lsp  (fish-language-server)                │    ║
--- ║  │  ├─ Formatter    fish_indent (built-in, via conform.nvim)        │    ║
--- ║  │  ├─ Linter       fish -n     (syntax check, via nvim-lint)       │    ║
--- ║  │  ├─ Treesitter   fish parser                                     │    ║
--- ║  │  └─ Extras       auto chmod +x on save for *.fish files          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file (fish)        R  Run with trace        │    ║
--- ║  │  │            e  Execute line/selection in terminal              │    ║
--- ║  │  ├─ TEST      t  Run tests (fishtape)                            │    ║
--- ║  │  ├─ DEBUG     d  Run with debug output (fish --debug)            │    ║
--- ║  │  ├─ REPL      c  Interactive fish shell                          │    ║
--- ║  │  ├─ INSPECT   i  Syntax check (fish --no-execute)                │    ║
--- ║  │  └─ DOCS      h  Man page for word      s  Fish documentation    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType fish):                              ║
--- ║  • colorcolumn=80, textwidth=80                                          ║
--- ║  • tabstop=4, shiftwidth=4        (fish_indent default)                  ║
--- ║  • expandtab=true                 (spaces, matching fish_indent)         ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Auto chmod +x:                                                          ║
--- ║  • Files with *.fish extension are made executable after each save       ║
--- ║  • Only triggers if the file lacks execute permission                    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("fish") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Fish Nerd Font icon (trailing whitespace stripped)
local fish_icon = (icons.lang.fish or icons.ui.Terminal or ""):gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Fish buffers.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("fish", "Fish", fish_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- FILETYPE HELPER
--
-- Fish shell uses a single filetype "fish". This wrapper keeps the
-- calling convention consistent with other langs/*.lua modules that
-- may need to register across multiple filetypes (e.g. sh/bash).
-- ═══════════════════════════════════════════════════════════════════════════

--- Register a keymap for the "fish" filetype.
---
---@param mode string|string[] Vim mode(s)
---@param lhs string Left-hand side of the mapping
---@param rhs function|string Right-hand side (callback or command)
---@param opts table Keymap options (must include `desc`)
---@private
local function fish_map(mode, lhs, rhs, opts)
	keys.lang_map("fish", mode, lhs, rhs, opts)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current file with fish.
fish_map("n", "<leader>lr", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("fish " .. vim.fn.shellescape(file))
end, { desc = icons.ui.Play .. " Run file" })

--- Run the current file with trace mode (fish_trace=1).
---
--- Enables Fish tracing which prints each command before execution,
--- similar to bash's `set -x`. Requires Fish ≥ 3.1.
fish_map("n", "<leader>lR", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("fish_trace=1 fish " .. vim.fn.shellescape(file))
end, { desc = fish_icon .. " Run with trace (fish_trace)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — EXECUTE
-- ═══════════════════════════════════════════════════════════════════════════

--- Execute the current line in a fish terminal split.
---
--- Strips leading whitespace and skips comment/empty lines.
--- Uses `fish -c` to ensure the command runs in a Fish context
--- regardless of the user's default shell.
fish_map("n", "<leader>le", function()
	local line = vim.api.nvim_get_current_line():gsub("^%s+", "")
	if line == "" or line:match("^#") then
		vim.notify("Empty or comment line", vim.log.levels.INFO, { title = "Fish" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("fish -c " .. vim.fn.shellescape(line))
end, { desc = fish_icon .. " Execute current line" })

--- Execute the visual selection in a fish terminal split.
fish_map("v", "<leader>le", function()
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code ~= "" then
		vim.cmd.split()
		vim.cmd.terminal("fish -c " .. vim.fn.shellescape(code))
	end
end, { desc = fish_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
-- ═══════════════════════════════════════════════════════════════════════════

--- Open an interactive fish shell in a terminal split.
fish_map("n", "<leader>lc", function()
	vim.cmd.split()
	vim.cmd.terminal("fish")
end, { desc = icons.ui.Terminal .. " REPL" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TESTING
--
-- Uses fishtape (TAP-producing test runner for Fish) as test runner.
-- Falls back to looking for a corresponding .test.fish file if the
-- current file is a regular .fish script.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run tests with fishtape.
fish_map("n", "<leader>lt", function()
	if vim.fn.executable("fishtape") == 0 then
		vim.notify(
			"fishtape not found.\nInstall: fisher install jorgebucaran/fishtape",
			vim.log.levels.WARN,
			{ title = "Fish" }
		)
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local test_file = file

	-- Try to find corresponding .test.fish test file
	if not file:match("%.test%.fish$") then
		local tf = file:gsub("%.fish$", ".test.fish")
		if vim.fn.filereadable(tf) == 1 then test_file = tf end
	end

	vim.cmd.split()
	vim.cmd.terminal("fishtape " .. vim.fn.shellescape(test_file))
end, { desc = icons.dev.Test .. " Run tests (fishtape)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- Fish has no DAP adapter. This keymap runs the script with Fish's
-- built-in --debug flag which emits internal debug messages (parser,
-- execution engine, etc.) — useful for diagnosing complex evaluation
-- issues beyond what fish_trace provides.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current file with Fish debug output.
fish_map("n", "<leader>ld", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("fish --debug='*' " .. vim.fn.shellescape(file))
end, { desc = icons.dev.Debug .. " Run with debug output" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the man page for the word under cursor.
fish_map("n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then
		vim.notify("No word under cursor", vim.log.levels.INFO, { title = "Fish" })
		return
	end
	local ok = pcall(vim.cmd, "Man " .. word)
	if not ok then
		ok = pcall(vim.cmd.help, word)
		if not ok then vim.notify("No man page for: " .. word, vim.log.levels.INFO, { title = "Fish" }) end
	end
end, { desc = icons.ui.Note .. " Man page for word" })

--- Open Fish documentation in the browser.
fish_map("n", "<leader>ls", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Fish Documentation", url = "https://fishshell.com/docs/current/" },
		{ name = "Fish Tutorial", url = "https://fishshell.com/docs/current/tutorial.html" },
		{ name = "Fish for Bash Users", url = "https://fishshell.com/docs/current/fish_for_bash_users.html" },
		{ name = "Fish FAQ", url = "https://fishshell.com/docs/current/faq.html" },
		{ name = "Fish Design Document", url = "https://fishshell.com/docs/current/design.html" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = fish_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Fish docs" })

--- Run syntax check on the current file (fish --no-execute).
---
--- Fish's built-in syntax checker parses the file without executing
--- it and reports any syntax errors. This is the Fish equivalent of
--- ShellCheck for POSIX/Bash scripts.
fish_map("n", "<leader>li", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("fish --no-execute " .. vim.fn.shellescape(file))
end, { desc = icons.diagnostics.Info .. " Syntax check (fish -n)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("fish") then
		align_registry.register_many({
			fish_comments = {
				description = "Align Fish inline comments on '#'",
				icon = fish_icon,
				split_pattern = "#",
				category = "scripting",
				lang = "fish",
				filetypes = { "fish" },
			},
		})

		align_registry.set_ft_mapping("fish", "fish_comments")
		align_registry.mark_language_loaded("fish")

		fish_map({ "n", "x" }, "<leader>aF", align_registry.make_align_fn("fish_comments"), {
			desc = fish_icon .. " Align Fish inline comments",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- ┌──────────────────────────┬────────────────────────────────────────┐
-- │ Plugin                   │ How it lazy-loads for Fish              │
-- ├──────────────────────────┼────────────────────────────────────────┤
-- │ nvim-lspconfig           │ opts merge (fish_lsp server added)     │
-- │ mason.nvim               │ opts merge (tools → ensure_installed)  │
-- │ conform.nvim             │ opts merge (formatters_by_ft.fish)     │
-- │ nvim-lint                │ opts merge (linters_by_ft.fish)        │
-- │ nvim-treesitter          │ opts merge (fish parser)               │
-- └──────────────────────────┴────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs
return {
	-- ── LSP SERVER (fish-lsp) ──────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				fish_lsp = {
					filetypes = { "fish" },
				},
			},
		},
		init = function()
			-- ── Buffer-local options for Fish files ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("langs_fish_options", { clear = true }),
				pattern = { "fish" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "80"
					opt.textwidth = 80
					opt.tabstop = 4
					opt.shiftwidth = 4
					opt.softtabstop = 4
					opt.expandtab = true
					opt.number = true
					opt.relativenumber = true
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
				end,
			})

			-- ── Auto chmod +x on save for *.fish files ───────────────
			vim.api.nvim_create_autocmd("BufWritePost", {
				group = vim.api.nvim_create_augroup("langs_fish_chmod", { clear = true }),
				pattern = { "*.fish" },
				callback = function()
					local file = vim.fn.expand("%:p")
					local perm = vim.fn.getfperm(file)
					if perm ~= "" and not perm:match("x") then
						local result = vim.fn.system({ "chmod", "+x", file })
						if vim.v.shell_error == 0 then
							vim.notify("chmod +x → " .. vim.fn.expand("%:t"), vim.log.levels.INFO, { title = "Fish" })
						else
							vim.notify("chmod +x failed: " .. vim.trim(result), vim.log.levels.WARN, { title = "Fish" })
						end
					end
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"fish-lsp",
			},
		},
	},

	-- ── FORMATTER (fish_indent) ────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				fish = { "fish_indent" },
			},
		},
	},

	-- ── LINTER (fish --no-execute) ─────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				fish = { "fish" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"fish",
			},
		},
	},
}
