---@file lua/plugins/code/cmp.lua
---@description Blink.cmp — enterprise-grade completion engine with per-filetype sources and AI integration
---@module "plugins.code.cmp"
---@version 1.0.0
---@since 2026-02
---@see plugins.code.lazydev LazyDev provides Neovim API completion for Lua files
---@see plugins.code.lsp LSP servers provide primary completion data
---@see plugins.ai.codecompanion CodeCompanion AI source (conditional)
---@see core.icons Icons for kind display and source indicators
---@see core.settings Settings for AI chain, UI borders, plugin toggling
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/code/cmp.lua — Completion engine (blink.cmp)                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  blink.cmp                                                       │    ║
--- ║  │  ├─ LSP completions       (score: 100)                           │    ║
--- ║  │  ├─ AI/CodeCompanion      (score: 95, conditional)               │    ║
--- ║  │  ├─ LazyDev               (score: 90, lua only)                  │    ║
--- ║  │  ├─ Snippets/LuaSnip      (score: 80)                            │    ║
--- ║  │  ├─ Path                  (score: 25)                            │    ║
--- ║  │  ├─ Git                   (score: 20, gitcommit only)            │    ║
--- ║  │  ├─ Emoji                 (score: -5)                            │    ║
--- ║  │  ├─ Buffer fallback       (score: -10)                           │    ║
--- ║  │  ├─ Ripgrep               (score: -15, prose only)               │    ║
--- ║  │  └─ Dictionary            (score: -20, prose only)               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Filetype group system:                                          │    ║
--- ║  │  ┌────────────┬────────────────────────────────────────────┐     │    ║
--- ║  │  │ Group      │ Languages                                  │     │    ║
--- ║  │  ├────────────┼────────────────────────────────────────────┤     │    ║
--- ║  │  │ systems    │ c, cpp, rust, zig                          │     │    ║
--- ║  │  │ jvm        │ java, kotlin, scala                        │     │    ║
--- ║  │  │ scripting  │ python, ruby, lua, elixir, erlang…         │     │    ║
--- ║  │  │ functional │ haskell, ocaml, elm, gleam, clojure        │     │    ║
--- ║  │  │ general    │ go, dart, julia, r, solidity               │     │    ║
--- ║  │  │ web_core   │ html, css, js, ts, jsx, tsx                │     │    ║
--- ║  │  │ web_fw     │ vue, svelte, angular, astro, ember         │     │    ║
--- ║  │  │ templating │ twig, htmldjango, eruby, gotmpl            │     │    ║
--- ║  │  │ config     │ json, yaml, toml, xml, ini, dotenv         │     │    ║
--- ║  │  │ iac        │ terraform, dockerfile, helm, ansible       │     │    ║
--- ║  │  │ shell      │ sh, bash, zsh, fish, nushell, ps1          │     │    ║
--- ║  │  │ prose      │ markdown, text, rst, tex, org, norg        │     │    ║
--- ║  │  │ git        │ gitcommit, gitrebase, NeogitCommit…        │     │    ║
--- ║  │  │ database   │ sql, mysql, pgsql, plsql                   │     │    ║
--- ║  │  │ disabled   │ help, oil, neo-tree, lazy, mason…          │     │    ║
--- ║  │  └────────────┴────────────────────────────────────────────┘     │    ║
--- ║  │                                                                  │    ║
--- ║  │  AI source chain:                                                │    ║
--- ║  │  settings.ai.enabled                                             │    ║
--- ║  │  └─ settings.ai.inline.enabled                                   │    ║
--- ║  │     └─ settings.ai.codecompanion.enabled                         │    ║
--- ║  │        └─ settings.ai.inline.source == "codecompanion"           │    ║
--- ║  │           └─ CodeCompanion source added + ghost_text on          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ opts.enabled (top-level) guards large files + special bufs   │    ║
--- ║  │  ├─ Per-filetype sources via FT_GROUPS → GROUP_SOURCES mapping   │    ║
--- ║  │  ├─ AI source conditionally nil (not loaded if disabled)         │    ║
--- ║  │  ├─ Table-driven highlights (single loop, not 80+ individual)    │    ║
--- ║  │  ├─ ColorScheme autocmd re-applies highlights dynamically        │    ║
--- ║  │  ├─ nvim-cmp explicitly disabled (no dual-engine conflicts)      │    ║
--- ║  │  └─ Buffer source caps at 1MB per buffer (performance)           │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • InsertEnter + CmdlineEnter loading (zero startup cost)                ║
--- ║  • Table-driven highlights (1 loop, not 80+ individual calls)            ║
--- ║  • Cached color extraction (each HL group resolved once)                 ║
--- ║  • ColorScheme autocmd re-applies highlights dynamically                 ║
--- ║  • AI source conditionally nil (not loaded, not registered)              ║
--- ║  • Buffer source caps at 1MB per buffer                                  ║
--- ║  • Completion disabled in large files (>1MB) via top-level enabled       ║
--- ║  • Completion disabled in special buffers (oil, help, lazy…)             ║
--- ║  • Per-filetype sources for ALL 55+ supported languages                  ║
--- ║  • nvim-cmp explicitly disabled (no dual-engine conflicts)               ║
--- ║  • Icons from core/icons.lua (single source of truth)                    ║
--- ║                                                                          ║
--- ║  Keymaps (insert/cmdline mode, handled by blink internally):             ║
--- ║    <C-space>   Show / toggle documentation                               ║
--- ║    <C-e>       Hide completion                                           ║
--- ║    <CR>        Accept completion                                         ║
--- ║    <S-CR>      Accept (replace mode)                                     ║
--- ║    <C-CR>      Cancel                                                    ║
--- ║    <Tab>       Accept if snippet active, else select next                ║
--- ║    <S-Tab>     Snippet backward / select prev                            ║
--- ║    <C-n/p>     Select next / prev                                        ║
--- ║    <C-b/f>     Scroll documentation                                      ║
--- ║    <C-k>       Toggle signature help                                     ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
if not settings:is_plugin_enabled("cmp") then return {} end

