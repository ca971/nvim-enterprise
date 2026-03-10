---@file settings.lua
---@description Settings — root-level global configuration for the NvimEnterprise distribution
---@module "nvimenterprise.settings"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings singleton (loads, merges, and exposes this file)
---@see config.settings_manager Settings UI commands (:NvimSettings, :NvimColorscheme…)
---@see config.colorscheme_manager Colorscheme application from ui.colorscheme / ui.colorscheme_style
---@see config.extras_browser Extras browser reads lazyvim_extras from this file
---@see users User module system (per-user overrides merged on top)
---@see users.user_manager User lifecycle management (active_user field)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  settings.lua — Root configuration (single source of truth)              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Merge pipeline (managed by core.settings):                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  1. This file is loaded via dofile() (not require — allows       │    ║
--- ║  │     reload without cache busting)                                │    ║
--- ║  │  2. Active user determined from active_user field                │    ║
--- ║  │  3. User overrides loaded from users/<user>/settings.lua         │    ║
--- ║  │  4. Deep-merge: defaults ← user overrides (user wins)            │    ║
--- ║  │  5. Merged result stored in _G.NvimConfig.settings               │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Settings groups:                                                        ║
--- ║  ├─ version             Semantic version of NvimEnterprise               ║
--- ║  ├─ active_user         Active user profile ("default"|"bly"|"jane"…)    ║
--- ║  ├─ ui                  Visual appearance and interface                  ║
--- ║  │  ├─ colorscheme      Active colorscheme name                          ║
--- ║  │  ├─ colorscheme_style  Theme variant (e.g. "mocha", "night")          ║
--- ║  │  ├─ background       "dark" | "light" (vim.o.background)              ║
--- ║  │  ├─ colorscheme_variant  Secondary axis (e.g. "original", "mix")      ║
--- ║  │  ├─ transparent_background  Remove background colors                  ║
--- ║  │  ├─ float_border     Border style for floating windows                ║
--- ║  │  ├─ float_width/height  Float window size ratios                      ║
--- ║  │  ├─ global_statusline  Single statusline at bottom                    ║
--- ║  │  ├─ winbar           Breadcrumbs at top of each window                ║
--- ║  │  ├─ dashboard_style  "hyper" | "doom" | "mini"                        ║
--- ║  │  ├─ animations       UI animations toggle                             ║
--- ║  │  ├─ gui_font         Font for GUI clients (Neovide, nvim-qt)          ║
--- ║  │  └─ which_key_layout "classic" | "helix" | "modern"                   ║
--- ║  ├─ editor              Editor behavior and defaults                     ║
--- ║  │  ├─ tab_size, use_spaces, wrap, number, relative_number…              ║
--- ║  │  ├─ clipboard, undo_file, swap_file, backup                           ║
--- ║  │  ├─ search_ignore_case, search_smart_case                             ║
--- ║  │  ├─ split_right, split_below                                          ║
--- ║  │  ├─ fold_method, fold_level                                           ║
--- ║  │  ├─ fill_chars, list_chars, session_options                           ║
--- ║  │  └─ encoding, timeout_len, update_time…                               ║
--- ║  ├─ keymaps             Leader and local leader keys                     ║
--- ║  ├─ plugins             Per-plugin enable/disable flags                  ║
--- ║  │  ├─ disabled[]       Explicit disable list (repo names)               ║
--- ║  │  └─ <name>.enabled   Per-plugin toggle (true/false)                   ║
--- ║  ├─ languages           Language module enable list                      ║
--- ║  │  └─ enabled[]        Array of lang module names                       ║
--- ║  ├─ lsp                 Language Server Protocol settings                ║
--- ║  │  ├─ format_on_save, format_timeout                                    ║
--- ║  │  ├─ diagnostic_virtual_text, signs, underline, severity_sort          ║
--- ║  │  ├─ inlay_hints, auto_install                                         ║
--- ║  │  └─ (consumed by plugins.code.lsp and plugins.code.conform)           ║
--- ║  ├─ ai                  AI assistant configuration                       ║
--- ║  │  ├─ enabled          Master switch for all AI features                ║
--- ║  │  ├─ provider         Default AI provider                              ║
--- ║  │  ├─ api_keys         Environment variable names per provider          ║
--- ║  │  ├─ codecompanion    CodeCompanion plugin settings                    ║
--- ║  │  ├─ avante           Avante plugin settings                           ║
--- ║  │  ├─ inline           Ghost-text completion via blink.cmp              ║
--- ║  │  └─ ollama           Local model settings (URL, models)               ║
--- ║  ├─ lazyvim_extras      LazyVim extras enable list                       ║
--- ║  │  ├─ enabled          Master switch                                    ║
--- ║  │  └─ extras[]         Priority-sorted extra IDs                        ║
--- ║  ├─ colorschemes        Installed colorscheme registry                   ║
--- ║  │  └─ <name> = "repo"  Map of scheme name to GitHub repo                ║
--- ║  ├─ performance         Startup and runtime performance tuning           ║
--- ║  │  ├─ lazy_load, cache, ssh_optimization                                ║
--- ║  │  └─ git_protocol     "https" | "ssh" for plugin cloning               ║
--- ║  ├─ neovide             Neovide GUI client settings                      ║
--- ║  ├─ dashboard_ui        Clean dashboard mode (hide bars)                 ║
--- ║  │  ├─ dashboard_filetypes[]  Filetypes treated as dashboards            ║
--- ║  │  ├─ tool_filetypes[]       Sidebar/tool windows to ignore             ║
--- ║  │  └─ float_commands[]       Commands that open overlays from dash      ║
--- ║  └─ directories         Directories to create at startup                 ║
--- ║     ├─ cache[]          Under stdpath("cache")                           ║
--- ║     ├─ data[]           Under stdpath("data")                            ║
--- ║     └─ state[]          Under stdpath("state")                           ║
--- ║                                                                          ║
--- ║  Colorscheme style reference:                                            ║
--- ║  ┌─────────────────────┬────────────────────────────────────────────┐    ║
--- ║  │  Theme              │  colorscheme_style values                  │    ║
--- ║  ├─────────────────────┼────────────────────────────────────────────┤    ║
--- ║  │  catppuccin         │  latte, frappe, macchiato, mocha           │    ║
--- ║  │  tokyonight         │  storm, moon, night, day                   │    ║
--- ║  │  rose-pine          │  main, moon, dawn                          │    ║
--- ║  │  kanagawa           │  wave, dragon, lotus                       │    ║
--- ║  │  gruvbox-material   │  hard, medium, soft (+ background + var.)  │    ║
--- ║  │  everforest         │  hard, medium, soft (+ background)         │    ║
--- ║  │  nightfox           │  nightfox, dayfox, dawnfox, duskfox…       │    ║
--- ║  │  onedark-pro        │  onedark, onelight, vivid, dark            │    ║
--- ║  │  onedark            │  dark, darker, cool, deep, warm, warmer…   │    ║
--- ║  │  sonokai            │  default, atlantis, andromeda, shusia…     │    ║
--- ║  │  dracula            │  dracula, dracula-soft                     │    ║
--- ║  │  monokai-pro        │  classic, octagon, pro, machine…           │    ║
--- ║  │  cyberdream         │  dark, light                               │    ║
--- ║  │  material           │  darker, lighter, oceanic, palenight…      │    ║
--- ║  │  bamboo             │  vulgaris, multiplex, light                │    ║
--- ║  │  fluoromachine      │  fluoromachine, retrowave, delta           │    ║
--- ║  │  vscode             │  dark, light                               │    ║
--- ║  └─────────────────────┴────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Design decisions:                                                       ║
--- ║  ├─ Single file for ALL defaults — no hunting across multiple files      ║
--- ║  ├─ User overrides via deep-merge — only override what you need          ║
--- ║  ├─ dofile() loading (not require) — allows reload without cache bust    ║
--- ║  ├─ @class annotations on each group for lua-language-server support     ║
--- ║  ├─ Commented style reference inline for quick lookup                    ║
--- ║  ├─ plugins.disabled[] + per-plugin .enabled for flexible toggling       ║
--- ║  ├─ languages.enabled[] is an explicit allow-list (start minimal)        ║
--- ║  ├─ AI master switch + per-plugin switches for granular control          ║
--- ║  ├─ colorschemes table maps name → repo (installed vs active decoupled)  ║
--- ║  └─ directories.{cache,data,state} created at bootstrap time             ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

