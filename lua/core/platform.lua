---@file lua/core/platform.lua
---@description Platform — cross-platform & environment detection singleton
---@module "core.platform"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.class Base OOP system (Platform extends Class)
---@see core.icons Icons referenced for OS, UI, borders, and runtimes
---@see core.settings Settings reads platform capabilities for feature toggling
---@see core.health Health checks use platform data for diagnostics
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/platform.lua — Cross-platform & environment detection              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Platform (singleton, extends Class)                             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Detection layers (all run once at startup via :init()):         │    ║
--- ║  │  ├─ OS detection         mac | windows | linux | bsd | unknown   │    ║
--- ║  │  ├─ Architecture         x86_64 | arm64 | aarch64 | …            │    ║
--- ║  │  ├─ Environment          SSH | WSL | Docker | Proxmox | VPS      │    ║
--- ║  │  ├─ Multiplexers         Tmux | Zellij                           │    ║
--- ║  │  ├─ Terminal caps        TrueColor | Nerd Font | GUI client      │    ║
--- ║  │  ├─ Language runtimes    Node | Python | Ruby | Go | Rust | Lua  │    ║
--- ║  │  └─ Path utilities       path_sep | config/data/cache/state dirs │    ║
--- ║  │                                                                  │    ║
--- ║  │  Detection strategies:                                           │    ║
--- ║  │  ├─ OS:       vim.uv.os_uname().sysname pattern matching         │    ║
--- ║  │  ├─ WSL:      vim.fn.has("wsl") + /proc/version "microsoft"      │    ║
--- ║  │  ├─ SSH:      SSH_TTY / SSH_CLIENT / SSH_CONNECTION env vars     │    ║
--- ║  │  ├─ Docker:   /.dockerenv file + /proc/1/cgroup parsing          │    ║
--- ║  │  ├─ Proxmox:  pveversion executable + /etc/pve directory         │    ║
--- ║  │  ├─ VPS:      /sys/hypervisor/type + DMI product_name heuristic  │    ║
--- ║  │  ├─ GUI:      neovide / nvui / fvim globals + gui_running        │    ║
--- ║  │  ├─ Color:    COLORTERM + TERM_PROGRAM + TERM pattern matching   │    ║
--- ║  │  └─ Runtimes: Declarative registry + vim.fn.executable() loop    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Registries (declarative, single source of truth):               │    ║
--- ║  │  ├─ RUNTIME_EXECUTABLES  runtime name → executable(s)            │    ║
--- ║  │  └─ STDPATH_DIRS         stdpath names → self.{name}_dir fields  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Singleton pattern:                                              │    ║
--- ║  │  ├─ get_instance() creates Platform once, caches in _instance    │    ║
--- ║  │  ├─ Module returns the instance directly (not the class)         │    ║
--- ║  │  └─ require("core.platform") always returns the same object      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Consumers:                                                      │    ║
--- ║  │  ├─ core/settings.lua    Feature toggling based on capabilities  │    ║
--- ║  │  ├─ core/options.lua     Clipboard, shell, path settings         │    ║
--- ║  │  ├─ core/health.lua      :checkhealth diagnostics                │    ║
--- ║  │  ├─ plugins/ui/          Colorscheme & font decisions            │    ║
--- ║  │  └─ plugins/tools/       Terminal integration (tmux, etc.)       │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • All detection runs exactly once in :init(), cached on the instance    ║
--- ║  • No shell-out except for runtime detection (vim.fn.executable)         ║
--- ║  • File reads use pcall() to gracefully handle permission errors         ║
--- ║  • Singleton pattern: require() returns the same object every time       ║
--- ║  • Icons loaded once from core/icons.lua (single source of truth)        ║
--- ║  • Runtimes & paths declared in registry tables — no repetitive code     ║
--- ║                                                                          ║
--- ║  User command:                                                           ║
--- ║    :SystemInfo    Show platform info in a centered floating window       ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local Class = require("core.class")
local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════
-- CLASS DEFINITION
-- ═══════════════════════════════════════════════════════════════════════

