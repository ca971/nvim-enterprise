---@file lua/core/keymaps.lua
---@description Keymaps — centralized keymap registry with conflict detection, which-key groups, and language-specific bindings
---@module "core.keymaps"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.icons Icons referenced for keymap descriptions and which-key groups
---@see core.options Options sets leader keys before keymaps load
---@see core.bootstrap Bootstrap calls Keymaps.setup() during startup
---@see plugins.editor.which-key Which-key displays group definitions from M.groups
---@see plugins.editor.telescope Telescope keymaps registered here (find, search, git)
---@see plugins.editor.flash Flash keymaps registered here (jump, treesitter)
---@see plugins.editor.trouble Trouble keymaps registered here (diagnostics, todo)
---@see plugins.ui.bufferline BufferLine keymaps registered here (cycle, close, pin)
---@see plugins.ui.noice Noice keymaps registered here (dismiss, history, scroll)
---@see plugins.code.lsp LSP attach keymaps registered via M.on_lsp_attach()
---@see langs All langs/*.lua modules register via M.lang_map() and M.lang_group()
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/keymaps.lua — Centralized keymap management system                 ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Keymaps (module table — registry + setup + audit)               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Components:                                                     │    ║
--- ║  │  ├─ Which-key group definitions (M.groups)                       │    ║
--- ║  │  │  Single source of truth for every <leader> prefix group       │    ║
--- ║  │  │  with semantic icon colors (blue=data, green=nav, etc.)       │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Conflict detection registry (M._registry)                    │    ║
--- ║  │  │  Tracks "mode|lhs" → {desc, source, mode} for every global    │    ║
--- ║  │  │  keymap. Warns via vim.notify on cross-module conflicts.      │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ General keymaps (_register_general)                          │    ║
--- ║  │  │  Better defaults, window/buffer/tab mgmt, diagnostics,        │    ║
--- ║  │  │  movement, search, clipboard, undo breakpoints                │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Plugin keymaps (_register_plugin_keymaps)                    │    ║
--- ║  │  │  Telescope, BufferLine, Noice, Flash, Trouble                 │    ║
--- ║  │  │  Uses lazy require() for deferred plugin loading              │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Language keymaps (lang_map / lang_group)                     │    ║
--- ║  │  │  Per-filetype buffer-local keymaps applied via FileType       │    ║
--- ║  │  │  autocmd. langs/*.lua modules register into M._lang_maps.     │    ║
--- ║  │  │  Which-key <leader>l label overrides per filetype.            │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ LSP attach keymaps (on_lsp_attach)                           │    ║
--- ║  │  │  Buffer-local keymaps added on LspAttach event.               │    ║
--- ║  │  │  Capability-gated: inlay hints, code lens.                    │    ║
--- ║  │  │                                                               │    ║
--- ║  │  └─ Audit & health-check (audit / check_health)                  │    ║
--- ║  │     Registry dump to scratch buffer, prefix conflict detection.  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Color strategy for which-key icons:                             │    ║
--- ║  │  ├─ Blue     Buffer, Windows, LSP          (data / layout)       │    ║
--- ║  │  ├─ Green    Explorer, Search               (navigation)         │    ║
--- ║  │  ├─ Red      Debug, Diagnostics, Profiler   (errors / warnings)  │    ║
--- ║  │  ├─ Orange   Code, Git, Hunks, Noice        (actions / VCS)      │    ║
--- ║  │  ├─ Purple   Lang, UI, Tabs                 (language / settings)│    ║
--- ║  │  ├─ Cyan     Find, Terminal, Prev/Next      (discovery / shell)  │    ║
--- ║  │  ├─ Yellow   Notifications, Surround        (alerts)             │    ║
--- ║  │  └─ Azure    Session                        (persistence)        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ M.map() wraps vim.keymap.set() with conflict detection       │    ║
--- ║  │  │  and source tracking — drop-in replacement                    │    ║
--- ║  │  ├─ Buffer-local and <Plug> keymaps skip registry tracking       │    ║
--- ║  │  │  (no conflict risk — scoped or internal)                      │    ║
--- ║  │  ├─ detect_source() uses debug.getinfo(3) for auto-tagging       │    ║
--- ║  │  ├─ Lang keymaps are deferred (stored, then applied on FT)       │    ║
--- ║  │  │  so langs/*.lua can be loaded at any time during startup      │    ║
--- ║  │  ├─ Retroactive FT application handles `nvim file.py` case       │    ║
--- ║  │  │  where FileType fires before VeryLazy/setup()                 │    ║
--- ║  │  └─ setup() is idempotent via _initialized guard                 │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Conflict detection is O(modes) per map() call (constant for most)     ║
--- ║  • Plugin keymaps use lazy require() — plugins load on first keypress    ║
--- ║  • Lang keymaps are buffer-local — no global namespace pollution         ║
--- ║  • normalize_lhs() uses pattern replacement (single gsub call)           ║
--- ║  • check_health() uses nvim_replace_termcodes for accurate comparison    ║
--- ║                                                                          ║
--- ║  Public API:                                                             ║
--- ║    M.map(mode, lhs, rhs, opts, source)     Register with conflict detect ║
--- ║    M.lang_group(ft, label, icon)           Register FT which-key label   ║
--- ║    M.lang_map(lang, mode, lhs, rhs, opts)  Register FT buffer-local map  ║
--- ║    M.on_lsp_attach(bufnr, client)          LSP buffer-local keymaps      ║
--- ║    M.setup()                               Initialize the keymap system  ║
--- ║    M.audit()                               Dump registry to scratch buf  ║
--- ║    M.check_health()                        Detect prefix conflicts       ║
--- ║    M.get_lang_groups()                     Get registered lang groups    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════
-- TYPE DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════

--- Entry stored in the internal conflict-detection registry.
---@class core.keymaps.RegistryEntry
---@field desc string Human-readable description of the mapping
---@field source string Module or plugin name that registered this keymap
---@field mode string Single-character vim mode (e.g. `"n"`, `"v"`, `"i"`)

--- A deferred language-specific keymap to be applied on FileType.
---@class core.keymaps.LangKeymap
---@field mode string|string[] Vim mode(s) for the mapping
---@field lhs string Left-hand side key sequence (e.g. `"<leader>lr"`)
---@field rhs string|function Right-hand side action
---@field opts vim.keymap.set.Opts Options passed to `vim.keymap.set()`

--- Label and icon for a filetype-specific `<leader>l` which-key group.
---@class core.keymaps.LangGroup
---@field label string Display name shown in which-key (e.g. `"Python"`)
---@field icon string Nerd Font icon glyph (e.g. `""`)

--- Icon spec for which-key v3 group definitions.
---@class core.keymaps.WhichKeyIcon
---@field icon string Nerd Font glyph
---@field color "azure"|"blue"|"cyan"|"green"|"grey"|"orange"|"purple"|"red"|"yellow"

--- A single which-key v3 group spec entry.
---@class core.keymaps.WhichKeyGroup
---@field [1] string Key sequence (e.g. `"<leader>f"`)
---@field group string Display name for the group
---@field icon core.keymaps.WhichKeyIcon Icon with color
---@field buffer? integer Optional buffer number for buffer-local groups

-- ═══════════════════════════════════════════════════════════════════════
-- MODULE DEFINITION
-- ═══════════════════════════════════════════════════════════════════════

--- The keymap system module.
---
--- Provides centralized keymap registration with conflict detection,
--- which-key group definitions, language-specific buffer-local keymaps,
--- LSP attach keymaps, and audit/health-check tooling.
---
---@class core.keymaps
---@field groups core.keymaps.WhichKeyGroup[] Which-key v3 group specs (single source of truth)
---@field _registry table<string, core.keymaps.RegistryEntry> Internal conflict-detection registry (key = `"mode|lhs"`)
---@field _lang_maps table<string, core.keymaps.LangKeymap[]> Per-filetype deferred buffer-local keymaps
---@field _lang_groups table<string, core.keymaps.LangGroup> Per-filetype which-key label overrides for `<leader>l`
---@field _initialized boolean Guard flag to ensure `setup()` runs only once

local icons = require("core.icons")

---@type core.keymaps
local M = {}

-- ═══════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP DEFINITIONS
--
-- Single source of truth for every <leader> prefix group.
-- Each entry defines a key prefix with a display name and colored
-- icon. Registered with which-key via wk.add() during setup().
--
-- Color assignments follow a semantic strategy documented in the
-- architecture header above.
-- ═══════════════════════════════════════════════════════════════════════

--- Which-key v3 group specifications.
---
--- Each entry defines a key prefix group with a display name and colored icon.
--- Registered with which-key during `setup()` via `wk.add()`.
---
---@type core.keymaps.WhichKeyGroup[]
M.groups = {
	-- ── Top-level leader groups ──────────────────────────────────────
	{ "<leader><Tab>", group = "Tabs", icon = { icon = icons.ui.Tab, color = "purple" } },
	{ "<leader>b", group = "Buffer", icon = { icon = icons.ui.Tab, color = "blue" } },
	{ "<leader>c", group = "Code", icon = { icon = icons.ui.Code, color = "orange" } },
	{ "<leader>d", group = "Debug", icon = { icon = icons.ui.Bug, color = "red" } },
	{ "<leader>e", group = "Explorer", icon = { icon = icons.tree.Explorer, color = "green" } },
	{ "<leader>f", group = "Find", icon = { icon = icons.documents.FileFind, color = "cyan" } },
	{ "<leader>g", group = "Git", icon = { icon = icons.git.Logo, color = "orange" } },
	{ "<leader>l", group = "Lang", icon = { icon = icons.misc.Lsp, color = "purple" } },
	{ "<leader>n", group = "Notifications", icon = { icon = icons.misc.Bell, color = "yellow" } },
	{ "<leader>q", group = "Session", icon = { icon = icons.ui.BookMark, color = "azure" } },
	{ "<leader>s", group = "Search", icon = { icon = icons.ui.Telescope, color = "green" } },
	{ "<leader>t", group = "Terminal", icon = { icon = icons.ui.Terminal, color = "cyan" } },
	{ "<leader>u", group = "UI / Toggle", icon = { icon = icons.ui.Gear, color = "purple" } },
	{ "<leader>w", group = "Windows", icon = { icon = icons.ui.Window, color = "blue" } },
	{ "<leader>x", group = "Diagnostics", icon = { icon = icons.diagnostics.Warn, color = "red" } },

	-- ── Sub-groups ───────────────────────────────────────────────────
	{ "<leader>dp", group = "Profiler", icon = { icon = icons.ui.History, color = "red" } },
	{ "<leader>gh", group = "Hunks", icon = { icon = icons.git.Diff, color = "orange" } },
	{ "<leader>sn", group = "Noice", icon = { icon = icons.ui.Fire, color = "orange" } },

	-- ── Bracket navigation groups ────────────────────────────────────
	{ "[", group = "Prev", icon = { icon = icons.ui.BoldArrowLeft, color = "cyan" } },
	{ "]", group = "Next", icon = { icon = icons.ui.BoldArrowRight, color = "cyan" } },

	-- ── g-prefix groups ──────────────────────────────────────────────
	{ "g", group = "Goto / Operators", icon = { icon = icons.kinds.Function, color = "blue" } },
	{ "gs", group = "Surround", icon = { icon = icons.type.Array, color = "yellow" } },
	{ "gr", group = "LSP", icon = { icon = icons.kinds.Interface, color = "blue" } },

	-- ── z-prefix ─────────────────────────────────────────────────────
	{ "z", group = "Folds / Spelling", icon = { icon = icons.ui.WordWrap, color = "grey" } },
}

-- ═══════════════════════════════════════════════════════════════════════
-- INTERNAL STATE
--
-- Registry for conflict detection, per-filetype keymap storage,
-- per-filetype which-key label overrides, and initialization guard.
-- ═══════════════════════════════════════════════════════════════════════

--- Internal registry mapping `"mode|lhs"` to entry metadata.
--- Used for conflict detection when registering global keymaps.
---@type table<string, core.keymaps.RegistryEntry>
M._registry = {}

--- Per-filetype buffer-local keymaps, applied via FileType autocmd.
--- Keys are filetype strings, values are lists of deferred keymap specs.
---@type table<string, core.keymaps.LangKeymap[]>
M._lang_maps = {}

--- Per-filetype which-key label overrides for the `<leader>l` group.
--- When a buffer of a registered filetype opens, the generic "Lang" label
--- is replaced with a language-specific label and icon.
---@type table<string, core.keymaps.LangGroup>
M._lang_groups = {}

--- Guard flag ensuring `setup()` only executes once.
---@type boolean
M._initialized = false

-- ═══════════════════════════════════════════════════════════════════════
-- PRIVATE HELPERS
--
-- Normalization and utility functions for the keymap registry.
-- These handle mode expansion, leader-key normalization, registry
-- key construction, and automatic source detection from the call stack.
-- ═══════════════════════════════════════════════════════════════════════

--- Normalize a mode argument into a flat list of single-character mode strings.
---
--- Accepts all forms used by `vim.keymap.set()`:
--- - A single character: `"n"` → `{"n"}`
--- - A multi-char string: `"nvi"` → `{"n", "v", "i"}`
--- - A table: `{"n", "v"}` → `{"n", "v"}` (returned as-is)
---
---@param mode string|string[] Mode specification
---@return string[] modes List of single-character mode strings
---@private
local function normalize_modes(mode)
	if type(mode) == "table" then return mode end
	local modes = {}
	for i = 1, #mode do
		modes[#modes + 1] = mode:sub(i, i)
	end
	return modes
end

--- Normalize the left-hand side key sequence for consistent registry lookups.
---
--- Handles case-insensitive `<Leader>` / `<leader>` / `<LEADER>` variants
--- by converting them all to lowercase `<leader>`. Ensures that bindings
--- registered with different casing do not create false conflicts.
---
---@param lhs string Raw key sequence (e.g. `"<Leader>ff"`, `"<leader>gg"`)
---@return string normalized Normalized key sequence (e.g. `"<leader>ff"`)
---@private
local function normalize_lhs(lhs)
	local normalized, _ = lhs:gsub("<[Ll][Ee][Aa][Dd][Ee][Rr]>", "<leader>")
	return normalized
end

--- Build a unique registry key from a single mode character and normalized lhs.
---
--- The separator `|` is used because it cannot appear in either a mode
--- character or a key sequence, ensuring uniqueness.
---
---@param m string Single mode character (e.g. `"n"`)
---@param lhs string Normalized key sequence (e.g. `"<leader>ff"`)
---@return string key Registry key (e.g. `"n|<leader>ff"`)
---@private
local function make_reg_key(m, lhs)
	return m .. "|" .. lhs
end

--- Auto-detect the calling module name from the Lua call stack.
---
--- Inspects `debug.getinfo(3)` (caller's caller) to extract the filename
--- without the `.lua` extension. Used as the default `source` parameter
--- in `M.map()` when none is explicitly provided.
---
---@return string source Module filename without extension, or `"unknown"`
---@private
local function detect_source()
	local info = debug.getinfo(3, "S")
	if info and info.source then return info.source:match("([^/\\]+)%.lua$") or "unknown" end
	return "unknown"
end

-- ═══════════════════════════════════════════════════════════════════════
-- PUBLIC API — map()
--
-- Drop-in replacement for vim.keymap.set() that adds conflict
-- detection and source tracking. Every global keymap registered
-- through map() is tracked in M._registry for audit and health.
-- ═══════════════════════════════════════════════════════════════════════

--- Register a keymap with automatic conflict detection.
---
--- Drop-in replacement for `vim.keymap.set()` that additionally:
--- - Tracks every global (non-buffer-local) mapping in `M._registry`
--- - Emits a `vim.notify()` warning if two different source modules
---   attempt to bind the same mode+lhs combination
--- - Defaults to `silent = true` unless overridden in `opts`
--- - Skips registry tracking for buffer-local and `<Plug>` mappings
---
--- ```lua
--- local keys = require("core.keymaps")
--- keys.map("n", "<leader>ff", "<cmd>Telescope find_files<cr>",
---   { desc = "Find files" }, "telescope")
--- ```
---
---@param mode string|string[] Vim mode(s): `"n"`, `"v"`, `"i"`, `"x"`, `{"n","v"}`, etc.
---@param lhs string Key sequence (e.g. `"<leader>ff"`, `"gd"`, `"]d"`)
---@param rhs string|function Right-hand side (command string or Lua function)
---@param opts? vim.keymap.set.Opts Options table (`desc`, `buffer`, `silent`, `expr`, `remap`, etc.)
---@param source? string Module/plugin name for conflict messages; auto-detected if `nil`
function M.map(mode, lhs, rhs, opts, source)
	opts = vim.tbl_extend("force", { silent = true }, opts or {})
	source = source or detect_source()

	-- Conflict detection (global, non-<Plug> keymaps only)
	if not opts.buffer and not lhs:match("^<Plug>") then
		local norm_lhs = normalize_lhs(lhs)
		for _, m in ipairs(normalize_modes(mode)) do
			local key = make_reg_key(m, norm_lhs)
			local prev = M._registry[key]

			if prev and prev.source ~= source then
				vim.schedule(function()
					vim.notify(
						string.format(
							"[keymaps] CONFLICT in mode '%s' for '%s':\n" .. '  was: "%s" (from %s)\n' .. '  now: "%s" (from %s)',
							m,
							lhs,
							prev.desc,
							prev.source,
							opts.desc or "(no desc)",
							source
						),
						vim.log.levels.WARN,
						{ title = "Keymap Conflict" }
					)
				end)
			end

			M._registry[key] = {
				desc = opts.desc or "",
				source = source,
				mode = m,
			}
		end
	end

	vim.keymap.set(mode, lhs, rhs, opts)
end

-- ═══════════════════════════════════════════════════════════════════════
-- PUBLIC API — LANGUAGE KEYMAPS
--
-- Two-part system for filetype-specific keymaps:
-- 1. lang_group(): registers a which-key label override for <leader>l
-- 2. lang_map(): registers a deferred buffer-local keymap
--
-- Both are consumed by the FileType autocmd created in setup().
-- The deferred pattern allows langs/*.lua to be loaded at any time
-- during startup without depending on setup() order.
-- ═══════════════════════════════════════════════════════════════════════

--- Register a which-key group label override for `<leader>l` (filetype-specific).
---
--- When a buffer with the given filetype opens, which-key will display
--- the custom label and icon instead of the generic "Lang" group.
---
--- ```lua
--- keys.lang_group("python", "Python", icons.app.Python)
--- -- In Python buffers: <leader>l shows " Python"
--- -- In other buffers:  <leader>l shows "󰄭 Lang"
--- ```
---
---@param filetype string Vim filetype (e.g. `"python"`, `"rust"`, `"go"`)
---@param label string Display name for which-key (e.g. `"Python"`, `"Rust"`)
---@param icon string Nerd Font icon glyph (e.g. `""`)
function M.lang_group(filetype, label, icon)
	M._lang_groups[filetype] = { label = label, icon = icon }
end

--- Register a language-specific buffer-local keymap.
---
--- The keymap is stored internally and applied as a **buffer-local** mapping
--- whenever a buffer with the matching filetype is opened (via the FileType
--- autocmd created in `setup()`). This prevents language-specific keymaps
--- from polluting the global keymap namespace.
---
--- ```lua
--- -- In lua/langs/python.lua:
--- keys.lang_map("python", "n", "<leader>lr", function()
---   vim.cmd.terminal("python3 " .. vim.fn.shellescape(vim.fn.expand("%:p")))
--- end, { desc = " Run file" })
--- ```
---
---@param lang string|string[] Filetype(s) to bind to (e.g. `"python"` or `{"typescript","javascript"}`)
---@param mode string|string[] Vim mode(s) (e.g. `"n"`, `{"n","v"}`)
---@param lhs string Key sequence (e.g. `"<leader>lr"`)
---@param rhs string|function Right-hand side action
---@param opts? vim.keymap.set.Opts Options (`desc` is strongly recommended for which-key display)
function M.lang_map(lang, mode, lhs, rhs, opts)
	opts = vim.tbl_extend("force", { silent = true }, opts or {})
	local langs = type(lang) == "string" and { lang } or lang

	for _, ft in ipairs(langs) do
		if not M._lang_maps[ft] then M._lang_maps[ft] = {} end
		M._lang_maps[ft][#M._lang_maps[ft] + 1] = {
			mode = mode,
			lhs = lhs,
			rhs = rhs,
			opts = opts,
		}
	end
end

--- Apply all registered language-specific keymaps and which-key group
--- labels for a given buffer and filetype.
---
--- Called automatically by the FileType autocmd created in `setup()`.
--- Also called retroactively for buffers opened before `setup()` ran
--- (e.g., when opening Neovim with a file argument: `nvim file.py`).
---
---@param bufnr integer Buffer number to apply keymaps to
---@param filetype string Detected filetype of the buffer
---@private
function M._apply_lang_maps(bufnr, filetype)
	-- Apply buffer-local keymaps for this filetype
	local maps = M._lang_maps[filetype]
	if maps then
		for _, km in ipairs(maps) do
			local buf_opts = vim.tbl_extend("force", km.opts, { buffer = bufnr })
			vim.keymap.set(km.mode, km.lhs, km.rhs, buf_opts)
		end
	end

	-- Override <leader>l which-key label with language-specific version
	local lg = M._lang_groups[filetype]
	if lg then
		local ok, wk = pcall(require, "which-key")
		if ok then wk.add({
			{ "<leader>l", group = lg.label, icon = lg.icon, buffer = bufnr },
		}) end
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- PUBLIC API — LSP ATTACH KEYMAPS
--
-- Buffer-local keymaps added when an LSP client attaches.
-- Only registers keymaps that supplement Neovim 0.11+ built-in
-- defaults (grn, grr, gra, gri, gO, CTRL-S are already provided).
-- Capability-dependent mappings (inlay hints, code lens) are
-- conditionally registered only when the client supports them.
-- ═══════════════════════════════════════════════════════════════════════

--- Create standard LSP buffer-local keymaps on LspAttach.
---
--- Registers only keymaps that supplement Neovim 0.11+ built-in defaults
--- (`grn`, `grr`, `gra`, `gri`, `gO`, `CTRL-S` are already provided).
---
--- Conditionally registers capability-dependent mappings (inlay hints,
--- code lens) only when the attached LSP client supports them.
---
--- ```lua
--- vim.api.nvim_create_autocmd("LspAttach", {
---   callback = function(ev)
---     local client = vim.lsp.get_client_by_id(ev.data.client_id)
---     require("core.keymaps").on_lsp_attach(ev.buf, client)
---   end,
--- })
--- ```
---
---@param bufnr integer Buffer number to attach keymaps to
---@param client? vim.lsp.Client LSP client instance (used for capability checks; may be `nil`)
function M.on_lsp_attach(bufnr, client)
	--- Set a buffer-local keymap with common defaults.
	---@param mode string|string[] Vim mode(s)
	---@param lhs string Key sequence
	---@param rhs string|function Action
	---@param desc string Human-readable description
	local function bmap(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
	end

	-- ── Diagnostics ──────────────────────────────────────────────────
	bmap("n", "<leader>cd", vim.diagnostic.open_float, "Line diagnostics")

	-- ── Formatting ───────────────────────────────────────────────────
	bmap({ "n", "v" }, "<leader>cF", function()
		vim.lsp.buf.format({ async = true, bufnr = bufnr })
	end, icons.ui.Code .. " Format buffer")

	-- ── Inlay Hints (capability-gated) ───────────────────────────────
	if client and client:supports_method("textDocument/inlayHint") then
		bmap("n", "<leader>uh", function()
			local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr })
			vim.lsp.inlay_hint.enable(not enabled, { bufnr = bufnr })
		end, "Toggle inlay hints")
	end

	-- ── Code Lens (capability-gated) ─────────────────────────────────
	if client and client:supports_method("textDocument/codeLens") then
		bmap("n", "<leader>cc", vim.lsp.codelens.run, "Run code lens")
		bmap("n", "<leader>cC", vim.lsp.codelens.refresh, "Refresh code lens")
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- GENERAL KEYMAPS
--
-- All non-plugin keymaps: better defaults, cursor movement, search,
-- empty lines, undo breakpoints, indentation, yank/paste, move lines,
-- window navigation/resize/management, buffer switching, tab mgmt,
-- diagnostic navigation, quickfix/location list, and clipboard.
--
-- All registered through M.map() with source "general" for
-- conflict detection.
-- ═══════════════════════════════════════════════════════════════════════

--- Register all general-purpose (non-plugin) keymaps.
---
--- All keymaps are registered through `M.map()` with source `"general"`
--- to participate in conflict detection.
---@private
function M._register_general()
	local map = M.map

	-- ── Better defaults ──────────────────────────────────────────────
	map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" }, "general")
	map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = icons.ui.Lock .. " Save file" }, "general")
	map("n", "<leader>qq", "<cmd>qa<cr>", { desc = icons.ui.SignOut .. " Quit all" }, "general")
	map("n", "<leader>fn", "<cmd>enew<cr>", { desc = icons.ui.NewFile .. " New file" }, "general")

	-- ── Better up/down (respects wrapped lines) ──────────────────────
	map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true }, "general")
	map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true }, "general")
	map({ "n", "x" }, "<Down>", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true }, "general")
	map({ "n", "x" }, "<Up>", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true }, "general")

	-- ── Better search (center + unfold) ──────────────────────────────
	map("n", "n", "'Nn'[v:searchforward].'zv'", { desc = "Next search result", expr = true }, "general")
	map("n", "N", "'nN'[v:searchforward].'zv'", { desc = "Prev search result", expr = true }, "general")
	map({ "x", "o" }, "n", "'Nn'[v:searchforward]", { desc = "Next search result", expr = true }, "general")
	map({ "x", "o" }, "N", "'nN'[v:searchforward]", { desc = "Prev search result", expr = true }, "general")

	-- ── Add empty lines ──────────────────────────────────────────────
	map("n", "]<Space>", function()
		local count = vim.v.count1
		local lines = {} ---@type string[]
		for _ = 1, count do
			lines[#lines + 1] = ""
		end
		vim.api.nvim_put(lines, "l", true, false)
	end, { desc = "Add empty line below" }, "general")

	map("n", "[<Space>", function()
		local count = vim.v.count1
		local lines = {} ---@type string[]
		for _ = 1, count do
			lines[#lines + 1] = ""
		end
		local row = vim.api.nvim_win_get_cursor(0)[1]
		vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, lines)
	end, { desc = "Add empty line above" }, "general")

	-- ── Undo breakpoints in insert mode ──────────────────────────────
	map("i", ",", ",<C-g>u", { desc = "Undo breakpoint", silent = false }, "general")
	map("i", ".", ".<C-g>u", { desc = "Undo breakpoint", silent = false }, "general")
	map("i", ";", ";<C-g>u", { desc = "Undo breakpoint", silent = false }, "general")

	-- ── Leave insert mode ────────────────────────────────────────────
	map("i", "jj", "<Esc>", { silent = true, desc = "Leave Insert Mode" }, "general")

	-- ── Toggle line numbers ──────────────────────────────────────────
	--stylua: ignore start
	map( "n", "<leader>N", "<cmd>exec &nu==&rnu? 'se nu!' : 'se rnu!'<CR>", { noremap = true, silent = true, desc = "Toggle Line Numbers" }, "general")
	--stylua: ignore end

	-- ── Better indenting (stay in visual mode) ───────────────────────
	-- map("v", "<", "<gv", { desc = "Indent left" }, "general")
	-- map("v", ">", ">gv", { desc = "Indent right" }, "general")

	-- ── Don't yank on x/X ───────────────────────────────────────────
	map("n", "x", '"_x', { desc = "Delete char (no yank)" }, "general")
	map("n", "X", '"_X', { desc = "Delete char back (no yank)" }, "general")

	-- ── Select all ───────────────────────────────────────────────────
	map("n", "<leader>A", "gg<S-v>G", { desc = "Select all" }, "general")

	-- ── Paste without yanking in visual mode ─────────────────────────
	map("x", "p", '"_dP', { desc = "Paste (no yank)" }, "general")

	-- ── Keywordprg ───────────────────────────────────────────────────
	map("n", "<leader>K", "<cmd>norm! K<cr>", { desc = icons.ui.List .. " Keywordprg" }, "general")

	-- ── Redraw / clear ───────────────────────────────────────────────
	map(
		"n",
		"<leader>ur",
		"<cmd>nohlsearch<bar>diffupdate<bar>normal! <C-L><cr>",
		{ desc = icons.ui.Refresh .. " Redraw / Clear hlsearch" },
		"general"
	)

	-- ── Move lines ───────────────────────────────────────────────────
	map("n", "<M-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move line down" }, "general")
	map("n", "<M-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move line up" }, "general")
	map("i", "<M-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move line down" }, "general")
	map("i", "<M-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move line up" }, "general")
	map("v", "<M-j>", ":m '>+1<cr>gv=gv", { desc = "Move selection down" }, "general")
	map("v", "<M-k>", ":m '<-2<cr>gv=gv", { desc = "Move selection up" }, "general")

	-- ── Windows: navigation ──────────────────────────────────────────
	map("n", "<C-h>", "<C-w>h", { desc = "Left window" }, "general")
	map("n", "<C-j>", "<C-w>j", { desc = "Lower window" }, "general")
	map("n", "<C-k>", "<C-w>k", { desc = "Upper window" }, "general")
	map("n", "<C-l>", "<C-w>l", { desc = "Right window" }, "general")

	-- ── Windows: resize ──────────────────────────────────────────────
	map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase height" }, "general")
	map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease height" }, "general")
	map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase width" }, "general")
	map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease width" }, "general")

	-- ── Windows: management ──────────────────────────────────────────
	map("n", "<leader>wd", "<C-w>c", { desc = icons.ui.BoldClose .. " Close window" }, "general")
	map("n", "<leader>w|", "<C-w>v", { desc = "Vertical split" }, "general")
	map("n", "<leader>w-", "<C-w>s", { desc = "Horizontal split" }, "general")
	map("n", "<leader>wo", "<C-w>o", { desc = "Close other windows" }, "general")
	map("n", "<leader>w=", "<C-w>=", { desc = "Equalize windows" }, "general")
	map("n", "<leader>wT", "<C-w>T", { desc = "Move to new tab" }, "general")

	-- ── Split shortcuts (quick access aliases) ───────────────────────
	map("n", "<leader>|", "<C-w>v", { desc = "Vertical split" }, "general")
	map("n", "<leader>-", "<C-w>s", { desc = "Horizontal split" }, "general")

	-- ── Buffers ──────────────────────────────────────────────────────
	map("n", "<leader>bb", "<cmd>e #<cr>", { desc = "Alternate buffer" }, "general")
	map("n", "<leader>bn", "<cmd>enew<cr>", { desc = icons.ui.NewFile .. " New buffer" }, "general")

	-- ── Tabs ─────────────────────────────────────────────────────────
	map("n", "<leader><Tab><Tab>", "<cmd>tabnew<cr>", { desc = "New tab" }, "general")
	map("n", "<leader><Tab>d", "<cmd>tabclose<cr>", { desc = "Close tab" }, "general")
	map("n", "<leader><Tab>o", "<cmd>tabonly<cr>", { desc = "Close other tabs" }, "general")
	map("n", "<leader><Tab>]", "<cmd>tabnext<cr>", { desc = "Next tab" }, "general")
	map("n", "<leader><Tab>[", "<cmd>tabprevious<cr>", { desc = "Prev tab" }, "general")
	map("n", "<leader><Tab>f", "<cmd>tabfirst<cr>", { desc = "First tab" }, "general")
	map("n", "<leader><Tab>l", "<cmd>tablast<cr>", { desc = "Last tab" }, "general")

	-- ── Terminal navigation ──────────────────────────────────────────
	map("t", "<C-h>", "<C-\\><C-N><C-w>h", { silent = true, desc = "Switch Right (Terminal)" }, "general")
	map("t", "<C-l>", "<C-\\><C-N><C-w>l", { silent = true, desc = "Switch Left (Terminal)" }, "general")
	map("t", "<C-j>", "<C-\\><C-N><C-w>j", { silent = true, desc = "Switch Down (Terminal)" }, "general")
	map("t", "<C-k>", "<C-\\><C-N><C-w>k", { silent = true, desc = "Switch Up (Terminal)" }, "general")

	-- ── Diagnostics: quick navigation ────────────────────────────────
	local severity = vim.diagnostic.severity

	map("n", "[d", function()
		vim.diagnostic.jump({ count = -1, float = true })
	end, { desc = "Prev diagnostic" }, "general")

	map("n", "]d", function()
		vim.diagnostic.jump({ count = 1, float = true })
	end, { desc = "Next diagnostic" }, "general")

	map("n", "[e", function()
		vim.diagnostic.jump({ count = -1, severity = severity.ERROR, float = true })
	end, { desc = "Prev error" }, "general")

	map("n", "]e", function()
		vim.diagnostic.jump({ count = 1, severity = severity.ERROR, float = true })
	end, { desc = "Next error" }, "general")

	map("n", "[w", function()
		vim.diagnostic.jump({ count = -1, severity = severity.WARN, float = true })
	end, { desc = "Prev warning" }, "general")

	map("n", "]w", function()
		vim.diagnostic.jump({ count = 1, severity = severity.WARN, float = true })
	end, { desc = "Next warning" }, "general")

	-- ── Quickfix and location list ───────────────────────────────────
	map("n", "<leader>xq", "<cmd>copen<cr>", { desc = "Quickfix list" }, "general")
	map("n", "<leader>xl", "<cmd>lopen<cr>", { desc = "Location list" }, "general")
	map("n", "[q", "<cmd>cprevious<cr>", { desc = "Prev quickfix" }, "general")
	map("n", "]q", "<cmd>cnext<cr>", { desc = "Next quickfix" }, "general")
	map("n", "[Q", "<cmd>cfirst<cr>", { desc = "First quickfix" }, "general")
	map("n", "]Q", "<cmd>clast<cr>", { desc = "Last quickfix" }, "general")

	-- ── Clipboard (system register) ──────────────────────────────────
	map({ "n", "v" }, "<leader>y", '"+y', { desc = "Yank to clipboard" }, "general")
	map("n", "<leader>Y", '"+yg_', { desc = "Yank line to clipboard" }, "general")
	map({ "n", "v" }, "<leader>p", '"+p', { desc = "Paste from clipboard" }, "general")
	map({ "n", "v" }, "<leader>P", '"+P', { desc = "Paste before from clipboard" }, "general")
end

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN-SPECIFIC KEYMAPS
--
-- Keymaps for plugins not managed via lazy.nvim `keys = {}`.
-- Each plugin section uses lazy require() so the plugin is only
-- loaded when the keymap is first triggered. All keymaps registered
-- through M.map() with explicit source names for conflict detection.
-- ═══════════════════════════════════════════════════════════════════════

--- Register keymaps for plugins not managed via lazy.nvim `keys = {}`.
---@private
function M._register_plugin_keymaps()
	local map = M.map

	-- ── Telescope: core shortcuts ────────────────────────────────────
	map("n", "<leader>/", function()
		require("telescope.builtin").live_grep()
	end, { desc = icons.ui.Search .. " Grep (live)" }, "telescope")

	map("n", "<leader>,", function()
		require("telescope.builtin").buffers({ sort_mru = true, sort_lastused = true })
	end, { desc = icons.ui.Tab .. " Buffers" }, "telescope")

	map("n", "<leader>:", function()
		require("telescope.builtin").command_history()
	end, { desc = "Command history" }, "telescope")

	-- ── Telescope: find ──────────────────────────────────────────────
	map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find files" }, "telescope")
	map(
		"n",
		"<leader>fF",
		"<cmd>Telescope find_files hidden=true no_ignore=true<cr>",
		{ desc = "Find files (all)" },
		"telescope"
	)
	map("n", "<leader>fg", function()
		require("telescope.builtin").git_files()
	end, { desc = icons.git.Logo .. " Git files" }, "telescope")
	map(
		"n",
		"<leader>fb",
		"<cmd>Telescope buffers sort_mru=true sort_lastused=true<cr>",
		{ desc = icons.ui.Tab .. " Buffers" },
		"telescope"
	)
	map(
		"n",
		"<leader>fr",
		"<cmd>Telescope frecency<cr>",
		{ desc = icons.ui.History .. " Recent (frecency)" },
		"telescope"
	)
	map(
		"n",
		"<leader>fR",
		"<cmd>Telescope oldfiles<cr>",
		{ desc = icons.ui.History .. " Recent (oldfiles)" },
		"telescope"
	)

	-- ── Telescope: search ────────────────────────────────────────────
	map("n", "<leader>sg", "<cmd>Telescope live_grep<cr>", { desc = "Grep (live)" }, "telescope")
	map("n", "<leader>sw", "<cmd>Telescope grep_string<cr>", { desc = "Grep word" }, "telescope")
	map("v", "<leader>sw", "<cmd>Telescope grep_string<cr>", { desc = "Grep selection" }, "telescope")
	map("n", "<leader>sb", "<cmd>Telescope current_buffer_fuzzy_find<cr>", { desc = "Search in buffer" }, "telescope")
	map("n", "<leader>sR", "<cmd>Telescope resume<cr>", { desc = icons.ui.Refresh .. " Resume last search" }, "telescope")
	map("n", "<leader>sp", "<cmd>Telescope pickers<cr>", { desc = "Previous pickers" }, "telescope")
	map("n", "<leader>sk", "<cmd>Telescope keymaps<cr>", { desc = icons.ui.Keyboard .. " Keymaps" }, "telescope")
	map("n", "<leader>sH", "<cmd>Telescope help_tags<cr>", { desc = "Help tags" }, "telescope")
	map("n", "<leader>sM", "<cmd>Telescope man_pages<cr>", { desc = "Man pages" }, "telescope")
	map("n", "<leader>so", "<cmd>Telescope vim_options<cr>", { desc = "Vim options" }, "telescope")
	map("n", "<leader>sc", "<cmd>Telescope command_history<cr>", { desc = "Command history" }, "telescope")
	map("n", "<leader>sC", "<cmd>Telescope commands<cr>", { desc = "Commands" }, "telescope")
	map("n", "<leader>sa", "<cmd>Telescope autocommands<cr>", { desc = "Autocommands" }, "telescope")
	map("n", "<leader>sh", "<cmd>Telescope highlights<cr>", { desc = "Highlights" }, "telescope")
	map("n", "<leader>sj", "<cmd>Telescope jumplist<cr>", { desc = "Jumplist" }, "telescope")
	map("n", "<leader>sl", "<cmd>Telescope loclist<cr>", { desc = "Location list" }, "telescope")
	map("n", "<leader>sq", "<cmd>Telescope quickfix<cr>", { desc = "Quickfix list" }, "telescope")
	map("n", "<leader>s'", "<cmd>Telescope marks<cr>", { desc = "Marks" }, "telescope")
	map("n", '<leader>s"', "<cmd>Telescope registers<cr>", { desc = "Registers" }, "telescope")

	-- ── Telescope: LSP integration ───────────────────────────────────
	map("n", "<leader>ss", "<cmd>Telescope aerial<cr>", { desc = "Goto symbol (Aerial)" }, "telescope")
	map("n", "<leader>sS", "<cmd>Telescope lsp_workspace_symbols<cr>", { desc = "Workspace symbols" }, "telescope")
	map("n", "<leader>sd", "<cmd>Telescope diagnostics bufnr=0<cr>", { desc = "Buffer diagnostics" }, "telescope")
	map("n", "<leader>sD", "<cmd>Telescope diagnostics<cr>", { desc = "Workspace diagnostics" }, "telescope")
	map("n", "<leader>sr", "<cmd>Telescope lsp_references<cr>", { desc = "References" }, "telescope")
	map("n", "<leader>si", "<cmd>Telescope lsp_implementations<cr>", { desc = "Implementations" }, "telescope")
	map("n", "<leader>sT", "<cmd>Telescope treesitter<cr>", { desc = "Treesitter symbols" }, "telescope")

	-- ── Telescope: extensions ────────────────────────────────────────
	map("n", "<leader>sf", "<cmd>Telescope filetypes<cr>", { desc = "Filetypes" }, "telescope")
	map("n", "<leader>sP", "<cmd>Telescope lazy<cr>", { desc = icons.misc.Lazy .. " Plugins" }, "telescope")
	map("n", "<leader>sN", "<cmd>Telescope luasnip<cr>", { desc = "Snippets" }, "telescope")
	map("n", "<leader>su", "<cmd>Telescope undo<cr>", { desc = "Undo tree" }, "telescope")
	map("n", "<leader>fp", "<cmd>Telescope projects<cr>", { desc = icons.ui.Project .. " Projects" }, "telescope")
	map("n", "<leader>fz", "<cmd>Telescope zoxide list<cr>", { desc = "Zoxide" }, "telescope")
	map("n", "<leader>fe", "<cmd>Telescope file_browser<cr>", { desc = "File browser" }, "telescope")
	map(
		"n",
		"<leader>fE",
		"<cmd>Telescope file_browser path=%:p:h select_buffer=true<cr>",
		{ desc = "File browser (cwd)" },
		"telescope"
	)

	-- ── Telescope: colorschemes ──────────────────────────────────────
	map("n", "<leader>st", function()
		require("telescope.builtin").colorscheme({ enable_preview = true })
	end, { desc = icons.ui.Art .. " Colorschemes" }, "telescope")

	-- ── Git (Telescope pickers) ──────────────────────────────────────
	map("n", "<leader>gc", "<cmd>Telescope git_commits<cr>", { desc = icons.git.Commit .. " Commits" }, "telescope")
	map(
		"n",
		"<leader>gC",
		"<cmd>Telescope git_bcommits<cr>",
		{ desc = icons.git.Commit .. " Commits (buffer)" },
		"telescope"
	)
	map("n", "<leader>gb", "<cmd>Telescope git_branches<cr>", { desc = icons.git.Branch .. " Branches" }, "telescope")
	map("n", "<leader>gt", "<cmd>Telescope git_stash<cr>", { desc = "Stash" }, "telescope")
	map("n", "<leader>gs", function()
		require("telescope.builtin").git_status()
	end, { desc = icons.git.Git .. " Git status" }, "telescope")

	-- ── BufferLine ───────────────────────────────────────────────────
	map("n", "H", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev buffer" }, "bufferline")
	map("n", "L", "<cmd>BufferLineCycleNext<cr>", { desc = "Next buffer" }, "bufferline")
	map("n", "[b", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev buffer" }, "bufferline")
	map("n", "]b", "<cmd>BufferLineCycleNext<cr>", { desc = "Next buffer" }, "bufferline")
	map("n", "[B", "<cmd>BufferLineMovePrev<cr>", { desc = "Move buffer left" }, "bufferline")
	map("n", "]B", "<cmd>BufferLineMoveNext<cr>", { desc = "Move buffer right" }, "bufferline")
	map("n", "<leader>bo", "<cmd>BufferLineCloseOthers<cr>", { desc = "Close others" }, "bufferline")
	map("n", "<leader>bp", "<cmd>BufferLineTogglePin<cr>", { desc = "Toggle pin" }, "bufferline")
	map("n", "<leader>bP", "<cmd>BufferLineGroupClose ungrouped<cr>", { desc = "Close unpinned" }, "bufferline")
	map("n", "<leader>bl", "<cmd>BufferLineCloseLeft<cr>", { desc = "Close to left" }, "bufferline")
	map("n", "<leader>br", "<cmd>BufferLineCloseRight<cr>", { desc = "Close to right" }, "bufferline")
	map("n", "<leader>bs", "<cmd>BufferLineSortByDirectory<cr>", { desc = "Sort by directory" }, "bufferline")

	-- ── Noice ────────────────────────────────────────────────────────
	map("n", "<leader>snd", function()
		require("noice").cmd("dismiss")
	end, { desc = "Dismiss all" }, "noice")

	map("n", "<leader>sna", function()
		require("noice").cmd("all")
	end, { desc = "All messages" }, "noice")

	map("n", "<leader>snh", function()
		require("noice").cmd("history")
	end, { desc = "History" }, "noice")

	map("n", "<leader>snl", function()
		require("noice").cmd("last")
	end, { desc = "Last message" }, "noice")

	map("n", "<leader>snt", function()
		require("noice").cmd("pick")
	end, { desc = "Noice picker" }, "noice")

	-- Scroll in hover docs / signature help (Noice LSP override)
	map({ "n", "i", "s" }, "<C-f>", function()
		if not require("noice.lsp").scroll(4) then return "<C-f>" end
	end, { desc = "Scroll forward", expr = true }, "noice")

	map({ "n", "i", "s" }, "<C-b>", function()
		if not require("noice.lsp").scroll(-4) then return "<C-b>" end
	end, { desc = "Scroll backward", expr = true }, "noice")

	-- ── Flash ────────────────────────────────────────────────────────
	map({ "n", "x", "o" }, "s", function()
		require("flash").jump()
	end, { desc = "Flash" }, "flash")

	map({ "n", "x", "o" }, "S", function()
		require("flash").treesitter()
	end, { desc = "Flash Treesitter" }, "flash")

	map("o", "r", function()
		require("flash").remote()
	end, { desc = "Remote Flash" }, "flash")

	map({ "o", "x" }, "R", function()
		require("flash").treesitter_search()
	end, { desc = "Treesitter search" }, "flash")

	map("c", "<C-s>", function()
		require("flash").toggle()
	end, { desc = "Toggle Flash search" }, "flash")

	-- ── Trouble ──────────────────────────────────────────────────────
	map("n", "<leader>xx", function()
		require("trouble").toggle("diagnostics")
	end, { desc = icons.diagnostics.Error .. " Diagnostics (Trouble)" }, "trouble")

	map("n", "<leader>xX", function()
		require("trouble").toggle({ mode = "diagnostics", filter = { buf = 0 } })
	end, { desc = "Buffer diagnostics" }, "trouble")

	map("n", "<leader>xt", function()
		require("trouble").toggle("todo")
	end, { desc = "TODO (Trouble)" }, "trouble")

	map("n", "<leader>xT", function()
		require("trouble").toggle({ mode = "todo", keywords = { "TODO", "FIX", "FIXME" } })
	end, { desc = "TODO/FIX/FIXME" }, "trouble")

	map("n", "<leader>xQ", function()
		require("trouble").toggle("quickfix")
	end, { desc = "Quickfix (Trouble)" }, "trouble")

	map("n", "<leader>xL", function()
		require("trouble").toggle("loclist")
	end, { desc = "Location list (Trouble)" }, "trouble")

	map("n", "<leader>cl", function()
		require("trouble").toggle("lsp")
	end, { desc = "LSP defs/refs (Trouble)" }, "trouble")
end

-- ═══════════════════════════════════════════════════════════════════════
-- SETUP
--
-- Initializes the full keymap system in order:
-- 1. General keymaps (better defaults, navigation, etc.)
-- 2. Plugin keymaps (Telescope, BufferLine, Noice, Flash, Trouble)
-- 3. Which-key group registration
-- 4. FileType autocmd for language-specific keymaps
-- 5. Retroactive application to already-loaded buffers
--
-- Idempotent via _initialized guard.
-- ═══════════════════════════════════════════════════════════════════════

--- Initialize the keymap system.
---
--- Performs the following in order:
--- 1. Registers all general-purpose keymaps (`_register_general`)
--- 2. Registers all plugin-specific keymaps (`_register_plugin_keymaps`)
--- 3. Adds which-key group definitions (if which-key is loaded)
--- 4. Creates a `FileType` autocmd for language-specific keymaps
--- 5. Retroactively applies lang keymaps to already-loaded buffers
---
--- **Idempotent:** guarded by `M._initialized`; safe to call multiple times.
---
--- ```lua
--- -- Called from which-key plugin config after wk.setup():
--- require("core.keymaps").setup()
--- ```
function M.setup()
	if M._initialized then return end
	M._initialized = true

	-- Register keymaps
	M._register_general()
	M._register_plugin_keymaps()

	-- Register which-key groups (if which-key is already loaded)
	local ok, wk = pcall(require, "which-key")
	if ok then wk.add(M.groups) end

	-- FileType autocmd: apply per-language keymaps and which-key labels
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("CoreKeymapLang", { clear = true }),
		desc = "Apply language-specific keymaps and which-key group labels",
		callback = function(ev)
			M._apply_lang_maps(ev.buf, ev.match)
		end,
	})

	-- Retroactively apply to buffers opened BEFORE setup() ran.
	-- Handles the case: `nvim file.py` (FileType fires before VeryLazy).
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			local ft = vim.bo[buf].filetype
			if ft ~= "" then M._apply_lang_maps(buf, ft) end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- AUDIT & DEBUGGING
--
-- Tools for reviewing the full keymap landscape:
-- • audit(): dumps registry to a scratch buffer, grouped by source
-- • check_health(): detects prefix conflicts using termcode comparison
-- • get_lang_groups(): returns registered language groups for display
-- ═══════════════════════════════════════════════════════════════════════

--- Print all registered keymaps to a scratch buffer, grouped by source module.
---
--- Opens a vertical split with a read-only buffer containing:
--- - Total keymap count and language group/keymap summary
--- - All keymaps sorted by source module then by registry key
--- - Language-specific keymaps with their filetype icons
---
--- **Usage:** `:lua require("core.keymaps").audit()`
function M.audit()
	---@type table<string, { key: string, desc: string }[]>
	local by_source = {}
	for key, entry in pairs(M._registry) do
		local src = entry.source
		if not by_source[src] then by_source[src] = {} end
		by_source[src][#by_source[src] + 1] = {
			key = key,
			desc = entry.desc,
		}
	end

	---@type string[]
	local lines = {
		"========================================",
		"       Keymap Registry Audit            ",
		"========================================",
		"",
		string.format("Total keymaps registered: %d", vim.tbl_count(M._registry)),
		string.format("Language groups: %d", vim.tbl_count(M._lang_groups)),
		string.format("Language keymaps: %d filetypes", vim.tbl_count(M._lang_maps)),
		"",
	}

	local sources = vim.tbl_keys(by_source)
	table.sort(sources)

	for _, src in ipairs(sources) do
		local entries = by_source[src]
		table.sort(entries, function(a, b)
			return a.key < b.key
		end)
		lines[#lines + 1] = string.format("-- %s (%d) --", src, #entries)
		for _, entry in ipairs(entries) do
			lines[#lines + 1] = string.format("  %-30s  %s", entry.key, entry.desc)
		end
		lines[#lines + 1] = ""
	end

	if next(M._lang_maps) then
		lines[#lines + 1] = "-- Language Keymaps --"
		for ft, maps in pairs(M._lang_maps) do
			local lg = M._lang_groups[ft]
			local ft_icon = lg and (lg.icon .. " ") or ""
			lines[#lines + 1] = string.format("  %s%s: %d keymaps", ft_icon, ft, #maps)
			for _, km in ipairs(maps) do
				lines[#lines + 1] = string.format("    %-20s  %s", km.lhs, km.opts.desc or "(no desc)")
			end
		end
		lines[#lines + 1] = ""
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("filetype", "keymapaudit", { buf = buf })
	vim.cmd.vsplit()
	vim.api.nvim_win_set_buf(0, buf)
end

--- Detect prefix conflicts in the keymap registry.
---
--- A prefix conflict occurs when one key sequence is both a direct mapping
--- and a prefix for longer mappings in the same mode. While which-key
--- handles these gracefully via timeout, they may indicate unintentional
--- keymap design issues.
---
--- Uses `vim.api.nvim_replace_termcodes()` to compare actual internal
--- byte representations, avoiding false positives from raw string matching.
---
--- **Usage:** `:lua require("core.keymaps").check_health()`
function M.check_health()
	local all_keys = vim.tbl_keys(M._registry)
	table.sort(all_keys)

	--- Convert a key sequence to its internal byte representation.
	---@param lhs string Key sequence (e.g. `"<leader>ff"`, `"<M-j>"`)
	---@return string internal Internal byte representation
	local function to_internal(lhs)
		return vim.api.nvim_replace_termcodes(lhs, true, true, true)
	end

	---@type string[]
	local conflicts = {}
	for i, k1 in ipairs(all_keys) do
		local m1, lhs1 = k1:match("^(.)|(.+)$")
		if m1 and lhs1 then
			local internal1 = to_internal(lhs1)
			for j = i + 1, #all_keys do
				local k2 = all_keys[j]
				local m2, lhs2 = k2:match("^(.)|(.+)$")
				if m2 and lhs2 and m1 == m2 then
					local internal2 = to_internal(lhs2)
					if internal2:sub(1, #internal1) == internal1 and #internal2 > #internal1 then
						conflicts[#conflicts + 1] = string.format(
							"  mode '%s': '%s' (%s) <- prefix of -> '%s' (%s)",
							m1,
							lhs1,
							M._registry[k1].desc,
							lhs2,
							M._registry[k2].desc
						)
					end
				end
			end
		end
	end

	if #conflicts > 0 then
		vim.notify(
			string.format("Found %d prefix conflict(s):\n%s", #conflicts, table.concat(conflicts, "\n")),
			vim.log.levels.WARN,
			{ title = "Keymap Health Check" }
		)
	else
		vim.notify("No prefix conflicts detected", vim.log.levels.INFO, { title = "Keymap Health Check" })
	end
end

--- Get a deep copy of all registered language groups.
---
--- Useful for statusline or dashboard display, where you want to list
--- which language-specific which-key groups are available.
---
--- ```lua
--- local groups = require("core.keymaps").get_lang_groups()
--- for ft, info in pairs(groups) do
---   print(info.icon .. " " .. info.label)  --> " Python"
--- end
--- ```
---
---@return table<string, core.keymaps.LangGroup> groups Map of filetype to `{label, icon}`
function M.get_lang_groups()
	return vim.deepcopy(M._lang_groups)
end

return M