local icons = require("core.icons")
local api = vim.api

-- ═══════════════════════════════════════════════════════════════════════
-- PERFORMANCE THRESHOLDS
-- ═══════════════════════════════════════════════════════════════════════

--- Maximum file size before completion is disabled entirely.
---@type integer
---@private
local MAX_FILE_SIZE = 1024 * 1024 -- 1MB

--- Maximum buffer size for the buffer completion source.
--- Buffers larger than this are excluded from buffer-based completion.
---@type integer
---@private
local MAX_BUFFER_SIZE = 1024 * 1024 -- 1MB

-- ═══════════════════════════════════════════════════════════════════════
-- AI COMPLETION GUARD
--
-- Resolves the full AI settings chain to determine whether the
-- CodeCompanion completion source should be registered.
-- Chain: ai.enabled → ai.inline.enabled → ai.codecompanion.enabled
--        → ai.inline.source == "codecompanion"
-- ═══════════════════════════════════════════════════════════════════════

--- Resolve the AI settings chain to determine completion behavior.
---
--- Walks the full settings chain to determine:
--- 1. Whether AI features are active at all (`ai_active`)
--- 2. Whether the CodeCompanion blink source should be registered
---
---@return boolean ai_active `true` if any AI completion is enabled
---@return boolean use_cc_source `true` if the CodeCompanion source should be registered
---@private
local function resolve_ai_settings()
	local ai_master = settings:get("ai.enabled", false)
	if not ai_master then return false, false end

	local inline_enabled = settings:get("ai.inline.enabled", false)
	if not inline_enabled then return false, false end

	local cc_enabled = settings:get("ai.codecompanion.enabled", false)
	local avante_enabled = settings:get("ai.avante.enabled", false)
	if not cc_enabled and not avante_enabled then return false, false end

	local source = settings:get("ai.inline.source", "codecompanion")
	return true, (source == "codecompanion") and cc_enabled
end

local ai_active, use_codecompanion_source = resolve_ai_settings()

-- ═══════════════════════════════════════════════════════════════════════
-- FILETYPE GROUP SYSTEM
--
-- Single source of truth for which languages belong to which category.
-- Each group gets a tailored source list with appropriate priorities.
-- This ensures ALL 55+ supported languages have optimal completion.
--
-- Adding a new language:
--   1. Add the filetype to the appropriate group below
--   2. Done. Sources are auto-generated from the group.
-- ═══════════════════════════════════════════════════════════════════════

---@alias FtGroup
---| "programming"  # LSP-dominant, snippets secondary
---| "web"          # LSP + snippets balanced, emoji available
---| "config"       # LSP schema-aware, path important
---| "shell"        # LSP + buffer + path (system commands)
---| "prose"        # Dictionary, emoji, ripgrep enabled
---| "git"          # Conventional commits, emoji, git source
---| "database"     # LSP + buffer, no snippets noise
---| "disabled"     # No completion at all

