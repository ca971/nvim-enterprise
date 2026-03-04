---@file lua/langs/angular.lua
---@description Angular — Framework support (CLI, LSP, keymaps, formatter, linter)
---@module "langs.angular"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps               Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons                 Icon provider (`lang.angular`, `ui`, `dev`, `diagnostics`)
---@see core.mini-align-registry   Alignment preset registration for Angular templates
---@see langs.typescript           TypeScript support (shared tooling: prettier, eslint)
---@see langs.python               Python support (same architecture pattern)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/angular.lua — Angular framework integration                       ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("angular") → {} if off      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Detection layers:                                               │    ║
--- ║  │  ├─ Project     angular.json or .angular-cli.json in cwd         │    ║
--- ║  │  ├─ Filetype    htmlangular (Neovim 0.10+ native detection)      │    ║
--- ║  │  ├─ Pattern     *.component.html, *.template.html → htmlangular  │    ║
--- ║  │  └─ Pkg runner  pnpm > yarn > bun > npm (lock file heuristic)    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded on ft = "htmlangular"):                  │    ║
--- ║  │  ├─ LSP         angularls (Angular Language Service)             │    ║
--- ║  │  ├─ Formatter   prettier (conform.nvim)                          │    ║
--- ║  │  ├─ Linter      eslint_d (nvim-lint)                             │    ║
--- ║  │  └─ Treesitter  angular · html · typescript · css · scss         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (buffer-local, <leader>l group, 15 bindings):           │    ║
--- ║  │  ├─ SERVE       r  ng serve --open                               │    ║
--- ║  │  │              R  Build (dev/prod config selection)             │    ║
--- ║  │  ├─ TEST        t  Unit tests (karma/jest)                       │    ║
--- ║  │  │              T  E2E tests                                     │    ║
--- ║  │  ├─ GENERATE    g  Generate schematic (13 types, interactive)    │    ║
--- ║  │  │              d  Destroy info (no CLI command exists)          │    ║
--- ║  │  ├─ QUALITY     l  ng lint                                       │    ║
--- ║  │  │              s  Type check (tsc --noEmit)                     │    ║
--- ║  │  │              a  Analyze bundle (3 analysis tools)             │    ║
--- ║  │  ├─ DEPS        u  Update (4 update strategies)                  │    ║
--- ║  │  │              p  Install package (runner-aware)                │    ║
--- ║  │  ├─ NAV         w  Switch component part (TS/HTML/CSS/spec)      │    ║
--- ║  │  ├─ CLI         c  Full command palette (16 commands)            │    ║
--- ║  │  └─ DOCS        i  Project info       h  Documentation browser   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Generate schematics (13 types):                                 │    ║
--- ║  │  ├─ component (c)   service (s)     module (m)                   │    ║
--- ║  │  ├─ directive (d)   pipe (p)        guard (g)                    │    ║
--- ║  │  ├─ interceptor     resolver        interface (i)                │    ║
--- ║  │  ├─ class (cl)      enum (e)        library (lib)                │    ║
--- ║  │  └─ application                                                  │    ║
--- ║  │  Component options: Standalone · Inline template/style · Skip    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Component part switching:                                       │    ║
--- ║  │  ├─ .component.ts    ↔  TypeScript logic                         │    ║
--- ║  │  ├─ .component.html  ↔  Template                                 │    ║
--- ║  │  ├─ .component.scss  ↔  Styles (SCSS / CSS / Less)               │    ║
--- ║  │  └─ .spec.ts         ↔  Tests                                    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Mini.align integration:                                         │    ║
--- ║  │  ├─ Preset: angular_bindings (align on '=')                      │    ║
--- ║  │  └─ <leader>aL  Align Angular template bindings                  │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Project info detection:                                                 ║
--- ║  ├─ @angular/core version from package.json                              ║
--- ║  ├─ Features: PWA (ngsw-config.json), E2E (e2e/), SSR, i18n              ║
--- ║  └─ Tools: ng, tsc, prettier, eslint (executable checks)                 ║
--- ║                                                                          ║
--- ║  Documentation references (7):                                           ║
--- ║  ├─ Angular Docs · API Reference · CLI Reference                         ║
--- ║  ├─ RxJS Docs · NgRx (State Management)                                  ║
--- ║  └─ Angular Material · Angular Update Guide                              ║
--- ║                                                                          ║
--- ║  Buffer options (set on FileType htmlangular):                           ║
--- ║  • 2 spaces, expandtab       (Angular template convention)               ║
--- ║  • colorcolumn=120            (Angular style guide line length)          ║
--- ║  • treesitter foldexpr        (foldmethod=expr, foldlevel=99)            ║
--- ║  • commentstring="<!-- %s -->" (HTML comment syntax)                     ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Angular support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("angular") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Angular Nerd Font icon (trailing whitespace stripped)
local ng_icon = icons.lang.angular:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group as " Angular" in which-key for
-- htmlangular buffers. All lang_map() calls below bind into this group.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("htmlangular", "Angular", ng_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — DETECTION
--
-- Project detection, package runner resolution, and Angular CLI location.
-- Used by all keymap callbacks to validate the project context and
-- resolve the correct command prefix.
--
-- Detection strategy:
-- ├─ Project:  angular.json (v6+) or .angular-cli.json (v5)
-- ├─ Runner:   pnpm-lock.yaml > yarn.lock > bun.lockb > npm (fallback)
-- └─ CLI:      local node_modules/.bin/ng > global ng > npx ng
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect if the current working directory is an Angular project.
---
--- Checks for `angular.json` (Angular 6+) or `.angular-cli.json` (Angular 5
--- and earlier). Both files are created by `ng new` and are unique to
--- Angular projects.
---
---@return boolean is_angular `true` if an Angular project is detected in cwd
---@private
local function is_angular()
	local cwd = vim.fn.getcwd()
	return vim.fn.filereadable(cwd .. "/angular.json") == 1 or vim.fn.filereadable(cwd .. "/.angular-cli.json") == 1
end

--- Detect the package runner for the current project.
---
--- Checks for lock files in priority order, reflecting the ecosystem
--- preference: pnpm (fastest) → yarn → bun → npm (universal fallback).
---
--- ```lua
--- local runner = pkg_runner()  -- "pnpm" | "yarn" | "bun" | "npm"
--- ```
---
---@return string runner Package runner command name
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

--- Get the Angular CLI command (local or global).
---
--- Resolution order:
--- 1. Local `node_modules/.bin/ng` via `npx ng` (project-specific version)
--- 2. Global `ng` binary (if installed globally)
--- 3. `npx ng` fallback (downloads if needed)
---
---@return string cmd Angular CLI command string ready for shell execution
---@private
local function ng_cmd()
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/node_modules/.bin/ng") == 1 then return "npx ng" end
	if vim.fn.executable("ng") == 1 then return "ng" end
	return "npx ng"
end

--- Validate Angular project context and return the CLI command.
---
--- Combines `is_angular()` check with `ng_cmd()` resolution.
--- Shows a warning notification and returns `nil` if not in an Angular
--- project, allowing callers to use a simple nil-guard pattern:
---
--- ```lua
--- local cmd = check_ng()
--- if not cmd then return end
--- ```
---
---@return string|nil cmd Angular CLI command, or `nil` if not in an Angular project
---@private
local function check_ng()
	if not is_angular() then
		vim.notify("Not an Angular project (no angular.json)", vim.log.levels.WARN, { title = "Angular" })
		return nil
	end
	return ng_cmd()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SERVE / BUILD
--
-- Development server and production build commands.
-- Both use the Angular CLI resolved by check_ng().
-- ═══════════════════════════════════════════════════════════════════════════

--- Start the Angular development server with auto-open.
---
--- Runs `ng serve --open` in a terminal split. The `--open` flag
--- launches the default browser on `http://localhost:4200`.
keys.lang_map("htmlangular", "n", "<leader>lr", function()
	local cmd = check_ng()
	if not cmd then return end
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " serve --open")
	vim.notify("Angular dev server starting…", vim.log.levels.INFO, { title = "Angular" })
end, { desc = icons.ui.Play .. " Serve" })

