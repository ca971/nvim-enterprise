---@file lua/langs/toml.lua
---@description TOML — LSP, formatter, treesitter & buffer-local keymaps
---@module "langs.toml"
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
--- ║  langs/toml.lua — TOML language support                                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("toml") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "toml"):                     │    ║
--- ║  │  ├─ LSP          taplo  (completions, diagnostics, hover,        │    ║
--- ║  │  │               schema validation)                              │    ║
--- ║  │  ├─ Formatter    taplo  (via conform.nvim)                       │    ║
--- ║  │  ├─ Treesitter   toml parser (syntax + folding)                  │    ║
--- ║  │  └─ Extras       conversion · sorting · path copy · stats        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ VALIDATE  r  Validate (taplo check)                          │    ║
--- ║  │  │            p  Pretty-print / format (taplo fmt)               │    ║
--- ║  │  ├─ CONVERT   j  Convert to JSON (yq > taplo > python3)          │    ║
--- ║  │  │            y  Convert to YAML (yq)                            │    ║
--- ║  │  ├─ SORT      s  Sort keys (taplo fmt --reorder_keys)            │    ║
--- ║  │  ├─ PATH      c  Copy TOML key path at cursor to clipboard       │    ║
--- ║  │  ├─ FOLD      f  Toggle fold level (collapse/expand all)         │    ║
--- ║  │  ├─ STATS     i  Document statistics (tables, arrays, KV, etc.)  │    ║
--- ║  │  └─ DOCS      h  TOML specification (toml.io v1.0.0)             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Taplo CLI resolution:                                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. taplo executable → taplo (installed via Mason/cargo) │    │    ║
--- ║  │  │  2. nil              → user notification with install cmd│    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  TOML → JSON conversion resolution:                              │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. yq executable    → yq -p=toml -o=json                │    │    ║
--- ║  │  │  2. taplo executable → taplo get -o json                 │    │    ║
--- ║  │  │  3. python3          → tomllib + json (stdlib)           │    │    ║
--- ║  │  │  4. nil              → user notification                 │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  TOML → YAML conversion:                                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. yq executable → yq -p=toml -o=yaml                   │    │    ║
--- ║  │  │  2. nil           → user notification                    │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Key path copy algorithm:                                        │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Walk lines 1..cursor_row for [table] / [[array]]     │    │    ║
--- ║  │  │  2. Parse section header into path segments              │    │    ║
--- ║  │  │  3. If cursor line has key=value → append key            │    │    ║
--- ║  │  │  4. Copy "section.subsection.key" to system clipboard    │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType toml):                              ║
--- ║  • colorcolumn=100                 (TOML convention)                     ║
--- ║  • tabstop=2, shiftwidth=2         (2-space indentation)                 ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="# %s"           (TOML uses # comments)                 ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .toml → toml                                                          ║
--- ║  • Cargo.toml, pyproject.toml, Pipfile, stylua.toml, .taplo.toml → toml  ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if TOML support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("toml") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string TOML Nerd Font icon (trailing whitespace stripped)
local toml_icon = icons.lang.toml:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for TOML buffers.
-- The group is buffer-local and only visible when filetype == "toml".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("toml", "TOML", toml_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the taplo CLI is available in PATH.
---
--- Notifies the user with install instructions if `taplo` is not found.
--- Used as a guard in keymaps that require the taplo binary.
---
--- ```lua
--- if not check_taplo() then return end
--- vim.fn.system("taplo check file.toml")
--- ```
---
---@return boolean available `true` if `taplo` is executable
---@private
local function check_taplo()
	if vim.fn.executable("taplo") ~= 1 then
		vim.notify("Install: cargo install taplo-cli", vim.log.levels.WARN, { title = "TOML" })
		return false
	end
	return true
end

--- Open a conversion result in a vertical split scratch buffer.
---
--- Creates a new scratch buffer, sets its content and filetype,
--- then opens it in a vertical split. The buffer is wiped when
--- hidden.
---
---@param content string The converted content (JSON, YAML, etc.)
---@param filetype string The filetype to set on the scratch buffer
---@private
local function open_conversion_buffer(content, filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
	vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.cmd.vsplit()
	vim.api.nvim_win_set_buf(0, buf)
end

--- Get the current buffer content as a single string.
---
---@return string content All buffer lines joined with newlines
---@private
local function get_buffer_content()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	return table.concat(lines, "\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — VALIDATE / FORMAT
--
-- TOML validation and formatting via the taplo CLI.
-- Validate uses `taplo check` for pass/fail diagnostics.
-- Format uses `taplo fmt` for in-place canonical formatting.
-- ═══════════════════════════════════════════════════════════════════════════

--- Validate the current TOML file.
---
--- Runs `taplo check` which validates the file against the TOML
--- specification. Reports pass/fail via notifications.
--- Requires `taplo` to be installed.
keys.lang_map("toml", "n", "<leader>lr", function()
	if not check_taplo() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("taplo check " .. vim.fn.shellescape(file) .. " 2>&1")

	if vim.v.shell_error == 0 then
		vim.notify("✓ Valid TOML", vim.log.levels.INFO, { title = "TOML" })
	else
		vim.notify("✗ Errors:\n" .. result, vim.log.levels.ERROR, { title = "TOML" })
	end
end, { desc = icons.ui.Check .. " Validate" })

--- Format the current TOML file with taplo.
---
--- Saves the buffer, runs `taplo fmt` in-place, then reloads
--- the buffer to reflect changes. Reports success or error
--- via notifications.
keys.lang_map("toml", "n", "<leader>lp", function()
	if not check_taplo() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("taplo fmt " .. vim.fn.shellescape(file) .. " 2>&1")

	if vim.v.shell_error == 0 then
		vim.cmd.edit()
		vim.notify("Formatted", vim.log.levels.INFO, { title = "TOML" })
	else
		vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "TOML" })
	end
end, { desc = toml_icon .. " Format (taplo)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CONVERSION
--
-- Format conversion from TOML to JSON or YAML.
-- Results are displayed in a vertical split scratch buffer.
-- Multiple conversion tools are supported with automatic fallback.
-- ═══════════════════════════════════════════════════════════════════════════

--- Convert the current TOML file to JSON.
---
--- Tool resolution:
--- 1. `yq` → `yq -p=toml -o=json` (fastest, most reliable)
--- 2. `taplo` → `taplo get -o json`
--- 3. `python3` → `tomllib` + `json` (Python 3.11+ stdlib)
--- 4. None → notification with install suggestion
---
--- The result is displayed in a vertical split scratch buffer
--- with filetype set to `json`.
keys.lang_map("toml", "n", "<leader>lj", function()
	---@type string|nil
	local cmd
	if vim.fn.executable("yq") == 1 then
		cmd = "yq -p=toml -o=json"
	elseif vim.fn.executable("taplo") == 1 then
		cmd = "taplo get -o json"
	elseif vim.fn.executable("python3") == 1 then
		cmd = "python3 -c 'import sys,tomllib,json; print(json.dumps(tomllib.load(sys.stdin.buffer),indent=2))'"
	else
		vim.notify("Install yq or taplo", vim.log.levels.WARN, { title = "TOML" })
		return
	end

	local content = get_buffer_content()
	local result = vim.fn.system(cmd, content)

	if vim.v.shell_error ~= 0 then
		vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "TOML" })
		return
	end

	open_conversion_buffer(result, "json")
end, { desc = icons.file.Json .. " To JSON" })

--- Convert the current TOML file to YAML.
---
--- Requires `yq` (the only tool supporting TOML → YAML conversion).
--- The result is displayed in a vertical split scratch buffer
--- with filetype set to `yaml`.
keys.lang_map("toml", "n", "<leader>ly", function()
	if vim.fn.executable("yq") ~= 1 then
		vim.notify("Install: brew install yq", vim.log.levels.WARN, { title = "TOML" })
		return
	end

	local content = get_buffer_content()
	local result = vim.fn.system("yq -p=toml -o=yaml", content)

	if vim.v.shell_error ~= 0 then
		vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "TOML" })
		return
	end

	open_conversion_buffer(result, "yaml")
end, { desc = icons.file.Yaml .. " To YAML" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SORT / PATH
--
-- Key sorting via taplo and TOML key path extraction.
-- Sort uses taplo's `reorder_keys` option for canonical ordering.
-- Path copy walks the AST-like structure to build a dotted path.
-- ═══════════════════════════════════════════════════════════════════════════

--- Sort all TOML keys alphabetically.
---
--- Runs `taplo fmt --option reorder_keys=true` which formats the
--- file AND reorders all keys within each table alphabetically.
--- Reloads the buffer to reflect changes.
keys.lang_map("toml", "n", "<leader>ls", function()
	if not check_taplo() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("taplo fmt --option reorder_keys=true " .. vim.fn.shellescape(file) .. " 2>&1")

	if vim.v.shell_error == 0 then
		vim.cmd.edit()
		vim.notify("Keys sorted", vim.log.levels.INFO, { title = "TOML" })
	else
		vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "TOML" })
	end
end, { desc = toml_icon .. " Sort keys" })

