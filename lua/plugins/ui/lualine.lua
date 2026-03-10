---@file lua/plugins/ui/lualine.lua
---@description Lualine — Enterprise statusline with contextual language runtime display
---@module "plugins.ui.lualine"
---@author ca971
---@license MIT
---@version 1.0.1
---@since 2026-01
---
---@see core.settings              Plugin guard, AI provider, global_statusline preference
---@see core.platform              OS detection, SSH/Docker/WSL/Tmux/GUI flags, runtime registry
---@see core.icons                 Unified icon registry (powerline, git, diagnostics, ui, misc, app)
---@see config.colorscheme_manager Theme changes affect lualine via `theme = "auto"`
---@see plugins.ui.bufferline      Tabline counterpart (top bar)
---@see plugins.editor.gitsigns    Git diff source for branch/diff components
---@see plugins.lsp                LSP client names displayed in section X
---@see plugins.ui.noice           Noice command/mode display in section C
---@see plugins.editor.navic       Winbar breadcrumb navigation
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ui/lualine.lua — Power-user statusline                          ║
--- ║                                                                          ║
--- ║  Section Layout:                                                         ║
--- ║  ╭─A──╮ ◗──B──◖ ───C─────────────── │─X─│─X─│ ◗──Y──◖ ╭──Z──╮            ║
--- ║  │MODE│  GIT    FILE+DIAG+NOICE       STATUS     META    DATE            ║
--- ║                                                                          ║
--- ║  Design Rules:                                                           ║
--- ║  • Section B: ALWAYS visible (branch or project dir) → clean A→B→C       ║
--- ║  • Section X: user_component ALWAYS LAST → clean X→Y transition          ║
--- ║  • lang_runtime: reads executables from core.platform (single source)    ║
--- ║  • Every custom component wrapped in safe() (pcall)                      ║
--- ║  • Every condition wrapped in safe_cond() (pcall)                        ║
--- ║  • Expensive data cached per-session (versions, env, hostname)           ║
--- ║                                                                          ║
--- ║  Runtime Architecture:                                                   ║
--- ║  ┌─────────────────────┐     ┌────────────────────────────────┐          ║
--- ║  │  core/platform.lua  │────▶│  plugins/ui/lualine.lua        │          ║
--- ║  │  RUNTIME_EXECUTABLES│     │  FT_TO_RUNTIME + VERSION_ARGS  │          ║
--- ║  │  platform.runtimes  │     │  lang_runtime() component      │          ║
--- ║  │  :get_runtime_exe() │     │  Cached per-language/session   │          ║
--- ║  └─────────────────────┘     └────────────────────────────────┘          ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════
-- GUARD & DEPENDENCIES
-- ═══════════════════════════════════════════════════════════════

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok and not settings:is_plugin_enabled("lualine") then return {} end

local augroup = require("core.utils").augroup
local platform_ok, platform = pcall(require, "core.platform")
local icons_ok, icons = pcall(require, "core.icons")

--- Fallback icon tables when core.icons is unavailable (minimal startup).
--- Guarantees lualine never crashes on missing icons regardless of load order.
---@type table<string, table<string, string>>
if not icons_ok or not icons then
	icons = {
		powerline = {
			Left = "",
			Right = "",
			Thin_left = "",
			Thin_right = "",
			Round_left = "",
			Round_right = "",
			Round_thin_left = "",
			Round_thin_right = "",
		},
		git = { Branch = "", Added = "+", Modified = "~", Removed = "-" },
		diagnostics = { Error = "E", Warn = "W", Info = "I", Hint = "H" },
		ui = { User = "U", Pencil = "●", Lock = "RO", NewFile = "N" },
		misc = { AI = "AI" },
		app = {},
	}
end

-- ═══════════════════════════════════════════════════════════════
-- LOCAL REFERENCES
--
-- Module-level locals for frequently accessed globals.
-- Avoids repeated table lookups on every statusline refresh.
-- ═══════════════════════════════════════════════════════════════

---@type fun(formatstring: string, ...: any): string
local fmt = string.format

--- Cached icon category references for repeated use.
---@type table<string, string>
local pw = icons.powerline or {}
---@type table<string, string>
local gi = icons.git or {}
---@type table<string, string>
local dg = icons.diagnostics or {}
---@type table<string, string>
local ui = icons.ui or {}
---@type table<string, string>
local mi = icons.misc or {}
---@type table<string, string>
local app = icons.app or {}

-- ═══════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════

--- Safely access an icon from a table with fallback.
---
--- Provides nil-safe icon access: if the table is nil, the key is missing,
--- or the value is nil, returns the fallback string instead of erroring.
---
--- ```lua
--- ic(icons.git, "Branch", "")       -- → "" or fallback ""
--- ic(nil, "anything", "?")           -- → "?"
--- ```
---
---@param tbl table|nil Icon category table (e.g. `icons.git`)
---@param key string Icon key name (e.g. `"Branch"`)
---@param fallback? string Fallback string if key is missing (default: `""`)
---@return string icon The resolved icon or fallback
---@nodiscard
local function ic(tbl, key, fallback)
	if type(tbl) == "table" and tbl[key] ~= nil then return tbl[key] end
	return fallback or ""
end

--- Wrap a component function in pcall for error resilience.
---
--- Returns a new function that calls `fn` inside pcall and returns
--- the result if successful, or `fallback` if it throws. Every lualine
--- component should go through this wrapper to prevent a single broken
--- component from hiding the entire statusline.
---
--- ```lua
--- local my_comp = safe(function() return "hello" end)
--- my_comp()  -- → "hello"
---
--- local broken = safe(function() error("boom") end, "fallback")
--- broken()   -- → "fallback"
--- ```
---
---@param fn fun(): string Component function returning a display string
---@param fallback? string Fallback string on error (default: `""`)
---@return fun(): string wrapped Safe component function that never throws
---@nodiscard
local function safe(fn, fallback)
	return function()
		local ok, result = pcall(fn)
		if ok and type(result) == "string" then return result end
		return fallback or ""
	end
end

--- Wrap a condition function in pcall for error resilience.
---
--- Returns a new function that calls `fn` inside pcall and returns
--- `true` only if `fn` succeeds and returns `true`. Any error or
--- non-boolean return value results in `false` (component hidden).
---
--- ```lua
--- local cond = safe_cond(function() return true end)
--- cond()  -- → true
---
--- local broken = safe_cond(function() error("boom") end)
--- broken()  -- → false (component hidden, no crash)
--- ```
---
---@param fn fun(): boolean Condition function returning visibility flag
---@return fun(): boolean wrapped Safe condition function that never throws
---@nodiscard
local function safe_cond(fn)
	return function()
		local ok, result = pcall(fn)
		return ok and result == true
	end
end

--- Safely read a setting value from core.settings with fallback.
---
--- Wraps `settings:get()` in pcall to handle cases where core.settings
--- failed to load or the key doesn't exist. Returns `default` on any error.
---
--- ```lua
--- setting("ui.global_statusline", true)   -- → true (or saved value)
--- setting("nonexistent.key", 42)          -- → 42
--- ```
---
---@param key string Settings key path (e.g. `"ui.global_statusline"`)
---@param default any Fallback value if setting is unavailable
---@return any value The setting value or default
---@nodiscard
local function setting(key, default)
	if not settings_ok then return default end
	local ok, val = pcall(settings.get, settings, key, default)
	return ok and val or default
