---@file lua/langs/nushell.lua
---@description Nushell — LSP (nu --lsp), formatter, treesitter & buffer-local keymaps
---@module "langs.nushell"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.bash               Bash/Shell language support (shell scripting peer)
---@see langs.python             Python language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/nushell.lua — Nushell language support                            ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("nushell") → {} if off      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "nu"):                       │    ║
--- ║  │  ├─ LSP          nu --lsp (built-in, NOT via Mason/lspconfig)    │    ║
--- ║  │  │               Completions, diagnostics, hover, go-to-def      │    ║
--- ║  │  ├─ Formatter    nufmt (if available, not in Mason registry)     │    ║
--- ║  │  ├─ Linter       nu --ide-check (built-in IDE diagnostics)       │    ║
--- ║  │  ├─ Treesitter   nu parser                                       │    ║
--- ║  │  └─ CLI tools    nu (runtime, REPL, source, lint — all-in-one)   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file              R  Run with arguments     │    ║
--- ║  │  │            e  Execute line/selection                          │    ║
--- ║  │  ├─ TEST      t  Run tests (tests/mod.nu or current file)        │    ║
--- ║  │  ├─ REPL      c  Nu interactive REPL (nu -i)                     │    ║
--- ║  │  │            s  Source file in REPL                             │    ║
--- ║  │  ├─ TOOLS     l  Lint (--ide-check)                              │    ║
--- ║  │  │            m  Module info            p  Overlay list          │    ║
--- ║  │  └─ DOCS      i  Nushell info           h  Documentation picker  │    ║
--- ║  │                                                                  │    ║
--- ║  │  LSP integration (manual start):                                 │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. FileType autocmd triggers on ft = "nu"               │    │    ║
--- ║  │  │  2. Checks if `nu` is in $PATH                           │    │    ║
--- ║  │  │  3. Calls vim.lsp.start() with cmd = { "nu", "--lsp" }   │    │    ║
--- ║  │  │  4. Root dir resolved from env.nu / config.nu / .git     │    │    ║
--- ║  │  │  5. NOT managed by Mason (nu bundles its own LSP)        │    │    ║
--- ║  │  │  6. NOT via lspconfig (manual vim.lsp.start())           │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType nu):                                ║
--- ║  • colorcolumn=100, textwidth=100  (Nushell community standard)          ║
--- ║  • tabstop=2, shiftwidth=2         (Nushell standard indentation)        ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="# %s"            (Nushell single-line comment)         ║
--- ║                                                                          ║
--- ║  Test convention:                                                        ║
--- ║  • tests/mod.nu present → run tests/mod.nu                               ║
--- ║  • No test dir           → run current file as test script               ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .nu            → nu                                                   ║
--- ║  • env.nu          → nu                                                  ║
--- ║  • config.nu       → nu                                                  ║
--- ║  • login.nu        → nu                                                  ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Nushell support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("nushell") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Nushell Nerd Font icon (trailing whitespace stripped)
local nu_icon = icons.lang.nushell:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Nushell buffers.
-- The group is buffer-local and only visible when filetype == "nu".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("nu", "Nushell", nu_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Nushell availability check and command execution.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the `nu` binary is available in `$PATH`.
---
--- Displays an error notification if `nu` is not found.
---
--- ```lua
--- if not check_nu() then return end
--- ```
---
---@return boolean available `true` if `nu` is executable, `false` otherwise
---@private
local function check_nu()
	if vim.fn.executable("nu") ~= 1 then
		vim.notify("nu not found in PATH", vim.log.levels.ERROR, { title = "Nushell" })
		return false
	end
	return true
end

--- Run a command in a terminal split with optional nu check.
---
--- Verifies that `nu` is available, then opens a horizontal split
--- and runs the command. Optionally saves the current buffer first.
---
--- ```lua
--- run_nu("nu script.nu", true)          --> save + terminal
--- run_nu("nu -c 'ls'")                  --> terminal only
--- run_nu("nu -i")                       --> interactive REPL
--- ```
---
---@param cmd string Full command string to execute in the terminal
---@param save? boolean If `true`, save the current buffer before running (default: `false`)
---@return boolean success `true` if the command was launched, `false` if nu is missing
---@private
local function run_nu(cmd, save)
	if not check_nu() then return false end
	if save then vim.cmd("silent! write") end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
	return true
end

--- Open content in a scratch buffer in a horizontal split.
---
--- Creates a new unlisted scratch buffer, populates it with the
--- given lines, and opens it in a split. The buffer is wiped
--- when hidden (no save prompt).
---
--- ```lua
--- open_scratch(vim.split(output, "\n"))
--- ```
---
---@param lines string[] Content lines for the scratch buffer
---@return nil
---@private
local function open_scratch(lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.cmd.split()
	vim.api.nvim_win_set_buf(0, buf)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- File execution and line/selection evaluation.
-- All commands use the `nu` runtime directly.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current Nushell file in a terminal split.
---
--- Saves the buffer before execution.
keys.lang_map("nu", "n", "<leader>lr", function()
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	run_nu("nu " .. file, true)
end, { desc = icons.ui.Play .. " Run file" })

--- Run the current Nushell file with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then executes in a
--- terminal split. Aborts silently if the user cancels the prompt.
keys.lang_map("nu", "n", "<leader>lR", function()
	if not check_nu() then return end
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal("nu " .. file .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Execute the current line as a Nushell expression.
---
--- Strips leading whitespace before passing to `nu -c`.
--- Skips silently if the line is empty.
keys.lang_map("nu", "n", "<leader>le", function()
	if not check_nu() then return end
	local line = vim.api.nvim_get_current_line():gsub("^%s+", "")
	if line == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("nu -c " .. vim.fn.shellescape(line))
end, { desc = nu_icon .. " Execute line" })

--- Execute the visual selection as Nushell code.
---
--- Yanks the selection into register `z`, then passes it to
--- `nu -c` in a terminal split.
keys.lang_map("nu", "v", "<leader>le", function()
	if not check_nu() then return end
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("nu -c " .. vim.fn.shellescape(code))
end, { desc = nu_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL / SOURCE
--
-- Interactive REPL and file sourcing for live Nushell sessions.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a Nushell interactive REPL in a terminal split.
---
--- Launches `nu -i` (interactive mode) which provides a full
--- Nushell session with history, completions, and all configured
--- modules/overlays.
keys.lang_map("nu", "n", "<leader>lc", function()
	run_nu("nu -i")
end, { desc = icons.ui.Terminal .. " Nu REPL" })

--- Source the current file in a Nushell session.
---
--- Runs `nu -c 'source <file>'` which loads all definitions
--- (commands, aliases, modules) from the file into the session.
--- Saves the buffer before sourcing.
keys.lang_map("nu", "n", "<leader>ls", function()
	if not check_nu() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("nu -c 'source " .. file .. "'")
end, { desc = nu_icon .. " Source file" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution with convention-based discovery.
-- Falls back to running the current file if no test directory found.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run tests using Nushell conventions.
---
--- Strategy:
--- 1. `tests/mod.nu` exists → run it as the test entry point
--- 2. No test directory → run the current file as a test script
---
--- Saves the buffer before running.
keys.lang_map("nu", "n", "<leader>lt", function()
	if not check_nu() then return end
	vim.cmd("silent! write")

	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/tests/mod.nu") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("nu tests/mod.nu")
	else
		local file = vim.fn.shellescape(vim.fn.expand("%:p"))
		vim.cmd.split()
		vim.cmd.terminal("nu " .. file)
	end
end, { desc = icons.dev.Test .. " Run tests" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — LINT
--
-- Nushell's built-in IDE diagnostics via `nu --ide-check`.
-- Provides syntax and type checking without a full LSP session.
-- ═══════════════════════════════════════════════════════════════════════════

--- Lint the current file with `nu --ide-check`.
---
--- Runs `nu --ide-check 10 <file>` which performs syntax validation,
--- type checking, and produces IDE-formatted diagnostics at the
--- specified severity level (10 = all diagnostics).
---
--- If no issues are found, displays a success notification.
--- Otherwise, opens the diagnostics output in a scratch buffer.
keys.lang_map("nu", "n", "<leader>ll", function()
	if not check_nu() then return end
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	local result = vim.fn.system("nu --ide-check 10 " .. file .. " 2>&1")

	if result == "" or result:match("^%s*$") then
		vim.notify("✓ No issues found", vim.log.levels.INFO, { title = "Nushell" })
	else
		open_scratch(vim.split(result, "\n"))
	end
end, { desc = nu_icon .. " Lint (--ide-check)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — MODULE / OVERLAY
--
-- Nushell module and overlay inspection commands.
-- Modules are Nushell's code organization units; overlays are
-- layered environments that can be activated/deactivated.
-- ═══════════════════════════════════════════════════════════════════════════

--- List available Nushell modules.
---
--- Runs `nu -c 'help modules'` in a terminal split to display
--- all currently registered modules and their commands.
keys.lang_map("nu", "n", "<leader>lm", function()
	run_nu("nu -c 'help modules'")
end, { desc = nu_icon .. " Modules" })

--- List active Nushell overlays.
---
--- Runs `nu -c 'overlay list'` in a terminal split to display
--- the overlay stack (active overlays and their order).
keys.lang_map("nu", "n", "<leader>lp", function()
	run_nu("nu -c 'overlay list'")
end, { desc = nu_icon .. " Overlays" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Nushell toolchain info display and curated documentation links
-- for the Nushell ecosystem.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show Nushell toolchain and environment information.
---
--- Displays a summary notification containing:
--- - Nushell version (from `nu --version`)
--- - Current working directory
--- - Tool availability checklist (nu, nufmt)
keys.lang_map("nu", "n", "<leader>li", function()
	if not check_nu() then return end
	local version = vim.fn.system("nu --version 2>/dev/null"):gsub("%s+$", "")

	---@type string[]
	local info = {
		nu_icon .. " Nushell Info:",
		"",
		"  Version: " .. version,
		"  CWD:     " .. vim.fn.getcwd(),
	}

	-- ── Tool availability ────────────────────────────────────────
	---@type string[]
	local tools = { "nu", "nufmt" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Nushell" })
end, { desc = icons.diagnostics.Info .. " Nushell info" })

--- Open Nushell documentation in the browser.
---
--- Presents a list of curated Nushell resources via `vim.ui.select()`:
--- 1. Nushell Book — comprehensive language guide
--- 2. Nushell Commands — built-in command reference
--- 3. Nushell Cookbook — practical recipes and patterns
--- 4. Nushell GitHub — source code and issue tracker
---
--- Opens the selected URL in the system browser via `vim.ui.open()`.
keys.lang_map("nu", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Nushell Book", url = "https://www.nushell.sh/book/" },
		{ name = "Nushell Commands", url = "https://www.nushell.sh/commands/" },
		{ name = "Nushell Cookbook", url = "https://www.nushell.sh/cookbook/" },
		{ name = "Nushell GitHub", url = "https://github.com/nushell/nushell" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = nu_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Nushell-specific alignment presets for mini.align:
-- • nushell_record — align record fields on ":"
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("nushell") then
		---@type string Alignment preset icon from icons.app
		local nu_align_icon = icons.app.Nu

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			nushell_record = {
				description = "Align Nushell record fields on ':'",
				icon = nu_align_icon,
				split_pattern = ":",
				category = "devops",
				lang = "nushell",
				filetypes = { "nu" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("nu", "nushell_record")
		align_registry.mark_language_loaded("nushell")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("nu", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("nushell_record"), {
			desc = nu_align_icon .. "  Align Nushell record",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Nushell-specific
-- parts (LSP manual start, treesitter parser).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Nushell                │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ init only (manual vim.lsp.start on FileType)│
-- │ mason.nvim         │ NOT used (nu bundles its own LSP + linter)  │
-- │ conform.nvim       │ NOT used (nufmt not in Mason registry)      │
-- │ nvim-lint          │ NOT used (nu --ide-check via keymap)         │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Nushell is a self-contained toolchain:
-- • LSP: `nu --lsp` (built into the nu binary, NOT a separate server)
-- • Linter: `nu --ide-check` (built-in diagnostics)
-- • Formatter: `nufmt` (separate tool, not in Mason)
-- • Install: via package manager (brew, cargo, etc.), not Mason
--
-- The LSP is started manually via vim.lsp.start() in a FileType
-- autocmd because:
-- 1. nu --lsp is not in the Mason registry
-- 2. lspconfig doesn't have a built-in config for Nushell
-- 3. Manual start gives us full control over root_dir resolution
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Nushell
return {
	-- ── LSP (manual start — nu --lsp is built-in) ──────────────────────────
	-- Nushell bundles its own language server (`nu --lsp`).
	-- It is NOT managed by Mason or lspconfig — we start it manually
	-- via `vim.lsp.start()` in the FileType autocmd.
	--
	-- The LSP provides:
	--   • Completions (commands, variables, modules)
	--   • Diagnostics (syntax errors, type mismatches)
	--   • Hover documentation
	--   • Go-to-definition
	--
	-- Root directory resolution:
	--   env.nu → config.nu → .git → CWD (fallback)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					nu = "nu",
				},
				filename = {
					["env.nu"] = "nu",
					["config.nu"] = "nu",
					["login.nu"] = "nu",
				},
			})

			-- ── Buffer-local options + manual LSP start ──────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "nu" },
				callback = function(args)
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "100"
					opt.textwidth = 100
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true
					opt.number = true
					opt.relativenumber = true
					opt.commentstring = "# %s"

					-- ── Start nu --lsp manually ──────────────────
					-- nu --lsp is built into the nu binary.
					-- We start it via vim.lsp.start() since it's
					-- not in lspconfig's server registry.
					if vim.fn.executable("nu") == 1 then
						vim.lsp.start({
							name = "nushell",
							cmd = { "nu", "--lsp" },
							root_dir = vim.fs.dirname(vim.fs.find({ "env.nu", "config.nu", ".git" }, {
								upward = true,
								path = vim.api.nvim_buf_get_name(args.buf),
							})[1]) or vim.fn.getcwd(),
							filetypes = { "nu" },
						})
					end
				end,
			})
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- nu: syntax highlighting, folding, text objects, indentation.
	-- Nushell's pipeline-oriented syntax, structured data types,
	-- and closure syntax benefit significantly from treesitter parsing.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"nu",
			},
		},
	},
}
