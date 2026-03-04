---@file lua/plugins/ui/dashboard.lua
---@description Nvim Enterprise Custom Dashboard — performance-optimized startup screen
---@module "plugins.ui.dashboard"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings   Settings accessor (colorscheme, user, languages)
---@see core.platform   Platform detection (OS, runtimes, environment)
---@see core.utils      Icon helper, file utilities
---@see core.icons      Centralized icon definitions (app icons for runtimes)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ui/dashboard.lua — Enterprise Dashboard                         ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌─────────────────────────────────────────────────────────────────┐     ║
--- ║  │  nvim-enterprise-dashboard (local plugin)                       │     ║
--- ║  │                                                                 │     ║
--- ║  │  • Custom ASCII art with rainbow gradient                       │     ║
--- ║  │  • Two-column action layout (left: files, right: tools)         │     ║
--- ║  │  • System info bar (OS, env, runtimes, AI provider)             │     ║
--- ║  │  • Dynamic runtime display from core/platform runtimes          │     ║
--- ║  │  • Lazy.nvim stats in footer                                    │     ║
--- ║  │  • Segment-based line builder with highlight tracking           │     ║
--- ║  │  • Float/picker-aware keymap execution                          │     ║
--- ║  │  • Replaces snacks.nvim dashboard (explicitly disabled)         │     ║
--- ║  └─────────────────────────────────────────────────────────────────┘     ║
--- ║                                                                          ║
--- ║  Runtime display integration:                                            ║
--- ║  ┌─────────────────────────────────────────────────────────────────┐     ║
--- ║  │  core/platform.lua           core/icons.lua       dashboard     │     ║
--- ║  │  ┌────────────────────┐      ┌─────────────┐    ┌───────────┐   │     ║
--- ║  │  │ RUNTIME_EXECUTABLES│      │ icons.app   │    │ get_runt- │   │     ║
--- ║  │  │ go = "go"          │      │ Go = ""     │    │ imes()    │   │     ║
--- ║  │  │ python = {py3,py}  │      │ Python = "" │    │           │   │     ║
--- ║  │  │ rust = "rustc"     │      │ Rust = ""   │    │ Iterates  │   │     ║
--- ║  │  │ zig = "zig"        │  ──► │ Zig = ""    │ ──►│ runtimes, │   │     ║
--- ║  │  │ gcc = "gcc"        │      │ Gcc = nil   │    │ matches   │   │     ║
--- ║  │  │ ...                │      │ ...         │    │ icons.app │   │     ║
--- ║  │  └────────────────────┘      └─────────────┘    └───────────┘   │     ║
--- ║  │                                                                 │     ║
--- ║  │  Result: " Go  Python  Rust  Zig Gcc"                           │     ║
--- ║  │          (Gcc shown without icon — no icons.app["Gcc"] entry)   │     ║
--- ║  │                                                                 │     ║
--- ║  │  Adding a new runtime: only modify core/platform.lua            │     ║
--- ║  │  Adding its icon: only modify core/icons.lua                    │     ║
--- ║  │  Dashboard picks up both automatically — zero changes here.     │     ║
--- ║  └─────────────────────────────────────────────────────────────────┘     ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Deferred render via vim.schedule (never blocks UI)                    ║
--- ║  • Lazy stats read only after plugins loaded                             ║
--- ║  • Cached platform/settings reads (no repeated calls)                    ║
--- ║  • Minimal highlight setup (batch vim.api calls)                         ║
--- ║  • No require() calls in hot render path                                 ║
--- ║  • Reusable namespace across re-renders                                  ║
--- ║  • Efficient UTF-8 iteration for gradient                                ║
--- ║  • Single autocmd group for all dashboard events                         ║
--- ║  • Does NOT trigger treesitter loading                                   ║
--- ║  • Extmark-based highlighting (replaces deprecated buf_add_highlight)    ║
--- ║                                                                          ║
--- ║  Dashboard keymaps (buffer-local, inside dashboard only):                ║
--- ║    f   Find File          n   New File           g   Grep Search         ║
--- ║    r   Recent Files       s   Restore Session    S   Last Session        ║
--- ║    t   Settings           E   Edit Config        l   Lazy                ║
--- ║    M   Mason              h   Health Check       L   LSP Info            ║
--- ║    i   Nvim Info          x   LazyVim Extras     a   Languages           ║
--- ║    c   All Commands       P   Performance        u   Switch User         ║
--- ║    R   Restart Nvim       G   Git Protocol       V   View Log            ║
--- ║    C   Clear Log          v   Neovim Version     q   Quit                ║
--- ║    <Esc>  Close dashboard                                                ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════════

--- Rainbow gradient palette for ASCII art.
--- 18 colors cycling through the spectrum, used by the gradient engine
--- to apply per-character highlighting on the header ASCII art.
---@type string[]
---@private
local GRADIENT = {
	"#00d4ff",
	"#00e4d0",
	"#00f0a0",
	"#30ff70",
	"#70ff40",
	"#a0f020",
	"#d0e000",
	"#f0c000",
	"#ff9020",
	"#ff6040",
	"#ff3060",
	"#ff2080",
	"#e020a0",
	"#c030d0",
	"#9040f0",
	"#6050ff",
	"#4070ff",
	"#20a0ff",
}

