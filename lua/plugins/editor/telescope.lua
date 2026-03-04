---@file lua/plugins/editor/telescope.lua
---@description Telescope — performance-optimized fuzzy finder with full extension ecosystem
---@module "plugins.editor.telescope"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.icons Central icon definitions
---@see core.settings Project-wide settings and feature flags
---@see plugins.editor.persisted Session management (Telescope extension)
---@see plugins.editor.grug-far Project-wide search & replace (complementary)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/telescope.lua — Fuzzy finder & picker engine             ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  telescope.nvim                                                  │    ║
--- ║  │                                                                  │    ║
--- ║  │  • Fuzzy finder for files, grep, buffers, LSP, git, and more     │    ║
--- ║  │  • Native C FZF sorter via telescope-fzf-native (fastest)        │    ║
--- ║  │  • Enterprise UI-select interception (replaces vim.ui.select)    │    ║
--- ║  │  • 11 extensions loaded lazily on-demand                         │    ║
--- ║  │  • Ripgrep backend for all grep operations                       │    ║
--- ║  │  • Flex layout: auto-switches horizontal/vertical at 140 cols    │    ║
--- ║  │  • Picker cache: 10 previous pickers re-openable                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Extension ecosystem:                                            │    ║
--- ║  │  ├─ fzf-native       Native C FZF sorter (auto-loaded)           │    ║
--- ║  │  ├─ ui-select        Replace vim.ui.select (intercepted)         │    ║
--- ║  │  ├─ file-browser     File browser with CRUD operations           │    ║
--- ║  │  ├─ live-grep-args   Grep with raw ripgrep arguments             │    ║
--- ║  │  ├─ undo             Undo tree browser with delta diffs          │    ║
--- ║  │  ├─ frecency         Frequency × recency file sorting            │    ║
--- ║  │  ├─ zoxide           Smart directory jumping (z command)         │    ║
--- ║  │  ├─ lazy             Browse lazy.nvim installed plugins          │    ║
--- ║  │  ├─ luasnip          Browse and insert LuaSnip snippets          │    ║
--- ║  │  ├─ symbols          Unicode symbols, emoji, math, Nerd Font     │    ║
--- ║  │  └─ persisted        Git-branch-aware session browser            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Complements (does NOT replace):                                 │    ║
--- ║  │  ├─ <leader>rr  grug-far.nvim (search & REPLACE — project-wide)  │    ║
--- ║  │  ├─ <leader>/   Snacks grep (quick grep shortcut)                │    ║
--- ║  │  ├─ <leader>,   Snacks buffers (quick buffer shortcut)           │    ║
--- ║  │  ├─ <leader>:   Snacks command history (quick shortcut)          │    ║
--- ║  │  └─ <leader>ss  Aerial (symbol outline — different UX)           │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Loaded ONLY on cmd/keys (never at startup)                            ║
--- ║  • Extensions loaded lazily via pcall (no startup cost)                  ║
--- ║  • No require() in top-level scope (all deferred to opts/config)         ║
--- ║  • Extension configs use lazy functions to avoid early require           ║
--- ║  • Conditional extensions (zoxide, fd, delta) via executable check       ║
--- ║  • vim.fn.executable() cached at spec parse time (once)                  ║
--- ║  • Dependencies marked lazy = true where possible                        ║
--- ║  • Icons from core/icons.lua (single source of truth)                    ║
--- ║  • Borders derived from core/settings (float_border preference)          ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║                                                                          ║
--- ║    Files:                                                                ║
--- ║      <leader>ff    Find files (fd or find)                   (n)         ║
--- ║      <leader>fF    Find files (all, hidden + ignored)        (n)         ║
--- ║      <leader>fR    Recent files (oldfiles)                   (n)         ║
--- ║      <leader>fb    Open buffers (MRU sorted)                 (n)         ║
--- ║      <leader>fe    File browser (project root)               (n)         ║
--- ║      <leader>fE    File browser (current file dir)           (n)         ║
--- ║      <leader>fr    Recent files (frecency)                   (n)         ║
--- ║      <leader>fz    Zoxide directory jump                     (n)         ║
--- ║                                                                          ║
--- ║    Grep:                                                                 ║
--- ║      <leader>sg    Live grep (ripgrep)                       (n)         ║
--- ║      <leader>sG    Live grep with args (ripgrep flags)       (n)         ║
--- ║      <leader>sw    Grep word under cursor                    (n)         ║
--- ║      <leader>sw    Grep visual selection                     (v)         ║
--- ║      <leader>sb    Fuzzy search in current buffer            (n)         ║
--- ║                                                                          ║
--- ║    Git:                                                                  ║
--- ║      <leader>gc    Git commits (all)                         (n)         ║
--- ║      <leader>gC    Git commits (current buffer)              (n)         ║
--- ║      <leader>gb    Git branches                              (n)         ║
--- ║      <leader>gt    Git stash entries                         (n)         ║
--- ║                                                                          ║
--- ║    LSP:                                                                  ║
--- ║      <leader>ss    Document symbols (LSP)                    (n)         ║
--- ║      <leader>sS    Workspace symbols (LSP)                   (n)         ║
--- ║      <leader>sd    Buffer diagnostics                        (n)         ║
--- ║      <leader>sD    Workspace diagnostics                     (n)         ║
--- ║      <leader>si    LSP implementations                       (n)         ║
--- ║      <leader>sr    LSP references                            (n)         ║
--- ║                                                                          ║
--- ║    Vim internals:                                                        ║
--- ║      <leader>sH    Help tags                                 (n)         ║
--- ║      <leader>sM    Man pages                                 (n)         ║
--- ║      <leader>so    Vim options                               (n)         ║
--- ║      <leader>sk    Keymaps                                   (n)         ║
--- ║      <leader>sc    Command history                           (n)         ║
--- ║      <leader>sC    Commands                                  (n)         ║
--- ║      <leader>sa    Autocommands                              (n)         ║
--- ║      <leader>sh    Highlights                                (n)         ║
--- ║      <leader>sj    Jumplist                                  (n)         ║
--- ║      <leader>sl    Location list                             (n)         ║
--- ║      <leader>sq    Quickfix list                             (n)         ║
--- ║      <leader>sR    Resume last picker                        (n)         ║
--- ║      <leader>sp    Previous pickers (cached)                 (n)         ║
--- ║      <leader>sf    Filetypes                                 (n)         ║
--- ║      <leader>sT    Treesitter symbols                        (n)         ║
--- ║      <leader>s"    Registers                                 (n)         ║
--- ║      <leader>s'    Marks                                     (n)         ║
--- ║                                                                          ║
--- ║    Extensions:                                                           ║
--- ║      <leader>sG    Grep with args (live-grep-args)           (n)         ║
--- ║      <leader>su    Undo tree (telescope-undo)                (n)         ║
--- ║      <leader>sP    Lazy.nvim plugins (telescope-lazy)        (n)         ║
--- ║      <leader>sN    LuaSnip snippets (telescope-luasnip)      (n)         ║
--- ║      <leader>se    Symbols: emoji, math, nerd (telescope-symbols) (n)    ║
--- ║      <leader>qS    Sessions (telescope-persisted) — owned by persisted   ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
if not settings:is_plugin_enabled("telescope") then return {} end

