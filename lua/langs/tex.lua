---@file lua/langs/tex.lua
---@description LaTeX — LSP, formatter, linter, treesitter, VimTeX & buffer-local keymaps
---@module "langs.tex"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.utils               Utility functions (`has_executable`)
---@see core.mini-align-registry Alignment preset registration system
---@see langs.python             Python language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/tex.lua — LaTeX language support                                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("tex") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "tex" / "latex" / "plaintex")│    ║
--- ║  │  ├─ LSP          texlab  (completions, diagnostics, build,       │    ║
--- ║  │  │               forward search, chktex integration)             │    ║
--- ║  │  ├─ Formatter    latexindent (via conform.nvim)                  │    ║
--- ║  │  ├─ Linter       chktex (via nvim-lint)                          │    ║
--- ║  │  ├─ Treesitter   latex · bibtex parsers                          │    ║
--- ║  │  └─ Extras       VimTeX (compilation, viewing, SyncTeX, TOC,     │    ║
--- ║  │                  environments, documentation)                    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ COMPILE   c  Compile document (VimtexCompile)                │    ║
--- ║  │  │            k  Stop compilation (VimtexStop)                   │    ║
--- ║  │  ├─ VIEW      v  View PDF (VimtexView)                           │    ║
--- ║  │  │            s  SyncTeX — cursor position → PDF                 │    ║
--- ║  │  ├─ NAV       t  Table of contents (VimtexTocOpen)               │    ║
--- ║  │  ├─ INFO      i  VimTeX status info                              │    ║
--- ║  │  │            e  Show compilation errors                         │    ║
--- ║  │  │            l  View compilation log                            │    ║
--- ║  │  ├─ EDIT      m  Modify surrounding environment                  │    ║
--- ║  │  │            d  Delete surrounding environment                  │    ║
--- ║  │  ├─ TOOLS     x  Reload VimTeX                                   │    ║
--- ║  │  └─ DOCS      h  Package documentation (VimtexDocPackage)        │    ║
--- ║  │                                                                  │    ║
--- ║  │  VimTeX integration:                                             │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  VimTeX provides the compilation engine and PDF viewer   │    │    ║
--- ║  │  │  integration. It runs alongside texlab LSP:              │    │    ║
--- ║  │  │  • texlab   → completions, diagnostics, code actions     │    │    ║
--- ║  │  │  • VimTeX   → compilation, viewing, SyncTeX, TOC         │    │    ║
--- ║  │  │                                                          │    │    ║
--- ║  │  │  VimTeX keymaps are DISABLED (vimtex_mappings_enabled=0) │    │    ║
--- ║  │  │  All keymaps go through core.keymaps (lang_map) for      │    │    ║
--- ║  │  │  consistency with the rest of the config.                │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  PDF viewer auto-detection:                                      │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. zathura executable → zathura (SyncTeX support)       │    │    ║
--- ║  │  │  2. fallback → VimTeX default (system PDF viewer)        │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Texlab build pipeline:                                          │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  executable: latexmk                                     │    │    ║
--- ║  │  │  args: -pdf -interaction=nonstopmode -synctex=1 %file    │    │    ║
--- ║  │  │  forwardSearchAfter: true (auto-open PDF after build)    │    │    ║
--- ║  │  │  onSave: true (auto-build on save)                       │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType tex / latex / plaintex):            ║
--- ║  • wrap=true, linebreak=true       (soft wrapping for prose)             ║
--- ║  • breakindent=true, shift:2       (indented wrapped lines)              ║
--- ║  • conceallevel=0                  (show all markup characters)          ║
--- ║  • textwidth=80, colorcolumn=80    (80-char line guide)                  ║
--- ║  • tabstop=2, shiftwidth=2         (2-space indentation)                 ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • spell=true, spelllang=en_us     (English spell checking)              ║
--- ║  • relativenumber=false            (absolute line numbers for prose)     ║
--- ║  • formatoptions=tcroqlj           (auto-formatting for comments)        ║
--- ║  • commentstring="%s"              (LaTeX uses % comments)               ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .tex, .cls, .sty, .latex, .ltex → tex                                 ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if LaTeX support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("tex") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")
local has_executable = require("core.utils").has_executable

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for TeX buffers.
-- The group is buffer-local and only visible when filetype == "tex".
-- Uses a LaTeX-specific icon (󰗚).
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("tex", "LaTeX", "󰗚")

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — COMPILE / VIEW
--
-- VimTeX compilation and PDF viewing. The compilation engine is
-- configured via VimTeX (latexmk by default). The PDF viewer is
-- auto-detected (zathura preferred for SyncTeX support).
-- ═══════════════════════════════════════════════════════════════════════════