end

--- Extract foreground hex color from a highlight group.
---
--- Uses `nvim_get_hl()` with `link = false` to resolve through linked groups.
--- Returns nil if the group doesn't exist or has no fg color set.
---
--- ```lua
--- hl_fg("Function")      -- → "#89b4fa" (Catppuccin blue)
--- hl_fg("NonExistent")   -- → nil
--- ```
---
---@param name string Highlight group name (e.g. `"Function"`, `"@keyword"`)
---@return string|nil hex Hex color string (e.g. `"#89b4fa"`) or nil
---@nodiscard
local function hl_fg(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok and hl.fg then return fmt("#%06x", hl.fg) end
end

--- Extract background hex color from a highlight group.
---
--- Uses `nvim_get_hl()` with `link = false` to resolve through linked groups.
--- Returns nil if the group doesn't exist or has no bg color set.
---
--- ```lua
--- hl_bg("Normal")        -- → "#1e1e2e" (Catppuccin base)
--- hl_bg("NonExistent")   -- → nil
--- ```
---
---@param name string Highlight group name (e.g. `"Normal"`, `"StatusLine"`)
---@return string|nil hex Hex color string (e.g. `"#1e1e2e"`) or nil
---@nodiscard
local function hl_bg(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok and hl.bg then return fmt("#%06x", hl.bg) end
end

--- Get the OS icon from core.platform singleton.
---
--- Returns the platform-specific Nerd Font icon (e.g. 🐧 for Linux,
---  for macOS). Falls back to empty string if platform module is
--- unavailable or the method throws.
---
---@return string os_icon Platform Nerd Font icon or `""`
---@nodiscard
local function get_os_icon()
	if platform_ok and platform and platform.get_os_icon then
		local ok, r = pcall(platform.get_os_icon, platform)
		if ok and r then return r end
	end
	return ""
end

-- ═══════════════════════════════════════════════════════════════
-- SEPARATORS & LAYOUT CONSTANTS
--
-- Pre-resolved separator characters and reusable layout shorthands.
-- Used throughout the lualine configuration to ensure consistent
-- visual language and reduce table allocation per-component.
-- ═══════════════════════════════════════════════════════════════

--- Pre-resolved powerline separator characters from icons.powerline.
---@class LualineSeparators
---@field round_l string Round left separator `""`
---@field round_r string Round right separator `""`
---@field thin_r string Thin right divider `"│"`
---@field round_thin_l string Round thin left `""`
---@field round_thin_r string Round thin right `""`
local sep = {
	round_l = ic(pw, "Round_left", ""),
	round_r = ic(pw, "Round_right", ""),
	thin_r = ic(pw, "Thin_right", "│"),
	round_thin_l = ic(pw, "Round_thin_left", ""),
	round_thin_r = ic(pw, "Round_thin_right", ""),
}

--- Empty separator — disables separator between components.
---@type string
local SEP_NONE = ""

--- Thin vertical divider separator table for lualine components.
---@type table<string, string>
local SEP_THIN = { right = sep.thin_r }

--- Round powerline separator table for section transitions.
---@type table<string, string>
local SEP_ROUND = { right = sep.round_r }

--- Standard padding: 1 space on both sides.
---@type table<string, integer>
local PAD_STD = { left = 1, right = 1 }

--- Left-only padding: 1 space left, 0 right (compact layout).
---@type table<string, integer>
local PAD_L = { left = 1, right = 0 }

-- ═══════════════════════════════════════════════════════════════
-- COMPONENT FACTORY
--
-- Reduces boilerplate for custom function components.
-- Every function goes through safe(), every condition through safe_cond().
-- ═══════════════════════════════════════════════════════════════

---@class CompOpts
---@field color? table Lualine color table (e.g. `{ fg = "#89b4fa" }`)
---@field cond? fun(): boolean Condition function for component visibility
---@field sep? string|table Separator override (default: `SEP_NONE`)
---@field pad? table Padding override (e.g. `{ left = 1, right = 0 }`)
---
--- Create a lualine component table from a function and options.
---
--- Wraps the function in `safe()` and the condition in `safe_cond()`
--- automatically, reducing boilerplate from 6 lines to 1 per component.
---
--- ```lua
--- -- Without factory (verbose):
--- { safe(my_func), color = C.lsp, cond = safe_cond(cond.has_lsp), separator = "", padding = nil }
---
--- -- With factory (compact):
--- comp(my_func, { color = C.lsp, cond = cond.has_lsp })
--- ```
---@param fn fun(): string Component function returning a display string
---@param opts? CompOpts Component options
---@return table component Lualine-compatible component definition table
---@nodiscard
local function comp(fn, opts)
	opts = opts or {}
	return {
		safe(fn),
		color = opts.color,
		cond = opts.cond and safe_cond(opts.cond) or nil,
		separator = opts.sep ~= nil and opts.sep or SEP_NONE,
		padding = opts.pad,
	}
end

-- ═══════════════════════════════════════════════════════════════
-- CACHE
--
-- Performance cache for expensive operations. Prevents repeated
-- system calls, hostname lookups, and version checks on every
-- statusline refresh (every 1000ms).
--
-- Cache lifetime:
--   • env_string:       session lifetime (environment doesn't change)
--   • runtime_versions: session lifetime per-language (checked once)
--   • hostname:         session lifetime (resolved once)
--   • lazy_updates:     TTL-based (refreshed every LAZY_TTL seconds)
-- ═══════════════════════════════════════════════════════════════

---@class LualineCache
---@field env_string string|nil        Cached environment indicator string
---@field env_built boolean            Whether env_string has been computed
---@field lazy_updates number|nil      Cached count of available lazy.nvim updates
---@field lazy_checked number          Timestamp (seconds) of last lazy update check
---@field hostname string|nil          Cached hostname (first segment before dot)
---@field runtime_versions table<string, string|nil> Cached version strings per runtime key
---@field runtime_checked table<string, boolean>     Whether each runtime has been probed
local cache = {
	env_string = nil,
	env_built = false,
	lazy_updates = nil,
	lazy_checked = 0,
	hostname = nil,
	runtime_versions = {},
	runtime_checked = {},
}

--- Time-to-live for lazy.nvim update cache (in seconds).
--- After this interval, the next statusline refresh will re-check.
---@type integer
local LAZY_TTL = 300

-- ═══════════════════════════════════════════════════════════════
-- LOOKUP TABLES
--
-- Pre-built lookup tables for O(1) filetype checks.
-- Used by conditions and components to avoid string comparisons.
-- ═══════════════════════════════════════════════════════════════

--- Filetypes considered "prose" for word count display.
---@type table<string, boolean>
local PROSE_FILETYPES = {
	markdown = true,
	text = true,
	tex = true,
	latex = true,
	norg = true,
	org = true,
	rst = true,
	typst = true,
}

--- LSP client names to exclude from the LSP component display.
--- These are shown in dedicated components (AI, copilot) instead.
---@type table<string, boolean>
local LSP_IGNORED = { copilot = true, ["null-ls"] = true, ["none-ls"] = true }

-- ═══════════════════════════════════════════════════════════════
-- LANGUAGE RUNTIME — CONTEXTUAL VERSION DISPLAY
--
-- Shows the icon + version of the runtime matching the current
-- buffer's filetype. Uses core.platform as the single source of
-- truth for executable names and availability.
--
-- Architecture:
--   FT_TO_RUNTIME : Neovim filetype → runtime key
--   VERSION_ARGS  : runtime key → { args, pattern } for version extraction
--   Executable    : resolved via platform:get_runtime_executable(key)
--   Availability  : read from platform.runtimes[key] (cached at startup)
--   Icon          : icons.app[Capitalized_key] (single source of truth)
--
-- Adding a new language:
--   1. Ensure runtime exists in platform.lua RUNTIME_EXECUTABLES
--   2. Add filetype → runtime mapping in FT_TO_RUNTIME
--   3. Add version extraction rule in VERSION_ARGS
-- ═══════════════════════════════════════════════════════════════

--- Mapping from Neovim filetype to platform runtime key.
---
--- Keys are `vim.bo.filetype` values. Values are runtime keys matching
--- the `RUNTIME_EXECUTABLES` registry in `core/platform.lua`.
--- Multiple filetypes can map to the same runtime (e.g. JS/TS → `"node"`).
---
--- ```lua
--- FT_TO_RUNTIME["lua"]        -- → "lua"    (uses luajit or lua)
--- FT_TO_RUNTIME["typescript"] -- → "node"   (uses node)
--- FT_TO_RUNTIME["csv"]        -- → nil      (no runtime → component hidden)
--- ```
---
---@type table<string, string>
local FT_TO_RUNTIME = {
	lua = "lua",
	python = "python",
	javascript = "node",
	typescript = "node",
	typescriptreact = "node",
	javascriptreact = "node",
	vue = "node",
	svelte = "node",
	ruby = "ruby",
	go = "go",
	rust = "rust",
	c = "gcc",
	cpp = "gpp",
	php = "php",
	java = "java",
	zig = "zig",
	dart = "dart",
	scala = "scala",
	julia = "julia",
	haskell = "haskell",
	ocaml = "ocaml",
	nix = "nix",
}

--- Version extraction rules per runtime key.
---
--- Each entry defines the CLI arguments to pass to the executable
--- and a Lua pattern to capture the version string from stdout.
--- Keys MUST match `RUNTIME_EXECUTABLES` keys in `core/platform.lua`.
---
--- ```lua
--- VERSION_ARGS["lua"]    -- { args = "-v", pattern = "[Ll]ua[JITjit]*%s+(%S+)" }
--- -- Running: luajit -v 2>&1  →  "LuaJIT 2.1.0-beta3 -- ..."
--- -- Match:  "2.1.0-beta3"
--- ```
---
---@type table<string, { args: string, pattern: string }>
local VERSION_ARGS = {
	lua = { args = "-v", pattern = "[Ll]ua[JITjit]*%s+(%S+)" },
	python = { args = "--version", pattern = "Python%s+(%S+)" },
	node = { args = "-v", pattern = "(v%S+)" },
	ruby = { args = "-v", pattern = "ruby%s+(%S+)" },
	go = { args = "version", pattern = "go(%d[%d%.]+)" },
	rust = { args = "--version", pattern = "rustc%s+(%S+)" },
	gcc = { args = "--version", pattern = "(%d+%.%d+[%.%d]*)" },
	gpp = { args = "--version", pattern = "(%d+%.%d+[%.%d]*)" },
	php = { args = "-v", pattern = "PHP%s+(%S+)" },
	java = { args = "--version", pattern = "(%d+[%.%d]*)" },
	zig = { args = "version", pattern = "(%S+)" },
	dart = { args = "--version", pattern = "Dart%s+SDK%s+version:%s+(%S+)" },
	scala = { args = "-version", pattern = "(%d+[%.%d]*)" },
	julia = { args = "--version", pattern = "(%d+[%.%d]*)" },
	haskell = { args = "--version", pattern = "(%d+[%.%d]*)" },
	ocaml = { args = "--version", pattern = "(%S+)" },
	nix = { args = "--version", pattern = "nix.-(%d+[%.%d]*)" },
}

--- Resolve a Nerd Font icon for a runtime key from `icons.app`.
---
--- Capitalizes the first letter of the runtime key to match the
--- `icons.app` naming convention (e.g. `"lua"` → `icons.app.Lua`).
--- Returns `"•"` as fallback if the icon is not found.
---
--- ```lua
--- runtime_icon("lua")    -- → "" (from icons.app.Lua)
--- runtime_icon("python") -- → "󰌠" (from icons.app.Python)
--- runtime_icon("unknown") -- → "•"
--- ```
---
---@param rt_key string Runtime key (e.g. `"lua"`, `"python"`, `"node"`)
---@return string icon Nerd Font icon or `"•"` fallback
---@nodiscard
local function runtime_icon(rt_key)
	local cap = rt_key:gsub("^%l", string.upper)
	return ic(app, cap, "•")
end

--- Show icon + version of the runtime matching the current filetype.
---
--- Detection flow:
--- 1. Map `vim.bo.filetype` → runtime key via `FT_TO_RUNTIME`
--- 2. Check `platform.runtimes[key]` for availability (startup cache)
--- 3. On first call per runtime: resolve executable via
---    `platform:get_runtime_executable()`, run it with `VERSION_ARGS`,
---    parse version with Lua pattern, cache result
--- 4. On subsequent calls: return cached version immediately
---
--- Returns empty string for unknown filetypes, unavailable runtimes,
--- or failed version detection. Never throws.
---
--- ```lua
--- -- With filetype = "lua" and luajit installed:
--- lang_runtime()  -- → " 2.1.0-beta3"
---
--- -- With filetype = "csv" (no runtime mapping):
--- lang_runtime()  -- → ""
--- ```
---
---@return string component Formatted `"icon version"` or `""` if not applicable
---@nodiscard
local function lang_runtime()
	local rt_key = FT_TO_RUNTIME[vim.bo.filetype]
	if not rt_key then return "" end

	-- Availability from platform (already detected at startup)
	if not platform_ok or not platform or not platform.runtimes or not platform.runtimes[rt_key] then return "" end

	-- Return cached version
	if cache.runtime_checked[rt_key] then
		local ver = cache.runtime_versions[rt_key]
		if not ver then return "" end
		return runtime_icon(rt_key) .. " " .. ver
	end

	-- First detection for this runtime
	cache.runtime_checked[rt_key] = true

	local vargs = VERSION_ARGS[rt_key]
	if not vargs then return "" end

	-- Get executable from platform registry (single source of truth)
	local exe = platform:get_runtime_executable(rt_key)
	if not exe then return "" end

	local output = vim.fn.system(exe .. " " .. vargs.args .. " 2>&1")
	local ver = output:match(vargs.pattern)
	if ver then
		cache.runtime_versions[rt_key] = ver
		return runtime_icon(rt_key) .. " " .. ver
	end

	return ""
end

-- ═══════════════════════════════════════════════════════════════
-- COMPONENTS — Git (Section B)
--
-- Section B is designed to NEVER be empty. When no git branch is
-- available, it falls back to the project directory name. This
-- prevents separator glitches between sections A and C.
-- ═══════════════════════════════════════════════════════════════

--- Show git branch name or project directory as fallback.
---
--- Reads `vim.b.gitsigns_head` (set by gitsigns.nvim) for the current
--- branch. If unavailable (not a git repo), falls back to showing the
--- current working directory basename with a 📂 prefix.
---
--- Branch names longer than 20 characters are truncated with `"…"`.
---
--- This function **always returns content**, ensuring section B is never
--- empty and the A→B→C powerline transition remains clean.
---
--- ```lua
--- -- In a git repo:
--- branch_or_cwd()  -- → " main"
--- branch_or_cwd()  -- → " feature/very-lon…"
---
--- -- Outside a git repo:
--- branch_or_cwd()  -- → "📂 my-project"
--- ```
---
---@return string component Branch name with icon, or project dir with 📂
---@nodiscard
local function branch_or_cwd()
	local branch = vim.b.gitsigns_head
	if branch and branch ~= "" then
		local bi = ic(gi, "Branch", "")
		return bi .. " " .. (#branch > 20 and branch:sub(1, 17) .. "…" or branch)
	end
	return "📂 " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
end

-- ═══════════════════════════════════════════════════════════════
-- COMPONENTS — File Info (Sections C & Y)
-- ═══════════════════════════════════════════════════════════════

--- Show the current file size in human-readable format.
---
--- Uses adaptive unit suffixes: B, KB, MB, GB. Only displayed for
--- readable files with a positive size. Returns empty string for
--- unnamed buffers, unreadable files, or empty files.
---
--- ```lua
--- -- For a 56.3KB file:
--- filesize_component()  -- → "󰒋 56.3KB"
---
--- -- For a 1234 byte file:
--- filesize_component()  -- → "󰒋 1234B"
---
--- -- For an unnamed buffer:
--- filesize_component()  -- → ""
--- ```
---
---@return string component File size with 󰒋 icon, or `""` if unavailable
---@nodiscard
local function filesize_component()
	local file = vim.fn.expand("%:p")
	if file == "" or vim.fn.filereadable(file) == 0 then return "" end
	local size = vim.fn.getfsize(file)
	if size <= 0 then return "" end
	local suffixes = { "B", "KB", "MB", "GB" }
	local i = 1
	while size > 1024 and i < #suffixes do
		size = size / 1024
		i = i + 1
	end
	return i == 1 and ("󰒋 " .. size .. "B") or fmt("󰒋 %.1f%s", size, suffixes[i])
end

--- Show the current indent style and width.
---
--- Displays `"󰌒 {shiftwidth}"` for spaces or `"󰌑 Tab:{tabstop}"` for tabs.
--- Reads from buffer-local options (`vim.bo.expandtab`, `vim.bo.shiftwidth`,
--- `vim.bo.tabstop`).
---
--- ```lua
--- -- With expandtab=true, shiftwidth=2:
--- indent_component()  -- → "󰌒 2"
---
--- -- With expandtab=false, tabstop=4:
--- indent_component()  -- → "󰌑 Tab:4"
--- ```
---
---@return string component Indent info string (always non-empty)
---@nodiscard
local function indent_component()
	return vim.bo.expandtab and ("󰌒 " .. vim.bo.shiftwidth) or ("󰌑 Tab:" .. vim.bo.tabstop)
end

--- Show word count for prose filetypes.
---
--- In visual mode, shows selected word count instead of total.
--- Uses `vim.fn.wordcount()` which is fast (no buffer scanning).
--- Returns empty string if wordcount fails.
---
--- ```lua
--- -- In normal mode (markdown file with 1234 words):
--- wordcount_component()  -- → "󰈭 1234w"
---
--- -- In visual mode (5 words selected):
--- wordcount_component()  -- → "󰈭 5w sel"
--- ```
---
---@return string component Word count with 󰈭 icon, or `""` on error
---@nodiscard
local function wordcount_component()
	local ok, wc = pcall(vim.fn.wordcount)
	if not ok then return "" end
	if wc.visual_words then return "󰈭 " .. wc.visual_words .. "w sel" end
	return "󰈭 " .. (wc.words or 0) .. "w"
end

--- Show the current buffer number.
---
--- Always returns a non-empty string. Useful for debugging and
--- buffer navigation reference.
---
--- ```lua
--- bufnr_component()  -- → "󰓩 3"
--- ```
---
---@return string component Buffer number with 󰓩 icon
---@nodiscard
local function bufnr_component()
	return "󰓩 " .. vim.api.nvim_get_current_buf()
end

-- ═══════════════════════════════════════════════════════════════
-- COMPONENTS — Environment & Context (Section X)
--
-- Components that show the execution environment and session state.
-- Environment string is built once per session (doesn't change at
-- runtime). Session name is checked on every refresh.
-- ═══════════════════════════════════════════════════════════════

--- Build a cached display string showing the current execution environment.
---
--- Detects runtime environment from `core.platform` flags and `vim.env`
--- variables. Result is cached for the entire session since these
--- conditions don't change at runtime.
---
--- Detected environments:
--- • SSH (with hostname) • Docker • WSL (with distro name)
--- • Proxmox • VPS • Tmux • Zellij
--- • GUI (Neovide/NvUI/FVim) • Nix shell • Devcontainer/Codespaces
---
--- ```lua
--- -- On SSH to server "dev01" inside tmux:
--- build_env_string()  -- → " dev01   Tmux"
---
--- -- On local macOS:
--- build_env_string()  -- → ""
--- ```
---
---@return string env_string Double-space-separated environment indicators, or `""`
---@nodiscard
local function build_env_string()
	if cache.env_built then return cache.env_string or "" end
	cache.env_built = true

	if not platform_ok or not platform then
		cache.env_string = ""
		return ""
	end

	local parts = {}

	--- Append an environment indicator to the parts list.
	---@param s string Environment indicator string
	local function add(s)
		parts[#parts + 1] = s
	end

	if platform.is_ssh then
		if not cache.hostname then
			local ok, hn = pcall(vim.fn.hostname)
			cache.hostname = ok and (hn:match("^([^%.]+)") or hn) or "remote"
		end
		add(" " .. cache.hostname)
	end
	if platform.is_docker then add("󰡨 Docker") end
	if platform.is_wsl then add("󰖳 WSL" .. (vim.env.WSL_DISTRO_NAME and (" " .. vim.env.WSL_DISTRO_NAME) or "")) end
	if platform.is_proxmox then add("󰒋 Proxmox") end
	if platform.is_vps and not platform.is_docker then add("☁ VPS") end
	if platform.is_tmux then add(" Tmux") end
	if platform.is_zellij then add(" Zellij") end
	if platform.is_gui then
		add("󰖲 " .. (vim.g.neovide and "Neovide" or vim.g.nvui and "NvUI" or vim.g.fvim_loaded and "FVim" or "GUI"))
	end
	if vim.env.IN_NIX_SHELL or vim.env.NIX_STORE then add("❄ Nix") end
	if vim.env.REMOTE_CONTAINERS or vim.env.CODESPACES then add("󰜫 Dev") end

	cache.env_string = table.concat(parts, "  ")
	return cache.env_string
end

--- Show the active session name from auto-session or persisted.nvim.
---
--- Checks auto-session first (via `auto-session.lib`), then falls back
--- to `vim.g.persisted_loaded_session`. Displays only the basename
--- of the session path for compact display.
---
--- ```lua
--- -- With auto-session active:
--- session_component()  -- → "󰆔 my-project"
---
--- -- With no session:
--- session_component()  -- → ""
--- ```
---
---@return string component Session name with 󰆔 icon, or `""` if no session
---@nodiscard
local function session_component()
	local ok, lib = pcall(require, "auto-session.lib")
	if ok then
		local name = lib.current_session_name()
		if name and name ~= "" then return "󰆔 " .. vim.fn.fnamemodify(name, ":t") end
	end
	if vim.g.persisted_loaded_session then
		return "󰆔 " .. vim.fn.fnamemodify(vim.g.persisted_loaded_session, ":t:r")
	end
	return ""
end

--- Show the active Python virtual environment name.
---
--- Checks `VIRTUAL_ENV`, `CONDA_DEFAULT_ENV`, and `PYENV_VIRTUAL_ENV`
--- environment variables. Displays only the basename of the path.
--- Uses 󰏖 (package icon) to distinguish from the Python version
--- displayed by `lang_runtime()`.
---
--- ```lua
--- -- With VIRTUAL_ENV="/home/user/.venvs/myproject":
--- venv_component()  -- → "󰏖 myproject"
---
--- -- With no venv active:
--- venv_component()  -- → ""
--- ```
---
---@return string component Venv name with 󰏖 icon, or `""` if no venv
---@nodiscard
local function venv_component()
	local venv = vim.env.VIRTUAL_ENV or vim.env.CONDA_DEFAULT_ENV or vim.env.PYENV_VIRTUAL_ENV
	return venv and ("󰏖 " .. vim.fn.fnamemodify(venv, ":t")) or ""
end

-- ═══════════════════════════════════════════════════════════════
-- COMPONENTS — Tools: LSP, AI, DAP, Macro, Search, Lazy, User
--
-- Components that display development tool information.
-- Each returns a string (empty if inactive/unavailable).
-- All external requires are wrapped in pcall.
-- ═══════════════════════════════════════════════════════════════

--- Show active LSP client names for the current buffer.
---
--- Filters out copilot, null-ls, and none-ls (displayed in the AI
--- component instead). Truncates to `"first_name +N"` if the
--- combined display string exceeds 25 characters.
---
--- ```lua
--- -- Two LSP clients attached:
--- lsp_component()  -- → " lua_ls, stylua"
---
--- -- Many clients (truncated):
--- lsp_component()  -- → " tsserver +3"
---
--- -- No LSP clients:
--- lsp_component()  -- → ""
--- ```
---
---@return string component Formatted LSP client list with  icon, or `""`
---@nodiscard
local function lsp_component()
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	if #clients == 0 then return "" end
	local names = {}
	for _, c in ipairs(clients) do
		if not LSP_IGNORED[c.name] then names[#names + 1] = c.name end
	end
	if #names == 0 then return "" end
	local display = table.concat(names, ", ")
	return " " .. (#display > 25 and (names[1] .. " +" .. (#names - 1)) or display)
end

--- Aggregate AI assistant status from all providers.
---
--- Checks in order: GitHub Copilot (LSP client or legacy function),
--- Supermaven, Codeium, and the settings-configured AI provider.
--- Combines all active providers into a single space-separated string.
---
--- ```lua
--- -- Copilot + configured provider "claude":
--- ai_component()  -- → "  🤖 claude"
---
--- -- No AI assistants active:
--- ai_component()  -- → ""
--- ```
---
---@return string component Space-separated AI status indicators, or `""`
---@nodiscard
local function ai_component()
	local parts = {}

	-- Copilot: check LSP client first, then legacy vimscript function
	local ok1, cls = pcall(vim.lsp.get_clients, { name = "copilot", bufnr = 0 })
	if ok1 and #cls > 0 then
		parts[#parts + 1] = " "
	else
		local ok2, en = pcall(vim.api.nvim_call_function, "copilot#Enabled", {})
		if ok2 and en == 1 then parts[#parts + 1] = " " end
	end

	-- Supermaven
	local ok3, smapi = pcall(require, "supermaven-nvim.api")
	if ok3 and smapi.is_running() then parts[#parts + 1] = "󱙺" end

	-- Codeium
	local ok4, cstat = pcall(vim.api.nvim_call_function, "codeium#GetStatusString", {})
	if ok4 and cstat and vim.trim(cstat) ~= "" then parts[#parts + 1] = "󰘦 " .. vim.trim(cstat) end

	-- Configured provider from settings
	if setting("ai.enabled", false) then
		local provider = setting("ai.provider", "")
		if provider ~= "" and provider ~= "none" then parts[#parts + 1] = ic(mi, "AI", "🤖") .. " " .. provider end
	end

	return table.concat(parts, " ")
end

--- Show DAP (Debug Adapter Protocol) session status.
---
--- Displays the current debug status when a DAP session is active.
--- Falls back to `"active"` if `dap.status()` returns empty.
---
--- ```lua
--- -- While debugging at a breakpoint:
--- dap_component()  -- → "󰃤 Stopped at line 42"
---
--- -- No debug session:
--- dap_component()  -- → ""
--- ```
---
---@return string component Debug status with 󰃤 icon, or `""`
---@nodiscard
local function dap_component()
	local ok, dap = pcall(require, "dap")
	if not ok or not dap.session() then return "" end
	local status = dap.status()
	return "󰃤 " .. (status ~= "" and status or "active")
end

--- Show macro recording indicator.
---
--- Displays `"󰑋 REC @{register}"` when actively recording a macro.
--- Only visible during recording (ephemeral, high-visibility component).
---
--- ```lua
--- -- Recording into register q:
--- macro_component()  -- → "󰑋 REC @q"
---
--- -- Not recording:
--- macro_component()  -- → ""
--- ```
---
---@return string component Recording indicator with register name, or `""`
---@nodiscard
local function macro_component()
	local reg = vim.fn.reg_recording()
	return reg ~= "" and ("󰑋 REC @" .. reg) or ""
end

--- Show search match count (current/total).
---
--- Only displayed when `hlsearch` is active. Uses `vim.fn.searchcount()`
--- with a maximum of 999 matches and 250ms timeout to avoid blocking
--- on large files.
---
--- ```lua
--- -- Searching for "function" (3rd of 42 matches):
--- search_component()  -- → " 3/42"
---
--- -- No active search:
--- search_component()  -- → ""
--- ```
---
---@return string component Formatted `" current/total"`, or `""`
---@nodiscard
local function search_component()
	if vim.v.hlsearch == 0 then return "" end
	local ok, count = pcall(vim.fn.searchcount, { maxcount = 999, timeout = 250 })
	if ok and count and count.total and count.total > 0 then return fmt(" %d/%d", count.current, count.total) end
	return ""
end

--- Show count of available lazy.nvim plugin updates.
---
--- Uses a TTL-based cache (`LAZY_TTL` = 300s) to avoid checking on
--- every statusline refresh. Only displays when updates are available.
---
--- ```lua
--- -- 5 updates available:
--- lazy_updates()  -- → "󰏔 5"
---
--- -- No updates or lazy not loaded:
--- lazy_updates()  -- → ""
--- ```
---
---@return string component Update count with 󰏔 icon, or `""`
---@nodiscard
local function lazy_updates()
	local now = (vim.uv or vim.loop).now() / 1000
	if cache.lazy_updates and (now - cache.lazy_checked) < LAZY_TTL then
		return cache.lazy_updates > 0 and ("󰏔 " .. cache.lazy_updates) or ""
	end
	local ok, ls = pcall(require, "lazy.status")
	if ok and ls.has_updates() then
		local num = tonumber(ls.updates():match("%d+")) or 0
		cache.lazy_updates, cache.lazy_checked = num, now
		return num > 0 and ("󰏔 " .. num) or ""
	end
	cache.lazy_updates, cache.lazy_checked = 0, now
	return ""
end

--- Show the active user namespace name.
---
--- Reads from `_G.NvimConfig.state.active_user` (set by settings_manager).
--- Defaults to `"default"` if the global state is not initialized.
---
--- This component is the **anchor** of section X — it is always visible
--- and always positioned last to ensure clean X→Y separator rendering.
---
--- ```lua
--- -- With custom user namespace "work":
--- user_component()  -- → "U work"
---
--- -- Default state:
--- user_component()  -- → "U default"
--- ```
---
---@return string component User name with icon (always non-empty)
---@nodiscard
local function user_component()
	local user = (_G.NvimConfig and _G.NvimConfig.state and _G.NvimConfig.state.active_user) or "default"
	return ic(ui, "User", "U") .. " " .. user
end

-- ═══════════════════════════════════════════════════════════════
-- COMPONENTS — Noice (Section C)
--
-- Displays noice.nvim command and mode indicators inline in the
-- file section. Conditional: only shown when noice has content.
-- ═══════════════════════════════════════════════════════════════

--- Show the last noice.nvim command display.
---
--- Renders the command-line content captured by noice's `command`
--- status module. Empty when no command is being displayed.
---
--- ```lua
--- -- After running :%s/foo/bar/g:
--- noice_command()  -- → ":%s/foo/bar/g"
---
--- -- No command displayed:
--- noice_command()  -- → ""
--- ```
---
---@return string component Last command string, or `""`
---@nodiscard
local function noice_command()
	local ok, noice = pcall(require, "noice")
	return (ok and noice.api.status.command.has()) and noice.api.status.command.get() or ""
end

--- Show the current noice.nvim mode indicator.
---
--- Renders mode information captured by noice's `mode` status module
--- (e.g., recording indicator, visual mode details).
---
--- ```lua
--- -- In visual block mode:
--- noice_mode()  -- → "-- VISUAL BLOCK --"
---
--- -- No mode displayed:
--- noice_mode()  -- → ""
--- ```
---
---@return string component Mode indicator string, or `""`
---@nodiscard
local function noice_mode()
	local ok, noice = pcall(require, "noice")
	return (ok and noice.api.status.mode.has()) and noice.api.status.mode.get() or ""
end

-- ═══════════════════════════════════════════════════════════════
-- COMPONENTS — DateTime (Section Z)
--
-- Section Z uses a dynamic accent color derived from the active
-- colorscheme. The accent is applied by overriding lualine_z_*
-- highlight groups for all modes.
-- ═══════════════════════════════════════════════════════════════

--- Show date and time in European 24h format.
---
--- Format: `DD.MM.YYYY HH:MM` with a 󰃭 calendar icon prefix.
--- The section Z background color is controlled by `apply_datetime_hl()`
--- which derives the accent from the active colorscheme.
---
--- ```lua
--- datetime_component()  -- → "󰃭 10.03.2026 08:25"
--- ```
---
---@return string component Formatted date and time (always non-empty)
---@nodiscard
local function datetime_component()
	return "󰃭 " .. os.date("%d.%m.%Y") .. " " .. os.date("%H:%M")
end

--- Get the accent color for the datetime badge from the active colorscheme.
---
--- Cascades through semantic highlight groups to find a prominent
--- accent color. This ensures the datetime badge looks good on ANY
--- colorscheme without hardcoding theme-specific values:
---
--- • Catppuccin Mocha: `#89b4fa` (blue)
--- • Tokyo Night:      `#7aa2f7` (blue)
--- • Gruvbox:          `#8ec07c` (aqua)
--- • Dracula:          `#bd93f9` (purple)
---
--- Cascade order: `Function` → `@keyword` → `Statement` → `DiagnosticInfo`
---
---@return string hex Accent hex color (always returns a value, fallback `"#94e2d5"`)
---@nodiscard
local function datetime_accent()
	return hl_fg("Function") or hl_fg("@keyword") or hl_fg("Statement") or hl_fg("DiagnosticInfo") or "#94e2d5"
end

--- Override lualine_z highlight groups for ALL modes with accent colors.
---
--- Forces the entire section Z to use the accent background (derived from
--- the active colorscheme's `Function` fg). Lualine's natural section
--- separator between Y and Z then creates a perfect powerline transition.
---
--- Overrides: `lualine_z_{normal,insert,visual,replace,command,terminal,inactive}`
---
--- Called once at setup and again on every `ColorScheme` event to keep
--- the accent in sync with theme changes.
---
---@return nil
local function apply_datetime_hl()
	local accent = datetime_accent()
	local dark = hl_bg("Normal") or "#1e1e2e"
	for _, mode in ipairs({ "normal", "insert", "visual", "replace", "command", "terminal", "inactive" }) do
		vim.api.nvim_set_hl(0, "lualine_z_" .. mode, { fg = dark, bg = accent, bold = true })
	end
end

-- ═══════════════════════════════════════════════════════════════
-- CONDITIONS
--
-- Boolean functions that control component visibility in lualine.
-- Each condition is wrapped in safe_cond() at the call site via
-- the comp() factory. Raw functions are defined here for clarity.
--
-- Categories:
--   • Tool availability (LSP, noice, DAP, lazy)
--   • Runtime state (recording, searching, debugging)
--   • Environment (session, env string, venv, lang runtime)
--   • Filetype checks (prose)
--   • Encoding/format anomalies (non-UTF-8, non-Unix)
-- ═══════════════════════════════════════════════════════════════

---@class LualineConditions
---@field has_lsp fun(): boolean          At least one LSP client attached to current buffer
---@field is_recording fun(): boolean     Macro recording is active
---@field is_searching fun(): boolean     Highlight search is active with matches
---@field is_debugging fun(): boolean     DAP debug session is running
---@field has_noice_cmd fun(): boolean    Noice has a command string to display
---@field has_noice_mode fun(): boolean   Noice has a mode indicator to display
---@field has_lazy fun(): boolean         Lazy.nvim has pending plugin updates
---@field has_env fun(): boolean          Environment string is non-empty
---@field has_session fun(): boolean      Session manager has an active session
---@field has_ai fun(): boolean           At least one AI assistant is active
---@field has_venv fun(): boolean         Python virtual environment is active
---@field has_lang_runtime fun(): boolean Current filetype has a detected runtime version
---@field is_prose fun(): boolean         Current filetype is a prose/markup format
---@field non_utf8 fun(): boolean         File encoding is not UTF-8
---@field non_unix fun(): boolean         File format is not Unix (LF)
local cond = {
	--- Check if any non-ignored LSP clients are attached to the current buffer.
	---@return boolean
	has_lsp = function()
		return #vim.lsp.get_clients({ bufnr = 0 }) > 0
	end,

	--- Check if a macro is currently being recorded.
	---@return boolean
	is_recording = function()
		return vim.fn.reg_recording() ~= ""
	end,

	--- Check if highlight search is active.
	---@return boolean
	is_searching = function()
		return vim.v.hlsearch == 1
	end,

	--- Check if a DAP debug session is active.
	---@return boolean
	is_debugging = function()
		local ok, d = pcall(require, "dap")
		return ok and d.session() ~= nil
	end,

	--- Check if noice.nvim has a command to display.
	---@return boolean
	has_noice_cmd = function()
		local ok, n = pcall(require, "noice")
		return ok and n.api.status.command.has()
	end,

	--- Check if noice.nvim has a mode indicator to display.
	---@return boolean
	has_noice_mode = function()
		local ok, n = pcall(require, "noice")
		return ok and n.api.status.mode.has()
	end,

	--- Check if lazy.nvim has pending plugin updates.
	---@return boolean
	has_lazy = function()
		local ok, l = pcall(require, "lazy.status")
		return ok and l.has_updates()
	end,

	--- Check if the cached environment string is non-empty.
	---@return boolean
	has_env = function()
		return build_env_string() ~= ""
	end,

	--- Check if a session manager has an active session.
	---@return boolean
	has_session = function()
		return session_component() ~= ""
	end,

	--- Check if at least one AI assistant is active.
	---@return boolean
	has_ai = function()
		return ai_component() ~= ""
	end,

	--- Check if a Python virtual environment is active.
	---@return boolean
	has_venv = function()
		return venv_component() ~= ""
	end,

	--- Check if the current filetype has a detected language runtime.
	---@return boolean
	has_lang_runtime = function()
		return lang_runtime() ~= ""
	end,

	--- Check if the current filetype is a prose/markup format.
	---@return boolean
	is_prose = function()
		return PROSE_FILETYPES[vim.bo.filetype] or false
	end,

	--- Check if the file encoding is NOT UTF-8 (encoding anomaly).
	---@return boolean
	non_utf8 = function()
		return vim.bo.fileencoding ~= "utf-8" and vim.bo.fileencoding ~= ""
	end,

	--- Check if the file format is NOT Unix/LF (format anomaly).
	---@return boolean
	non_unix = function()
		return vim.bo.fileformat ~= "unix"
	end,
}

-- ═══════════════════════════════════════════════════════════════
-- COLORS
--
-- Static Catppuccin Mocha hex colors for component highlighting.
-- Theme-independent: they provide consistent color coding
-- regardless of the active colorscheme. Lualine handles section
-- backgrounds via `theme = "auto"`.
-- ═══════════════════════════════════════════════════════════════

---@class LualineColors
---@field env table      Environment string: pink `#f5c2e7`
---@field session table  Session name: flamingo `#f2cdcd`
---@field venv table     Virtual environment: green `#a6e3a1`
---@field runtime table  Language runtime version: sapphire `#74c7ec`
---@field ai table       AI assistant status: cyan `#7dcfff`
---@field lsp table      LSP client names: blue `#89b4fa`
---@field lazy table     Lazy.nvim updates: yellow `#f9e2af`
---@field user table     User namespace: purple `#bb9af7`
---@field dap table      DAP debug status: red `#f38ba8`
---@field macro table    Macro recording: red `#f38ba8`
---@field search table   Search count: peach `#fab387`
---@field indent table   Indent style: overlay `#9399b2`
---@field words table    Word count: mauve `#cba6f7`
---@field fsize table    File size: overlay `#9399b2`
---@field bufnr table    Buffer number: surface `#6c7086`
---@field noice table    Noice command/mode: text `#cdd6f4`

---@type LualineColors
local C = {
	env = { fg = "#f5c2e7", gui = "bold" },
	session = { fg = "#f2cdcd" },
	venv = { fg = "#a6e3a1" },
	runtime = { fg = "#74c7ec" },
	ai = { fg = "#7dcfff", gui = "bold" },
	lsp = { fg = "#89b4fa" },
	lazy = { fg = "#f9e2af" },
	user = { fg = "#bb9af7" },
	dap = { fg = "#f38ba8", gui = "bold" },
	macro = { fg = "#f38ba8", gui = "bold" },
	search = { fg = "#fab387" },
	indent = { fg = "#9399b2" },
	words = { fg = "#cba6f7" },
	fsize = { fg = "#9399b2" },
	bufnr = { fg = "#6c7086" },
	noice = { fg = "#cdd6f4" },
}

-- ═══════════════════════════════════════════════════════════════
-- PLUGIN SPEC
--
-- Loaded on VeryLazy. On dashboard launches (argc == 0), the
-- statusline is hidden (laststatus = 0) until a real file opens.
-- On file launches, a minimal " " statusline prevents flicker.
-- ═══════════════════════════════════════════════════════════════

return {
	"nvim-lualine/lualine.nvim",
	event = "VeryLazy",
	dependencies = { "nvim-mini/mini.icons" },

	--- Pre-initialization: set statusline placeholder before lualine loads.
	---
	--- • With files (`argc > 0`): show minimal `" "` to prevent flicker
	--- • Without files (dashboard): hide statusline entirely (`laststatus = 0`)
	---
	---@return nil
	init = function()
		vim.g.lualine_laststatus = vim.o.laststatus
		if vim.fn.argc(-1) > 0 then
			vim.o.statusline = " "
		else
			vim.o.laststatus = 0
		end
	end,

	--- Build the complete lualine options table.
	---
	--- Uses a function (not a static table) because several components need
	--- runtime evaluation: navic availability check, icon resolution, and
	--- conditional winbar setup.
	---
	---@return table opts Lualine configuration table passed to `lualine.setup()`
	opts = function()
		-- ── Winbar (navic breadcrumbs) ────────────────────────
		---@type table
		local winbar = {}
		if pcall(require, "nvim-navic") then
			winbar = {
				lualine_c = {
					comp(function()
						return require("nvim-navic").get_location()
					end, {
						color = C.noice,
						cond = function()
							local ok, navic = pcall(require, "nvim-navic")
							return ok and navic.is_available()
						end,
					}),
				},
			}
		end

		-- ── Pre-resolved icon strings ─────────────────────────
		---@type string
		local git_added = ic(gi, "Added", "+") .. " "
		---@type string
		local git_modified = ic(gi, "Modified", "~") .. " "
		---@type string
		local git_removed = ic(gi, "Removed", "-") .. " "
		---@type string
		local diag_error = ic(dg, "Error", "E") .. " "
		---@type string
		local diag_warn = ic(dg, "Warn", "W") .. " "
		---@type string
		local diag_info = ic(dg, "Info", "I") .. " "
		---@type string
		local diag_hint = ic(dg, "Hint", "H") .. " "
		---@type string
		local sym_modified = " " .. ic(ui, "Pencil", "●")
		---@type string
		local sym_readonly = " " .. ic(ui, "Lock", "RO")
		---@type string
		local sym_newfile = " " .. ic(ui, "NewFile", "N")

		return {
			options = {
				theme = "auto",
				globalstatus = setting("ui.global_statusline", true),
				disabled_filetypes = {
					statusline = { "dashboard", "alpha", "ministarter", "snacks_dashboard" },
					winbar = {
						"dashboard",
						"alpha",
						"ministarter",
						"snacks_dashboard",
						"neo-tree",
						"toggleterm",
						"Trouble",
						"help",
						"qf",
					},
				},
				section_separators = { left = sep.round_r, right = sep.round_l },
				component_separators = { left = sep.round_thin_r, right = sep.round_thin_l },
				refresh = { statusline = 1000, tabline = 1000, winbar = 1000 },
			},

			-- ═══════════════════════════════════════════════════
			-- ACTIVE SECTIONS
			-- ═══════════════════════════════════════════════════

			sections = {

				-- ── A: MODE — Round bubble, bold, OS icon ─────
				lualine_a = {
					{ "mode", icon = get_os_icon() },
				},

				-- ── B: GIT — Always visible (branch or CWD) ──
				lualine_b = {
					comp(branch_or_cwd, { sep = SEP_ROUND }),
					{
						"diff",
						symbols = { added = git_added, modified = git_modified, removed = git_removed },
						--- Provide git diff stats from gitsigns buffer variable.
						---@return { added: number|nil, modified: number|nil, removed: number|nil }|nil
						source = function()
							---@diagnostic disable-next-line: undefined-field
							local gs = vim.b.gitsigns_status_dict
							if gs then return { added = gs.added, modified = gs.changed, removed = gs.removed } end
						end,
					},
				},

				-- ── C: FILE — Diagnostics + type + name + size + noice ──
				lualine_c = {
					{
						"diagnostics",
						sources = { "nvim_diagnostic" },
						sections = { "error", "warn", "info", "hint" },
						symbols = {
							error = diag_error,
							warn = diag_warn,
							info = diag_info,
							hint = diag_hint,
						},
						colored = true,
						update_in_insert = false,
						always_visible = false,
						separator = SEP_NONE,
						padding = PAD_STD,
					},
					{ "filetype", icon_only = true, separator = SEP_NONE, padding = PAD_L },
					{
						"filename",
						path = 1,
						symbols = {
							modified = sym_modified,
							readonly = sym_readonly,
							unnamed = " [No Name]",
							newfile = sym_newfile,
						},
						separator = SEP_NONE,
						padding = PAD_STD,
					},
					comp(filesize_component, { color = C.fsize }),
					comp(noice_command, { color = C.noice, cond = cond.has_noice_cmd }),
					comp(noice_mode, { color = C.noice, cond = cond.has_noice_mode }),
				},

				-- ── X: STATUS CENTER ──────────────────────────
				-- Order: ephemeral → context → language → AI → tools → ANCHOR
				-- Rule: user_component ALWAYS LAST → clean X→Y separator
				lualine_x = {
					-- Ephemeral (high-visibility, conditional)
					comp(dap_component, { color = C.dap, cond = cond.is_debugging, sep = SEP_THIN }),
					comp(macro_component, { color = C.macro, cond = cond.is_recording, sep = SEP_THIN }),
					comp(search_component, { color = C.search, cond = cond.is_searching, sep = SEP_THIN }),
					-- Context
					comp(session_component, { color = C.session, cond = cond.has_session }),
					comp(build_env_string, { color = C.env, cond = cond.has_env, sep = SEP_THIN }),
					-- Language (venv name + contextual runtime version)
					comp(venv_component, { color = C.venv, cond = cond.has_venv }),
					comp(lang_runtime, { color = C.runtime, cond = cond.has_lang_runtime, sep = SEP_THIN }),
					-- AI
					comp(ai_component, { color = C.ai, cond = cond.has_ai }),
					-- Tools (conditional)
					comp(lsp_component, { color = C.lsp, cond = cond.has_lsp }),
					comp(lazy_updates, { color = C.lazy, cond = cond.has_lazy }),
					-- ANCHOR — always visible, always last, no custom separator
					comp(user_component, { color = C.user }),
				},

				-- ── Y: META — indent, encoding, words, bufnr, progress, location ──
				lualine_y = {
					comp(indent_component, { color = C.indent, pad = PAD_L }),
					{
						"encoding",
						fmt = function(s)
							return (s and s ~= "") and s:upper() or ""
						end,
						cond = safe_cond(cond.non_utf8),
						separator = SEP_NONE,
						padding = PAD_L,
					},
					{ "fileformat", cond = safe_cond(cond.non_unix), separator = SEP_NONE, padding = PAD_L },
					comp(wordcount_component, { color = C.words, cond = cond.is_prose, pad = PAD_L }),
					comp(bufnr_component, { color = C.bufnr, pad = PAD_STD }),
					{ "progress", separator = SEP_NONE, padding = PAD_L },
					{ "location", padding = PAD_STD },
				},

				-- ── Z: DATETIME — accent badge (bg via highlight overrides) ──
				lualine_z = {
					comp(datetime_component, { pad = PAD_STD }),
				},
			},

			-- ═══════════════════════════════════════════════════
			-- INACTIVE SECTIONS
			-- ═══════════════════════════════════════════════════

			inactive_sections = {
				lualine_a = {},
				lualine_b = {},
				lualine_c = { { "filename", path = 1, symbols = { modified = " ●", readonly = " " } } },
				lualine_x = { "location" },
				lualine_y = {},
				lualine_z = {},
			},

			-- ═══════════════════════════════════════════════════
			-- WINBAR & EXTENSIONS
			-- ═══════════════════════════════════════════════════

			winbar = winbar,
			inactive_winbar = {},

			extensions = {
				"neo-tree",
				"lazy",
				"toggleterm",
				"trouble",
				"quickfix",
				"man",
				"mason",
				"nvim-dap-ui",
				"fugitive",
				"oil",
				"overseer",
			},
		}
	end,

	--- Post-setup: apply datetime highlights and register colorscheme autocmd.
	---
	--- 1. Override section Z highlights with colorscheme-derived accent
	--- 2. Initialize lualine with the options table
	--- 3. Register `ColorScheme` autocmd for automatic accent refresh
	---
	---@param _ table Plugin spec (unused)
	---@param opts table Lualine options table from `opts()`
	---@return nil
	config = function(_, opts)
		apply_datetime_hl()
		require("lualine").setup(opts)

		vim.api.nvim_create_autocmd("ColorScheme", {
			group = augroup("LualineDatetime"),
			callback = function()
				vim.schedule(function()
					apply_datetime_hl()
					pcall(function()
						require("lualine").refresh()
					end)
				end)
			end,
			desc = "Update lualine Z accent on colorscheme change",
		})
	end,
}
