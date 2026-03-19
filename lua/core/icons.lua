---@file lua/core/icons.lua
---@description Icons — centralized icon definitions for the entire configuration
---@module "core.icons"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.platform Platform reads icons for OS display and :SystemInfo
---@see core.settings Settings references icons for UI rendering decisions
---@see plugins.ui.lualine Statusline icons (diagnostics, git, mode)
---@see plugins.ui.bufferline Buffer tab icons (file, modified, close)
---@see plugins.code.cmp Completion menu kind icons
---@see plugins.code.lsp LSP diagnostics signs
---@see plugins.code.dap DAP breakpoint and control icons
---@see plugins.editor.neo-tree File explorer icons (tree, folders, git status)
---@see plugins.editor.telescope Telescope prompt and selection icons
---@see plugins.editor.which-key Keymap group icons
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/icons.lua — Single source of truth for all glyphs                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Icons (module table, NOT a class instance)                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Categories (21 tables):                                         │    ║
--- ║  │  ├─ diagnostics    Error, Warn, Hint, Info signs                 │    ║
--- ║  │  ├─ git            Branch, diff, status indicators               │    ║
--- ║  │  ├─ kinds          LSP completion item types (CompletionItemKind)│    ║
--- ║  │  ├─ ui             General UI elements (arrows, buttons, etc.)   │    ║
--- ║  │  ├─ type           Data structure type indicators                │    ║
--- ║  │  ├─ documents      File/folder operation icons                   │    ║
--- ║  │  ├─ file           Filetype-specific icons                       │    ║
--- ║  │  ├─ dev            Development tool and service icons            │    ║
--- ║  │  ├─ tree           Tree/indent guide characters                  │    ║
--- ║  │  ├─ arrows         Directional arrow variants                    │    ║
--- ║  │  ├─ powerline      Powerline separator glyphs                    │    ║
--- ║  │  ├─ separator      Section and statusline separators             │    ║
--- ║  │  ├─ borders        Float/window border character sets            │    ║
--- ║  │  ├─ dap            Debug Adapter Protocol controls               │    ║
--- ║  │  ├─ misc           Miscellaneous / uncategorized icons           │    ║
--- ║  │  ├─ os             Operating system logos                        │    ║
--- ║  │  ├─ app            Application and process icons                 │    ║
--- ║  │  ├─ status         System status indicators                      │    ║
--- ║  │  └─ lang           Programming language icons (per-language)     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ Module table (not OOP) — icons are pure data, no methods     │    ║
--- ║  │  ├─ Flat access: icons.diagnostics.Error, icons.git.Branch       │    ║
--- ║  │  ├─ Every plugin reads from here — never hardcode glyphs         │    ║
--- ║  │  ├─ Nerd Font v3+ required (Symbols Nerd Font Mono fallback)     │    ║
--- ║  │  ├─ Border tables use Neovim's 8-element border format:          │    ║
--- ║  │  │  { topleft, top, topright, right, botright, bot, botleft, l } │    ║
--- ║  │  └─ kinds table mirrors LSP CompletionItemKind enum names        │    ║
--- ║  │     exactly, so plugins can use `icons.kinds[kind]` directly     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Consumers (non-exhaustive):                                     │    ║
--- ║  │  ├─ core/platform.lua      OS icon in :SystemInfo                │    ║
--- ║  │  ├─ core/health.lua        :checkhealth section icons            │    ║
--- ║  │  ├─ plugins/code/cmp.lua   Completion menu kind formatting       │    ║
--- ║  │  ├─ plugins/code/lsp/      Diagnostic signs, code action icons   │    ║
--- ║  │  ├─ plugins/code/dap.lua   Breakpoint signs, DAP UI controls     │    ║
--- ║  │  ├─ plugins/ui/lualine     Statusline component icons            │    ║
--- ║  │  ├─ plugins/ui/bufferline  Tab icons, close button               │    ║
--- ║  │  ├─ plugins/ui/dashboard   Startup screen action icons           │    ║
--- ║  │  ├─ plugins/ui/noice       Notification and cmdline icons        │    ║
--- ║  │  ├─ plugins/editor/*       neo-tree, telescope, trouble, etc.    │    ║
--- ║  │  └─ plugins/editor/persisted  Session management icons           │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Pure data — zero computation, zero function calls                     ║
--- ║  • Loaded once at startup, cached by require() module system             ║
--- ║  • No conditional logic — platform checks belong in consumers            ║
--- ║  • String literals only — no concatenation or formatting at load time    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════
-- MODULE DEFINITION
-- ═══════════════════════════════════════════════════════════════════════

---@class Icons
---@field diagnostics table<string, string> LSP diagnostic severity icons (Error, Warn, Hint, Info)
---@field git table<string, string> Git status and operation icons (Branch, Added, Modified, etc.)
---@field kinds table<string, string> LSP CompletionItemKind icons (mirrors LSP enum names exactly)
---@field ui table<string, string> General UI elements (arrows, buttons, indicators, actions)
---@field type table<string, string> Data structure type icons (Array, Boolean, Object, etc.)
---@field documents table<string, string> File and folder operation icons (find, export, import)
---@field file table<string, string> Filetype-specific icons (json, yaml, markdown, etc.)
---@field dev table<string, string> Development tool and cloud service icons (Docker, K8s, CI/CD)
---@field tree table<string, string> Tree view indent guide characters (vertical, branch, last)
---@field arrows table<string, string> Directional arrow variants (chevrons, bold, small, double)
---@field powerline table<string, string> Powerline-style separator glyphs (hard, thin, round, slant)
---@field separator table<string, string> Section and statusline separators (hard, soft, flame, pixel)
---@field borders table<string, string[]> Float/window border character sets (Neovim 8-element format)
---@field dap table<string, string> Debug Adapter Protocol icons (breakpoints, controls, stepping)
---@field misc table<string, string> Miscellaneous icons (AI, Neovim, Treesitter, etc.)
---@field os table<string, string> Operating system logo icons (Mac, Linux distros, Windows, BSD)
---@field app table<string, string> Application, shell, and package manager icons
---@field status table<string, string> System status indicators (battery, network, volume, etc.)
---@field lang table<string, string> Programming language icons keyed by lowercase language name

local M = {}

-- ═══════════════════════════════════════════════════════════════════════
-- DIAGNOSTICS
--
-- Used by LSP diagnostic signs, lualine diagnostics component,
-- trouble.nvim, and tiny-inline-diagnostic. Names match
-- vim.diagnostic.severity keys for direct mapping.
-- ═══════════════════════════════════════════════════════════════════════

M.diagnostics = {
	Error = "",
	Warn = "",
	Hint = "󰌵",
	Info = "",
}

-- ═══════════════════════════════════════════════════════════════════════
-- GIT
--
-- Used by gitsigns.nvim (signs column), neo-tree (git status),
-- lualine (diff component), neogit, and diffview.
-- ═══════════════════════════════════════════════════════════════════════

M.git = {
	Added = "",
	Branch = "",
	Commit = "",
	Conflict = "",
	Diff = "",
	Git = "󰊢",
	Ignored = "",
	Logo = "󰊢",
	Modified = "",
	Removed = "",
	Renamed = "󰁔",
	Repo = "󰊢",
	Staged = "",
	Unmerged = "󰘬",
	Unstaged = "",
	Untracked = "",
}

-- ═══════════════════════════════════════════════════════════════════════
-- LSP KIND (COMPLETION MENU)
--
-- Keys mirror the LSP CompletionItemKind enum names exactly, allowing
-- plugins to use `icons.kinds[item.kind]` without translation.
-- Used by nvim-cmp, blink-cmp, and any completion UI.
-- AI provider entries (Codeium, Copilot, Supermaven, TabNine) are
-- included for AI-assisted completion sources.
-- ═══════════════════════════════════════════════════════════════════════

M.kinds = {
	Array = "",
	Boolean = "󰨙",
	Class = "󰠱",
	Codeium = "󱜙",
	Color = "󰏘",
	Constant = "󰏿",
	Constructor = "",
	Copilot = " ",
	Enum = "",
	EnumMember = "",
	Event = "",
	Field = "󰜢",
	File = "󰈙",
	Folder = "󰉋",
	Function = "󰊕",
	Interface = "",
	Key = "",
	Keyword = "󰌋",
	Method = "󰆧",
	Module = "",
	Namespace = "",
	Null = "󰟢",
	Number = "",
	Object = "",
	Operator = "󰆕",
	Package = "",
	Property = "󰜢",
	Reference = "󰈇",
	Snippet = "",
	StaticMethod = "",
	String = "",
	Struct = "󰙅",
	Supermaven = "",
	TabNine = "󱜙",
	Text = "󰉿",
	TypeParameter = "󰅲",
	Unit = "󰑭",
	Value = "󰎠",
	Variable = "󰀫",
}

-- ═══════════════════════════════════════════════════════════════════════
-- UI / GENERAL
--
-- Catch-all category for general-purpose UI elements used across
-- multiple plugins: which-key group icons, dashboard actions,
-- notification titles, floating window decorations, etc.
-- ═══════════════════════════════════════════════════════════════════════

M.ui = {
	ArrowRight = "󰅂",
	Art = "󰏘",
	BigCircle = "",
	BigUnfilledCircle = "",
	BoldArrowDown = "",
	BoldArrowLeft = "",
	BoldArrowRight = "",
	BoldArrowUp = "",
	BoldClose = "󰅖",
	BoldDividerLeft = "",
	BoldDividerRight = "",
	BoldLineLeft = "▎",
	BoldLineMiddle = "│",
	BookMark = "󰃀",
	Bug = "",
	Calendar = "󰃭",
	Check = "󰄬",
	ChevronRight = "",
	Circle = "",
	Close = "󰅖",
	Code = "󰅩",
	Comment = "󰅺",
	Config = "",
	Copy = "󰆏",
	Couleur = "󰏁",
	Dashboard = "󰕮",
	DividerLeft = "",
	DividerRight = "",
	Dot = "󰇼",
	Ellipsis = "…",
	EmptyFolderOpen = "",
	File = "󰈔",
	Fire = "󰈸",
	Folder = "󰉋",
	FolderClosed = "",
	FolderEmpty = "",
	FolderOpen = "",
	FolderSymlink = "󱅷",
	Gear = "󰒓",
	History = "󰄉",
	Incoming = "󰏷",
	Indicator = "",
	Keyboard = "",
	Keymap = "󰌌",
	Lightbulb = "󰌵",
	LineLeft = "▏",
	LineMiddle = "│",
	List = "󰗚",
	Lock = "󰌾",
	NewFile = "󰝒",
	Note = "󰎚",
	Package = "󰏗",
	Pencil = "󰏫",
	Perf = "󰅒",
	Play = "",
	Plus = "+",
	Project = "󰉏",
	Project_alt = "󰉋",
	Refresh = "󰑐",
	Robot = "󰚩",
	Rocket = "󰓅",
	Search = "",
	Settings = "",
	SignIn = "󰍔",
	SignOut = "󰍓",
	Sleep = "󰒲",
	Square = "",
	Star = "󰓎",
	Tab = "󰓩",
	Table = "󰓫",
	Target = "󰓾",
	Telescope = "󰭎",
	Terminal = "󰞷",
	Text = "󰉿",
	Tree = "󰙅",
	Triangle = "󰳤",
	User = "󰋑",
	Window = "",
	WordWrap = "󰖈",
	Diff = "󰙇",
	Files = "󰉓",
	Unlock = "󰌾",
}

-- ═══════════════════════════════════════════════════════════════════════
-- DATA STRUCTURE TYPES
--
-- Used for inline type annotations, hover documentation rendering,
-- and data-oriented UI elements (JSON viewers, debugger watches).
-- ═══════════════════════════════════════════════════════════════════════

M.type = {
	Array = "󰅪",
	Boolean = "",
	Enum = "",
	List = "󰅪",
	Null = "󰟢",
	Number = "󰎠",
	Object = "󰅩",
	String = "󰉿",
	Struct = "",
	Table = "",
}

-- ═══════════════════════════════════════════════════════════════════════
-- DOCUMENTS
--
-- File and folder operation icons used by neo-tree, oil.nvim,
-- telescope file browser, and file-related notifications.
-- ═══════════════════════════════════════════════════════════════════════

M.documents = {
	Default = "󰈙",
	Export = "󰮔",
	File = "󰈔",
	FileFind = "󰈞",
	FileTree = "󰙅",
	Files = "󰈚",
	Import = "",
	RootFolderOpened = "",
	Symlink = "",
	SymlinkFolder = "",
	Word = "󰈭",
}

-- ═══════════════════════════════════════════════════════════════════════
-- FILETYPE
--
-- Format-specific icons for known file types. Used in neo-tree,
-- bufferline, lualine filename component, and dashboard recent files.
-- ═══════════════════════════════════════════════════════════════════════

M.file = {
	Default = "󰈔",
	Config = "󰒓",
	Json = "",
	Yaml = "",
	Toml = "",
	Xml = "󰗀",
	Markdown = "",
	Readme = "󰈙",
	License = "󰘥",
	Log = "󰗬",
	Lock = "󰌾",
	Env = "󰆆",
	Sql = "󰆼",
	Csv = "󰒈",
	Image = "󰋩",
	Video = "󰕧",
	Audio = "󰎆",
	Archive = "󰪶",
	Pdf = "󰈦",
	Binary = "󱆃",
}

-- ═══════════════════════════════════════════════════════════════════════
-- DEVELOPMENT TOOLS
--
-- Icons for dev tooling, CI/CD services, cloud providers, and
-- infrastructure. Used in which-key groups, dashboard, and
-- tool-specific plugin configurations.
-- ═══════════════════════════════════════════════════════════════════════

M.dev = {
	Debug = "󰃤",
	Test = "󰙨",
	Benchmark = "󰓅",
	Build = "󰒲",
	Deploy = "󰗵",
	Database = "󰆼",
	Api = "󰡄",
	Server = "󰒋",
	Cloud = "󰅟",
	Container = "󰡨",
	Kubernetes = "󱃾",
	Terraform = "󱁢",
	Ansible = "󱂚",
	Jenkins = "󰐚",
	Github = "󰊤",
	Gitlab = "󰮠",
	Bitbucket = "󰊲",
	Azure = "󰠅",
	Aws = "󰸏",
	Gcp = "󱇳",
}

-- ═══════════════════════════════════════════════════════════════════════
-- TREE
--
-- Indent guide and tree structure characters used by neo-tree,
-- aerial.nvim, and any hierarchical view rendering.
-- ═══════════════════════════════════════════════════════════════════════

M.tree = {
	Indent = "│",
	LastIndent = "└─",
	MiddleIndent = "├─",
	Vertical = "│",
	Explorer = "󰙅",
	Explorer_alt = "󰉓",
}

-- ═══════════════════════════════════════════════════════════════════════
-- ARROWS
--
-- Directional indicators used in menus, completion popups,
-- breadcrumbs, and fold markers.
-- ═══════════════════════════════════════════════════════════════════════

M.arrows = {
	Accepted = "",
	ArrowClosed = "",
	ArrowDown = "",
	ArrowLeft = "❮",
	ArrowOpen = "",
	ArrowRight = "❯",
	ChevronRight = ">",
	ChevronRight_alt = "",
	CurvedArrowRight = " ",
	Diamond = "<>",
	DoubleArrowRight = "»",
	DoubleRightArrow_alt = "󰄾",
	SmallArrowRight = "➜",
	SmallArrowDown = "󰅀",
}

-- ═══════════════════════════════════════════════════════════════════════
-- POWERLINE SEPARATORS
--
-- Powerline-style glyphs for statusline (lualine) and bufferline
-- section separators. Variants: hard (solid), thin (line),
-- round (half-circle), slant (diagonal).
-- ═══════════════════════════════════════════════════════════════════════

M.powerline = {
	Left = "",
	Right = "",
	Thin_left = "",
	Thin_right = "",
	Round_left = "",
	Round_right = "",
	Round_thin_left = "",
	Round_thin_right = "",
	Slant_left = "",
	Slant_right = "",
	Slant_left_thin = "",
	Slant_right_thin = "",
	Block = "█",
	Half_block = "▌",
}

-- ═══════════════════════════════════════════════════════════════════════
-- SEPARATORS
--
-- General-purpose separators for UI composition: statusline sections,
-- winbar breadcrumbs, tab dividers, and decorative elements.
-- Includes novelty variants (flame, pixel) for creative themes.
-- ═══════════════════════════════════════════════════════════════════════

M.separator = {
	Left_hard = "",
	Right_hard = "",
	Left_soft = "",
	Right_soft = "",
	Left_hard_half_circle = "",
	Right_hard_half_circle = "",
	Right_half_circle = "",
	Left_half_circle = "",
	Left_thin = "",
	Right_thin = "",
	Bottom_left = "",
	Bottom_right = "",
	Top_left = "",
	Top_right = "",
	Vertical = "│",
	Horizontal = "─",
	Dot = "󰇙",
	Ellipsis = "…",
	Flame_left = "",
	Flame_right = "",
	Pixel_left = "",
	Pixel_right = "",
	Block = "█",
	Half_block = "▌",
}

-- ═══════════════════════════════════════════════════════════════════════
-- BORDERS
--
-- Window/float border character sets in Neovim's 8-element format:
-- { top-left, top, top-right, right, bottom-right, bottom, bottom-left, left }
-- Used by every floating window: LSP hover, completion docs, Telescope,
-- noice.nvim, lazy.nvim, mason.nvim, dressing.nvim, etc.
-- ═══════════════════════════════════════════════════════════════════════

M.borders = {
	Rounded = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
	Single = { "┌", "─", "┐", "│", "┘", "─", "└", "│" },
	Double = { "╔", "═", "╗", "║", "╝", "═", "╚", "║" },
	Solid = { " ", " ", " ", " ", " ", " ", " ", " " },
}

-- ═══════════════════════════════════════════════════════════════════════
-- DAP (DEBUG ADAPTER PROTOCOL)
--
-- Breakpoint signs, execution controls, and stepping icons.
-- Used by nvim-dap sign definitions and nvim-dap-ui controls.
-- ═══════════════════════════════════════════════════════════════════════

M.dap = {
	Breakpoint = "",
	BreakpointCondition = "󰟃",
	BreakpointRejected = "󰃤",
	LogPoint = "󰰰",
	Stopped = "󰁕",
	Pause = "󰏤",
	Play = "󰐊",
	StepInto = "󰆹",
	StepOver = "󰆸",
	StepOut = "󰆷",
	StepBack = "󰆼",
	RunLast = "󰑐",
	Terminate = "󰓛",
	Disconnect = "󰈂",
}

-- ═══════════════════════════════════════════════════════════════════════
-- MISCELLANEOUS
--
-- Icons that don't fit neatly into other categories or are used
-- for branding and identity (Neovim, Vim, AI, plugin managers).
-- ═══════════════════════════════════════════════════════════════════════

M.misc = {
	AI = "󰧑",
	Bell = "󰂚",
	Code = "",
	Copilot = " ",
	Ghost = "󰊠",
	Lazy = "󰒲",
	Linux = "󰌽",
	Lock = "󰌾",
	Lsp = "󰄭",
	Apple = "󰀵",
	ManUp = "",
	Mason = "󰇥",
	Neovim = "",
	Robot = "󰚩",
	RunningMan = "🏃",
	Telescope = "",
	Treesitter = "󰔱",
	Vim = "",
	Windows = "󰖳",
	Xmark = "✗",
	Yoga = "🧘",
	Laptop = "💻",
}

-- ═══════════════════════════════════════════════════════════════════════
-- OPERATING SYSTEMS
--
-- OS logos used by core/platform.lua for :SystemInfo display,
-- lualine OS indicator, and dashboard branding.
-- Includes major Linux distributions for distro-specific theming.
-- ═══════════════════════════════════════════════════════════════════════

M.os = {
	Mac = "",
	Linux = "",
	Linux_alt = "🐧",
	Windows = "",
	Freebsd = "",
	Freebsd_alt = "😈",
	Ubuntu = "",
	Debian = "",
	Fedora = "",
	Arch = "",
	Centos = "",
	Alpine = "",
	Nixos = "",
	Raspberry_pi = "",
	Android = "",
}

-- ═══════════════════════════════════════════════════════════════════════
-- APPLICATIONS & PROCESSES
--
-- Icons for shells, package managers, languages (as applications),
-- databases, and system tools. Used in toggleterm tab names,
-- which-key groups, and tool-specific UI integrations.
-- Distinguished from `lang` table: `app` = tool icons for UI,
-- `lang` = language icons for file/buffer identification.
-- ═══════════════════════════════════════════════════════════════════════

M.app = {
	Bash = "",
	Bear = "󰄛",
	Brew = "🍺",
	Btop = "",
	Bun = "󰛦",
	Busted = "󰙨",
	Cargo = "󱘗",
	Clj = "",
	Cmake = "",
	Composer = "",
	Cpp = "",
	Cppcheck = "󰒕",
	Csharp = "",
	Csso = "󰌜",
	Curl = "󰇚",
	Dart = "",
	Deno = "",
	Dialyer = "󰈞",
	Djlint = "󰧮",
	Docker = "󰡨",
	Docker_alt = "🐳",
	Dot = "󱁉",
	Dotnet = "󰪮",
	Dune = "󱆢",
	Elixir = "",
	Elm = "",
	Ember = "",
	Erl = "",
	Erlc = "",
	Erlfmt = "󰉖",
	Eslint = "󰱺",
	Eslint_d = "󱓡",
	Fish = "󰈺",
	Flutter = "",
	Forge = "󱡠",
	Gcc = "",
	Git = "",
	Gleam = "󱗠",
	Go = "",
	Gpp = "",
	Grip = "󰒔",
	Haskell = "",
	Helm = "⎈",
	Htop = "",
	Ipython = "",
	Java = "",
	Javascript = "",
	Jshell = "",
	Julia = "",
	Kotlin = "",
	Kotlinc = "",
	Lake = "󰌠",
	Lazygit = "",
	Lean = "󰌠",
	Lua = "",
	Luajit = "",
	Make = "",
	Man = "󰈚",
	Mongo = "",
	Mypy = "󰈞",
	Mysql = "",
	Neovim = "",
	Ng = "",
	Nix = "",
	Node = "󰎙",
	Npm = "",
	Npx = "󰎙",
	Nu = "󰘳",
	Nvim = "",
	Ocaml = "",
	Ocamlformat = "󰉖",
	Opa = "󰱺",
	Opam = "󰏖",
	Pandoc = "󰏫",
	Php = "󰌟",
	Pip = "",
	Pnpm = "",
	Podman = "󰡨",
	Postgres = "",
	Prettier = "󰉖",
	Prisma = "",
	Pry = "󰘧",
	Psysh = "󰘧",
	Python = "",
	Python_alt = "🐍",
	Rebar3 = "󰒕",
	Redis = "",
	Regols = "󰡪",
	Repl = "󰐤",
	Ri = "󰈙",
	Rspec = "󰙨",
	Ruby = "",
	Ruff = "󱚣",
	Rust = "",
	Rust_alt = "🦀",
	Rustywind = "󱏿",
	Sail = "󱗬",
	Scala = "",
	Solhint = "󰈞",
	Sqlfluff = "󰆚",
	Sqlite3 = "",
	Ssh = "󰣀",
	Ssh_alt = "🔒",
	Su = "",
	Sudo = "󰌆",
	Swift = "",
	Taplo = "󰅒",
	Terraform = "󱁢",
	Tflint = "󰓼",
	Thrift = "󱐤",
	Tmux = "",
	Tool = "󰓼",
	Top = "",
	Ts_node = "󰛦",
	Tsx = "",
	Twigcs = "󰛦",
	Typescript = "",
	Utop = "󰘧",
	Valgrind = "󰙨",
	Vim = "",
	Wget = "󰇚",
	Xmllint = "󰗀",
	Xq = "󰗀",
	Yamllint = "󰅪",
	Yarn = "",
	Yq = "󰅪",
	Zig = "",
	Zsh = "",
	["C++"] = "",
	["Clang-tidy"] = "󰒕",
	["Clj-kondo"] = "󰱯",
	["Elm-review"] = "󰈞",
	["Elm-test"] = "󰙨",
	["G++"] = "",
	["Html-minifier"] = "󰛨",
	["Live-server"] = "󱂇",
	["Nomicfoundation-solidity-ls"] = "󰡪",
	["Scala-cli"] = "󰭟",
	["Source-map-explorer"] = "󰆼",
}

-- ═══════════════════════════════════════════════════════════════════════
-- STATUS INDICATORS
--
-- System status icons for potential statusline integrations,
-- dashboard widgets, or remote development indicators.
-- ═══════════════════════════════════════════════════════════════════════

M.status = {
	Connected = "󰄄",
	Disconnected = "󰂭",
	Battery_full = "󰁹",
	Battery_high = "󰂁",
	Battery_medium = "󰁾",
	Battery_low = "󰂃",
	Battery_critical = "󰂎",
	Battery_charging = "󰂄",
	Cpu = "󰍛",
	Memory = "󰘚",
	Disk = "󰋊",
	Network = "󰀂",
	Network_off = "󰖪",
	Wifi = "󰖩",
	Wifi_off = "󰖪",
	Bluetooth = "󰂯",
	Volume_high = "󰕾",
	Volume_low = "󰕿",
	Volume_mute = "󰝟",
	Microphone = "󰍬",
	Microphone_off = "󰍭",
	Camera = "󰄀",
	Camera_off = "󰄁",
	Clock = "󰥔",
	Calendar = "󰃭",
	Power = "󰐥",
	Sleep = "󰒲",
	Remote = "🌐",
	Onfire = "🔥",
}

-- ═══════════════════════════════════════════════════════════════════════
-- PROGRAMMING LANGUAGES
--
-- Per-language icons keyed by lowercase language name. Used by
-- langs/*.lua modules for which-key group icons, lualine filetype
-- display, and treesitter language indicators.
-- Keys match the filenames in lua/langs/ for direct lookup:
--   icons.lang[vim.bo.filetype] or icons.lang["python"]
-- ═══════════════════════════════════════════════════════════════════════

M.lang = {
	angular = "",
	ansible = "󱂚",
	astro = "",
	bash = "",
	c = "",
	clojure = "",
	cmake = "",
	cpp = "",
	csharp = "",
	css = "",
	csv = "",
	dart = "",
	docker = "",
	elixir = "",
	elm = "",
	ember = "",
	erlang = "",
	fish = "󰈺",
	git = "",
	gleam = "󰲵",
	go = "",
	graphql = "",
	handlebars = "󰛖",
	haskell = "",
	helm = "⎈",
	html = "",
	java = "",
	javascript = "",
	json = "",
	julia = "",
	kotlin = "",
	lean = "󰮣",
	less = "",
	lua = "",
	markdown = "",
	nix = "",
	nushell = "",
	ocaml = "",
	perl = "",
	php = "󰌟",
	powershell = "",
	prisma = "",
	python = "",
	r = "",
	rego = "",
	rego_official = " ",
	ruby = "",
	rust = "",
	sass = "",
	scala = "",
	sh = " ",
	solidity = "",
	sql = "",
	stylus = "",
	svelte = "",
	swift = "",
	systemverilog = "",
	tailwind = "󱏿",
	terraform = "",
	tex = "",
	thrift = "",
	thrift_official = " ",
	toml = "",
	twig = "",
	typescript = "",
	verilog = "",
	vim = "",
	vue = "",
	xml = "󰗀",
	yaml = "",
	zig = "",
	zsh = "󱆃",
}

return M
