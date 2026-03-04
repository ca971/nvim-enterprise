---@file lua/langs/helm.lua
---@description Helm — LSP, treesitter & buffer-local keymaps for chart templates
---@module "langs.helm"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.docker             Docker language support (same devops category)
---@see langs.python             Python language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/helm.lua — Helm chart template support                            ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("helm") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "helm"):                     │    ║
--- ║  │  ├─ LSP          helm_ls (Helm Language Server, delegates to     │    ║
--- ║  │  │                         yamlls for YAML intelligence)         │    ║
--- ║  │  ├─ Formatter    — (none, Helm templates are not auto-formatted) │    ║
--- ║  │  ├─ Linter       helm lint (via keymap, chart-level linting)     │    ║
--- ║  │  ├─ Treesitter   gotmpl · yaml parsers                           │    ║
--- ║  │  ├─ DAP          — (not applicable for templates)                │    ║
--- ║  │  └─ Extras       helm CLI integration (template, lint, package)  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ TEMPLATE  r  Render template       R  Render with values     │    ║
--- ║  │  │            t  Template dry-run       T  Template with debug   │    ║
--- ║  │  ├─ LINT      l  Lint chart            L  Lint strict mode       │    ║
--- ║  │  ├─ DEPS      d  Show dependencies     D  Update dependencies    │    ║
--- ║  │  ├─ VALUES    v  Show computed values   V  Values with overrides │    ║
--- ║  │  ├─ PACKAGE   p  Package chart (.tgz)                            │    ║
--- ║  │  ├─ SEARCH    s  Search Artifact Hub (CLI or browser)            │    ║
--- ║  │  └─ DOCS      i  Chart info (Chart.yaml) h  Helm docs (browser)  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Chart root detection:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Walk upward from current file directory              │    │    ║
--- ║  │  │  2. Search for Chart.yaml using vim.fn.findfile()        │    │    ║
--- ║  │  │  3. Return parent directory of Chart.yaml                │    │    ║
--- ║  │  │  4. nil if not found → notify user                       │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType helm):                              ║
--- ║  • colorcolumn=120, textwidth=120 (template line length)                 ║
--- ║  • tabstop=2, shiftwidth=2        (YAML-style 2-space indent)            ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • commentstring="{{/* %s */}}"   (Go template block comments)           ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .gotmpl → helm                                                        ║
--- ║  • templates/*.yaml, templates/*.yml, templates/*.tpl → helm             ║
--- ║  • templates/_*.tpl → helm (partials)                                    ║
--- ║  • Chart.yaml, values.yaml → helm                                        ║
--- ║  • helmfile*.yaml, helmfile*.yml → helm                                  ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Helm support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("helm") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Helm icon (trailing whitespace stripped, fallback to ⎈)
local helm_icon = icons.lang.helm and icons.lang.helm:gsub("%s+$", "") or "⎈"

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Helm buffers.
-- The group is buffer-local and only visible when filetype == "helm".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("helm", "Helm", helm_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Find the Helm chart root directory by walking upward from the current file.
---
--- Uses `vim.fn.findfile()` to search for `Chart.yaml` starting from
--- the current file's directory and walking upward (`;` suffix).
--- Returns the parent directory of the found `Chart.yaml`.
---
--- ```lua
--- local chart = find_chart_root()
--- if chart then
---   vim.cmd.terminal("helm lint " .. chart)
--- end
--- ```
---
---@return string|nil chart_root Absolute path to the chart directory, or `nil`
---@private
local function find_chart_root()
	local file = vim.fn.expand("%:p:h")
	local root = vim.fn.findfile("Chart.yaml", file .. ";")
	if root ~= "" then return vim.fn.fnamemodify(root, ":p:h") end
	return nil
end

--- Check that the helm CLI is available in PATH.
---
--- Notifies the user with installation instructions if helm is not found.
---
--- ```lua
--- if not check_helm() then return end
--- ```
---
---@return boolean available `true` if `helm` is executable, `false` otherwise
---@private
local function check_helm()
	if vim.fn.executable("helm") ~= 1 then
		vim.notify("Install helm: brew install helm", vim.log.levels.WARN, { title = "Helm" })
		return false
	end
	return true
end

--- Check helm availability AND find the chart root.
---
--- Combines `check_helm()` and `find_chart_root()` into a single guard.
--- Notifies the user if either condition fails.
---
--- ```lua
--- local chart = require_chart()
--- if not chart then return end
--- vim.cmd.terminal("helm template " .. vim.fn.shellescape(chart))
--- ```
---
---@return string|nil chart_root The chart directory, or `nil` if helm/chart not found
---@private
local function require_chart()
	if not check_helm() then return nil end
	local chart = find_chart_root()
	if not chart then
		vim.notify("No Chart.yaml found", vim.log.levels.WARN, { title = "Helm" })
		return nil
	end
	return chart
end

--- Discover values files in the chart directory.
---
--- Scans for files matching `values*.yaml` and `values*.yml` patterns
--- in the given chart root directory.
---
---@param chart_root string Absolute path to the chart directory
---@return string[] files List of absolute paths to values files
---@private
local function discover_values_files(chart_root)
	local files = vim.fn.globpath(chart_root, "values*.yaml", false, true)
	vim.list_extend(files, vim.fn.globpath(chart_root, "values*.yml", false, true))
	return files
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEMPLATE RENDERING
--
-- Helm template rendering with optional values file overrides.
-- All rendering happens in a terminal split.
-- ═══════════════════════════════════════════════════════════════════════════

--- Render the Helm chart templates with `helm template`.
---
--- Walks upward to find `Chart.yaml`, then renders all templates
--- in a terminal split.
keys.lang_map("helm", "n", "<leader>lr", function()
	local chart = require_chart()
	if not chart then return end
	vim.cmd.split()
	vim.cmd.terminal("helm template " .. vim.fn.shellescape(chart))
end, { desc = icons.ui.Play .. " Render template" })

--- Render templates with a custom values file override.
---
--- Scans the chart directory for `values*.yaml` / `values*.yml` files.
--- If found, presents a picker to select the values file.
--- If none found, prompts for a file path with completion.
keys.lang_map("helm", "n", "<leader>lR", function()
	local chart = require_chart()
	if not chart then return end

	local values_files = discover_values_files(chart)

	if #values_files == 0 then
		vim.ui.input({ prompt = "Values file path: ", completion = "file" }, function(file)
			if not file or file == "" then return end
			vim.cmd.split()
			vim.cmd.terminal("helm template " .. vim.fn.shellescape(chart) .. " -f " .. vim.fn.shellescape(file))
		end)
		return
	end

	-- ── Picker with discovered values files ──────────────────────────
	---@type string[]
	local display = vim.tbl_map(function(f)
		return vim.fn.fnamemodify(f, ":t")
	end, values_files)

	vim.ui.select(display, { prompt = helm_icon .. " Select values file:" }, function(_, idx)
		if not idx then return end
		vim.cmd.split()
		vim.cmd.terminal("helm template " .. vim.fn.shellescape(chart) .. " -f " .. vim.fn.shellescape(values_files[idx]))
	end)
end, { desc = icons.ui.Play .. " Render with values" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEMPLATE DRY-RUN
--
-- Template rendering in dry-run and debug modes for chart development.
-- ═══════════════════════════════════════════════════════════════════════════

--- Render templates in dry-run mode.
---
--- Runs `helm template --dry-run` which renders templates without
--- actually installing the chart. Useful for validating template output.
keys.lang_map("helm", "n", "<leader>lt", function()
	local chart = require_chart()
	if not chart then return end
	vim.cmd.split()
	vim.cmd.terminal("helm template --dry-run " .. vim.fn.shellescape(chart))
end, { desc = helm_icon .. " Template dry-run" })

--- Render templates with debug output.
---
--- Runs `helm template --debug` which includes computed values and
--- additional diagnostic information in the output.
keys.lang_map("helm", "n", "<leader>lT", function()
	local chart = require_chart()
	if not chart then return end
	vim.cmd.split()
	vim.cmd.terminal("helm template --debug " .. vim.fn.shellescape(chart))
end, { desc = helm_icon .. " Template debug" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — LINT
--
-- Chart linting via `helm lint`. Supports both normal and strict modes.
-- Strict mode treats warnings as errors for CI-like validation.
-- ═══════════════════════════════════════════════════════════════════════════

--- Lint the Helm chart with `helm lint`.
---
--- Validates the chart structure, template syntax, and values schema.
keys.lang_map("helm", "n", "<leader>ll", function()
	local chart = require_chart()
	if not chart then return end
	vim.cmd.split()
	vim.cmd.terminal("helm lint " .. vim.fn.shellescape(chart))
end, { desc = icons.diagnostics.Warn .. " Lint chart" })

--- Lint the chart in strict mode.
---
--- Runs `helm lint --strict` which treats all warnings as errors.
--- Useful for CI pipelines or pre-commit validation.
keys.lang_map("helm", "n", "<leader>lL", function()
	local chart = require_chart()
	if not chart then return end
	vim.cmd.split()
	vim.cmd.terminal("helm lint --strict " .. vim.fn.shellescape(chart))
end, { desc = icons.diagnostics.Error .. " Lint strict" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEPENDENCIES
--
-- Chart dependency inspection and management.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show chart dependencies via `helm dependency list`.
---
--- Displays the dependency table (name, version, repository, status)
--- in a notification.
keys.lang_map("helm", "n", "<leader>ld", function()
	local chart = require_chart()
	if not chart then return end
	local result = vim.fn.system("helm dependency list " .. vim.fn.shellescape(chart) .. " 2>&1")
	vim.notify(result, vim.log.levels.INFO, { title = helm_icon .. " Chart Dependencies" })
end, { desc = icons.ui.Package .. " Show dependencies" })

--- Update chart dependencies with `helm dependency update`.
---
--- Downloads and locks all dependencies defined in `Chart.yaml`.
--- Updates the `charts/` directory and `Chart.lock` file.
keys.lang_map("helm", "n", "<leader>lD", function()
	local chart = require_chart()
	if not chart then return end
	vim.cmd.split()
	vim.cmd.terminal("helm dependency update " .. vim.fn.shellescape(chart))
end, { desc = icons.ui.Package .. " Update dependencies" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — VALUES
--
-- Inspect chart values (defaults and overrides).
-- ═══════════════════════════════════════════════════════════════════════════

--- Show the chart's default values with `helm show values`.
---
--- Displays the full `values.yaml` content in a terminal split.
keys.lang_map("helm", "n", "<leader>lv", function()
	local chart = require_chart()
	if not chart then return end
	vim.cmd.split()
	vim.cmd.terminal("helm show values " .. vim.fn.shellescape(chart))
end, { desc = helm_icon .. " Show values" })

--- Show rendered NOTES.txt with a specific values override file.
---
--- Scans for values files in the chart directory and presents a picker.
--- Renders only the `templates/NOTES.txt` template with the selected
--- values file merged.
keys.lang_map("helm", "n", "<leader>lV", function()
	local chart = require_chart()
	if not chart then return end

	local values_files = discover_values_files(chart)

	if #values_files == 0 then
		vim.notify("No values files found", vim.log.levels.INFO, { title = "Helm" })
		return
	end

	---@type string[]
	local display = vim.tbl_map(function(f)
		return vim.fn.fnamemodify(f, ":t")
	end, values_files)

	vim.ui.select(display, { prompt = helm_icon .. " Select values file:" }, function(_, idx)
		if not idx then return end
		vim.cmd.split()
		vim.cmd.terminal(
			"helm template "
				.. vim.fn.shellescape(chart)
				.. " --show-only templates/NOTES.txt -f "
				.. vim.fn.shellescape(values_files[idx])
		)
	end)
end, { desc = helm_icon .. " Values with overrides" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — INFO / PACKAGE
--
-- Chart metadata inspection and packaging.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show chart metadata from Chart.yaml in a notification.
---
--- Parses `Chart.yaml` and displays key-value pairs (name, version,
--- description, apiVersion, appVersion, etc.).
keys.lang_map("helm", "n", "<leader>li", function()
	local chart = find_chart_root()
	if not chart then
		vim.notify("No Chart.yaml found", vim.log.levels.WARN, { title = "Helm" })
		return
	end

	local chart_file = chart .. "/Chart.yaml"
	if vim.fn.filereadable(chart_file) ~= 1 then
		vim.notify("Chart.yaml not readable", vim.log.levels.WARN, { title = "Helm" })
		return
	end

	local lines = vim.fn.readfile(chart_file)
	---@type string[]
	local info = {}
	for _, line in ipairs(lines) do
		local key, val = line:match("^(%w+):%s*(.+)$")
		if key and val then info[#info + 1] = string.format("  %-15s %s", key .. ":", val) end
	end

	if #info > 0 then
		table.insert(info, 1, helm_icon .. " Chart Info")
		table.insert(info, 2, string.rep("─", 40))
		vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Helm" })
	end
end, { desc = icons.diagnostics.Info .. " Chart info" })

--- Package the chart into a `.tgz` archive.
---
--- Runs `helm package <chart>` which creates a versioned tarball
--- suitable for uploading to a chart repository.
keys.lang_map("helm", "n", "<leader>lp", function()
	local chart = require_chart()
	if not chart then return end
	vim.cmd.split()
	vim.cmd.terminal("helm package " .. vim.fn.shellescape(chart))
end, { desc = icons.ui.Package .. " Package chart" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SEARCH / DOCUMENTATION
--
-- Artifact Hub search and Helm documentation access.
-- ═══════════════════════════════════════════════════════════════════════════

--- Search Artifact Hub for Helm charts.
---
--- If helm CLI is available, runs `helm search hub <query>` in a
--- terminal split. Otherwise falls back to opening Artifact Hub
--- in the system browser.
keys.lang_map("helm", "n", "<leader>ls", function()
	vim.ui.input({ prompt = "Search Artifact Hub: " }, function(query)
		if not query or query == "" then return end
		if vim.fn.executable("helm") == 1 then
			vim.cmd.split()
			vim.cmd.terminal("helm search hub " .. vim.fn.shellescape(query))
		else
			local url = "https://artifacthub.io/packages/search?ts_query_web=" .. vim.fn.escape(query, " ")
			vim.ui.open(url)
		end
	end)
end, { desc = icons.ui.Search .. " Search hub" })

--- Open Helm documentation in the system browser.
keys.lang_map("helm", "n", "<leader>lh", function()
	vim.ui.open("https://helm.sh/docs/")
end, { desc = icons.ui.Note .. " Helm docs" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Helm-specific alignment presets for mini.align:
-- • helm_assign — align template variable assignments on ":="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("helm") then
		---@type string Alignment preset icon from icons.lang
		local align_icon = icons.lang.helm

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			helm_assign = {
				description = "Align Helm template assignments on ':='",
				icon = align_icon,
				split_pattern = ":=",
				category = "devops",
				lang = "helm",
				filetypes = { "helm" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("helm", "helm_assign")
		align_registry.mark_language_loaded("helm")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("helm", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("helm_assign"), {
			desc = align_icon .. "  Align Helm assign",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Helm-specific
-- parts (servers, parsers).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for Helm                   │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig                         │ opts merge (helm_ls server added on require) │
-- │ mason.nvim                             │ opts fn merge (helm-ls added)                │
-- │ nvim-treesitter                        │ opts fn merge (gotmpl + yaml parsers added)  │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Helm templates are YAML with embedded Go template syntax.
-- The helm_ls language server delegates YAML intelligence to yamlls
-- while providing Go template completions and diagnostics. There is
-- no dedicated formatter because Helm templates mix YAML structure
-- with Go template directives, making auto-formatting unreliable.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Helm
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- helm_ls: Helm Language Server providing completions, diagnostics,
	-- and hover for Helm chart templates. Delegates YAML intelligence
	-- to yaml-language-server for structure validation.
	--
	-- Configuration:
	-- • yamlls.enabled = true — enables YAML language server delegation
	-- • yamlls.path = "yaml-language-server" — path to yamlls binary
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				helm_ls = {
					settings = {
						["helm-ls"] = {
							yamlls = {
								enabled = true,
								path = "yaml-language-server",
							},
						},
					},
					filetypes = { "helm" },
				},
			},
		},
		init = function()
			-- ── Filetype detection ───────────────────────────────────
			-- Helm templates are YAML with Go template syntax.
			-- Files inside a chart's templates/ directory are detected
			-- as "helm" filetype for proper LSP and keymap activation.
			vim.filetype.add({
				extension = {
					gotmpl = "helm",
				},
				pattern = {
					[".*/templates/.*%.yaml"] = "helm",
					[".*/templates/.*%.yml"] = "helm",
					[".*/templates/.*%.tpl"] = "helm",
					[".*/templates/_.*%.tpl"] = "helm",
					["Chart%.yaml"] = "helm",
					["values%.yaml"] = "helm",
					["helmfile.*%.yaml"] = "helm",
					["helmfile.*%.yml"] = "helm",
				},
			})

			-- ── Buffer-local options for Helm files ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "helm" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true
					opt.commentstring = "{{/* %s */}}"
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
	-- Ensures helm-ls is installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = function(_, opts)
			opts.ensure_installed = opts.ensure_installed or {}
			vim.list_extend(opts.ensure_installed, { "helm-ls" })
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- gotmpl: Go template syntax highlighting and folding
	-- yaml:   YAML structure highlighting (underlying format)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = function(_, opts)
			opts.ensure_installed = opts.ensure_installed or {}
			vim.list_extend(opts.ensure_installed, { "gotmpl", "yaml" })
		end,
	},
}
