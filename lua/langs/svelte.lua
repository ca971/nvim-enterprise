---@file lua/langs/svelte.lua
---@description Svelte — LSP, formatter, linter, treesitter, DAP & buffer-local keymaps
---@module "langs.svelte"
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
---@see langs.solidity            Solidity language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/svelte.lua — Svelte language support                              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("svelte") → {} if off       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "svelte"):                   │    ║
--- ║  │  ├─ LSP          svelte-language-server (completions, diag)      │    ║
--- ║  │  ├─ Formatter    prettier (with svelte plugin)                   │    ║
--- ║  │  ├─ Linter       eslint_d (via nvim-lint)                        │    ║
--- ║  │  ├─ Treesitter   svelte parser (syntax + folding)                │    ║
--- ║  │  ├─ DAP          js adapter (via mason-nvim-dap)                 │    ║
--- ║  │  └─ Extras       SvelteKit detection · commands picker           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ DEV       r  Dev server (npm/pnpm/yarn/bun run dev)          │    ║
--- ║  │  │            R  Build (production)                              │    ║
--- ║  │  │            p  Preview (production build)                      │    ║
--- ║  │  ├─ TEST      t  Run tests (vitest / playwright auto-detect)     │    ║
--- ║  │  ├─ CHECK     s  Svelte check (type diagnostics)                 │    ║
--- ║  │  │            l  Lint (eslint via npm script)                    │    ║
--- ║  │  ├─ COMMANDS  c  SvelteKit commands picker (11 actions)          │    ║
--- ║  │  ├─ DEBUG     d  Debug (JS DAP adapter)                          │    ║
--- ║  │  ├─ INFO      i  Package info (SvelteKit, runner, CWD)           │    ║
--- ║  │  └─ DOCS      h  Documentation browser (Svelte, SvelteKit,       │    ║
--- ║  │                  Tutorial, REPL)                                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Package runner auto-detection:                                  │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. pnpm-lock.yaml → pnpm                                │    │    ║
--- ║  │  │  2. yarn.lock      → yarn                                │    │    ║
--- ║  │  │  3. bun.lockb      → bun                                 │    │    ║
--- ║  │  │  4. fallback       → npm                                 │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  SvelteKit detection:                                            │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Reads svelte.config.js and checks for @sveltejs/kit     │    │    ║
--- ║  │  │  import. Used for info display only — keymaps work       │    │    ║
--- ║  │  │  regardless of SvelteKit presence.                       │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Test runner auto-detection:                                     │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. vitest.config.ts/.js   → npm run test (vitest)       │    │    ║
--- ║  │  │  2. playwright.config.ts   → npm run test (playwright)   │    │    ║
--- ║  │  │  3. fallback               → <runner> test               │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType svelte):                            ║
--- ║  • colorcolumn=100, textwidth=100  (common Svelte convention)            ║
--- ║  • tabstop=2, shiftwidth=2         (2-space indentation)                 ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .svelte → svelte                                                      ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Svelte support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("svelte") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Svelte Nerd Font icon (trailing whitespace stripped)
local svelte_icon = icons.lang.svelte:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Svelte buffers.
-- The group is buffer-local and only visible when filetype == "svelte".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("svelte", "Svelte", svelte_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the Node.js package runner for the current project.
---
--- Resolution order (based on lockfile presence):
--- 1. `pnpm-lock.yaml` → `"pnpm"`
--- 2. `yarn.lock`       → `"yarn"`
--- 3. `bun.lockb`       → `"bun"`
--- 4. Fallback           → `"npm"`
---
--- ```lua
--- local runner = pkg_runner()
--- vim.cmd.terminal(runner .. " run dev")
--- ```
---
---@return string runner The package runner command
---@private
local function pkg_runner()
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/pnpm-lock.yaml") == 1 then
		return "pnpm"
	elseif vim.fn.filereadable(cwd .. "/yarn.lock") == 1 then
		return "yarn"
	elseif vim.fn.filereadable(cwd .. "/bun.lockb") == 1 then
		return "bun"
	end
	return "npm"
end

--- Build a `<runner> run <script>` command string.
---
--- Combines the auto-detected package runner with `run` and the
--- given script name. Used by all keymaps that execute npm scripts.
---
--- ```lua
--- run_script("dev")   --> "pnpm run dev"
--- run_script("build") --> "npm run build"
--- ```
---
---@param script string The npm script name (e.g. `"dev"`, `"build"`, `"test"`)
---@return string cmd The full command string
---@private
local function run_script(script)
	return pkg_runner() .. " run " .. script
end

--- Detect whether the current project uses SvelteKit.
---
--- Reads `svelte.config.js` in the CWD and checks if it imports
--- `@sveltejs/kit`. Returns `false` if the config file doesn't
--- exist or doesn't contain the SvelteKit import.
---
--- Used for informational display only — keymaps work regardless
--- of SvelteKit presence.
---
---@return boolean is_kit `true` if the project uses SvelteKit
---@private
local function is_sveltekit()
	local cwd = vim.fn.getcwd()
	local config_path = cwd .. "/svelte.config.js"

	if vim.fn.filereadable(config_path) ~= 1 then return false end

	local content = table.concat(vim.fn.readfile(config_path), "\n")
	return content:match("@sveltejs/kit") ~= nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEV / BUILD / PREVIEW
--
-- Development server, production build, and preview commands.
-- All commands use the auto-detected package runner and delegate
-- to npm scripts defined in `package.json`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start the Svelte development server.
---
--- Runs `<runner> run dev` which starts the Vite dev server
--- with hot module replacement (HMR).
keys.lang_map("svelte", "n", "<leader>lr", function()
	vim.cmd.split()
	vim.cmd.terminal(run_script("dev"))
end, { desc = icons.ui.Play .. " Dev server" })

--- Build the project for production.
---
--- Runs `<runner> run build` which creates an optimized production
--- build in the `build/` (SvelteKit) or `dist/` directory.
keys.lang_map("svelte", "n", "<leader>lR", function()
	vim.cmd.split()
	vim.cmd.terminal(run_script("build"))
end, { desc = icons.dev.Build .. " Build" })

--- Preview the production build locally.
---
--- Runs `<runner> run preview` which serves the production build
--- on a local port for testing before deployment.
keys.lang_map("svelte", "n", "<leader>lp", function()
	vim.cmd.split()
	vim.cmd.terminal(run_script("preview"))
end, { desc = svelte_icon .. " Preview" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Test execution with auto-detection of the test framework.
-- Supports Vitest (unit) and Playwright (E2E).
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the test suite with the auto-detected test runner.
---
--- Detection order:
--- 1. `vitest.config.ts/.js` exists → `<runner> run test` (Vitest)
--- 2. `playwright.config.ts` exists → `<runner> run test` (Playwright)
--- 3. Fallback → `<runner> test`
keys.lang_map("svelte", "n", "<leader>lt", function()
	vim.cmd("silent! write")
	local cwd = vim.fn.getcwd()

	---@type string
	local cmd
	if
		vim.fn.filereadable(cwd .. "/vitest.config.ts") == 1
		or vim.fn.filereadable(cwd .. "/vitest.config.js") == 1
	then
		cmd = run_script("test")
	elseif vim.fn.filereadable(cwd .. "/playwright.config.ts") == 1 then
		cmd = run_script("test")
	else
		cmd = pkg_runner() .. " test"
	end

	vim.cmd.split()
	vim.cmd.terminal(cmd)
end, { desc = icons.dev.Test .. " Test" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CHECK / LINT
--
-- Type checking and static analysis.
-- Svelte check provides TypeScript-level diagnostics for .svelte files.
-- Lint runs the project's configured ESLint ruleset.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run `svelte-check` for type diagnostics.
---
--- Executes `<runner> run check` which runs `svelte-check` to
--- validate TypeScript types, component props, and Svelte-specific
--- rules across the project.
keys.lang_map("svelte", "n", "<leader>ls", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(run_script("check"))
end, { desc = icons.ui.Check .. " Svelte check" })

--- Run the project linter via npm script.
---
--- Executes `<runner> run lint` which typically runs ESLint with
--- the project's configured rules and Svelte plugin.
keys.lang_map("svelte", "n", "<leader>ll", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(run_script("lint"))
end, { desc = svelte_icon .. " Lint" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — COMMANDS PICKER
--
-- Unified command palette for Svelte/SvelteKit operations.
-- Presents 11 actions including dev, build, test, lint, format,
-- and package management commands.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the SvelteKit commands picker.
---
--- Presents 11 available commands in a selection menu:
--- - dev, build, preview, check, lint, format
--- - test:unit, test:integration
--- - install, update, outdated (package management)
---
--- Package management commands use the auto-detected runner directly
--- (e.g. `pnpm install`) rather than npm scripts.
keys.lang_map("svelte", "n", "<leader>lc", function()
	---@type string
	local runner = pkg_runner()

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "dev",              cmd = run_script("dev") },
		{ name = "build",            cmd = run_script("build") },
		{ name = "preview",          cmd = run_script("preview") },
		{ name = "check",            cmd = run_script("check") },
		{ name = "lint",             cmd = run_script("lint") },
		{ name = "format",           cmd = run_script("format") },
		{ name = "test:unit",        cmd = run_script("test:unit") },
		{ name = "test:integration", cmd = run_script("test:integration") },
		{ name = runner .. " install",  cmd = runner .. " install" },
		{ name = runner .. " update",   cmd = runner .. " update" },
		{ name = runner .. " outdated", cmd = runner .. " outdated" },
	}

	vim.ui.select(
		vim.tbl_map(function(a) return a.name end, actions),
		{ prompt = svelte_icon .. " Svelte:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = svelte_icon .. " Commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via the JavaScript debug adapter.
-- Uses the same JS DAP adapter as other web frameworks (React, Vue).
-- The adapter is configured by mason-nvim-dap (ensure_installed: "js").
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session.
---
--- Saves the buffer, then calls `dap.continue()` which either resumes
--- a paused session or launches a new one using the JavaScript adapter.
--- Requires the `js` DAP adapter to be installed via Mason.
keys.lang_map("svelte", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Svelte" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (js)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INFO / DOCUMENTATION
--
-- Project information and external documentation access.
-- Info displays SvelteKit detection status, package runner, and CWD.
-- Documentation links open in the system browser via `vim.ui.open()`.
-- ═══════════════════════════════════════════════════════════════════════════

--- Display Svelte project information.
---
--- Shows:
--- - SvelteKit detection status (✓ / ✗)
--- - Auto-detected package runner (npm / pnpm / yarn / bun)
--- - Current working directory
keys.lang_map("svelte", "n", "<leader>li", function()
	---@type string[]
	local info = {
		svelte_icon .. " Svelte Info:",
		"",
		"  SvelteKit: " .. (is_sveltekit() and "✓" or "✗"),
		"  Runner:    " .. pkg_runner(),
		"  CWD:       " .. vim.fn.getcwd(),
	}

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Svelte" })
end, { desc = icons.diagnostics.Info .. " Package info" })

--- Open Svelte documentation in the system browser.
---
--- Presents a selection menu with links to key Svelte documentation
--- resources. The selected URL is opened via `vim.ui.open()`.
---
--- Available documentation links:
--- - Svelte Docs (component framework)
--- - SvelteKit Docs (application framework)
--- - Svelte Tutorial (interactive learning)
--- - Svelte REPL (online playground)
keys.lang_map("svelte", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Svelte Docs",     url = "https://svelte.dev/docs" },
		{ name = "SvelteKit Docs",  url = "https://kit.svelte.dev/docs" },
		{ name = "Svelte Tutorial", url = "https://learn.svelte.dev/" },
		{ name = "Svelte REPL",     url = "https://svelte.dev/repl" },
	}

	vim.ui.select(
		vim.tbl_map(function(r) return r.name end, refs),
		{ prompt = svelte_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Svelte-specific alignment presets for mini.align:
-- • svelte_bindings — align template attribute bindings on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("svelte") then
		---@type string Alignment preset icon from icons.lang
		local svelte_align_icon = icons.lang.svelte

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			svelte_bindings = {
				description = "Align Svelte template bindings on '='",
				icon = svelte_align_icon,
				split_pattern = "=",
				category = "web",
				lang = "svelte",
				filetypes = { "svelte" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("svelte", "svelte_bindings")
		align_registry.mark_language_loaded("svelte")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("svelte", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("svelte_bindings"), {
			desc = svelte_align_icon .. "  Align Svelte bindings",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Svelte-specific
-- parts (servers, formatters, linters, parsers, DAP adapter).
--
-- Loading strategy:
-- ┌──────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin               │ How it lazy-loads for Svelte                 │
-- ├──────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig       │ opts merge (svelte server added)            │
-- │ mason.nvim           │ opts merge (svelte-ls + prettier + eslint)  │
-- │ conform.nvim         │ opts merge (prettier for svelte)            │
-- │ nvim-lint            │ opts merge (eslint_d for svelte)            │
-- │ nvim-treesitter      │ opts merge (svelte parser ensured)          │
-- │ mason-nvim-dap       │ opts merge (js adapter ensured)             │
-- └──────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Svelte
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- svelte: Svelte Language Server (completions, diagnostics, hover,
	-- go-to-definition, TypeScript integration within .svelte files)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				svelte = {},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					svelte = "svelte",
				},
			})

			-- ── Buffer-local options for Svelte files ────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "svelte" },
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
	-- Ensures svelte-language-server, prettier, and eslint-lsp are
	-- installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"svelte-language-server",
				"prettier",
				"eslint-lsp",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- Prettier with the Svelte plugin for .svelte file formatting.
	-- The plugin must be installed in the project: npm i -D prettier-plugin-svelte
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				svelte = { "prettier" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- eslint_d: fast ESLint daemon (complements the LSP).
	-- Requires eslint and eslint-plugin-svelte in the project.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				svelte = { "eslint_d" },
			},
		},
	},

	-- ── TREESITTER PARSER ──────────────────────────────────────────────────
	-- svelte: syntax highlighting, folding, indentation for .svelte files
	-- (handles <script>, <style>, and template sections)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"svelte",
			},
		},
	},

	-- ── DAP (JavaScript debug adapter) ─────────────────────────────────────
	-- Ensures the `js` DAP adapter is installed via Mason.
	-- Used for debugging Svelte applications via the JS debug protocol.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"jay-babu/mason-nvim-dap.nvim",
		optional = true,
		opts = {
			ensure_installed = { "js" },
		},
	},
}