---@type table<string, string[]>
---@private
local FT_GROUPS = {
	-- ── Systems programming ──────────────────────────────────────────
	-- LSP dominant. Snippets helpful for boilerplate. No emoji.
	systems = { "c", "cpp", "rust", "zig" },

	-- ── JVM languages ────────────────────────────────────────────────
	jvm = { "java", "kotlin", "scala" },

	-- ── Scripting languages ──────────────────────────────────────────
	scripting = {
		"python",
		"ruby",
		"lua",
		"elixir",
		"erlang",
		"perl",
	},

	-- ── Functional languages ─────────────────────────────────────────
	functional = {
		"haskell",
		"ocaml",
		"elm",
		"gleam",
		"clojure",
		"lean",
	},

	-- ── General-purpose ──────────────────────────────────────────────
	general = {
		"go",
		"dart",
		"julia",
		"r",
		"nim",
		"solidity",
		"thrift",
	},

	-- ── Web core ─────────────────────────────────────────────────────
	-- Snippets very valuable (html tags, css properties, JSX).
	-- Emoji available for JSX/TSX string literals.
	web_core = {
		"html",
		"css",
		"scss",
		"less",
		"sass",
		"javascript",
		"javascriptreact",
		"typescript",
		"typescriptreact",
		"javascript.jsx",
		"typescript.tsx",
	},

	-- ── Web frameworks ───────────────────────────────────────────────
	web_framework = {
		"vue",
		"svelte",
		"angular",
		"astro",
		"ember",
		"mdx",
	},

	-- ── Templating engines ───────────────────────────────────────────
	templating = {
		"twig",
		"htmldjango",
		"eruby",
		"gotmpl",
		"handlebars",
		"ejs",
		"jinja",
		"jinja2",
		"blade",
	},

	-- ── Configuration / data formats ─────────────────────────────────
	-- LSP provides schema-aware completion (jsonls, yamlls, taplo).
	-- Path completion very important (file references in config).
	config = {
		"json",
		"jsonc",
		"json5",
		"yaml",
		"yaml.ansible",
		"yaml.docker-compose",
		"toml",
		"xml",
		"ini",
		"conf",
		"dotenv",
		"editorconfig",
		"properties",
	},

	-- ── Infrastructure as Code ───────────────────────────────────────
	-- Similar to config but with snippets for resource blocks.
	iac = {
		"terraform",
		"hcl",
		"dockerfile",
		"helm",
		"ansible",
		"nix",
	},

	-- ── Shell / CLI ──────────────────────────────────────────────────
	-- Buffer source important (captures command names from context).
	-- Path completion critical (file paths everywhere).
	shell = {
		"sh",
		"bash",
		"zsh",
		"fish",
		"nushell",
		"powershell",
		"ps1",
		"csh",
		"tcsh",
	},

	-- ── Prose / documentation ────────────────────────────────────────
	-- Dictionary, emoji, ripgrep all enabled.
	-- Snippets for markdown syntax, LaTeX commands.
	prose = {
		"markdown",
		"markdown.mdx",
		"text",
		"rst",
		"asciidoc",
		"org",
		"norg",
		"tex",
		"latex",
		"plaintex",
		"quarto",
		"rmd",
		"typst",
	},

	-- ── Git ──────────────────────────────────────────────────────────
	-- Conventional commit keywords, co-author completion.
	-- Emoji for gitmoji workflow.
	git = {
		"gitcommit",
		"gitrebase",
		"git_rebase",
		"NeogitCommitMessage",
		"octo",
	},

	-- ── Database ─────────────────────────────────────────────────────
	-- LSP (sqlls, sqls) provides table/column completion.
	-- Buffer captures table names from context.
	database = {
		"sql",
		"mysql",
		"pgsql",
		"plsql",
		"sqlite",
	},

	-- ── Package manifests ────────────────────────────────────────────
	-- Special handling: crates.nvim, package.json aware.
	package_manifest = {
		"cargo.toml",
		"requirements",
	},

	-- ── Disabled ─────────────────────────────────────────────────────
	-- Buffers where completion must NEVER appear.
	disabled = {
		-- Plugin UIs
		"TelescopePrompt",
		"minifiles",
		"oil",
		"neo-tree",
		"neo-tree-popup",
		"NvimTree",
		"lazy",
		"mason",
		"lspinfo",
		"null-ls-info",
		"aerial",

		-- Snacks
		"snacks_dashboard",
		"snacks_notif",
		"snacks_terminal",
		"snacks_win",

		-- Help / docs
		"help",
		"man",
		"qf",
		"checkhealth",
		"tsplayground",

		-- Dashboard / start screens
		"alpha",
		"dashboard",
		"starter",
		"ministarter",

		-- DAP
		"dap-repl",
		"dapui_watches",
		"dapui_stacks",
		"dapui_breakpoints",
		"dapui_scopes",
		"dapui_console",

		-- Trouble / diagnostics
		"trouble",
		"Trouble",

		-- Diff / merge
		"DiffviewFiles",
		"DiffviewFileHistory",
		"NeogitStatus",
		"NeogitLogView",
		"NeogitPopup",
		"NeogitConsole",

		-- Terminal
		"terminal",
		"toggleterm",
		"FTerm",

		-- Misc
		"notify",
		"noice",
		"WhichKey",
		"Outline",
		"undotree",
		"spectre_panel",
	},
}

-- ═══════════════════════════════════════════════════════════════════════
-- SOURCE LISTS PER GROUP
--
-- Each group gets a curated list of sources. The order matters for
-- fallback behavior but NOT for scoring (that's score_offset's job).
-- AI source is injected at position 2 where applicable.
-- ═══════════════════════════════════════════════════════════════════════

---@type table<string, string[]>
---@private
local GROUP_SOURCES = {
	-- Programming: LSP is king, snippets for boilerplate, no fluff
	systems = { "lsp", "path", "snippets", "buffer" },
	jvm = { "lsp", "path", "snippets", "buffer" },
	scripting = { "lsp", "path", "snippets", "buffer" },
	functional = { "lsp", "path", "snippets", "buffer" },
	general = { "lsp", "path", "snippets", "buffer" },

	-- Web: snippets very valuable, emoji for JSX string literals
	web_core = { "lsp", "path", "snippets", "buffer", "emoji" },
	web_framework = { "lsp", "path", "snippets", "buffer", "emoji" },
	templating = { "lsp", "path", "snippets", "buffer" },

	-- Config: LSP schemas, path references, no snippets noise
	config = { "lsp", "path", "buffer" },

	-- IaC: snippets for resource blocks, path for file references
	iac = { "lsp", "path", "snippets", "buffer" },

	-- Shell: buffer captures commands, path is everywhere
	shell = { "lsp", "path", "buffer", "snippets" },

	-- Prose: full suite — dictionary, emoji, ripgrep
	prose = { "lsp", "path", "snippets", "buffer", "emoji", "dictionary", "ripgrep" },

	-- Git: emoji for gitmoji, git source for conventional commits
	git = { "buffer", "path", "emoji", "git" },

	-- Database: LSP for schemas, buffer for table names
	database = { "lsp", "buffer", "path", "snippets" },

	-- Package manifests: LSP + buffer + path
	package_manifest = { "lsp", "buffer", "path" },

	-- Disabled: nothing
	disabled = {},
}

