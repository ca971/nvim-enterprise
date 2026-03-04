---@file lua/langs/tailwind.lua
---@description Tailwind CSS — LSP, class sorting, color hints & buffer-local keymaps
---@module "langs.tailwind"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.svelte             Svelte language support (Tailwind consumer)
---@see langs.vue                Vue language support (Tailwind consumer)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/tailwind.lua — Tailwind CSS support (supplementary module)        ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("tailwind") → {} if off     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (active across 16 web filetypes):                     │    ║
--- ║  │  ├─ LSP          tailwindcss (class completions, hover, lint)    │    ║
--- ║  │  ├─ Sorter       rustywind (CLI class sorting)                   │    ║
--- ║  │  │               tailwind-sorter.nvim (on-save, opt-in)          │    ║
--- ║  │  ├─ Treesitter   html · css parsers (supplementary)              │    ║
--- ║  │  └─ Extras       tailwind-tools.nvim (color hints, concealing)   │    ║
--- ║  │                  ⚠ currently disabled (enabled = false)          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>lw sub-group):                    │    ║
--- ║  │  ├─ SORT      ws  Sort classes (rustywind --write)               │    ║
--- ║  │  ├─ HINTS     wc  Toggle color hints (Colorizer or inlay hints)  │    ║
--- ║  │  ├─ SEARCH    wf  Find class usage (Telescope grep / vimgrep)    │    ║
--- ║  │  └─ DOCS      wh  Tailwind docs (contextual word → URL)          │    ║
--- ║  │               wl  Class cheat sheet (nerdcave.com)               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Supported filetypes (16):                                       │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  html · css · scss                                       │    │    ║
--- ║  │  │  javascript · javascriptreact                            │    │    ║
--- ║  │  │  typescript · typescriptreact                            │    │    ║
--- ║  │  │  vue · svelte · astro                                    │    │    ║
--- ║  │  │  php · elixir · heex · templ                             │    │    ║
--- ║  │  │  htmldjango · erb                                        │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  LSP class detection (experimental classRegex):                  │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Standard: class, className, class:list, classList       │    │    ║
--- ║  │  │  Utility:  clsx(), cva(), cn(), tw`` (tagged templates)  │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Color hints toggle strategy:                                    │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. :ColorizerToggle exists → use nvim-colorizer         │    │    ║
--- ║  │  │  2. fallback               → toggle LSP inlay hints      │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Class search strategy:                                          │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Telescope available → grep_string (excludes          │    │    ║
--- ║  │  │     node_modules, dist, build)                           │    │    ║
--- ║  │  │  2. fallback → vimgrep across *.{html,jsx,tsx,vue,svelte}│    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Tailwind support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("tailwind") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Tailwind Nerd Font icon (trailing whitespace stripped)
local tw_icon = icons.lang.tailwind:gsub("%s+$", "")