--- Compile the current LaTeX document.
---
--- Triggers `VimtexCompile` which starts continuous compilation
--- via latexmk. The compilation runs in the background and
--- auto-updates the PDF on file changes.
keys.lang_map("tex", "n", "<leader>lc", "<cmd>VimtexCompile<cr>", {
	desc = "󱁤 Compile document",
})

--- Stop the current compilation process.
---
--- Sends SIGTERM to the latexmk process started by `VimtexCompile`.
keys.lang_map("tex", "n", "<leader>lk", "<cmd>VimtexStop<cr>", {
	desc = icons.ui.Close .. " Stop compilation",
})

--- View the compiled PDF document.
---
--- Opens the PDF in the configured viewer (zathura if available,
--- otherwise the system default). Uses SyncTeX for forward search
--- (cursor position → PDF location).
keys.lang_map("tex", "n", "<leader>lv", "<cmd>VimtexView<cr>", {
	desc = icons.ui.Play .. " View PDF",
})

--- Sync cursor position to PDF location (SyncTeX forward search).
---
--- Jumps to the PDF location corresponding to the current cursor
--- position in the source file. Requires SyncTeX support in both
--- the PDF viewer and the build pipeline.
keys.lang_map("tex", "n", "<leader>ls", "<cmd>VimtexView<cr>", {
	desc = "󰛓 SyncTeX",
})

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — NAVIGATION / INFO
--
-- Document navigation and build status information.
-- TOC provides a structured document outline.
-- Info shows the VimTeX compilation state and configuration.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the document table of contents.
---
--- Displays a navigable TOC sidebar parsed from `\section`,
--- `\subsection`, etc. commands in the document.
keys.lang_map("tex", "n", "<leader>lt", "<cmd>VimtexTocOpen<cr>", {
	desc = icons.ui.List .. " Table of contents",
})

--- Show VimTeX status and configuration info.
---
--- Displays compilation status, configured viewer, main file,
--- and other VimTeX internals.
keys.lang_map("tex", "n", "<leader>li", "<cmd>VimtexInfo<cr>", {
	desc = icons.diagnostics.Info .. " VimTeX Info",
})

--- Show compilation errors and warnings.
---
--- Opens the quickfix list populated with LaTeX compilation
--- errors, warnings, and overfull/underfull box messages.
keys.lang_map("tex", "n", "<leader>le", "<cmd>VimtexErrors<cr>", {
	desc = icons.diagnostics.Error .. " Show errors",
})

--- View the LaTeX compilation log.
---
--- Opens the full compilation log output from latexmk.
--- Useful for debugging complex build issues not shown
--- in the quickfix error list.
keys.lang_map("tex", "n", "<leader>ll", "<cmd>VimtexLog<cr>", {
	desc = icons.documents.File .. " View Log",
})

--- Reload the VimTeX plugin state.
---
--- Re-initializes VimTeX for the current buffer. Useful after
--- modifying VimTeX configuration or switching main files.
keys.lang_map("tex", "n", "<leader>lx", "<cmd>VimtexReload<cr>", {
	desc = icons.ui.Refresh .. " Reload VimTeX",
})

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — ENVIRONMENTS / DOCUMENTATION
--
-- LaTeX environment manipulation and package documentation.
-- Uses VimTeX's built-in environment change/delete operators
-- and the texdoc integration for package docs.
-- ═══════════════════════════════════════════════════════════════════════════

