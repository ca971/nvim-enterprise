---@file lua/langs/html.lua
---@description HTML — LSP, formatter, linter, treesitter & buffer-local keymaps
---@module "langs.html"
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
---@see langs.ember              Ember language support (Handlebars templates)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/html.lua — HTML language support                                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("html") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "html"):                     │    ║
--- ║  │  ├─ LSP          html (vscode-html-languageservice)              │    ║
--- ║  │  │               emmet_language_server (abbreviation expansion)  │    ║
--- ║  │  ├─ Formatter    prettier (via conform.nvim)                     │    ║
--- ║  │  ├─ Linter       htmlhint (via nvim-lint)                        │    ║
--- ║  │  ├─ Treesitter   html parser                                     │    ║
--- ║  │  ├─ DAP          — (not applicable)                              │    ║
--- ║  │  └─ Extras       nvim-ts-autotag (auto-close/rename tags)        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ PREVIEW   p  Open in browser       s  Live server            │    ║
--- ║  │  ├─ TOOLS     e  Minify (html-minifier) v  W3C validator         │    ║
--- ║  │  │            x  Fix with prettier      t  Tag picker            │    ║
--- ║  │  └─ DOCS      h  MDN docs (contextual)  i  Element info (hover)  │    ║
--- ║  │               r  Entity reference (WHATWG spec)                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Live server resolution:                                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. live-server (npm) → hot-reload on port 5500          │    │    ║
--- ║  │  │  2. python3 -m http.server → static serving on 5500      │    │    ║
--- ║  │  │  3. Notification with install instructions               │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Emmet support scope:                                            │    ║
--- ║  │  html, css, scss, less, jsx, tsx, vue, svelte, astro, php, blade │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType html/htmldjango):                   ║
--- ║  • wrap=true                      (long lines are common in HTML)        ║
--- ║  • colorcolumn=120                (soft guideline)                       ║
--- ║  • tabstop=2, shiftwidth=2        (HTML convention: 2-space indent)      ║
--- ║  • expandtab=true                 (spaces, never tabs)                   ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .html → html (handled by Neovim built-in)                             ║
--- ║  • nvim-ts-autotag covers: html, xml, jsx, tsx, vue, svelte, astro, php  ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if HTML support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("html") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string HTML Nerd Font icon (trailing whitespace stripped)
local html_icon = icons.lang.html:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for HTML buffers.
-- The group is buffer-local and only visible when filetype == "html".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("html", "HTML", html_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — PREVIEW
--
-- Browser preview and live development server.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the current HTML file in the system browser.
---
--- Saves the buffer, then opens the file using the OS default browser
--- via `vim.ui.open()`.
keys.lang_map("html", "n", "<leader>lp", function()
	vim.cmd("silent! write")
	vim.ui.open(vim.fn.expand("%:p"))
end, { desc = icons.status.Remote .. " Preview in browser" })

--- Start a local development server for the current file.
---
--- Resolution strategy:
--- 1. `live-server` — npm package with hot-reload (port 5500)
--- 2. `python3 -m http.server` — static file serving (port 5500)
--- 3. Notification with install instructions if neither found
---
--- `live-server` is launched as a detached background job.
--- `python3` is launched in a terminal split.
keys.lang_map("html", "n", "<leader>ls", function()
	if vim.fn.executable("live-server") == 1 then
		vim.fn.jobstart({ "live-server", "--port=5500", "--open=" .. vim.fn.expand("%:t") }, {
			cwd = vim.fn.expand("%:p:h"),
			detach = true,
		})
		vim.notify("Live server: http://localhost:5500", vim.log.levels.INFO, { title = "HTML" })
	elseif vim.fn.executable("python3") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("python3 -m http.server 5500")
		vim.notify("Serving on http://localhost:5500", vim.log.levels.INFO, { title = "HTML" })
	else
		vim.notify("Install: npm i -g live-server", vim.log.levels.WARN, { title = "HTML" })
	end
end, { desc = icons.dev.Server .. " Live server" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS
--
-- HTML development utilities: minification, validation, formatting,
-- and tag insertion.
-- ═══════════════════════════════════════════════════════════════════════════

--- Minify the current HTML file with html-minifier.
---
--- Saves the buffer, then runs `html-minifier` with:
--- • `--collapse-whitespace` — remove unnecessary whitespace
--- • `--remove-comments`    — strip HTML comments
--- • `--minify-css`         — inline CSS minification
--- • `--minify-js`          — inline JS minification
---
--- Output is written to `<filename>.min.html` alongside the original.
--- Requires `html-minifier` to be installed: `npm i -g html-minifier`.
keys.lang_map("html", "n", "<leader>le", function()
	if vim.fn.executable("html-minifier") ~= 1 then
		vim.notify("Install: npm i -g html-minifier", vim.log.levels.WARN, { title = "HTML" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local output = vim.fn.expand("%:p:r") .. ".min.html"
	vim.fn.system(
		string.format(
			"html-minifier --collapse-whitespace --remove-comments --minify-css --minify-js -o %s %s",
			vim.fn.shellescape(output),
			vim.fn.shellescape(file)
		)
	)
	if vim.v.shell_error == 0 then
		vim.notify("Minified → " .. vim.fn.fnamemodify(output, ":t"), vim.log.levels.INFO, { title = "HTML" })
	else
		vim.notify("Minification failed", vim.log.levels.ERROR, { title = "HTML" })
	end
end, { desc = html_icon .. " Minify" })

--- Open the W3C HTML validator in the system browser.
---
--- Opens the upload-based validator page where you can submit
--- the current file for standards compliance checking.
keys.lang_map("html", "n", "<leader>lv", function()
	vim.cmd("silent! write")
	vim.ui.open("https://validator.w3.org/#validate_by_upload")
end, { desc = html_icon .. " Validate W3C" })

--- Format the current file with prettier.
---
--- Runs `prettier --write` synchronously, then reloads the buffer.
--- Requires `prettier` to be installed.
keys.lang_map("html", "n", "<leader>lx", function()
	if vim.fn.executable("prettier") ~= 1 then
		vim.notify("Install prettier", vim.log.levels.WARN, { title = "HTML" })
		return
	end
	vim.cmd("silent! write")
	vim.fn.system("prettier --write " .. vim.fn.shellescape(vim.fn.expand("%:p")))
	vim.cmd.edit()
	vim.notify("Formatted with prettier", vim.log.levels.INFO, { title = "HTML" })
end, { desc = html_icon .. " Fix with prettier" })

--- Insert an HTML tag from a picker of common elements.
---
--- Presents a picker with ~35 common HTML tags organized by category.
--- After selection:
--- • Void elements (`img`, `input`, etc.) → inserts self-closing `<tag />`
--- • Normal elements → inserts `<tag>`, cursor line, `</tag>`
---
--- Places the cursor inside the tag and enters insert mode for
--- non-void elements.
keys.lang_map("html", "n", "<leader>lt", function()
	---@type string[]
	local common_tags = {
		"div", "span", "p", "a", "img",
		"ul", "ol", "li",
		"h1", "h2", "h3", "h4", "h5", "h6",
		"table", "thead", "tbody", "tr", "th", "td",
		"form", "input", "button", "select", "textarea", "label",
		"header", "footer", "nav", "main", "section", "article", "aside",
		"video", "audio", "canvas", "svg",
	}

	vim.ui.select(common_tags, { prompt = html_icon .. " Insert tag:" }, function(tag)
		if not tag then return end
		local row = vim.api.nvim_win_get_cursor(0)[1]

		---@type table<string, boolean> HTML void elements (no closing tag)
		local void_tags = { img = true, input = true, br = true, hr = true, meta = true, link = true }

		---@type string[]
		local lines
		if void_tags[tag] then
			lines = { "<" .. tag .. " />" }
		else
			lines = { "<" .. tag .. ">", "  ", "</" .. tag .. ">" }
		end

		vim.api.nvim_buf_set_lines(0, row, row, false, lines)
		vim.api.nvim_win_set_cursor(0, { row + (#lines > 1 and 2 or 1), 2 })
		if #lines > 1 then vim.cmd("startinsert") end
	end)
end, { desc = icons.ui.List .. " Tag picker" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to MDN documentation, LSP hover, and the WHATWG
-- named character reference specification.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open MDN documentation for the element under cursor.
---
--- If the cursor is on a word, navigates directly to the MDN page
--- for that HTML element (`/Web/HTML/Element/<word>`). Otherwise
--- opens the HTML reference index.
keys.lang_map("html", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word ~= "" then
		vim.ui.open("https://developer.mozilla.org/en-US/docs/Web/HTML/Element/" .. word)
	else
		vim.ui.open("https://developer.mozilla.org/en-US/docs/Web/HTML")
	end
end, { desc = icons.ui.Note .. " MDN docs" })

--- Show LSP hover information for the element under cursor.
---
--- Delegates to `vim.lsp.buf.hover()` which displays the element's
--- documentation from the HTML language server.
keys.lang_map("html", "n", "<leader>li", function()
	vim.lsp.buf.hover()
end, { desc = icons.diagnostics.Info .. " Element info" })

--- Open the WHATWG named character reference table.
---
--- Opens the HTML specification page listing all named character
--- entities (e.g. `&amp;`, `&lt;`, `&nbsp;`, etc.).
keys.lang_map("html", "n", "<leader>lr", function()
	vim.ui.open("https://html.spec.whatwg.org/multipage/named-characters.html")
end, { desc = html_icon .. " Entity reference" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers HTML-specific alignment presets for mini.align:
-- • html_attributes — align HTML tag attributes on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("html") then
		---@type string Alignment preset icon from icons.lang
		local align_icon = icons.lang.html

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			html_attributes = {
				description = "Align HTML attributes on '='",
				icon = align_icon,
				split_pattern = "=",
				category = "web",
				lang = "html",
				filetypes = { "html" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("html", "html_attributes")
		align_registry.mark_language_loaded("html")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("html", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("html_attributes"), {
			desc = align_icon .. "  Align HTML attrs",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the HTML-specific
-- parts (servers, formatters, linters, parsers, tag plugins).
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for HTML                   │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig                         │ opts merge (html + emmet servers added)      │
-- │ mason.nvim                             │ opts merge (4 tools added to ensure_installed│
-- │ conform.nvim                           │ opts merge (prettier for ft html)            │
-- │ nvim-lint                              │ opts merge (htmlhint for ft html)            │
-- │ nvim-treesitter                        │ opts merge (html parser added)               │
-- │ nvim-ts-autotag                        │ ft = html/xml/jsx/tsx/vue/svelte/astro/php   │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for HTML
return {
	-- ── LSP SERVERS ────────────────────────────────────────────────────────
	-- html: vscode-html-languageservice providing completions, diagnostics,
	--       hover, and formatting (disabled — prettier via conform instead).
	--       Extended filetypes: htmldjango, templ.
	--
	-- emmet_language_server: Emmet abbreviation expansion for rapid HTML
	--       authoring. Covers a wide range of template filetypes.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				html = {
					filetypes = { "html", "htmldjango", "templ" },
					init_options = {
						provideFormatter = false,
					},
				},
				emmet_language_server = {
					filetypes = {
						"html",
						"css",
						"scss",
						"less",
						"javascriptreact",
						"typescriptreact",
						"vue",
						"svelte",
						"astro",
						"php",
						"blade",
						"erb",
					},
				},
			},
		},
		init = function()
			-- ── Buffer-local options for HTML files ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "html", "htmldjango" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = true
					opt.colorcolumn = "120"
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
	-- Ensures html-lsp, emmet-language-server, prettier, and htmlhint
	-- are installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"html-lsp",
				"emmet-language-server",
				"prettier",
				"htmlhint",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- prettier: opinionated HTML formatter. Used instead of the html LSP's
	-- built-in formatter (provideFormatter = false) for consistent
	-- formatting across the web stack (HTML, CSS, JS).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				html = { "prettier" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- htmlhint: configurable HTML linter checking for common issues
	-- (missing doctype, unclosed tags, inline styles, etc.).
	-- Configured via .htmlhintrc in the project root.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				html = { "htmlhint" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- html: syntax highlighting, folding, text objects and indentation
	--       for HTML documents.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"html",
			},
		},
	},

	-- ── AUTO TAG (auto-close and rename HTML tags) ─────────────────────────
	-- nvim-ts-autotag: automatically closes and renames paired HTML/XML
	-- tags using treesitter. Covers a wide range of template languages.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"windwp/nvim-ts-autotag",
		ft = { "html", "xml", "javascriptreact", "typescriptreact", "vue", "svelte", "astro", "php", "blade" },
		opts = {},
	},
}
