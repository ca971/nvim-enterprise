---@file lua/langs/twig.lua
---@description Twig — LSP, formatter, linter, treesitter & buffer-local keymaps
---@module "langs.twig"
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
--- ║  langs/twig.lua — Twig template engine support                           ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("twig") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "twig"):                     │    ║
--- ║  │  ├─ LSP          none (filetype detection + buffer options only) │    ║
--- ║  │  ├─ Formatter    djlint (via conform.nvim, --profile=jinja)      │    ║
--- ║  │  ├─ Linter       djlint (via nvim-lint, --profile=jinja)         │    ║
--- ║  │  ├─ Treesitter   twig · html parsers                             │    ║
--- ║  │  └─ Extras       block navigation · extends/includes browser ·   │    ║
--- ║  │                  wrap in block · Symfony integration · stats     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ LINT      l  Lint (djlint --profile=jinja)                   │    ║
--- ║  │  │            t  Lint (twigcs, Symfony-specific)                 │    ║
--- ║  │  ├─ FORMAT    f  Format (djlint --reformat)                      │    ║
--- ║  │  ├─ NAVIGATE  b  List blocks (jump to definition)                │    ║
--- ║  │  │            e  List extends/includes/embeds (jump to ref)      │    ║
--- ║  │  ├─ EDIT      w  Wrap line/selection in {% block %} (n + v)      │    ║
--- ║  │  ├─ SYMFONY   s  Symfony commands picker (5 actions)             │    ║
--- ║  │  ├─ STATS     i  Template statistics (blocks, includes, vars)    │    ║
--- ║  │  └─ DOCS      h  Documentation browser (Twig docs, tags,         │    ║
--- ║  │                  filters, functions, Symfony templates)          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Symfony console auto-detection:                                 │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. bin/console exists  → php bin/console (Symfony 3+)   │    │    ║
--- ║  │  │  2. app/console exists  → php app/console (Symfony 2)    │    │    ║
--- ║  │  │  3. nil                 → "Not a Symfony project"        │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Block navigation:                                               │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Scans all lines for {% block <name> %} tags.            │    │    ║
--- ║  │  │  Presents block names with line numbers via vim.ui.select│    │    ║
--- ║  │  │  Selection jumps to the block definition and centers.    │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Template reference scanning:                                    │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Scans for {% extends %}, {% include %}, {% embed %}     │    │    ║
--- ║  │  │  Presents references with type, name, and line number.   │    │    ║
--- ║  │  │  Selection jumps to the reference and centers.           │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType twig):                              ║
--- ║  • colorcolumn=120, textwidth=120  (template line length)                ║
--- ║  • tabstop=2, shiftwidth=2         (2-space indentation)                 ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="{# %s #}"       (Twig comment syntax)                  ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .twig            → twig                                               ║
--- ║  • *.html.twig      → twig (Symfony convention)                          ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Twig support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("twig") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Twig Nerd Font icon (trailing whitespace stripped)
local twig_icon = icons.lang.twig:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Twig buffers.
-- The group is buffer-local and only visible when filetype == "twig".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("twig", "Twig", twig_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that djlint is available in PATH.
---
--- Notifies the user with install instructions if `djlint` is not found.
--- Used as a guard in lint and format keymaps.
---
---@return boolean available `true` if `djlint` is executable
---@private
local function check_djlint()
	if vim.fn.executable("djlint") ~= 1 then
		vim.notify("Install: pip install djlint", vim.log.levels.WARN, { title = "Twig" })
		return false
	end
	return true
end

--- Detect the Symfony console binary for the current project.
---
--- Resolution order:
--- 1. `bin/console` in CWD → `"php bin/console"` (Symfony 3+)
--- 2. `app/console` in CWD → `"php app/console"` (Symfony 2)
--- 3. `nil` → not a Symfony project
---
---@return string|nil console The console command, or `nil` if not found
---@private
local function detect_symfony_console()
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/bin/console") == 1 then
		return "php bin/console"
	elseif vim.fn.filereadable(cwd .. "/app/console") == 1 then
		return "php app/console"
	end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — LINT / FORMAT
--
-- Template linting and formatting via djlint and twigcs.
-- djlint uses `--profile=jinja` for Twig/Jinja2 compatibility.
-- twigcs is a Symfony-specific Twig coding standards checker.
-- ═══════════════════════════════════════════════════════════════════════════

--- Lint the current Twig file with djlint.
---
--- Runs `djlint --profile=jinja` which checks for template
--- syntax errors, best practices, and accessibility issues.
--- Output appears in a terminal split.
keys.lang_map("twig", "n", "<leader>ll", function()
	if not check_djlint() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("djlint " .. vim.fn.shellescape(file) .. " --profile=jinja")
end, { desc = twig_icon .. " Lint (djlint)" })

--- Format the current Twig file with djlint.
---
--- Saves the buffer, runs `djlint --reformat --profile=jinja`
--- in-place, then reloads the buffer. Reports success or error
--- via notifications.
keys.lang_map("twig", "n", "<leader>lf", function()
	if not check_djlint() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("djlint " .. vim.fn.shellescape(file) .. " --reformat --profile=jinja 2>&1")
	vim.cmd.edit()

	if vim.v.shell_error == 0 then
		vim.notify("Formatted", vim.log.levels.INFO, { title = "Twig" })
	else
		vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "Twig" })
	end