--- Lua gets special treatment (lazydev source for Neovim API completion).
---@type string[]
---@private
local LUA_SOURCES = { "lsp", "path", "snippets", "buffer", "lazydev" }

-- ═══════════════════════════════════════════════════════════════════════
-- AI SOURCE INJECTION
--
-- When AI is active, inject the codecompanion source at position 2
-- in each applicable group (after LSP, before snippets).
-- Not injected in: disabled, git, config, database, package_manifest.
-- ═══════════════════════════════════════════════════════════════════════

--- Groups where AI source should NOT be injected.
---@type table<string, boolean>
---@private
local AI_EXCLUDED_GROUPS = {
	disabled = true,
	git = true,
	config = true,
	database = true,
	package_manifest = true,
}

if use_codecompanion_source then
	for group_name, sources in pairs(GROUP_SOURCES) do
		if not AI_EXCLUDED_GROUPS[group_name] and #sources > 0 then table.insert(sources, 2, "codecompanion") end
	end
	table.insert(LUA_SOURCES, 2, "codecompanion")
end

-- ═══════════════════════════════════════════════════════════════════════
-- PER-FILETYPE BUILDER
--
-- Generates the blink.cmp per_filetype table from the group system.
-- This ensures EVERY supported filetype has an explicit source list.
-- ═══════════════════════════════════════════════════════════════════════

--- Build the per-filetype source mapping from FT_GROUPS and GROUP_SOURCES.
---
--- Iterates all groups and assigns a deep-copied source list to each
--- filetype. Lua gets a special override with the lazydev source.
---
---@return table<string, string[]> per_filetype Map of filetype → source list
---@private
local function build_per_filetype()
	local ft = {}

	for group_name, filetypes in pairs(FT_GROUPS) do
		local sources = GROUP_SOURCES[group_name]
		if sources then
			for _, filetype in ipairs(filetypes) do
				ft[filetype] = vim.deepcopy(sources)
			end
		end
	end

	-- Override Lua with lazydev-aware sources
	ft.lua = vim.deepcopy(LUA_SOURCES)

	return ft
end

-- ═══════════════════════════════════════════════════════════════════════
-- DEFAULT SOURCES
--
-- For filetypes NOT in any group. Covers edge cases and
-- newly-added languages automatically.
-- ═══════════════════════════════════════════════════════════════════════

--- Build the default source list for unmapped filetypes.
---
---@return string[] sources Default source list with optional AI injection
---@private
local function build_default_sources()
	local sources = { "lsp", "path", "snippets", "buffer", "lazydev", "emoji" }
	if use_codecompanion_source then table.insert(sources, 2, "codecompanion") end
	return sources
end

-- ═══════════════════════════════════════════════════════════════════════
-- COMPLETION ENABLED GUARD
--
-- Top-level enabled function for blink.cmp. Disables completion
-- entirely in:
--   1. Large files (>1MB) — prevents slowdowns
--   2. Prompt/terminal buffers — not applicable
-- ═══════════════════════════════════════════════════════════════════════

local uv = vim.uv or vim.loop

--- Determine whether completion should be active for the current buffer.
---
--- Returns `false` for:
--- - Prompt and terminal buffers (`buftype == "prompt"` or `"terminal"`)
--- - Files larger than `MAX_FILE_SIZE` (1MB)
---
--- This function is called by blink.cmp on every completion trigger,
--- so it must be fast (two cheap checks, one optional stat call).
---
---@return boolean enabled `true` if completion should be active
---@private
local function is_completion_enabled()
	local bufnr = api.nvim_get_current_buf()

	-- Check buftype — disable in special buffers
	local buftype = vim.bo[bufnr].buftype
	if buftype == "prompt" or buftype == "terminal" then return false end

	-- Check file size — disable in large files
	local fname = api.nvim_buf_get_name(bufnr)
	if fname ~= "" then
		local stat = uv.fs_stat(fname)
		if stat and stat.size > MAX_FILE_SIZE then return false end
	end

	return true
end

-- ═══════════════════════════════════════════════════════════════════════
-- HIGHLIGHT MANAGEMENT
--
-- Table-driven highlight system with cached color extraction.
-- Each highlight group color is resolved once per colorscheme change
-- and cached in a local table. The ColorScheme autocmd re-applies
-- all highlights when the theme changes.
-- ═══════════════════════════════════════════════════════════════════════

--- Extract the foreground color of a highlight group (cached).
---
---@param name string Highlight group name
---@param cache table<string, string|false> Color cache (mutated)
---@return string|nil hex Hex color string (e.g. `"#7aa2f7"`), or `nil`
---@private
local function fg_of(name, cache)
	if cache[name] ~= nil then return cache[name] or nil end
	local ok, group = pcall(api.nvim_get_hl, 0, { name = name, link = false })
	if ok and group.fg then
		local hex = string.format("#%06x", group.fg)
		cache[name] = hex
		return hex
	end
	cache[name] = false
	return nil
end