---@class Platform : Class
---@field os string Detected operating system: `"mac"` | `"windows"` | `"linux"` | `"bsd"` | `"unknown"`
---@field arch string CPU architecture from uname: `"x86_64"` | `"arm64"` | `"aarch64"` | …
---@field is_mac boolean `true` if running on macOS / Darwin
---@field is_windows boolean `true` if running on Windows / MinGW
---@field is_linux boolean `true` if running on Linux
---@field is_bsd boolean `true` if running on a BSD variant
---@field is_wsl boolean `true` if running inside Windows Subsystem for Linux
---@field is_ssh boolean `true` if running in an SSH session
---@field is_docker boolean `true` if running inside a Docker / containerd container
---@field is_proxmox boolean `true` if running on a Proxmox VE host
---@field is_vps boolean `true` if running on a virtual private server (heuristic)
---@field is_gui boolean `true` if running in a GUI client (Neovide, nvui, fvim, etc.)
---@field is_tmux boolean `true` if running inside a tmux session
---@field is_zellij boolean `true` if running inside a Zellij session
---@field has_nerd_font boolean `true` if Nerd Font icons are available (default: `true`)
---@field has_true_color boolean `true` if terminal supports 24-bit / TrueColor
---@field runtimes table<string, boolean> Map of language runtime name → availability
---@field path_sep string OS path separator: `"/"` (Unix) or `"\\"` (Windows)
---@field config_dir string Neovim config directory (`vim.fn.stdpath("config")`)
---@field data_dir string Neovim data directory (`vim.fn.stdpath("data")`)
---@field cache_dir string Neovim cache directory (`vim.fn.stdpath("cache")`)
---@field state_dir string Neovim state directory (`vim.fn.stdpath("state")`)
local Platform = Class:extend("Platform") --[[@as Platform]]

-- ═══════════════════════════════════════════════════════════════════════
-- RUNTIME REGISTRY
--
-- Declarative mapping: runtime name → executable name(s).
-- When a list is given, the first match wins (e.g. python3 before python).
-- The key becomes the index in self.runtimes.
--
-- To add a new runtime, just add one line here — no other code to touch.
-- Example:   deno = "deno",
-- Example:   dotnet = { "dotnet", "dotnet-sdk" },
-- ═══════════════════════════════════════════════════════════════════════

---@type table<string, string|string[]>
local RUNTIME_EXECUTABLES = {
	cpp = "c++",
	gcc = "gcc",
	go = "go",
	gpp = "g++",
	haskell = "haskell",
	java = "java",
	julia = "julia",
	lean = "lean",
	lua = "lua",
	mysql = "mysql",
	nix = "nix",
	node = "node",
	nu = "nu",
	ocaml = "ocaml",
	php = "php",
	prisma = "prisma",
	python = { "python3", "python" },
	ruby = "ruby",
	rust = "rustc",
	scala = "scala",
	terraform = "terraform",
	vim = "vim",
	zig = "zig",
}

-- ═══════════════════════════════════════════════════════════════════════
-- STDPATH REGISTRY
--
-- Declarative list of vim.fn.stdpath() directories to cache.
-- Each entry generates a field named "{name}_dir" on the instance.
--
-- To expose a new stdpath, just add one string here.
-- Example:   "log"   →  self.log_dir = vim.fn.stdpath("log")
-- Example:   "run"   →  self.run_dir = vim.fn.stdpath("run")
-- ═══════════════════════════════════════════════════════════════════════

---@type string[]
local STDPATH_DIRS = { "config", "data", "cache", "state" }

-- ═══════════════════════════════════════════════════════════════════════
-- OS DETECTION
--
-- Uses vim.uv.os_uname() for reliable cross-platform detection.
-- Pattern matching on sysname handles edge cases (MinGW, BSD variants).
-- Returns multiple values to set all OS flags in a single call.
-- ═══════════════════════════════════════════════════════════════════════

