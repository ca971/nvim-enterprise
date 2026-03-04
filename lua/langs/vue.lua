---@file lua/langs/vue.lua
---@description Vue.js — LSP, formatter, linter, treesitter, DAP & buffer-local keymaps
---@module "langs.vue"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.typescript         TypeScript language support (shared DAP adapter)
---@see langs.python             Python language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/vue.lua — Vue.js language support                                 ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("vue") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "vue"):                      │    ║
--- ║  │  ├─ LSP          vue_ls       (vue-language-server, hybridMode)  │    ║
--- ║  │  ├─ Formatter    prettier     (opinionated code formatter)       │    ║
--- ║  │  ├─ Linter       eslint_d     (fast ESLint daemon)               │    ║
--- ║  │  ├─ Treesitter   vue parser                                      │    ║
--- ║  │  └─ DAP          js-debug-adapter (shared with TypeScript)       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ DEV       r  Dev server              R  Build                │    ║
--- ║  │  │            p  Preview                                         │    ║
--- ║  │  ├─ TEST      t  Test (vitest)                                   │    ║
--- ║  │  ├─ CHECK     s  Type check (vue-tsc)    l  Lint (eslint)        │    ║
--- ║  │  ├─ DEBUG     d  Debug (DAP continue)                            │    ║
--- ║  │  ├─ COMMANDS  c  Vue/Nuxt command picker                         │    ║
--- ║  │  │            n  Nuxt DevTools (browser)                         │    ║
--- ║  │  └─ DOCS      i  Package info            h  Documentation picker │    ║
--- ║  │                                                                  │    ║
--- ║  │  Nuxt detection:                                                 │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  is_nuxt() scans CWD for nuxt.config.{ts,js}             │    │    ║
--- ║  │  │  When detected:                                          │    │    ║
--- ║  │  │  • Type check uses `<pm> run typecheck` (Nuxt CLI)       │    │    ║
--- ║  │  │  • Command picker adds nuxi commands (generate, prepare, │    │    ║
--- ║  │  │    analyze, cleanup, upgrade, add module)                │    │    ║
--- ║  │  │  • <leader>ln opens Nuxt DevTools in browser             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Package manager auto-detection:                                 │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. bun.lockb        → bun                               │    │    ║
--- ║  │  │  2. pnpm-lock.yaml   → pnpm                              │    │    ║
--- ║  │  │  3. yarn.lock        → yarn                              │    │    ║
--- ║  │  │  4. fallback         → npm                               │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType vue):                               ║
--- ║  • colorcolumn=100, textwidth=100  (common Vue/TS project line length)   ║
--- ║  • tabstop=2, shiftwidth=2         (standard Vue/TS indentation)         ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .vue → vue                                                            ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Vue support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("vue") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Vue Nerd Font icon (trailing whitespace stripped)
local vue_icon = icons.lang.vue:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Vue buffers.
-- The group is buffer-local and only visible when filetype == "vue".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("vue", "Vue", vue_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the project's package manager from its lockfile.
---
--- Scans the current working directory for lockfiles and returns
--- the matching package manager command.
---
--- Resolution order:
--- 1. `bun.lockb`       → bun
--- 2. `pnpm-lock.yaml`  → pnpm
--- 3. `yarn.lock`       → yarn
--- 4. fallback          → npm
---
--- ```lua
--- local pm = pkg_runner()   -- "bun" | "pnpm" | "yarn" | "npm"
--- ```
---
---@return string pm Package manager command name
---@private
local function pkg_runner()
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/bun.lockb") == 1 then return "bun" end
	if vim.fn.filereadable(cwd .. "/pnpm-lock.yaml") == 1 then return "pnpm" end
	if vim.fn.filereadable(cwd .. "/yarn.lock") == 1 then return "yarn" end
	return "npm"
end

--- Build a package manager `run` command string for a named script.
---
--- Prepends the detected package manager to `run <script>`, producing
--- commands like `pnpm run dev`, `bun run build`, etc.
---
--- ```lua
--- run_script("dev")     -- → "pnpm run dev"  (if pnpm detected)
--- run_script("build")   -- → "npm run build"  (fallback)
--- ```
---
---@param script string Name of the npm/package.json script to run
---@return string cmd Full shell command to execute the script
---@private
local function run_script(script)
	return pkg_runner() .. " run " .. script
end

--- Detect whether the current project is a Nuxt application.
---
--- Scans the current working directory for `nuxt.config.ts` or
--- `nuxt.config.js`. When detected, additional Nuxt-specific
--- commands and keymaps become available.
---
--- ```lua
--- if is_nuxt() then
---   vim.cmd.terminal(runner .. " exec nuxi generate")
--- end
--- ```
---
---@return boolean is_nuxt `true` if a Nuxt config file exists in CWD
---@private
local function is_nuxt()
	local cwd = vim.fn.getcwd()
	return vim.fn.filereadable(cwd .. "/nuxt.config.ts") == 1 or vim.fn.filereadable(cwd .. "/nuxt.config.js") == 1
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEV / BUILD
--
-- Project development server, build, and preview commands.
-- All keymaps open a terminal split for output.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start the Vue/Nuxt development server.
---
--- Runs `<pm> run dev` in a terminal split. Supports hot-module
--- replacement (HMR) for instant feedback during development.
keys.lang_map("vue", "n", "<leader>lr", function()
	vim.cmd.split()
	vim.cmd.terminal(run_script("dev"))
end, { desc = icons.ui.Play .. " Dev server" })

--- Build the project for production.
---
--- Runs `<pm> run build` in a terminal split. Produces optimised
--- output in `dist/` (Vite) or `.output/` (Nuxt).
keys.lang_map("vue", "n", "<leader>lR", function()
	vim.cmd.split()
	vim.cmd.terminal(run_script("build"))
end, { desc = icons.dev.Build .. " Build" })

--- Preview the production build locally.
---
--- Runs `<pm> run preview` in a terminal split. Serves the built
--- output on a local HTTP server for final verification before
--- deployment.
keys.lang_map("vue", "n", "<leader>lp", function()
	vim.cmd.split()
	vim.cmd.terminal(run_script("preview"))
end, { desc = vue_icon .. " Preview" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution via the project's configured test runner (vitest).
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the full test suite.
---
--- Saves the buffer, then runs `<pm> run test` in a terminal split.
--- Expects the `test` script to be defined in `package.json` (typically
--- wired to vitest or jest).
keys.lang_map("vue", "n", "<leader>lt", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(run_script("test"))
end, { desc = icons.dev.Test .. " Test" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CHECK & LINT
--
-- Static type-checking and linting commands.
-- Type checking adapts to Nuxt vs plain Vue projects automatically.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run type-checking on the project.
---
--- Adapts the command to the project type:
--- - Nuxt project → `<pm> run typecheck` (uses Nuxt's built-in check)
--- - Plain Vue    → `<pm> exec vue-tsc --noEmit` (direct vue-tsc)
---
--- Saves the buffer before execution.
keys.lang_map("vue", "n", "<leader>ls", function()
	vim.cmd("silent! write")
	local runner = pkg_runner()
	vim.cmd.split()
	if is_nuxt() then
		vim.cmd.terminal(runner .. " run typecheck")
	else
		vim.cmd.terminal(runner .. " exec vue-tsc --noEmit")
	end
end, { desc = icons.ui.Check .. " Type check" })

--- Run the project's lint script.
---
--- Saves the buffer, then runs `<pm> run lint` in a terminal split.
--- Expects the `lint` script to be defined in `package.json` (typically
--- wired to eslint with Vue plugin).
keys.lang_map("vue", "n", "<leader>ll", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(run_script("lint"))
end, { desc = vue_icon .. " Lint" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via nvim-dap and js-debug-adapter.
--
-- <leader>ld starts or continues a debug session. The adapter
-- (js-debug-adapter / pwa-node / pwa-chrome) is auto-configured by
-- mason-nvim-dap. Shares the same adapter as langs/typescript.lua.
-- Both <leader>ld (lang) and <leader>dc (core dap) work in Vue files.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session.
---
--- Saves the buffer, then calls `dap.continue()` which either resumes
--- a paused session or launches a new one using the js-debug adapter.
keys.lang_map("vue", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Vue" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (js)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — COMMANDS
--
-- Command picker presenting all available Vue / Nuxt project commands
-- in a unified `vim.ui.select()` menu. Nuxt-specific commands are
-- appended dynamically when a Nuxt config file is detected.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a unified command picker for Vue / Nuxt operations.
---
--- Presents a `vim.ui.select()` menu with:
--- - Common scripts: dev, build, preview, lint, format, test
--- - Package management: install, update, outdated
--- - Nuxt-only (when detected): nuxi generate, prepare, analyze,
---   cleanup, upgrade, add module
---
--- Actions with `prompt = true` ask for additional input (e.g.
--- module name for `nuxi module add`).
---
---@see is_nuxt Nuxt project detection
keys.lang_map("vue", "n", "<leader>lc", function()
	local runner = pkg_runner()

	---@class VueAction
	---@field name string Display label for the action
	---@field cmd string Shell command to execute
	---@field prompt? boolean Whether to prompt for additional input

	---@type VueAction[]
	local actions = {
		{ name = "dev", cmd = run_script("dev") },
		{ name = "build", cmd = run_script("build") },
		{ name = "preview", cmd = run_script("preview") },
		{ name = "lint", cmd = run_script("lint") },
		{ name = "lint:fix", cmd = run_script("lint:fix") },
		{ name = "format", cmd = run_script("format") },
		{ name = "test:unit", cmd = run_script("test:unit") },
		{ name = "test:e2e", cmd = run_script("test:e2e") },
		{ name = "type-check", cmd = run_script("type-check") },
		{ name = runner .. " install", cmd = runner .. " install" },
		{ name = runner .. " update", cmd = runner .. " update" },
		{ name = runner .. " outdated", cmd = runner .. " outdated" },
	}

	-- ── Append Nuxt-specific commands when detected ──────────────
	if is_nuxt() then
		---@type VueAction[]
		local nuxt_actions = {
			{ name = "nuxi generate", cmd = runner .. " exec nuxi generate" },
			{ name = "nuxi prepare", cmd = runner .. " exec nuxi prepare" },
			{ name = "nuxi analyze", cmd = runner .. " exec nuxi analyze" },
			{ name = "nuxi cleanup", cmd = runner .. " exec nuxi cleanup" },
			{ name = "nuxi upgrade", cmd = runner .. " exec nuxi upgrade" },
			{ name = "nuxi add module…", cmd = runner .. " exec nuxi module add", prompt = true },
		}
		for _, a in ipairs(nuxt_actions) do
			actions[#actions + 1] = a
		end
	end

	-- ── Present selection ────────────────────────────────────────
	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = vue_icon .. " Vue:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]
			if action.prompt then
				vim.ui.input({ prompt = "Name: " }, function(name)
					if not name or name == "" then return end
					vim.cmd.split()
					vim.cmd.terminal(action.cmd .. " " .. vim.fn.shellescape(name))
				end)
			else
				vim.cmd.split()
				vim.cmd.terminal(action.cmd)
			end
		end
	)
end, { desc = vue_icon .. " Commands" })

--- Open Nuxt DevTools in the default browser.
---
--- Only available in Nuxt projects (detected via `is_nuxt()`).
--- Opens `http://localhost:3000/__nuxt_devtools__/` which provides
--- component inspection, state management, and route debugging.
keys.lang_map("vue", "n", "<leader>ln", function()
	if not is_nuxt() then
		vim.notify("Not a Nuxt project", vim.log.levels.INFO, { title = "Vue" })
		return
	end
	vim.ui.open("http://localhost:3000/__nuxt_devtools__/")
end, { desc = vue_icon .. " Nuxt DevTools" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to Vue / Nuxt ecosystem documentation and project
-- metadata without leaving the editor.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show project information summary.
---
--- Displays a notification with:
--- - Nuxt detection status (✓ / ✗)
--- - Detected package manager
--- - Current working directory
keys.lang_map("vue", "n", "<leader>li", function()
	local info = {
		vue_icon .. " Vue Info:",
		"",
		"  Nuxt:   " .. (is_nuxt() and "✓" or "✗"),
		"  Runner: " .. pkg_runner(),
		"  CWD:    " .. vim.fn.getcwd(),
	}
	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Vue" })
end, { desc = icons.diagnostics.Info .. " Package info" })

--- Open Vue / Nuxt ecosystem documentation in the browser.
---
--- Presents a `vim.ui.select()` menu with links to:
--- - Vue 3 Guide & API Reference
--- - Nuxt 3 Docs
--- - Pinia (state management)
--- - Vue Router
--- - VueUse (composable utilities)
keys.lang_map("vue", "n", "<leader>lh", function()
	---@class VueDocRef
	---@field name string Display label for the documentation link
	---@field url string URL to open in the browser

	---@type VueDocRef[]
	local refs = {
		{ name = "Vue 3 Docs", url = "https://vuejs.org/guide/introduction.html" },
		{ name = "Vue API Reference", url = "https://vuejs.org/api/" },
		{ name = "Nuxt 3 Docs", url = "https://nuxt.com/docs" },
		{ name = "Pinia (State)", url = "https://pinia.vuejs.org/" },
		{ name = "Vue Router", url = "https://router.vuejs.org/" },
		{ name = "VueUse", url = "https://vueuse.org/" },
	}
	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = vue_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Vue-specific alignment presets for mini.align:
-- • vue_bindings — align template attribute bindings on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("vue") then
		---@type string Alignment preset icon from icons.lang
		local vue_align_icon = icons.lang.vue

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			vue_bindings = {
				description = "Align Vue template bindings on '='",
				icon = vue_align_icon,
				split_pattern = "=",
				category = "web",
				lang = "vue",
				filetypes = { "vue" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("vue", "vue_bindings")
		align_registry.mark_language_loaded("vue")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("vue", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("vue_bindings"), {
			desc = vue_align_icon .. "  Align Vue bindings",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Vue-specific
-- parts (servers, formatters, linters, parsers, adapters).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Vue                     │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (vue_ls server added on require)  │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.vue)            │
-- │ nvim-lint          │ opts merge (linters_by_ft.vue)               │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- │ mason-nvim-dap     │ opts merge (js adapter in ensure_installed)  │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Vue
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- vue_ls: vue-language-server (official Vue Language Tools)
	-- Provides completions, diagnostics, template type-checking, and
	-- component prop validation. Runs in non-hybrid mode for full
	-- standalone SFC support (no separate TS server needed).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				vue_ls = {
					filetypes = { "vue", "typescript", "javascript" },
					init_options = {
						vue = {
							hybridMode = false,
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					vue = "vue",
				},
			})

			-- ── Buffer-local options for Vue files ───────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "vue" },
				callback = function()
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
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures vue-language-server, prettier, and eslint-lsp are
	-- installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"vue-language-server",
				"prettier",
				"eslint-lsp",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- Prettier: opinionated code formatter for Vue SFCs.
	-- Formats <template>, <script>, and <style> blocks uniformly.
	-- Respects project-local .prettierrc / prettier.config.js.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				vue = { "prettier" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- eslint_d: daemonized ESLint for near-instant linting feedback.
	-- Works with eslint-plugin-vue for template and script linting.
	-- Respects project-local .eslintrc / eslint.config.js (flat config).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				vue = { "eslint_d" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- vue: syntax highlighting, folding, and text objects for
	--      Single File Components (<template>, <script>, <style>)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"vue",
			},
		},
	},

	-- ── DAP — JAVASCRIPT / VUE DEBUGGER ────────────────────────────────────
	-- Shares the js-debug-adapter with langs/typescript.lua.
	-- mason-nvim-dap auto-configures pwa-node / pwa-chrome adapters.
	--
	-- After loading, ALL core DAP keymaps work in Vue files:
	--   <leader>dc, <leader>db, <leader>di, <leader>do, F5, F9, etc.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"jay-babu/mason-nvim-dap.nvim",
		optional = true,
		opts = {
			ensure_installed = { "js" },
		},
	},
}
