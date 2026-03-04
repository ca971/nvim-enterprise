---@file lua/langs/r.lua
---@description R — LSP, formatter, linter, treesitter & buffer-local keymaps
---@module "langs.r"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.utils               Utility functions (`has_executable`)
---@see core.mini-align-registry Alignment preset registration system
---@see langs.python             Python language support (same architecture)
---@see langs.prisma             Prisma language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/r.lua — R language support                                        ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("r") → {} if off            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "r" / "rmd"):                │    ║
--- ║  │  ├─ LSP          r_language_server (completions, diagnostics,    │    ║
--- ║  │  │               rich documentation, code actions)               │    ║
--- ║  │  ├─ Formatter    styler (via LSP or CLI)                         │    ║
--- ║  │  ├─ Linter       lintr (via LSP diagnostics + CLI keymap)        │    ║
--- ║  │  ├─ Treesitter   r · rnoweb parsers                              │    ║
--- ║  │  └─ Extras       renv management · Rmarkdown/Quarto rendering    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file (Rscript)   R  Run with arguments      │    ║
--- ║  │  │            e  Execute line/selection                          │    ║
--- ║  │  ├─ REPL      c  R console (--no-save)                           │    ║
--- ║  │  │            s  Source file into R session                      │    ║
--- ║  │  ├─ TEST      t  Run tests (testthat::test_local)                │    ║
--- ║  │  ├─ PACKAGES  p  Install CRAN packages (prompted)                │    ║
--- ║  │  ├─ RENV      d  Renv commands picker (6 actions)                │    ║
--- ║  │  │               init · snapshot · restore · status · update ·   │    ║
--- ║  │  │               clean                                           │    ║
--- ║  │  ├─ RENDER    k  Render Rmarkdown/Quarto document                │    ║
--- ║  │  ├─ LINT      l  Run lintr on current file                       │    ║
--- ║  │  ├─ INFO      i  R session info (sessionInfo)                    │    ║
--- ║  │  └─ DOCS      h  Documentation browser (rdocumentation, CRAN,    │    ║
--- ║  │                  Tidyverse, R4DS, cheatsheets + word search)     │    ║
--- ║  │                                                                  │    ║
--- ║  │  R CLI resolution:                                               │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Rscript / R  → system PATH executable check          │    │    ║
--- ║  │  │  2. nil           → user notification with error         │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Render pipeline:                                                │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. .qmd + quarto available → quarto render              │    │    ║
--- ║  │  │  2. .Rmd / fallback         → rmarkdown::render()        │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType r / rmd):                           ║
--- ║  • colorcolumn=80, textwidth=80    (Tidyverse style guide)               ║
--- ║  • tabstop=2, shiftwidth=2         (2-space indentation)                 ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="# %s"            (R uses # comments)                   ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .r, .R          → r                                                   ║
--- ║  • .rmd, .Rmd, .qmd → rmd                                                ║
--- ║  • .Rprofile, .Renviron → r                                              ║
--- ║                                                                          ║
--- ║  Conditional loading:                                                    ║
--- ║  • LSP + Mason install only when `R` executable is found in PATH         ║
--- ║  • Treesitter parsers always installed (no runtime dependency)           ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if R support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("r") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local has_executable = require("core.utils").has_executable
local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string R Nerd Font icon (trailing whitespace stripped)
local r_icon = icons.lang.r:gsub("%s+$", "")

---@type string[] Filetypes covered by this module (R + R Markdown)
local r_fts = { "r", "rmd" }

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUPS
--
-- Registers the <leader>l group label for R and R Markdown buffers.
-- Both filetypes share the same icon and keymap prefix.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("r", "R", r_icon)
keys.lang_group("rmd", "R Markdown", r_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the R runtime (`Rscript`) is available in PATH.
---
--- Notifies the user with an error if `Rscript` is not found.
--- All keymaps should call this before executing R commands.
---
--- ```lua
--- if not check_r() then return end
--- vim.cmd.terminal("Rscript script.R")
--- ```
---
---@return boolean available `true` if `Rscript` is executable
---@private
local function check_r()
	if not has_executable("Rscript") then
		vim.notify("R / Rscript not found in PATH", vim.log.levels.ERROR, { title = "R" })
		return false
	end
	return true
end

--- Escape double quotes inside a file path for R string literals.
---
--- R CLI commands use `Rscript -e 'source("path")'`, so any double
--- quotes in the path must be escaped to prevent syntax errors.
---
--- ```lua
--- local safe = escape_r_string('/path/with "quotes"/file.R')
--- --> '/path/with \\"quotes\\"/file.R'
--- ```
---
---@param str string Raw file path or R expression
---@return string escaped Path with `"` replaced by `\"`
---@private
local function escape_r_string(str)
	return str:gsub('"', '\\"')
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
--
-- File execution and line/selection evaluation via Rscript.
-- All keymaps open a terminal split for output.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the current R file with Rscript in a terminal split.
---
--- Saves the buffer before execution. Uses the system `Rscript`
--- binary which runs the script non-interactively.
keys.lang_map(r_fts, "n", "<leader>lr", function()
	if not check_r() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("Rscript " .. vim.fn.shellescape(file))
end, { desc = icons.ui.Play .. " Run (Rscript)" })

--- Run the current R file with user-provided arguments.
---
--- Prompts for arguments via `vim.ui.input()`, then passes them
--- to `Rscript` after the file path. Arguments are appended raw
--- (not shell-escaped individually) to allow shell expansion.
--- Aborts silently if the user cancels the prompt.
keys.lang_map(r_fts, "n", "<leader>lR", function()
	if not check_r() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal("Rscript " .. vim.fn.shellescape(file) .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

--- Execute the current line as an R expression.
---
--- Strips leading whitespace before passing to `Rscript -e`.
--- Skips silently if the line is empty.
keys.lang_map(r_fts, "n", "<leader>le", function()
	if not check_r() then return end
	local line = vim.api.nvim_get_current_line():gsub("^%s+", "")
	if line == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("Rscript -e " .. vim.fn.shellescape(line))
end, { desc = r_icon .. " Execute line" })

--- Execute the visual selection as R code.
---
--- Yanks the selection into register `z`, then passes it to
--- `Rscript -e` in a terminal split.
keys.lang_map(r_fts, "v", "<leader>le", function()
	if not check_r() then return end
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("Rscript -e " .. vim.fn.shellescape(code))
end, { desc = r_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL / SOURCE
--
-- Interactive R console and file sourcing.
-- The console runs R with `--no-save` to avoid polluting the workspace.
-- Source uses R's `source()` function for proper evaluation context.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open an interactive R console in a terminal split.
---
--- Runs `R --no-save` which starts an interactive R session
--- without saving the workspace on exit. Provides full REPL
--- functionality including help, completion, and plotting.
keys.lang_map(r_fts, "n", "<leader>lc", function()
	if not check_r() then return end
	vim.cmd.split()
	vim.cmd.terminal("R --no-save")
end, { desc = icons.ui.Terminal .. " R console" })

--- Source the current file into an R session.
---
--- Uses `Rscript -e 'source("file")'` which evaluates the file
--- in a fresh R session with proper `source()` semantics (e.g.
--- `__file__` is set, relative paths resolve correctly).
keys.lang_map(r_fts, "n", "<leader>ls", function()
	if not check_r() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("Rscript -e 'source(\"" .. escape_r_string(file) .. "\")'")
end, { desc = r_icon .. " Source file" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via testthat. Runs the full local test suite.
-- Uses `testthat::test_local()` which auto-discovers test files
-- in the `tests/testthat/` directory.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the local test suite with testthat.
---
--- Saves the buffer, then executes `testthat::test_local()` which
--- discovers and runs all test files in `tests/testthat/`.
--- Results are displayed in the terminal split.
keys.lang_map(r_fts, "n", "<leader>lt", function()
	if not check_r() then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("Rscript -e 'testthat::test_local()'")
end, { desc = icons.dev.Test .. " Test (testthat)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — PACKAGES / RENV
--
-- CRAN package installation and renv environment management.
-- Package install supports multiple comma/space-separated names.
-- Renv provides a picker with 6 common operations.
-- ═══════════════════════════════════════════════════════════════════════════

--- Install CRAN packages by name.
---
--- Prompts for one or more package names (space or comma-separated),
--- then runs `install.packages(c(...))` in a terminal split.
---
--- ```
--- Input: "dplyr, ggplot2 tidyr"
--- Executes: install.packages(c("dplyr", "ggplot2", "tidyr"))
--- ```
keys.lang_map(r_fts, "n", "<leader>lp", function()
	if not check_r() then return end
	vim.ui.input({ prompt = "Package(s) to install: " }, function(pkg)
		if not pkg or pkg == "" then return end

		---@type string[]
		local pkgs = {}
		for p in pkg:gmatch("[^%s,]+") do
			pkgs[#pkgs + 1] = '"' .. p .. '"'
		end

		local install_cmd = "install.packages(c(" .. table.concat(pkgs, ", ") .. "))"
		vim.cmd.split()
		vim.cmd.terminal("Rscript -e " .. vim.fn.shellescape(install_cmd))
	end)
end, { desc = icons.ui.Package .. " Install packages" })

--- Open the renv commands picker.
---
--- Presents 6 renv operations in a selection menu:
--- - `renv::init()`     — Initialize renv in the project
--- - `renv::snapshot()` — Save current package state to lockfile
--- - `renv::restore()`  — Restore packages from lockfile
--- - `renv::status()`   — Show differences between lockfile and library
--- - `renv::update()`   — Update packages to latest versions
--- - `renv::clean()`    — Remove unused packages from the library
keys.lang_map(r_fts, "n", "<leader>ld", function()
	if not check_r() then return end

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "renv::init()", cmd = "Rscript -e 'renv::init()'" },
		{ name = "renv::snapshot()", cmd = "Rscript -e 'renv::snapshot()'" },
		{ name = "renv::restore()", cmd = "Rscript -e 'renv::restore()'" },
		{ name = "renv::status()", cmd = "Rscript -e 'renv::status()'" },
		{ name = "renv::update()", cmd = "Rscript -e 'renv::update()'" },
		{ name = "renv::clean()", cmd = "Rscript -e 'renv::clean()'" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = r_icon .. " Renv:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = r_icon .. " Renv" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RENDER / LINT
--
-- Document rendering (Rmarkdown / Quarto) and static analysis.
-- Render auto-detects the document type and selects the appropriate
-- pipeline (quarto for .qmd, rmarkdown::render for .Rmd).
-- ═══════════════════════════════════════════════════════════════════════════

--- Render the current Rmarkdown or Quarto document.
---
--- Auto-detects the rendering pipeline:
--- 1. `.qmd` file + `quarto` executable → `quarto render`
--- 2. All other cases → `rmarkdown::render()`
---
--- Saves the buffer before rendering. Output is displayed
--- in a terminal split.
keys.lang_map(r_fts, "n", "<leader>lk", function()
	if not check_r() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")

	if has_executable("quarto") and file:match("%.qmd$") then
		vim.cmd.split()
		vim.cmd.terminal("quarto render " .. vim.fn.shellescape(file))
	else
		vim.cmd.split()
		vim.cmd.terminal("Rscript -e 'rmarkdown::render(\"" .. escape_r_string(file) .. "\")'")
	end
end, { desc = r_icon .. " Render" })

--- Run lintr on the current file.
---
--- Saves the buffer, then executes `lintr::lint()` which performs
--- static analysis and reports style issues, potential bugs, and
--- best-practice violations. Output appears in the terminal split.
keys.lang_map(r_fts, "n", "<leader>ll", function()
	if not check_r() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("Rscript -e 'lintr::lint(\"" .. escape_r_string(file) .. "\")'")
end, { desc = r_icon .. " Lint (lintr)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INFO / DOCUMENTATION
--
-- R session information and external documentation access.
-- Session info displays R version, loaded packages, and platform.
-- Documentation links open in the system browser via `vim.ui.open()`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Display R session information.
---
--- Runs `sessionInfo()` which outputs:
--- - R version and platform
--- - Locale settings
--- - Attached packages and versions
--- - Loaded namespaces
keys.lang_map(r_fts, "n", "<leader>li", function()
	if not check_r() then return end
	vim.cmd.split()
	vim.cmd.terminal("Rscript -e 'sessionInfo()'")
end, { desc = icons.diagnostics.Info .. " Session info" })

--- Open R documentation in the system browser.
---
--- Presents a selection menu with links to key R documentation
--- resources. If the cursor is on a word, adds a search link
--- to rdocumentation.org as the first option.
---
--- Available documentation links:
--- - Search: <word> (contextual, only when cursor is on a word)
--- - R Documentation (rdocumentation.org)
--- - CRAN (cran.r-project.org)
--- - Tidyverse (tidyverse.org)
--- - R for Data Science (r4ds.hadley.nz)
--- - RStudio Cheatsheets (posit.co)
keys.lang_map(r_fts, "n", "<leader>lh", function()
	---@type string
	local word = vim.fn.expand("<cword>")

	---@type { name: string, url: string }[]
	local refs = {
		{ name = "R Documentation", url = "https://www.rdocumentation.org/" },
		{ name = "CRAN", url = "https://cran.r-project.org/" },
		{ name = "Tidyverse", url = "https://www.tidyverse.org/" },
		{ name = "R for Data Science", url = "https://r4ds.hadley.nz/" },
		{ name = "RStudio Cheatsheets", url = "https://posit.co/resources/cheatsheets/" },
	}

	-- Prepend contextual search link if cursor is on a word
	if word ~= "" then
		table.insert(refs, 1, {
			name = "Search: " .. word,
			url = "https://www.rdocumentation.org/search?q=" .. word,
		})
	end

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = r_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers R-specific alignment presets for mini.align:
-- • r_named — align named vector/list elements on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("r") then
		---@type string Alignment preset icon from icons.lang
		local r_align_icon = icons.lang.r

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			r_named = {
				description = "Align R named vector elements on '='",
				icon = r_align_icon,
				split_pattern = "=",
				category = "scripting",
				lang = "r",
				filetypes = { "r", "rmd" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("r", "r_named")
		align_registry.mark_language_loaded("r")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("r", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("r_named"), {
			desc = r_align_icon .. "  Align R named",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the R-specific
-- parts (servers, parsers, filetype extensions, buffer options).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for R                      │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts fn (server added only if R executable) │
-- │ mason.nvim         │ opts fn (tool added only if R executable)   │
-- │ nvim-treesitter    │ opts merge (parsers always ensured)         │
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- Conditional loading:
-- • LSP server and Mason tool are only configured when the `R`
--   executable is found in PATH. This prevents errors on systems
--   where R is not installed but the language is enabled in settings.
-- • Treesitter parsers are always installed (lightweight, no runtime
--   dependency on R).
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for R
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- r_language_server: completions, diagnostics, rich documentation,
	-- code actions, and formatting via the languageserver R package.
	-- Only configured when R is available in PATH.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = function(_, opts)
			if not has_executable("R") then return end

			opts.servers = opts.servers or {}
			opts.servers.r_language_server = {
				settings = {
					r = {
						lsp = {
							rich_documentation = true,
							diagnostics = true,
						},
					},
				},
			}
		end,
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					r = "r",
					R = "r",
					rmd = "rmd",
					Rmd = "rmd",
					qmd = "rmd",
					Rprofile = "r",
					Renviron = "r",
				},
				filename = {
					[".Rprofile"] = "r",
					[".Renviron"] = "r",
				},
			})

			-- ── Buffer-local options for R / R Markdown files ────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "r", "rmd" },
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

					opt.commentstring = "# %s"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures r-languageserver is installed via Mason, but only when
	-- the R executable is available (avoids install errors).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = function(_, opts)
			if not has_executable("R") then return end
			opts.ensure_installed = opts.ensure_installed or {}
			vim.list_extend(opts.ensure_installed, { "r-languageserver" })
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- r:      syntax highlighting, folding, text objects
	-- rnoweb: Sweave (.Rnw) document support
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"r",
				"rnoweb",
			},
		},
	},
}