--- Extract the background color of a highlight group (cached).
---
---@param name string Highlight group name
---@param cache table<string, string|false> Color cache (mutated)
---@return string|nil hex Hex color string, or `nil`
---@private
local function bg_of(name, cache)
	local key = name .. ":bg"
	if cache[key] ~= nil then return cache[key] or nil end
	local ok, group = pcall(api.nvim_get_hl, 0, { name = name, link = false })
	if ok and group.bg then
		local hex = string.format("#%06x", group.bg)
		cache[key] = hex
		return hex
	end
	cache[key] = false
	return nil
end

--- Apply all blink.cmp highlight groups.
---
--- Uses a table-driven approach: static highlights are defined in a
--- single table and applied in one loop, then kind-specific highlights
--- are generated from a kind→color mapping table.
---
--- Colors are extracted from the current colorscheme with fallbacks
--- to Tokyo Night defaults. A fresh cache is created on each call
--- (called once at setup + once per ColorScheme change).
---@private
local function apply_highlights()
	local hl = api.nvim_set_hl
	local c = {}

	-- ── Base palette ─────────────────────────────────────────────────
	local float_bg = bg_of("NormalFloat", c) or bg_of("Normal", c) or "#1a1b26"
	local float_fg = fg_of("NormalFloat", c) or fg_of("Normal", c) or "#c0caf5"
	local border_fg = fg_of("FloatBorder", c) or "#29a4bd"
	local comment_fg = fg_of("Comment", c) or "#565f89"
	local match_fg = fg_of("Special", c) or "#7dcfff"
	local deprecated_fg = fg_of("NonText", c) or "#3b4261"
	local cursor_bg = bg_of("CursorLine", c) or "#292e42"
	local selection_bg = bg_of("Visual", c) or "#364a82"

	-- ── Derived palette ──────────────────────────────────────────────
	local type_fg = fg_of("Type", c) or "#2ac3de"
	local func_fg = fg_of("Function", c) or "#7aa2f7"
	local var_fg = fg_of("@variable", c) or fg_of("Identifier", c) or "#c0caf5"
	local const_fg = fg_of("Constant", c) or "#ff9e64"
	local kw_fg = fg_of("Keyword", c) or "#bb9af7"
	local str_fg = fg_of("String", c) or "#9ece6a"
	local mod_fg = fg_of("Include", c) or fg_of("@module", c) or "#7dcfff"
	local snip_fg = fg_of("Special", c) or "#7dcfff"
	local dir_fg = fg_of("Directory", c) or "#7aa2f7"
	local ai_fg = str_fg
	local warn_fg = fg_of("DiagnosticWarn", c) or "#e0af68"

	-- ── Static highlights ────────────────────────────────────────────
	local static = {
		-- Menu
		BlinkCmpMenu = { fg = float_fg, bg = float_bg },
		BlinkCmpMenuBorder = { fg = border_fg, bg = float_bg },
		BlinkCmpMenuSelection = { bg = selection_bg, bold = true },
		BlinkCmpScrollBarThumb = { bg = deprecated_fg },
		BlinkCmpScrollBarGutter = { bg = float_bg },

		-- Labels
		BlinkCmpLabel = { fg = float_fg },
		BlinkCmpLabelMatch = { fg = match_fg, bold = true },
		BlinkCmpLabelDeprecated = { fg = deprecated_fg, strikethrough = true },
		BlinkCmpLabelDescription = { fg = comment_fg },
		BlinkCmpLabelDetail = { fg = comment_fg, italic = true },

		-- Documentation
		BlinkCmpDoc = { fg = float_fg, bg = float_bg },
		BlinkCmpDocBorder = { fg = border_fg, bg = float_bg },
		BlinkCmpDocSeparator = { fg = comment_fg, bg = float_bg },
		BlinkCmpDocCursorLine = { bg = cursor_bg },

		-- Signature help
		BlinkCmpSignatureHelp = { fg = float_fg, bg = float_bg },
		BlinkCmpSignatureHelpBorder = { fg = border_fg, bg = float_bg },
		BlinkCmpSignatureHelpActiveParameter = { fg = warn_fg, bold = true, underline = true },

		-- Ghost text
		BlinkCmpGhostText = { fg = deprecated_fg, italic = true },

		-- Source labels
		BlinkCmpSource = { fg = comment_fg, italic = true },
		BlinkCmpSourceLsp = { fg = func_fg, italic = true },
		BlinkCmpSourcePath = { fg = dir_fg, italic = true },
		BlinkCmpSourceSnippets = { fg = snip_fg, italic = true },
		BlinkCmpSourceBuffer = { fg = comment_fg, italic = true },
		BlinkCmpSourceEmoji = { fg = warn_fg, italic = true },
		BlinkCmpSourceDict = { fg = str_fg, italic = true },
		BlinkCmpSourceRipgrep = { fg = const_fg, italic = true },
		BlinkCmpSourceCmdline = { fg = fg_of("Statement", c) or "#9d7cd8", italic = true },
		BlinkCmpSourceLazydev = { fg = kw_fg, italic = true },
		BlinkCmpSourceGit = { fg = fg_of("diffAdded", c) or str_fg, italic = true },
		BlinkCmpSourceAI = { fg = ai_fg, italic = true },
		BlinkCmpSourceCodeCompanion = { fg = ai_fg, italic = true },
	}

	for name, def in pairs(static) do
		hl(0, name, def)
	end

	-- ── Kind highlights (table-driven) ───────────────────────────────
	local kinds = {
		Class = type_fg,
		Struct = type_fg,
		Interface = type_fg,
		Enum = type_fg,
		EnumMember = type_fg,
		TypeParameter = type_fg,
		Array = type_fg,
		Object = type_fg,

		Function = func_fg,
		Method = func_fg,
		Constructor = func_fg,
		StaticMethod = func_fg,

		Variable = var_fg,
		Field = var_fg,
		Property = var_fg,

		Constant = const_fg,
		Value = const_fg,
		Unit = const_fg,
		Number = const_fg,
		Boolean = const_fg,
		Null = const_fg,

		Keyword = kw_fg,
		Operator = kw_fg,
		Event = kw_fg,
		String = str_fg,
		Color = str_fg,

		Module = mod_fg,
		Namespace = mod_fg,
		Package = mod_fg,
		Snippet = snip_fg,

		Text = float_fg,
		Reference = fg_of("@markup.link", c) or "#7dcfff",
		Key = fg_of("@field", c) or var_fg,
		File = dir_fg,
		Folder = dir_fg,

		Copilot = ai_fg,
		Supermaven = ai_fg,
		TabNine = ai_fg,
		Codeium = ai_fg,
		CodeCompanion = ai_fg,
	}

	for kind, fg in pairs(kinds) do
		hl(0, "BlinkCmpKind" .. kind, { fg = fg })
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- SOURCE DISPLAY MAP
--
-- Maps source IDs to display metadata (label, icon, highlight group)
-- used by the completion menu's source_icon column.
-- ═══════════════════════════════════════════════════════════════════════

