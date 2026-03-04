---@file lua/langs/elm.lua
---@description Elm — LSP, formatter, treesitter & buffer-local keymaps
---@module "langs.elm"
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
---@see langs.elixir             Elixir language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/elm.lua — Elm language support                                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("elm") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "elm"):                      │    ║
--- ║  │  ├─ LSP          elmls (Elm Language Server — completions,       │    ║
--- ║  │  │                       diagnostics, go-to-definition)          │    ║
--- ║  │  ├─ Formatter    elm-format (opinionated, via conform.nvim)      │    ║
--- ║  │  ├─ Linter       elm-review (via keymap, not nvim-lint)          │    ║
--- ║  │  ├─ Treesitter   elm parser                                      │    ║
--- ║  │  ├─ DAP          — (not applicable for Elm)                      │    ║
--- ║  │  └─ Extras       elm reactor (dev server with hot-reload)        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ MAKE      r  elm make              R  elm make --optimize    │    ║
--- ║  │  ├─ REPL      c  elm repl                                        │    ║
--- ║  │  ├─ TEST      t  elm-test                                        │    ║
--- ║  │  ├─ REACTOR   p  Start elm reactor     e  Open in browser        │    ║
--- ║  │  ├─ PACKAGES  i  Install package       d  Package diff           │    ║
--- ║  │  │            s  elm init (new project)                          │    ║
--- ║  │  ├─ REVIEW    l  elm-review                                      │    ║
--- ║  │  └─ DOCS      h  Documentation (browser, contextual search)      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Tool resolution:                                                │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  elm-test:   elm-test (global) → npx elm-test (local)    │    │    ║
--- ║  │  │  elm-review: elm-review (global) → npx elm-review (local)│    │    ║
--- ║  │  │  Both fallback to npx for project-local installations    │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType elm):                               ║
--- ║  • colorcolumn=80, textwidth=80   (Elm community convention)             ║
--- ║  • tabstop=4, shiftwidth=4        (Elm standard indentation)             ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • commentstring="-- %s"          (Haskell-style line comments)          ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .elm → elm                                                            ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Elm support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("elm") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Elm Nerd Font icon (trailing whitespace stripped)
local elm_icon = icons.lang.elm:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Elm buffers.
-- The group is buffer-local and only visible when filetype == "elm".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("elm", "Elm", elm_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the elm binary is available in PATH.
---
--- Notifies the user with an error and installation instructions
--- if elm is not found.
---
--- ```lua
--- if not check_elm() then return end
--- ```
---
---@return boolean available `true` if `elm` is executable, `false` otherwise
---@private
local function check_elm()
	if vim.fn.executable("elm") ~= 1 then
		vim.notify("elm not found — install: npm install -g elm", vim.log.levels.ERROR, { title = "Elm" })
		return false
	end
	return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — MAKE / BUILD
--
-- Elm compilation via `elm make`. Supports both debug and optimized builds.
-- Output is written to `elm.js` in the current directory.
-- ═══════════════════════════════════════════════════════════════════════════

--- Compile the current file with `elm make`.
---
--- Saves the buffer, then runs `elm make <file> --output=elm.js`
--- in a terminal split. The output file can be included in an HTML
--- page or served by elm reactor.
keys.lang_map("elm", "n", "<leader>lr", function()
	if not check_elm() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("elm make " .. vim.fn.shellescape(file) .. " --output=elm.js")
end, { desc = icons.ui.Play .. " Elm make" })

--- Compile the current file with optimizations enabled.
---
--- Saves the buffer, then runs `elm make <file> --optimize --output=elm.js`.
--- The `--optimize` flag enables dead code elimination, minification
--- hints, and other production optimizations.
keys.lang_map("elm", "n", "<leader>lR", function()
	if not check_elm() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("elm make " .. vim.fn.shellescape(file) .. " --optimize --output=elm.js")
end, { desc = icons.ui.Play .. " Elm make --optimize" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
--
-- Opens the Elm REPL for interactive expression evaluation.
-- The REPL supports importing project modules and experimenting
-- with Elm expressions and types.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Elm REPL in a terminal split.
---
--- Runs `elm repl` which provides an interactive environment for
--- evaluating Elm expressions, importing modules, and exploring types.
keys.lang_map("elm", "n", "<leader>lc", function()
	if not check_elm() then return end
	vim.cmd.split()
	vim.cmd.terminal("elm repl")
end, { desc = icons.ui.Terminal .. " Elm REPL" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via elm-test. Supports both global and project-local
-- installations via npx fallback.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the test suite with elm-test.
---
--- Tool resolution:
--- 1. `elm-test` — globally installed (highest priority)
--- 2. `npx elm-test` — project-local via npx
--- 3. Notification with install instructions if neither found
keys.lang_map("elm", "n", "<leader>lt", function()
	---@type string|nil
	local cmd
	if vim.fn.executable("elm-test") == 1 then
		cmd = "elm-test"
	elseif vim.fn.executable("npx") == 1 then
		cmd = "npx elm-test"
	else
		vim.notify("Install: npm install -g elm-test", vim.log.levels.WARN, { title = "Elm" })
		return
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.dev.Test .. " Elm test" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REACTOR / DEV SERVER
--
-- Elm reactor provides a development server with hot-reload and
-- time-travel debugging capabilities at http://localhost:8000.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start Elm reactor (development server with hot-reload).
---
--- Launches `elm reactor` in a terminal split and notifies the user
--- with the server URL (http://localhost:8000).
keys.lang_map("elm", "n", "<leader>lp", function()
	if not check_elm() then return end
	vim.cmd.split()
	vim.cmd.terminal("elm reactor")
	vim.notify("Elm Reactor at http://localhost:8000", vim.log.levels.INFO, { title = "Elm" })
end, { desc = elm_icon .. " Elm reactor" })

--- Open the current file in Elm reactor via the system browser.
---
--- Constructs the URL from the file's relative path and opens it
--- at `http://localhost:8000/<relative-path>`. Requires elm reactor
--- to be already running.
keys.lang_map("elm", "n", "<leader>le", function()
	local rel = vim.fn.expand("%:.")
	local url = "http://localhost:8000/" .. rel
	vim.ui.open(url)
	vim.notify("Opening: " .. url, vim.log.levels.INFO, { title = "Elm" })
end, { desc = elm_icon .. " Open in browser" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — PACKAGE MANAGEMENT
--
-- Elm package installation, diff inspection, and project initialization.
-- ═══════════════════════════════════════════════════════════════════════════

--- Install an Elm package.
---
--- Prompts for a package name (e.g. `elm/json`, `elm/http`), then runs
--- `elm install <package>` in a terminal split.
keys.lang_map("elm", "n", "<leader>li", function()
	if not check_elm() then return end
	vim.ui.input({ prompt = "Package (e.g. elm/json): " }, function(pkg)
		if not pkg or pkg == "" then return end
		vim.cmd.split()
		vim.cmd.terminal("elm install " .. vim.fn.shellescape(pkg))
	end)
end, { desc = icons.ui.Package .. " Install package" })

--- Show the API diff for a package between versions.
---
--- Prompts for a package name, then runs `elm diff <package>` in a
--- terminal split to display additions, removals, and changes.
keys.lang_map("elm", "n", "<leader>ld", function()
	if not check_elm() then return end
	vim.ui.input({ prompt = "Package (e.g. elm/core): " }, function(pkg)
		if not pkg or pkg == "" then return end
		vim.cmd.split()
		vim.cmd.terminal("elm diff " .. vim.fn.shellescape(pkg))
	end)
end, { desc = elm_icon .. " Package diff" })

--- Initialize a new Elm project with `elm init`.
---
--- Creates an `elm.json` file in the current directory. Warns the user
--- if an `elm.json` already exists to prevent accidental overwrite.
keys.lang_map("elm", "n", "<leader>ls", function()
	if not check_elm() then return end
	if vim.fn.filereadable("elm.json") == 1 then
		vim.notify("elm.json already exists", vim.log.levels.INFO, { title = "Elm" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("elm init")
end, { desc = elm_icon .. " Elm init" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REVIEW / LINT
--
-- Static analysis via elm-review. Supports both global and project-local
-- installations via npx fallback.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run elm-review static analysis on the project.
---
--- Tool resolution:
--- 1. `elm-review` — globally installed (highest priority)
--- 2. `npx elm-review` — project-local via npx
--- 3. Notification with install instructions if neither found
keys.lang_map("elm", "n", "<leader>ll", function()
	---@type string|nil
	local cmd
	if vim.fn.executable("elm-review") == 1 then
		cmd = "elm-review"
	elseif vim.fn.executable("npx") == 1 then
		cmd = "npx elm-review"
	else
		vim.notify("Install: npm install -g elm-review", vim.log.levels.WARN, { title = "Elm" })
		return
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = elm_icon .. " Elm review" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to Elm documentation and package search via the system
-- browser. Supports contextual search for the word under cursor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open Elm documentation in the system browser.
---
--- If the cursor is on a word, adds a contextual "Search: <word>"
--- entry at the top of the picker that searches the Elm package
--- registry for matching packages or modules.
---
--- Static entries:
--- • Elm Guide         — official language tutorial
--- • Elm Packages      — package registry
--- • Elm Core Docs     — core library documentation
--- • Elm Syntax Reference — language syntax cheatsheet
keys.lang_map("elm", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")

	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Elm Guide", url = "https://guide.elm-lang.org/" },
		{ name = "Elm Packages", url = "https://package.elm-lang.org/" },
		{ name = "Elm Core Docs", url = "https://package.elm-lang.org/packages/elm/core/latest/" },
		{ name = "Elm Syntax Reference", url = "https://elm-lang.org/docs/syntax" },
	}

	if word ~= "" then
		table.insert(refs, 1, {
			name = "Search: " .. word,
			url = "https://package.elm-lang.org/?q=" .. word,
		})
	end

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = elm_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Elm-specific alignment presets for mini.align:
-- • elm_record — align record field definitions on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("elm") then
		---@type string Alignment preset icon from icons.lang
		local align_icon = icons.lang.elm

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			elm_record = {
				description = "Align Elm record fields on '='",
				icon = align_icon,
				split_pattern = "=",
				category = "functional",
				lang = "elm",
				filetypes = { "elm" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("elm", "elm_record")
		align_registry.mark_language_loaded("elm")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("elm", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("elm_record"), {
			desc = align_icon .. "  Align Elm record",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Elm-specific
-- parts (servers, formatters, parsers).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for Elm                    │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig                         │ opts merge (elmls server added on require)   │
-- │ mason.nvim                             │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim                           │ opts merge (elm_format for ft elm)           │
-- │ nvim-treesitter                        │ opts merge (elm parser added)                │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Linting is handled via elm-review keymap rather than nvim-lint
-- because elm-review requires project-specific rule configuration
-- (review/src/ReviewConfig.elm) and is best run as a full-project tool.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Elm
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- elmls: Elm Language Server providing completions, diagnostics,
	-- go-to-definition, find-references, and rename support.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				elmls = {},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					elm = "elm",
				},
			})

			-- ── Buffer-local options for Elm files ───────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "elm" },
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
					opt.commentstring = "-- %s"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures elm-language-server and elm-format are installed via Mason.
	-- elm-format is the community-standard opinionated formatter.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"elm-language-server",
				"elm-format",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- elm-format: the official Elm formatter. Enforces a single canonical
	-- style with no configuration options (similar to gofmt / ormolu).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				elm = { "elm_format" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- elm: syntax highlighting, folding, text objects and indentation
	--      for Elm source files (.elm).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"elm",
			},
		},
	},
}