end, { desc = twig_icon .. " Format (djlint)" })

--- Lint the current Twig file with twigcs.
---
--- Runs `twigcs` which checks the file against Symfony's Twig
--- coding standards. Requires `twigcs` to be installed globally
--- via Composer (notifies with install instructions if not found).
keys.lang_map("twig", "n", "<leader>lt", function()
	if vim.fn.executable("twigcs") ~= 1 then
		vim.notify("Install: composer global require friendsoftwig/twigcs", vim.log.levels.WARN, { title = "Twig" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("twigcs " .. vim.fn.shellescape(file))
end, { desc = twig_icon .. " Twigcs lint" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEMPLATE ANALYSIS
--
-- Template structure navigation: block listing and template reference
-- scanning. Both use line-by-line pattern matching to find Twig tags
-- and present results in a selection picker with jump-to-definition.
-- ═══════════════════════════════════════════════════════════════════════════

--- List all blocks defined in the current template.
---
--- Scans the buffer for `{% block <name> %}` tags, collects block
--- names with line numbers, and presents them via `vim.ui.select()`.
--- Selecting a block jumps to its definition and centers the view.
---
--- Notifies the user if no blocks are found.
keys.lang_map("twig", "n", "<leader>lb", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	---@type { name: string, lnum: integer }[]
	local blocks = {}
	for i, line in ipairs(lines) do
		---@type string|nil
		local block_name = line:match("{%%%s*block%s+(%w+)")
		if block_name then blocks[#blocks + 1] = { name = block_name, lnum = i } end
	end

	if #blocks == 0 then
		vim.notify("No blocks found", vim.log.levels.INFO, { title = "Twig" })
		return
	end

	vim.ui.select(
		vim.tbl_map(function(b)
			return string.format("%-20s (L%d)", b.name, b.lnum)
		end, blocks),
		{ prompt = twig_icon .. " Blocks:" },
		function(_, idx)
			if not idx then return end
			vim.api.nvim_win_set_cursor(0, { blocks[idx].lnum, 0 })
			vim.cmd("normal! zz")
		end
	)
end, { desc = twig_icon .. " List blocks" })

--- List all template references (extends, includes, embeds).
---
--- Scans the buffer for:
--- - `{% extends "template" %}` — parent template inheritance
--- - `{% include "template" %}` — template inclusion
--- - `{% embed "template" %}`   — template embedding
---
--- Presents references with type, template name, and line number.
--- Selecting a reference jumps to its line and centers the view.
keys.lang_map("twig", "n", "<leader>le", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	---@type { type: string, name: string, lnum: integer }[]
	local refs = {}
	for i, line in ipairs(lines) do
		-- ── extends ──────────────────────────────────────────────
		local extends = line:match("{%%%s*extends%s+['\"](.-)['\"']")
		if extends then refs[#refs + 1] = { type = "extends", name = extends, lnum = i } end

		-- ── includes ─────────────────────────────────────────────
		for include in line:gmatch("{%%%s*include%s+['\"](.-)['\"']") do
			refs[#refs + 1] = { type = "include", name = include, lnum = i }
		end

		-- ── embeds ───────────────────────────────────────────────
		for embed in line:gmatch("{%%%s*embed%s+['\"](.-)['\"']") do
			refs[#refs + 1] = { type = "embed", name = embed, lnum = i }
		end
	end

	if #refs == 0 then
		vim.notify("No extends/includes found", vim.log.levels.INFO, { title = "Twig" })
		return
	end

	vim.ui.select(
		vim.tbl_map(function(r)
			return string.format("[%s] %s (L%d)", r.type, r.name, r.lnum)
		end, refs),
		{ prompt = twig_icon .. " References:" },
		function(_, idx)
			if not idx then return end
			vim.api.nvim_win_set_cursor(0, { refs[idx].lnum, 0 })
			vim.cmd("normal! zz")
		end
	)
end, { desc = twig_icon .. " Extends/includes" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — WRAP IN BLOCK
--
-- Wraps the current line (normal mode) or selection (visual mode)
-- in a `{% block <name> %}` / `{% endblock %}` pair.
-- Prompts for the block name before wrapping.
-- ═══════════════════════════════════════════════════════════════════════════

--- Wrap the current line in a Twig block (normal mode).
---
--- Prompts for a block name, then inserts `{% block <name> %}`
--- above and `{% endblock %}` below the current line, preserving
--- the original indentation.
keys.lang_map("twig", "n", "<leader>lw", function()
	vim.ui.input({ prompt = "Block name: " }, function(name)
		if not name or name == "" then return end

		---@type integer
		local row = vim.api.nvim_win_get_cursor(0)[1]
		local line = vim.api.nvim_get_current_line()
		---@type string
		local indent = line:match("^(%s*)") or ""

		---@type string[]
		local result = {
			indent .. "{% block " .. name .. " %}",
			line,
			indent .. "{% endblock %}",
		}
		vim.api.nvim_buf_set_lines(0, row - 1, row, false, result)
	end)
end, { desc = twig_icon .. " Wrap in block" })

--- Wrap the visual selection in a Twig block (visual mode).
---
--- Prompts for a block name, then wraps the selected lines with
--- `{% block <name> %}` / `{% endblock %}`, indenting the original
--- content by 2 spaces.
keys.lang_map("twig", "v", "<leader>lw", function()
	vim.ui.input({ prompt = "Block name: " }, function(name)
		if not name or name == "" then return end

		---@type integer
		local start_row = vim.fn.line("'<") - 1
		---@type integer
		local end_row = vim.fn.line("'>")
		local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row, false)
		---@type string
		local indent = (lines[1] or ""):match("^(%s*)") or ""

		---@type string[]
		local result = { indent .. "{% block " .. name .. " %}" }
		for _, l in ipairs(lines) do
			result[#result + 1] = "  " .. l
		end
		result[#result + 1] = indent .. "{% endblock %}"

		vim.api.nvim_buf_set_lines(0, start_row, end_row, false, result)
	end)
end, { desc = twig_icon .. " Wrap in block" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SYMFONY
--
-- Symfony framework integration via the console binary.
-- Auto-detects the console location (bin/console or app/console).
-- Provides a picker with 5 common Symfony commands related to Twig.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Symfony commands picker.
---
--- Auto-detects the Symfony console binary, then presents 5
--- commands related to Twig development:
--- - `debug:twig`      — show registered Twig extensions/filters
--- - `cache:clear`     — clear the Symfony cache
--- - `lint:twig`       — lint all templates in `templates/`
--- - `debug:router`    — show registered routes
--- - `debug:container` — show registered services
---
--- Notifies the user if no Symfony console is found.
keys.lang_map("twig", "n", "<leader>ls", function()
	local console = detect_symfony_console()
	if not console then
		vim.notify("Not a Symfony project (bin/console not found)", vim.log.levels.INFO, { title = "Twig" })
		return
	end

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "debug:twig", cmd = console .. " debug:twig" },
		{ name = "cache:clear", cmd = console .. " cache:clear" },
		{ name = "twig:lint", cmd = console .. " lint:twig templates/" },
		{ name = "debug:router", cmd = console .. " debug:router" },
		{ name = "debug:container", cmd = console .. " debug:container" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = twig_icon .. " Symfony:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = twig_icon .. " Symfony commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — STATS / DOCUMENTATION
--
-- Template statistics and external documentation access.
-- Stats are computed by parsing the buffer with pattern matching.
-- Documentation links open in the system browser via `vim.ui.open()`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Display template statistics for the current Twig file.
---
--- Parses the current buffer line-by-line to count:
--- - **Lines**: total line count
--- - **Blocks**: `{% block ... %}` tags
--- - **Includes**: `{% include ... %}` tags
--- - **Extends**: `{% extends ... %}` presence (✓ / ✗)
--- - **Variables**: `{{ ... }}` expressions
--- - **Filters**: `| filter_name` pipe expressions
---
--- Results are displayed in a notification popup.
keys.lang_map("twig", "n", "<leader>li", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	---@type integer
	local blocks = 0
	---@type integer
	local includes = 0
	---@type integer
	local extends = 0
	---@type integer
	local filters = 0
	---@type integer
	local vars = 0

	for _, line in ipairs(lines) do
		if line:match("{%%%s*block%s") then blocks = blocks + 1 end
		if line:match("{%%%s*include%s") then includes = includes + 1 end
		if line:match("{%%%s*extends%s") then extends = extends + 1 end
		for _ in line:gmatch("{{.-}}") do
			vars = vars + 1
		end
		for _ in line:gmatch("|%s*%w+") do
			filters = filters + 1
		end
	end

	vim.notify(
		string.format(
			"%s Template Stats:\n"
				.. "  Lines:     %d\n"
				.. "  Blocks:    %d\n"
				.. "  Includes:  %d\n"
				.. "  Extends:   %s\n"
				.. "  Variables: %d\n"
				.. "  Filters:   %d",
			twig_icon,
			#lines,
			blocks,
			includes,
			extends > 0 and "✓" or "✗",
			vars,
			filters
		),
		vim.log.levels.INFO,
		{ title = "Twig" }
	)
end, { desc = icons.diagnostics.Info .. " Stats" })

--- Open Twig documentation in the system browser.
---
--- Presents a selection menu with links to key Twig and Symfony
--- template documentation resources.
---
--- Available documentation links:
--- - Twig Docs (main documentation)
--- - Twig Tags (block, extends, include, etc.)
--- - Twig Filters (escape, date, raw, etc.)
--- - Twig Functions (dump, include, etc.)
--- - Symfony Templates (Symfony-specific Twig integration)
keys.lang_map("twig", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Twig Docs", url = "https://twig.symfony.com/doc/3.x/" },
		{ name = "Twig Tags", url = "https://twig.symfony.com/doc/3.x/tags/index.html" },
		{ name = "Twig Filters", url = "https://twig.symfony.com/doc/3.x/filters/index.html" },
		{ name = "Twig Functions", url = "https://twig.symfony.com/doc/3.x/functions/index.html" },
		{ name = "Symfony Templates", url = "https://symfony.com/doc/current/templates.html" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = twig_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Twig-specific alignment presets for mini.align:
-- • twig_vars — align template variable assignments on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("twig") then
		---@type string Alignment preset icon from icons.lang
		local twig_align_icon = icons.lang.twig

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			twig_vars = {
				description = "Align Twig template variables on '='",
				icon = twig_align_icon,
				split_pattern = "=",
				category = "web",
				lang = "twig",
				filetypes = { "twig" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("twig", "twig_vars")
		align_registry.mark_language_loaded("twig")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("twig", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("twig_vars"), {
			desc = twig_align_icon .. "  Align Twig vars",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Twig-specific
-- parts (filetype detection, formatters, linters, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Twig                   │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ init only (filetype + buffer options)       │
-- │ mason.nvim         │ opts merge (djlint ensured)                 │
-- │ conform.nvim       │ opts merge (djlint with jinja profile)     │
-- │ nvim-lint          │ opts merge (djlint for twig)               │
-- │ nvim-treesitter    │ opts merge (twig + html parsers)            │
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- Notable omissions:
-- • No Twig-specific LSP server is configured. The nvim-lspconfig spec
--   provides filetype detection and buffer options only. Consider
--   twiggy-language-server if a Twig LS becomes stable.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Twig
return {
	-- ── FILETYPE + BUFFER OPTIONS ──────────────────────────────────────────
	-- nvim-lspconfig is used here ONLY for filetype registration and
	-- buffer-local options. No Twig LSP server is configured.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					twig = "twig",
				},
				pattern = {
					[".*%.html%.twig$"] = "twig",
				},
			})

			-- ── Buffer-local options for Twig files ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "twig" },
				callback = function()
					local opt = vim.opt_local

					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120

					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true

					opt.number = true
					opt.relativenumber = true

					opt.commentstring = "{# %s #}"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures djlint is installed via Mason.
	-- djlint serves as both linter and formatter for Twig templates.
	-- NOTE: twigcs is NOT available via Mason — install via Composer.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"djlint",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- djlint as formatter with --profile=jinja for Twig/Jinja2 compat.
	-- The --reformat flag is added via prepend_args.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				twig = { "djlint" },
			},
			formatters = {
				djlint = {
					prepend_args = { "--profile=jinja", "--reformat" },
				},
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- djlint as linter via nvim-lint.
	-- Checks for template syntax errors, best practices, and
	-- accessibility issues.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				twig = { "djlint" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- twig: Twig template syntax (tags, filters, expressions)
	-- html:  HTML structure within Twig templates
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"twig",
				"html",
			},
		},
	},
}