---@type table<string, { label: string, icon: string, hl: string }>
---@private
local source_display = {
	lsp = { label = "LSP", icon = icons.misc.Lsp, hl = "BlinkCmpSourceLsp" },
	path = { label = "Path", icon = icons.ui.Folder, hl = "BlinkCmpSourcePath" },
	snippets = { label = "Snip", icon = icons.kinds.Snippet, hl = "BlinkCmpSourceSnippets" },
	buffer = { label = "Buf", icon = icons.ui.File, hl = "BlinkCmpSourceBuffer" },
	cmdline = { label = "Cmd", icon = icons.ui.Terminal, hl = "BlinkCmpSourceCmdline" },
	emoji = { label = "Emoji", icon = "󰞅", hl = "BlinkCmpSourceEmoji" },
	dictionary = { label = "Dict", icon = "󰗚", hl = "BlinkCmpSourceDict" },
	ripgrep = { label = "Rg", icon = icons.ui.Search, hl = "BlinkCmpSourceRipgrep" },
	git = { label = "Git", icon = icons.git.Git, hl = "BlinkCmpSourceGit" },
	copilot = { label = "AI", icon = icons.kinds.Copilot, hl = "BlinkCmpSourceAI" },
	supermaven = { label = "AI", icon = icons.kinds.Supermaven, hl = "BlinkCmpSourceAI" },
	lazydev = { label = "Dev", icon = icons.misc.Neovim, hl = "BlinkCmpSourceLazydev" },
	codecompanion = { label = "AI", icon = icons.misc.AI or "󰧑", hl = "BlinkCmpSourceCodeCompanion" },
}

-- ═══════════════════════════════════════════════════════════════════════
-- AI EXCLUDED FILETYPES
--
-- Hash map of filetypes where the AI source should not activate,
-- even if the provider is registered. Built from FT_GROUPS.disabled.
-- ═══════════════════════════════════════════════════════════════════════

---@type table<string, boolean>
---@private
local ai_excluded_ft = {}
for _, ft in ipairs(FT_GROUPS.disabled) do
	ai_excluded_ft[ft] = true
end
ai_excluded_ft[""] = true

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════

local float_border = settings:get("ui.float_border", "rounded")

