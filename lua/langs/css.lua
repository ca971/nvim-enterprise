---@file lua/langs/css.lua
---@description CSS / SCSS / Less — Styling support, LSP, formatter, linter, color tools
---@module "langs.css"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps               Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons                 Icon provider (`lang.css`, `ui`, `diagnostics`)
---@see core.mini-align-registry   Alignment preset registration for CSS properties
---@see langs.html                 HTML support (shared colorizer, ccc.nvim)
---@see langs.tailwind             Tailwind CSS support (complementary styling)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/css.lua — CSS / SCSS / Less language support                      ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("css") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Multi-filetype module:                                          │    ║
--- ║  │  ├─ css   — standard CSS stylesheets                             │    ║
--- ║  │  ├─ scss  — Sass (SCSS syntax)                                   │    ║
--- ║  │  └─ less  — Less CSS preprocessor                                │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded on ft = "css" | "scss" | "less"):        │    ║
--- ║  │  ├─ LSP         cssls (css, scss, less validation + completion)  │    ║
--- ║  │  ├─ Formatter   prettier (conform.nvim)                          │    ║
--- ║  │  ├─ Linter      stylelint (nvim-lint)                            │    ║
--- ║  │  ├─ Treesitter  css · scss parsers                               │    ║
--- ║  │  ├─ Colorizer   nvim-colorizer.lua (inline color preview)        │    ║
--- ║  │  └─ Color picker ccc.nvim (inline HSL/RGB/Hex picker)            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (buffer-local, <leader>l group, 8 bindings):            │    ║
--- ║  │  ├─ COLOR       c  Color picker (ccc.nvim / fallback)            │    ║
--- ║  │  ├─ ORGANIZE    s  Sort properties alphabetically                │    ║
--- ║  │  ├─ PREVIEW     p  Preview HTML in browser                       │    ║
--- ║  │  ├─ TOOLS       e  Minify (csso / clean-css)                     │    ║
--- ║  │  │              r  Insert CSS reset snippet (3 options)          │    ║
--- ║  │  └─ DOCS        h  MDN docs for property                         │    ║
--- ║  │                 i  CSS specificity calculator                    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Property sorting algorithm:                                     │    ║
--- ║  │  ├─ 1. Find enclosing { } block from cursor position             │    ║
--- ║  │  ├─ 2. Extract non-empty lines between braces                    │    ║
--- ║  │  ├─ 3. Sort by property name (alphabetical)                      │    ║
--- ║  │  └─ 4. Replace lines in-place                                    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Specificity calculator (heuristic):                             │    ║
--- ║  │  ├─ IDs:      #foo → (1, 0, 0)                                   │    ║
--- ║  │  ├─ Classes:  .bar, [attr], :pseudo → (0, 1, 0)                  │    ║
--- ║  │  └─ Elements: div, span → (0, 0, 1)                              │    ║
--- ║  │                                                                  │    ║
--- ║  │  Minification tools (priority order):                            │    ║
--- ║  │  ├─ csso     — CSS Structure Optimizer (most effective)          │    ║
--- ║  │  └─ cleancss — clean-css CLI (fallback)                          │    ║
--- ║  │                                                                  │    ║
--- ║  │  CSS reset snippets (3 options):                                 │    ║
--- ║  │  ├─ Modern Reset   — box-sizing, margin, padding                 │    ║
--- ║  │  ├─ Body Reset     — min-height, line-height, font-smoothing     │    ║
--- ║  │  └─ Media Reset    — img/video block display, max-width          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Mini.align integration:                                         │    ║
--- ║  │  ├─ Preset: css_properties (align on ':')                        │    ║
--- ║  │  └─ <leader>aL  Align CSS / SCSS properties                      │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (set on FileType css, scss, less):                       ║
--- ║  • 2 spaces, expandtab        (web convention)                           ║
--- ║  • colorcolumn=80              (CSS convention)                          ║
--- ║  • treesitter foldexpr         (foldmethod=expr, foldlevel=99)           ║
--- ║                                                                          ║
--- ║  LSP settings (all three languages share unknownAtRules = "ignore"):     ║
--- ║  • Ignores @tailwind, @apply, and other framework-specific at-rules      ║
--- ║  • Validation enabled for property names and values                      ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if CSS support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("css") then
	return {}
