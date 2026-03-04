---@file lua/config/extras_browser.lua
---@description ExtrasBrowser — interactive LazyVim extras browser, toggler and persistence manager (singleton)
---@module "config.extras_browser"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.class Base OOP system (ExtrasBrowser extends Class)
---@see core.utils File I/O, deep copy, table contains utilities
---@see core.platform Platform singleton (path resolution, config_dir, has_nerd_font)
---@see core.icons Centralized icon definitions (UI, git, misc)
---@see core.logger Structured logging (Logger:for_module)
---@see core.settings Settings singleton (extras enabled state, float_border)
---@see config.commands Registers :NvimExtras command that calls ExtrasBrowser:show()
---@see plugins.lazyvim_extras.extras_loader Consumes the extras list written by ExtrasBrowser
---
---@see https://github.com/LazyVim/LazyVim LazyVim extras specification format
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  config/extras_browser.lua — LazyVim extras browser (singleton)          ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  ExtrasBrowser (singleton, extends Class)                        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Data layer:                                                     │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  CATALOG (static)                                          │  │    ║
--- ║  │  │  Complete registry of all available LazyVim extras,        │  │    ║
--- ║  │  │  organized by category (Coding, DAP, Editor, Formatting,   │  │    ║
--- ║  │  │  Lang, Linting, Test, UI, Util). Each entry has:           │  │    ║
--- ║  │  │    { id = "lazyvim.plugins.extras.xxx", name, desc }       │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  PRIORITY (static)                                         │  │    ║
--- ║  │  │  Load-order priority map for extras. Lower number = loaded │  │    ║
--- ║  │  │  first. Ensures correct dependency order when writing      │  │    ║
--- ║  │  │  the extras list to settings.lua:                          │  │    ║
--- ║  │  │    10-30   UI framework (edgy, dashboards, animations)     │  │    ║
--- ║  │  │    50-60   Completion engines (blink, nvim-cmp, luasnip)   │  │    ║
--- ║  │  │    70-90   Coding infrastructure (copilot, surround…)      │  │    ║
--- ║  │  │    100     Core debug/test frameworks                      │  │    ║
--- ║  │  │    110     Editor search/picker infrastructure             │  │    ║
--- ║  │  │    200-230 Editor extras                                   │  │    ║
--- ║  │  │    500     Languages (default)                             │  │    ║
--- ║  │  │    800     Formatting / linting                            │  │    ║
--- ║  │  │    900     DAP language-specific                           │  │    ║
--- ║  │  │    950     Util (no dependencies)                          │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toggle pipeline:                                                │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  1. Read current extras from settings (handles both        │  │    ║
--- ║  │  │     formats: { extras = {...} } and flat array)            │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  2. Add or remove the target extra ID                      │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  3. Sort by priority (deterministic load order)            │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  4. Update in-memory _G.NvimConfig.settings                │  │    ║
--- ║  │  │     (normalized to canonical { enabled, extras } format)   │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  5. Write to disk via text-level surgery on settings.lua   │  │    ║
--- ║  │  │     Replaces the ENTIRE lazyvim_extras = { ... } block     │  │    ║
--- ║  │  │     using brace-depth tracking for correct nesting         │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  UI layer (floating window):                                     │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • Scratch buffer with category headers (── Title ──)      │  │    ║
--- ║  │  │  • Each extra: [ON]/[OFF] marker + name + description      │  │    ║
--- ║  │  │  • Dedicated highlight namespace (no deprecated -1 id)     │  │    ║
--- ║  │  │  • Semantic highlights: DiagnosticOk, Comment, Title…      │  │    ║
--- ║  │  │  • Toggle: <CR> or <Space> on any extra line               │  │    ║
--- ║  │  │  • Close: q or <Esc>                                       │  │    ║
--- ║  │  │  • Instant visual feedback + vim.notify confirmation       │  │    ║
--- ║  │  │  • Sort: enabled first, then category, then name           │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Persistence strategy:                                           │    ║
--- ║  │  ├─ _save_extras() reads settings.lua as raw text                │    ║
--- ║  │  ├─ _replace_lazyvim_extras_block() finds the block via          │    ║
--- ║  │  │  pattern match + brace-depth tracking (handles nesting)       │    ║
--- ║  │  ├─ Rebuilds the block with priority-sorted extras               │    ║
--- ║  │  ├─ Handles trailing commas after closing brace                  │    ║
--- ║  │  └─ Preserves all other file content (comments, formatting)      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ Singleton pattern: one browser instance for the lifetime     │    ║
--- ║  │  ├─ CATALOG is static class data (no disk reads for extras list) │    ║
--- ║  │  ├─ Priority sort ensures deterministic, dependency-safe order   │    ║
--- ║  │  ├─ Dual-format read (_enabled_map / _get_current_extras)        │    ║
--- ║  │  │  supports both legacy flat array and canonical format         │    ║
--- ║  │  ├─ Block replacement (not field-level surgery) avoids partial   │    ║
--- ║  │  │  update corruption when the extras list changes size          │    ║
--- ║  │  ├─ Named highlight namespace avoids deprecated ns_id = -1       │    ║
--- ║  │  └─ Nerd Font detection: falls back to [X] markers when absent   │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • CATALOG is a static class field — built once, never recomputed        ║
--- ║  • PRIORITY is a static lookup table — O(1) per extra                    ║
--- ║  • _enabled_map() builds a hash set for O(1) membership checks           ║
--- ║  • _sort_by_priority() uses vim.deepcopy to avoid mutating input         ║
--- ║  • Floating window uses scratch buffer (bufhidden=wipe, no file I/O)     ║
--- ║  • Highlights use a dedicated namespace for targeted clear/update        ║
--- ║  • Highlights applied in a single pass over the line array               ║
--- ║  • Toggle updates a single line in the buffer (no full redraw)           ║
--- ║  • Module cached by require() — singleton returned directly              ║
--- ║                                                                          ║
--- ║  Public API:                                                             ║
--- ║    extras_browser:show()                  Open the floating browser UI   ║
--- ║    extras_browser:toggle(extra_id)        Toggle an extra on/off         ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local Class = require("core.class")
local utils = require("core.utils")
local platform = require("core.platform")
local icons = require("core.icons")
local Logger = require("core.logger")

