---@file lua/langs/julia.lua
---@description Julia — LSP (julials), formatter, treesitter & buffer-local keymaps
---@module "langs.julia"
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
---@see langs.rust               Rust language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/julia.lua — Julia language support                                ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("julia") → {} if off        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "julia"):                    │    ║
--- ║  │  ├─ LSP          julials  (LanguageServer.jl)                    │    ║
--- ║  │  │               Completions, diagnostics, lint, go-to-def       │    ║
--- ║  │  ├─ Formatter    JuliaFormatter.jl (CLI, not conform)            │    ║
--- ║  │  ├─ Treesitter   julia parser                                    │    ║
--- ║  │  └─ Debug        Debugger.jl (CLI, not DAP)                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file              R  Run with arguments     │    ║
--- ║  │  │            e  Eval line/selection                             │    ║
--- ║  │  ├─ TEST      t  Test (Pkg.test)                                 │    ║
--- ║  │  ├─ DEBUG     d  Debug (Debugger.jl @enter)                      │    ║
--- ║  │  ├─ REPL      c  Julia REPL (--project if available)             │    ║
--- ║  │  ├─ TOOLS     s  Format (JuliaFormatter.jl)                      │    ║
--- ║  │  │            b  Benchmark file                                  │    ║
--- ║  │  │            p  Pkg commands (status/update/add/rm/gc/…)        │    ║
--- ║  │  └─ DOCS      i  @doc (inline)          h  Documentation picker  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Project detection:                                              │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Project.toml present → --project=. flag added to:       │    │    ║
--- ║  │  │    • REPL launch                                         │    │    ║
--- ║  │  │    • Pkg commands                                        │    │    ║
--- ║  │  │    • Benchmark                                           │    │    ║
--- ║  │  │    • Debug                                               │    │    ║
--- ║  │  │  No Project.toml → standalone file execution             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Pkg commands picker:                                            │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  status       → Pkg.status()                             │    │    ║
--- ║  │  │  update       → Pkg.update()                             │    │    ║
--- ║  │  │  instantiate  → Pkg.instantiate()                        │    │    ║
--- ║  │  │  resolve      → Pkg.resolve()                            │    │    ║
--- ║  │  │  add…         → Pkg.add("name")    (prompts for name)    │    │    ║
--- ║  │  │  remove…      → Pkg.rm("name")     (prompts for name)    │    │    ║
--- ║  │  │  gc           → Pkg.gc()                                 │    │    ║
--- ║  │  │  precompile   → Pkg.precompile()                         │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType julia):                             ║
--- ║  • colorcolumn=92, textwidth=92  (Julia style guide line length)         ║
--- ║  • tabstop=4, shiftwidth=4       (Julia standard indentation)            ║
--- ║  • expandtab=true                (spaces, never tabs)                    ║
--- ║  • commentstring="# %s"          (Julia single-line comment)             ║
--- ║  • Treesitter folding            (foldmethod=expr, foldlevel=99)         ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .jl  → julia                                                          ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Julia support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("julia") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Julia Nerd Font icon (trailing whitespace stripped)
local jl_icon = icons.lang.julia:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Julia buffers.
-- The group is buffer-local and only visible when filetype == "julia".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("julia", "Julia", jl_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Julia availability check, project detection, and command execution.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the `julia` binary is available in `$PATH`.
---
--- Displays an error notification if `julia` is not found.
---
--- ```lua
--- if not check_julia() then return end
--- ```
---
---@return boolean available `true` if `julia` is executable, `false` otherwise
---@private
local function check_julia()
	if vim.fn.executable("julia") ~= 1 then
		vim.notify("julia not found in PATH", vim.log.levels.ERROR, { title = "Julia" })
		return false
	end
	return true
end

--- Get the `--project=.` flag if a `Project.toml` exists in CWD.
---
--- Julia projects are identified by the presence of `Project.toml`.
--- When present, the `--project=.` flag activates the project
--- environment (dependencies, compat, etc.).
---
--- ```lua
--- local flag = get_project_flag()   --> " --project=." or ""
--- vim.cmd.terminal("julia" .. flag .. " script.jl")
--- ```
---
---@return string flag `" --project=."` if `Project.toml` exists, `""` otherwise
---@private
local function get_project_flag()
	if vim.fn.filereadable("Project.toml") == 1 then
		return " --project=."
	end
	return ""
end

--- Run a Julia command in a terminal split with project detection.
---
--- Checks that `julia` is available, then opens a horizontal split
--- with a terminal running the given command. Automatically prepends
--- `julia` and the project flag if `prepend_julia` is true.
---
--- ```lua
--- -- Run with julia prefix + project flag
--- run_julia_cmd("script.jl", true)        --> "julia --project=. script.jl"
---
--- -- Run raw command string
--- run_julia_cmd("julia -e 'println(1)'")  --> "julia -e 'println(1)'"
--- ```
---
---@param cmd string Command or arguments to execute
---@param prepend_julia? boolean If `true`, prepend `julia` + project flag (default: `false`)
---@return nil
---@private
local function run_julia_cmd(cmd, prepend_julia)
	if not check_julia() then return end

	---@type string
	local full_cmd
	if prepend_julia then
		full_cmd = "julia" .. get_project_flag() .. " " .. cmd
	else
		full_cmd = cmd
	end

	vim.cmd.split()
	vim.cmd.terminal(full_cmd)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- File execution and line/selection evaluation.
-- All keymaps open a terminal split for output.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current Julia file in a terminal split.
---
--- Saves the buffer before execution. If a `Project.toml` exists
--- in CWD, the `--project=.` flag is automatically added to
--- activate the project environment.
keys.lang_map("julia", "n", "<leader>lr", function()
	if not check_julia() then return end
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	run_julia_cmd(file, true)
end, { desc = icons.ui.Play .. " Run file" })

--- Run the current Julia file with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then executes in a
--- terminal split with the project flag. Aborts silently if the
--- user cancels the prompt.
keys.lang_map("julia", "n", "<leader>lR", function()
	if not check_julia() then return end
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		run_julia_cmd(file .. " " .. args, true)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Evaluate the current line as a Julia expression.
---
--- Strips leading whitespace before passing to `julia -e`.
--- Skips silently if the line is empty.
keys.lang_map("julia", "n", "<leader>le", function()
	if not check_julia() then return end
	local line = vim.api.nvim_get_current_line():gsub("^%s+", "")
	if line == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("julia -e " .. vim.fn.shellescape(line))
end, { desc = jl_icon .. " Eval line" })

--- Evaluate the visual selection as Julia code.
---
--- Yanks the selection into register `z`, then passes it to
--- `julia -e` in a terminal split.
keys.lang_map("julia", "v", "<leader>le", function()
	if not check_julia() then return end
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("julia -e " .. vim.fn.shellescape(code))
end, { desc = jl_icon .. " Eval selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
--
-- Opens an interactive Julia REPL in a terminal split.
-- Automatically activates the project environment when
-- Project.toml is present.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a Julia REPL in a terminal split.
---
--- If `Project.toml` exists in CWD, launches with `--project=.`
--- to activate the project environment (dependencies, Manifest).
--- Otherwise, launches a bare Julia REPL.
keys.lang_map("julia", "n", "<leader>lc", function()
	run_julia_cmd("julia" .. get_project_flag())
end, { desc = icons.ui.Terminal .. " Julia REPL" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via Julia's built-in Pkg.test().
-- Falls back to running the current file if no Project.toml is found.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the project test suite via `Pkg.test()`.
---
--- Strategy:
--- 1. `Project.toml` present → `julia --project=. -e "using Pkg; Pkg.test()"`
--- 2. No project → run the current file directly (assumed to be a test script)
keys.lang_map("julia", "n", "<leader>lt", function()
	if not check_julia() then return end
	vim.cmd("silent! write")
	if vim.fn.filereadable("Project.toml") == 1 then
		run_julia_cmd('julia --project=. -e "using Pkg; Pkg.test()"')
	else
		local file = vim.fn.shellescape(vim.fn.expand("%:p"))
		run_julia_cmd(file, true)
	end
end, { desc = icons.dev.Test .. " Test (Pkg.test)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — BENCHMARK / DEBUG
--
-- Benchmark execution and Debugger.jl integration.
-- Both commands use the project environment when available.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current file as a benchmark.
---
--- Executes the file with the project environment activated.
--- The file is expected to use `BenchmarkTools.jl` or similar
--- benchmarking packages that are in the project dependencies.
keys.lang_map("julia", "n", "<leader>lb", function()
	if not check_julia() then return end
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	run_julia_cmd(file, true)
end, { desc = icons.dev.Benchmark .. " Benchmark" })

--- Debug the current file using Debugger.jl.
---
--- Launches Julia with `@enter include("file.jl")` which drops
--- into the Debugger.jl interactive session at the first expression.
---
--- Requires `Debugger.jl` to be installed in the project or global
--- environment.
---
--- NOTE: This uses Julia's CLI-based Debugger.jl, not DAP. For a
--- graphical debugging experience, consider using the Julia VS Code
--- extension or a future DAP adapter.
keys.lang_map("julia", "n", "<leader>ld", function()
	if not check_julia() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	run_julia_cmd(string.format(
		'julia%s -e "using Debugger; @enter include(\\"%s\\")"',
		get_project_flag(),
		file
	))
end, { desc = icons.dev.Debug .. " Debug" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Formatting via JuliaFormatter.jl and package management via Pkg.
-- ═══════════════════════════════════════════════════════════════════════════

--- Format the current file using JuliaFormatter.jl.
---
--- Runs `JuliaFormatter.format_file()` on the current file, then
--- reloads the buffer to reflect changes. Notifies if JuliaFormatter
--- is not installed.
---
--- NOTE: JuliaFormatter.jl must be installed in the global Julia
--- environment (`julia -e 'using Pkg; Pkg.add("JuliaFormatter")'`).
keys.lang_map("julia", "n", "<leader>ls", function()
	if not check_julia() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system(string.format(
		'julia -e "using JuliaFormatter; format_file(\\"%s\\")" 2>&1',
		file
	))
	if vim.v.shell_error == 0 then
		vim.cmd.edit()
		vim.notify("Formatted", vim.log.levels.INFO, { title = "Julia" })
	else
		vim.notify(
			"Format error (install JuliaFormatter.jl?):\n" .. result,
			vim.log.levels.WARN,
			{ title = "Julia" }
		)
	end
end, { desc = jl_icon .. " Format" })

--- Open the Pkg commands picker.
---
--- Presents a list of common `Pkg` operations via `vim.ui.select()`:
--- - Direct commands: status, update, instantiate, resolve, gc, precompile
--- - Prompt commands: add, remove (prompts for package name)
---
--- All commands run with `--project=.` to operate on the current
--- project environment. Opens in a terminal split for output.
---
--- ```
--- ┌─ Pkg: ─────────────┐
--- │  status              │
--- │  update              │
--- │  instantiate         │
--- │  resolve             │
--- │  add…                │ ← prompts for package name
--- │  remove…             │ ← prompts for package name
--- │  gc                  │
--- │  precompile          │
--- └──────────────────────┘
--- ```
keys.lang_map("julia", "n", "<leader>lp", function()
	if not check_julia() then return end

	---@type { name: string, cmd: string|nil, prompt: boolean|nil }[]
	local actions = {
		{ name = "status", cmd = 'julia --project=. -e "using Pkg; Pkg.status()"' },
		{ name = "update", cmd = 'julia --project=. -e "using Pkg; Pkg.update()"' },
		{ name = "instantiate", cmd = 'julia --project=. -e "using Pkg; Pkg.instantiate()"' },
		{ name = "resolve", cmd = 'julia --project=. -e "using Pkg; Pkg.resolve()"' },
		{ name = "add…", prompt = true },
		{ name = "remove…", prompt = true },
		{ name = "gc", cmd = 'julia --project=. -e "using Pkg; Pkg.gc()"' },
		{ name = "precompile", cmd = 'julia --project=. -e "using Pkg; Pkg.precompile()"' },
	}

	vim.ui.select(
		vim.tbl_map(function(a) return a.name end, actions),
		{ prompt = jl_icon .. " Pkg:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]

			if action.prompt then
				vim.ui.input({ prompt = "Package name: " }, function(pkg)
					if not pkg or pkg == "" then return end
					---@type string
					local op = action.name:match("^(%w+)")
					run_julia_cmd(string.format(
						'julia --project=. -e "using Pkg; Pkg.%s(\\"%s\\")"',
						op,
						pkg
					))
				end)
			else
				run_julia_cmd(action.cmd --[[@as string]])
			end
		end
	)
end, { desc = icons.ui.Package .. " Pkg commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to Julia's @doc macro for inline help and curated
-- documentation links for the Julia ecosystem.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show `@doc` documentation for the word under cursor.
---
--- Runs `julia -e "@doc <word>"` in a terminal split, displaying
--- the same output as the Julia REPL's `?` help mode.
keys.lang_map("julia", "n", "<leader>li", function()
	if not check_julia() then return end
	local word = vim.fn.expand("<cword>")
	if word == "" then return end
	vim.cmd.split()
	vim.cmd.terminal(string.format('julia -e "@doc %s"', word))
end, { desc = icons.diagnostics.Info .. " @doc" })

--- Open Julia documentation in the browser.
---
--- Presents a list of curated Julia ecosystem resources via
--- `vim.ui.select()`:
--- 1. Julia Docs — official language documentation
--- 2. Julia Packages — community package registry
--- 3. Julia Academy — free online courses
--- 4. JuliaHub — package search and computing platform
---
--- Opens the selected URL in the system browser via `vim.ui.open()`.
keys.lang_map("julia", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Julia Docs", url = "https://docs.julialang.org/en/v1/" },
		{ name = "Julia Packages", url = "https://juliapackages.com/" },
		{ name = "Julia Academy", url = "https://juliaacademy.com/" },
		{ name = "JuliaHub", url = "https://juliahub.com/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r) return r.name end, refs),
		{ prompt = jl_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Julia-specific alignment presets for mini.align:
-- • julia_kwargs — align named tuples and keyword arguments on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("julia") then
		---@type string Alignment preset icon from icons.lang
		local julia_align_icon = icons.lang.julia

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			julia_kwargs = {
				description = "Align Julia named tuples on '='",
				icon = julia_align_icon,
				split_pattern = "=",
				category = "scripting",
				lang = "julia",
				filetypes = { "julia" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("julia", "julia_kwargs")
		align_registry.mark_language_loaded("julia")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("julia", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("julia_kwargs"), {
			desc = julia_align_icon .. "  Align Julia kwargs",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Julia-specific
-- parts (servers, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Julia                  │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (julials server added on require) │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Julia's tooling ecosystem differs from most languages:
-- • Formatting is done via JuliaFormatter.jl (CLI), not conform
-- • Linting is built into julials (LanguageServer.jl)
-- • Debugging uses Debugger.jl (CLI), not DAP
-- • No separate linter tool — julials handles all diagnostics
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Julia
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- julials: LanguageServer.jl — the standard Julia LSP.
	-- Provides completions, diagnostics, go-to-definition, references,
	-- rename, and workspace symbol search.
	--
	-- Settings:
	--   • lint.missingrefs = "all" — report all missing references
	--   • completionmode = "qualify" — show qualified names in completions
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				julials = {
					settings = {
						julia = {
							lint = {
								missingrefs = "all",
							},
							completionmode = "qualify",
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					jl = "julia",
				},
			})

			-- ── Buffer-local options for Julia files ─────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "julia" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "92"
					opt.textwidth = 92
					opt.tabstop = 4
					opt.shiftwidth = 4
					opt.softtabstop = 4
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
	-- Ensures the Julia LSP is installed via Mason:
	--   • julia-lsp — LanguageServer.jl (pre-built sysimage for fast start)
	--
	-- NOTE: JuliaFormatter.jl and Debugger.jl are managed via Julia's
	-- own package manager (Pkg), not Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"julia-lsp",
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- julia: syntax highlighting, folding, text objects, indentation.
	-- Julia's complex syntax (Unicode operators, macros, type annotations,
	-- string interpolation) benefits significantly from treesitter parsing.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"julia",
			},
		},
	},
}