end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string CSS Nerd Font icon (trailing whitespace stripped)
local css_icon = icons.lang.css:gsub("%s+$", "")

---@type string[] All CSS-family filetypes that share keymaps and tooling
local css_ft = { "css", "scss", "less" }

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUPS
--
-- Registers the <leader>l group for all three CSS-family filetypes.
-- Each filetype gets its own label but shares the same icon and keymaps.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("css", "CSS", css_icon)
keys.lang_group("scss", "SCSS", css_icon)
keys.lang_group("less", "Less", css_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — COLOR
--
-- Color manipulation tools. Prefers ccc.nvim's inline picker which
-- supports HSL, RGB, and Hex formats with live preview. Falls back
-- to basic hex color detection on the current line.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open color picker for the color value under cursor.
---
--- Strategy:
--- 1. If `ccc.nvim` is loaded → use `:CccPick` (inline picker with live preview)
--- 2. Fallback: scan the current line for hex color patterns (`#RRGGBB` or `#RGB`)
---    and display the found value in a notification
---
--- ccc.nvim supports HSL, RGB, Hex, and named colors. It provides a
--- floating picker that updates the color value in real-time.
keys.lang_map(css_ft, "n", "<leader>lc", function()
	-- ── Strategy 1: ccc.nvim inline picker ────────────────────────────
	if vim.fn.exists(":CccPick") == 2 then
		vim.cmd("CccPick")
		return
	end

	-- ── Strategy 2: basic hex detection ───────────────────────────────
	local line = vim.api.nvim_get_current_line()
	---@type string|nil
	local hex = line:match("#%x%x%x%x%x%x") or line:match("#%x%x%x")
	if hex then
		vim.notify("Color: " .. hex, vim.log.levels.INFO, { title = "CSS" })
	else
		vim.notify("No color value found on this line", vim.log.levels.INFO, { title = "CSS" })
	end
end, { desc = icons.ui.Art .. " Color picker" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SORTING
--
-- Alphabetical property sorting within CSS rule blocks.
-- This is a common code style convention that makes properties
-- easier to find and reduces merge conflicts.
-- ═══════════════════════════════════════════════════════════════════════════

--- Sort CSS properties alphabetically within the current rule block.
---
--- Algorithm:
--- 1. From the cursor position, search backward for `{` (block start)
--- 2. Search forward for `}` (block end)
--- 3. Extract all non-empty lines between the braces
--- 4. Sort by the property name (text before the first `:`)
--- 5. Replace the lines in-place
---
--- Handles multi-line declarations and preserves indentation.
--- Skips empty lines during sorting.
---
--- NOTE: This is a heuristic sort — it may not handle edge cases
--- like multi-value shorthand properties or comments between properties.
keys.lang_map(css_ft, "n", "<leader>ls", function()
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	---@type integer|nil
	local start_line
	---@type integer|nil
	local end_line

	-- ── Search backward for { ─────────────────────────────────────────
	for i = cursor_line, 1, -1 do
		if lines[i]:match("{") then
			start_line = i
			break
		end
	end

	-- ── Search forward for } ──────────────────────────────────────────
	for i = cursor_line, #lines do
		if lines[i]:match("}") then
			end_line = i
			break
		end
	end

	if not start_line or not end_line or end_line - start_line <= 1 then
		vim.notify("No CSS rule block found", vim.log.levels.INFO, { title = "CSS" })
		return
	end

	-- ── Extract, sort, and replace properties ─────────────────────────
	---@type string[]
	local props = {}
	for i = start_line + 1, end_line - 1 do
		local prop = lines[i]
		if prop:match("%S") then
			props[#props + 1] = prop
		end
	end

	table.sort(props, function(a, b)
		---@type string
		local pa = a:match("^%s*([%w-]+)") or ""
		---@type string
		local pb = b:match("^%s*([%w-]+)") or ""
		return pa < pb
	end)

	vim.api.nvim_buf_set_lines(0, start_line, end_line - 1, false, props)
	vim.notify(string.format("Sorted %d properties", #props), vim.log.levels.INFO, { title = "CSS" })
end, { desc = css_icon .. " Sort properties" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — PREVIEW & TOOLS
--
-- Browser preview, CSS minification, and reset snippet insertion.
-- ═══════════════════════════════════════════════════════════════════════════

--- Preview the associated HTML file in the default browser.
---
--- Searches for `.html` files in the current directory and parent
--- directory. If multiple HTML files are found, presents a selection
--- via `vim.ui.select()`. If only one is found, opens it directly.
keys.lang_map(css_ft, "n", "<leader>lp", function()
	local dir = vim.fn.expand("%:p:h")

	---@type string[]
	local html_files = vim.fn.glob(dir .. "/*.html", false, true)
	if #html_files == 0 then
		html_files = vim.fn.glob(dir .. "/../*.html", false, true)
	end

	if #html_files == 0 then
		vim.notify("No HTML file found nearby", vim.log.levels.INFO, { title = "CSS" })
		return
	end

	if #html_files == 1 then
		vim.ui.open(html_files[1])
	else
		vim.ui.select(html_files, { prompt = "Open HTML file:" }, function(choice)
			if choice then
				vim.ui.open(choice)
			end
		end)
	end
end, { desc = icons.status.Remote .. " Preview in browser" })

--- Minify the current CSS file.
---
--- Creates a `.min.css` (or `.min.scss`, `.min.less`) file alongside
--- the source file. Saves the buffer before minification.
---
--- Tool priority:
--- 1. `csso` — CSS Structure Optimizer (best compression via structural optimization)
--- 2. `cleancss` — clean-css CLI (fallback, simpler minification)
---
--- Both tools are available via npm:
--- ```sh
--- npm install -g csso-cli    # or
--- npm install -g clean-css-cli
--- ```
keys.lang_map(css_ft, "n", "<leader>le", function()
	if vim.fn.executable("csso") ~= 1 and vim.fn.executable("cleancss") ~= 1 then
		vim.notify(
			"Install: npm install -g csso-cli\nor: npm install -g clean-css-cli",
			vim.log.levels.WARN,
			{ title = "CSS" }
		)
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local output = vim.fn.expand("%:p:r") .. ".min." .. vim.fn.expand("%:e")

	---@type string
	local cmd
	if vim.fn.executable("csso") == 1 then
		cmd = string.format("csso %s -o %s", vim.fn.shellescape(file), vim.fn.shellescape(output))
	else
		cmd = string.format("cleancss -o %s %s", vim.fn.shellescape(output), vim.fn.shellescape(file))
	end

	vim.fn.system(cmd)
	if vim.v.shell_error == 0 then
		vim.notify("Minified → " .. vim.fn.fnamemodify(output, ":t"), vim.log.levels.INFO, { title = "CSS" })
	else
		vim.notify("Minification failed", vim.log.levels.ERROR, { title = "CSS" })
	end
end, { desc = css_icon .. " Minify" })

--- Insert a CSS reset snippet at the current cursor position.
---
--- Presents 3 modern CSS reset options via `vim.ui.select()`:
--- 1. **Modern Reset (minimal)** — box-sizing, margin, padding reset
--- 2. **Body Reset** — min-height, line-height, font-smoothing
--- 3. **Media Reset** — block display and max-width for media elements
---
--- Based on Josh Comeau's "Custom CSS Reset" and Andy Bell's
--- "A Modern CSS Reset" best practices.
keys.lang_map(css_ft, "n", "<leader>lr", function()
	---@type { name: string, lines: string[] }[]
	local resets = {
		{
			name = "Modern Reset (minimal)",
			lines = {
				"*, *::before, *::after {",
				"  box-sizing: border-box;",
				"  margin: 0;",
				"  padding: 0;",
				"}",
				"",
			},
		},
		{
			name = "Body Reset",
			lines = {
				"body {",
				"  min-height: 100vh;",
				"  line-height: 1.5;",
				"  -webkit-font-smoothing: antialiased;",
				"}",
				"",
			},
		},
		{
			name = "Media Reset",
			lines = {
				"img, picture, video, canvas, svg {",
				"  display: block;",
				"  max-width: 100%;",
				"}",
				"",
			},
		},
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, resets),
		{ prompt = css_icon .. " Insert reset:" },
		function(_, idx)
			if idx then
				local row = vim.api.nvim_win_get_cursor(0)[1]
				vim.api.nvim_buf_set_lines(0, row, row, false, resets[idx].lines)
			end
		end
	)
end, { desc = css_icon .. " CSS reset snippet" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- MDN documentation access and CSS specificity analysis.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open MDN documentation for the CSS property under cursor.
---
--- Navigates to `https://developer.mozilla.org/en-US/docs/Web/CSS/<property>`.
--- Works with standard CSS properties, at-rules, pseudo-classes, etc.
keys.lang_map(css_ft, "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then
		return
	end
	vim.ui.open("https://developer.mozilla.org/en-US/docs/Web/CSS/" .. word)
end, { desc = icons.ui.Note .. " MDN docs" })

--- Show CSS specificity for the selector on the current line.
---
--- Extracts the selector before `{` (or the entire line if no brace),
--- then calculates specificity using a heuristic parser:
---
--- - **IDs** (`#foo`): pattern `#[%w%-_]+` → weight (1, 0, 0)
--- - **Classes** (`.bar`), attributes (`[attr]`), pseudo-classes (`:hover`):
---   → weight (0, 1, 0)
--- - **Elements** (`div`, `span`): remaining word tokens after
---   subtracting ID and class counts → weight (0, 0, 1)
---
--- Displays the result as `(IDs, Classes, Elements)` notation.
---
--- NOTE: This is a heuristic calculator. It does not handle:
--- - `:not()`, `:is()`, `:where()` pseudo-class specificity rules
--- - `::before`, `::after` pseudo-element specificity
--- - Combined selectors with commas
keys.lang_map(css_ft, "n", "<leader>li", function()
	local line = vim.api.nvim_get_current_line()
	---@type string|nil
	local selector = line:match("^(.-)%s*{") or line:match("^%s*(.-)%s*$")
	if not selector or selector == "" then
		vim.notify("No selector found on this line", vim.log.levels.INFO, { title = "CSS" })
		return
	end

	-- ── Basic specificity calculation ─────────────────────────────────
	---@type integer
	local ids = 0
	---@type integer
	local classes = 0
	---@type integer
	local elements = 0

	-- Count IDs: #identifier
	for _ in selector:gmatch("#[%w%-_]+") do
		ids = ids + 1
	end
	-- Count classes: .class
	for _ in selector:gmatch("%.[%w%-_]+") do
		classes = classes + 1
	end
	-- Count attribute selectors: [attr]
	for _ in selector:gmatch("%[.-%]") do
		classes = classes + 1
	end
	-- Count pseudo-classes: :hover, :nth-child, etc.
	for _ in selector:gmatch(":[%w%-]+") do
		classes = classes + 1
	end
	-- Count elements: rough heuristic (all word tokens minus IDs/classes)
	for _ in selector:gmatch("[%a][%w]*") do
		elements = elements + 1
	end
	elements = math.max(0, elements - ids - classes)

	vim.notify(
		string.format(
			"Selector: %s\nSpecificity: (%d, %d, %d)",
			selector:gsub("^%s+", ""):gsub("%s+$", ""),
			ids,
			classes,
			elements
		),
		vim.log.levels.INFO,
		{ title = "CSS Specificity" }
	)
end, { desc = icons.diagnostics.Info .. " Specificity info" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers CSS-specific alignment presets when mini.align is available.
-- Loaded once per session (guarded by is_language_loaded).
--
-- Preset: css_properties — align CSS property declarations on the ':'
-- character. Useful for visually aligning property-value pairs:
--
-- Example:
--   color       : red;
--   font-size   : 16px;
--   line-height : 1.5;
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("css") then
		---@type string Alignment preset icon from icons.lang
		local align_icon = icons.lang.css

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			css_properties = {
				description = "Align CSS / SCSS properties on ':'",
				icon = align_icon,
				split_pattern = ":",
				category = "web",
				lang = "css",
				filetypes = { "css", "scss" },
			},
		})

		-- ── Set default filetype mappings ─────────────────────────────
		align_registry.set_ft_mapping("css", "css_properties")
		align_registry.set_ft_mapping("scss", "css_properties")
		align_registry.mark_language_loaded("css")

		-- ── Alignment keymap ─────────────────────────────────────────
		keys.lang_map({ "css", "scss" }, { "n", "x" }, "<leader>aL", align_registry.make_align_fn("css_properties"), {
			desc = align_icon .. "  Align CSS props",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the CSS-specific
-- parts (servers, formatters, linters, parsers, color tools).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for CSS                    │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (cssls added to servers)          │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters for css/scss/less)    │
-- │ nvim-lint          │ opts merge (linters for css/scss/less)       │
-- │ nvim-treesitter    │ opts merge (css/scss to ensure_installed)    │
-- │ nvim-colorizer     │ ft = css/scss/less/html/js/ts (lazy load)   │
-- │ ccc.nvim           │ ft = css/scss/less/html + cmd (lazy load)   │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for CSS
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────
	-- cssls: CSS Language Server providing completions for properties,
	-- values, selectors, and at-rules. Supports CSS, SCSS, and Less.
	--
	-- Key settings:
	-- • validate: true — enable syntax and property validation
	-- • unknownAtRules: "ignore" — suppress warnings for framework
	--   at-rules (@tailwind, @apply, @screen, etc.)
	-- ────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				cssls = {
					settings = {
						css = {
							validate = true,
							lint = { unknownAtRules = "ignore" },
						},
						scss = {
							validate = true,
							lint = { unknownAtRules = "ignore" },
						},
						less = {
							validate = true,
							lint = { unknownAtRules = "ignore" },
						},
					},
				},
			},
		},
		init = function()
			-- ── Buffer-local options for CSS-family files ─────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "css", "scss", "less" },
				callback = function()
					local opt = vim.opt_local

					-- ── Layout ────────────────────────────────────────
					opt.wrap = false
					opt.colorcolumn = "80"

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
				desc = "NvimEnterprise: CSS/SCSS/Less buffer options",
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────
	-- Ensures CSS Language Server, Prettier, and Stylelint are
	-- installed and managed by Mason.
	-- ────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"css-lsp",
				"prettier",
				"stylelint",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────
	-- Prettier for CSS, SCSS, and Less files. Prettier auto-detects
	-- the CSS dialect and handles vendor prefixes, nesting (SCSS),
	-- and mixins appropriately.
	-- ────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				css = { "prettier" },
				scss = { "prettier" },
				less = { "prettier" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────
	-- Stylelint for CSS, SCSS, and Less files. Provides inline
	-- diagnostics for style violations, property ordering, selector
	-- specificity limits, and more.
	--
	-- Requires a `.stylelintrc` or `stylelint.config.js` configuration
	-- file in the project root.
	-- ────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				css = { "stylelint" },
				scss = { "stylelint" },
				less = { "stylelint" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────
	-- css:  syntax highlighting, folding, selector text objects
	-- scss: SCSS-specific syntax (nesting, variables, mixins, @use)
	-- ────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"css",
				"scss",
			},
		},
	},

	-- ── COLOR HIGHLIGHTER ──────────────────────────────────────────────
	-- nvim-colorizer.lua: inline color preview (background highlight).
	-- Supports CSS color functions (rgb, hsl, oklch), hex values,
	-- and named colors. Also activated for HTML, JS, and TS files
	-- that may contain inline styles.
	--
	-- NOTE: tailwind mode is disabled here — see langs/tailwind.lua
	-- for Tailwind-specific color highlighting.
	-- ────────────────────────────────────────────────────────────────────
	{
		"NvChad/nvim-colorizer.lua",
		ft = { "css", "scss", "less", "html", "javascript", "typescript" },
		opts = {
			filetypes = { "css", "scss", "less", "html", "javascript", "typescript" },
			user_default_options = {
				css = true,
				css_fn = true,
				tailwind = false,
				mode = "background",
				always_update = true,
			},
		},
	},

	-- ── COLOR PICKER ───────────────────────────────────────────────────
	-- ccc.nvim: inline color picker with HSL/RGB/Hex conversion.
	-- Lazy-loaded on CSS-family filetypes and specific commands.
	--
	-- Features:
	-- • :CccPick — open color picker at cursor position
	-- • :CccConvert — convert between color formats
	-- • :CccHighlighterToggle — toggle inline color highlighting
	-- • LSP integration for editor.colorProvider capability
	-- ────────────────────────────────────────────────────────────────────
	{
		"uga-rosa/ccc.nvim",
		ft = { "css", "scss", "less", "html" },
		cmd = { "CccPick", "CccConvert", "CccHighlighterToggle" },
		opts = {
			highlighter = {
				auto_enable = true,
				lsp = true,
			},
		},
	},
}