--- Detect the current operating system from uname sysname.
---
--- Returns the OS name string plus boolean flags for each platform,
--- allowing the caller to set all fields in a single destructuring.
---
---@return string os_name Normalized OS name
---@return boolean is_mac macOS / Darwin
---@return boolean is_windows Windows / MinGW
---@return boolean is_linux Linux
---@return boolean is_bsd BSD variant
---@private
local function detect_os()
	local uname = vim.uv.os_uname()
	local sysname = (uname.sysname or ""):lower()

	if sysname:find("darwin") then
		return "mac", true, false, false, false
	elseif sysname:find("windows") or sysname:find("mingw") then
		return "windows", false, true, false, false
	elseif sysname:find("linux") then
		return "linux", false, false, true, false
	elseif sysname:find("bsd") then
		return "bsd", false, false, false, true
	else
		return "unknown", false, false, false, false
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- ENVIRONMENT DETECTION
--
-- Each detector returns a boolean and uses the cheapest check first
-- (env vars → file existence → file content parsing).
-- All file reads are wrapped in pcall() for robustness.
-- ═══════════════════════════════════════════════════════════════════════

--- Detect WSL (Windows Subsystem for Linux).
---
--- Two-pass detection: first checks `vim.fn.has("wsl")` (fast, Neovim-native),
--- then falls back to parsing `/proc/version` for the `"microsoft"` string
--- which is present in both WSL1 and WSL2 kernels.
---
---@return boolean is_wsl `true` if running inside WSL
---@private
local function detect_wsl()
	if vim.fn.has("wsl") == 1 then return true end
	if vim.fn.filereadable("/proc/version") == 1 then
		local ok, release = pcall(vim.fn.readfile, "/proc/version", "", 1)
		if ok and release and release[1] then return release[1]:lower():find("microsoft") ~= nil end
	end
	return false
end

--- Detect SSH session via standard environment variables.
---
--- Checks `SSH_TTY`, `SSH_CLIENT`, and `SSH_CONNECTION` — at least one
--- is set by OpenSSH when a remote session is established.
---
---@return boolean is_ssh `true` if running in an SSH session
---@private
local function detect_ssh()
	return vim.env.SSH_TTY ~= nil or vim.env.SSH_CLIENT ~= nil or vim.env.SSH_CONNECTION ~= nil
end

--- Detect Docker / containerd container.
---
--- Two-pass detection:
--- 1. Check for `/.dockerenv` sentinel file (fastest, Docker-specific)
--- 2. Parse `/proc/1/cgroup` for `"docker"` or `"containerd"` strings
---    (catches containerd and some Podman setups)
---
---@return boolean is_docker `true` if running inside a container
---@private
local function detect_docker()
	if vim.fn.filereadable("/.dockerenv") == 1 then return true end
	if vim.fn.filereadable("/proc/1/cgroup") == 1 then
		local ok, cgroup = pcall(vim.fn.readfile, "/proc/1/cgroup", "", 5)
		if ok and cgroup then
			for _, line in ipairs(cgroup) do
				if line:find("docker") or line:find("containerd") then return true end
			end
		end
	end
	return false
end

--- Detect Proxmox VE host environment.
---
--- Checks for the `pveversion` CLI tool or the `/etc/pve` configuration
--- directory, both of which are unique to Proxmox VE installations.
---
---@return boolean is_proxmox `true` if running on a Proxmox VE host
---@private
local function detect_proxmox()
	return vim.fn.executable("pveversion") == 1 or vim.fn.isdirectory("/etc/pve") == 1
end

--- Detect VPS environment (heuristic-based).
---
--- Uses two signals:
--- 1. `/sys/hypervisor/type` exists → definitely virtualized
--- 2. DMI product name contains known hypervisor strings
---    (`"virtual"`, `"kvm"`, `"vmware"`, `"xen"`)
---
--- NOTE: This is a best-effort heuristic. Bare-metal cloud instances
--- (e.g., AWS i3.metal) will return `false`.
---
---@return boolean is_vps `true` if likely running on a virtual machine
---@private
local function detect_vps()
	if vim.fn.filereadable("/sys/hypervisor/type") == 1 then return true end
	if vim.fn.filereadable("/sys/class/dmi/id/product_name") == 1 then
		local ok, dmi = pcall(vim.fn.readfile, "/sys/class/dmi/id/product_name", "", 1)
		if ok and dmi and dmi[1] then
			local product = dmi[1]:lower()
			return product:find("virtual") ~= nil
				or product:find("kvm") ~= nil
				or product:find("vmware") ~= nil
				or product:find("xen") ~= nil
		end
	end
	return false