return {
	{
		"saghen/blink.cmp",
		version = "1.*",
		event = { "InsertEnter", "CmdlineEnter" },
		dependencies = {
			-- ── Snippet engine ─────────────────────────────────────
			-- Full spec in lua/plugins/code/luasnip.lua
			-- lazy.nvim merges specs automatically.
			"L3MON4D3/LuaSnip",

			-- ── Blink extensions ───────────────────────────────────
			{ "saghen/blink.compat", version = "*", lazy = true, opts = {} },
			{ "moyiz/blink-emoji.nvim", lazy = true },
			{ "Kaiser-Yang/blink-cmp-dictionary", lazy = true },
			{
				"mikavilpas/blink-ripgrep.nvim",
				lazy = true,
				cond = function()
					return vim.fn.executable("rg") == 1
				end,
			},

			-- ── Git completion (conventional commits, co-authors) ──
			{
				"Kaiser-Yang/blink-cmp-git",
				lazy = true,
				dependencies = { "nvim-lua/plenary.nvim" },
				cond = function()
					return vim.fn.executable("git") == 1
				end,
			},
		},

		---@module 'blink.cmp'
		---@type blink.cmp.Config
		opts = {
			-- ══════════════════════════════════════════════════════════
			-- TOP-LEVEL ENABLED GUARD
			--
			-- Controls whether blink.cmp is active for the current buffer.
			-- Must be at the top level of opts (NOT under completion).
			-- Disables completion in large files (>1MB) and special buffers.
			-- ══════════════════════════════════════════════════════════
			enabled = is_completion_enabled,

			-- ── Keymap ───────────────────────────────────────────────
			keymap = {
				preset = "none",
				["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
				["<C-e>"] = { "hide", "fallback" },
				["<CR>"] = { "accept", "fallback" },
				["<S-CR>"] = {
					function(cmp)
						return cmp.accept({ behavior = "replace" })
					end,
					"fallback",
				},
				["<C-CR>"] = { "cancel", "fallback" },
				["<Tab>"] = {
					function(cmp)
						if cmp.snippet_active() then
							return cmp.accept()
						else
							return cmp.select_next()
						end
					end,
					"snippet_forward",
					"fallback",
				},
				["<S-Tab>"] = { "snippet_backward", "select_prev", "fallback" },
				["<C-n>"] = { "select_next", "fallback" },
				["<C-p>"] = { "select_prev", "fallback" },
				["<C-b>"] = { "scroll_documentation_up", "fallback" },
				["<C-f>"] = { "scroll_documentation_down", "fallback" },
				["<C-k>"] = { "show_signature", "hide_signature", "fallback" },
			},

			-- ── Appearance ───────────────────────────────────────────
			appearance = {
				use_nvim_cmp_as_default = false,
				nerd_font_variant = "mono",
				kind_icons = vim.tbl_extend("force", icons.kinds, {
					CodeCompanion = icons.misc.AI or "󰧑",
				}),
			},

			-- ── Completion ───────────────────────────────────────────
			completion = {
				accept = {
					auto_brackets = { enabled = true },
				},

				list = {
					max_items = 50,
					selection = {
						preselect = true,
						auto_insert = true,
					},
				},

				menu = {
					enabled = true,
					min_width = 20,
					max_height = 15,
					border = float_border,
					winhighlight = table.concat({
						"Normal:BlinkCmpMenu",
						"FloatBorder:BlinkCmpMenuBorder",
						"CursorLine:BlinkCmpMenuSelection",
						"Search:None",
						"PmenuSbar:BlinkCmpScrollBarGutter",
						"PmenuThumb:BlinkCmpScrollBarThumb",
					}, ","),
					scrollbar = true,
					auto_show = true,

					draw = {
						align_to = "label",
						padding = 1,
						gap = 1,
						treesitter = { "lsp" },

						columns = {
							{ "kind_icon" },
							{ "label", "label_description", gap = 1 },
							{ "source_icon" },
						},

						components = {
							kind_icon = {
								ellipsis = false,
								text = function(ctx)
									local ai_kinds = {
										Copilot = icons.kinds.Copilot,
										Supermaven = icons.kinds.Supermaven,
										TabNine = icons.kinds.TabNine,
										Codeium = icons.kinds.Codeium,
										CodeCompanion = icons.misc.AI or "󰧑",
									}
									return (ai_kinds[ctx.kind] or icons.kinds[ctx.kind] or icons.ui.Dot) .. " "
								end,
								highlight = function(ctx)
									return "BlinkCmpKind" .. ctx.kind
								end,
							},

							label = {
								width = { fill = true, max = 50 },
								text = function(ctx)
									return ctx.label .. ctx.label_detail
								end,
								highlight = function(ctx)
									local base = ctx.deprecated and "BlinkCmpLabelDeprecated" or "BlinkCmpLabel"
									local highlights = { { 0, #ctx.label, group = base } }
									if ctx.label_matched_indices then
										for _, idx in ipairs(ctx.label_matched_indices) do
											highlights[#highlights + 1] = { idx, idx + 1, group = "BlinkCmpLabelMatch" }
										end
									end
									return highlights
								end,
							},

							source_icon = {
								width = { max = 4 },
								text = function(ctx)
									local info = source_display[ctx.source_id]
									return (info and info.icon or icons.ui.Dot) .. " "
								end,
								highlight = function(ctx)
									local info = source_display[ctx.source_id]
									return info and info.hl or "BlinkCmpSource"
								end,
							},
						},
					},
				},

				documentation = {
					auto_show = true,
					auto_show_delay_ms = 200,
					update_delay_ms = 50,
					treesitter_highlighting = true,
					window = {
						min_width = 15,
						max_width = 80,
						max_height = 20,
						border = float_border,
						winhighlight = table.concat({
							"Normal:BlinkCmpDoc",
							"FloatBorder:BlinkCmpDocBorder",
							"CursorLine:BlinkCmpDocCursorLine",
							"EndOfBuffer:BlinkCmpDoc",
						}, ","),
						scrollbar = true,
					},
				},

				ghost_text = {
					enabled = ai_active,
				},
			},

			-- ── Signature Help ────────────────────────────────────────
			signature = {
				enabled = true,
				window = {
					min_width = 1,
					max_width = 80,
					max_height = 15,
					border = float_border,
					winhighlight = table.concat({
						"Normal:BlinkCmpSignatureHelp",
						"FloatBorder:BlinkCmpSignatureHelpBorder",
					}, ","),
					scrollbar = false,
					treesitter_highlighting = true,
				},
			},

			-- ── Snippets (LuaSnip) ───────────────────────────────────
			snippets = {
				expand = function(snippet)
					require("luasnip").lsp_expand(snippet)
				end,
				active = function(filter)
					if filter and filter.direction then return require("luasnip").jumpable(filter.direction) end
					return require("luasnip").in_snippet()
				end,
				jump = function(direction)
					require("luasnip").jump(direction)
				end,
			},

			-- ── Sources ──────────────────────────────────────────────
			sources = {
				default = build_default_sources(),
				per_filetype = build_per_filetype(),

				providers = {
					-- ── LSP (score: 100) ─────────────────────────
					lsp = {
						name = "LSP",
						module = "blink.cmp.sources.lsp",
						score_offset = 100,
						fallbacks = { "buffer" },
					},

					-- ── Path (score: 25) ─────────────────────────
					path = {
						name = "Path",
						module = "blink.cmp.sources.path",
						score_offset = 25,
						opts = {
							trailing_slash = true,
							label_trailing_slash = true,
							get_cwd = function(context)
								return vim.fn.expand(("#%d:p:h"):format(context.bufnr))
							end,
							show_hidden_files_by_default = true,
						},
					},

					-- ── Snippets (score: 80) ─────────────────────
					snippets = {
						name = "Snippets",
						module = "blink.cmp.sources.snippets",
						score_offset = 80,
						min_keyword_length = 2,
						opts = {
							friendly_snippets = true,
							search_paths = { vim.fn.stdpath("config") .. "/snippets" },
							global_snippets = { "all" },
						},
					},

					-- ── Buffer (score: -10) ──────────────────────
					buffer = {
						name = "Buffer",
						module = "blink.cmp.sources.buffer",
						score_offset = -10,
						min_keyword_length = 3,
						opts = {
							get_bufnrs = function()
								local bufs = {}
								for _, win in ipairs(api.nvim_list_wins()) do
									local buf = api.nvim_win_get_buf(win)
									local byte_size = api.nvim_buf_get_offset(buf, api.nvim_buf_line_count(buf))
									if byte_size < MAX_BUFFER_SIZE then bufs[buf] = true end
								end
								return vim.tbl_keys(bufs)
							end,
						},
					},

					-- ── LazyDev (score: 90) ──────────────────────
					lazydev = {
						name = "LazyDev",
						module = "lazydev.integrations.blink",
						score_offset = 90,
					},

					-- ── Emoji (score: -5) ────────────────────────
					emoji = {
						name = "Emoji",
						module = "blink-emoji",
						score_offset = -5,
						opts = { insert = true },
					},

					-- ── Dictionary (score: -20) ──────────────────
					dictionary = {
						name = "Dict",
						module = "blink-cmp-dictionary",
						score_offset = -20,
						min_keyword_length = 3,
					},

					-- ── Ripgrep (score: -15) ─────────────────────
					ripgrep = {
						name = "Rg",
						module = "blink-ripgrep",
						score_offset = -15,
						min_keyword_length = 4,
						opts = {
							prefix_min_len = 4,
							context_size = 3,
							max_filesize = "1M",
							additional_rg_options = {
								"--smart-case",
								"--hidden",
								"--glob=!.git",
							},
						},
					},

					-- ── Git (score: 20) ──────────────────────────
					git = {
						name = "Git",
						module = "blink-cmp-git",
						score_offset = 20,
						opts = {
							commit = { enabled = true },
							git_centers = {
								github = {
									issue = { enabled = true },
									pull_request = { enabled = true },
									mention = { enabled = true },
								},
							},
						},
					},

					-- ── CodeCompanion / AI (score: 95) ───────────
					codecompanion = use_codecompanion_source and {
						name = "CodeCompanion",
						module = "codecompanion.providers.completion.blink",
						score_offset = 95,
						enabled = function()
							return not ai_excluded_ft[vim.bo.filetype]
						end,
					} or nil,
				},
			},

			-- ── Cmdline ──────────────────────────────────────────────
			cmdline = {
				sources = function()
					local type = vim.fn.getcmdtype()
					if type == "/" or type == "?" then return { "buffer" } end
					if type == ":" then return { "cmdline", "path" } end
					if type == "@" or type == "-" then return { "buffer", "path" } end
					return {}
				end,
			},

			-- ── Fuzzy ────────────────────────────────────────────────
			fuzzy = {
				use_proximity = true,
				frecency = { enabled = true },
				sorts = { "score", "sort_text" },
			},
		},

		opts_extend = { "sources.default" },

		---@param _ table Plugin spec (unused)
		---@param opts table Resolved blink.cmp options
		config = function(_, opts)
			require("blink.cmp").setup(opts)
			apply_highlights()

			api.nvim_create_autocmd("ColorScheme", {
				group = api.nvim_create_augroup("NvimEnterprise_BlinkHL", { clear = true }),
				desc = "Re-apply blink.cmp highlights after colorscheme change",
				callback = apply_highlights,
			})
		end,
	},

	-- ── Disable nvim-cmp (prevent dual-engine conflicts) ─────────────
	{ "hrsh7th/nvim-cmp", enabled = false },
	{ "hrsh7th/cmp-nvim-lsp", enabled = false },
	{ "hrsh7th/cmp-buffer", enabled = false },
	{ "hrsh7th/cmp-path", enabled = false },
	{ "hrsh7th/cmp-cmdline", enabled = false },
	{ "saadparwaiz1/cmp_luasnip", enabled = false },
}
