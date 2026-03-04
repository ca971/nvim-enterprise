---@file lua/plugins/editor/grug-far.lua
---@description Grug Far — project-wide search & replace with live preview and ripgrep backend
---@module "plugins.editor.grug-far"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.telescope  Telescope grep pickers (search-only, complementary)
---@see plugins.editor.diffview   Diffview for reviewing changes after bulk replace
---@see plugins.editor.gitsigns   Git hunk actions (undo individual changes post-replace)
---
---@see https://github.com/MagicDuck/grug-far.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/grug-far.lua — Search & Replace engine                   ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  grug-far.nvim                                                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  • Project-wide find and replace (ripgrep + AST-grep backends)   │    ║
--- ║  │  • Live preview of replacements before applying                  │    ║
--- ║  │  • Regex support (PCRE2 via ripgrep)                             │    ║
--- ║  │  • File glob filtering (search only in *.lua, exclude tests/)    │    ║
--- ║  │  • Replace in specific files, buffers, or entire project         │    ║
--- ║  │  • Visual selection as search input                              │    ║
--- ║  │  • Sync results with quickfix list                               │    ║
--- ║  │  • Persistent history of previous search/replace operations      │    ║
--- ║  │  • AST-grep engine for structural code search (optional)         │    ║
--- ║  │                                                                  │    ║
--- ║  │  UI layout (vertical split):                                     │    ║
--- ║  │  ┌─────────────────────────────────────────────────────────┐     │    ║
--- ║  │  │   Search:  [pattern]                                    │     │    ║
--- ║  │  │   Replace: [replacement]                                │     │    ║
--- ║  │  │   Files:   [glob filter]                                │     │    ║
--- ║  │  │   Flags:   [--flags]                                    │     │    ║
--- ║  │  │─────────────────────────────────────────────────────────│     │    ║
--- ║  │  │   file.lua:12: matched line with [highlight]            │     │    ║
--- ║  │  │   file.lua:45: another match with [highlight]           │     │    ║
--- ║  │  │   other.lua:3: third match [highlight]                  │     │    ║
--- ║  │  └─────────────────────────────────────────────────────────┘     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Search scopes:                                                  │    ║
--- ║  │  ├─ Project-wide   (default — all files matching glob)           │    ║
--- ║  │  ├─ Current file   (<leader>rf — paths = current file)           │    ║
--- ║  │  ├─ Open buffers   (<leader>rb — paths = all listed bufs)        │    ║
--- ║  │  ├─ Word/WORD      (<leader>rw/rW — prefilled search term)       │    ║
--- ║  │  └─ Visual sel.    (<leader>rv — prefilled from selection)       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (inside grug-far buffer):                  │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  <localleader>r  Replace all matches                     │    │    ║
--- ║  │  │  <localleader>q  Send results to quickfix list           │    │    ║
--- ║  │  │  <localleader>s  Sync locations                          │    │    ║
--- ║  │  │  <localleader>l  Sync current line                       │    │    ║
--- ║  │  │  <localleader>e  Swap engine (ripgrep ↔ ast-grep)        │    │    ║
--- ║  │  │  <localleader>t  Open history                            │    │    ║
--- ║  │  │  <localleader>i  Preview location                        │    │    ║
--- ║  │  │  <C-j>/<C-k>    Navigate results (next/prev)             │    │    ║
--- ║  │  │  <enter>         Go to location / pick history           │    │    ║
--- ║  │  │  q               Close buffer                            │    │    ║
--- ║  │  │  g?              Help                                    │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Complements (does NOT replace):                                 │    ║
--- ║  │  ├─ <leader>sg   Live grep (Telescope — search only, no replace) │    ║
--- ║  │  ├─ <leader>sw   Grep word (Telescope — search only)             │    ║
--- ║  │  ├─ <leader>sb   Buffer search (Telescope — single buffer)       │    ║
--- ║  │  ├─ <leader>/    Grep live (Snacks — search only)                │    ║
--- ║  │  ├─ :%s/old/new/ Vim built-in (single file, no preview)          │    ║
--- ║  │  └─ <leader>cr   Rename file (LSP rename — symbols only)         │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • cmd + keys loading (zero startup cost until first use)                ║
--- ║  • ripgrep backend (fastest grep tool available)                         ║
--- ║  • --hidden --glob=!.git/ (search dotfiles, skip .git directory)         ║
--- ║  • Optional ast-grep backend (structural search, needs `sg` binary)      ║
--- ║  • Results streamed incrementally (responsive on large codebases)        ║
--- ║  • Transient mode: buffer auto-cleaned when closed                       ║
--- ║  • mini.* modules disabled in grug-far buffer (prevents conflicts)       ║
--- ║  • Icons from core/icons.lua (single source of truth)                    ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║  ┌─────────────────────────────────────────────────────────────────────┐ ║
--- ║  │  KEY          MODE   ACTION                     CONFLICT STATUS     │ ║
--- ║  │  <leader>rr   n      Search & Replace (project) ✓ safe (r* owned)   │ ║
--- ║  │  <leader>rw   n      Replace word under cursor  ✓ safe              │ ║
--- ║  │  <leader>rW   n      Replace WORD under cursor  ✓ safe              │ ║
--- ║  │  <leader>rf   n      Search & Replace (file)    ✓ safe              │ ║
--- ║  │  <leader>rv   x      Replace visual selection   ✓ safe              │ ║
--- ║  │  <leader>rb   n      Search & Replace (buffers) ✓ safe              │ ║
--- ║  └─────────────────────────────────────────────────────────────────────┘ ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Grug Far plugin is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_plugin_enabled("grug_far") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