local log = Logger:for_module("config.extras_browser")

-- ═══════════════════════════════════════════════════════════════════════
-- HIGHLIGHT NAMESPACE
--
-- Dedicated namespace for all highlights in the extras browser
-- floating window. Using a named namespace instead of -1 avoids
-- the deprecated nvim_buf_clear_namespace(buf, -1, ...) signature
-- and enables targeted highlight management without affecting
-- other plugins or extmarks.
-- ═══════════════════════════════════════════════════════════════════════

---@type integer
local ns = vim.api.nvim_create_namespace("nvimenterprise_extras_browser")

-- ═══════════════════════════════════════════════════════════════════════
-- CLASS DEFINITION
-- ═══════════════════════════════════════════════════════════════════════

---@class ExtrasBrowser : Class
---@field _settings Settings Reference to the Settings singleton for reading/writing extras state
local ExtrasBrowser = Class:extend("ExtrasBrowser")

-- ═══════════════════════════════════════════════════════════════════════
-- PRIORITY MAP
--
-- Defines the load order for LazyVim extras. Lower number = loaded
-- first by lazy.nvim. This is critical because some extras depend
-- on others (e.g., dap.core before dap.nlua, completion engines
-- before coding extras).
--
-- Extras not listed here default to DEFAULT_PRIORITY (500),
-- which places them in the "languages" tier.
-- ═══════════════════════════════════════════════════════════════════════

---@type table<string, number>
ExtrasBrowser.PRIORITY = {
	-- ── UI framework (window layouts, must come first) ───────── 10-30
	["lazyvim.plugins.extras.ui.edgy"] = 10,
	["lazyvim.plugins.extras.ui.alpha"] = 20,
	["lazyvim.plugins.extras.ui.dashboard-nvim"] = 20,
	["lazyvim.plugins.extras.ui.mini-starter"] = 20,
	["lazyvim.plugins.extras.ui.mini-animate"] = 30,
	["lazyvim.plugins.extras.ui.mini-indentscope"] = 30,
	["lazyvim.plugins.extras.ui.indent-blankline"] = 30,
	["lazyvim.plugins.extras.ui.treesitter-context"] = 30,
	["lazyvim.plugins.extras.ui.treesitter-rewrite"] = 30,
	["lazyvim.plugins.extras.ui.smear-cursor"] = 35,
	["lazyvim.plugins.extras.ui.neo-scroll"] = 35,

	-- ── Completion engines (before coding extras) ────────────── 50-60
	["lazyvim.plugins.extras.coding.blink"] = 50,
	["lazyvim.plugins.extras.coding.nvim-cmp"] = 50,
	["lazyvim.plugins.extras.coding.luasnip"] = 60,

	-- ── Coding infrastructure ────────────────────────────────── 70-90
	["lazyvim.plugins.extras.coding.copilot"] = 70,
	["lazyvim.plugins.extras.coding.copilot-chat"] = 75,
	["lazyvim.plugins.extras.coding.tabnine"] = 70,
	["lazyvim.plugins.extras.coding.codeium"] = 70,
	["lazyvim.plugins.extras.coding.supermaven"] = 70,
	["lazyvim.plugins.extras.coding.mini-comment"] = 80,
	["lazyvim.plugins.extras.coding.mini-surround"] = 80,
	["lazyvim.plugins.extras.coding.neogen"] = 85,
	["lazyvim.plugins.extras.coding.yanky"] = 90,

	-- ── Core debug / test frameworks ─────────────────────────── 100
	["lazyvim.plugins.extras.dap.core"] = 100,
	["lazyvim.plugins.extras.test.core"] = 100,

	-- ── Editor search/picker infrastructure ──────────────────── 110
	["lazyvim.plugins.extras.editor.telescope"] = 110,
	["lazyvim.plugins.extras.editor.fzf"] = 110,

	-- ── Editor extras (some register into edgy panels) ───────── 200
	["lazyvim.plugins.extras.editor.aerial"] = 200,
	["lazyvim.plugins.extras.editor.outline"] = 200,
	["lazyvim.plugins.extras.editor.overseer"] = 200,
	["lazyvim.plugins.extras.editor.navic"] = 200,
	["lazyvim.plugins.extras.editor.harpoon2"] = 210,
	["lazyvim.plugins.extras.editor.illuminate"] = 210,
	["lazyvim.plugins.extras.editor.inc-rename"] = 210,
	["lazyvim.plugins.extras.editor.leap"] = 210,
	["lazyvim.plugins.extras.editor.flash"] = 210,
	["lazyvim.plugins.extras.editor.dial"] = 220,
	["lazyvim.plugins.extras.editor.mini-diff"] = 220,
	["lazyvim.plugins.extras.editor.mini-files"] = 220,
	["lazyvim.plugins.extras.editor.mini-move"] = 220,
	["lazyvim.plugins.extras.editor.neo-tree"] = 220,
	["lazyvim.plugins.extras.editor.refactoring"] = 230,

	-- ── Languages (default 500, listed for completeness) ─────── 500
	-- All lang extras use DEFAULT_PRIORITY = 500

	-- ── Formatting / linting (after lang) ────────────────────── 800
	["lazyvim.plugins.extras.formatting.prettier"] = 800,
	["lazyvim.plugins.extras.formatting.biome"] = 800,
	["lazyvim.plugins.extras.formatting.black"] = 800,
	["lazyvim.plugins.extras.linting.eslint"] = 800,

	-- ── DAP language-specific (after dap.core) ───────────────── 900
	["lazyvim.plugins.extras.dap.nlua"] = 900,

	-- ── Util (low priority, no dependencies) ─────────────────── 950
	["lazyvim.plugins.extras.util.chezmoi"] = 950,
	["lazyvim.plugins.extras.util.dot"] = 950,
	["lazyvim.plugins.extras.util.gitui"] = 950,
	["lazyvim.plugins.extras.util.mini-hipatterns"] = 950,
	["lazyvim.plugins.extras.util.octo"] = 950,
	["lazyvim.plugins.extras.util.project"] = 950,
	["lazyvim.plugins.extras.util.rest"] = 950,
	["lazyvim.plugins.extras.util.startuptime"] = 950,
}