end

-- ═══════════════════════════════════════════════════════════════════════
-- TERMINAL & GUI DETECTION
--
-- Determines rendering capabilities to inform colorscheme selection,
-- icon usage, and clipboard integration strategy.
-- ═══════════════════════════════════════════════════════════════════════

--- Detect GUI client (Neovide, nvui, fvim, etc.).
---
--- Checks well-known global variables set by GUI frontends before
--- falling back to the generic `gui_running` feature flag.
---
---@return boolean is_gui `true` if running in a GUI client
---@private
local function detect_gui()
	if vim.g.neovide or vim.g.nvui or vim.g.fvim_loaded then return true end
	return vim.fn.has("gui_running") == 1
end

--- Detect true color (24-bit) terminal support.
---
--- Checks `COLORTERM` (standard), known terminal programs (iTerm,
--- WezTerm, Alacritty), and falls back to the `256color` TERM suffix.
---
--- NOTE: `256color` in TERM doesn't guarantee true color, but most
--- modern terminals that set it also support 24-bit color.
---
---@return boolean has_true_color `true` if the terminal supports 24-bit color
---@private
local function detect_true_color()
	return vim.env.COLORTERM == "truecolor"
		or vim.env.COLORTERM == "24bit"
		or vim.fn.has("gui_running") == 1
		or vim.env.TERM_PROGRAM == "iTerm.app"
		or vim.env.TERM_PROGRAM == "WezTerm"
		or vim.env.TERM_PROGRAM == "Alacritty"
		or (vim.env.TERM or ""):find("256color") ~= nil
end

-- ═══════════════════════════════════════════════════════════════════════
-- RUNTIME DETECTION HELPER
--
-- Probes one or more executables for a single runtime entry.
-- Supports both a plain string ("node") and a fallback list
-- ({"python3", "python"}) where the first match wins.
-- ═══════════════════════════════════════════════════════════════════════

--- Probe executables for a single runtime entry.
---
--- Accepts a single executable name (string) or a list of fallbacks.
--- For a list, returns `true` as soon as the first candidate is found.
---
---@param self Platform
---@param executables string|string[] One or more executable names
---@return boolean available `true` if at least one executable is in PATH
---@private
local function probe_runtime(self, executables)
	if type(executables) == "string" then return self:has_executable(executables) end
	for _, exe in ipairs(executables) do
		if self:has_executable(exe) then return true end
	end
	return false
end

-- ═══════════════════════════════════════════════════════════════════════
-- CONSTRUCTOR
--
-- Runs all detection exactly once. The singleton pattern at the
-- bottom of this file ensures :init() is never called twice.
-- Detection order matters: OS must come first (WSL depends on is_linux).
-- ═══════════════════════════════════════════════════════════════════════

