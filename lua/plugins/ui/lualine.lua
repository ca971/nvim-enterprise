---@file lua/plugins/ui/lualine.lua
---@description Lualine — Enterprise-grade statusline information center
---@module "plugins.ui.lualine"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Plugin guard, AI provider, global_statusline preference
---@see core.platform              OS detection, SSH/Docker/WSL/Tmux/GUI flags, runtimes
---@see core.icons                 Unified icon registry (powerline, git, diagnostics, ui, misc)
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
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  ╭─A─╮◗──B──◖───C───────────────│─X─│─X─│◗──Y──◖╭─Z──╮           │    ║
--- ║  │  │MODE│ GIT   FILE+DIAG+NOICE     STATUS    META   DATE  │       │    ║
--- ║  │  ╰───╯◖─────◗────────────────────│───│───│◖─────◗╰────╯          │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Separator Strategy:                                                     ║
--- ║  ├─ A (mode)     : Round bubble    ╭───╮                                 ║
--- ║  ├─ B (git)      : Powerline       ◗───◖                                 ║
--- ║  ├─ C (file)     : Open/flowing     ───                                  ║
--- ║  ├─ X (status)   : Thin dividers    │ │                                  ║
--- ║  ├─ Y (meta)     : Powerline       ◗───◖                                 ║
--- ║  └─ Z (datetime) : Round bubble    ╭───╮                                 ║
--- ║                                                                          ║
--- ║  Section Contents:                                                       ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  A — Mode                                                        │    ║
--- ║  │  └─ Mode text + OS icon from core.platform                       │    ║
--- ║  │                                                                  │    ║
--- ║  │  B — Git                                                         │    ║
--- ║  │  ├─ Branch name (truncated at 20 chars)                          │    ║
--- ║  │  └─ Diff stats from gitsigns (added/modified/removed)            │    ║
--- ║  │                                                                  │    ║
--- ║  │  C — File                                                        │    ║
--- ║  │  ├─ LSP diagnostics (error/warn/info/hint)                       │    ║
--- ║  │  ├─ Filetype icon (icon_only)                                    │    ║
--- ║  │  ├─ Filename with relative path                                  │    ║
--- ║  │  ├─ File size (human-readable)                                   │    ║
--- ║  │  └─ Noice command + mode display                                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  X — Status Center (12 components, conditional)                  │    ║
--- ║  │  ├─ Critical:  DAP status, macro recording, search count         │    ║
--- ║  │  ├─ Context:   session name, environment string                  │    ║
--- ║  │  ├─ Languages: venv, python version, node version, runtimes      │    ║
--- ║  │  ├─ AI:        copilot/supermaven/codeium + provider             │    ║
--- ║  │  ├─ User:      active namespace from NvimConfig.state            │    ║
--- ║  │  └─ Tools:     LSP names, lazy.nvim update count                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Y — Meta                                                        │    ║
--- ║  │  ├─ Indent style (spaces/tabs + width)                           │    ║
--- ║  │  ├─ Encoding (only if non-UTF-8)                                 │    ║
--- ║  │  ├─ File format (only if non-Unix)                               │    ║
--- ║  │  ├─ Word count (prose filetypes only)                            │    ║
--- ║  │  └─ Buffer number                                                │    ║
--- ║  │                                                                  │    ║
--- ║  │  Z — DateTime                                                    │    ║
--- ║  │  ├─ Scroll progress (%)                                          │    ║
--- ║  │  ├─ Cursor location (line:col)                                   │    ║
--- ║  │  └─ Date + time (DD.MM.YYYY HH:MM, 24h)                          │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Environment Detection (cached, from core.platform):                     ║
--- ║  ├─ SSH (hostname), Docker, WSL (distro), Proxmox, VPS                   ║
--- ║  ├─ Tmux, Zellij, GUI (Neovide/NvUI/FVim)                                ║
--- ║  └─ Nix shell, Devcontainer/Codespaces                                   ║
--- ║                                                                          ║
--- ║  Caching Strategy:                                                       ║
--- ║  ├─ env_string:     built once, cached for session lifetime              ║
--- ║  ├─ python_version: checked once per session                             ║
--- ║  ├─ node_version:   checked once per session                             ║
--- ║  ├─ hostname:       resolved once per session                            ║
--- ║  └─ lazy_updates:   TTL-based (300s refresh interval)                    ║
--- ║                                                                          ║
--- ║  Winbar:                                                                 ║
--- ║  └─ nvim-navic breadcrumbs (LSP document symbols)                        ║
--- ║                                                                          ║
--- ║  Extensions (12):                                                        ║
--- ║  neo-tree, lazy, toggleterm, trouble, quickfix, man,                     ║
--- ║  mason, nvim-dap-ui, fugitive, oil, overseer                             ║
--- ║                                                                          ║
--- ║  Defensive Design:                                                       ║
--- ║  • safe() wrapper: pcall on every component function                     ║
--- ║  • safe_cond() wrapper: pcall on every condition function                ║
--- ║  • icon() helper: fallback on missing icons (never crashes)              ║
--- ║  • Fallback icons table if core.icons is unavailable                     ║
--- ║  • setting() helper: pcall on settings access                            ║
--- ║  • All external requires (noice, dap, navic, etc.) wrapped in pcall      ║
--- ║  • Component results validated as strings before return                  ║
--- ║  • Color palette uses static hex values (theme-independent)              ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok and not settings:is_plugin_enabled("lualine") then return {} end
local augroup = require("core.utils").augroup