--- Default priority for extras not explicitly listed in the PRIORITY table.
--- Places unlisted extras in the "languages" tier (after core infra, before formatting).
---@type number
ExtrasBrowser.DEFAULT_PRIORITY = 500

-- ═══════════════════════════════════════════════════════════════════════
-- CATALOG
--
-- Static registry of ALL available LazyVim extras, organized by
-- category. Each entry is a table with { id, name, desc }.
-- This is the single source of truth for what can be toggled.
-- ═══════════════════════════════════════════════════════════════════════

--stylua: ignore start
---@type table<string, table<integer, { id: string, name: string, desc: string }>>
ExtrasBrowser.CATALOG = {
  ["Coding"] = {
    { id = "lazyvim.plugins.extras.coding.blink",         name = "Blink",         desc = "Blink completion engine" },
    { id = "lazyvim.plugins.extras.coding.nvim-cmp",      name = "nvim-cmp",      desc = "Classic completion engine" },
    { id = "lazyvim.plugins.extras.coding.luasnip",       name = "LuaSnip",       desc = "Snippet engine" },
    { id = "lazyvim.plugins.extras.coding.mini-comment",  name = "Mini Comment",  desc = "Comment toggling" },
    { id = "lazyvim.plugins.extras.coding.mini-surround", name = "Mini Surround", desc = "Surround actions (add/delete/replace)" },
    { id = "lazyvim.plugins.extras.coding.neogen",        name = "Neogen",        desc = "Annotation / docstring generator" },
    { id = "lazyvim.plugins.extras.coding.yanky",         name = "Yanky",         desc = "Improved yank/paste with history" },
    { id = "lazyvim.plugins.extras.coding.copilot",       name = "Copilot",       desc = "GitHub Copilot AI completion" },
    { id = "lazyvim.plugins.extras.coding.copilot-chat",  name = "Copilot Chat",  desc = "GitHub Copilot Chat interface" },
    { id = "lazyvim.plugins.extras.coding.tabnine",       name = "TabNine",       desc = "TabNine AI completion" },
    { id = "lazyvim.plugins.extras.coding.codeium",       name = "Codeium",       desc = "Codeium AI completion" },
    { id = "lazyvim.plugins.extras.coding.supermaven",    name = "Supermaven",    desc = "Supermaven AI completion" },
  },
  ["DAP (Debug)"] = {
    { id = "lazyvim.plugins.extras.dap.core", name = "DAP Core", desc = "Debug adapter protocol core" },
    { id = "lazyvim.plugins.extras.dap.nlua", name = "DAP Lua",  desc = "Debug Neovim Lua plugins" },
  },
  ["Editor"] = {
    { id = "lazyvim.plugins.extras.editor.aerial",      name = "Aerial",      desc = "Code outline / symbol tree" },
    { id = "lazyvim.plugins.extras.editor.dial",        name = "Dial",        desc = "Increment/decrement values (dates, booleans…)" },
    { id = "lazyvim.plugins.extras.editor.flash",       name = "Flash",       desc = "Navigate with search labels" },
    { id = "lazyvim.plugins.extras.editor.fzf",         name = "FZF",         desc = "FZF-based fuzzy finder" },
    { id = "lazyvim.plugins.extras.editor.harpoon2",    name = "Harpoon 2",   desc = "Quick file mark navigation" },
    { id = "lazyvim.plugins.extras.editor.illuminate",  name = "Illuminate",  desc = "Highlight word under cursor" },
    { id = "lazyvim.plugins.extras.editor.inc-rename",  name = "Inc Rename",  desc = "Incremental LSP rename with preview" },
    { id = "lazyvim.plugins.extras.editor.leap",        name = "Leap",        desc = "Fast 2-character cursor motion" },
    { id = "lazyvim.plugins.extras.editor.mini-diff",   name = "Mini Diff",   desc = "Inline git diff indicators" },
    { id = "lazyvim.plugins.extras.editor.mini-files",  name = "Mini Files",  desc = "Minimal floating file browser" },
    { id = "lazyvim.plugins.extras.editor.mini-move",   name = "Mini Move",   desc = "Move lines/selections with Alt+hjkl" },
    { id = "lazyvim.plugins.extras.editor.navic",       name = "Navic",       desc = "LSP breadcrumb navigation in statusline" },
    { id = "lazyvim.plugins.extras.editor.neo-tree",    name = "Neo-tree",    desc = "File explorer sidebar" },
    { id = "lazyvim.plugins.extras.editor.outline",     name = "Outline",     desc = "Code outline sidebar (symbols)" },
    { id = "lazyvim.plugins.extras.editor.overseer",    name = "Overseer",    desc = "Task runner / job manager" },
    { id = "lazyvim.plugins.extras.editor.refactoring", name = "Refactoring", desc = "Extract/inline refactoring tools" },
    { id = "lazyvim.plugins.extras.editor.telescope",   name = "Telescope",   desc = "Telescope fuzzy finder extensions" },
  },
  ["Formatting"] = {
    { id = "lazyvim.plugins.extras.formatting.biome",    name = "Biome",    desc = "Biome formatter (JS/TS/JSON)" },
    { id = "lazyvim.plugins.extras.formatting.black",    name = "Black",    desc = "Python Black formatter" },
    { id = "lazyvim.plugins.extras.formatting.prettier", name = "Prettier", desc = "Prettier multi-language formatter" },
  },
  ["Lang"] = {
    { id = "lazyvim.plugins.extras.lang.angular",    name = "Angular",        desc = "Angular framework support" },
    { id = "lazyvim.plugins.extras.lang.ansible",    name = "Ansible",        desc = "Ansible playbook support" },
    { id = "lazyvim.plugins.extras.lang.astro",      name = "Astro",          desc = "Astro framework support" },
    { id = "lazyvim.plugins.extras.lang.clangd",     name = "Clangd (C/C++)", desc = "C/C++ via clangd LSP" },
    { id = "lazyvim.plugins.extras.lang.clojure",    name = "Clojure",        desc = "Clojure language support" },
    { id = "lazyvim.plugins.extras.lang.cmake",      name = "CMake",          desc = "CMake build system support" },
    { id = "lazyvim.plugins.extras.lang.dart",       name = "Dart",           desc = "Dart language support" },
    { id = "lazyvim.plugins.extras.lang.docker",     name = "Docker",         desc = "Dockerfile & Compose support" },
    { id = "lazyvim.plugins.extras.lang.elixir",     name = "Elixir",        desc = "Elixir language support" },
    { id = "lazyvim.plugins.extras.lang.elm",        name = "Elm",            desc = "Elm language support" },
    { id = "lazyvim.plugins.extras.lang.erlang",     name = "Erlang",         desc = "Erlang language support" },
    { id = "lazyvim.plugins.extras.lang.git",        name = "Git",            desc = "Git filetype support (commit, rebase…)" },
    { id = "lazyvim.plugins.extras.lang.gleam",      name = "Gleam",          desc = "Gleam language support" },
    { id = "lazyvim.plugins.extras.lang.go",         name = "Go",             desc = "Go language support" },
    { id = "lazyvim.plugins.extras.lang.graphql",    name = "GraphQL",        desc = "GraphQL schema & query support" },
    { id = "lazyvim.plugins.extras.lang.haskell",    name = "Haskell",        desc = "Haskell language support" },
    { id = "lazyvim.plugins.extras.lang.helm",       name = "Helm",           desc = "Kubernetes Helm chart support" },
    { id = "lazyvim.plugins.extras.lang.java",       name = "Java",           desc = "Java language support (jdtls)" },
    { id = "lazyvim.plugins.extras.lang.json",       name = "JSON",           desc = "JSON support with SchemaStore" },
    { id = "lazyvim.plugins.extras.lang.kotlin",     name = "Kotlin",         desc = "Kotlin language support" },
    { id = "lazyvim.plugins.extras.lang.markdown",   name = "Markdown",       desc = "Markdown editing & preview" },
    { id = "lazyvim.plugins.extras.lang.nix",        name = "Nix",            desc = "Nix language support" },
    { id = "lazyvim.plugins.extras.lang.nushell",    name = "Nushell",        desc = "Nushell scripting support" },
    { id = "lazyvim.plugins.extras.lang.ocaml",      name = "OCaml",          desc = "OCaml language support" },
    { id = "lazyvim.plugins.extras.lang.php",        name = "PHP",            desc = "PHP language support" },
    { id = "lazyvim.plugins.extras.lang.prisma",     name = "Prisma",         desc = "Prisma ORM schema support" },
    { id = "lazyvim.plugins.extras.lang.python",     name = "Python",         desc = "Python language support" },
    { id = "lazyvim.plugins.extras.lang.r",          name = "R",              desc = "R language support" },
    { id = "lazyvim.plugins.extras.lang.ruby",       name = "Ruby",           desc = "Ruby language support" },
    { id = "lazyvim.plugins.extras.lang.rust",       name = "Rust",           desc = "Rust language support (rust-analyzer)" },
    { id = "lazyvim.plugins.extras.lang.scala",      name = "Scala",          desc = "Scala language support (metals)" },
    { id = "lazyvim.plugins.extras.lang.sql",        name = "SQL",            desc = "SQL editing & completion" },
    { id = "lazyvim.plugins.extras.lang.svelte",     name = "Svelte",         desc = "Svelte framework support" },
    { id = "lazyvim.plugins.extras.lang.swift",      name = "Swift",          desc = "Swift language support" },
    { id = "lazyvim.plugins.extras.lang.tailwind",   name = "Tailwind",       desc = "Tailwind CSS color & class support" },
    { id = "lazyvim.plugins.extras.lang.terraform",  name = "Terraform",      desc = "Terraform / HCL support" },
    { id = "lazyvim.plugins.extras.lang.tex",        name = "LaTeX",          desc = "LaTeX / TeX editing support" },
    { id = "lazyvim.plugins.extras.lang.thrift",     name = "Thrift",         desc = "Apache Thrift support" },
    { id = "lazyvim.plugins.extras.lang.toml",       name = "TOML",           desc = "TOML support with taplo" },
    { id = "lazyvim.plugins.extras.lang.typescript", name = "TypeScript",     desc = "TypeScript / JavaScript support" },
    { id = "lazyvim.plugins.extras.lang.vue",        name = "Vue",            desc = "Vue framework support" },
    { id = "lazyvim.plugins.extras.lang.yaml",       name = "YAML",           desc = "YAML support with SchemaStore" },
    { id = "lazyvim.plugins.extras.lang.zig",        name = "Zig",            desc = "Zig language support" },
  },
  ["Linting"] = {
    { id = "lazyvim.plugins.extras.linting.eslint", name = "ESLint", desc = "ESLint integration for JS/TS" },
  },
  ["Test"] = {
    { id = "lazyvim.plugins.extras.test.core", name = "Neotest Core", desc = "Test runner framework (neotest)" },
  },
  ["UI"] = {
    { id = "lazyvim.plugins.extras.ui.alpha",              name = "Alpha",            desc = "Dashboard (alpha-nvim)" },
    { id = "lazyvim.plugins.extras.ui.dashboard-nvim",     name = "Dashboard",        desc = "Dashboard (dashboard-nvim)" },
    { id = "lazyvim.plugins.extras.ui.edgy",               name = "Edgy",             desc = "Predefined window layouts & panels" },
    { id = "lazyvim.plugins.extras.ui.indent-blankline",   name = "Indent Blankline", desc = "Indentation guide lines" },
    { id = "lazyvim.plugins.extras.ui.mini-animate",       name = "Mini Animate",     desc = "Smooth cursor & scroll animations" },
    { id = "lazyvim.plugins.extras.ui.mini-indentscope",   name = "Mini Indentscope", desc = "Animated indent scope line" },
    { id = "lazyvim.plugins.extras.ui.mini-starter",       name = "Mini Starter",     desc = "Minimal startup dashboard" },
    { id = "lazyvim.plugins.extras.ui.neo-scroll",         name = "Neo Scroll",       desc = "Smooth scrolling" },
    { id = "lazyvim.plugins.extras.ui.smear-cursor",       name = "Smear Cursor",     desc = "Cursor trail animation" },
    { id = "lazyvim.plugins.extras.ui.treesitter-context", name = "TS Context",       desc = "Sticky function/class headers" },
    { id = "lazyvim.plugins.extras.ui.treesitter-rewrite", name = "TS Rewrite",       desc = "Treesitter-based text objects rewrite" },
  },
  ["Util"] = {
    { id = "lazyvim.plugins.extras.util.chezmoi",         name = "Chezmoi",         desc = "Dotfile manager integration" },
    { id = "lazyvim.plugins.extras.util.dot",             name = "Dot",             desc = "Dotfile syntax highlighting" },
    { id = "lazyvim.plugins.extras.util.gitui",           name = "GitUI",           desc = "GitUI terminal integration" },
    { id = "lazyvim.plugins.extras.util.mini-hipatterns", name = "Mini Hipatterns", desc = "Highlight patterns (colors, TODO…)" },
    { id = "lazyvim.plugins.extras.util.octo",            name = "Octo",            desc = "GitHub issues & PR in Neovim" },
    { id = "lazyvim.plugins.extras.util.project",         name = "Project",         desc = "Project root detection & switching" },
    { id = "lazyvim.plugins.extras.util.rest",            name = "Rest",            desc = "HTTP client (rest.nvim)" },
    { id = "lazyvim.plugins.extras.util.startuptime",     name = "StartupTime",     desc = "Measure startup time" },
  },
}
--stylua: ignore end

