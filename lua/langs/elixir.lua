---@file lua/langs/elixir.lua
---@description Elixir — LSP, formatter, linter, treesitter & buffer-local keymaps
---@module "langs.elixir"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.python             Python language support (same architecture)
---@see langs.docker             Docker language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/elixir.lua — Elixir language support                              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("elixir") → {} if off       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "elixir" / "heex" /          │    ║
--- ║  │             "eelixir"):                                          │    ║
--- ║  │  ├─ LSP          elixirls (ElixirLS — completions, dialyzer)     │    ║
--- ║  │  ├─ Formatter    mix format (via keymap, not conform)            │    ║
--- ║  │  ├─ Linter       credo (via mix, keymap-triggered)               │    ║
--- ║  │  ├─ Treesitter   elixir · heex · eex parsers                     │    ║
--- ║  │  ├─ DAP          — (not configured, see elixir-ls debugger)      │    ║
--- ║  │  └─ Extras       Phoenix-aware mix commands                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file (elixir)     R  Mix run / phx.server   │    ║
--- ║  │  │            e  Eval line              e  Eval selection (vis)  │    ║
--- ║  │  ├─ REPL      c  IEx REPL (with mix context if available)        │    ║
--- ║  │  ├─ TEST      t  mix test (all)        T  Test current file      │    ║
--- ║  │  ├─ MIX       d  deps.get              m  Mix commands (picker)  │    ║
--- ║  │  │            p  Phoenix tasks (picker, Phoenix projects only)   │    ║
--- ║  │  ├─ FORMAT    s  mix format                                      │    ║
--- ║  │  ├─ LINT      l  credo (current file)                            │    ║
--- ║  │  └─ DOCS      i  Module info           h  HexDocs (browser)      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Phoenix detection:                                              │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Reads mix.exs from CWD                               │    │    ║
--- ║  │  │  2. Scans for :phoenix dependency                        │    │    ║
--- ║  │  │  3. If found: Mix run → phx.server, extra mix commands   │    │    ║
--- ║  │  │     • phx.server, phx.routes, phx.digest                 │    │    ║
--- ║  │  │     • phx.gen.html/json/live/context                     │    │    ║
--- ║  │  │     • ecto.migrate/rollback/reset/gen.migration          │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType elixir/heex/eelixir):               ║
--- ║  • colorcolumn=98, textwidth=98   (Elixir formatter default)             ║
--- ║  • tabstop=2, shiftwidth=2        (Elixir convention: 2-space indent)    ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • commentstring="# %s"          (Elixir comments)                       ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .ex, .exs → elixir                                                    ║
--- ║  • .heex → heex                                                          ║
--- ║  • .leex, .eex → eelixir                                                 ║
--- ║  • mix.exs, mix.lock, .formatter.exs, .credo.exs → elixir                ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Elixir support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("elixir") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Elixir Nerd Font icon (trailing whitespace stripped)
local ex_icon = icons.lang.elixir:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Elixir buffers.
-- The group is buffer-local and only visible when filetype == "elixir".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("elixir", "Elixir", ex_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect if the current project is a Phoenix application.
---
--- Reads `mix.exs` from the current working directory and scans for
--- the `:phoenix` dependency string. This heuristic covers both
--- `{:phoenix, "~> 1.7"}` and `{:phoenix, ">= 0.0.0"}` patterns.
---
--- ```lua
--- if is_phoenix() then
---   vim.cmd.terminal("mix phx.server")
--- end
--- ```
---
---@return boolean is_phoenix `true` if `:phoenix` is found in mix.exs
---@private
local function is_phoenix()
	local cwd = vim.fn.getcwd()
	local mix_exs = cwd .. "/mix.exs"
	if vim.fn.filereadable(mix_exs) ~= 1 then return false end
	local content = table.concat(vim.fn.readfile(mix_exs), "\n")
	return content:match(":phoenix") ~= nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- File execution and expression evaluation.
-- All keymaps open a terminal split for output.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current Elixir file in a terminal split.
---
--- Saves the buffer before execution. Requires the `elixir` binary
--- to be available in PATH.
keys.lang_map("elixir", "n", "<leader>lr", function()
	if vim.fn.executable("elixir") ~= 1 then
		vim.notify("elixir not found in PATH", vim.log.levels.ERROR, { title = "Elixir" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("elixir " .. vim.fn.shellescape(file))
end, { desc = icons.ui.Play .. " Run file" })

--- Run the project with mix.
---
--- Saves the buffer, then executes:
--- • `mix phx.server` if this is a Phoenix project
--- • `mix run` otherwise
keys.lang_map("elixir", "n", "<leader>lR", function()
	vim.cmd("silent! write")
	local cmd = "mix run"
	if is_phoenix() then cmd = "mix phx.server" end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.Play .. " Mix run" })

--- Evaluate the current line as an Elixir expression.
---
--- Strips leading whitespace before passing to `elixir -e`.
--- Skips silently if the line is empty.
keys.lang_map("elixir", "n", "<leader>le", function()
	local line = vim.api.nvim_get_current_line():gsub("^%s+", "")
	if line == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("elixir -e " .. vim.fn.shellescape(line))
end, { desc = ex_icon .. " Eval line" })

--- Evaluate the visual selection as Elixir code.
---
--- Yanks the selection into register `z`, then passes it to
--- `elixir -e` in a terminal split.
keys.lang_map("elixir", "v", "<leader>le", function()
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("elixir -e " .. vim.fn.shellescape(code))
end, { desc = ex_icon .. " Eval selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
--
-- Opens an interactive IEx session in a terminal split.
-- Automatically loads the mix project context if mix.exs is present.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open an IEx REPL in a terminal split.
---
--- Uses `iex -S mix` when a `mix.exs` file is found in the current
--- directory (loads all project modules and dependencies), otherwise
--- falls back to a bare `iex` session.
keys.lang_map("elixir", "n", "<leader>lc", function()
	local cmd = "iex"
	if vim.fn.filereadable("mix.exs") == 1 then cmd = "iex -S mix" end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.ui.Terminal .. " IEx REPL" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via `mix test`. Supports both full-suite and
-- single-file testing with automatic test file detection.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the full test suite with `mix test`.
keys.lang_map("elixir", "n", "<leader>lt", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("mix test")
end, { desc = icons.dev.Test .. " Run tests" })

--- Run tests for the current file.
---
--- If the current file is not a test file (`*_test.exs`), attempts
--- to find the corresponding test file by:
--- 1. Replacing `/lib/` with `/test/` in the path
--- 2. Replacing `.ex` with `_test.exs` in the filename
---
--- Falls back to running the current file directly if no test file
--- is found (useful when already editing a test file).
keys.lang_map("elixir", "n", "<leader>lT", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")

	-- ── Auto-detect corresponding test file ──────────────────────────
	---@type string
	local test_file = file
	if not file:match("_test%.exs$") then test_file = file:gsub("/lib/", "/test/"):gsub("%.ex$", "_test.exs") end

	if vim.fn.filereadable(test_file) == 1 then
		vim.cmd.split()
		vim.cmd.terminal("mix test " .. vim.fn.shellescape(test_file))
	else
		-- Run current file if it is itself a test file
		vim.cmd.split()
		vim.cmd.terminal("mix test " .. vim.fn.shellescape(file))
	end
end, { desc = icons.dev.Test .. " Test file" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — MIX
--
-- Mix task management: dependency installation, comprehensive task picker,
-- and Phoenix-specific operations.
-- ═══════════════════════════════════════════════════════════════════════════

--- Install project dependencies with `mix deps.get`.
keys.lang_map("elixir", "n", "<leader>ld", function()
	vim.cmd.split()
	vim.cmd.terminal("mix deps.get")
end, { desc = icons.ui.Package .. " Deps.get" })

--- Open a picker with common mix tasks.
---
--- Base tasks (always available):
--- • compile, deps.get, deps.update, deps.tree
--- • format, hex.info, hex.outdated
--- • clean, dialyzer, credo, docs, release
---
--- Phoenix tasks (appended if `:phoenix` detected in mix.exs):
--- • phx.server, phx.routes
--- • phx.gen.html/json/live/context (prompt for args)
--- • ecto.migrate/rollback/reset/gen.migration (prompt for args)
keys.lang_map("elixir", "n", "<leader>lm", function()
	---@type { name: string, cmd: string, prompt?: boolean }[]
	local actions = {
		{ name = "compile", cmd = "mix compile" },
		{ name = "deps.get", cmd = "mix deps.get" },
		{ name = "deps.update --all", cmd = "mix deps.update --all" },
		{ name = "deps.tree", cmd = "mix deps.tree" },
		{ name = "format", cmd = "mix format" },
		{ name = "hex.info", cmd = "mix hex.info" },
		{ name = "hex.outdated", cmd = "mix hex.outdated" },
		{ name = "clean", cmd = "mix clean" },
		{ name = "dialyzer", cmd = "mix dialyzer" },
		{ name = "credo", cmd = "mix credo" },
		{ name = "docs", cmd = "mix docs" },
		{ name = "release", cmd = "mix release" },
	}

	-- ── Append Phoenix tasks if applicable ───────────────────────────
	if is_phoenix() then
		---@type { name: string, cmd: string, prompt?: boolean }[]
		local phx = {
			{ name = "phx.server", cmd = "mix phx.server" },
			{ name = "phx.routes", cmd = "mix phx.routes" },
			{ name = "phx.gen.html…", cmd = "mix phx.gen.html", prompt = true },
			{ name = "phx.gen.json…", cmd = "mix phx.gen.json", prompt = true },
			{ name = "phx.gen.live…", cmd = "mix phx.gen.live", prompt = true },
			{ name = "phx.gen.context…", cmd = "mix phx.gen.context", prompt = true },
			{ name = "ecto.migrate", cmd = "mix ecto.migrate" },
			{ name = "ecto.rollback", cmd = "mix ecto.rollback" },
			{ name = "ecto.reset", cmd = "mix ecto.reset" },
			{ name = "ecto.gen.migration…", cmd = "mix ecto.gen.migration", prompt = true },
		}
		for _, a in ipairs(phx) do
			actions[#actions + 1] = a
		end
	end

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = ex_icon .. " Mix:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]
			if action.prompt then
				vim.ui.input({ prompt = "Arguments: " }, function(args)
					if not args or args == "" then return end
					vim.cmd.split()
					vim.cmd.terminal(action.cmd .. " " .. args)
				end)
			else
				vim.cmd.split()
				vim.cmd.terminal(action.cmd)
			end
		end
	)
end, { desc = ex_icon .. " Mix commands" })

--- Open a Phoenix-specific tasks picker.
---
--- Only available in Phoenix projects (detected via `is_phoenix()`).
--- Notifies the user if the current project is not a Phoenix app.
---
--- Available actions:
--- • Start server   — `mix phx.server`
--- • Routes         — `mix phx.routes`
--- • Digest         — `mix phx.digest`
keys.lang_map("elixir", "n", "<leader>lp", function()
	if not is_phoenix() then
		vim.notify("Not a Phoenix project", vim.log.levels.INFO, { title = "Elixir" })
		return
	end

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "Start server", cmd = "mix phx.server" },
		{ name = "Routes", cmd = "mix phx.routes" },
		{ name = "Digest", cmd = "mix phx.digest" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = ex_icon .. " Phoenix:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = ex_icon .. " Phoenix tasks" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FORMAT / LINT
--
-- Manual formatting and linting via mix tasks.
-- These complement the LSP diagnostics from ElixirLS.
-- ═══════════════════════════════════════════════════════════════════════════

--- Format the current file with `mix format`.
---
--- Saves the buffer, runs `mix format` synchronously, then reloads
--- the buffer to reflect changes. Notifies on success or error.
keys.lang_map("elixir", "n", "<leader>ls", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("mix format " .. vim.fn.shellescape(file) .. " 2>&1")
	if vim.v.shell_error == 0 then
		vim.cmd.edit()
		vim.notify("Formatted", vim.log.levels.INFO, { title = "Elixir" })
	else
		vim.notify("Format error:\n" .. result, vim.log.levels.ERROR, { title = "Elixir" })
	end
end, { desc = ex_icon .. " Format (mix)" })

--- Run credo linter on the current file.
---
--- Saves the buffer, then runs `mix credo <file>` in a terminal split
--- to display all lint warnings and suggestions.
keys.lang_map("elixir", "n", "<leader>ll", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("mix credo " .. vim.fn.shellescape(file))
end, { desc = ex_icon .. " Lint (credo)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to Elixir module metadata and HexDocs documentation
-- without leaving the editor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show module info for the word under cursor.
---
--- Attempts to call `__info__(:functions)` on the module name under
--- the cursor. Falls back to `h <module>` (IEx help) if the first
--- approach fails.
keys.lang_map("elixir", "n", "<leader>li", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then return end
	vim.cmd.split()
	vim.cmd.terminal(
		"elixir -e 'IO.puts inspect(" .. word .. ".__info__(:functions))' 2>/dev/null || elixir -e 'h " .. word .. "'"
	)
end, { desc = icons.diagnostics.Info .. " Module info" })

--- Open HexDocs documentation in the system browser.
---
--- If the cursor is on a word, adds a contextual "HexDocs: <word>"
--- entry at the top of the picker that links directly to the module
--- page on hexdocs.pm.
---
--- Static entries:
--- • Elixir Docs     — official Elixir documentation
--- • Hex.pm          — package registry
--- • Phoenix Docs    — web framework documentation
--- • Ecto Docs       — database wrapper documentation
keys.lang_map("elixir", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")

	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Elixir Docs", url = "https://elixir-lang.org/docs.html" },
		{ name = "Hex.pm (packages)", url = "https://hex.pm/" },
		{ name = "Phoenix Docs", url = "https://hexdocs.pm/phoenix/" },
		{ name = "Ecto Docs", url = "https://hexdocs.pm/ecto/" },
	}

	if word ~= "" then
		table.insert(refs, 1, {
			name = "HexDocs: " .. word,
			url = "https://hexdocs.pm/elixir/" .. word .. ".html",
		})
	end

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = ex_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " HexDocs" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Elixir-specific alignment presets for mini.align:
-- • elixir_map     — align map entries on ":"
-- • elixir_keyword — align keyword list entries on "=>"
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("elixir") then
		---@type string Alignment preset icon from icons.app
		local align_icon = icons.app.Elixir

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			elixir_map = {
				description = "Align Elixir map entries on ':'",
				icon = align_icon,
				split_pattern = ":",
				category = "functional",
				lang = "elixir",
				filetypes = { "elixir" },
			},
			elixir_keyword = {
				description = "Align Elixir keyword list on '=>'",
				icon = align_icon,
				split_pattern = "=>",
				category = "functional",
				lang = "elixir",
				filetypes = { "elixir" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("elixir", "elixir_map")
		align_registry.mark_language_loaded("elixir")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("elixir", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("elixir_map"), {
			desc = align_icon .. "  Align Elixir map",
		})
		keys.lang_map("elixir", { "n", "x" }, "<leader>aT", align_registry.make_align_fn("elixir_keyword"), {
			desc = align_icon .. "  Align Elixir keyword",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Elixir-specific
-- parts (servers, parsers).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for Elixir                 │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig                         │ opts merge (elixirls server added on require)│
-- │ mason.nvim                             │ opts merge (elixir-ls added to ensure_installed)│
-- │ nvim-treesitter                        │ opts merge (elixir/heex/eex parsers added)   │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Formatting and linting are handled via mix tasks (keymaps above)
-- rather than conform.nvim / nvim-lint, because mix format and credo are
-- tightly integrated with the project's mix.exs configuration.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Elixir
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- elixirls: ElixirLS language server providing completions, diagnostics
	-- (including Dialyzer), go-to-definition, and test lenses.
	--
	-- Configuration:
	-- • dialyzerEnabled = true   — enables Dialyzer-based type analysis
	-- • fetchDeps = false        — does not auto-fetch deps on startup
	-- • enableTestLenses = true  — shows "Run test" code lenses
	-- • suggestSpecs = true      — suggests @spec annotations
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				elixirls = {
					settings = {
						elixirLS = {
							dialyzerEnabled = true,
							fetchDeps = false,
							enableTestLenses = true,
							suggestSpecs = true,
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					ex = "elixir",
					exs = "elixir",
					heex = "heex",
					leex = "eelixir",
					eex = "eelixir",
				},
				filename = {
					["mix.exs"] = "elixir",
					["mix.lock"] = "elixir",
					[".formatter.exs"] = "elixir",
					[".credo.exs"] = "elixir",
				},
			})

			-- ── Buffer-local options for Elixir files ────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "elixir", "heex", "eelixir" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "98"
					opt.textwidth = 98
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true
					opt.number = true
					opt.relativenumber = true
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
					opt.commentstring = "# %s"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures elixir-ls is installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"elixir-ls",
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- elixir: syntax highlighting, folding, text objects for Elixir source
	-- heex:   Phoenix HEEx templates (HTML + Elixir expressions)
	-- eex:    Embedded Elixir templates (EEx / LEEx)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"elixir",
				"heex",
				"eex",
			},
		},
	},
}