---@class NvimEnterpriseSettings
return {

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                         Active User                                  │
	-- └──────────────────────────────────────────────────────────────────────┘

	--- The active user namespace. Set to "default" for the base configuration.
	--- Each user has their own directory under lua/users/<name>/
	--- with optional settings.lua, keymaps.lua, and plugins/ overrides.
	---@type string Active user profile name (default: "default")
	active_user = "default",

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                         UI Settings                                  │
	-- └──────────────────────────────────────────────────────────────────────┘

	---@class UISettings
	ui = {
		---@type string Active colorscheme name (must match a key in colorschemes table below)
		colorscheme = "tokyonight",

		---@type string Active colorscheme style
		colorscheme_style = "night",

		--- Background mode. Controls vim.o.background for themes that support it.
		--- Most themes auto-detect, but some (gruvbox-material, everforest,
		--- oxocarbon, melange, vscode, gruvbox) use this to switch dark/light.
		---@type "dark"|"light"
		background = "dark",

		--- Secondary style option. Used by themes with a second axis:
		---   gruvbox-material → "material" | "mix" | "original" (foreground palette)
		---   everforest       → (reserved for future use)
		---   material         → (style set via colorscheme_style)
		--- Leave empty ("") to use the theme's default.
		---@type string Active colorscheme variant
		colorscheme_variant = "",

		--- Enable transparent background
		---@type boolean
		transparent_background = false,

		--- Float window border style
		---@type "none"|"single"|"double"|"rounded"|"solid"|"shadow"
		float_border = "rounded",

		--- Width ratio for large floating windows (0.0–1.0)
		---@type number
		float_width = 0.8,

		--- Height ratio for large floating windows (0.0–1.0)
		---@type number
		float_height = 0.8,

		--- Use global statusline (single statusline at bottom)
		---@type boolean
		global_statusline = true,

		--- Enable winbar (breadcrumbs at top of each window)
		---@type boolean
		winbar = false,

		--- Dashboard header style
		---@type "hyper"|"doom"|"mini"
		dashboard_style = "hyper",

		--- Enable UI animations (when supported by plugins)
		---@type boolean
		animations = true,

		--- GUI font (for Neovide, nvim-qt, etc.)
		---@type string
		gui_font = "JetBrainsMono Nerd Font:h14",

		--- Which-Key window layout preset
		--- "classic" = bottom bar, "helix" = helix-style popup, "modern" = floating centered
		---@type "classic"|"helix"|"modern"
		which_key_layout = "modern",
	},

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                       Editor Settings                                │
	-- └──────────────────────────────────────────────────────────────────────┘

	---@class EditorSettings
	editor = {
		---@type integer Number of spaces per tab
		tab_size = 2,
		---@type boolean Expand tabs to spaces
		use_spaces = true,
		---@type boolean Show relative line numbers
		relative_number = true,
		---@type boolean Show absolute line number on cursor line
		number = true,
		---@type boolean Wrap long lines
		wrap = false,
		---@type boolean Wrap search around end of file
		wrap_scan = false,
		---@type boolean Highlight the cursor line
		cursor_line = true,
		---@type integer Lines to keep above/below cursor
		scroll_off = 8,
		---@type integer Columns to keep left/right of cursor
		side_scroll_off = 8,
		---@type "yes"|"no"|"auto"|"number" Sign column display mode
		sign_column = "yes",
		---@type "unnamedplus"|"unnamed"|"" System clipboard integration
		clipboard = "unnamedplus",
		---@type boolean Persistent undo across sessions
		undo_file = true,
		---@type boolean Enable swap files
		swap_file = false,
		---@type boolean Enable backup files
		backup = false,
		---@type boolean Case-insensitive search
		search_ignore_case = true,
		---@type boolean Override ignorecase when pattern has uppercase
		search_smart_case = true,
		---@type boolean Vertical splits open to the right
		split_right = true,
		---@type boolean Horizontal splits open below
		split_below = true,
		---@type string|nil Terminal shell override (nil = system default)
		terminal_shell = nil,
		---@type string Mouse support mode
		mouse = "a",
		---@type integer Popup menu max height
		pumheight = 10,
		---@type boolean Show matching bracket
		show_match = true,
		---@type boolean Auto-write files when leaving buffer
		auto_write = true,
		---@type boolean Confirm before closing modified buffers
		confirm = true,
		---@type "expr"|"indent"|"marker"|"manual" Fold method
		fold_method = "expr",
		---@type integer Default fold level (99 = all open)
		fold_level = 99,

		---@type table<string, string> Fill characters for folds, diff, borders
		fill_chars = {
			fold = " ",
			foldopen = "▽",
			foldclose = "▷",
			foldsep = " ",
			diff = "╱",
			eob = " ",
			msgsep = "‾",
			horiz = "━",
			horizup = "┻",
			horizdown = "┳",
			vert = "┃",
			vertleft = "┫",
			vertright = "┣",
			verthoriz = "╋",
		},

		---@type table<string, string> List mode display characters
		list_chars = {
			eol = "⤶",
			tab = ">.",
			trail = "~",
			extends = "◀",
			precedes = "▶",
		},

		---@type string[] Session save/restore options
		session_options = {
			"buffers",
			"curdir",
			"folds",
			"globals",
			"help",
			"skiprtp",
			"tabpages",
			"winsize",
		},

		---@type boolean Show vertical cursor column
		cursor_column = false,
		---@type integer CursorHold event delay (ms)
		update_time = 200,
		---@type integer Mapped sequence timeout (ms)
		timeout_len = 300,
		---@type string Internal encoding
		encoding = "utf-8",
		---@type string File encoding
		file_encoding = "utf-8",
		---@type boolean Whether Nerd Fonts are installed
		have_nerd_font = true,
		---@type integer Default netrw list style
		netrw_list_style = 3,
		---@type integer Tabline display (0=never, 1=if >1 tab, 2=always)
		show_tab_line = 2,
	},

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                       Keymap Settings                                │
	-- └──────────────────────────────────────────────────────────────────────┘

	---@class KeymapSettings
	keymaps = {
		---@type string Leader key
		leader = " ",
		---@type string Local leader key
		local_leader = "\\",
	},

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                      Plugin Settings                                 │
	-- └──────────────────────────────────────────────────────────────────────┘

	--- Toggle any plugin on/off from this single location.
	--- Each key matches a plugin module name in lua/plugins/.
	--- Set enabled = false to completely disable a plugin.
	--- You can also add the full repo path to the `disabled` list.
	---@class PluginSettings
	plugins = {
		--- Explicit disable list (repo names, e.g. "folke/flash.nvim")
		---@type string[]
		disabled = {},

		-- ── UI ──────────────────────────────────────────────────────
		lualine = { enabled = true },
		bufferline = { enabled = true },
		dashboard = { enabled = true },
		noice = { enabled = true },
		dressing = { enabled = true },
		indent_blankline = { enabled = true },
		mini_icons = { enabled = true },
		nvim_web_devicons = { enabled = true },
		snacks = { enabled = true },
		tiny_inline_diagnostic = { enabled = true },
		no_neck_pain = { enabled = true },
		presenting = { enabled = true },

		-- ── Editor ──────────────────────────────────────────────────
		telescope = { enabled = true },
		oil = { enabled = true },
		harpoon = { enabled = true },
		neo_tree = { enabled = true },
		which_key = { enabled = true },
		gitsigns = { enabled = true },
		flash = { enabled = true },
		mini_pairs = { enabled = true },
		mini_surround = { enabled = true },
		mini_ai = { enabled = true },
		mini_splitjoin = { enabled = true },
		mini_operators = { enabled = true },
		mini_move = { enabled = true },
		mini_trailspace = { enabled = true },
		mini_cursorword = { enabled = true },
		todo_comments = { enabled = true },
		trouble = { enabled = true },
		diffview = { enabled = true },
		markview = { enabled = true },
		grug_far = { enabled = true },

		-- ── Code ────────────────────────────────────────────────────
		cmp = { enabled = true },
		treesitter = { enabled = true },
		conform = { enabled = true },
		nvim_lint = { enabled = true },
		lazydev = { enabled = true },
		dap = { enabled = true },

		-- ── Tools ───────────────────────────────────────────────────
		toggleterm = { enabled = true },
		persistence = { enabled = true },
		project = { enabled = true },
		lazygit = { enabled = true },

		-- ── Misc ────────────────────────────────────────────────────
		wakatime = { enabled = false },
		startuptime = { enabled = false },
	},

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                      Language Settings                               │
	-- └──────────────────────────────────────────────────────────────────────┘

	--- Only enabled languages will have their LSP servers, treesitter
	--- parsers, formatters, linters, and extra plugins installed.
	--- Start minimal — add languages as needed.
	---
	---   Available:
	---   "angular", "ansible", "astro", "c", "clojure", "cmake", "cpp",
	---   "css", "csv", "dart", "docker", "dotnet", "elixir", "elm",
	---   "ember", "erlang", "git", "gleam", "go", "haskell", "helm",
	---   "html", "java", "javascript", "json", "julia", "kotlin", "lean",
	---   "lua", "markdown", "nix", "nushell", "ocaml", "php", "prisma",
	---   "python", "r", "rego", "ruby", "rust", "scala", "solidity",
	---   "sql", "svelte", "tailwind", "terraform", "tex", "thrift",
	---   "toml", "twig", "typescript", "vim", "vue", "xml", "yaml", "zig"
	---@class LanguageSettings
	languages = {
		---@type string[]
		enabled = {
			"angular",
			"ansible",
			"astro",
			"c",
			"clojure",
			"cmake",
			"cpp",
			"css",
			"csv",
			"dart",
			"docker",
			"dotnet",
			"elixir",
			"elm",
			"ember",
			"erlang",
			"git",
			"gleam",
			"go",
			"haskell",
			"helm",
			"html",
			"java",
			"javascript",
			"json",
			"julia",
			"kotlin",
			"lean",
			"lua",
			"markdown",
			"nix",
			"nushell",
			"ocaml",
			"php",
			"prisma",
			"python",
			"r",
			"rego",
			"ruby",
			"rust",
			"scala",
			"solidity",
			"sql",
			"svelte",
			"tailwind",
			"terraform",
			"tex",
			"thrift",
			"toml",
			"twig",
			"typescript",
			"vim",
			"vue",
			"xml",
			"yaml",
			"zig",
		},
	},

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                        LSP Settings                                  │
	-- └──────────────────────────────────────────────────────────────────────┘

	---@class LSPSettings
	lsp = {
		---@type boolean Format buffer on save
		format_on_save = true,
		---@type integer Timeout for formatting (ms)
		format_timeout = 3000,
		---@type boolean Show inline diagnostic text
		diagnostic_virtual_text = true,
		---@type boolean Show signs in sign column
		diagnostic_signs = true,
		---@type boolean Underline diagnostics
		diagnostic_underline = true,
		---@type boolean Enable inlay hints (Neovim ≥ 0.10)
		inlay_hints = true,
		---@type boolean Sort diagnostics by severity
		diagnostic_severity_sort = true,
		---@type boolean Auto-install LSP servers via Mason
		auto_install = true,
	},

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                        AI Settings                                   │
	-- └──────────────────────────────────────────────────────────────────────┘

	--- Each AI plugin can be independently enabled.
	--- Ghost text (inline AI completion) requires:
	---   1. ai.enabled = true
	---   2. ai.inline.enabled = true
	---   3. At least one AI plugin (codecompanion or avante) enabled
	---@class AISettings
	ai = {
		---@type boolean Master switch for all AI features
		enabled = false,

		---@type "claude"|"openai"|"gemini"|"deepseek"|"qwen"|"glm"|"kimi"|"ollama"
		--- Default provider (used as fallback when a plugin doesn't specify one)
		provider = "claude",

		--- API key environment variable names (for reference & validation)
		---@class AIApiKeys
		api_keys = {
			claude = "ANTHROPIC_API_KEY",
			openai = "OPENAI_API_KEY",
			gemini = "GEMINI_API_KEY",
			deepseek = "DEEPSEEK_API_KEY",
			qwen = "DASHSCOPE_API_KEY",
			glm = "GLM_API_KEY",
			kimi = "MOONSHOT_API_KEY",
			-- ollama: no key needed (local)
		},

		--- CodeCompanion settings
		---@class AICodeCompanionSettings
		codecompanion = {
			---@type boolean
			enabled = false,
			---@type "claude"|"openai"|"gemini"|"deepseek"|"qwen"|"glm"|"kimi"|"ollama"
			provider = "claude",
			---@type "claude"|"openai"|"gemini"|"deepseek"|"qwen"|"glm"|"kimi"|"ollama"|nil
			inline_provider = nil,
		},

		--- Avante settings
		---@class AIAvanteSettings
		avante = {
			---@type boolean
			enabled = false,
			---@type "claude"|"openai"|"gemini"|"deepseek"|"qwen"|"glm"|"kimi"|"ollama"
			provider = "claude",
			---@type "claude"|"openai"|"gemini"|"deepseek"|"qwen"|"glm"|"kimi"|"ollama"|nil
			auto_suggestions_provider = nil,
		},

		--- Inline completion (ghost-text via blink.cmp)
		--- Requires ai.enabled = true AND at least one
		--- AI plugin enabled (codecompanion or avante)
		---@class AIInlineSettings
		inline = {
			---@type boolean Enable AI-powered ghost-text in blink.cmp
			enabled = false,
			---@type "codecompanion"|"ollama"
			source = "codecompanion",
		},

		--- Ollama-specific settings (local models)
		---@class AIOllamaSettings
		ollama = {
			---@type string Ollama server URL
			url = "http://localhost:11434",
			---@type string Model for chat/completion
			chat_model = "qwen2.5-coder:7b",
			---@type string Model for inline completion
			completion_model = "qwen2.5-coder:1.5b",
		},
	},

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                     LazyVim Extras                                   │
	-- └──────────────────────────────────────────────────────────────────────┘

	--- Enabled LazyVim extras. Managed by :NvimExtras command via
	--- config.extras_browser. Extras are stored in priority-sorted
	--- order to ensure correct dependency resolution at load time.
	---@class LazyVimExtrasSettings
	--stylua: ignore start
	lazyvim_extras = {
		enabled = true,
		extras = {
			"lazyvim.plugins.extras.ui.edgy",
			"lazyvim.plugins.extras.editor.aerial",
		},
	},
	--stylua: ignore end

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                       Colorschemes                                   │
	-- └──────────────────────────────────────────────────────────────────────┘

	--- All listed colorschemes are installed; only the active one is loaded
	--- eagerly. The rest are available via the theme switcher (:Telescope
	--- colorscheme / Snacks.picker.colorschemes).
	---
	--- Map format: `<name> = "<github_owner>/<repo>"`
	--- The `<name>` key must match what you put in `ui.colorscheme`.
	---@class ColorschemeSettings
	---@field colorschemes table<string, string> Map of colorscheme name → GitHub repo
	--stylua: ignore start
	colorschemes = {
		-- ── Top 1-5: The Giants ──────────────────────────────────────
		["catppuccin"]       = "catppuccin/nvim",
		["tokyonight"]       = "folke/tokyonight.nvim",
		["rose-pine"]        = "rose-pine/neovim",
		["kanagawa"]         = "rebelot/kanagawa.nvim",
		["gruvbox-material"] = "sainnhe/gruvbox-material",

		-- ── Top 6-10: Modern Standards ───────────────────────────────
		["everforest"]       = "sainnhe/everforest",
		["nord"]             = "shaunsingh/nord.nvim",
		["nordic"]           = "AlexvZyl/nordic.nvim",
		["onedark-pro"]      = "olimorris/onedarkpro.nvim",
		["nightfox"]         = "EdenEast/nightfox.nvim",

		-- ── Top 11-15: Aesthetic & Thematic ──────────────────────────
		["solarized-osaka"]  = "craftzdog/solarized-osaka.nvim",
		["onedark"]          = "navarasu/onedark.nvim",
		["dracula"]          = "Mofiqul/dracula.nvim",
		["github-theme"]     = "projekt0n/github-nvim-theme",
		["sonokai"]          = "sainnhe/sonokai",

		-- ── Top 16-20: Emerging & Specialized ────────────────────────
		["monokai-pro"]      = "tanvirtin/monokai.nvim",
		["cyberdream"]       = "scottmckendry/cyberdream.nvim",
		["material"]         = "marko-cerovac/material.nvim",
		["ashen"]            = "ficcdaf/ashen.nvim",
		["evergarden"]       = "comfysage/evergarden",

		-- ── Top 21-30: Rising Stars & Honorable Mentions ─────────────
		["bamboo"]           = "ribru17/bamboo.nvim",
		["oxocarbon"]        = "nyoom-engineering/oxocarbon.nvim",
		["melange"]          = "savq/melange-nvim",
		["fluoromachine"]    = "maxmx03/fluoromachine.nvim",
		["vscode"]           = "Mofiqul/vscode.nvim",
		["night-owl"]        = "oxfist/night-owl.nvim",
		["nightfly"]         = "bluz71/vim-nightfly-colors",
		["zenbones"]         = "mcchrish/zenbones.nvim",
		["yorumi"]           = "yorumicolors/yorumi.nvim",
		["gruvbox"]          = "ellisonleao/gruvbox.nvim",

		-- ── Niche & Minimalist ───────────────────────────────────────
		["shadow"]           = "rjshkhr/shadow.nvim",
	},
	--stylua: ignore end

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                      Performance                                     │
	-- └──────────────────────────────────────────────────────────────────────┘

	---@class PerformanceSettings
	performance = {
		---@type boolean Enable lazy loading of plugins
		lazy_load = true,
		---@type boolean Enable Lua module caching (vim.loader)
		cache = true,
		---@type boolean Reduce visual effects over SSH
		ssh_optimization = true,
		---@type "https"|"ssh" Git protocol for cloning plugins
		--- "https" → https://github.com/author/plugin.git (default, works everywhere)
		--- "ssh"   → git@github.com:author/plugin.git (requires SSH key configured)
		git_protocol = "https",
	},

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                                Neovide                               │
	-- └──────────────────────────────────────────────────────────────────────┘

	--- Neovide-specific enhancements. Applied only when Neovide is detected.
	---@class NeovideSettings
	neovide = {
		input_time = true,
		remember_window_size = true,
		background_color = "#0f1117",
		window_blurred = true,
		floating_shadow = true,
		light_radius = 5,
		padding_left = 20,
		padding_top = 20,
		opacity = 0.8,
		cursor_vfx_mode = "railgun",
		cursor_trail_size = 0.05,
		cursor_antialiasing = true,
		hide_mouse_when_typing = true,
		input_macos_alt_is_meta = false,
		cursor_animation_length = 0.03,
		cursor_vfx_particle_speed = 20.0,
		cursor_vfx_particle_density = 5.0,
	},

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                     Dashboard UI Settings                            │
	-- └──────────────────────────────────────────────────────────────────────┘

	--- Controls the "clean dashboard" behavior:
	--- When the only visible buffer is a dashboard, tabline and statusline
	--- are hidden for an immersive experience.
	---@class DashboardUISettings
	dashboard_ui = {
		--- Enable the clean dashboard mode (hide bars on dashboard)
		---@type boolean
		enabled = true,

		--- Filetypes considered as full-screen "start screen" / dashboard.
		--- When these are the ONLY visible non-floating buffers, the UI bars
		--- (tabline, statusline, cmdline) are hidden.
		--- ONLY true dashboards go here — NOT tool windows.
		---@type string[]
		dashboard_filetypes = {
			"dashboard",
			"alpha",
			"starter",
			"snacks_dashboard",
		},

		--- Filetypes for sidebar/tool/overlay windows that should NOT count
		--- as "real" code buffers when deciding whether to show bars.
		--- If the only visible windows are a dashboard + these tool windows,
		--- the bars remain hidden.
		---@type string[]
		tool_filetypes = {
			"neo-tree",
			"NvimTree",
			"Outline",
			"aerial",
			"undotree",
			"diff",
			"qf",
			"help",
			"man",
			"toggleterm",
			"lazy",
			"mason",
			"TelescopePrompt",
			"TelescopeResults",
			"notify",
			"noice",
			"lspinfo",
			"checkhealth",
			"DressingInput",
			"DressingSelect",
			"snacks_input",
			"snacks_notif",
		},

		--- Commands that open floating/overlay windows from the dashboard.
		--- These will NOT trigger close_dash() — the dashboard stays intact.
		---@type string[]
		float_commands = {
			"Lazy",
			"Mason",
			"LspInfo",
			"NvimInfo",
			"NvimCommands",
			"NvimExtras",
			"NvimLanguages",
			"NvimVersion",
			"NvimPerf",
			"NvimHealth",
			"NvimLogView",
			"NvimLogClear",
			"NvimGitProtocol",
			"NvimGitConvert",
			"Settings",
			"UserSwitch",
		},
	},

	-- ┌──────────────────────────────────────────────────────────────────────┐
	-- │                     Directory Settings                               │
	-- └──────────────────────────────────────────────────────────────────────┘

	--- Directories to ensure exist at startup.
	--- Paths are relative to Neovim's stdpath directories.
	--- Created by core.bootstrap during initialization.
	---@class DirectorySettings
	directories = {
		--- Subdirectories under stdpath("cache")
		---@type string[]
		cache = {
			"sessions",
			"lazy",
			"lazy/cache",
			"backup",
			"swap",
			"undo",
			"shada",
			"tags",
		},
		--- Subdirectories under stdpath("data")
		---@type string[]
		data = {
			"lazy",
			"mason",
			"treesitter",
		},
		--- Subdirectories under stdpath("state")
		---@type string[]
		state = {
			"swap",
			"undo",
			"backup",
			"shada",
		},
	},
}