--- Initialize the Platform singleton — runs all detection layers.
---
--- Detection order:
--- 1. OS & architecture (no dependencies)
--- 2. Environment (WSL depends on `is_linux`)
--- 3. Multiplexers (env var checks)
--- 4. Terminal / GUI capabilities
--- 5. Language runtimes (declarative registry loop)
--- 6. Path configuration (declarative stdpath loop)
function Platform:init()
	-- ── OS & Architecture ────────────────────────────────────────────
	self.os, self.is_mac, self.is_windows, self.is_linux, self.is_bsd = detect_os()
	self.arch = (vim.uv.os_uname().machine or "unknown"):lower()

	-- ── Environment ──────────────────────────────────────────────────
	-- WSL check depends on is_linux being set first
	self.is_wsl = self.is_linux and detect_wsl()
	self.is_ssh = detect_ssh()
	self.is_docker = detect_docker()
	self.is_proxmox = detect_proxmox()
	self.is_vps = detect_vps()

	-- ── Multiplexers ─────────────────────────────────────────────────
	self.is_tmux = vim.env.TMUX ~= nil
	self.is_zellij = vim.env.ZELLIJ ~= nil

	-- ── Terminal / GUI capabilities ──────────────────────────────────
	self.is_gui = detect_gui()
	self.has_nerd_font = true -- Assume Nerd Font; can be toggled in settings
	self.has_true_color = detect_true_color()

	-- ── Language runtimes ────────────────────────────────────────────
	-- Driven by RUNTIME_EXECUTABLES registry — add new runtimes there
	self.runtimes = {}
	for name, executables in pairs(RUNTIME_EXECUTABLES) do
		self.runtimes[name] = probe_runtime(self, executables)
	end

	-- ── Path configuration ───────────────────────────────────────────
	-- Driven by STDPATH_DIRS registry — add new stdpath entries there
	self.path_sep = self.is_windows and "\\" or "/"
	for _, name in ipairs(STDPATH_DIRS) do
		self[name .. "_dir"] = vim.fn.stdpath(name) --[[@as string]]
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- PUBLIC API — UTILITIES
-- ═══════════════════════════════════════════════════════════════════════

--- Get the Nerd Font icon for the current operating system.
---
--- Returns an empty string if `has_nerd_font` is `false`, allowing
--- callers to use the result without conditional checks.
---
---@return string icon OS icon from `core/icons.lua`, or `""` if no Nerd Font
function Platform:get_os_icon()
	if not self.has_nerd_font then return "" end

	---@type table<string, string>
	local mapping = {
		mac = icons.os.Mac,
		windows = icons.os.Windows,
		linux = icons.os.Linux,
		bsd = icons.os.Freebsd,
		unknown = icons.misc.Question or "?",
	}

	return mapping[self.os] or mapping.unknown
end

--- Join path segments using the platform-appropriate separator.
---
--- ```lua
--- platform:path_join("lua", "core", "init.lua")
--- -- Unix:    "lua/core/init.lua"
--- -- Windows: "lua\\core\\init.lua"
--- ```
---
---@param ... string Path segments to join
---@return string path Joined path string
function Platform:path_join(...)
	return table.concat({ ... }, self.path_sep)
end

--- Check if a command is available on the system PATH.
---
---@param cmd string Command / executable name to check
---@return boolean available `true` if the command is found in PATH
function Platform:has_executable(cmd)
	return vim.fn.executable(cmd) == 1
end

-- ═══════════════════════════════════════════════════════════════════════
-- PUBLIC API — SUMMARY / DIAGNOSTICS
--
-- Human-readable summaries used by :SystemInfo, :checkhealth,
-- and lualine integrations.
-- ═══════════════════════════════════════════════════════════════════════

--- Get a one-line summary of environment flags only.
---
--- Used internally by `:summary()` and `:show_info()` to display
--- the active environment tags (SSH, WSL, Docker, Tmux).
---
---@return string env_summary Comma-separated environment tags, or `"Local"`
function Platform:summary_env_only()
	local env = {}
	if self.is_ssh then table.insert(env, "SSH") end
	if self.is_wsl then table.insert(env, "WSL") end
	if self.is_docker then table.insert(env, "Docker") end
	if self.is_tmux then table.insert(env, "Tmux") end
	return #env > 0 and table.concat(env, ", ") or "Local"
end

