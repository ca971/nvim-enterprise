---@file lua/langs/ember.lua
---@description Ember.js / Handlebars — LSP, formatter, treesitter & buffer-local keymaps
---@module "langs.ember"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see langs.python             Python language support (same architecture)
---@see langs.elm                Elm language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/ember.lua — Ember.js / Handlebars template support                ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("ember") → {} if off        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "handlebars" /               │    ║
--- ║  │             "html.handlebars"):                                  │    ║
--- ║  │  ├─ LSP          ember-language-server (completions, diagnostics)│    ║
--- ║  │  ├─ Formatter    prettier --parser glimmer (via conform.nvim)    │    ║
--- ║  │  ├─ Linter       — (via ember-language-server diagnostics)       │    ║
--- ║  │  ├─ Treesitter   glimmer parser (Handlebars/Glimmer templates)   │    ║
--- ║  │  ├─ DAP          — (not applicable for templates)                │    ║
--- ║  │  └─ Extras       ember-cli integration (serve, build, generate)  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ SERVE     r  ember serve           R  ember build (env picker│    ║
--- ║  │  ├─ TEST      t  ember test            T  ember test --server    │    ║
--- ║  │  ├─ GENERATE  g  Generate (blueprint picker + name prompt)       │    ║
--- ║  │  │            d  Destroy (blueprint picker + name prompt)        │    ║
--- ║  │  ├─ ADDON     i  Install addon                                   │    ║
--- ║  │  ├─ COMMANDS  c  Ember commands (picker)                         │    ║
--- ║  │  ├─ TOOLS     e  Ember Inspector (browser)                       │    ║
--- ║  │  │            s  Format (prettier --parser glimmer)              │    ║
--- ║  │  └─ DOCS      h  Documentation (browser)                         │    ║
--- ║  │                                                                  │    ║
--- ║  │  ember-cli resolution:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. ./node_modules/.bin/ember — project-local (highest)  │    │    ║
--- ║  │  │  2. npx ember — if ember-cli-build.js exists in CWD      │    │    ║
--- ║  │  │  3. ember — globally installed                           │    │    ║
--- ║  │  │  4. nil — not found, notify with install instructions    │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Ember project detection:                                        │    ║
--- ║  │  • ember-cli-build.js in CWD                                     │    ║
--- ║  │  • .ember-cli in CWD                                             │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType handlebars/html.handlebars):        ║
--- ║  • colorcolumn=120, textwidth=120 (template line length)                 ║
--- ║  • tabstop=2, shiftwidth=2        (Ember convention: 2-space indent)     ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • commentstring="{{!-- %s --}}"  (Handlebars block comments)            ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .hbs → handlebars                                                     ║
--- ║  • app/templates/*.hbs → handlebars                                      ║
--- ║  • app/components/*.hbs → handlebars                                     ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Ember support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("ember") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Ember Nerd Font icon (trailing whitespace stripped)
local ember_icon = icons.lang.ember:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUPS
--
-- Registers the <leader>l group label for Handlebars buffers.
-- Both groups are buffer-local and only visible in their respective filetypes.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("handlebars", "Ember", ember_icon)
keys.lang_group("html.handlebars", "Ember", ember_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS
--
-- Shared constants used throughout the module.
-- ═══════════════════════════════════════════════════════════════════════════

---@type string[] Filetypes that receive Ember keymaps
local hbs_fts = { "handlebars", "html.handlebars" }

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect the ember-cli binary to use.
---
--- Resolution order:
--- 1. `./node_modules/.bin/ember` — project-local (highest priority)
--- 2. `npx ember`                 — if `ember-cli-build.js` exists in CWD
--- 3. `ember`                     — globally installed
--- 4. `nil`                       — not found
---
--- ```lua
--- local cmd = ember_cmd()
--- if cmd then
---   vim.cmd.terminal(cmd .. " serve")
--- end
--- ```
---
---@return string|nil cmd The ember command string, or `nil` if not found
---@private
local function ember_cmd()
	local cwd = vim.fn.getcwd()

	-- ── Strategy 1: project-local binary ─────────────────────────────
	if vim.fn.filereadable(cwd .. "/node_modules/.bin/ember") == 1 then return "./node_modules/.bin/ember" end

	-- ── Strategy 2: npx in an Ember project ──────────────────────────
	if vim.fn.executable("npx") == 1 and vim.fn.filereadable(cwd .. "/ember-cli-build.js") == 1 then
		return "npx ember"
	end

	-- ── Strategy 3: global binary ────────────────────────────────────
	if vim.fn.executable("ember") == 1 then return "ember" end

	return nil
end

--- Check that ember-cli is available and return the command.
---
--- Notifies the user with installation instructions if ember-cli
--- is not found. Wraps `ember_cmd()` with error reporting.
---
--- ```lua
--- local cmd = check_ember()
--- if not cmd then return end
--- ```
---
---@return string|nil cmd The ember command string, or `nil` if not found
---@private
local function check_ember()
	local cmd = ember_cmd()
	if not cmd then
		vim.notify("ember-cli not found\nInstall: npm install -g ember-cli", vim.log.levels.WARN, { title = "Ember" })
	end
	return cmd
end

--- Check if the current working directory is an Ember project.
---
--- Looks for `ember-cli-build.js` or `.ember-cli` configuration files
--- in the current directory.
---
--- ```lua
--- if is_ember_project() then
---   -- safe to run ember-cli commands
--- end
--- ```
---
---@return boolean is_ember `true` if an Ember project is detected
---@private
local function is_ember_project()
	local cwd = vim.fn.getcwd()
	return vim.fn.filereadable(cwd .. "/ember-cli-build.js") == 1 or vim.fn.filereadable(cwd .. "/.ember-cli") == 1
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SERVE / BUILD
--
-- Ember development server and production build commands.
-- ═══════════════════════════════════════════════════════════════════════════

--- Start the Ember development server.
---
--- Launches `ember serve` in a terminal split and notifies the user
--- with the default development URL (http://localhost:4200).
keys.lang_map(hbs_fts, "n", "<leader>lr", function()
	local cmd = check_ember()
	if not cmd then return end
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " serve")
	vim.notify("Ember serve at http://localhost:4200", vim.log.levels.INFO, { title = "Ember" })
end, { desc = icons.ui.Play .. " Ember serve" })

--- Build the Ember application for a specific environment.
---
--- Presents a picker with build environments:
--- • development — unminified, source maps, debug helpers
--- • production  — minified, tree-shaken, fingerprinted
--- • test        — test-specific configuration
keys.lang_map(hbs_fts, "n", "<leader>lR", function()
	local cmd = check_ember()
	if not cmd then return end

	---@type string[]
	local envs = { "development", "production", "test" }

	vim.ui.select(envs, { prompt = ember_icon .. " Build environment:" }, function(env)
		if not env then return end
		vim.cmd.split()
		vim.cmd.terminal(cmd .. " build --environment=" .. env)
	end)
end, { desc = icons.dev.Build .. " Ember build" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
--
-- Ember test execution via ember-cli.
-- Supports both single-run and persistent server modes.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run the Ember test suite (single run).
---
--- Executes `ember test` which builds and runs all tests once.
keys.lang_map(hbs_fts, "n", "<leader>lt", function()
	local cmd = check_ember()
	if not cmd then return end
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " test")
end, { desc = icons.dev.Test .. " Ember test" })

--- Run Ember tests in server mode.
---
--- Executes `ember test --server` which starts a persistent test
--- server that re-runs tests on file changes (similar to watch mode).
keys.lang_map(hbs_fts, "n", "<leader>lT", function()
	local cmd = check_ember()
	if not cmd then return end
	vim.cmd.split()
	vim.cmd.terminal(cmd .. " test --server")
end, { desc = icons.dev.Test .. " Test --server" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — GENERATE / DESTROY
--
-- Ember blueprint scaffolding and teardown.
-- Uses ember-cli's generate and destroy commands with a blueprint picker
-- and name prompt.
-- ═══════════════════════════════════════════════════════════════════════════

--- Generate an Ember artifact from a blueprint.
---
--- Presents a picker with common blueprints:
--- • component, route, controller, model, service, helper
--- • mixin, adapter, serializer, initializer, template, util, test
---
--- Prompts for the artifact name after blueprint selection.
keys.lang_map(hbs_fts, "n", "<leader>lg", function()
	local cmd = check_ember()
	if not cmd then return end

	---@type string[]
	local blueprints = {
		"component",
		"route",
		"controller",
		"model",
		"service",
		"helper",
		"mixin",
		"adapter",
		"serializer",
		"initializer",
		"template",
		"util",
		"test",
	}

	vim.ui.select(blueprints, { prompt = ember_icon .. " Generate:" }, function(bp)
		if not bp then return end
		vim.ui.input({ prompt = "Name: " }, function(name)
			if not name or name == "" then return end
			vim.cmd.split()
			vim.cmd.terminal(cmd .. " generate " .. bp .. " " .. vim.fn.shellescape(name))
		end)
	end)
end, { desc = ember_icon .. " Generate" })

--- Destroy (remove) a previously generated Ember artifact.
---
--- Presents a picker with common destructible blueprints:
--- • component, route, controller, model, service, helper
---
--- Prompts for the artifact name after blueprint selection.
--- The destroy command undoes what `ember generate` created.
keys.lang_map(hbs_fts, "n", "<leader>ld", function()
	local cmd = check_ember()
	if not cmd then return end

	---@type string[]
	local blueprints = {
		"component",
		"route",
		"controller",
		"model",
		"service",
		"helper",
	}

	vim.ui.select(blueprints, { prompt = ember_icon .. " Destroy:" }, function(bp)
		if not bp then return end
		vim.ui.input({ prompt = "Name: " }, function(name)
			if not name or name == "" then return end
			vim.cmd.split()
			vim.cmd.terminal(cmd .. " destroy " .. bp .. " " .. vim.fn.shellescape(name))
		end)
	end)
end, { desc = ember_icon .. " Destroy" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — ADDON / COMMANDS
--
-- Ember addon management and general command picker.
-- ═══════════════════════════════════════════════════════════════════════════

--- Install an Ember addon.
---
--- Prompts for the addon name, then runs `ember install <addon>`
--- in a terminal split. Ember addons are npm packages with
--- additional blueprint generators.
keys.lang_map(hbs_fts, "n", "<leader>li", function()
	local cmd = check_ember()
	if not cmd then return end
	vim.ui.input({ prompt = "Addon name: " }, function(addon)
		if not addon or addon == "" then return end
		vim.cmd.split()
		vim.cmd.terminal(cmd .. " install " .. vim.fn.shellescape(addon))
	end)
end, { desc = icons.ui.Package .. " Install addon" })

--- Open a picker with common Ember and npm commands.
---
--- Available actions:
--- • serve, build, test           — core ember-cli commands
--- • lint, lint:fix               — npm script-based linting
--- • version, help                — ember-cli info
--- • npm install, npm outdated    — dependency management
keys.lang_map(hbs_fts, "n", "<leader>lc", function()
	local cmd = check_ember()
	if not cmd then return end

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "serve", cmd = cmd .. " serve" },
		{ name = "build", cmd = cmd .. " build" },
		{ name = "test", cmd = cmd .. " test" },
		{ name = "lint", cmd = "npm run lint" },
		{ name = "lint:fix", cmd = "npm run lint:fix" },
		{ name = "version", cmd = cmd .. " version" },
		{ name = "help", cmd = cmd .. " help" },
		{ name = "npm install", cmd = "npm install" },
		{ name = "npm outdated", cmd = "npm outdated" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = ember_icon .. " Ember:" },
		function(_, idx)
			if not idx then return end
			vim.cmd.split()
			vim.cmd.terminal(actions[idx].cmd)
		end
	)
end, { desc = ember_icon .. " Commands" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- Development utilities: Ember Inspector and manual formatting.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the Ember Inspector GitHub page in the system browser.
---
--- The Ember Inspector is a browser extension for debugging
--- Ember applications (component tree, routes, data, deprecations).
keys.lang_map(hbs_fts, "n", "<leader>le", function()
	vim.ui.open("https://github.com/emberjs/ember-inspector")
end, { desc = ember_icon .. " Ember Inspector" })

--- Format the current file with prettier (Glimmer parser).
---
--- Tool resolution:
--- 1. `prettier` — globally installed (highest priority)
--- 2. `npx prettier` — project-local via npx
--- 3. Notification with install instructions if neither found
---
--- Uses `--parser glimmer` to correctly parse Handlebars/Glimmer
--- template syntax in `.hbs` files.
keys.lang_map(hbs_fts, "n", "<leader>ls", function()
	if vim.fn.executable("prettier") ~= 1 and vim.fn.executable("npx") ~= 1 then
		vim.notify("Install prettier: npm install -g prettier", vim.log.levels.WARN, { title = "Ember" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local prettier = vim.fn.executable("prettier") == 1 and "prettier" or "npx prettier"
	local result = vim.fn.system(prettier .. " --parser glimmer --write " .. vim.fn.shellescape(file) .. " 2>&1")
	if vim.v.shell_error == 0 then
		vim.cmd.edit()
		vim.notify("Formatted", vim.log.levels.INFO, { title = "Ember" })
	else
		vim.notify("Prettier error:\n" .. result, vim.log.levels.ERROR, { title = "Ember" })
	end
end, { desc = ember_icon .. " Format (glimmer)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to Ember.js documentation and ecosystem resources
-- via the system browser.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open Ember documentation in the system browser.
---
--- Presents a picker with key reference pages:
--- • Ember Guides          — official tutorial and guides
--- • Ember API Docs        — framework API reference
--- • Ember CLI Docs        — build tool documentation
--- • Glimmer Components    — component model documentation
--- • Ember Observer        — addon discovery and quality scores
keys.lang_map(hbs_fts, "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Ember Guides", url = "https://guides.emberjs.com/" },
		{ name = "Ember API Docs", url = "https://api.emberjs.com/" },
		{ name = "Ember CLI Docs", url = "https://cli.emberjs.com/" },
		{ name = "Glimmer Components", url = "https://guides.emberjs.com/release/components/" },
		{ name = "Ember Observer (addons)", url = "https://emberobserver.com/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = ember_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Ember-specific
-- parts (servers, formatters, parsers).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for Ember                  │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig                         │ opts merge (ember server added on require)   │
-- │ mason.nvim                             │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim                           │ opts merge (prettier for handlebars ft)      │
-- │ nvim-treesitter                        │ opts merge (glimmer parser added)            │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: The conform.nvim spec uses a custom `prepend_args` function
-- for prettier to auto-detect .hbs files and pass `--parser glimmer`.
-- This ensures correct formatting for both Handlebars templates and
-- other file types that also use prettier.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Ember
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- ember-language-server: provides completions, diagnostics,
	-- go-to-definition, and find-references for Ember.js projects
	-- (components, helpers, routes, services, models).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				ember = {},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					hbs = "handlebars",
				},
				pattern = {
					[".*/app/templates/.*%.hbs$"] = "handlebars",
					[".*/app/components/.*%.hbs$"] = "handlebars",
				},
			})

			-- ── Buffer-local options for Handlebars files ────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "handlebars", "html.handlebars" },
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
					opt.commentstring = "{{!-- %s --}}"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures ember-language-server and prettier are installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"ember-language-server",
				"prettier",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- prettier with Glimmer parser for Handlebars templates.
	-- The `prepend_args` function auto-detects `.hbs` files and passes
	-- `--parser glimmer` to ensure correct template formatting.
	-- This avoids breaking prettier's behavior for non-Handlebars files.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				handlebars = { "prettier" },
				["html.handlebars"] = { "prettier" },
			},
			formatters = {
				prettier = {
					prepend_args = function(_, ctx)
						if ctx.filename and ctx.filename:match("%.hbs$") then return { "--parser", "glimmer" } end
						return {}
					end,
				},
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- glimmer: syntax highlighting, folding, text objects for
	--          Handlebars/Glimmer templates (.hbs files).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"glimmer",
			},
		},
	},
}