-- ═══════════════════════════════════════════════════════════════════════
-- CONSTRUCTOR
-- ═══════════════════════════════════════════════════════════════════════

--- Initialize a new ExtrasBrowser instance.
---
--- Acquires a reference to the Settings singleton for reading the
--- current extras state and writing toggled changes.
function ExtrasBrowser:init()
	self._settings = require("core.settings")
end

-- ═══════════════════════════════════════════════════════════════════════
-- INTERNAL — PRIORITY & SORTING
--
-- Extras must be loaded in a specific order to satisfy implicit
-- dependencies (e.g., dap.core before dap.nlua, completion engines
-- before coding extras). The priority system enforces this by
-- sorting the extras list before writing to settings.lua.
-- ═══════════════════════════════════════════════════════════════════════

--- Get the load priority of an extra.
---
--- Looks up the extra ID in the PRIORITY table. Returns
--- DEFAULT_PRIORITY (500) for unlisted extras, placing them
--- in the "languages" tier.
---
---@param extra_id string Fully qualified extra ID (e.g. `"lazyvim.plugins.extras.coding.blink"`)
---@return number priority Load priority (lower = loaded first)
---@private
function ExtrasBrowser:_get_priority(extra_id)
	return self.PRIORITY[extra_id] or self.DEFAULT_PRIORITY