--- Get a full human-readable summary string of the platform.
---
--- Format: `OS=linux  Arch=x86_64  Env=[SSH, Docker]  Mux=[Tmux]  Langs=[node, python, go]`
---
---@return string summary Formatted platform summary
function Platform:summary()
	local env = {}
	if self.is_ssh then table.insert(env, "SSH") end
	if self.is_wsl then table.insert(env, "WSL") end
	if self.is_docker then table.insert(env, "Docker") end
	if self.is_tmux then table.insert(env, "Tmux") end
	if self.is_gui then table.insert(env, "GUI") end

	local dev_tools = {}
	--stylua: ignore start
	if self.is_tmux then table.insert(dev_tools, "Tmux") end
	if self.is_zellij then table.insert(dev_tools, "Zellij") end
	--stylua: ignore end

	local active_langs = {}
	for lang, installed in pairs(self.runtimes) do
		if installed then table.insert(active_langs, lang) end
	end

	return string.format(
		"OS=%s  Arch=%s  Env=[%s]  Mux=[%s]  Langs=[%s]",
		self.os,
		self.arch,
		#env > 0 and table.concat(env, ", ") or "local",
		#dev_tools > 0 and table.concat(dev_tools, ", ") or "none",
		#active_langs > 0 and table.concat(active_langs, ", ") or "none"
	)
end

-- ═══════════════════════════════════════════════════════════════════════
-- SYSTEM INFO COMMAND
--
-- :SystemInfo displays a centered floating window with all detected
-- platform information. Uses icons from core/icons.lua for consistent
-- visual language across the configuration.
-- ═══════════════════════════════════════════════════════════════════════

--- Display platform information in a centered floating window.
---
--- Creates a scratch buffer with formatted system info, opens it in a
--- centered floating window with rounded borders, and sets up `q` / `<Esc>`
--- keymaps to close. The window is read-only and non-persistent.
function Platform:show_info()
	local os_icon = self:get_os_icon()

	-- ── Build content lines ──────────────────────────────────────────
	local lines = {
		string.format(" %s  System Information ", icons.ui.Gear),
		string.format(" %s", string.rep("─", 35)),
		string.format(" %s OS:        %s (%s)", os_icon, self.os:gsub("^%l", string.upper), self.arch),
		string.format(" %s Env:       %s", icons.ui.Project, self:summary_env_only()),
		string.format(" %s GUI:       %s", icons.ui.Window, tostring(self.is_gui)),
		string.format(" %s Terminal:  %s", icons.ui.Terminal, self.has_true_color and "TrueColor" or "256color"),
		string.format(" %s", string.rep("─", 35)),
		string.format(" %s Runtimes:", icons.ui.Code),
	}

	-- Add detected runtimes with language-specific icons
	for lang, installed in pairs(self.runtimes) do
		if installed then
			local lang_icon = icons.app[lang:gsub("^%l", string.upper)] or "•"
			table.insert(lines, string.format("   %s %-10s Installed", lang_icon, lang))
		end
	end

	-- ── Create floating window ───────────────────────────────────────
	local width = 40
	local height = #lines + 2

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	---@type vim.api.keyset.win_config
	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		col = (vim.o.columns - width) / 2,
		row = (vim.o.lines - height) / 2,
		style = "minimal",
		border = icons.borders and icons.borders.Rounded or "rounded",
		title = " Platform Info ",
		title_pos = "center",
	}

	vim.api.nvim_open_win(buf, true, win_opts)

	-- ── Close keymaps ────────────────────────────────────────────────
	vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
	vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

-- ═══════════════════════════════════════════════════════════════════════
-- SINGLETON
--
-- Platform detection is expensive (file I/O, env checks) and must
-- only run once. The singleton is created on first require() and
-- cached in the module-local _instance variable.
-- ═══════════════════════════════════════════════════════════════════════

---@type Platform|nil
---@private
local _instance = nil

--- Get or create the Platform singleton instance.
---
--- On first call, creates a new `Platform` instance (runs all detection).
--- On subsequent calls, returns the cached instance.
---
---@return Platform instance The global Platform singleton
---@private
local function get_instance()
	if not _instance then
		---@diagnostic disable-next-line: param-type-mismatch
		_instance = Platform:new() --[[@as Platform]]
	end
	return _instance
end

-- ═══════════════════════════════════════════════════════════════════════
-- USER COMMAND REGISTRATION
-- ═══════════════════════════════════════════════════════════════════════

vim.api.nvim_create_user_command("SystemInfo", function()
	get_instance():show_info()
end, {
	desc = "Show NvimEnterprise platform and system information",
})

return get_instance()