--- Build the Angular application with configuration selection.
---
--- Prompts the user to choose between `development` and `production`
--- configurations via `vim.ui.select()`. The production config enables
--- AOT compilation, tree shaking, and minification.
keys.lang_map("htmlangular", "n", "<leader>lR", function()
	local cmd = check_ng()
	if not cmd then return end
	---@type string[]
	local configs = { "development", "production" }
	vim.ui.select(configs, { prompt = ng_icon .. " Build configuration:" }, function(config)
		if not config then return end
		vim.cmd.split()
		vim.cmd.terminal(cmd .. " build --configuration=" .. config)
	end)
end, { desc = icons.dev.Build .. " Build" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Unit and end-to-end test execution.
-- Unit tests use the configured test runner (Karma or Jest).
-- E2E tests use the configured e2e framework (Protractor, Cypress, etc.).
-- ═══════════════════════════════════════════════════════════════════════════

--- Run unit tests via `ng test`.
---
--- Saves the buffer before execution. The test runner (Karma or Jest)
--- is determined by the project's `angular.json` configuration.
keys.lang_map("htmlangular", "n", "<leader>lt", function()
	local cmd = check_ng()
	if not cmd then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " test")
end, { desc = icons.dev.Test .. " Test (karma/jest)" })

--- Run end-to-end tests via `ng e2e`.
---
--- Saves the buffer before execution. Requires an e2e framework
--- to be configured (Protractor, Cypress, or Playwright).
keys.lang_map("htmlangular", "n", "<leader>lT", function()
	local cmd = check_ng()
	if not cmd then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " e2e")
end, { desc = icons.dev.Test .. " E2E test" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — GENERATE
--
-- Interactive schematic generator supporting 13 Angular schematic types.
-- For components, offers additional options: standalone, inline template,
-- inline style, skip tests.
--
-- Schematic types:
-- ├─ component (c)   service (s)     module (m)     directive (d)
-- ├─ pipe (p)        guard (g)       interceptor    resolver
-- ├─ interface (i)   class (cl)      enum (e)       library (lib)
-- └─ application
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate an Angular schematic via interactive multi-step UI.
---
--- Flow:
--- 1. Select schematic type (13 options with short aliases)
--- 2. Enter the schematic name
--- 3. For components only: select additional creation options
---    (Standalone, Inline template, Inline style, Skip tests)
--- 4. Execute `ng generate <type> <name> [options]` in a terminal split
keys.lang_map("htmlangular", "n", "<leader>lg", function()
	local cmd = check_ng()
	if not cmd then return end

	---@type { name: string, short: string }[]
	local schematics = {
		{ name = "component", short = "c" },
		{ name = "service", short = "s" },
		{ name = "module", short = "m" },
		{ name = "directive", short = "d" },
		{ name = "pipe", short = "p" },
		{ name = "guard", short = "g" },
		{ name = "interceptor", short = "" },
		{ name = "resolver", short = "" },
		{ name = "interface", short = "i" },
		{ name = "class", short = "cl" },
		{ name = "enum", short = "e" },
		{ name = "library", short = "lib" },
		{ name = "application", short = "" },
	}

	vim.ui.select(
		vim.tbl_map(function(s)
			local label = s.name
			if s.short ~= "" then label = label .. " (" .. s.short .. ")" end
			return label
		end, schematics),
		{ prompt = ng_icon .. " Generate:" },
		function(_, idx)
			if not idx then return end
			local schematic = schematics[idx]

			vim.ui.input({ prompt = "Name: " }, function(name)
				if not name or name == "" then return end

				-- ── Component-specific options ────────────────────────
				if schematic.name == "component" then
					---@type string[]
					local options = { "Default", "Standalone", "Inline template", "Inline style", "Skip tests" }
					vim.ui.select(options, { prompt = ng_icon .. " Options:" }, function(option)
						---@type string
						local extra = ""
						if option == "Standalone" then
							extra = " --standalone"
						elseif option == "Inline template" then
							extra = " --inline-template"
						elseif option == "Inline style" then
							extra = " --inline-style"
						elseif option == "Skip tests" then
							extra = " --skip-tests"
						end
						vim.cmd.split()
						vim.cmd.terminal(cmd .. " generate " .. schematic.name .. " " .. vim.fn.shellescape(name) .. extra)
					end)
				else
					vim.cmd.split()
					vim.cmd.terminal(cmd .. " generate " .. schematic.name .. " " .. vim.fn.shellescape(name))
				end
			end)
		end
	)
end, { desc = ng_icon .. " Generate" })

--- Show destroy info notification.
---
--- Angular CLI does not provide a `destroy` or `remove` command.
--- Informs the user to manually delete files and clean up module references.
keys.lang_map("htmlangular", "n", "<leader>ld", function()
	vim.notify(
		"Angular CLI has no 'destroy' command.\nManually delete the files and remove module references.",
		vim.log.levels.INFO,
		{ title = "Angular" }
	)
end, { desc = ng_icon .. " Destroy (info)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — QUALITY (LINT / TYPE CHECK / ANALYZE)
--
-- Code quality tools: Angular linter, TypeScript type checking,
-- and bundle size analysis with multiple tool options.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the Angular linter via `ng lint`.
---
--- Saves the buffer before execution. Requires `@angular-eslint` or
--- another lint schematic to be configured in the project.
keys.lang_map("htmlangular", "n", "<leader>ll", function()
	local cmd = check_ng()
	if not cmd then return end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " lint")
end, { desc = ng_icon .. " Lint" })

--- Type-check the project without emitting files.
---
--- Runs `tsc --noEmit` via the detected package runner. This catches
--- TypeScript errors across the entire project without producing output
--- files. Useful for CI validation and pre-commit checks.
keys.lang_map("htmlangular", "n", "<leader>ls", function()
	local runner = pkg_runner()
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal(runner .. " exec tsc --noEmit")
end, { desc = icons.ui.Check .. " Type check" })

--- Analyze bundle size with interactive tool selection.
---
--- Dynamically detects available analysis tools and presents them:
--- 1. `source-map-explorer` — treemap visualization of bundle contents
--- 2. `webpack-bundle-analyzer` — interactive zoomable treemap (via `--stats-json`)
--- 3. `ng build --source-map` — basic build with source maps for size inspection
---
--- Tool availability is checked both globally (`executable()`) and
--- locally (`node_modules/.bin/`).
keys.lang_map("htmlangular", "n", "<leader>la", function()
	local cmd = check_ng()
	if not cmd then return end
	local cwd = vim.fn.getcwd()

	---@type { name: string, cmd: string }[]
	local actions = {}

	-- ── Detect available analysis tools ───────────────────────────────
	if
		vim.fn.executable("source-map-explorer") == 1
		or vim.fn.filereadable(cwd .. "/node_modules/.bin/source-map-explorer") == 1
	then
		actions[#actions + 1] = {
			name = "source-map-explorer",
			cmd = cmd .. " build --source-map && npx source-map-explorer dist/**/*.js",
		}
	end

	actions[#actions + 1] = {
		name = "ng build --stats-json + bundle analyzer",
		cmd = cmd .. " build --stats-json && npx webpack-bundle-analyzer dist/**/stats.json",
	}

	actions[#actions + 1] = {
		name = "ng build --source-map (size check)",
		cmd = cmd .. " build --source-map",
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = ng_icon .. " Analyze:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = ng_icon .. " Analyze bundle" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEPENDENCIES (UPDATE / INSTALL)
--
-- Dependency management: update Angular packages and install new ones.
-- All commands are package-runner-aware (npm / pnpm / yarn / bun).
-- ═══════════════════════════════════════════════════════════════════════════

--- Update Angular packages with interactive strategy selection.
---
--- Available strategies:
--- 1. Check available updates (dry run)
--- 2. Update `@angular/core` + `@angular/cli` only
--- 3. Update all packages
--- 4. Force update all packages (bypasses peer dependency checks)
keys.lang_map("htmlangular", "n", "<leader>lu", function()
	local cmd = check_ng()
	if not cmd then return end

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "Check available updates", cmd = cmd .. " update" },
		{ name = "Update @angular/core", cmd = cmd .. " update @angular/core @angular/cli" },
		{ name = "Update all", cmd = cmd .. " update --all" },
		{ name = "Force update", cmd = cmd .. " update --all --force" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = ng_icon .. " Update:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = icons.ui.Refresh .. " Update" })

--- Install a package using the detected package runner.
---
--- Adapts the install command syntax per runner:
--- - npm:  `npm install <pkg>`
--- - pnpm: `pnpm add <pkg>`
--- - yarn: `yarn add <pkg>`
--- - bun:  `bun add <pkg>`
---
--- Prompts for the package name via `vim.ui.input()`.
keys.lang_map("htmlangular", "n", "<leader>lp", function()
	local runner = pkg_runner()
	vim.ui.input({ prompt = "Package to install: " }, function(pkg)
		if not pkg or pkg == "" then return end

		---@type string
		local install_cmd
		if runner == "npm" then
			install_cmd = "npm install " .. vim.fn.shellescape(pkg)
		elseif runner == "pnpm" then
			install_cmd = "pnpm add " .. vim.fn.shellescape(pkg)
		elseif runner == "yarn" then
			install_cmd = "yarn add " .. vim.fn.shellescape(pkg)
		else
			install_cmd = runner .. " add " .. vim.fn.shellescape(pkg)
		end

		vim.cmd.split()
		vim.cmd.terminal(install_cmd)
	end)
end, { desc = icons.ui.Package .. " Install package" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — NAVIGATION (COMPONENT PART SWITCHING)
--
-- Angular components consist of multiple co-located files sharing a
-- base name: *.component.ts, *.component.html, *.component.scss,
-- *.spec.ts, etc. This keymap enables quick navigation between them.
--
-- Supported file extensions:
-- ├─ .component.ts    → TypeScript logic
-- ├─ .component.html  → Template
-- ├─ .component.scss  → Styles (SCSS)
-- ├─ .component.css   → Styles (CSS)
-- ├─ .component.less  → Styles (Less)
-- └─ .spec.ts         → Unit tests
-- ═══════════════════════════════════════════════════════════════════════════

--- Switch between component-related files.
---
--- Detects the current file's base name by stripping the extension
--- pattern (`.component.*` or `.spec.ts`), then scans for all existing
--- sibling files and presents them via `vim.ui.select()`.
---
--- The current file is excluded from the selection list to avoid
--- no-op navigation.
keys.lang_map("htmlangular", "n", "<leader>lw", function()
	local file = vim.fn.expand("%:p")
	local base = file:gsub("%.component%.[%w]+$", ""):gsub("%.spec%.ts$", "")

	-- ── Validate current file is a component ──────────────────────────
	if not file:match("%.component%.") and not file:match("%.spec%.ts$") then
		vim.notify("Not a component file", vim.log.levels.INFO, { title = "Angular" })
		return
	end

	-- ── Rebuild base from spec files ──────────────────────────────────
	if file:match("%.spec%.ts$") then base = file:gsub("%.spec%.ts$", "") end

	-- ── Find existing sibling files ───────────────────────────────────
	---@type { label: string, path: string }[]
	local parts = {}

	---@type { ext: string, label: string }[]
	local candidates = {
		{ ext = ".component.ts", label = "TypeScript" },
		{ ext = ".component.html", label = "Template" },
		{ ext = ".component.scss", label = "Styles (SCSS)" },
		{ ext = ".component.css", label = "Styles (CSS)" },
		{ ext = ".component.less", label = "Styles (Less)" },
		{ ext = ".spec.ts", label = "Tests" },
	}

	for _, c in ipairs(candidates) do
		local path = base .. c.ext
		if vim.fn.filereadable(path) == 1 and path ~= file then parts[#parts + 1] = { label = c.label, path = path } end
	end

	if #parts == 0 then
		vim.notify("No related component files found", vim.log.levels.INFO, { title = "Angular" })
		return
	end

	-- ── Present selection ─────────────────────────────────────────────
	vim.ui.select(
		vim.tbl_map(function(p)
			return p.label
		end, parts),
		{ prompt = ng_icon .. " Switch to:" },
		function(_, idx)
			if idx then vim.cmd.edit(parts[idx].path) end
		end
	)
end, { desc = ng_icon .. " Switch component part" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CLI COMMAND PALETTE
--
-- Full command palette with 16 pre-configured Angular CLI and package
-- runner commands. Provides centralized access to all common Angular
-- development tasks from a single keymap.
--
-- Commands organized by category:
-- ├─ Serve:    serve, serve --open
-- ├─ Build:    build (dev), build (prod)
-- ├─ Test:     test, test --watch=false, e2e
-- ├─ Quality:  lint, lint --fix
-- ├─ i18n:     extract-i18n
-- ├─ Deploy:   deploy
-- ├─ Info:     config list, version
-- └─ Package:  install, outdated, audit
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Angular CLI command palette.
---
--- Presents 16 commands covering all common Angular development tasks.
--- Commands are resolved using both `ng_cmd()` (for Angular-specific
--- commands) and `pkg_runner()` (for package management commands).
keys.lang_map("htmlangular", "n", "<leader>lc", function()
	local cmd = check_ng()
	if not cmd then return end
	local runner = pkg_runner()

	---@type { name: string, cmd: string }[]
	local actions = {
		-- ── Serve ─────────────────────────────────────────────────────
		{ name = "serve", cmd = cmd .. " serve" },
		{ name = "serve --open", cmd = cmd .. " serve --open" },
		-- ── Build ─────────────────────────────────────────────────────
		{ name = "build (dev)", cmd = cmd .. " build" },
		{ name = "build (prod)", cmd = cmd .. " build --configuration=production" },
		-- ── Test ──────────────────────────────────────────────────────
		{ name = "test", cmd = cmd .. " test" },
		{ name = "test --watch=false", cmd = cmd .. " test --watch=false" },
		{ name = "e2e", cmd = cmd .. " e2e" },
		-- ── Quality ───────────────────────────────────────────────────
		{ name = "lint", cmd = cmd .. " lint" },
		{ name = "lint --fix", cmd = cmd .. " lint --fix" },
		-- ── i18n / Deploy ─────────────────────────────────────────────
		{ name = "extract-i18n", cmd = cmd .. " extract-i18n" },
		{ name = "deploy", cmd = cmd .. " deploy" },
		-- ── Info ───────────────────────────────────────────────────────
		{ name = "config list", cmd = cmd .. " config" },
		{ name = "version", cmd = cmd .. " version" },
		-- ── Package runner ────────────────────────────────────────────
		{ name = runner .. " install", cmd = runner .. " install" },
		{ name = runner .. " outdated", cmd = runner .. " outdated" },
		{ name = runner .. " audit", cmd = runner .. " audit" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = ng_icon .. " Angular:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = ng_icon .. " CLI commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INFO / DOCUMENTATION
--
-- Project introspection and external documentation access.
-- Info detects: Angular version, project features (PWA, SSR, i18n, E2E),
-- and tool availability (ng, tsc, prettier, eslint).
-- ═══════════════════════════════════════════════════════════════════════════

--- Show detailed Angular project information.
---
--- Gathers and displays:
--- - Angular project detection status and CWD
--- - Package runner in use (npm / pnpm / yarn / bun)
--- - `@angular/core` version extracted from `package.json`
--- - Detected features: PWA, E2E, SSR, i18n
--- - Tool availability: ng, tsc, prettier, eslint
---
--- Feature detection heuristics:
--- - PWA:  `ngsw-config.json` exists (Angular service worker config)
--- - E2E:  `e2e/` directory exists
--- - SSR:  `angular.json` contains `"ssr"` or `"server"` target
--- - i18n: `angular.json` contains `"i18n"` configuration
keys.lang_map("htmlangular", "n", "<leader>li", function()
	---@type string[]
	local info = { ng_icon .. " Angular Info:", "" }
	info[#info + 1] = "  Angular:  " .. (is_angular() and "✓" or "✗")
	info[#info + 1] = "  Runner:   " .. pkg_runner()
	info[#info + 1] = "  CWD:      " .. vim.fn.getcwd()

	-- ── Angular version from package.json ─────────────────────────────
	local cwd = vim.fn.getcwd()
	local pkg_json = cwd .. "/package.json"
	if vim.fn.filereadable(pkg_json) == 1 then
		local content = table.concat(vim.fn.readfile(pkg_json), "\n")
		---@type string|nil
		local angular_ver = content:match('"@angular/core"%s*:%s*"(.-)"')
		if angular_ver then info[#info + 1] = "  @angular/core: " .. angular_ver end
	end

	-- ── Feature detection ─────────────────────────────────────────────
	---@type string[]
	local features = {}
	if vim.fn.filereadable(cwd .. "/ngsw-config.json") == 1 then features[#features + 1] = "PWA" end
	if vim.fn.isdirectory(cwd .. "/e2e") == 1 then features[#features + 1] = "E2E" end

	local angular_json = cwd .. "/angular.json"
	if vim.fn.filereadable(angular_json) == 1 then
		local aj_content = table.concat(vim.fn.readfile(angular_json), "\n")
		if aj_content:match('"ssr"') or aj_content:match('"server"') then features[#features + 1] = "SSR" end
		if aj_content:match('"i18n"') then features[#features + 1] = "i18n" end
	end

	if #features > 0 then info[#info + 1] = "  Features: " .. table.concat(features, ", ") end

	-- ── Tool availability ─────────────────────────────────────────────
	---@type string[]
	local tools = { "ng", "tsc", "prettier", "eslint" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		---@type string
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Angular" })
end, { desc = icons.diagnostics.Info .. " Project info" })

--- Open Angular documentation in the default browser.
---
--- Presents 7 curated reference links via `vim.ui.select()`:
--- 1. Angular Docs         — https://angular.dev/
--- 2. Angular API          — https://angular.dev/api
--- 3. Angular CLI          — https://angular.dev/tools/cli
--- 4. RxJS Docs            — https://rxjs.dev/
--- 5. NgRx (State Mgmt)    — https://ngrx.io/
--- 6. Angular Material     — https://material.angular.io/
--- 7. Angular Update Guide — https://angular.dev/update-guide
keys.lang_map("htmlangular", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Angular Docs", url = "https://angular.dev/" },
		{ name = "Angular API Reference", url = "https://angular.dev/api" },
		{ name = "Angular CLI Reference", url = "https://angular.dev/tools/cli" },
		{ name = "RxJS Docs", url = "https://rxjs.dev/" },
		{ name = "NgRx (State Management)", url = "https://ngrx.io/" },
		{ name = "Angular Material", url = "https://material.angular.io/" },
		{ name = "Angular Update Guide", url = "https://angular.dev/update-guide" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = ng_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Angular-specific alignment presets when mini.align is
-- available. Loaded once per session (guarded by is_language_loaded).
--
-- Preset: angular_bindings — align Angular template attribute bindings
-- on the '=' character (e.g. `[ngClass]="..."`, `(click)="..."`).
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("angular") then
		---@type string Alignment preset icon from icons.lang
		local angular_icon = icons.lang.angular

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			angular_bindings = {
				description = "Align Angular template bindings on '='",
				icon = angular_icon,
				split_pattern = "=",
				category = "web",
				lang = "angular",
				filetypes = { "html", "typescript" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("angular", "angular_bindings")
		align_registry.mark_language_loaded("angular")

		-- ── Alignment keymap ─────────────────────────────────────────
		keys.lang_map("angular", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("angular_bindings"), {
			desc = angular_icon .. "  Align Angular bindings",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Angular-specific
-- parts (servers, formatters, linters, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for Angular                │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (angularls added to servers)      │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.htmlangular)    │
-- │ nvim-lint          │ opts merge (linters_by_ft.htmlangular)       │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Angular
return {
	-- ── LSP SERVER ────────────────────────────────────────────────────
	-- angularls: Angular Language Service providing completions,
	-- diagnostics, go-to-definition, and template type checking
	-- for Angular templates and TypeScript files.
	-- ──────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				angularls = {
					filetypes = { "htmlangular", "typescript", "html" },
				},
			},
		},
		init = function()
			-- ── Filetype detection ────────────────────────────────────
			-- Angular templates use "htmlangular" filetype (Neovim 0.10+).
			-- Reinforce detection for common naming patterns that may not
			-- be auto-detected outside of Angular project context.
			vim.filetype.add({
				pattern = {
					[".*%.component%.html$"] = "htmlangular",
					[".*%.template%.html$"] = "htmlangular",
				},
			})

			-- ── Buffer-local options for Angular templates ────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "htmlangular" },
				callback = function()
					local opt = vim.opt_local

					-- ── Layout ────────────────────────────────────────
					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120
					opt.number = true
					opt.relativenumber = true

					-- ── Indentation (Angular convention: 2 spaces) ────
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true

					-- ── Folding (treesitter-based) ────────────────────
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99

					-- ── Comments ──────────────────────────────────────
					opt.commentstring = "<!-- %s -->"
				end,
				desc = "NvimEnterprise: Angular template buffer options",
			})
		end,
	},

	-- ── MASON TOOLS ───────────────────────────────────────────────────
	-- Ensures Angular Language Server, Prettier, and ESLint LSP are
	-- installed and managed by Mason.
	-- ──────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"angular-language-server",
				"prettier",
				"eslint-lsp",
			},
		},
	},

	-- ── FORMATTER ─────────────────────────────────────────────────────
	-- Prettier for Angular templates (htmlangular filetype).
	-- Prettier auto-detects Angular template syntax and handles
	-- interpolation brackets, structural directives, and pipes.
	-- ──────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				htmlangular = { "prettier" },
			},
		},
	},

	-- ── LINTER ────────────────────────────────────────────────────────
	-- eslint_d (daemon mode) for fast Angular template linting.
	-- Requires @angular-eslint to be configured in the project's
	-- .eslintrc or eslint.config.js.
	-- ──────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				htmlangular = { "eslint_d" },
			},
		},
	},

	-- ── TREESITTER PARSERS ────────────────────────────────────────────
	-- angular:    Angular template syntax (structural directives, pipes)
	-- html:       Base HTML parsing (inherited by angular parser)
	-- typescript: Component class files
	-- css/scss:   Component styles
	-- ──────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"angular",
				"html",
				"typescript",
				"css",
				"scss",
			},
		},
	},
}