end

--- Sort an extras list by load priority.
---
--- Creates a sorted copy (does not mutate the input). Extras with
--- lower priority numbers come first. Within the same priority
--- tier, extras are sorted alphabetically for determinism.
---
---@param extras string[] List of extra IDs to sort
---@return string[] sorted New list sorted by priority then alphabetically
---@private
function ExtrasBrowser:_sort_by_priority(extras)
	local sorted = vim.deepcopy(extras)
	table.sort(sorted, function(a, b)
		local pa = self:_get_priority(a)
		local pb = self:_get_priority(b)
		if pa ~= pb then return pa < pb end
		return a < b
	end)
	return sorted
end

-- ═══════════════════════════════════════════════════════════════════════
-- INTERNAL — SETTINGS READ
--
-- The extras list in settings.lua can appear in two formats:
--
-- Format 1 (canonical):
--   lazyvim_extras = { enabled = true, extras = { "...", "..." } }
--
-- Format 2 (legacy / flat array):
--   lazyvim_extras = { enabled = true, "...", "..." }
--
-- Both _enabled_map() and _get_current_extras() handle both formats
-- transparently. On write, we always normalize to Format 1.
-- ═══════════════════════════════════════════════════════════════════════

--- Build a hash set of currently enabled extra IDs for O(1) lookup.
---
--- Reads from the Settings singleton and handles both the canonical
--- `{ extras = {...} }` format and the legacy flat array format.
---
---@return table<string, boolean> map Extra ID → `true` for each enabled extra
---@private
function ExtrasBrowser:_enabled_map()
	local lazyvim_extras = self._settings:get("lazyvim_extras", {})
	local map = {}

	-- Format 1: extras in a sub-table "extras"
	if lazyvim_extras.extras and type(lazyvim_extras.extras) == "table" then
		for _, id in ipairs(lazyvim_extras.extras) do
			map[id] = true
		end
	end

	-- Format 2: extras as direct array entries in lazyvim_extras
	for _, id in ipairs(lazyvim_extras) do
		if type(id) == "string" then map[id] = true end
	end

	return map
