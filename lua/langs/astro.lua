---@file lua/langs/astro.lua
---@description Astro — Framework support (dev server, build, LSP, formatter, linter, DAP)
---@module "langs.astro"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps               Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons                 Icon provider (`lang.astro`, `ui`, `dev`, `diagnostics`)
---@see core.mini-align-registry   Alignment preset registration for Astro templates
---@see langs.typescript           TypeScript support (shared tooling: prettier, eslint)
---@see langs.angular              Angular support (same web framework architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/astro.lua — Astro web framework integration                       ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("astro") → {} if off        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Detection layers:                                               │    ║
--- ║  │  ├─ Filetype    astro (extension-based: *.astro)                 │    ║
--- ║  │  └─ Pkg runner  pnpm > yarn > bun > npm (lock file heuristic)    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded on ft = "astro"):                        │    ║
--- ║  │  ├─ LSP         astro-ls (Astro Language Server)                 │    ║
--- ║  │  ├─ Formatter   prettier + prettier-plugin-astro (conform.nvim)  │    ║
--- ║  │  ├─ Linter      eslint_d (nvim-lint, conditional)                │    ║
--- ║  │  ├─ Treesitter  astro parser                                     │    ║
--- ║  │  └─ DAP         js adapter (via mason-nvim-dap)                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (buffer-local, <leader>l group, 9 bindings):            │    ║
--- ║  │  ├─ DEV/BUILD   r  Dev server           R  Build                 │    ║
--- ║  │  │              p  Preview                                       │    ║
--- ║  │  ├─ QUALITY     t  Astro check           l  Lint (eslint)        │    ║
--- ║  │  ├─ DEBUG       d  Debug (js adapter)                            │    ║
--- ║  │  ├─ CLI         c  Command palette (9 commands)                  │    ║
--- ║  │  └─ DOCS        i  Project info          h  Documentation        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Command palette (9 actions):                                    │    ║
--- ║  │  ├─ dev · build · preview · check · lint · format                │    ║
--- ║  │  ├─ <runner> install · <runner> update                           │    ║
--- ║  │  └─ astro add… (interactive integration installer)               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Mini.align integration:                                         │    ║
--- ║  │  ├─ Preset: astro_bindings (align on '=')                        │    ║
--- ║  │  └─ <leader>aL  Align Astro template bindings                    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (set on FileType astro):                                 ║
--- ║  • 2 spaces, expandtab        (Astro / web convention)                   ║
--- ║  • colorcolumn=100             (Astro style guide line length)           ║
--- ║  • treesitter foldexpr         (foldmethod=expr, foldlevel=99)           ║
--- ║                                                                          ║
--- ║  Documentation references (4):                                           ║
--- ║  ├─ Astro Docs · API Reference                                           ║
--- ║  └─ Integrations · GitHub                                                ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Astro support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("astro") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Astro Nerd Font icon (trailing whitespace stripped)
local astro_icon = icons.lang.astro:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group as " Astro" in which-key for
-- astro buffers. All lang_map() calls below bind into this group.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("astro", "Astro", astro_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — PACKAGE RUNNER
--
-- Astro projects use npm scripts for dev/build/preview workflows.
-- These helpers detect the package runner and build script commands.
--
-- Detection strategy:
-- ├─ pnpm-lock.yaml → pnpm
-- ├─ yarn.lock      → yarn
-- ├─ bun.lockb      → bun
-- └─ (fallback)     → npm
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the package runner for the current project.
---
--- Checks for lock files in priority order, reflecting the ecosystem
--- preference: pnpm (fastest) → yarn → bun → npm (universal fallback).
---
---@return string runner Package runner command name (`"pnpm"` | `"yarn"` | `"bun"` | `"npm"`)
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

--- Build a package runner script command.
---
--- Combines the detected package runner with `run <script>` to
--- produce the full CLI command for npm scripts defined in `package.json`.
---
--- ```lua
--- run_script("dev")     -- "pnpm run dev" (if pnpm detected)
--- run_script("build")   -- "npm run build" (fallback)
--- ```
---
---@param script string npm script name (e.g. `"dev"`, `"build"`, `"preview"`)
---@return string cmd Full command string ready for shell execution
---@private
local function run_script(script)
	return pkg_runner() .. " run " .. script
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEV / BUILD
--
-- Development server, production build, and preview commands.
-- All commands use npm scripts resolved via run_script().
--
-- Workflow:
-- ├─ dev:     start Vite dev server with HMR (port 4321 by default)
-- ├─ build:   generate static site to dist/ (or SSR output)
-- └─ preview: serve the built output locally for inspection
-- ═══════════════════════════════════════════════════════════════════════════

--- Start the Astro development server.
---
--- Runs the `dev` npm script (typically `astro dev`) which starts
--- the Vite-powered dev server with hot module replacement on
--- `http://localhost:4321`.
keys.lang_map("astro", "n", "<leader>lr", function()
	vim.cmd.split()
	vim.cmd.terminal(run_script("dev"))
end, { desc = icons.ui.Play .. " Dev server" })

--- Build the Astro project for production.
---
--- Runs the `build` npm script (typically `astro build`) which
--- generates static HTML/CSS/JS output to `dist/`, or server-side
--- rendered output if SSR is configured.
keys.lang_map("astro", "n", "<leader>lR", function()
	vim.cmd.split()
	vim.cmd.terminal(run_script("build"))
end, { desc = icons.dev.Build .. " Build" })

--- Preview the built Astro site.
---
--- Runs the `preview` npm script (typically `astro preview`) which
--- serves the production build locally. Requires a prior `build` step.
keys.lang_map("astro", "n", "<leader>lp", function()
	vim.cmd.split()
	vim.cmd.terminal(run_script("preview"))
end, { desc = astro_icon .. " Preview" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — QUALITY (CHECK / LINT)
--
-- Code quality tools: Astro type checker and ESLint integration.
-- Astro check validates .astro files for TypeScript errors and
-- component prop mismatches.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run `astro check` for type validation.
---
--- Saves the buffer before execution. Prefers the global `astro`
--- binary if available, otherwise falls back to the local installation
--- via the detected package runner's `exec` command.
---
--- `astro check` validates:
--- - TypeScript types in frontmatter and expressions
--- - Component prop types and required props
--- - Astro-specific diagnostics (e.g. invalid directives)
keys.lang_map("astro", "n", "<leader>lt", function()
	vim.cmd("silent! write")
	if vim.fn.executable("astro") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("astro check")
	else
		vim.cmd.split()
		vim.cmd.terminal(pkg_runner() .. " exec astro check")
	end
end, { desc = icons.ui.Check .. " Astro check" })

--- Run the project's lint script.
---
--- Saves the buffer, then executes the `lint` npm script which
--- typically runs ESLint with Astro-specific rules and plugins.
--- Requires `"lint"` to be defined in `package.json` scripts.
keys.lang_map("astro", "n", "<leader>ll", function()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(run_script("lint"))
end, { desc = astro_icon .. " Lint" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
--
-- DAP integration via the JavaScript debug adapter.
-- Uses the same js adapter as other web framework modules.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start or continue a DAP debug session.
---
--- Saves the buffer, then calls `dap.continue()` which either resumes
--- a paused session or launches a new one using the JavaScript adapter.
--- Requires nvim-dap and the `js` adapter to be installed via Mason.
keys.lang_map("astro", "n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Astro" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (js)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CLI COMMAND PALETTE
--
-- Centralized command palette with 9 pre-configured Astro CLI and
-- package runner commands. Covers the full development lifecycle
-- from a single keymap.
--
-- Commands organized by category:
-- ├─ Dev:      dev, build, preview
-- ├─ Quality:  check, lint, format
-- ├─ Package:  install, update
-- └─ Extend:   astro add… (interactive integration installer)
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Astro CLI command palette.
---
--- Presents 9 commands covering the full Astro development lifecycle.
--- The `astro add…` action prompts for an integration name (e.g.
--- `react`, `tailwind`, `mdx`) and runs `astro add <name>` which
--- auto-installs the package and configures `astro.config.mjs`.
keys.lang_map("astro", "n", "<leader>lc", function()
	local runner = pkg_runner()

	---@type { name: string, cmd: string, prompt?: boolean }[]
	local actions = {
		{ name = "dev", cmd = run_script("dev") },
		{ name = "build", cmd = run_script("build") },
		{ name = "preview", cmd = run_script("preview") },
		{ name = "check", cmd = runner .. " exec astro check" },
		{ name = "lint", cmd = run_script("lint") },
		{ name = "format", cmd = run_script("format") },
		{ name = runner .. " install", cmd = runner .. " install" },
		{ name = runner .. " update", cmd = runner .. " update" },
		{ name = "astro add…", cmd = runner .. " exec astro add", prompt = true },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = astro_icon .. " Astro:" },
		function(_, idx)
			if not idx then return end
			local action = actions[idx]
			if action.prompt then
				vim.ui.input({ prompt = "Integration: " }, function(name)
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
end, { desc = astro_icon .. " Commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INFO / DOCUMENTATION
--
-- Project introspection and external documentation access.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show basic Astro project information.
---
--- Displays the detected package runner and current working directory.
keys.lang_map("astro", "n", "<leader>li", function()
	---@type string[]
	local info = {
		astro_icon .. " Astro Info:",
		"",
		"  Runner: " .. pkg_runner(),
		"  CWD:    " .. vim.fn.getcwd(),
	}
	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Astro" })
end, { desc = icons.diagnostics.Info .. " Project info" })

--- Open Astro documentation in the default browser.
---
--- Presents 4 curated reference links via `vim.ui.select()`:
--- 1. Astro Docs          — https://docs.astro.build/
--- 2. Astro API Reference — https://docs.astro.build/en/reference/api-reference/
--- 3. Astro Integrations  — https://astro.build/integrations/
--- 4. Astro GitHub        — https://github.com/withastro/astro
keys.lang_map("astro", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Astro Docs", url = "https://docs.astro.build/" },
		{ name = "Astro API Reference", url = "https://docs.astro.build/en/reference/api-reference/" },
		{ name = "Astro Integrations", url = "https://astro.build/integrations/" },
		{ name = "Astro GitHub", url = "https://github.com/withastro/astro" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = astro_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Astro-specific alignment presets when mini.align is
-- available. Loaded once per session (guarded by is_language_loaded).
--
-- Preset: astro_bindings — align Astro template attribute bindings
-- on the '=' character (e.g. `class="..."`, `client:load`, `set:html`).
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("astro") then
		---@type string Alignment preset icon from icons.lang
		local align_icon = icons.lang.astro

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			astro_bindings = {
				description = "Align Astro template bindings on '='",
				icon = align_icon,
				split_pattern = "=",
				category = "web",
				lang = "astro",
				filetypes = { "astro" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("astro", "astro_bindings")
		align_registry.mark_language_loaded("astro")

		-- ── Alignment keymap ─────────────────────────────────────────
		keys.lang_map("astro", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("astro_bindings"), {
			desc = align_icon .. "  Align Astro bindings",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Astro-specific
-- parts (servers, formatters, linters, parsers, adapters).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Astro                  │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (astro added to servers)          │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.astro)          │
-- │ nvim-lint          │ opts fn (conditional eslint_d registration)  │
-- │ nvim-treesitter    │ opts merge (astro parser to ensure_installed)│
-- │ mason-nvim-dap     │ opts merge (js adapter to ensure_installed)  │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Astro
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────
	-- astro-ls: Astro Language Server providing completions, diagnostics,
	-- go-to-definition, and type checking for .astro files. Handles
	-- frontmatter (TypeScript), template expressions, and component props.
	-- ────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				astro = {},
			},
		},
		init = function()
			-- ── Filetype detection ──────────────────────────────────
			-- Ensure .astro files are recognized. Neovim may already
			-- detect this natively, but we reinforce for consistency.
			vim.filetype.add({
				extension = {
					astro = "astro",
				},
			})

			-- ── Buffer-local options for Astro files ─────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "astro" },
				callback = function()
					local opt = vim.opt_local

					-- ── Layout ────────────────────────────────────────
					opt.wrap = false
					opt.colorcolumn = "100"
					opt.textwidth = 100

					-- ── Indentation (web convention: 2 spaces) ───────
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true

					-- ── Line numbers ──────────────────────────────────
					opt.number = true
					opt.relativenumber = true

					-- ── Folding (treesitter-based) ────────────────────
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
				end,
				desc = "NvimEnterprise: Astro buffer options",
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────
	-- Ensures Astro Language Server and Prettier are installed
	-- and managed by Mason.
	-- ────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"astro-language-server",
				"prettier",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────
	-- Prettier for Astro files. Requires prettier-plugin-astro to be
	-- installed in the project (`npm i -D prettier-plugin-astro`).
	-- Prettier auto-detects the plugin and handles .astro syntax
	-- including frontmatter, template expressions, and style blocks.
	-- ────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				astro = { "prettier" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────
	-- eslint_d for Astro files (conditional registration).
	--
	-- Only registers the linter if eslint_d or eslint is available
	-- on the system PATH. This prevents nvim-lint errors in projects
	-- that don't use ESLint.
	--
	-- NOTE: Uses opts function (not table) to conditionally merge,
	-- unlike most other lang modules that use static opts tables.
	-- ────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = function(_, opts)
			if vim.fn.executable("eslint_d") == 1 or vim.fn.executable("eslint") == 1 then
				opts.linters_by_ft = opts.linters_by_ft or {}
				opts.linters_by_ft.astro = { "eslint_d" }
			end
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────
	-- astro: syntax highlighting, folding, and indentation for .astro
	-- files including frontmatter fences, template expressions,
	-- and embedded CSS/JS/TS blocks.
	-- ────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"astro",
			},
		},
	},

	-- ── DAP — JAVASCRIPT DEBUG ADAPTER ─────────────────────────────────
	-- Ensures the JavaScript debug adapter (js-debug-adapter) is
	-- installed via Mason for debugging Astro server-side code
	-- and API routes.
	-- ────────────────────────────────────────────────────────────────────
	{
		"jay-babu/mason-nvim-dap.nvim",
		optional = true,
		opts = {
			ensure_installed = { "js" },
		},
	},
}
