---@file lua/langs/rego.lua
---@description Rego — LSP, formatter, treesitter & buffer-local keymaps
---@module "langs.rego"
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
---@see langs.prisma             Prisma language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/rego.lua — Rego (Open Policy Agent) language support              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("rego") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "rego"):                     │    ║
--- ║  │  ├─ LSP          regols  (Rego Language Server, conditional)     │    ║
--- ║  │  ├─ Formatter    opa fmt (via conform.nvim, conditional)         │    ║
--- ║  │  ├─ Treesitter   rego parser (syntax + folding)                  │    ║
--- ║  │  └─ Extras       eval · test · check · REPL · bundle · info      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ EVAL      r  Eval file (opa eval)  R  Eval with input JSON   │    ║
--- ║  │  ├─ TEST      t  Run tests (opa test -v)                         │    ║
--- ║  │  ├─ CHECK     l  Strict check (opa check)                        │    ║
--- ║  │  │            p  Parse / syntax check (opa parse)                │    ║
--- ║  │  ├─ REPL      c  OPA REPL (opa run --watch)                      │    ║
--- ║  │  ├─ BUILD     b  Bundle build (opa build → bundle.tar.gz)        │    ║
--- ║  │  ├─ FORMAT    f  Format file (opa fmt -w)                        │    ║
--- ║  │  ├─ INFO      i  OPA version + tools availability                │    ║
--- ║  │  └─ DOCS      h  Documentation browser (OPA docs, Playground,    │    ║
--- ║  │                  Rego Reference, Styra Academy, GitHub)          │    ║
--- ║  │                                                                  │    ║
--- ║  │  OPA CLI resolution:                                             │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. opa  → system PATH executable check                  │    │    ║
--- ║  │  │  2. nil  → user notification with install instructions   │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType rego):                              ║
--- ║  • colorcolumn=100, textwidth=100  (OPA convention)                      ║
--- ║  • tabstop=4, shiftwidth=4         (4-width indentation)                 ║
--- ║  • expandtab=false                 (Rego uses tabs by default)           ║
--- ║  • commentstring="# %s"           (Rego uses # comments)                 ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .rego → rego                                                          ║
--- ║                                                                          ║
--- ║  Conditional loading:                                                    ║
--- ║  • LSP (regols) only configured when `regols` executable is in PATH      ║
--- ║  • Formatter (opa fmt) only configured when `opa` executable is in PATH  ║
--- ║  • Treesitter parser always installed (no runtime dependency)            ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Rego support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("rego") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Rego Nerd Font icon (trailing whitespace stripped)
local rego_icon = icons.lang.rego:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Rego buffers.
-- The group is buffer-local and only visible when filetype == "rego".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("rego", "Rego", rego_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the OPA CLI (`opa`) is available in PATH.
---
--- Notifies the user with an error and install instructions if `opa`
--- is not found. All keymaps should call this before executing OPA
--- commands.
---
--- ```lua
--- if not check_opa() then return end
--- vim.cmd.terminal("opa eval -d policy.rego 'data'")
--- ```
---
---@return boolean available `true` if `opa` is executable
---@private
local function check_opa()
	if vim.fn.executable("opa") ~= 1 then
		vim.notify("opa not found in PATH — install Open Policy Agent", vim.log.levels.ERROR, { title = "Rego" })
		return false
	end
	return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — EVAL / RUN
--
-- Policy evaluation using the OPA CLI.
-- Supports evaluating against the file's own data or with external
-- JSON input and custom queries.
-- ═══════════════════════════════════════════════════════════════════════════

--- Evaluate the current Rego file against its own data.
---
--- Saves the buffer, then runs `opa eval -d <file> "data"` which
--- evaluates all rules in the file and returns the complete data
--- document. Output appears in a terminal split.
keys.lang_map("rego", "n", "<leader>lr", function()
	if not check_opa() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("opa eval -d " .. vim.fn.shellescape(file) .. ' "data"')
end, { desc = icons.ui.Play .. " Eval file" })

--- Evaluate the current Rego file with external JSON input.
---
--- Prompts for two inputs:
--- 1. **Input JSON file** — path to the input document
--- 2. **Query** — OPA query expression (defaults to `"data"`)
---
--- Runs `opa eval -d <policy> -i <input> <query>`. Aborts silently
--- if either prompt is cancelled.
keys.lang_map("rego", "n", "<leader>lR", function()
	if not check_opa() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")

	vim.ui.input({ prompt = "Input JSON file: " }, function(input)
		if not input or input == "" then return end
		vim.ui.input({ prompt = "Query (default: data): ", default = "data" }, function(query)
			if not query or query == "" then query = "data" end
			vim.cmd.split()
			vim.cmd.terminal(
				string.format(
					"opa eval -d %s -i %s %s",
					vim.fn.shellescape(file),
					vim.fn.shellescape(input),
					vim.fn.shellescape(query)
				)
			)
		end)
	end)
end, { desc = icons.ui.Play .. " Eval with input" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST / CHECK
--
-- Policy testing and static analysis.
-- Tests use OPA's built-in test runner which discovers `test_*` rules.
-- Check and parse provide two levels of validation: semantic (strict)
-- and syntactic (parse-only).
-- ═══════════════════════════════════════════════════════════════════════════

--- Run OPA tests in the current directory.
---
--- Executes `opa test . -v` which discovers all `test_*` rules
--- across all `.rego` files in the directory tree. Verbose output
--- shows individual test results.
keys.lang_map("rego", "n", "<leader>lt", function()
	if not check_opa() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("opa test . -v")
end, { desc = icons.dev.Test .. " Test" })

--- Run strict semantic checks on the current file.
---
--- Executes `opa check --strict` which validates:
--- - Rule definitions and references
--- - Type correctness
--- - Unused variables and imports
--- - Deprecated features
---
--- Reports pass/fail via notifications (does not open a terminal).
keys.lang_map("rego", "n", "<leader>ll", function()
	if not check_opa() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("opa check --strict " .. vim.fn.shellescape(file) .. " 2>&1")
	if vim.v.shell_error == 0 then
		vim.notify("✓ No issues found", vim.log.levels.INFO, { title = "Rego" })
	else
		vim.notify(result, vim.log.levels.WARN, { title = "Rego" })
	end
end, { desc = icons.ui.Check .. " Check (strict)" })

--- Parse the current file for syntax errors only.
---
--- Runs `opa parse` which validates the file's syntax without
--- evaluating rules or checking references. Lighter than
--- `opa check --strict` — useful for rapid feedback during editing.
keys.lang_map("rego", "n", "<leader>lp", function()
	if not check_opa() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("opa parse " .. vim.fn.shellescape(file) .. " 2>&1")
	if vim.v.shell_error == 0 then
		vim.notify("✓ Syntax OK", vim.log.levels.INFO, { title = "Rego" })
	else
		vim.notify(result, vim.log.levels.ERROR, { title = "Rego" })
	end
end, { desc = rego_icon .. " Parse (syntax)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL / BUNDLE / FORMAT
--
-- Interactive REPL, policy bundle creation, and file formatting.
-- The REPL runs OPA in watch mode for live policy evaluation.
-- Bundle creates a distributable policy archive.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the OPA REPL in watch mode.
---
--- Runs `opa run --watch .` which starts an interactive OPA shell
--- that automatically reloads when policy files change. Provides
--- full query evaluation and data exploration capabilities.
keys.lang_map("rego", "n", "<leader>lc", function()
	if not check_opa() then return end
	vim.cmd.split()
	vim.cmd.terminal("opa run --watch .")
end, { desc = icons.ui.Terminal .. " OPA REPL" })

--- Build an OPA bundle from the current directory.
---
--- Runs `opa build -b . -o bundle.tar.gz` which creates a
--- distributable policy bundle containing all `.rego` files,
--- data files, and a manifest. The output file is `bundle.tar.gz`
--- in the current directory.
keys.lang_map("rego", "n", "<leader>lb", function()
	if not check_opa() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("opa build -b . -o bundle.tar.gz")
end, { desc = rego_icon .. " Bundle build" })

--- Format the current Rego file in-place.
---
--- Saves the buffer, runs `opa fmt -w` which formats the file
--- according to OPA's canonical style, then reloads the buffer
--- to reflect changes.
keys.lang_map("rego", "n", "<leader>lf", function()
	if not check_opa() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.fn.system("opa fmt -w " .. vim.fn.shellescape(file))
	vim.cmd.edit()
	vim.notify("Formatted", vim.log.levels.INFO, { title = "Rego" })
end, { desc = rego_icon .. " Format file" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INFO / DOCUMENTATION
--
-- OPA environment information and external documentation access.
-- Info displays version and tool availability.
-- Documentation links open in the system browser via `vim.ui.open()`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Display OPA environment information.
---
--- Shows:
--- - OPA version (parsed from `opa version` output)
--- - Tool availability status for `opa` and `regols`
--- - Current working directory
---
--- Results are displayed in a notification popup.
keys.lang_map("rego", "n", "<leader>li", function()
	---@type string[]
	local info = { rego_icon .. " OPA / Rego Info:", "" }

	-- ── OPA version ──────────────────────────────────────────────────
	if vim.fn.executable("opa") == 1 then
		---@type string
		local version = vim.fn.system("opa version 2>/dev/null"):match("Version:%s*(%S+)") or "unknown"
		info[#info + 1] = "  Version: " .. version
	end

	-- ── Tool availability ────────────────────────────────────────────
	---@type string[]
	local tools = { "opa", "regols" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		---@type string
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	-- ── Working directory ────────────────────────────────────────────
	info[#info + 1] = "  CWD:     " .. vim.fn.getcwd()

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Rego" })
end, { desc = icons.diagnostics.Info .. " OPA info" })

--- Open OPA / Rego documentation in the system browser.
---
--- Presents a selection menu with links to key OPA documentation
--- resources. The selected URL is opened via `vim.ui.open()` which
--- delegates to the system's default browser.
---
--- Available documentation links:
--- - OPA Docs (main documentation)
--- - Rego Reference (language specification)
--- - Rego Playground (interactive policy editor)
--- - Styra Academy (learning platform)
--- - OPA GitHub (source repository)
keys.lang_map("rego", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "OPA Docs", url = "https://www.openpolicyagent.org/docs/latest/" },
		{ name = "Rego Reference", url = "https://www.openpolicyagent.org/docs/latest/policy-reference/" },
		{ name = "Rego Playground", url = "https://play.openpolicyagent.org/" },
		{ name = "Styra Academy", url = "https://academy.styra.com/" },
		{ name = "OPA GitHub", url = "https://github.com/open-policy-agent/opa" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = rego_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Rego-specific alignment presets for mini.align:
-- • rego_assign — align rule assignments on ":="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("rego") then
		---@type string Alignment preset icon from icons.lang
		local rego_align_icon = icons.lang.rego

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			rego_assign = {
				description = "Align Rego rule assignments on ':='",
				icon = rego_align_icon,
				split_pattern = ":=",
				category = "domain",
				lang = "rego",
				filetypes = { "rego" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("rego", "rego_assign")
		align_registry.mark_language_loaded("rego")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("rego", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("rego_assign"), {
			desc = rego_align_icon .. "  Align Rego assign",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Rego-specific
-- parts (servers, formatters, parsers, filetype extensions, buffer options).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Rego                   │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts fn (regols added only if executable)   │
-- │ conform.nvim       │ opts fn (opa_fmt added only if opa exists)  │
-- │ nvim-treesitter    │ opts merge (rego parser always ensured)     │
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- Conditional loading:
-- • LSP server (regols) only configured when `regols` executable is
--   found in PATH. regols is a community project and may not be
--   installed alongside OPA.
-- • Formatter (opa fmt) only configured when `opa` executable is
--   found in PATH. Uses a custom conform formatter definition since
--   opa fmt reads from stdin.
-- • Treesitter parser always installed (lightweight, no runtime
--   dependency on OPA).
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Rego
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- regols: Rego Language Server (completions, diagnostics, hover,
	-- go-to-definition for rules and packages).
	-- Only configured when regols is available in PATH.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = function(_, opts)
			if vim.fn.executable("regols") ~= 1 then return end
			opts.servers = opts.servers or {}
			opts.servers.regols = {}
		end,
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					rego = "rego",
				},
			})

			-- ── Buffer-local options for Rego files ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "rego" },
				callback = function()
					local opt = vim.opt_local

					opt.wrap = false
					opt.colorcolumn = "100"
					opt.textwidth = 100

					opt.tabstop = 4
					opt.shiftwidth = 4
					opt.softtabstop = 4
					opt.expandtab = false -- Rego uses tabs by default

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

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- opa fmt: OPA's built-in formatter via conform.nvim.
	-- Custom formatter definition since opa fmt reads from stdin.
	-- Only configured when opa is available in PATH.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = function(_, opts)
			if vim.fn.executable("opa") ~= 1 then return end

			opts.formatters_by_ft = opts.formatters_by_ft or {}
			opts.formatters_by_ft.rego = { "opa_fmt" }

			opts.formatters = opts.formatters or {}
			opts.formatters.opa_fmt = {
				command = "opa",
				args = { "fmt" },
				stdin = true,
			}
		end,
	},

	-- ── TREESITTER PARSER ──────────────────────────────────────────────────
	-- rego: syntax highlighting, folding, indentation
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"rego",
			},
		},
	},
}