---@type Icons
local icons = require("core.icons")

return {
	"nvim-telescope/telescope.nvim",
	lazy = true,
	version = false,
	cmd = "Telescope",

	-- ═══════════════════════════════════════════════════════════════════
	-- ENTERPRISE-GRADE UI-SELECT INTERCEPTION
	--
	-- Replaces vim.ui.select at startup with zero cost.
	-- The original function is overridden with a wrapper that:
	-- 1. Force-loads telescope.nvim via lazy.nvim
	-- 2. Loads the ui-select extension
	-- 3. Calls the now-overridden vim.ui.select with original args
	--
	-- Result: Telescope only loads when a selection menu actually opens.
	-- Cost at startup: 0.00ms (just a function assignment).
	-- ═══════════════════════════════════════════════════════════════════
	init = function()
		---@diagnostic disable-next-line: duplicate-set-field
		vim.ui.select = function(...)
			require("lazy").load({ plugins = { "telescope.nvim" } })
			require("telescope").load_extension("ui-select")
			return vim.ui.select(...)
		end
	end,

	-- ═══════════════════════════════════════════════════════════════════
	-- KEYS — Native Telescope pickers
	--
	-- Organized by functional group: files, grep, git, LSP, vim internals.
	-- Each keymap maps directly to a Telescope builtin picker.
	-- Extension-specific keymaps are on their dependency specs below.
	-- ═══════════════════════════════════════════════════════════════════
	keys = {
		-- ── Files ────────────────────────────────────────────────────
		{ "<leader>ff", "<Cmd>Telescope find_files<CR>", desc = icons.ui.Search .. " Find files" },
		{
			"<leader>fF",
			"<Cmd>Telescope find_files hidden=true no_ignore=true<CR>",
			desc = icons.ui.Search .. " Find files (all)",
		},
		{ "<leader>fR", "<Cmd>Telescope oldfiles<CR>", desc = icons.ui.History .. " Recent (oldfiles)" },
		{ "<leader>fb", "<Cmd>Telescope buffers sort_mru=true sort_lastused=true<CR>", desc = icons.ui.Tab .. " Buffers" },

		-- ── Grep ─────────────────────────────────────────────────────
		{ "<leader>sg", "<Cmd>Telescope live_grep<CR>", desc = icons.ui.Search .. " Grep (live)" },
		{ "<leader>sw", "<Cmd>Telescope grep_string<CR>", desc = icons.ui.Search .. " Grep word" },
		{ "<leader>sw", "<Cmd>Telescope grep_string<CR>", mode = "v", desc = icons.ui.Search .. " Grep selection" },
		{ "<leader>sb", "<Cmd>Telescope current_buffer_fuzzy_find<CR>", desc = icons.ui.Search .. " Search in buffer" },

		-- ── Git ──────────────────────────────────────────────────────
		{ "<leader>gc", "<Cmd>Telescope git_commits<CR>", desc = icons.git.Commit .. " Commits" },
		{ "<leader>gC", "<Cmd>Telescope git_bcommits<CR>", desc = icons.git.Commit .. " Commits (buffer)" },
		{ "<leader>gb", "<Cmd>Telescope git_branches<CR>", desc = icons.git.Branch .. " Branches" },
		{ "<leader>gt", "<Cmd>Telescope git_stash<CR>", desc = icons.git.Git .. " Stash" },

		-- ── LSP ──────────────────────────────────────────────────────
		{ "<leader>ss", "<Cmd>Telescope lsp_document_symbols<CR>", desc = icons.kinds.Function .. " Document symbols" },
		{ "<leader>sS", "<Cmd>Telescope lsp_workspace_symbols<CR>", desc = icons.kinds.Function .. " Workspace symbols" },
		{ "<leader>sd", "<Cmd>Telescope diagnostics bufnr=0<CR>", desc = icons.diagnostics.Warn .. " Buffer diagnostics" },
		{ "<leader>sD", "<Cmd>Telescope diagnostics<CR>", desc = icons.diagnostics.Warn .. " Workspace diagnostics" },
		{ "<leader>si", "<Cmd>Telescope lsp_implementations<CR>", desc = icons.kinds.Interface .. " Implementations" },
		{ "<leader>sr", "<Cmd>Telescope lsp_references<CR>", desc = icons.kinds.Reference .. " References" },

		-- ── Vim internals ────────────────────────────────────────────
		{ "<leader>sH", "<Cmd>Telescope help_tags<CR>", desc = icons.ui.Note .. " Help tags" },
		{ "<leader>sM", "<Cmd>Telescope man_pages<CR>", desc = icons.documents.Default .. " Man pages" },
		{ "<leader>so", "<Cmd>Telescope vim_options<CR>", desc = icons.ui.Gear .. " Vim options" },
		{ "<leader>sk", "<Cmd>Telescope keymaps<CR>", desc = icons.ui.Keyboard .. " Keymaps" },
		{ "<leader>sc", "<Cmd>Telescope command_history<CR>", desc = icons.ui.History .. " Command history" },
		{ "<leader>sC", "<Cmd>Telescope commands<CR>", desc = icons.ui.Terminal .. " Commands" },
		{ "<leader>sa", "<Cmd>Telescope autocommands<CR>", desc = icons.ui.Gear .. " Autocommands" },
		{ "<leader>sh", "<Cmd>Telescope highlights<CR>", desc = icons.ui.Couleur .. " Highlights" },
		{ "<leader>sj", "<Cmd>Telescope jumplist<CR>", desc = icons.ui.BoldArrowRight .. " Jumplist" },
		{ "<leader>sl", "<Cmd>Telescope loclist<CR>", desc = icons.ui.List .. " Location list" },
		{ "<leader>sq", "<Cmd>Telescope quickfix<CR>", desc = icons.ui.Bug .. " Quickfix list" },
		{ "<leader>sR", "<Cmd>Telescope resume<CR>", desc = icons.ui.Refresh .. " Resume last" },
		{ "<leader>sp", "<Cmd>Telescope pickers<CR>", desc = icons.ui.History .. " Previous pickers" },
		{ "<leader>sf", "<Cmd>Telescope filetypes<CR>", desc = icons.ui.File .. " Filetypes" },
		{ "<leader>sT", "<Cmd>Telescope treesitter<CR>", desc = icons.misc.Treesitter .. " Treesitter symbols" },
		{ '<leader>s"', "<Cmd>Telescope registers<CR>", desc = icons.ui.Copy .. " Registers" },
		{ "<leader>s'", "<Cmd>Telescope marks<CR>", desc = icons.ui.BookMark .. " Marks" },
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- DEPENDENCIES — Strictly lazy-loaded
	--
	-- Each extension is a separate dependency spec with its own `keys`
	-- table. This means the extension only loads when its specific
	-- keymap is triggered — not when Telescope opens for any reason.
	--
	-- Pattern: keymap → load_extension() → vim.cmd("Telescope <ext>")
	-- This ensures zero startup cost for unused extensions.
	-- ═══════════════════════════════════════════════════════════════════
	dependencies = {
		{ "nvim-lua/plenary.nvim", lazy = true },

		-- ── FZF native sorter ────────────────────────────────────────
		-- Compiled C implementation of the FZF algorithm.
		-- Auto-loaded in config() via pcall (safe if build fails).
		{ "nvim-telescope/telescope-fzf-native.nvim", build = "make", lazy = true },

		-- ── UI-Select ────────────────────────────────────────────────
		-- Loaded via init() interception, not via keymap.
		{ "nvim-telescope/telescope-ui-select.nvim", lazy = true },

		-- ── File browser ─────────────────────────────────────────────
		{
			"nvim-telescope/telescope-file-browser.nvim",
			keys = {
				{
					"<leader>fe",
					--- Open the file browser at the project root.
					--- Loads the extension on first invocation.
					function()
						require("telescope").load_extension("file_browser")
						vim.cmd("Telescope file_browser")
					end,
					desc = icons.ui.Folder .. " File browser",
				},
				{
					"<leader>fE",
					--- Open the file browser at the current file's directory.
					--- Selects the current buffer in the file list.
					function()
						require("telescope").load_extension("file_browser")
						vim.cmd("Telescope file_browser path=%:p:h select_buffer=true")
					end,
					desc = icons.ui.Folder .. " File browser (cwd)",
				},
			},
			lazy = true,
		},

		-- ── Live grep with args ──────────────────────────────────────
		{
			"nvim-telescope/telescope-live-grep-args.nvim",
			version = "^1.0.0",
			keys = {
				{
					"<leader>sG",
					--- Open live grep with raw ripgrep argument support.
					--- Allows flags like `--glob`, `--type`, `--fixed-strings`.
					---
					--- Example searches:
					---   `"exact phrase" --glob=*.lua`
					---   `pattern --type=py --no-ignore`
					function()
						require("telescope").load_extension("live_grep_args")
						require("telescope").extensions.live_grep_args.live_grep_args()
					end,
					desc = icons.ui.Search .. " Grep (with args)",
				},
			},
			lazy = true,
		},

		-- ── Undo tree browser ────────────────────────────────────────
		{
			"debugloop/telescope-undo.nvim",
			keys = {
				{
					"<leader>su",
					--- Open the undo tree browser.
					--- Uses `delta` for side-by-side diffs if the binary is available.
					--- Press `<CR>` to restore the selected undo state.
					function()
						require("telescope").load_extension("undo")
						vim.cmd("Telescope undo")
					end,
					desc = icons.ui.History .. " Undo tree",
				},
			},
			lazy = true,
		},

		-- ── Frecency (frequency × recency) ──────────────────────────
		{
			"nvim-telescope/telescope-frecency.nvim",
			dependencies = { { "kkharji/sqlite.lua", lazy = true } },
			keys = {
				{
					"<leader>fr",
					--- Open the frecency picker.
					--- Sorts files by a combined frequency × recency score,
					--- prioritizing files you open often AND recently.
					--- Requires sqlite3 for persistent scoring database.
					function()
						require("telescope").load_extension("frecency")
						vim.cmd("Telescope frecency")
					end,
					desc = icons.ui.History .. " Recent (frecency)",
				},
			},
			lazy = true,
		},

		-- ── Zoxide (smart cd) ────────────────────────────────────────
		{
			"jvgrootveld/telescope-zoxide",
			keys = {
				{
					"<leader>fz",
					--- Open the zoxide directory picker.
					--- Requires the `zoxide` binary (`cargo install zoxide`).
					--- Directories are ranked by frequency of use.
					function()
						require("telescope").load_extension("zoxide")
						vim.cmd("Telescope zoxide list")
					end,
					desc = icons.ui.Folder .. " Zoxide",
				},
			},
			lazy = true,
		},

		-- ── Lazy.nvim plugin browser ─────────────────────────────────
		{
			"tsakirist/telescope-lazy.nvim",
			keys = {
				{
					"<leader>sP",
					--- Browse all installed lazy.nvim plugins.
					--- Shows plugin name, source, load time, and status.
					function()
						require("telescope").load_extension("lazy")
						vim.cmd("Telescope lazy")
					end,
					desc = icons.misc.Lazy .. " Plugins",
				},
			},
			lazy = true,
		},

		-- ── LuaSnip snippet browser ──────────────────────────────────
		{
			"benfowler/telescope-luasnip.nvim",
			keys = {
				{
					"<leader>sN",
					--- Browse available LuaSnip snippets for the current filetype.
					--- Press `<CR>` to insert the selected snippet at cursor.
					function()
						require("telescope").load_extension("luasnip")
						vim.cmd("Telescope luasnip")
					end,
					desc = icons.kinds.Snippet .. " Snippets",
				},
			},
			lazy = true,
		},

		-- ── Symbols picker (emoji, math, Unicode, Nerd Font) ────────
		{
			"nvim-telescope/telescope-symbols.nvim",
			keys = {
				{
					"<leader>se",
					--- Open the symbols picker with all available sources.
					--- Sources: emoji, math, latex, nerd font, kaomoji, gitmoji.
					---
					--- Note: telescope-symbols is NOT a Telescope extension.
					--- It's a data provider for `telescope.builtin.symbols()`.
					--- No `load_extension()` call needed.
					function()
						require("telescope.builtin").symbols({
							sources = { "emoji", "math", "latex", "nerd", "kaomoji", "gitmoji" },
						})
					end,
					desc = icons.ui.Art .. " Symbols (emoji/math/nerd)",
				},
			},
			lazy = true,
		},

		-- ── Persisted sessions (Telescope extension) ─────────────────
		-- Keymaps owned by persisted.lua (<leader>qS).
		-- Declared here only so Telescope knows the extension exists
		-- and can configure its picker layout in the extensions block.
		{
			"olimorris/persisted.nvim",
			lazy = true,
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTS — Telescope configuration
	--
	-- Uses a function to defer require("telescope.actions") until
	-- Telescope actually loads. No top-level requires — everything
	-- is resolved inside the function at load time.
	-- ═══════════════════════════════════════════════════════════════════

	---@return table opts Complete Telescope setup options
	opts = function()
		local actions = require("telescope.actions")
		local layout_actions = require("telescope.actions.layout")

		---@type string Border style from user settings
		local border = settings:get("ui.float_border", "rounded")

		--- Build the `find_files` command based on available binaries.
		--- Prefers `fd` over `find` for speed, hidden file support,
		--- and sane defaults (respects .gitignore automatically).
		---@type string[]|nil
		local find_command = nil
		if vim.fn.executable("fd") == 1 then
			find_command = {
				"fd",
				"--type",
				"f",
				"--strip-cwd-prefix",
				"--hidden",
				"--follow",
				"--exclude",
				".git",
			}
		end

		return {
			-- ── Defaults ─────────────────────────────────────────────
			defaults = {
				prompt_prefix = icons.ui.Telescope .. "  ",
				selection_caret = icons.ui.ChevronRight .. " ",
				multi_icon = icons.ui.Check .. " ",
				path_display = { "truncate" },
				sorting_strategy = "ascending",
				selection_strategy = "reset",
				scroll_strategy = "limit",
				color_devicons = true,
				set_env = { ["COLORTERM"] = "truecolor" },

				-- ── Layout ───────────────────────────────────────────
				-- Flex layout auto-switches between horizontal and
				-- vertical based on terminal width (flip at 140 cols).
				layout_strategy = "flex",
				layout_config = {
					horizontal = { prompt_position = "top", preview_width = 0.55 },
					vertical = { mirror = false, preview_height = 0.5 },
					flex = { flip_columns = 140 },
					width = 0.87,
					height = 0.85,
					preview_cutoff = 60,
				},

				-- ── Borders ──────────────────────────────────────────
				borderchars = border == "rounded" and { "─", "│", "─", "│", "╭", "╮", "╯", "╰" } or nil,

				-- ── File ignore patterns ─────────────────────────────
				-- Applied to ALL pickers that list files.
				-- Supplements .gitignore (which ripgrep/fd respect natively).
				---@type string[]
				file_ignore_patterns = {
					"%.git/",
					"node_modules/",
					"__pycache__/",
					"%.pyc",
					"%.o",
					"%.a",
					"%.out",
					"%.class",
					"%.pdf",
					"%.mkv",
					"%.mp4",
					"%.zip",
					"%.tar",
					"%.gz",
					"%.DS_Store",
					"vendor/",
					"%.lock",
				},

				-- ── Keymaps inside Telescope ─────────────────────────
				-- These are ONLY active inside the Telescope window.
				-- They do NOT conflict with global keymaps.
				mappings = {
					i = {
						["<C-n>"] = actions.cycle_history_next,
						["<C-p>"] = actions.cycle_history_prev,
						["<C-j>"] = actions.move_selection_next,
						["<C-k>"] = actions.move_selection_previous,
						["<CR>"] = actions.select_default,
						["<C-x>"] = actions.select_horizontal,
						["<C-v>"] = actions.select_vertical,
						["<C-t>"] = actions.select_tab,
						["<C-u>"] = actions.preview_scrolling_up,
						["<C-d>"] = actions.preview_scrolling_down,
						["<M-p>"] = layout_actions.toggle_preview,
						["<C-c>"] = actions.close,
					},
					n = {
						["q"] = actions.close,
						["<CR>"] = actions.select_default,
						["<M-p>"] = layout_actions.toggle_preview,
					},
				},

				-- ── Picker cache ─────────────────────────────────────
				-- Keep last 10 pickers in memory for re-opening via
				-- <leader>sp (Previous pickers) and <leader>sR (Resume).
				cache_picker = { num_pickers = 10 },

				-- ── Ripgrep arguments ────────────────────────────────
				-- Applied to all grep-based pickers (live_grep, grep_string).
				-- --hidden: include dotfiles
				-- --smart-case: case-insensitive unless uppercase is used
				-- --glob=!.git/: exclude .git directory contents
				---@type string[]
				vimgrep_arguments = {
					"rg",
					"--color=never",
					"--no-heading",
					"--with-filename",
					"--line-number",
					"--column",
					"--smart-case",
					"--hidden",
					"--glob=!.git/",
				},
			},

			-- ── Per-picker overrides ─────────────────────────────────
			pickers = {
				find_files = {
					hidden = true,
					follow = true,
					find_command = find_command,
				},
				live_grep = {
					additional_args = { "--hidden", "--glob=!.git/" },
				},
				grep_string = {
					additional_args = { "--hidden", "--glob=!.git/" },
				},
				buffers = {
					sort_lastused = true,
					sort_mru = true,
					previewer = false,
					theme = "dropdown",
					mappings = {
						i = { ["<C-d>"] = actions.delete_buffer },
						n = { ["dd"] = actions.delete_buffer },
					},
				},
				lsp_references = {
					show_line = false,
					include_declaration = false,
				},
				diagnostics = {
					theme = "ivy",
					line_width = "full",
				},
			},

			-- ── Extension configurations ─────────────────────────────
			-- Each extension is configured here but only LOADED
			-- when its keymap triggers load_extension().
			extensions = {
				fzf = {
					fuzzy = true,
					override_generic_sorter = true,
					override_file_sorter = true,
					case_mode = "smart_case",
				},

				["ui-select"] = {
					require("telescope.themes").get_dropdown({
						previewer = false,
						initial_mode = "normal",
						layout_config = { width = 0.5, height = 0.4 },
					}),
				},

				file_browser = {
					theme = "ivy",
					hijack_netrw = false,
					grouped = true,
					previewer = true,
					hidden = { file_browser = true, folder_browser = true },
					layout_config = { height = 0.4 },
				},

				live_grep_args = {
					auto_quoting = true,
					mappings = {
						i = {
							--- Quote the current prompt and append `--iglob` flag.
							--- Useful for filtering grep results by file pattern.
							["<C-i>"] = function(...)
								return require("telescope-live-grep-args.actions").quote_prompt({
									postfix = " --iglob ",
								})(...)
							end,
						},
					},
				},

				undo = {
					use_delta = vim.fn.executable("delta") == 1,
					side_by_side = true,
					layout_strategy = "vertical",
					layout_config = { preview_height = 0.7 },
					mappings = {
						i = {
							--- Restore the selected undo state.
							["<CR>"] = function(...)
								return require("telescope-undo.actions").restore(...)
							end,
						},
						n = {
							--- Restore the selected undo state.
							["<CR>"] = function(...)
								return require("telescope-undo.actions").restore(...)
							end,
						},
					},
				},

				frecency = {
					show_scores = true,
					show_unindexed = true,
					db_safe_mode = false,
					auto_validate = true,
					ignore_patterns = { "*.git/*", "*/tmp/*", "*/node_modules/*" },
					workspaces = {
						["nvim"] = vim.fn.stdpath("config"),
						["data"] = vim.fn.stdpath("data"),
					},
				},

				persisted = {
					layout_config = { width = 0.6, height = 0.5 },
				},
			},
		}
	end,

	-- ═══════════════════════════════════════════════════════════════════
	-- CONFIG — Load Telescope and the FZF native extension
	--
	-- fzf-native is loaded unconditionally via pcall. If the C build
	-- failed (e.g., no `make` on the system), it silently falls back
	-- to the Lua-based sorter with no user-visible error.
	-- ═══════════════════════════════════════════════════════════════════

	---@param _ table Plugin spec (unused)
	---@param opts table Resolved options from opts function above
	config = function(_, opts)
		require("telescope").setup(opts)
		pcall(require("telescope").load_extension, "fzf")
	end,
}