end

--- Get the current extras list as an ordered, deduplicated array.
---
--- Collects extras from both the canonical and legacy formats,
--- deduplicates via a `seen` set, and preserves insertion order.
---
---@return string[] current Ordered list of currently enabled extra IDs
---@private
function ExtrasBrowser:_get_current_extras()
	local lazyvim_extras = self._settings:get("lazyvim_extras", {})
	local current = {}
	local seen = {}

	-- Collect from sub-table "extras" if it exists
	if lazyvim_extras.extras and type(lazyvim_extras.extras) == "table" then
		for _, id in ipairs(lazyvim_extras.extras) do
			if type(id) == "string" and not seen[id] then
				table.insert(current, id)
				seen[id] = true
			end
		end
	end

	-- Collect from direct array entries
	for _, id in ipairs(lazyvim_extras) do
		if type(id) == "string" and not seen[id] then
			table.insert(current, id)
			seen[id] = true
		end
	end

	return current
end

--- Build the flat display list for the browser UI.
---
--- Iterates over all CATALOG categories and extras, enriches each
--- entry with its current enabled/disabled state, and sorts the
--- result: enabled extras first, then by category, then by name.
---
---@return table[] list Array of `{ id, name, desc, category, enabled }` entries
---@private
function ExtrasBrowser:_build_list()
	local enabled = self:_enabled_map()
	local list = {}

	for category, extras in pairs(self.CATALOG) do
		for _, extra in ipairs(extras) do
			table.insert(list, {
				id = extra.id,
				name = extra.name,
				desc = extra.desc,
				category = category,
				enabled = enabled[extra.id] == true,
			})
		end
	end

	-- Sort: enabled first, then alphabetically by category + name
	table.sort(list, function(a, b)
		if a.enabled ~= b.enabled then return a.enabled end
		if a.category ~= b.category then return a.category < b.category end
		return a.name < b.name
	end)

	return list
end

-- ═══════════════════════════════════════════════════════════════════════
-- TOGGLE
--
-- The toggle operation is the core mutation: it adds or removes an
-- extra from the enabled list, re-sorts by priority, updates
-- in-memory settings, and persists to disk.
-- ═══════════════════════════════════════════════════════════════════════

--- Toggle an extra on or off.
---
--- If the extra is currently enabled, removes it from the list.
--- If disabled, adds it. After mutation, the list is re-sorted
--- by priority, the in-memory settings are updated to canonical
--- format, and the change is persisted to disk.
---
--- ```lua
--- local extras_browser = require("config.extras_browser")
--- local now_enabled = extras_browser:toggle("lazyvim.plugins.extras.lang.python")
--- -- now_enabled == true  (was disabled, now enabled)
--- ```
---
---@param extra_id string Fully qualified extra ID to toggle
---@return boolean new_state `true` if the extra is now enabled, `false` if disabled
function ExtrasBrowser:toggle(extra_id)
	local current = self:_get_current_extras()
	local found = false

	for i, id in ipairs(current) do
		if id == extra_id then
			table.remove(current, i)
			found = true
			break
		end
	end

	if not found then table.insert(current, extra_id) end

	-- Sort by priority before saving
	current = self:_sort_by_priority(current)

	-- Update in memory (normalize to the canonical format)
	local merged = self._settings:all()
	merged.lazyvim_extras = {
		enabled = #current > 0,
		extras = current,
	}

	-- Write to disk
	self:_save_extras(current)

	return not found