-- ═══════════════════════════════════════════════════════════════════════════
-- SAFE REQUIRES
--
-- Platform and icons are loaded defensively. If core.icons is unavailable
-- (e.g. during minimal startup), a hardcoded fallback table with all
-- required icon categories is used. This guarantees lualine never crashes
-- on missing icons regardless of startup order.
-- ═══════════════════════════════════════════════════════════════════════════

local platform_ok, platform = pcall(require, "core.platform")
local icons_ok, icons = pcall(require, "core.icons")

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
			Slant_left = "",
			Slant_right = "",
		},
		git = { Branch = "", Added = "+", Modified = "~", Removed = "-" },
		diagnostics = { Error = "E", Warn = "W", Info = "I", Hint = "H" },
		ui = { User = "U", Pencil = "●", Lock = "RO", NewFile = "N" },
		misc = { AI = "AI" },
		os = {},
	}
end

--- Safely access an icon from a table with fallback.
---@param tbl table|nil Icon category table (e.g. `icons.ui`)
---@param key string Icon key name (e.g. `"Branch"`)
---@param fallback string Fallback string if key is missing
---@return string icon The resolved icon or fallback
local function icon(tbl, key, fallback)
	if type(tbl) == "table" and tbl[key] ~= nil then return tbl[key] end
	return fallback or ""
end

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

-- ═══════════════════════════════════════════════════════════════════════════
-- SEPARATOR PALETTE
--
-- Pre-resolved separator characters from icons.powerline.
-- Used in section_separators, component_separators, and inline
-- separator overrides throughout the lualine configuration.
--
-- Types:
--   round_*:      ╭╮ bubble edges (sections A and Z)
--   arrow_*:       powerline arrows (sections B and Y)
--   thin_*:       │ thin dividers (within sections)
--   slant_*:       diagonal separators (available but not default)
--   round_thin_*:  rounded thin dividers (datetime component)
-- ═══════════════════════════════════════════════════════════════════════════

---@type table<string, string> Pre-resolved separator characters
local sep = {
	-- ── Section separators (outer edges) ──────────────────────────────
	round_l = icon(pw, "Round_left", ""),
	round_r = icon(pw, "Round_right", ""),
	arrow_l = icon(pw, "Left", ""),
	arrow_r = icon(pw, "Right", ""),
	slant_l = icon(pw, "Slant_left", ""),
	slant_r = icon(pw, "Slant_right", ""),

	-- ── Component separators (between items within a section) ─────────
	thin_l = icon(pw, "Thin_left", "│"),
	thin_r = icon(pw, "Thin_right", "│"),
	round_thin_l = icon(pw, "Round_thin_left", ""),
	round_thin_r = icon(pw, "Round_thin_right", ""),
	slant_thin_l = icon(pw, "Slant_left_thin", ""),
	slant_thin_r = icon(pw, "Slant_right_thin", ""),
}

-- ═══════════════════════════════════════════════════════════════════════════
-- SAFE HELPERS
--
-- Wrapper functions that ensure no component or condition ever throws
-- an error. Every function used in lualine sections goes through
-- safe() (for components) or safe_cond() (for conditions).
-- ═══════════════════════════════════════════════════════════════════════════

--- Safely read a setting value with fallback.
---
--- Wraps settings:get() in pcall to handle cases where
--- core.settings failed to load or the key doesn't exist.
---@param key string Settings key path (e.g. `"ui.global_statusline"`)
---@param default any Fallback value if setting is unavailable
---@return any value The setting value or default
---@private
local function setting(key, default)
	if not settings_ok or not settings then return default end
	local ok, val = pcall(settings.get, settings, key, default)
	return ok and val or default
end

--- Get the OS icon from core.platform.
---
--- Returns the platform-specific icon (e.g. 🐧 for Linux, 🍎 for macOS).
--- Falls back to empty string if platform is unavailable.
---@return string os_icon Platform icon or empty string
---@private
local function get_os_icon()
	if platform_ok and platform and platform.get_os_icon then
		local ok, result = pcall(platform.get_os_icon, platform)
		if ok and result then return result end
	end
	return ""
end

--- Wrap a component function in pcall for error resilience.
---
--- Returns a new function that calls `fn` inside pcall and returns
--- the result if successful, or `fallback` if it throws.
--- Every lualine component should go through this wrapper.
---@param fn function Component function returning a string
---@param fallback? string Fallback string on error (default: `""`)
---@return function wrapped Safe component function
---@private
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
--- true only if `fn` succeeds and returns true.
--- Every lualine `cond` should go through this wrapper.
---@param fn function Condition function returning a boolean
---@return function wrapped Safe condition function
---@private
local function safe_cond(fn)
	return function()
		local ok, result = pcall(fn)
		return ok and result == true
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- COLOR EXTRACTION HELPERS
--
-- Used by dynamic components (datetime) to derive colors from
-- the active colorscheme. Ensures visual consistency when switching
-- themes at runtime via :ColorScheme* commands.
-- ═══════════════════════════════════════════════════════════════════════════