--- Copy the TOML key path at the cursor to the system clipboard.
---
--- Algorithm:
--- 1. Walk lines 1..cursor_row scanning for `[table]` / `[[array]]`
---    headers to build the current section path
--- 2. Parse the header into dotted path segments
--- 3. If the cursor line contains a `key = value` assignment, append
---    the key name to the section path
--- 4. Copy the full dotted path to the `+` register (system clipboard)
---
--- Examples:
--- - Cursor on `name = "foo"` under `[package]` → copies `package.name`
--- - Cursor on `[dependencies]` header → copies `dependencies`
--- - Cursor on `version = "1.0"` under `[package.metadata]` → copies
---   `package.metadata.version`
keys.lang_map("toml", "n", "<leader>lc", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	---@type integer
	local row = vim.api.nvim_win_get_cursor(0)[1]

	-- ── Walk backwards to find the current section header ────────
	---@type string[]
	local sections = {}
	for i = 1, row do
		local header = lines[i]:match("^%[([^%]]+)%]")
		if header then
			-- Handle nested: [[array]] vs [table]
			local clean = header:gsub("^%[", ""):gsub("%]$", "")
			sections = vim.split(clean, "%.", { plain = false })
		end
	end

	-- ── Extract key on the current line (if any) ─────────────────
	---@type string|nil
	local current_key = lines[row]:match("^([%w_%-%.]+)%s*=")

	---@type string
	local path
	if current_key then
		path = table.concat(sections, ".") .. "." .. current_key
	else
		path = table.concat(sections, ".")
	end

	vim.fn.setreg("+", path)
	vim.notify("Copied: " .. path, vim.log.levels.INFO, { title = "TOML" })
end, { desc = toml_icon .. " Copy key path" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FOLD / STATS / DOCUMENTATION
--
-- Fold management, document statistics, and TOML specification access.
-- Stats are computed by parsing the buffer with pattern matching.
-- ═══════════════════════════════════════════════════════════════════════════

--- Toggle fold level between fully collapsed and fully expanded.
---
--- If any folds are open (`foldlevel > 0`), collapses all folds.
--- Otherwise, expands all folds. Provides a quick way to get
--- an overview of the document structure.
keys.lang_map("toml", "n", "<leader>lf", function()
	if vim.wo.foldlevel > 0 then
		vim.cmd("normal! zM")
		vim.notify("Folds: collapsed", vim.log.levels.INFO, { title = "TOML" })
	else
		vim.cmd("normal! zR")
		vim.notify("Folds: expanded", vim.log.levels.INFO, { title = "TOML" })
	end
end, { desc = toml_icon .. " Toggle fold" })

--- Display document statistics for the current TOML file.
---
--- Parses the current buffer line-by-line to count:
--- - **Lines**: total line count
--- - **Tables**: `[section]` headers
--- - **Arrays**: `[[array]]` headers
--- - **KV pairs**: `key = value` assignments
--- - **Comments**: lines starting with `#`
---
--- Results are displayed in a notification popup.
keys.lang_map("toml", "n", "<leader>li", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	---@type integer
	local tables = 0
	---@type integer
	local arrays = 0
	---@type integer
	local kv_pairs = 0
	---@type integer
	local comments = 0

	for _, line in ipairs(lines) do
		if line:match("^%s*#") then
			comments = comments + 1
		elseif line:match("^%[%[.+%]%]") then
			arrays = arrays + 1
		elseif line:match("^%[.+%]") then
			tables = tables + 1
		elseif line:match("^[%w_%-%.]+%s*=") then
			kv_pairs = kv_pairs + 1
		end
	end

	vim.notify(
		string.format(
			"%s TOML Stats:\n"
				.. "  Lines:     %d\n"
				.. "  Tables:    %d\n"
				.. "  Arrays:    %d\n"
				.. "  KV pairs:  %d\n"
				.. "  Comments:  %d",
			toml_icon,
			#lines,
			tables,
			arrays,
			kv_pairs,
			comments
		),
		vim.log.levels.INFO,
		{ title = "TOML" }
	)
end, { desc = icons.diagnostics.Info .. " Stats" })

--- Open the TOML specification in the system browser.
---
--- Opens the official TOML v1.0.0 specification at toml.io.
keys.lang_map("toml", "n", "<leader>lh", function()
	vim.ui.open("https://toml.io/en/v1.0.0")
end, { desc = icons.ui.Note .. " TOML spec" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers TOML-specific alignment presets for mini.align:
-- • toml_pairs — align key-value pairs on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("toml") then
		---@type string Alignment preset icon from icons.file
		local toml_align_icon = icons.file.Toml

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			toml_pairs = {
				description = "Align TOML key-value pairs on '='",
				icon = toml_align_icon,
				split_pattern = "=",
				category = "data",
				lang = "toml",
				filetypes = { "toml" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("toml", "toml_pairs")
		align_registry.mark_language_loaded("toml")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("toml", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("toml_pairs"), {
			desc = toml_align_icon .. "  Align TOML pairs",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the TOML-specific
-- parts (servers, formatters, parsers, filetype extensions).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for TOML                   │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (taplo server + settings)         │
-- │ mason.nvim         │ opts merge (taplo ensured)                   │
-- │ conform.nvim       │ opts merge (taplo formatter for toml)        │
-- │ nvim-treesitter    │ opts merge (toml parser ensured)             │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for TOML
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- taplo: TOML Language Server (completions, diagnostics, hover,
	-- schema validation for known files like Cargo.toml, pyproject.toml).
	--
	-- Settings:
	-- • formatting.alignEntries: false (don't align = signs by default)
	-- • schema.enabled: true (validate against known TOML schemas)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				taplo = {
					settings = {
						taplo = {
							formatting = { alignEntries = false },
							schema = { enabled = true },
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					toml = "toml",
				},
				filename = {
					["Cargo.toml"] = "toml",
					["pyproject.toml"] = "toml",
					["Pipfile"] = "toml",
					["stylua.toml"] = "toml",
					[".taplo.toml"] = "toml",
				},
			})

			-- ── Buffer-local options for TOML files ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "toml" },
				callback = function()
					local opt = vim.opt_local

					opt.wrap = false
					opt.colorcolumn = "100"

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
	-- Ensures taplo is installed via Mason.
	-- Taplo serves as both the LSP server and the CLI formatter.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"taplo",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- Taplo as formatter via conform.nvim.
	-- Uses taplo's built-in formatting engine (same as `taplo fmt`).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				toml = { "taplo" },
			},
		},
	},

	-- ── TREESITTER PARSER ──────────────────────────────────────────────────
	-- toml: syntax highlighting, folding, indentation
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"toml",
			},
		},
	},
}