end

-- ═══════════════════════════════════════════════════════════════════════
-- INTERNAL — PERSISTENCE
--
-- Writes the extras list to root settings.lua by replacing the
-- ENTIRE lazyvim_extras = { ... } block. Uses brace-depth tracking
-- to find the correct closing brace (handles nested tables).
--
-- Strategy:
-- 1. Read settings.lua as raw text
-- 2. Find lazyvim_extras = { via pattern match
-- 3. Track brace depth to find the matching closing }
-- 4. Replace the entire block with a freshly built one
-- 5. Preserve all surrounding content (comments, formatting)
-- ═══════════════════════════════════════════════════════════════════════

--- Save the extras list to the root `settings.lua` file on disk.
---
--- Rebuilds the entire `lazyvim_extras = { ... }` block with
--- priority-sorted extras and replaces it in the file via
--- `_replace_lazyvim_extras_block()`.
---
---@param extras string[] Priority-sorted list of extra IDs to write
---@private
function ExtrasBrowser:_save_extras(extras)
	local path = platform:path_join(platform.config_dir, "settings.lua")
	local content, err = utils.read_file(path)
	if not content then
		log:error("Cannot read settings.lua: %s", err or "unknown")
		return
	end

	-- Ensure extras are sorted by priority
	extras = self:_sort_by_priority(extras)

	-- Build the new lazyvim_extras block
	local new_block
	if #extras > 0 then
		local extras_lines = {}
		for _, id in ipairs(extras) do
			table.insert(extras_lines, string.format('\t\t\t"%s",', id))
		end
		new_block = string.format(
			"lazyvim_extras = {\n\t\tenabled = true,\n\t\textras = {\n%s\n\t\t},\n\t}",
			table.concat(extras_lines, "\n")
		)
	else
		new_block = "lazyvim_extras = {\n\t\tenabled = true,\n\t}"
	end

	-- Replace the entire lazyvim_extras = { ... } block
	local new_content = self:_replace_lazyvim_extras_block(content, new_block)

	if not new_content then
		log:error("Could not find lazyvim_extras block in settings.lua")
		vim.notify("Could not find lazyvim_extras block in settings.lua", vim.log.levels.ERROR, { title = "NvimExtras" })
		return
	end

	local ok, write_err = utils.write_file(path, new_content)
	if not ok then
		log:error("Cannot write settings.lua: %s", write_err or "unknown")
	else
		log:info("Updated lazyvim_extras in settings.lua (%d extras, priority-sorted)", #extras)
	end
end

--- Replace the `lazyvim_extras = { ... }` block in file content.
---
--- Finds the block start via pattern match, then uses brace-depth
--- tracking to locate the matching closing brace (correctly handles
--- nested `{ ... }` tables within the block). Also consumes a
--- trailing comma after the closing brace if present.
---
---@param content string The full settings.lua file content
---@param new_block string The replacement block (without trailing comma)
---@return string|nil new_content The modified content, or `nil` if the block was not found
---@private
function ExtrasBrowser:_replace_lazyvim_extras_block(content, new_block)
	local start_pos = content:find("lazyvim_extras%s*=%s*%{")
	if not start_pos then return nil end

	local brace_start = content:find("%{", start_pos)
	if not brace_start then return nil end

	local depth = 0
	local end_pos = nil

	for i = brace_start, #content do
		local ch = content:sub(i, i)
		if ch == "{" then
			depth = depth + 1
		elseif ch == "}" then
			depth = depth - 1
			if depth == 0 then
				end_pos = i
				break
			end
		end
	end

	if not end_pos then return nil end

	-- Check if there's a trailing comma after the closing brace
	local after_brace = content:sub(end_pos + 1, end_pos + 1)
	if after_brace == "," then end_pos = end_pos + 1 end

	local replacement = new_block .. ","
	local before = content:sub(1, start_pos - 1)
	local after = content:sub(end_pos + 1)

	return before .. replacement .. after
end

-- ═══════════════════════════════════════════════════════════════════════
-- UI — FLOATING WINDOW BROWSER
--
-- Opens a centered floating window with all available extras,
-- grouped by category. The user can toggle extras with <CR> or
-- <Space> and close with q or <Esc>. Changes are persisted
-- immediately and take effect after a Neovim restart.
--
-- All highlights use the dedicated `ns` namespace created at
-- module level. This avoids the deprecated nvim_buf_add_highlight
-- / nvim_buf_clear_namespace calls with ns_id = -1, and isolates
-- our highlights from other plugins.
-- ═══════════════════════════════════════════════════════════════════════

--- Show the extras browser in a centered floating window.
---
--- Builds a scratch buffer with:
--- - Title header with Lazy icon
--- - Help line (toggle/close keymaps)
--- - Category headers (── Category ──────)
--- - Extra lines: [ON]/[OFF] marker + name + description
--- - Footer with restart reminder and sort info
---
--- Keymaps (buffer-local):
--- - `<CR>` / `<Space>` — Toggle the extra under the cursor
--- - `q` / `<Esc>` — Close the browser window
---
--- Visual feedback:
--- - `DiagnosticOk` highlight for enabled extras
--- - `Comment` highlight for disabled extras
--- - `Title` for category headers
--- - `Special` for the title
--- - `DiagnosticInfo` for the help line
--- - `DiagnosticWarn` for the footer
--- - `vim.notify` confirmation on each toggle
function ExtrasBrowser:show()
	local list = self:_build_list()
	local buf = vim.api.nvim_create_buf(false, true)

	-- ── Build display lines ──────────────────────────────────────
	local lines = {
		" " .. icons.misc.Lazy .. " LazyVim Extras Browser",
		"",
		" Toggle: <CR> or <Space>  │  Close: q / <Esc>  │  Restart needed after changes",
		"",
	}

	local current_category = ""
	---@type table<integer, table>
	local line_to_extra = {}

	for _, extra in ipairs(list) do
		if extra.category ~= current_category then
			current_category = extra.category
			table.insert(lines, " ── " .. current_category .. " " .. string.rep("─", 50 - #current_category))
			table.insert(lines, "")
		end

		local marker = (extra.enabled and (platform.has_nerd_font and icons.ui.Check or "[X]")) or "   "
		local status = extra.enabled and " [ON] " or " [OFF]"
		local line = string.format(" %s%s %-22s %s", marker, status, extra.name, extra.desc)
		table.insert(lines, line)
		line_to_extra[#lines] = extra
	end

	table.insert(lines, "")
	table.insert(lines, " " .. icons.ui.Fire .. " Restart Neovim after changes to apply extras")
	table.insert(lines, " " .. icons.ui.Gear .. " Extras are auto-sorted by load priority")

	-- ── Buffer setup ─────────────────────────────────────────────
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "nvimextras"

	-- ── Window geometry ──────────────────────────────────────────
	local width = 80
	local height = math.min(#lines, math.floor(vim.o.lines * 0.8))
	local ui_info = vim.api.nvim_list_uis()[1]
	local row = math.floor((ui_info.height - height) / 2)
	local col = math.floor((ui_info.width - width) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = self._settings:get("ui.float_border", "rounded"),
		title = " " .. icons.misc.Lazy .. " Extras ",
		title_pos = "center",
	})

	vim.wo[win].cursorline = true
	vim.wo[win].winblend = 0

	-- ── Highlights (using dedicated namespace + extmarks) ────────
	for i, line in ipairs(lines) do
		local hl_group
		if line:match("^%s*──") then
			hl_group = "Title"
		elseif line:match("LazyVim Extras") then
			hl_group = "Special"
		elseif line:match("%[ON%]") then
			hl_group = "DiagnosticOk"
		elseif line:match("%[OFF%]") then
			hl_group = "Comment"
		elseif line:match("Toggle:") then
			hl_group = "DiagnosticInfo"
		elseif line:match("Restart") or line:match("auto%-sorted") then
			hl_group = "DiagnosticWarn"
		end

		if hl_group then
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
				end_row = i - 1,
				end_col = #line,
				hl_group = hl_group,
			})
		end
	end

	-- ── Keymaps (buffer-local) ───────────────────────────────────
	local self_ref = self
	local close = function()
		if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
	end

	local toggle = function()
		local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
		local extra = line_to_extra[cursor_line]
		if not extra then return end

		local new_state = self_ref:toggle(extra.id)
		extra.enabled = new_state

		-- Update the single toggled line (no full redraw)
		local marker = new_state and icons.ui.Check or "  "
		local status = new_state and " [ON] " or " [OFF]"
		local new_line = string.format(" %s%s %-22s %s", marker, status, extra.name, extra.desc)

		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, cursor_line - 1, cursor_line, false, { new_line })
		vim.bo[buf].modifiable = false

		-- Update highlight for the toggled line (clear + re-apply via extmarks)
		vim.api.nvim_buf_clear_namespace(buf, ns, cursor_line - 1, cursor_line)
		vim.api.nvim_buf_set_extmark(buf, ns, cursor_line - 1, 0, {
			end_row = cursor_line - 1,
			end_col = #new_line,
			hl_group = new_state and "DiagnosticOk" or "Comment",
		})

		vim.notify(
			string.format(
				"%s %s: %s\n\nRestart Neovim to apply.",
				new_state and icons.ui.Check or icons.ui.BoldClose,
				extra.name,
				new_state and "enabled" or "disabled"
			),
			vim.log.levels.INFO,
			{ title = "LazyVim Extras" }
		)
	end

	vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })
	vim.keymap.set("n", "<CR>", toggle, { buffer = buf, silent = true })
	vim.keymap.set("n", "<Space>", toggle, { buffer = buf, silent = true })
end

-- ═══════════════════════════════════════════════════════════════════════
-- SINGLETON
--
-- ExtrasBrowser is instantiated once and returned directly by require().
-- The Settings reference is acquired in :init() on first construction.
-- ═══════════════════════════════════════════════════════════════════════

---@type ExtrasBrowser|nil
---@private
local _instance = nil

--- Get or create the ExtrasBrowser singleton instance.
---
--- On first call, creates a new `ExtrasBrowser` instance which
--- acquires a reference to the Settings singleton in `:init()`.
--- On subsequent calls, returns the cached instance.
---
---@return ExtrasBrowser instance The global ExtrasBrowser singleton
---@private
local function get_instance()
	if not _instance then
		_instance = ExtrasBrowser:new() --[[@as ExtrasBrowser]]
	end
	return _instance
end

return get_instance()