--- Extract foreground hex color from a highlight group.
---@param name string Highlight group name
---@return string|nil hex Hex color or nil
---@private
local function hl_fg(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok and hl.fg then return string.format("#%06x", hl.fg) end
	return nil
end

--- Extract background hex color from a highlight group.
---@param name string Highlight group name
---@return string|nil hex Hex color or nil
---@private
local function hl_bg(name)
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok and hl.bg then return string.format("#%06x", hl.bg) end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DYNAMIC DATETIME COLORS
--
-- Derives datetime badge colors from the active colorscheme.
-- The accent color cascades through semantic highlight groups
-- to find the most appropriate prominent color:
--   Function → @keyword → Statement → DiagnosticInfo → fallback
--
-- This ensures the datetime badge looks good on ANY colorscheme:
--   • Catppuccin Mocha : blue badge   (#89b4fa)
--   • Tokyo Night      : blue badge   (#7aa2f7)
--   • Gruvbox           : aqua badge   (#8ec07c)
--   • Rose Pine         : rose badge   (#ebbcba)
--   • Kanagawa          : blue badge   (#7e9cd8)
--   • Dracula           : purple badge (#bd93f9)
--   • Everforest        : green badge  (#a7c080)
-- ═══════════════════════════════════════════════════════════════════════════

--- Get the accent color for the datetime badge.
---
--- Cascades through semantic highlight groups to find a prominent
--- accent color from the current colorscheme.
---@return string hex Accent hex color
---@private
local function datetime_accent()
	return hl_fg("Function") or hl_fg("@keyword") or hl_fg("Statement") or hl_fg("DiagnosticInfo") or "#94e2d5"
end

--- Override lualine_z highlight groups for ALL modes with accent colors.
---
--- This forces the entire section Z to use the accent bg (derived from
--- the active colorscheme's Function fg). Lualine's natural section
--- separator between Y and Z then creates a perfect powerline
--- transition automatically.
---
--- Overrides: lualine_z_{normal,insert,visual,replace,command,terminal,inactive}
---@return nil
---@private
local function apply_datetime_section_hl()
	local accent = datetime_accent()
	local dark = hl_bg("Normal") or "#1e1e2e"

	local modes = { "normal", "insert", "visual", "replace", "command", "terminal", "inactive" }
	for _, mode in ipairs(modes) do
		vim.api.nvim_set_hl(0, "lualine_z_" .. mode, {
			fg = dark,
			bg = accent,
			bold = true,
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CACHE
--
-- Performance cache for expensive operations. Prevents repeated
-- system calls, hostname lookups, and version checks on every
-- statusline refresh (every 1000ms).
--
-- Cache lifetime:
--   • env_string:      session lifetime (built once)
--   • python_version:  session lifetime (checked once)
--   • node_version:    session lifetime (checked once)
--   • hostname:        session lifetime (resolved once)
--   • lazy_updates:    TTL-based (refreshed every 300 seconds)
-- ═══════════════════════════════════════════════════════════════════════════

---@class LualineCache
---@field env_string string|nil    Cached environment indicator string
---@field env_built boolean        Whether env_string has been computed
---@field lazy_updates number|nil  Cached count of available lazy.nvim updates
---@field lazy_checked_at number   Timestamp of last lazy update check
---@field python_version string|nil Cached Python version string
---@field python_checked boolean   Whether Python version has been checked
---@field hostname string|nil      Cached hostname (first segment before dot)
---@field node_version string|nil  Cached Node.js version string
---@field node_checked boolean     Whether Node version has been checked
local cache = {
	env_string = nil,
	env_built = false,
	lazy_updates = nil,
	lazy_checked_at = 0,
	python_version = nil,
	python_checked = false,
	hostname = nil,
	node_version = nil,
	node_checked = false,
}

--- Time-to-live for lazy.nvim update cache (in seconds).
--- After this interval, the next statusline refresh will re-check
--- for available updates.
---@type integer
local LAZY_CACHE_TTL = 300

-- ═══════════════════════════════════════════════════════════════════════════
-- ENVIRONMENT STRING (from platform singleton)
--
-- Builds a cached string showing the current execution environment.
-- Detects: SSH, Docker, WSL, Proxmox, VPS, Tmux, Zellij, GUI,
-- Nix shell, and Devcontainer/Codespaces.
-- Built once per session — environment doesn't change at runtime.
-- ═══════════════════════════════════════════════════════════════════════════

--- Build a display string showing the current execution environment.
---
--- Detects runtime environment from core.platform flags and vim.env
--- variables. Result is cached for the entire session since these
--- conditions don't change at runtime.
---@return string env_string Space-separated environment indicators (may be empty)
---@private
local function build_env_string()
	if cache.env_built then return cache.env_string or "" end

	local envs = {}

	if not platform_ok or not platform then
		cache.env_built = true
		cache.env_string = ""
		return ""
	end

	-- ── Remote access ─────────────────────────────────────────────────
	if platform.is_ssh then
		if not cache.hostname then
			local ok, hn = pcall(vim.fn.hostname)
			cache.hostname = ok and (hn:match("^([^%.]+)") or hn) or "remote"
		end
		table.insert(envs, " " .. cache.hostname)
	end

	-- ── Containerization ──────────────────────────────────────────────
	if platform.is_docker then table.insert(envs, "󰡨 Docker") end

	-- ── Windows Subsystem for Linux ───────────────────────────────────
	if platform.is_wsl then
		local distro = vim.env.WSL_DISTRO_NAME
		table.insert(envs, "󰖳 WSL" .. (distro and (" " .. distro) or ""))
	end

	-- ── Server environments ───────────────────────────────────────────
	if platform.is_proxmox then table.insert(envs, "󰒋 Proxmox") end

	if platform.is_vps and not platform.is_docker then table.insert(envs, "☁ VPS") end

	-- ── Terminal multiplexers ─────────────────────────────────────────
	if platform.is_tmux then table.insert(envs, " Tmux") end

	if platform.is_zellij then table.insert(envs, " Zellij") end

	-- ── GUI clients ───────────────────────────────────────────────────
	if platform.is_gui then
		local gui_name = vim.g.neovide and "Neovide" or vim.g.nvui and "NvUI" or vim.g.fvim_loaded and "FVim" or "GUI"
		table.insert(envs, "󰖲 " .. gui_name)
	end

	-- ── Package managers / dev environments ───────────────────────────
	if vim.env.IN_NIX_SHELL or vim.env.NIX_STORE then table.insert(envs, "❄ Nix") end

	if vim.env.REMOTE_CONTAINERS or vim.env.CODESPACES then table.insert(envs, "󰜫 Devcontainer") end

	cache.env_string = table.concat(envs, "  ")
	cache.env_built = true
	return cache.env_string
end

-- ═══════════════════════════════════════════════════════════════════════════
-- DYNAMIC ENVIRONMENT COMPONENTS
--
-- Components that show per-project language runtime information.
-- These are conditional: they only appear when the relevant
-- filetype is active or the environment variable is set.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show the active Python virtual environment name.
---
--- Checks VIRTUAL_ENV, CONDA_DEFAULT_ENV, and PYENV_VIRTUAL_ENV.
--- Displays only the basename of the environment path.
---@return string component Formatted venv name or empty string
---@private
local function venv_component()
	local venv = vim.env.VIRTUAL_ENV or vim.env.CONDA_DEFAULT_ENV or vim.env.PYENV_VIRTUAL_ENV
	if venv then return "󰌠 " .. vim.fn.fnamemodify(venv, ":t") end
	return ""
end

--- Show the Python version (only for Python files).
---
--- Version is checked once per session and cached.
--- Tries `python3` first, falls back to `python`.
---@return string component Formatted Python version or empty string
---@private
local function python_version_component()
	if vim.bo.filetype ~= "python" then return "" end
	if not cache.python_checked then
		cache.python_checked = true
		local py = vim.fn.exepath("python3") ~= "" and "python3" or "python"
		if vim.fn.executable(py) == 1 then
			local ver = vim.fn.system(py .. " --version 2>&1"):gsub("Python%s+", ""):gsub("%s+", "")
			if ver and not ver:find("not found") and not ver:find("error") then cache.python_version = ver end
		end
	end
	return cache.python_version and ("󰌠 " .. cache.python_version) or ""
end

--- Show the Node.js version (only for JS/TS files).
---
--- Version is checked once per session and cached.
--- Only displayed for javascript, typescript, vue, svelte filetypes.
---@return string component Formatted Node version or empty string
---@private
local function node_version_component()
	local js_fts = {
		javascript = true,
		typescript = true,
		typescriptreact = true,
		javascriptreact = true,
		vue = true,
		svelte = true,
	}
	if not js_fts[vim.bo.filetype] then return "" end
	if not cache.node_checked then
		cache.node_checked = true
		if vim.fn.executable("node") == 1 then
			local ver = vim.fn.system("node -v 2>/dev/null"):gsub("%s+", "")
			if ver ~= "" and not ver:find("not found") then cache.node_version = ver end
		end
	end
	return cache.node_version and ("󰎙 " .. cache.node_version) or ""
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TOOL COMPONENTS
--
-- Components that display information about development tools:
-- LSP servers, treesitter parsers, AI assistants, debugging,
-- sessions, search, macros, lazy.nvim updates, and more.
--
-- Every component returns a string (empty if inactive/unavailable).
-- All external requires are wrapped in pcall.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show active LSP client names for the current buffer.
---
--- Filters out copilot, null-ls, and none-ls (displayed elsewhere).
--- Truncates to "first_name +N" if the combined string exceeds 25 chars.
---@return string component Formatted LSP client list or empty string
---@private
local function lsp_component()
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	if #clients == 0 then return "" end

	local names = {}
	local ignored = { copilot = true, ["null-ls"] = true, ["none-ls"] = true }
	for _, client in ipairs(clients) do
		if not ignored[client.name] then names[#names + 1] = client.name end
	end
	if #names == 0 then return "" end

	local display = table.concat(names, ", ")
	if #display > 25 then display = names[1] .. " +" .. (#names - 1) end
	return " " .. display
end

--- Check if GitHub Copilot LSP client is attached to the current buffer.
---@return string status " " if active, empty string otherwise
---@private
local function copilot_status()
	local ok, clients = pcall(vim.lsp.get_clients, { name = "copilot", bufnr = 0 })
	if ok and #clients > 0 then return " " end
	local ok2, enabled = pcall(vim.api.nvim_call_function, "copilot#Enabled", {})
	if ok2 and enabled == 1 then return " " end
	return ""
end

--- Check if Supermaven AI is running.
---@return string status "󱙺" if active, empty string otherwise
---@private
local function supermaven_status()
	local ok, api = pcall(require, "supermaven-nvim.api")
	if ok and api.is_running() then return "󱙺" end
	return ""
end

--- Check Codeium AI status.
---@return string status Codeium status string with icon, or empty string
---@private
local function codeium_status()
	local ok, status = pcall(vim.api.nvim_call_function, "codeium#GetStatusString", {})
	if ok and status and vim.trim(status) ~= "" then return "󰘦 " .. vim.trim(status) end
	return ""
end

--- Aggregate AI assistant status from all providers.
---
--- Checks copilot, supermaven, codeium, and the settings-configured
--- AI provider. Combines all active providers into a single string.
---@return string component Space-separated AI status indicators
---@private
local function ai_component()
	local parts = {}
	local c = copilot_status()
	if c ~= "" then parts[#parts + 1] = c end
	local s = supermaven_status()
	if s ~= "" then parts[#parts + 1] = s end
	local d = codeium_status()
	if d ~= "" then parts[#parts + 1] = d end
	if setting("ai.enabled", false) then
		local provider = setting("ai.provider", "")
		if provider ~= "" and provider ~= "none" then parts[#parts + 1] = icon(mi, "AI", "🤖") .. " " .. provider end
	end
	return table.concat(parts, " ")
end

--- Show the active user namespace name.
---
--- Reads from _G.NvimConfig.state.active_user (set by settings_manager).
---@return string component Formatted user name with icon
---@private
local function user_component()
	local user = "default"
	if _G.NvimConfig and _G.NvimConfig.state then user = _G.NvimConfig.state.active_user or user end
	return icon(ui, "User", "U") .. " " .. user
end

--- Show macro recording indicator.
---
--- Displays "󰑋 REC @{register}" when actively recording a macro.
---@return string component Recording indicator or empty string
---@private
local function macro_component()
	local reg = vim.fn.reg_recording()
	if reg ~= "" then return "󰑋 REC @" .. reg end
	return ""
end

--- Show search match count (current/total).
---
--- Only displayed when hlsearch is active. Uses searchcount()
--- with a max of 999 matches and 250ms timeout.
---@return string component Formatted search count or empty string
---@private
local function search_component()
	if vim.v.hlsearch == 0 then return "" end
	local ok, count = pcall(vim.fn.searchcount, { maxcount = 999, timeout = 250 })
	if ok and count and count.total and count.total > 0 then
		return string.format(" %d/%d", count.current, count.total)
	end
	return ""
end

--- Show count of available lazy.nvim plugin updates.
---
--- Uses a TTL-based cache (300s) to avoid checking on every
--- statusline refresh. Only displays when updates are available.
---@return string component Update count with icon or empty string
---@private
local function lazy_updates_component()
	local now = (vim.uv or vim.loop).now() / 1000
	if cache.lazy_updates ~= nil and (now - cache.lazy_checked_at) < LAZY_CACHE_TTL then
		return cache.lazy_updates > 0 and ("󰏔 " .. cache.lazy_updates) or ""
	end
	local ok, lazy_status = pcall(require, "lazy.status")
	if ok and lazy_status.has_updates() then
		local num = tonumber(lazy_status.updates():match("%d+")) or 0
		cache.lazy_updates = num
		cache.lazy_checked_at = now
		return num > 0 and ("󰏔 " .. num) or ""
	end
	cache.lazy_updates = 0
	cache.lazy_checked_at = now
	return ""
end

--- Show DAP (Debug Adapter Protocol) session status.
---
--- Displays the current debug status when a DAP session is active.
---@return string component Debug status with icon or empty string
---@private
local function dap_component()
	local ok, dap = pcall(require, "dap")
	if not ok then return "" end
	local session = dap.session()
	if session then
		local status = dap.status()
		return "󰃤 " .. (status ~= "" and status or "active")
	end
	return ""
end

--- Show the active session name (auto-session or persisted).
---
--- Checks auto-session first, then persisted.nvim.
--- Displays only the basename of the session file.
---@return string component Session name with icon or empty string
---@private
local function session_component()
	local ok, auto_session = pcall(require, "auto-session.lib")
	if ok then
		local name = auto_session.current_session_name()
		if name and name ~= "" then return "󰆔 " .. vim.fn.fnamemodify(name, ":t") end
	end
	if vim.g.persisted_loaded_session then
		return "󰆔 " .. vim.fn.fnamemodify(vim.g.persisted_loaded_session, ":t:r")
	end
	return ""
end

--- Show the current indent style and width.
---
--- Displays "󰌒 {width}" for spaces or "󰌑 Tab:{width}" for tabs.
---@return string component Indent info string
---@private
local function indent_component()
	if vim.bo.expandtab then return "󰌒 " .. vim.bo.shiftwidth end
	return "󰌑 Tab:" .. vim.bo.tabstop
end

--- Show word count (for prose filetypes).
---
--- In visual mode, shows selected word count instead.
---@return string component Word count with icon or empty string
---@private
local function wordcount_component()
	local ok, wc = pcall(vim.fn.wordcount)
	if not ok then return "" end
	if wc.visual_words then return "󰈭 " .. wc.visual_words .. "w sel" end
	return "󰈭 " .. (wc.words or 0) .. "w"
end

--- Show the current file size in human-readable format.
---
--- Uses adaptive suffixes: B, KB, MB, GB.
---@return string component File size with icon or empty string
---@private
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
	return i == 1 and ("󰒋 " .. size .. "B") or string.format("󰒋 %.1f%s", size, suffixes[i])
end

--- Show the last noice.nvim command.
---@return string component Last command or empty string
---@private
local function noice_command()
	local ok, noice = pcall(require, "noice")
	if ok and noice.api.status.command.has() then return noice.api.status.command.get() end
	return ""
end

--- Show the current noice.nvim mode indicator.
---@return string component Mode indicator or empty string
---@private
local function noice_mode()
	local ok, noice = pcall(require, "noice")
	if ok and noice.api.status.mode.has() then return noice.api.status.mode.get() end
	return ""
end

--- Date + Time: DD.MM.YYYY HH:MM (24h).
--- Simple text — section Z highlight handles the badge colors.
---@return string datetime Formatted date and time string
---@private
local function datetime_component()
	return "󰃭 " .. os.date("%d.%m.%Y") .. " " .. os.date("%H:%M")
end

--- Show the current buffer number.
---@return string component Buffer number with icon
---@private
local function bufnr_component()
	return "󰓩 " .. vim.api.nvim_get_current_buf()
end

--- Show icons for installed language runtimes.
---
--- Reads runtime availability from core.platform.runtimes table.
--- Only shows icons (no version numbers) for compact display.
---@return string component Space-separated runtime icons or empty string
---@private
local function runtimes_component()
	if not platform_ok or not platform or not platform.runtimes then return "" end
	local rt_icons = {
		node = icons.app.Node,
		python = icons.app.Python,
		ruby = icons.app.Ruby,
		go = icons.app.Go,
		rust = icons.app.Rust,
		lua = icons.app.Lua,
		nix = icons.app.Nix,
		cpp = icons.app.Cpp,
		gpp = icons.app.Gpp,
		php = icons.app.Php,
	}
	local parts = {}
	for lang, installed in pairs(platform.runtimes) do
		if installed then parts[#parts + 1] = rt_icons[lang] or "•" end
	end
	return #parts > 0 and table.concat(parts, " ") or ""
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CONDITIONS
--
-- Boolean functions that control component visibility in lualine.
-- Each condition is wrapped in safe_cond() at the call site to
-- prevent errors from hiding the entire statusline.
--
-- Conditions are organized by category:
--   • Tool availability (LSP, treesitter, noice, DAP)
--   • Runtime state (recording, searching, debugging)
--   • Environment (session, env string, venv)
--   • Filetype checks (prose, python, JS/TS)
--   • Encoding/format anomalies (non-UTF-8, non-Unix)
-- ═══════════════════════════════════════════════════════════════════════════

---@class LualineConditions
---@field has_lsp fun(): boolean     LSP clients attached to current buffer
---@field is_recording fun(): boolean Macro recording is active
---@field is_searching fun(): boolean Highlight search is active
---@field is_debugging fun(): boolean DAP session is running
---@field has_noice_cmd fun(): boolean Noice has command to display
---@field has_noice_mode fun(): boolean Noice has mode to display
---@field has_lazy_updates fun(): boolean Lazy.nvim updates available
---@field is_prose fun(): boolean    Current filetype is prose/markup
---@field has_env fun(): boolean     Environment string is non-empty
---@field has_session fun(): boolean Session manager has active session
---@field has_ai fun(): boolean      At least one AI assistant is active
---@field has_venv fun(): boolean    Python virtual env is active
---@field is_python fun(): boolean   Current filetype is Python
---@field is_js_ts fun(): boolean    Current filetype is JS/TS family
---@field has_runtimes fun(): boolean At least one runtime detected
---@field has_ts fun(): boolean      Treesitter parser available for buffer
---@field non_utf8 fun(): boolean    File encoding is not UTF-8
---@field non_unix fun(): boolean    File format is not Unix (LF)
local cond = {
	-- ── Tool availability ─────────────────────────────────────────────
	has_lsp = function()
		return #vim.lsp.get_clients({ bufnr = 0 }) > 0
	end,
	has_noice_cmd = function()
		local ok, noice = pcall(require, "noice")
		return ok and noice.api.status.command.has()
	end,
	has_noice_mode = function()
		local ok, noice = pcall(require, "noice")
		return ok and noice.api.status.mode.has()
	end,
	has_lazy_updates = function()
		local ok, ls = pcall(require, "lazy.status")
		return ok and ls.has_updates()
	end,
	has_ts = function()
		local buf = vim.api.nvim_get_current_buf()
		local ft = vim.bo[buf].filetype
		if not ft or ft == "" then return false end
		local lang = ft
		if vim.treesitter.language and vim.treesitter.language.get_lang then
			local ok, resolved = pcall(vim.treesitter.language.get_lang, ft)
			if ok and resolved then lang = resolved end
		end
		local parser_ok = pcall(vim.treesitter.get_parser, buf, lang)
		return parser_ok
	end,

	-- ── Runtime state ─────────────────────────────────────────────────
	is_recording = function()
		return vim.fn.reg_recording() ~= ""
	end,
	is_searching = function()
		return vim.v.hlsearch == 1
	end,
	is_debugging = function()
		local ok, dap = pcall(require, "dap")
		return ok and dap.session() ~= nil
	end,

	-- ── Environment ───────────────────────────────────────────────────
	has_env = function()
		return build_env_string() ~= ""
	end,
	has_session = function()
		return session_component() ~= ""
	end,
	has_ai = function()
		return ai_component() ~= ""
	end,
	has_venv = function()
		return venv_component() ~= ""
	end,
	has_runtimes = function()
		return runtimes_component() ~= ""
	end,

	-- ── Filetype checks ───────────────────────────────────────────────
	is_prose = function()
		local prose = {
			markdown = true,
			text = true,
			tex = true,
			latex = true,
			norg = true,
			org = true,
			rst = true,
			typst = true,
		}
		return prose[vim.bo.filetype] or false
	end,
	is_python = function()
		return vim.bo.filetype == "python"
	end,
	is_js_ts = function()
		local fts = {
			javascript = true,
			typescript = true,
			typescriptreact = true,
			javascriptreact = true,
			vue = true,
			svelte = true,
		}
		return fts[vim.bo.filetype] or false
	end,

	-- ── Encoding/format anomalies ─────────────────────────────────────
	non_utf8 = function()
		return vim.bo.fileencoding ~= "utf-8" and vim.bo.fileencoding ~= ""
	end,
	non_unix = function()
		return vim.bo.fileformat ~= "unix"
	end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- COLORS
--
-- Static Catppuccin Mocha hex colors for component highlighting.
-- These are theme-independent — they provide consistent color coding
-- regardless of the active colorscheme (lualine handles integration
-- via `theme = "auto"` for section backgrounds).
--
-- Color mapping:
--   pink     → environment   │  blue     → LSP
--   green    → venv/TS/node  │  cyan     → AI
--   purple   → user          │  red      → macro/DAP
--   peach    → search        │  yellow   → lazy/python
--   teal     → datetime      │  flamingo → session
--   overlay  → indent/size   │  mauve    → words
--   sapphire → runtimes      │  text     → noice
-- ═══════════════════════════════════════════════════════════════════════════

---@type table<string, table> Component color definitions (fg + optional gui)
local C = {
	env = { fg = "#f5c2e7", gui = "bold" },
	venv = { fg = "#a6e3a1" },
	lsp = { fg = "#89b4fa" },
	ts = { fg = "#a6e3a1" },
	ai = { fg = "#7dcfff", gui = "bold" },
	user = { fg = "#bb9af7" },
	macro = { fg = "#f38ba8", gui = "bold" },
	search = { fg = "#fab387" },
	lazy = { fg = "#f9e2af" },
	dap = { fg = "#f38ba8", gui = "bold" },
	indent = { fg = "#9399b2" },
	words = { fg = "#cba6f7" },
	session = { fg = "#f2cdcd" },
	filesize = { fg = "#9399b2" },
	bufnr = { fg = "#6c7086" },
	noice = { fg = "#cdd6f4" },
	pyver = { fg = "#f9e2af" },
	nodever = { fg = "#a6e3a1" },
	runtimes = { fg = "#74c7ec" },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
--
-- Loaded on VeryLazy. On dashboard launches (argc == 0), the
-- statusline is hidden (laststatus = 0) until a real file opens.
-- On file launches, a minimal " " statusline is shown to prevent
-- flickering before lualine initializes.
-- ═══════════════════════════════════════════════════════════════════════════

return {
	"nvim-lualine/lualine.nvim",
	event = "VeryLazy",
	dependencies = { "nvim-mini/mini.icons" },

	--- Pre-initialization: set statusline placeholder before lualine loads.
	---
	--- • With files: show minimal " " to prevent flicker
	--- • Without files (dashboard): hide statusline entirely
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
	--- Uses a function (not a static table) because several components
	--- need runtime evaluation: navic availability check, icon resolution,
	--- and telescope theme detection.
	---@return table opts Lualine configuration table
	opts = function()
		-- ── Winbar (navic breadcrumbs) ────────────────────────────────
		local winbar = {}
		local navic_ok = pcall(require, "nvim-navic")
		if navic_ok then
			winbar = {
				lualine_c = {
					{
						safe(function()
							return require("nvim-navic").get_location()
						end),
						cond = safe_cond(function()
							local ok, navic = pcall(require, "nvim-navic")
							return ok and navic.is_available()
						end),
						color = C.noice,
					},
				},
			}
		end

		-- ── Icon pre-resolution ───────────────────────────────────────
		local git_branch = icon(gi, "Branch", "")
		local git_added = icon(gi, "Added", "+") .. " "
		local git_modified = icon(gi, "Modified", "~") .. " "
		local git_removed = icon(gi, "Removed", "-") .. " "

		local diag_error = icon(dg, "Error", "E") .. " "
		local diag_warn = icon(dg, "Warn", "W") .. " "
		local diag_info = icon(dg, "Info", "I") .. " "
		local diag_hint = icon(dg, "Hint", "H") .. " "

		local sym_modified = " " .. icon(ui, "Pencil", "●")
		local sym_readonly = " " .. icon(ui, "Lock", "RO")
		local sym_newfile = " " .. icon(ui, "NewFile", "N")

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

				-- ── Global separators ─────────────────────────────────
				section_separators = {
					left = sep.round_r,
					right = sep.round_l,
				},
				component_separators = {
					left = sep.round_thin_r,
					right = sep.round_thin_l,
				},

				refresh = { statusline = 1000, tabline = 1000, winbar = 1000 },
			},

			-- ═══════════════════════════════════════════════════════════
			-- ACTIVE SECTIONS
			-- ═══════════════════════════════════════════════════════════

			sections = {

				-- ── A: MODE — Round bubble, bold, OS icon ─────────────
				lualine_a = {
					{
						"mode",
						icon = get_os_icon(),
					},
				},

				-- ── B: GIT — Branch + diff stats ──────────────────────
				lualine_b = {
					{
						"branch",
						icon = git_branch,
						fmt = function(s)
							if not s or s == "" then return "" end
							return #s > 20 and s:sub(1, 17) .. "…" or s
						end,
						separator = { right = sep.round_r },
					},
					{
						"diff",
						symbols = {
							added = git_added,
							modified = git_modified,
							removed = git_removed,
						},
						source = function()
							---@diagnostic disable-next-line: undefined-field
							local gs = vim.b.gitsigns_status_dict
							if gs then return { added = gs.added, modified = gs.changed, removed = gs.removed } end
						end,
					},
				},

				-- ── C: FILE — Diagnostics + filetype + name + size ────
				lualine_c = {
					{
						"diagnostics",
						symbols = {
							error = diag_error,
							warn = diag_warn,
							info = diag_info,
							hint = diag_hint,
						},
						separator = "",
					},
					{
						"filetype",
						icon_only = true,
						separator = "",
						padding = { left = 1, right = 0 },
					},
					{
						"filename",
						path = 1,
						symbols = {
							modified = sym_modified,
							readonly = sym_readonly,
							unnamed = " [No Name]",
							newfile = sym_newfile,
						},
						separator = "",
						padding = { left = 0, right = 1 },
					},
					{
						safe(filesize_component),
						color = C.filesize,
						separator = "",
						padding = { left = 0, right = 1 },
					},
					{
						safe(noice_command),
						color = C.noice,
						cond = safe_cond(cond.has_noice_cmd),
						separator = "",
					},
					{
						safe(noice_mode),
						color = C.noice,
						cond = safe_cond(cond.has_noice_mode),
						separator = "",
					},
				},

				-- ── X: STATUS CENTER — env, tools, AI, LSP ────────────
				lualine_x = {
					-- ── Critical (ephemeral, high-visibility) ─────────
					{
						safe(dap_component),
						color = C.dap,
						cond = safe_cond(cond.is_debugging),
						separator = { right = sep.thin_r },
					},
					{
						safe(macro_component),
						color = C.macro,
						cond = safe_cond(cond.is_recording),
						separator = { right = sep.thin_r },
					},
					{
						safe(search_component),
						color = C.search,
						cond = safe_cond(cond.is_searching),
						separator = { right = sep.thin_r },
					},

					-- ── Context (session, environment) ────────────────
					{
						safe(session_component),
						color = C.session,
						cond = safe_cond(cond.has_session),
						separator = "",
					},
					{
						safe(build_env_string),
						color = C.env,
						cond = safe_cond(cond.has_env),
						separator = { right = sep.thin_r },
					},

					-- ── Languages (dynamic per-project) ───────────────
					{
						safe(venv_component),
						color = C.venv,
						cond = safe_cond(cond.has_venv),
						separator = "",
					},
					{
						safe(python_version_component),
						color = C.pyver,
						cond = safe_cond(cond.is_python),
						separator = "",
					},
					{
						safe(node_version_component),
						color = C.nodever,
						cond = safe_cond(cond.is_js_ts),
						separator = "",
					},
					{
						safe(runtimes_component),
						color = C.runtimes,
						cond = safe_cond(cond.has_runtimes),
						separator = { right = sep.thin_r },
					},

					-- ── AI + User ─────────────────────────────────────
					{
						safe(ai_component),
						color = C.ai,
						cond = safe_cond(cond.has_ai),
						separator = "",
					},
					{
						safe(user_component),
						color = C.user,
						separator = { right = sep.thin_r },
					},

					-- ── LSP + Updates ─────────────────────────────────
					{
						safe(lsp_component),
						color = C.lsp,
						cond = safe_cond(cond.has_lsp),
						separator = "",
					},
					{
						safe(lazy_updates_component),
						color = C.lazy,
						cond = safe_cond(cond.has_lazy_updates),
					},
				},

				-- ── Y: META — indent, encoding, words, bufnr ─────────
				lualine_y = {
					{
						safe(indent_component),
						color = C.indent,
						separator = "",
						padding = { left = 1, right = 0 },
					},
					{
						"encoding",
						fmt = function(s)
							if not s or s == "" then return "" end
							return s:upper()
						end,
						cond = safe_cond(cond.non_utf8),
						separator = "",
						padding = { left = 1, right = 0 },
					},
					{
						"fileformat",
						cond = safe_cond(cond.non_unix),
						separator = "",
						padding = { left = 1, right = 0 },
					},
					{
						safe(wordcount_component),
						color = C.words,
						cond = safe_cond(cond.is_prose),
						separator = "",
						padding = { left = 1, right = 0 },
					},
					{
						safe(bufnr_component),
						color = C.bufnr,
						padding = { left = 1, right = 1 },
					},
					{
						"progress",
						separator = "",
						padding = { left = 1, right = 0 },
					},
					{
						"location",
						padding = { left = 1, right = 1 },
					},
				},

				-- ── Z: DATETIME — accent badge (bg overridden via highlights) ─
				lualine_z = {
					{
						safe(datetime_component),
						padding = { left = 1, right = 1 },
					},
				},
			},

			-- ═══════════════════════════════════════════════════════════
			-- INACTIVE SECTIONS
			-- ═══════════════════════════════════════════════════════════

			inactive_sections = {
				lualine_a = {},
				lualine_b = {},
				lualine_c = {
					{
						"filename",
						path = 1,
						symbols = { modified = " ●", readonly = " " },
					},
				},
				lualine_x = { "location" },
				lualine_y = {},
				lualine_z = {},
			},

			-- ═══════════════════════════════════════════════════════════
			-- WINBAR & EXTENSIONS
			-- ═══════════════════════════════════════════════════════════

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
	--- Post-setup: override section Z highlights and register
	--- ColorScheme autocmd for automatic accent refresh.
	config = function(_, opts)
		-- ── Step 1: Override section Z highlights ─────────────────
		apply_datetime_section_hl()

		-- ── Step 2: Initialize lualine ───────────────────────────
		require("lualine").setup(opts)

		-- ── Step 3: Re-apply on colorscheme change ───────────────
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = augroup("LualineDatetime"),
			callback = function()
				vim.schedule(function()
					apply_datetime_section_hl()
					pcall(function()
						require("lualine").refresh()
					end)
				end)
			end,
			desc = "NvimEnterprise: Update lualine Z accent on colorscheme change",
		})
	end,
}