---@type Icons
local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open grug-far in transient mode with optional prefills.
---
--- Wraps `require("grug-far").open()` with `transient = true` to
--- ensure the buffer is auto-cleaned when closed. Accepts an optional
--- prefills table for pre-populating search, replace, or paths fields.
---
--- ```lua
--- open_grug({})                                        -- empty search
--- open_grug({ search = "foo" })                        -- prefilled search
--- open_grug({ paths = vim.fn.expand("%") })            -- scoped to file
--- open_grug({ search = "foo", paths = "*.lua" })       -- combined
--- ```
---
---@param prefills? table<string, string> Optional prefill fields (`search`, `replace`, `paths`, `flags`)
---@return nil
---@private
local function open_grug(prefills)
	local opts = { transient = true }
	if prefills and next(prefills) then opts.prefills = prefills end
	require("grug-far").open(opts)
end

--- Collect relative paths of all open (listed) buffers.
---
--- Iterates over all loaded, listed buffers, extracts their file paths,
--- and converts them to CWD-relative paths. Used to scope search &
--- replace operations to only the currently open buffers.
---
--- ```lua
--- local paths = get_open_buffer_paths()
--- -- → { "lua/init.lua", "lua/core/settings.lua", ... }
--- ```
---
---@return string[] paths CWD-relative file paths of all open buffers
---@private
local function get_open_buffer_paths()
	---@type string[]
	local buf_paths = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
			local name = vim.api.nvim_buf_get_name(buf)
			if name ~= "" then buf_paths[#buf_paths + 1] = vim.fn.fnamemodify(name, ":.") end
		end
	end
	return buf_paths
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPEC
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Trigger            │ Details                                      │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ cmd                │ :GrugFar (for direct command-line access)    │
-- │ keys               │ <leader>r{r,w,W,f,v,b} (6 entry points)    │
-- │ dependencies       │ none (ripgrep expected system-wide)          │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"MagicDuck/grug-far.nvim",

	-- ═══════════════════════════════════════════════════════════════════
	-- LAZY LOADING STRATEGY
	--
	-- Cmd + keys loading ensures zero startup cost. The plugin is only
	-- loaded when a search & replace operation is explicitly triggered.
	-- ═══════════════════════════════════════════════════════════════════
	cmd = "GrugFar",

	-- ═══════════════════════════════════════════════════════════════════
	-- GLOBAL KEYMAPS
	--
	-- All keymaps live under <leader>r (Replace group).
	-- This prefix is exclusively owned by grug-far — no conflicts
	-- with other plugins.
	--
	-- ⚠ CONFLICT AUDIT:
	-- <leader>rr (n)   — no conflict (r* prefix is grug-far-owned)
	-- <leader>rw (n)   — no conflict
	-- <leader>rW (n)   — no conflict
	-- <leader>rf (n)   — no conflict
	-- <leader>rv (x)   — no conflict (visual mode only)
	-- <leader>rb (n)   — no conflict
	-- ═══════════════════════════════════════════════════════════════════
	keys = {
		-- ── Project-wide search ──────────────────────────────────────
		{
			"<leader>rr",
			function()
				open_grug()
			end,
			desc = icons.ui.Search .. " Search & Replace (project)",
		},

		-- ── Word under cursor ────────────────────────────────────────
		{
			"<leader>rw",
			function()
				open_grug({ search = vim.fn.expand("<cword>") })
			end,
			desc = icons.ui.Search .. " Replace word under cursor",
		},

		-- ── WORD under cursor (includes special chars) ───────────────
		{
			"<leader>rW",
			function()
				open_grug({ search = vim.fn.expand("<cWORD>") })
			end,
			desc = icons.ui.Search .. " Replace WORD under cursor",
		},

		-- ── Current file only ────────────────────────────────────────
		{
			"<leader>rf",
			function()
				open_grug({ paths = vim.fn.expand("%") })
			end,
			desc = icons.ui.File .. " Search & Replace (current file)",
		},

		-- ── Visual selection ─────────────────────────────────────────
		{
			"<leader>rv",
			function()
				require("grug-far").with_visual_selection({ transient = true })
			end,
			mode = "x",
			desc = icons.ui.Search .. " Replace selection",
		},

		-- ── Open buffers only ────────────────────────────────────────
		{
			"<leader>rb",
			function()
				local paths = get_open_buffer_paths()
				open_grug({ paths = table.concat(paths, " ") })
			end,
			desc = icons.ui.Tab .. " Search & Replace (open buffers)",
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	--
	-- Returned as a function to defer any heavy computation until the
	-- plugin is actually loaded (lazy-safe).
	--
	-- Organized into logical sections:
	-- ├─ Engine          Backend selection (ripgrep / ast-grep)
	-- ├─ Window          Creation command and transient mode
	-- ├─ Icons           UI elements from core/icons.lua
	-- ├─ Results         Display configuration
	-- ├─ Keymaps         Buffer-local keymaps (inside grug-far buffer)
	-- ├─ History         Persistent search/replace history
	-- ├─ Ripgrep         Extra arguments for ripgrep backend
	-- └─ Folding         Result folding behavior
	-- ═══════════════════════════════════════════════════════════════════
	opts = function()
		return {
			-- ── Engine ──────────────────────────────────────────────
			-- "ripgrep" for standard text search (fastest).
			-- "astgrep" for structural code search (needs `sg` binary).
			-- Swappable at runtime with <localleader>e.
			---@type string
			engine = "ripgrep",

			-- ── Window ──────────────────────────────────────────────
			-- vsplit: opens grug-far in a vertical split (side-by-side
			-- with the source file for context).
			-- transient: auto-cleanup buffer when closed.
			-- startInInsertMode: false to allow immediate navigation.
			---@type string
			windowCreationCommand = "vsplit",
			---@type boolean
			transient = true,
			---@type boolean
			startInInsertMode = false,

			-- ── Icons ───────────────────────────────────────────────
			-- All icons sourced from core/icons.lua for consistency
			-- with the rest of the Neovim configuration.
			---@type table<string, string|boolean>
			icons = {
				enabled = true,
				actionEntryBullet = icons.ui.ChevronRight .. " ",
				searchInput = icons.ui.Search .. " ",
				replaceInput = icons.ui.Pencil .. " ",
				filesFilterInput = icons.ui.File .. " ",
				flagsInput = icons.ui.Gear .. " ",
				resultsStatusReady = icons.ui.Check .. " ",
				resultsStatusError = icons.diagnostics.Error .. " ",
				resultsStatusSuccess = icons.ui.Check .. " ",
				resultsActionMessage = icons.ui.Lightbulb .. " ",
				historyTitle = icons.ui.History .. " History",
			},

			-- ── Results ─────────────────────────────────────────────
			-- Line numbers displayed right-aligned for clean layout.
			resultLocation = {
				---@type boolean
				showNumberLabel = true,
				---@type string
				numberLabelPosition = "right_align",
			},

			-- ── Buffer-local keymaps ────────────────────────────────
			-- These keymaps are ONLY active inside the grug-far buffer.
			-- They use <localleader> prefix to avoid ANY conflict with
			-- global keymaps. Navigation uses <C-j>/<C-k> for
			-- consistency with Telescope and other pickers.
			---@type table<string, table<string, string>>
			keymaps = {
				replace = { n = "<localleader>r" },
				qflist = { n = "<localleader>q" },
				syncLocations = { n = "<localleader>s" },
				syncLine = { n = "<localleader>l" },
				close = { n = "q" },
				historyOpen = { n = "<localleader>t" },
				historyAdd = { n = "<localleader>a" },
				refresh = { n = "<localleader>f" },
				openLocation = { n = "<localleader>o" },
				openNextLocation = { n = "<C-j>" },
				openPrevLocation = { n = "<C-k>" },
				gotoLocation = { n = "<enter>" },
				pickHistoryEntry = { n = "<enter>" },
				abort = { n = "<localleader>b" },
				help = { n = "g?" },
				toggleShowCommand = { n = "<localleader>p" },
				swapEngine = { n = "<localleader>e" },
				previewLocation = { n = "<localleader>i" },
				swapReplacementInterpreter = { n = "<localleader>x" },
			},

			-- ── History ─────────────────────────────────────────────
			-- Persistent history allows recalling previous search &
			-- replace operations. Auto-saved on buffer delete to
			-- prevent data loss.
			history = {
				---@type boolean
				enabled = true,
				---@type integer
				maxItems = 50,
				autoSave = {
					---@type boolean
					enabled = true,
					---@type boolean
					onBufDelete = true,
				},
			},

			-- ── Ripgrep arguments ───────────────────────────────────
			-- --hidden:         search inside dotfiles (.env, .config)
			-- --glob=!.git/:    always exclude the .git directory
			---@type string
			extraRgArgs = "--hidden --glob=!.git/",

			---@type string
			filesFilter = "",

			-- ── Folding ─────────────────────────────────────────────
			-- Results can be folded by file for large result sets.
			-- foldlevel=0: all files collapsed by default.
			folding = {
				---@type boolean
				enabled = true,
				---@type integer
				foldlevel = 0,
				---@type string
				foldcolumn = "1",
			},
		}
	end,

	-- ═══════════════════════════════════════════════════════════════════
	-- CONFIG
	--
	-- Post-setup hooks:
	-- 1. Register the <leader>r which-key group with icon
	-- 2. Create a FileType autocommand for grug-far buffers that:
	--    • Unlists the buffer (hidden from buffer pickers)
	--    • Disables mini.cursorword (prevents highlight flicker)
	--    • Disables mini.trailspace (search input has trailing spaces)
	--    • Disables mini.indentscope (irrelevant in search UI)
	-- ═══════════════════════════════════════════════════════════════════

	---@param _ table Plugin spec (unused)
	---@param opts table Resolved options
	config = function(_, opts)
		require("grug-far").setup(opts)

		-- ── Which-key group ──────────────────────────────────────────
		local wk_ok, wk = pcall(require, "which-key")
		if wk_ok then
			wk.add({
				{
					"<leader>r",
					group = icons.ui.Search .. " Search & Replace",
					icon = { icon = icons.ui.Search, color = "red" },
				},
			})
		end

		-- ── Disable mini.* modules in grug-far buffers ───────────────
		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("GrugFar_BufferConfig", { clear = true }),
			pattern = "grug-far",
			desc = "Unlist grug-far buffer and disable mini.* modules",
			---@param event { buf: integer } Autocmd event data
			callback = function(event)
				vim.bo[event.buf].buflisted = false
				vim.b[event.buf].minicursorword_disable = true
				vim.b[event.buf].minitrailspace_disable = true
				vim.b[event.buf].miniindentscope_disable = true
			end,
		})
	end,
}