---@type string[] Filetypes where Tailwind CSS is commonly used (16 total)
local tw_fts = {
	"html",
	"css",
	"scss",
	"javascript",
	"javascriptreact",
	"typescript",
	"typescriptreact",
	"vue",
	"svelte",
	"astro",
	"php",
	"elixir",
	"heex",
	"templ",
	"htmldjango",
	"erb",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY SUB-GROUP
--
-- Registers the <leader>lw sub-group placeholder for Tailwind keymaps.
-- This does NOT override the host filetype's <leader>l group — it adds
-- a nested sub-group alongside the primary lang keymaps.
--
-- Example: in a .svelte file, <leader>l shows Svelte keymaps AND
-- <leader>lw shows Tailwind keymaps.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map(tw_fts, "n", "<leader>lw", function() end, {
	desc = tw_icon .. " Tailwind",
})

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CLASS SORTING
--
-- Tailwind class sorting via rustywind (Rust-based CLI tool).
-- Sorts classes in-place according to the recommended Tailwind order
-- (layout → spacing → typography → decorative).
-- ═══════════════════════════════════════════════════════════════════════════

--- Sort Tailwind classes in the current file using rustywind.
---
--- Saves the buffer, runs `rustywind --write` in-place, then reloads
--- the buffer. Requires `rustywind` to be installed globally or via
--- Mason (notifies with install instructions if not found).
---
--- Sorting order follows Tailwind's recommended convention:
--- layout → flexbox → spacing → sizing → typography → decorative.
keys.lang_map(tw_fts, "n", "<leader>lws", function()
	if vim.fn.executable("rustywind") ~= 1 then
		vim.notify("Install: npm install -g rustywind", vim.log.levels.WARN, { title = "Tailwind" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.fn.system("rustywind --write " .. vim.fn.shellescape(file))
	vim.cmd.edit()
	vim.notify("Classes sorted", vim.log.levels.INFO, { title = "Tailwind" })
end, { desc = tw_icon .. " Sort classes" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — COLOR HINTS
--
-- Toggles visual color hints for Tailwind color classes.
-- Uses nvim-colorizer when available, falls back to LSP inlay hints.
-- ═══════════════════════════════════════════════════════════════════════════

--- Toggle Tailwind color hints in the current buffer.
---
--- Strategy:
--- 1. Check that `tailwindcss` LSP is attached to the buffer
--- 2. If `:ColorizerToggle` exists → toggle nvim-colorizer
--- 3. Fallback → toggle LSP inlay hints for the buffer
---
--- Notifies the user if the tailwindcss LSP is not attached.
keys.lang_map(tw_fts, "n", "<leader>lwc", function()
	local clients = vim.lsp.get_clients({ bufnr = 0, name = "tailwindcss" })
	if #clients == 0 then
		vim.notify("tailwindcss LSP not attached", vim.log.levels.INFO, { title = "Tailwind" })
		return
	end

	-- ── Strategy 1: nvim-colorizer ───────────────────────────────
	if vim.fn.exists(":ColorizerToggle") == 2 then
		vim.cmd("ColorizerToggle")
		return
	end

	-- ── Strategy 2: LSP inlay hints (fallback) ───────────────────
	---@type boolean
	local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
	vim.lsp.inlay_hint.enable(not enabled, { bufnr = 0 })
	vim.notify("Color hints: " .. (enabled and "OFF" or "ON"), vim.log.levels.INFO, { title = "Tailwind" })
end, { desc = icons.ui.Art .. " Toggle color hints" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SEARCH / NAVIGATION
--
-- Find usages of a Tailwind class across the project.
-- Uses Telescope when available for fuzzy-searchable results,
-- falls back to vimgrep with a quickfix list.
-- ═══════════════════════════════════════════════════════════════════════════

--- Find all usages of the Tailwind class under cursor.
---
--- Strategy:
--- 1. If Telescope is available → `grep_string` with exclusions
---    for `node_modules/`, `dist/`, and `build/` directories
--- 2. Fallback → `vimgrep` across `*.{html,jsx,tsx,vue,svelte}`
---    and opens the quickfix list
---
--- Skips silently if the cursor is not on a word.
keys.lang_map(tw_fts, "n", "<leader>lwf", function()
	---@type string
	local word = vim.fn.expand("<cword>")
	if word == "" then return end

	-- ── Strategy 1: Telescope grep ───────────────────────────────
	local ok, builtin = pcall(require, "telescope.builtin")
	if ok then
		builtin.grep_string({
			search = word,
			additional_args = {
				"--glob",
				"!node_modules",
				"--glob",
				"!dist",
				"--glob",
				"!build",
			},
			prompt_title = tw_icon .. " Class: " .. word,
		})
		return
	end

	-- ── Strategy 2: vimgrep fallback ─────────────────────────────
	vim.cmd("vimgrep /" .. vim.fn.escape(word, "/") .. "/gj **/*.{html,jsx,tsx,vue,svelte}")
	vim.cmd.copen()
end, { desc = icons.ui.Search .. " Find class usage" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Tailwind CSS documentation access via the system browser.
-- Contextual: if the cursor is on a class name, opens the
-- corresponding documentation page. Otherwise opens the docs index.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open Tailwind CSS documentation in the system browser.
---
--- If the cursor is on a word (Tailwind class name), attempts to
--- construct a documentation URL by:
--- 1. Replacing hyphens with `/` (e.g. `text-blue` → `text/blue`)
--- 2. Stripping variant prefixes (e.g. `hover:` → removed)
---
--- Falls back to the main docs index if the cursor is not on a word.
---
--- NOTE: The URL construction is a heuristic — not all class names
--- map cleanly to documentation pages. Complex utilities may land
--- on 404 pages.
keys.lang_map(tw_fts, "n", "<leader>lwh", function()
	---@type string
	local word = vim.fn.expand("<cword>")
	if word ~= "" then
		vim.ui.open("https://tailwindcss.com/docs/" .. word:gsub("%-", "/"):gsub("^%w+:", ""))
	else
		vim.ui.open("https://tailwindcss.com/docs")
	end
end, { desc = icons.ui.Note .. " Tailwind docs" })

--- Open the Tailwind CSS class cheat sheet.
---
--- Opens the nerdcave.com cheat sheet which provides a searchable,
--- categorized reference of all Tailwind utility classes with
--- visual previews.
keys.lang_map(tw_fts, "n", "<leader>lwl", function()
	vim.ui.open("https://nerdcave.com/tailwind-cheat-sheet")
end, { desc = icons.ui.List .. " Class cheat sheet" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Tailwind-specific alignment presets for mini.align:
-- • tailwind_classes — align multi-line class groups on whitespace
--
-- Applied to a subset of web filetypes where multi-line class
-- attributes are common (HTML, Vue, Svelte, Astro, JSX/TSX).
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("tailwind") then
		---@type string Alignment preset icon from icons.lang
		local tw_align_icon = icons.lang.tailwind

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			tailwind_classes = {
				description = "Align Tailwind multi-line class groups",
				icon = tw_align_icon,
				split_pattern = "%s+",
				category = "web",
				lang = "tailwind",
				filetypes = { "html", "vue", "svelte", "astro", "typescriptreact", "javascriptreact" },
			},
		})

		-- ── Mark loaded (no ft_mapping — Tailwind is supplementary) ──
		align_registry.mark_language_loaded("tailwind")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("tailwind", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("tailwind_classes"), {
			desc = tw_align_icon .. "  Align Tailwind classes",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Tailwind-specific
-- parts (servers, tools, parsers, Tailwind plugins).
--
-- Loading strategy:
-- ┌──────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin               │ How it lazy-loads for Tailwind               │
-- ├──────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig       │ opts merge (tailwindcss server + settings)  │
-- │ mason.nvim           │ opts merge (tailwindcss-ls + rustywind)     │
-- │ nvim-treesitter      │ opts merge (html + css parsers)             │
-- │ tailwind-tools.nvim  │ ft lazy load (⚠ currently disabled)        │
-- │ tailwind-sorter.nvim │ ft lazy load (on-save disabled by default) │
-- └──────────────────────┴──────────────────────────────────────────────┘
--
-- Design note:
-- • This module is supplementary — it adds Tailwind support ON TOP of
--   the host language's toolchain. The tailwindcss LSP runs alongside
--   the host LSP (e.g. svelte + tailwindcss, vue + tailwindcss).
-- • No formatter/linter specs — Tailwind formatting is handled by the
--   host language's prettier config (with prettier-plugin-tailwindcss).
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Tailwind CSS
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- tailwindcss: Tailwind CSS Language Server (class completions,
	-- hover previews, color hints, diagnostic linting).
	-- Runs alongside the host language's LSP (e.g. svelte, vue).
	--
	-- Settings:
	-- • classAttributes — HTML attributes to scan for class names
	-- • lint — severity levels for Tailwind-specific diagnostics
	-- • classRegex — experimental regex patterns for utility libraries
	--   (clsx, cva, cn, tw tagged templates)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				tailwindcss = {
					filetypes = tw_fts,
					settings = {
						tailwindCSS = {
							classAttributes = {
								"class",
								"className",
								"class:list",
								"classList",
								"ngClass",
							},
							lint = {
								cssConflict = "warning",
								invalidApply = "error",
								invalidConfigPath = "error",
								invalidScreen = "error",
								invalidTailwindDirective = "error",
								invalidVariant = "error",
								recommendedVariantOrder = "warning",
							},
							experimental = {
								classRegex = {
									-- clsx("...", "...")
									{ "clsx\\(([^)]*)\\)", "(?:'|\"|`)([^']*)(?:'|\"|`)" },
									-- cva("base", { variants: ... })
									{ "cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
									-- cn("...", "...")
									{ "cn\\(([^)]*)\\)", "(?:'|\"|`)([^']*)(?:'|\"|`)" },
									-- tw`...`
									{ "tw`([^`]*)" },
								},
							},
						},
					},
				},
			},
		},
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures tailwindcss-language-server and rustywind are installed.
	-- rustywind provides CLI class sorting (used by <leader>lws keymap).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"tailwindcss-language-server",
				"rustywind",
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- html + css: supplementary parsers for Tailwind class detection
	-- and syntax highlighting within templates. Most host languages
	-- already ensure these, but they're listed here for completeness.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"html",
				"css",
			},
		},
	},

	-- ── TAILWIND TOOLS (color hints, concealing) ───────────────────────────
	-- Provides inline color previews and optional class name concealing.
	-- ⚠ Currently DISABLED (enabled = false) — enable manually if desired.
	--
	-- Features when enabled:
	-- • document_color: inline color swatches next to color classes
	-- • conceal: replaces long class lists with "…" (toggle-able)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"luckasRanaworke/tailwind-tools.nvim",
		name = "tailwind-tools",
		enabled = false,
		build = ":UpdateRemotePlugins",
		lazy = true,
		ft = tw_fts,
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"neovim/nvim-lspconfig",
			"nvim-telescope/telescope.nvim",
		},
		opts = {
			server = {
				override = false,
			},
			document_color = {
				enabled = true,
				kind = "inline",
				inline_symbol = "󰝤 ",
			},
			conceal = {
				enabled = false,
				symbol = "…",
				highlight = {
					fg = "#38BDF8",
				},
			},
		},
	},

	-- ── TAILWIND SORTER (auto-sort on save) ────────────────────────────────
	-- Sorts Tailwind classes automatically on save using a treesitter-based
	-- approach. Disabled by default (`on_save_enabled = false`) — classes
	-- can be sorted manually via <leader>lws (rustywind) instead.
	--
	-- To enable auto-sort: set `on_save_enabled = true` in opts.
	-- Requires `npm ci && npm run build` in the formatter directory.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"laytan/tailwind-sorter.nvim",
		lazy = true,
		ft = tw_fts,
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
		},
		build = "cd formatter && npm ci && npm run build",
		opts = {
			on_save_enabled = false,
			on_save_pattern = {
				"*.html",
				"*.jsx",
				"*.tsx",
				"*.vue",
				"*.svelte",
				"*.astro",
			},
		},
	},
}