--- Change the surrounding LaTeX environment.
---
--- Prompts for a new environment name and replaces the
--- `\begin{...}` / `\end{...}` pair around the cursor.
--- Uses VimTeX's `<plug>(vimtex-env-change)` operator.
keys.lang_map("tex", "n", "<leader>lm", "<plug>(vimtex-env-change)", {
	desc = "󱗆 Modify Environment",
})

--- Delete the surrounding LaTeX environment.
---
--- Removes the `\begin{...}` / `\end{...}` pair around the
--- cursor, keeping the content inside. Uses VimTeX's
--- `<plug>(vimtex-env-delete)` operator.
keys.lang_map("tex", "n", "<leader>ld", "<plug>(vimtex-env-delete)", {
	desc = "󰆴 Delete Environment",
})

--- Open documentation for the LaTeX package under cursor.
---
--- Uses VimTeX's `VimtexDocPackage` which calls `texdoc` to
--- open the documentation for the package name under the cursor
--- or in the current `\usepackage{}` command.
keys.lang_map("tex", "n", "<leader>lh", "<cmd>VimtexDocPackage<cr>", {
	desc = icons.ui.Note .. " Package Documentation",
})

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers LaTeX-specific alignment presets for mini.align:
-- • tex_tabular — align tabular column separators on "&"
-- • tex_options — align key-value options on "="
--
-- Applied to both tex and latex filetypes.
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("tex") then
		---@type string Alignment preset icon from icons.lang
		local tex_align_icon = icons.lang.tex

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			tex_tabular = {
				description = "Align LaTeX tabular columns on '&'",
				icon = tex_align_icon,
				split_pattern = "&",
				category = "domain",
				lang = "tex",
				filetypes = { "tex", "latex" },
			},
			tex_options = {
				description = "Align LaTeX key-value options on '='",
				icon = tex_align_icon,
				split_pattern = "=",
				category = "domain",
				lang = "tex",
				filetypes = { "tex", "latex" },
			},
		})

		-- ── Set default filetype mappings ─────────────────────────────
		align_registry.set_ft_mapping("tex", "tex_tabular")
		align_registry.set_ft_mapping("latex", "tex_tabular")
		align_registry.mark_language_loaded("tex")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map({ "tex", "latex" }, { "n", "x" }, "<leader>aL", align_registry.make_align_fn("tex_tabular"), {
			desc = tex_align_icon .. "  Align TeX tabular",
		})
		keys.lang_map({ "tex", "latex" }, { "n", "x" }, "<leader>aT", align_registry.make_align_fn("tex_options"), {
			desc = tex_align_icon .. "  Align TeX options",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the LaTeX-specific
-- parts (servers, formatters, linters, parsers, VimTeX).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for LaTeX                  │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (texlab server + build settings) │
-- │ vimtex             │ ft = tex/latex/plaintex (true lazy load)    │
-- │ mason.nvim         │ opts merge (latexindent + texlab ensured)   │
-- │ conform.nvim       │ opts merge (latexindent for tex)            │
-- │ nvim-lint          │ opts merge (chktex for tex)                 │
-- │ nvim-treesitter    │ opts merge (latex + bibtex parsers)         │
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- Design notes:
-- • VimTeX and texlab serve complementary roles:
--   - texlab: LSP features (completions, diagnostics, code actions)
--   - VimTeX: compilation engine, PDF viewer, SyncTeX, TOC, environments
-- • VimTeX's built-in keymaps are DISABLED (vimtex_mappings_enabled = 0)
--   to maintain consistency with the lang_map() keymap system.
-- • The PDF viewer is auto-detected: zathura if available (best SyncTeX
--   support), otherwise VimTeX's default.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for LaTeX
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- texlab: LaTeX Language Server (completions, diagnostics, hover,
	-- go-to-definition, build integration, forward search).
	--
	-- Build settings:
	-- • executable: latexmk (standard LaTeX build tool)
	-- • args: -pdf (PDF output), -interaction=nonstopmode (no prompts),
	--   -synctex=1 (enable SyncTeX)
	-- • forwardSearchAfter: auto-jump to PDF after build
	-- • onSave: auto-build when the file is saved
	--
	-- Forward search (SyncTeX):
	-- • Configured for zathura with --synctex-forward
	-- • Change executable/args for other viewers (okular, Skim, etc.)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				texlab = {
					settings = {
						texlab = {
							build = {
								executable = "latexmk",
								args = {
									"-pdf",
									"-interaction=nonstopmode",
									"-synctex=1",
									"%file",
								},
								forwardSearchAfter = true,
								onSave = true,
							},
							forwardSearch = {
								executable = "zathura",
								args = {
									"--syncview",
									"--synctex-forward",
									"--forward-search-file",
									"%f",
									"%l",
									"%p",
								},
							},
							chktex = {
								openViewerAfter = false,
								lintOnOpen = true,
							},
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					tex = "tex",
					cls = "tex",
					sty = "tex",
					latex = "tex",
					ltex = "tex",
				},
			})

			-- ── Buffer-local options for LaTeX files ─────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "tex", "latex", "plaintex" },
				callback = function()
					local opt = vim.opt_local

					-- ── Display: soft wrapping for prose ─────────────
					opt.wrap = true
					opt.conceallevel = 0
					opt.linebreak = true
					opt.breakindent = true
					opt.breakindentopt = "shift:2"
					opt.textwidth = 80
					opt.colorcolumn = "80"

					-- ── Indentation ──────────────────────────────────
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true

					-- ── Format options ───────────────────────────────
					opt.formatoptions = "tcroqlj"
					opt.commentstring = "%s"

					-- ── Line numbers (absolute for prose) ────────────
					opt.number = true
					opt.relativenumber = false

					-- ── Spell checking ───────────────────────────────
					opt.spell = true
					opt.spelllang = "en_us"
				end,
			})
		end,
	},

	-- ── VIMTEX (compilation engine + PDF viewer) ───────────────────────────
	-- VimTeX provides the LaTeX compilation pipeline, PDF viewer
	-- integration, SyncTeX, TOC, environment manipulation, and
	-- package documentation via texdoc.
	--
	-- Configuration:
	-- • vimtex_view_method: zathura (auto-detected, SyncTeX support)
	-- • vimtex_quickfix_mode: 0 (don't auto-open quickfix)
	-- • vimtex_mappings_enabled: 0 (use lang_map() instead)
	-- • vimtex_indent_enabled: 1 (VimTeX indentation rules)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"lervag/vimtex",
		ft = { "tex", "latex", "plaintex" },
		init = function()
			-- ── PDF viewer auto-detection ────────────────────────────
			if has_executable("zathura") then
				vim.g.vimtex_view_method = "zathura"
			end

			vim.g.vimtex_quickfix_mode = 0
			vim.g.vimtex_mappings_enabled = 0
			vim.g.vimtex_indent_enabled = 1
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures latexindent and texlab are installed via Mason.
	-- NOTE: chktex is typically installed with the TeX distribution
	-- (texlive, miktex) and is NOT managed by Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"latexindent",
				"texlab",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- latexindent: Perl-based LaTeX code indenter and formatter.
	-- Uses --local flag to read project-specific settings from
	-- localSettings.yaml if present.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				tex = { "latexindent" },
			},
			formatters = {
				latexindent = {
					prepend_args = {
						"--local",
					},
				},
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- chktex: LaTeX semantic checker (style, common mistakes,
	-- spacing issues). Complements texlab's built-in chktex integration.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				tex = { "chktex" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- latex:  syntax highlighting, folding, indentation
	-- bibtex: BibTeX bibliography file support
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"latex",
				"bibtex",
			},
		},
	},
}