--- ASCII art for the dashboard header.
--- Rendered with rainbow gradient via the gradient engine.
---@type string[]
---@private
-- stylua: ignore
local ASCII_ART = {
	[[             ___ _______  __     _ _           ]],
	[[   ___ __ _ / _ \___  / | \ \   / (_)_ __ ___  ]],
	[[  / __/ _` | (_) | / /| |  \ \ / /| | '_ ` _ \ ]],
	[[ | (_| (_| |\__, |/ / | |   \ V / | | | | | | |]],
	[[  \___\__,_|  /_//_/  |_|    \_/  |_|_| |_| |_|]],
	[[                                               ]],
}

--- Layout dimensions for the two-column action area.
---@type { col_w: integer, gap_w: integer }
---@private
local LAYOUT = {
	col_w = 34,
	gap_w = 6,
}

--- Commands that open floating windows (don't close dashboard).
--- When a keymap triggers one of these, the dashboard buffer is preserved
--- behind the floating window instead of being wiped.
---@type table<string, true>
---@private
local FLOAT_COMMANDS = {
	Lazy = true,
	Mason = true,
	NvimLspInfo = true,
	NvimInfo = true,
	NvimCommands = true,
	NvimExtras = true,
	NvimLanguages = true,
	NvimVersion = true,
	NvimPerf = true,
	NvimHealth = true,
	NvimLogView = true,
	NvimLogClear = true,
	NvimGitProtocol = true,
	NvimGitConvert = true,
	Settings = true,
	UserSwitch = true,
}

--- Command prefixes that indicate a picker/fuzzy-finder.
--- Used to detect whether a command will open a picker UI, in which
--- case the dashboard should not be closed prematurely.
---@type string[]
---@private
local PICKER_PREFIXES = { "Telescope", "lua Snacks" }

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPECS
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec[]
return {
	-- ── Disable snacks dashboard (replaced by this one) ──────────────
	{
		"folke/snacks.nvim",
		opts = { dashboard = { enabled = false } },
	},

	-- ── Enterprise dashboard ─────────────────────────────────────────
	{
		dir = vim.fn.stdpath("config"),
		name = "nvim-enterprise-dashboard",
		lazy = false,
		priority = 100,

		config = function()
			local settings = require("core.settings")
			if not settings:is_plugin_enabled("dashboard") then return end

			-- ══════════════════════════════════════════════════════
			-- CACHED IMPORTS
			--
			-- All require() calls done once at config time, not per
			-- render. Locals are faster than table lookups in the
			-- hot render path.
			-- ══════════════════════════════════════════════════════

			local utils = require("core.utils")
			local platform = require("core.platform")
			local icons = require("core.icons")
			local augroup = require("core.utils").augroup

			local api = vim.api
			local fn = vim.fn
			local fmt = string.format
			local rep = string.rep
			local dw = fn.strdisplaywidth
			local set_hl = api.nvim_set_hl
			local ic = utils.icon

			---@type integer
			local GRAD_N = #GRADIENT
			---@type integer
			local TOTAL_W = LAYOUT.col_w * 2 + LAYOUT.gap_w

			-- ══════════════════════════════════════════════════════
			-- EXTMARK-BASED HIGHLIGHT HELPER
			--
			-- Replaces deprecated nvim_buf_add_highlight with
			-- nvim_buf_set_extmark. Signature is intentionally
			-- identical for drop-in compatibility with all callers
			-- (grad_line, B:seg highlights, B:hl_line).
			-- ══════════════════════════════════════════════════════

			---@type integer
			local ns = api.nvim_create_namespace("nvim_dash")

			--- Apply a highlight to a buffer region via extmarks.
			---
			--- Drop-in replacement for the deprecated `nvim_buf_add_highlight`.
			--- Signature is intentionally identical for compatibility.
			---
			---@param buffer integer Buffer handle
			---@param ns_id integer Namespace ID for the extmark
			---@param hl_group string Highlight group name (e.g. `"DG1"`, `"DCat"`)
			---@param line integer 0-indexed line number
			---@param col_start integer 0-indexed byte start column
			---@param col_end integer 0-indexed byte end column, or `-1` for end of line
			---@private
			local function buf_add_hl(buffer, ns_id, hl_group, line, col_start, col_end)
				local opts = { hl_group = hl_group }
				if col_end == -1 then
					-- Highlight to end of line: extmark range spans to next line start
					opts.end_row = line + 1
					opts.end_col = 0
				else
					opts.end_col = col_end
				end
				pcall(api.nvim_buf_set_extmark, buffer, ns_id, line, col_start, opts)
			end

			-- ══════════════════════════════════════════════════════
			-- HIGHLIGHTS
			--
			-- All highlight groups are created once, then refreshed
			-- on ColorScheme change to persist across theme switches.
			-- ══════════════════════════════════════════════════════

			---@type integer
			local group = augroup("Dashboard")

			--- Create or refresh all dashboard highlight groups.
			---
			--- Called once at config time and again on every `ColorScheme`
			--- event to ensure dashboard colors persist across theme switches.
			---@private
			local function setup_hl()
				-- Gradient palette highlights (DG1 .. DG18)
				for i, c in ipairs(GRADIENT) do
					set_hl(0, "DG" .. i, { fg = c, bold = true })
				end
				-- stylua: ignore start
				set_hl(0, "DCat",    { fg = "#bb9af7", bold = true })
				set_hl(0, "DIcon",   { fg = "#7dcfff" })
				set_hl(0, "DDesc",   { fg = "#c0caf5" })
				set_hl(0, "DKey",    { fg = "#ff9e64", bold = true })
				set_hl(0, "DSep",    { fg = "#3b4261" })
				set_hl(0, "DDim",    { fg = "#565f89", italic = true })
				set_hl(0, "DAccent", { fg = "#7aa2f7" })
				set_hl(0, "DVal",    { fg = "#a9b1d6" })
				set_hl(0, "DFoot",   { fg = "#565f89", italic = true })
				set_hl(0, "DHide",   { blend = 100, nocombine = true })
				set_hl(0, "DI1",     { fg = "#9ece6a" })
				set_hl(0, "DI2",     { fg = "#e0af68" })
				set_hl(0, "DI3",     { fg = "#f7768e" })
				set_hl(0, "DI4",     { fg = "#7dcfff" })
				set_hl(0, "DI5",     { fg = "#bb9af7" })
				set_hl(0, "DI6",     { fg = "#ff9e64" })
				set_hl(0, "DI7",     { fg = "#7aa2f7" })
				set_hl(0, "DI8",     { fg = "#73daca" })
				-- stylua: ignore end
			end

			setup_hl()
			api.nvim_create_autocmd("ColorScheme", { group = group, callback = setup_hl })

			-- ══════════════════════════════════════════════════════
			-- CACHED SYSTEM INFO
			--
			-- Each getter caches its result on first call. The cache
			-- is never invalidated — system info doesn't change
			-- during a single Neovim session.
			-- ══════════════════════════════════════════════════════

			---@type string|nil Cached OS display string with icon
			---@private
			local cached_os_display

			---@type string|nil Cached environment tags string
			---@private
			local cached_env_tags

			---@type string|nil Cached "enabled/total" language count string
			---@private
			local cached_langs_count

			---@type string|nil Cached formatted runtimes display string
			---@private
			local cached_runtimes

			--- Get a time-of-day greeting string.
			---
			--- Maps the current hour to a contextual greeting:
			--- - 00–05: "Night owl mode"
			--- - 06–11: "Good morning"
			--- - 12–17: "Good afternoon"
			--- - 18–23: "Good evening"
			---
			---@return string greeting Time-appropriate greeting
			---@private
			local function get_greeting()
				local h = tonumber(os.date("%H"))
				if h < 6 then
					return "Night owl mode"
				elseif h < 12 then
					return "Good morning"
				elseif h < 18 then
					return "Good afternoon"
				else
					return "Good evening"
				end
			end

			--- Get the OS display string with platform-specific icon.
			---
			--- On Linux, attempts to detect the distribution via `lsb_release`
			--- and uses distribution-specific icons (Ubuntu, Debian, Arch, etc.).
			--- Falls back to generic Linux icon if detection fails.
			---
			--- Result is cached after first call.
			---
			---@return string os_display OS name with Nerd Font icon prefix
			---@private
			local function get_os_display()
				if cached_os_display then return cached_os_display end

				local result
				if platform.is_mac then
					result = ic("os", "Mac", { after = true }) .. "macOS"
				elseif platform.is_windows then
					result = ic("os", "Windows", { after = true }) .. "Windows"
				elseif platform.is_linux then
					if platform:has_executable("lsb_release") then
						local d = fn.system("lsb_release -si 2>/dev/null"):gsub("%s+$", ""):lower()
						---@type table<string, string>
						local m = {
							ubuntu = "Ubuntu",
							debian = "Debian",
							fedora = "Fedora",
							arch = "Arch",
							centos = "Centos",
							alpine = "Alpine",
							nixos = "Nixos",
						}
						if m[d] then result = ic("os", m[d], { after = true }) .. utils.capitalize(d) end
					end
					result = result or (ic("os", "Linux", { after = true }) .. "Linux")
				elseif platform.is_bsd then
					result = ic("os", "Freebsd", { after = true }) .. "FreeBSD"
				else
					result = platform.os
				end

				cached_os_display = result
				return result
			end

			--- Get environment tags string (SSH, WSL, Docker, Tmux, etc.).
			---
			--- Builds a space-separated string of active environment indicators.
			--- Returns `"Local"` if no special environment is detected.
			---
			--- Result is cached after first call.
			---
			---@return string env_tags Formatted environment tags or `"Local"`
			---@private
			local function get_env_tags()
				if cached_env_tags then return cached_env_tags end

				---@type string[]
				local t = {}
				if platform.is_ssh then t[#t + 1] = ic("app", "Ssh", { after = true }) .. "SSH" end
				if platform.is_wsl then t[#t + 1] = ic("os", "Linux", { after = true }) .. "WSL" end
				if platform.is_docker then t[#t + 1] = ic("app", "Docker", { after = true }) .. "Docker" end
				if platform.is_proxmox then t[#t + 1] = ic("dev", "Container", { after = true }) .. "Proxmox" end
				if platform.is_vps then t[#t + 1] = ic("dev", "Cloud", { after = true }) .. "VPS" end
				if platform.is_tmux then t[#t + 1] = ic("app", "Tmux", { after = true }) .. "Tmux" end
				if platform.is_zellij then t[#t + 1] = "Zellij" end

				cached_env_tags = #t > 0 and table.concat(t, " ") or "Local"
				return cached_env_tags
			end

			--- Count enabled LazyVim extras.
			---
			--- Reads from `lazyvim_extras.extras` and `lazyvim_extras` settings
			--- keys, deduplicates, and returns the total count as a string.
			---
			---@return string count Number of enabled extras as a string
			---@private
			local function get_extras_count()
				local e = settings:get("lazyvim_extras.extras", {})
				local r = settings:get("lazyvim_extras", {})
				---@type table<string, true>
				local seen = {}
				local c = 0
				for _, id in ipairs(e) do
					if type(id) == "string" then
						seen[id] = true
						c = c + 1
					end
				end
				for _, id in ipairs(r) do
					if type(id) == "string" and not seen[id] then c = c + 1 end
				end
				return tostring(c)
			end

			--- Count available and enabled languages from `lua/langs/`.
			---
			--- Scans the `lua/langs/` directory for `.lua` files (excluding
			--- `init.lua` and `_*` prefixed files), then cross-references with
			--- `settings.languages.enabled` to build a "enabled/total" string.
			---
			--- Result is cached after first call.
			---
			---@return string count Formatted "enabled/total" string (e.g. `"8/12"`)
			---@private
			local function get_langs_count()
				if cached_langs_count then return cached_langs_count end

				local total_count = 0
				---@type table<string, true>
				local available = {}
				local langs_dir = platform:path_join(platform.config_dir, "lua", "langs")

				if utils.dir_exists(langs_dir) then
					for _, filepath in ipairs(fn.globpath(langs_dir, "*.lua", false, true)) do
						local filename = fn.fnamemodify(filepath, ":t")
						if filename ~= "init.lua" and not vim.startswith(filename, "_") then
							available[filename:gsub("%.lua$", "")] = true
							total_count = total_count + 1
						end
					end
				end

				local enabled = settings:get("languages.enabled", {})
				---@type table<string, true>
				local seen = {}
				local enabled_count = 0
				if type(enabled) == "table" then
					for _, lang in ipairs(enabled) do
						if available[lang] and not seen[lang] then
							seen[lang] = true
							enabled_count = enabled_count + 1
						end
					end
				end

				cached_langs_count = fmt("%d/%d", enabled_count, total_count)
				return cached_langs_count
			end

			--- Build a display string of all installed runtimes with icons.
			---
			--- Dynamically iterates over **all** runtimes detected by
			--- `core/platform.lua` (populated from `RUNTIME_EXECUTABLES`).
			--- For each installed runtime, attempts to find a matching icon
			--- in `icons.app` using the capitalized runtime name as key.
			---
			--- Icon resolution:
			--- - `"go"`     → `icons.app["Go"]`     → `""` → `" Go"`
			--- - `"python"` → `icons.app["Python"]`  → `""` → `" Python"`
			--- - `"gcc"`    → `icons.app["Gcc"]`     → `nil` → `"Gcc"` (no icon)
			---
			--- Adding a new runtime requires **only** a change in
			--- `core/platform.lua` (RUNTIME_EXECUTABLES). Adding its icon
			--- requires **only** a change in `core/icons.lua` (icons.app).
			--- This function picks up both automatically.
			---
			--- Result is cached after first call.
			---
			---@return string runtimes Formatted runtime display string
			---@private
			local function get_runtimes()
				if cached_runtimes then return cached_runtimes end
				if not platform.runtimes then
					cached_runtimes = ""
					return cached_runtimes
				end

				-- Collect installed runtimes and sort for deterministic display
				---@type string[]
				local names = {}
				for name, installed in pairs(platform.runtimes) do
					if installed then names[#names + 1] = name end
				end
				table.sort(names)

				-- Build display items — icon from icons.app when available
				---@type string[]
				local items = {}
				for _, name in ipairs(names) do
					---@type string
					local display = utils.capitalize(name)
					-- icons.app keys are capitalized: "Go", "Python", "Rust", etc.
					if icons.app and icons.app[display] then
						items[#items + 1] = ic("app", display, { after = true }) .. display
					else
						items[#items + 1] = display
					end
				end

				cached_runtimes = #items > 0 and table.concat(items, " ") or ""
				return cached_runtimes
			end

			-- ══════════════════════════════════════════════════════
			-- TEXT HELPERS
			--
			-- Utility functions for string padding and centering.
			-- Used by the segment-based line builder and action
			-- item rendering.
			-- ══════════════════════════════════════════════════════

			--- Right-pad a string to a target display width.
			---
			--- Uses `strdisplaywidth` for accurate multi-byte character width.
			--- If the string is already at or beyond the target, returns as-is.
			---
			---@param s string Input string
			---@param target_w integer Target display width
			---@return string padded Padded string
			---@private
			local function dpad(s, target_w)
				local cur = dw(s)
				return cur >= target_w and s or (s .. rep(" ", target_w - cur))
			end

			--- Center a string within a given width.
			---
			--- Prepends spaces to center the string. If the string is already
			--- at or beyond the target width, returns as-is.
			---
			---@param s string Input string
			---@param w integer Container width
			---@return string centered Centered string with leading spaces
			---@private
			local function ctr(s, w)
				local cur = dw(s)
				return cur >= w and s or (rep(" ", math.floor((w - cur) / 2)) .. s)
			end

			-- ══════════════════════════════════════════════════════
			-- GRADIENT ENGINE
			--
			-- Applies per-character rainbow gradient highlighting
			-- to ASCII art lines. Uses efficient UTF-8 byte iteration
			-- to find non-space character positions, then maps each
			-- position to a gradient color index.
			-- ══════════════════════════════════════════════════════

			--- Apply rainbow gradient highlighting to a single buffer line.
			---
			--- Iterates over UTF-8 characters in the line, collects positions
			--- of non-space characters, then distributes the gradient palette
			--- evenly across those positions.
			---
			---@param buf integer Buffer handle
			---@param li integer 0-indexed line number
			---@param line string Line content (raw bytes)
			---@private
			local function grad_line(buf, li, line)
				---@type { [1]: integer, [2]: integer }[]
				local pos = {}
				local i = 1
				while i <= #line do
					local b = line:byte(i)
					local len = b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
					if b ~= 0x20 then pos[#pos + 1] = { i - 1, i - 1 + len } end
					i = i + len
				end
				local n = #pos
				if n == 0 then return end
				for idx, p in ipairs(pos) do
					local r = n > 1 and ((idx - 1) / (n - 1)) or 0.5
					local gi = math.max(1, math.min(GRAD_N, math.floor(r * (GRAD_N - 1)) + 1))
					buf_add_hl(buf, ns, "DG" .. gi, li, p[1], p[2])
				end
			end

			-- ══════════════════════════════════════════════════════
			-- COMMAND DETECTION
			--
			-- Helpers to determine command behavior for dashboard
			-- buffer management: float commands keep the dashboard
			-- open, picker commands defer dashboard cleanup.
			-- ══════════════════════════════════════════════════════

			--- Check if a command opens a floating window.
			---
			---@param cmd string Vim command string
			---@return boolean is_float `true` if the command is in FLOAT_COMMANDS
			---@private
			local function is_float_command(cmd)
				local first = cmd:match("^(%S+)")
				return first and FLOAT_COMMANDS[first] or false
			end

			--- Check if a command opens a picker/fuzzy-finder UI.
			---
			---@param cmd string Vim command string
			---@return boolean is_picker `true` if the command starts with a known picker prefix
			---@private
			local function is_picker_command(cmd)
				for _, prefix in ipairs(PICKER_PREFIXES) do
					if cmd:sub(1, #prefix) == prefix then return true end
				end
				return false
			end

			-- ══════════════════════════════════════════════════════
			-- SEGMENT-BASED LINE BUILDER
			--
			-- A builder pattern for constructing dashboard content.
			-- Tracks lines, highlight regions, gradient lines, and
			-- keymap bindings in a single pass. The built data is
			-- applied to a buffer in the render function.
			-- ══════════════════════════════════════════════════════

			---@class DashBuilder
			---@field lines string[] Collected line strings
			---@field hls { [1]: integer, [2]: string, [3]: integer, [4]: integer }[] Highlight regions: { line, hl_group, col_start, col_end }
			---@field grads integer[] 0-indexed line indices that need gradient
			---@field keymap table<string, string> Key → command mapping for buffer-local keymaps
			local B = {}

			--- Create a new DashBuilder instance.
			---
			---@return DashBuilder builder Fresh builder with empty state
			function B.new()
				return setmetatable({ lines = {}, hls = {}, grads = {}, keymap = {} }, { __index = B })
			end

			--- Append a raw line string.
			---
			---@param s string Line content
			function B:raw(s)
				self.lines[#self.lines + 1] = s
			end

			--- Append an empty line.
			function B:blank()
				self:raw("")
			end

			--- Append a line built from highlighted segments.
			---
			--- Each segment is a `{ text, hl_group }` pair where `hl_group`
			--- can be `nil` for unhighlighted text. Supports centering and
			--- left-padding via `opts`.
			---
			---@param segments { [1]: string, [2]: string|nil }[] List of `{ text, hl_group }` pairs
			---@param opts? { center?: boolean, width?: integer, pad?: integer } Positioning options
			---@return integer li 0-indexed line number of the appended line
			function B:seg(segments, opts)
				opts = opts or {}
				local plain = ""
				for _, s in ipairs(segments) do
					plain = plain .. s[1]
				end

				local prefix = ""
				if opts.center then
					local W = opts.width or vim.o.columns
					prefix = rep(" ", math.max(0, math.floor((W - dw(plain)) / 2)))
				elseif opts.pad then
					prefix = rep(" ", opts.pad)
				end

				self:raw(prefix .. plain)
				local li = #self.lines - 1

				local byte_off = #prefix
				for _, s in ipairs(segments) do
					local seg_bytes = #s[1]
					if s[2] then self.hls[#self.hls + 1] = { li, s[2], byte_off, byte_off + seg_bytes } end
					byte_off = byte_off + seg_bytes
				end
				return li
			end

			--- Append a line to be gradient-highlighted.
			---
			--- Optionally centers the string first. The line index is recorded
			--- in `self.grads` for processing by `grad_line()` during render.
			---
			---@param s string Line content
			---@param opts? { center?: boolean, width?: integer } Centering options
			function B:grad(s, opts)
				if opts and opts.center then s = ctr(s, opts.width or vim.o.columns) end
				self:raw(s)
				self.grads[#self.grads + 1] = #self.lines - 1
			end

			--- Mark the last appended line for full-line highlighting.
			---
			--- Adds a highlight entry with `col_end = -1` (end of line).
			---
			---@param hl_group string Highlight group to apply
			function B:hl_line(hl_group)
				self.hls[#self.hls + 1] = { #self.lines - 1, hl_group, 0, -1 }
			end

			-- ══════════════════════════════════════════════════════
			-- ACTION ITEM HELPERS
			--
			-- Functions to build segment lists for category headers,
			-- action items (icon + desc + key), and empty column
			-- placeholders. Used by the two-column layout builder.
			-- ══════════════════════════════════════════════════════

			--- Build segments for a single action item (icon + description + key).
			---
			---@param item { icon: string, desc: string, key: string } Action item data
			---@param col_w integer Column width for padding
			---@return { [1]: string, [2]: string|nil }[] segments Highlighted segments
			---@private
			local function item_segments(item, col_w)
				local icon_s = " " .. item.icon .. " "
				local avail = col_w - dw(icon_s) - dw(item.key) - 1
				return {
					{ icon_s, "DIcon" },
					{ dpad(item.desc, avail), "DDesc" },
					{ " ", nil },
					{ item.key, "DKey" },
				}
			end

			--- Build segments for a category title.
			---
			---@param title string Category title with icon
			---@return { [1]: string, [2]: string|nil }[] segments Single segment with DCat highlight
			---@private
			local function cat_segments(title)
				return { { title, "DCat" } }
			end

			--- Build empty segments for column padding.
			---
			---@param col_w integer Column width (all spaces)
			---@return { [1]: string, [2]: nil }[] segments Single unhighlighted segment
			---@private
			local function empty_segments(col_w)
				return { { rep(" ", col_w), nil } }
			end

			-- ══════════════════════════════════════════════════════
			-- ACTIONS
			--
			-- Static action definitions built once and reused across
			-- re-renders. Split into left column (files & config)
			-- and right column (enterprise tools & utilities).
			-- ══════════════════════════════════════════════════════

			--- Build the two-column action definitions.
			---
			--- Returns a table with `left` and `right` keys, each containing
			--- a list of categories. Each category has a `title` and a list
			--- of `items` with icon, description, key binding, and command.
			---
			---@return { left: table[], right: table[] } actions Two-column action layout
			---@private
			local function get_actions()
				-- stylua: ignore start
				return {
					left = {
						{
							title = ic("documents", "FileFind", { after = true }) .. "Files & Search",
							items = {
								{ icon = ic("documents", "FileFind"), desc = "Find File",       key = "f", cmd = "lua Snacks.dashboard.pick('files')" },
								{ icon = ic("ui", "NewFile"),         desc = "New File",        key = "n", cmd = "ene | startinsert" },
								{ icon = ic("ui", "Search"),          desc = "Grep Search",     key = "g", cmd = "lua Snacks.dashboard.pick('live_grep')" },
								{ icon = ic("ui", "History"),         desc = "Recent Files",    key = "r", cmd = "lua Snacks.dashboard.pick('oldfiles')" },
								{ icon = ic("ui", "Lightbulb"),       desc = "Save Session",    key = "S", cmd = "Persisted save" },
								{ icon = ic("ui", "BookMark"),        desc = "Restore Session", key = "s", cmd = "Persisted load_last" },
							},
						},
						{
							title = ic("ui", "Gear", { after = true }) .. "Config & Tools",
							items = {
								{ icon = ic("ui", "Gear"),          desc = "Settings",     key = "t", cmd = "Settings" },
								{ icon = ic("ui", "Pencil"),        desc = "Edit Config",  key = "E", cmd = "NvimEditConfig" },
								{ icon = ic("misc", "Lazy"),        desc = "Lazy",         key = "l", cmd = "Lazy" },
								{ icon = ic("misc", "Mason"),       desc = "Mason",        key = "M", cmd = "Mason" },
								{ icon = ic("diagnostics", "Info"), desc = "Health Check", key = "h", cmd = "NvimHealth" },
								{ icon = ic("misc", "Lsp"),         desc = "LSP Info",     key = "L", cmd = "NvimLspInfo" },
							},
						},
					},
					right = {
						{
							title = ic("ui", "Rocket", { after = true }) .. "Nvim Enterprise",
							items = {
								{ icon = ic("ui", "Dashboard"),    desc = "Nvim Info",      key = "i", cmd = "NvimInfo" },
								{ icon = ic("misc", "Lazy"),       desc = "LazyVim Extras", key = "x", cmd = "NvimExtras" },
								{ icon = ic("misc", "Treesitter"), desc = "Languages",      key = "a", cmd = "NvimLanguages" },
								{ icon = ic("ui", "List"),         desc = "All Commands",   key = "c", cmd = "NvimCommands" },
								{ icon = ic("ui", "Rocket"),       desc = "Performance",    key = "P", cmd = "NvimPerf" },
								{ icon = ic("ui", "User"),         desc = "Switch User",    key = "u", cmd = "UserSwitch" },
							},
						},
						{
							title = ic("ui", "Terminal", { after = true }) .. "Utilities",
							items = {
								{ icon = ic("ui", "Rocket"),    desc = "Restart Nvim",   key = "R", cmd = "NvimRestart" },
								{ icon = ic("ui", "Lock"),      desc = "Git Protocol",   key = "G", cmd = "NvimGitProtocol" },
								{ icon = ic("ui", "File"),      desc = "View Log",       key = "V", cmd = "NvimLogView" },
								{ icon = ic("ui", "BoldClose"), desc = "Clear Log",      key = "C", cmd = "NvimLogClear" },
								{ icon = ic("misc", "Vim"),     desc = "Neovim Version", key = "v", cmd = "NvimVersion" },
								{ icon = ic("ui", "SignOut"),   desc = "Quit Neovim",    key = "q", cmd = "qa" },
							},
						},
					},
				}
				-- stylua: ignore end
			end

			-- ══════════════════════════════════════════════════════
			-- MAIN RENDER
			--
			-- Builds the complete dashboard content using the segment
			-- builder, creates a scratch buffer, applies highlights
			-- and gradient, sets buffer/window options, and registers
			-- buffer-local keymaps and lifecycle autocmds.
			-- ══════════════════════════════════════════════════════

			--- Render the dashboard into a new scratch buffer.
			---
			--- Creates a fully-formatted dashboard with:
			--- 1. Gradient ASCII art header
			--- 2. System info lines (version, date, OS, env, runtimes, AI)
			--- 3. Two-column action layout with keymaps
			--- 4. Lazy.nvim stats footer
			---
			--- The buffer is set as the current buffer with all editor
			--- chrome disabled. Buffer-local keymaps are registered for
			--- each action item plus `<Esc>` to close.
			---
			--- Lifecycle autocmds handle cursor restoration on BufLeave
			--- and buffer cleanup on BufHidden.
			---@private
			local function render()
				local b = B.new()
				local W = vim.o.columns
				local COL_W = LAYOUT.col_w
				local GAP_W = LAYOUT.gap_w
				local LPAD = math.max(2, math.floor((W - TOTAL_W) / 2))

				-- ── Header ───────────────────────────────────
				b:blank()
				for _, a in ipairs(ASCII_ART) do
					b:grad(a, { center = true, width = W })
				end
				b:grad(ctr("E N T E R P R I S E   E D I T I O N", W))
				b:blank()

				-- ── Info lines ────────────────────────────────
				b:seg({
					{ ic("misc", "Vim", { after = true }), "DI1" },
					{ "v" .. (_G.NvimConfig.version or "1.0.0"), "DVal" },
					{ "    ", nil },
					{ ic("ui", "Calendar", { after = true }), "DI2" },
					{ os.date("%A %d %B %Y"), "DVal" },
					{ "    ", nil },
					{ ic("status", "Clock", { after = true }), "DI6" },
					{ os.date("%H:%M"), "DVal" },
				}, { center = true, width = W })

				b:seg({
					{ ic("misc", "Yoga", { after = true }), "DI2" },
					{ get_greeting() .. ", ", "DDim" },
					{ settings:get("active_user", "default"), "DAccent" },
					{ "    ", nil },
					{ get_os_display(), "DVal" },
					{ "    ", nil },
					{ ic("ui", "Terminal", { after = true }), "DI5" },
					{ get_env_tags(), "DVal" },
				}, { center = true, width = W })

				b:blank()

				b:seg({
					{ ic("ui", "Lock", { after = true }), "DI3" },
					{ settings:get("performance.git_protocol", "https"):lower(), "DVal" },
					{ "    ", nil },
					{ ic("misc", "Lazy", { after = true }), "DI5" },
					{ get_extras_count() .. " extras", "DVal" },
					{ "    ", nil },
					{ ic("misc", "Treesitter", { after = true }), "DI1" },
					{ get_langs_count() .. " langs", "DVal" },
					{ "    ", nil },
					{ ic("ui", "Art", { after = true }), "DI7" },
					{ settings:get("ui.colorscheme", "habamax"), "DAccent" },
				}, { center = true, width = W })

				-- ── Runtimes (dynamic from platform + icons) ─
				local rt = get_runtimes()
				if rt ~= "" then
					b:seg({
						{ ic("ui", "Code", { after = true }), "DI8" },
						{ rt, "DDim" },
					}, { center = true, width = W })
				end

				-- ── AI provider (if enabled) ─────────────────
				if settings:get("ai.enabled", false) then
					b:seg({
						{ ic("misc", "AI", { after = true }), "DI5" },
						{ "AI: ", "DDim" },
						{ utils.capitalize(settings:get("ai.provider", "none")), "DAccent" },
					}, { center = true, width = W })
				end

				-- ── Separator ────────────────────────────────
				b:blank()
				b:raw(rep(" ", LPAD) .. rep("─", TOTAL_W))
				b:hl_line("DSep")
				b:blank()

				-- ── Two-column actions ───────────────────────
				local actions = get_actions()

				--- Build a flat list of entries from category groups.
				---@param cats table[] List of categories with title and items
				---@return table[] entries Flat list of { type, title?, item? }
				local function build_entries(cats)
					---@type table[]
					local entries = {}
					for ci, cat in ipairs(cats) do
						entries[#entries + 1] = { type = "cat", title = cat.title }
						entries[#entries + 1] = { type = "blank" }
						for _, it in ipairs(cat.items) do
							entries[#entries + 1] = { type = "item", item = it }
							b.keymap[it.key] = it.cmd
						end
						if ci < #cats then entries[#entries + 1] = { type = "blank" } end
					end
					return entries
				end

				local left_entries = build_entries(actions.left)
				local right_entries = build_entries(actions.right)

				-- Equalize column heights
				local max_h = math.max(#left_entries, #right_entries)
				while #left_entries < max_h do
					left_entries[#left_entries + 1] = { type = "blank" }
				end
				while #right_entries < max_h do
					right_entries[#right_entries + 1] = { type = "blank" }
				end

				---@type { [1]: string, [2]: nil }
				local gap_seg = { rep(" ", GAP_W), nil }

				for row = 1, max_h do
					local le = left_entries[row]
					local re = right_entries[row]

					local left_segs = le.type == "cat" and cat_segments(le.title)
						or le.type == "item" and item_segments(le.item, COL_W)
						or empty_segments(COL_W)

					local right_segs = re.type == "cat" and cat_segments(re.title)
						or re.type == "item" and item_segments(re.item, COL_W)
						or empty_segments(COL_W)

					-- Pad columns to COL_W
					for _, segs in ipairs({ left_segs, right_segs }) do
						local plain = ""
						for _, s in ipairs(segs) do
							plain = plain .. s[1]
						end
						local cur = dw(plain)
						if cur < COL_W then segs[#segs + 1] = { rep(" ", COL_W - cur), nil } end
					end

					-- Combine: padding + left + gap + right
					---@type { [1]: string, [2]: string|nil }[]
					local all = { { rep(" ", LPAD), nil } }
					for _, s in ipairs(left_segs) do
						all[#all + 1] = s
					end
					all[#all + 1] = gap_seg
					for _, s in ipairs(right_segs) do
						all[#all + 1] = s
					end

					b:seg(all)
				end

				-- ── Footer ───────────────────────────────────
				b:blank()
				b:raw(rep(" ", LPAD) .. rep("─", TOTAL_W))
				b:hl_line("DSep")

				local lazy_ok, lazy = pcall(require, "lazy")
				if lazy_ok then
					local stats_ok, st = pcall(lazy.stats)
					if stats_ok and st then
						b:seg({
							{ ic("ui", "Rocket", { after = true }), "DI6" },
							{ fmt("Neovim loaded %d/%d plugins in %.1fms", st.loaded, st.count, st.startuptime), "DFoot" },
						}, { center = true, width = W })
					end
				end
				b:blank()

				-- ── Create buffer ─────────────────────────────
				local buf = api.nvim_create_buf(false, true)

				-- Strip trailing whitespace from all lines
				for i = 1, #b.lines do
					b.lines[i] = b.lines[i]:gsub("%s+$", "")
				end

				api.nvim_buf_set_lines(buf, 0, -1, false, b.lines)

				-- Apply gradient highlighting to header lines
				for _, li in ipairs(b.grads) do
					if b.lines[li + 1] then grad_line(buf, li, b.lines[li + 1]) end
				end

				-- Apply segment highlights via extmarks
				for _, h in ipairs(b.hls) do
					buf_add_hl(buf, ns, h[2], h[1], h[3], h[4])
				end

				-- ── Buffer options ─────────────────────────────
				vim.bo[buf].modifiable = false
				vim.bo[buf].bufhidden = "wipe"
				vim.bo[buf].buftype = "nofile"
				vim.bo[buf].swapfile = false
				vim.bo[buf].filetype = "dashboard"

				api.nvim_set_current_buf(buf)
				local win = api.nvim_get_current_win()

				-- Disable all editor chrome in the dashboard window
				vim.wo[win].number = false
				vim.wo[win].relativenumber = false
				vim.wo[win].signcolumn = "no"
				vim.wo[win].foldcolumn = "0"
				vim.wo[win].cursorline = false
				vim.wo[win].cursorcolumn = false
				vim.wo[win].colorcolumn = ""
				vim.wo[win].spell = false
				vim.wo[win].list = false
				vim.wo[win].wrap = false
				vim.wo[win].statuscolumn = ""

				-- Hide cursor in dashboard buffer
				local orig_gc = vim.o.guicursor
				vim.o.guicursor = "a:DHide"

				-- ── Keybindings ───────────────────────────────
				for key, cmd in pairs(b.keymap) do
					vim.keymap.set("n", key, function()
						if not is_float_command(cmd) then vim.o.guicursor = orig_gc end
						vim.cmd(cmd)
					end, { buffer = buf, silent = true, nowait = true })
				end

				vim.keymap.set("n", "<Esc>", function()
					vim.o.guicursor = orig_gc
					vim.cmd("enew")
				end, { buffer = buf, silent = true })

				-- ── Buffer lifecycle ──────────────────────────
				api.nvim_create_autocmd("BufLeave", {
					group = group,
					buffer = buf,
					callback = function()
						vim.o.guicursor = orig_gc
						vim.schedule(function()
							local cur_win = api.nvim_get_current_win()
							local cur_buf = api.nvim_get_current_buf()
							if cur_buf ~= buf and api.nvim_win_is_valid(cur_win) then
								local ft = vim.bo[cur_buf].filetype
								if ft ~= "TelescopePrompt" and ft ~= "lazy" and ft ~= "mason" then
									vim.wo[cur_win].number = settings:get("editor.number", true)
									vim.wo[cur_win].relativenumber = settings:get("editor.relative_number", true)
									vim.wo[cur_win].signcolumn = settings:get("editor.sign_column", "yes")
									vim.wo[cur_win].cursorline = settings:get("editor.cursor_line", true)
									vim.wo[cur_win].list = true
								end
							end
						end)
					end,
				})

				api.nvim_create_autocmd("BufHidden", {
					group = group,
					buffer = buf,
					once = true,
					callback = function()
						vim.schedule(function()
							if api.nvim_buf_is_valid(buf) then pcall(api.nvim_buf_delete, buf, { force = true }) end
						end)
					end,
				})
			end

			-- ══════════════════════════════════════════════════════
			-- ENTRY POINT
			--
			-- VimEnter autocmd that triggers the dashboard render
			-- when Neovim starts with no file arguments. Also
			-- registers the :Dashboard user command for manual
			-- invocation.
			-- ══════════════════════════════════════════════════════

			api.nvim_create_autocmd("VimEnter", {
				group = group,
				callback = function()
					if fn.argc() == 0 then
						local bl = api.nvim_buf_get_lines(0, 0, -1, false)
						local empty = #bl <= 1 and (bl[1] or "") == ""
						local one_buf = #vim.tbl_filter(function(bf)
							return vim.bo[bf].buflisted
						end, api.nvim_list_bufs()) <= 1
						if empty and one_buf then vim.schedule(render) end
					end
				end,
			})

			api.nvim_create_user_command("Dashboard", render, {
				desc = "Open Nvim Enterprise Dashboard",
			})
		end,
	},
}
