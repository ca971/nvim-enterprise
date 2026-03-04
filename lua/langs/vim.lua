---@file lua/langs/vim.lua
---@description Vim script — LSP, linter, treesitter & buffer-local keymaps
---@module "langs.vim"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.lua                Lua language support (same architecture)
---@see langs.python             Python language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/vim.lua — Vim script language support                             ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("vim") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "vim"):                      │    ║
--- ║  │  ├─ LSP          vimls        (vim-language-server)              │    ║
--- ║  │  ├─ Formatter    —            (none — use LSP formatting)        │    ║
--- ║  │  ├─ Linter       vint         (Vim script linter)                │    ║
--- ║  │  ├─ Treesitter   vim · vimdoc parsers                            │    ║
--- ║  │  └─ DAP          —            (N/A for Vim script)               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Source file             e  Execute current line │    ║
--- ║  │  │            e  Execute selection (visual)                      │    ║
--- ║  │  ├─ INSPECT   h  Help for word           i  Inspect variable     │    ║
--- ║  │  │            d  Function definition                             │    ║
--- ║  │  ├─ TOOLS     s  Scriptnames             t  Profile startup      │    ║
--- ║  │  │            v  Version info            c  Ex command line      │    ║
--- ║  │  │            x  Check health            a  Autocommands list    │    ║
--- ║  │  └─ CONFIG    o  Open $MYVIMRC                                   │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType vim):                               ║
--- ║  • colorcolumn=80, textwidth=80   (classic Vim script convention)        ║
--- ║  • tabstop=2, shiftwidth=2        (standard Vim script indentation)      ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Vim script support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("vim") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Vim Nerd Font icon (trailing whitespace stripped)
local vim_icon = icons.misc.Vim:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Vim script buffers.
-- The group is buffer-local and only visible when filetype == "vim".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("vim", "Vim", vim_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Strip a Vim script line for execution.
---
--- Removes leading whitespace and leading `"` comment characters so
--- that commented-out Ex commands can still be executed interactively.
---
--- ```lua
--- strip_vim_line('  " set number')   -- → "set number"
--- strip_vim_line('  echo "hello"')   -- → 'echo "hello"'
--- ```
---
---@param line string Raw line from the buffer
---@return string stripped Line ready for `vim.cmd()` execution
---@private
local function strip_vim_line(line)
	return line:gsub("^%s+", ""):gsub('^"%s*', "")
end

--- Execute a Vim Ex command with error handling.
---
--- Wraps `vim.cmd()` in `pcall()` and returns both the success flag
--- and the error message (if any). Used to centralise error handling
--- across all "execute" keymaps.
---
--- ```lua
--- local ok, err = safe_exec("set number")
--- if not ok then vim.notify(err) end
--- ```
---
---@param cmd string Ex command to execute
---@return boolean ok `true` if the command succeeded
---@return string|nil err Error message on failure, `nil` on success
---@private
local function safe_exec(cmd)
	local ok, err = pcall(vim.cmd, cmd)
	if ok then
		return true, nil
	end
	return false, tostring(err)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SOURCE & EXECUTE
--
-- File sourcing and line / selection evaluation.
-- All commands run in the current Neovim instance (not a terminal).
-- ═══════════════════════════════════════════════════════════════════════════

--- Source the current Vim script file.
---
--- Saves the buffer before sourcing. Uses `pcall(vim.cmd.source)` to
--- catch any errors during execution and display them via notification.
keys.lang_map("vim", "n", "<leader>lr", function()
	vim.cmd("silent! write")
	local ok, err = pcall(vim.cmd.source, vim.fn.expand("%:p"))
	if ok then
		vim.notify("Sourced: " .. vim.fn.expand("%:t"), vim.log.levels.INFO, { title = "Vim" })
	else
		vim.notify("Source error:\n" .. tostring(err), vim.log.levels.ERROR, { title = "Vim" })
	end
end, { desc = icons.ui.Play .. " Source file" })

--- Execute the current line as a Vim Ex command.
---
--- Strips leading whitespace and comment characters via
--- `strip_vim_line()`, then executes with `safe_exec()`.
--- Skips silently if the stripped line is empty.
keys.lang_map("vim", "n", "<leader>le", function()
	local line = strip_vim_line(vim.api.nvim_get_current_line())
	if line == "" then
		vim.notify("Empty line", vim.log.levels.INFO, { title = "Vim" })
		return
	end
	local ok, err = safe_exec(line)
	if ok then
		vim.notify("OK: " .. line:sub(1, 60), vim.log.levels.INFO, { title = "Vim" })
	else
		vim.notify("Error:\n" .. err, vim.log.levels.ERROR, { title = "Vim" })
	end
end, { desc = vim_icon .. " Execute current line" })

--- Execute the visual selection as Vim Ex commands.
---
--- Yanks the selection into register `z`, splits into lines, strips
--- each line via `strip_vim_line()`, and executes non-empty lines
--- sequentially. Collects and reports all errors at the end.
keys.lang_map("vim", "v", "<leader>le", function()
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code == "" then return end

	local lines = vim.split(code, "\n")
	---@type string[]
	local errors = {}
	---@type integer
	local executed = 0

	for _, line in ipairs(lines) do
		line = strip_vim_line(line)
		if line ~= "" then
			local ok, err = safe_exec(line)
			if ok then
				executed = executed + 1
			else
				errors[#errors + 1] = err
			end
		end
	end

	if #errors > 0 then
		vim.notify("Errors:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR, { title = "Vim" })
	else
		vim.notify("Executed " .. executed .. " lines", vim.log.levels.INFO, { title = "Vim" })
	end
end, { desc = vim_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INSPECT & HELP
--
-- Contextual help, variable inspection, and function definition lookup.
-- All keymaps use the word under cursor as input.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open `:help` for the word under cursor.
---
--- If the direct help lookup fails, retries with a `:` prefix
--- (for Ex commands like `:substitute`). Opens the general help
--- index if the cursor is on an empty word.
keys.lang_map("vim", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then
		vim.cmd("help")
		return
	end
	local ok = pcall(vim.cmd.help, word)
	if not ok then
		-- Retry with colon prefix for Ex commands
		ok = pcall(vim.cmd.help, ":" .. word)
		if not ok then
			vim.notify("No help for: " .. word, vim.log.levels.INFO, { title = "Vim" })
		end
	end
end, { desc = icons.ui.Note .. " Help for word" })

--- Inspect a variable under the cursor.
---
--- Tries to evaluate the word under cursor with every common Vim
--- variable scope prefix (`g:`, `b:`, `w:`, `t:`, `v:`, `&`, `$`)
--- and displays the first successful evaluation.
---
--- Scope resolution order:
--- 1. No prefix   (script-local or global fallback)
--- 2. `g:`        global
--- 3. `b:`        buffer-local
--- 4. `w:`        window-local
--- 5. `t:`        tab-local
--- 6. `v:`        Vim internal
--- 7. `&`         option
--- 8. `$`         environment variable
keys.lang_map("vim", "n", "<leader>li", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then return end

	---@type string[]
	local prefixes = { "", "g:", "b:", "w:", "t:", "v:", "&", "$" }
	for _, prefix in ipairs(prefixes) do
		local varname = prefix .. word
		local ok, val = pcall(vim.fn.eval, varname)
		if ok then
			vim.notify(
				string.format("%s = %s", varname, vim.inspect(val)),
				vim.log.levels.INFO,
				{ title = "Vim: inspect" }
			)
			return
		end
	end

	vim.notify("Cannot evaluate: " .. word, vim.log.levels.INFO, { title = "Vim" })
end, { desc = icons.diagnostics.Info .. " Inspect variable" })

--- Show the definition of a user-defined Vim function.
---
--- Runs `:verbose function <word>` which displays the function body
--- and the script file / line number where it was defined.
keys.lang_map("vim", "n", "<leader>ld", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then return end
	local ok, _ = pcall(vim.cmd, "verbose function " .. word)
	if not ok then
		vim.notify("Function not found: " .. word, vim.log.levels.INFO, { title = "Vim" })
	end
end, { desc = vim_icon .. " Function definition" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Development utilities: script listing, startup profiling, version
-- info, Ex command line, health check, and autocommand listing.
-- ═══════════════════════════════════════════════════════════════════════════

--- List all loaded scripts via `:scriptnames`.
---
--- Useful for debugging plugin load order and finding the source
--- file of a particular script.
keys.lang_map("vim", "n", "<leader>ls", function()
	vim.cmd("scriptnames")
end, { desc = vim_icon .. " Scriptnames" })

--- Profile Neovim startup time.
---
--- Launches a fresh Neovim instance with `--startuptime`, then
--- displays the top 30 slowest items sorted by elapsed time.
--- Runs in a terminal split so the output is scrollable.
keys.lang_map("vim", "n", "<leader>lt", function()
	local profile_log = vim.fn.tempname() .. "_startup.log"
	vim.cmd.split()
	vim.cmd.terminal(
		string.format(
			"nvim --startuptime %s -c 'quit' && cat %s | sort -k 2 -n -r | head -30",
			profile_log,
			profile_log
		)
	)
end, { desc = icons.ui.Perf .. " Profile startup" })

--- Show Neovim version information.
---
--- Displays the full `:version` output including build features,
--- compilation flags, and linked libraries.
keys.lang_map("vim", "n", "<leader>lv", function()
	vim.cmd("version")
end, { desc = icons.diagnostics.Info .. " Version" })

--- Open the Ex command line with a prefilled `:` prompt.
---
--- Feeds `:` into the input queue so the user lands directly in
--- command-line mode, ready to type an Ex command.
keys.lang_map("vim", "n", "<leader>lc", function()
	vim.api.nvim_feedkeys(":", "n", false)
end, { desc = icons.ui.Terminal .. " Command line" })

--- Run `:checkhealth` to diagnose common issues.
---
--- Opens the health check report in a new buffer. Checks all
--- registered health providers (LSP, treesitter, providers, etc.).
keys.lang_map("vim", "n", "<leader>lx", function()
	vim.cmd("checkhealth")
end, { desc = icons.ui.Check .. " Check health" })

--- List all registered autocommands.
---
--- Displays every autocommand grouped by event, useful for
--- debugging unexpected behaviour triggered by `FileType`,
--- `BufWritePre`, etc.
keys.lang_map("vim", "n", "<leader>la", function()
	vim.cmd("autocmd")
end, { desc = vim_icon .. " Autocommands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CONFIG
--
-- Quick access to the Neovim configuration entry point.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Neovim configuration file (`$MYVIMRC`).
---
--- Falls back to `<stdpath("config")>/init.lua` if `$MYVIMRC` is
--- not set (e.g. when Neovim is started with `--clean`).
keys.lang_map("vim", "n", "<leader>lo", function()
	if vim.env.MYVIMRC and vim.env.MYVIMRC ~= "" then
		vim.cmd.edit(vim.env.MYVIMRC)
	else
		vim.cmd.edit(vim.fn.stdpath("config") .. "/init.lua")
	end
end, { desc = icons.ui.Gear .. " Open $MYVIMRC" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Vim script-specific alignment presets for mini.align:
-- • vim_let — align `let` assignments on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("vim") then
		---@type string Alignment preset icon from icons.app
		local vim_align_icon = icons.app.Vim

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			vim_let = {
				description = "Align Vim script let assignments on '='",
				icon = vim_align_icon,
				split_pattern = "=",
				category = "scripting",
				lang = "vim",
				filetypes = { "vim" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("vim", "vim_let")
		align_registry.mark_language_loaded("vim")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("vim", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("vim_let"), {
			desc = vim_align_icon .. "  Align Vim let",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Vim script-specific
-- parts (servers, linters, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Vim script              │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (vimls server added on require)   │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ nvim-lint          │ opts merge (linters_by_ft.vim)               │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Vim script
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- vimls: vim-language-server
	-- Provides completions, go-to-definition, hover, and diagnostics
	-- for Vim script files (.vim, vimrc).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				vimls = {},
			},
		},
		init = function()
			-- ── Buffer-local options for Vim script files ────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "vim" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "80"
					opt.textwidth = 80
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true
					opt.number = true
					opt.relativenumber = true
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures vim-language-server and vint are installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"vim-language-server",
				"vint",
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- vint: Vim script linter enforcing best practices and catching
	-- common mistakes (deprecated features, missing scriptencoding, etc.).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				vim = { "vint" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- vim:    syntax highlighting, folding, text objects
	-- vimdoc: :help file highlighting and navigation
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"vim",
				"vimdoc",
			},
		},
	},
}
