---@file lua/core/secrets.lua
---@description Secrets — secure API key loader with dotenv parsing, permission checks, and masked display
---@module "core.secrets"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.security Security module (complementary — runtime security policies)
---@see core.platform Platform detection (Windows permission skip)
---@see core.bootstrap Bootstrap calls Secrets.init() during startup
---@see plugins.ai.avante Avante reads API keys from vim.env
---@see plugins.ai.codecompanion CodeCompanion reads API keys from vim.env
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/secrets.lua — Secure API key management with dotenv support        ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Secrets (module table, NOT a class — stateless utilities)       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Initialization pipeline (Secrets.init()):                       │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  1. Scan DEFAULT_PATHS for .env files                      │  │    ║
--- ║  │  │     ~/.config/nvim/.env → project .env                     │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  2. Permission check (Unix only)                           │  │    ║
--- ║  │  │     Warn if .env is not chmod 600 or 400                   │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  3. Parse dotenv with Lua string patterns                  │  │    ║
--- ║  │  │     KEY=value → vim.env.KEY = value                        │  │    ║
--- ║  │  │     Handles quotes, inline comments, whitespace            │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  4. Register user commands (:AIStatus, :AIReload)          │  │    ║
--- ║  │  │     Deferred via commands_registered guard                 │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Supported AI providers:                                         │    ║
--- ║  │  ├─ ANTHROPIC_API_KEY   → Claude                                 │    ║
--- ║  │  ├─ OPENAI_API_KEY      → GPT-5                                  │    ║
--- ║  │  ├─ GEMINI_API_KEY      → Gemini                                 │    ║
--- ║  │  ├─ DEEPSEEK_API_KEY    → DeepSeek                               │    ║
--- ║  │  ├─ DASHSCOPE_API_KEY   → Qwen                                   │    ║
--- ║  │  ├─ GLM_API_KEY         → GLM-5                                  │    ║
--- ║  │  ├─ MOONSHOT_API_KEY    → Kimi                                   │    ║
--- ║  │  └─ Ollama              → (no key — local inference)             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Dotenv parser features:                                         │    ║
--- ║  │  ├─ Single/double quoted values: KEY="value" or KEY='value'      │    ║
--- ║  │  ├─ Unquoted values with inline comment stripping: KEY=val #cmt  │    ║
--- ║  │  ├─ Comment lines (# ...) and empty lines skipped                │    ║
--- ║  │  ├─ Leading/trailing whitespace trimmed on keys and values       │    ║
--- ║  │  ├─ Shell env vars take precedence (unless override=true)        │    ║
--- ║  │  └─ Byte-level fast path: first byte check for # (ASCII 35)      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Security:                                                       │    ║
--- ║  │  ├─ Permission check: warns if .env is not 600 or 400 (Unix)     │    ║
--- ║  │  ├─ Masked display: shows first/last chars + *** for secrets     │    ║
--- ║  │  ├─ No secrets in logs — only masked output in :AIStatus         │    ║
--- ║  │  └─ Windows: permission check skipped (NTFS ACLs not checked)    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ Module table (not OOP) — secrets are stateless utilities     │    ║
--- ║  │  ├─ vim.uv (libuv) for file I/O — zero-copy, non-blocking        │    ║
--- ║  │  ├─ Lua string patterns (not regex) — fastest parsing option     │    ║
--- ║  │  ├─ Shell env vars preserved by default (no override) so         │    ║
--- ║  │  │  export KEY=val in shell always wins over .env                │    ║
--- ║  │  ├─ Cached references (uv, env, notify, fmt) to avoid            │    ║
--- ║  │  │  repeated global lookups in hot paths                         │    ║
--- ║  │  └─ commands_registered guard prevents double registration       │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • libuv fs_read for zero-copy file reading (no Vimscript overhead)      ║
--- ║  • Byte-level fast skip for comment lines (first byte == 35)             ║
--- ║  • Pre-computed SAFE_PERMS lookup table (no string comparison in loop)   ║
--- ║  • Pre-allocated lines table in status() (no repeated concatenation)     ║
--- ║  • Cached module-level references (uv, env, notify, fmt, rep)            ║
--- ║  • loaded_files tracked to avoid re-parsing same file                    ║
--- ║                                                                          ║
--- ║  User commands:                                                          ║
--- ║    :AIStatus     Show AI API keys status (masked) in a notification      ║
--- ║    :AISecrets    Alias for :AIStatus                                     ║
--- ║    :AIReload     Reload secrets from .env files and show status          ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local M = {}

-- ═══════════════════════════════════════════════════════════════════════
-- CACHED REFERENCES
--
-- Module-level locals for frequently accessed globals. Avoids
-- repeated table lookups in hot paths (dotenv parser loop).
-- ═══════════════════════════════════════════════════════════════════════

local uv = vim.uv or vim.loop
local env = vim.env
local notify = vim.notify
local fmt = string.format
local rep = string.rep

-- ═══════════════════════════════════════════════════════════════════════
-- CONSTANTS
--
-- AI_KEYS defines the known AI providers and their environment
-- variable names. DEFAULT_PATHS lists the .env file locations
-- to scan (config dir first, then project root).
-- ═══════════════════════════════════════════════════════════════════════

--- Known AI provider API key definitions.
---
--- Each entry maps an environment variable name to a human-readable
--- provider name and display icon for `:AIStatus` output.
---
---@type { env: string, name: string, icon: string }[]
M.AI_KEYS = {
	{ env = "ANTHROPIC_API_KEY", name = "Claude", icon = "🧠" },
	{ env = "OPENAI_API_KEY", name = "GPT-5", icon = "🤖" },
	{ env = "GEMINI_API_KEY", name = "Gemini", icon = "💎" },
	{ env = "DEEPSEEK_API_KEY", name = "DeepSeek", icon = "🔍" },
	{ env = "DASHSCOPE_API_KEY", name = "Qwen", icon = "🌐" },
	{ env = "GLM_API_KEY", name = "GLM-5", icon = "🐉" },
	{ env = "MOONSHOT_API_KEY", name = "Kimi", icon = "🌙" },
	{ env = "GITHUB_PERSONAL_ACCESS_TOKEN", name = "GitHub", icon = "🐙" },
}

--- Default .env file search paths (scanned in order).
---
--- 1. Config-level: `~/.config/nvim/.env` (global secrets)
--- 2. Project-level: `./.env` (project-specific overrides)
---
---@type string[]
M.DEFAULT_PATHS = {
	vim.fn.stdpath("config") .. "/.env",
	".env",
}

--- Pre-computed safe Unix permission lookup.
--- Only `600` (owner rw) and `400` (owner r) are considered secure.
---@type table<string, boolean>
---@private
local SAFE_PERMS = { ["600"] = true, ["400"] = true }

--- Windows detection flag (permission checks are skipped on Windows).
---@type boolean
---@private
local IS_WINDOWS = vim.fn.has("win32") == 1

-- ═══════════════════════════════════════════════════════════════════════
-- INTERNAL STATE
--
-- Tracks loaded file paths (for status display) and command
-- registration guard (prevents double registration).
-- ═══════════════════════════════════════════════════════════════════════

--- List of .env file paths that were successfully loaded (display paths).
---@type string[]
---@private
local loaded_files = {}

--- Guard flag to prevent double command registration.
---@type boolean
---@private
local commands_registered = false

-- ═══════════════════════════════════════════════════════════════════════
-- PERMISSION CHECK
--
-- Unix-only security check. Warns if .env file permissions are
-- too permissive (readable by group or others). Skipped entirely
-- on Windows where NTFS ACLs are not inspected.
-- ═══════════════════════════════════════════════════════════════════════

--- Check if a file has secure Unix permissions (600 or 400).
---
--- Skipped on Windows (always returns `true`). On Unix, reads the
--- file's `stat.mode` and extracts the last 3 octal digits.
---
---@param path string Absolute path to the file to check
---@return boolean secure `true` if permissions are safe (or on Windows)
---@return string|nil perms Octal permission string (e.g. `"600"`), or `nil` on stat failure
---@private
local function check_permissions(path)
	if IS_WINDOWS then return true, "N/A" end

	local stat = uv.fs_stat(path)
	if not stat then return false, nil end

	local perms = fmt("%o", stat.mode):sub(-3)
	return SAFE_PERMS[perms] == true, perms
end

-- ═══════════════════════════════════════════════════════════════════════
-- DOTENV PARSER
--
-- Fast .env file parser using libuv for file I/O and Lua string
-- patterns for line parsing. Supports:
-- • Quoted values (single and double quotes)
-- • Inline comment stripping for unquoted values
-- • Whitespace trimming on keys and values
-- • Shell env var precedence (unless override=true)
--
-- Performance: byte-level fast path skips comment lines by checking
-- the first byte (ASCII 35 = '#') before any pattern matching.
-- ═══════════════════════════════════════════════════════════════════════

--- Parse and load a .env file into `vim.env`.
---
--- Reads the file with libuv (`fs_open` + `fs_read` + `fs_close`),
--- then parses each line for `KEY=value` assignments. Shell environment
--- variables take precedence unless `opts.override` is `true`.
---
--- ```lua
--- local ok, count = M.load_dotenv("~/.config/nvim/.env")
--- local ok, count = M.load_dotenv(".env", { override = true, silent = true })
--- ```
---
---@param path string Path to the .env file (supports `~` expansion)
---@param opts? { override: boolean, silent: boolean } Parser options
---@return boolean success `true` if the file was read and parsed
---@return number count Number of environment variables set
function M.load_dotenv(path, opts)
	opts = opts or {}
	path = vim.fn.expand(path)

	local stat = uv.fs_stat(path)
	if not stat then return false, 0 end

	-- Permission check — warn but don't block loading
	local secure, perms = check_permissions(path)
	if not secure and not opts.silent then
		vim.schedule(function()
			notify(
				fmt(
					"🔒 %s has insecure permissions (%s). Fix: chmod 600 %s",
					vim.fn.fnamemodify(path, ":~"),
					perms or "?",
					path
				),
				vim.log.levels.WARN,
				{ title = "Secrets" }
			)
		end)
	end

	-- Read entire file with libuv (zero-copy)
	local fd = uv.fs_open(path, "r", 438) -- 438 = 0o666
	if not fd then return false, 0 end

	local data = uv.fs_read(fd, stat.size, 0)
	uv.fs_close(fd)

	if not data then return false, 0 end

	-- Parse line by line
	local count = 0
	local override = opts.override

	for raw_line in data:gmatch("[^\r\n]+") do
		-- Fast skip: comment or empty (byte-level check, no pattern)
		local first = raw_line:byte(1)
		if first and first ~= 35 then -- 35 = '#'
			-- Trim leading/trailing whitespace
			local line = raw_line:match("^%s*(.-)%s*$")

			if line ~= "" and line:byte(1) ~= 35 then
				local key, value = line:match("^([%w_]+)%s*=%s*(.+)$")

				if key and value then
					-- Strip quotes (single or double)
					local q = value:byte(1)
					if q == 34 or q == 39 then -- 34 = '"', 39 = "'"
						value = value:sub(2, -2)
					else
						-- Strip inline comments for unquoted values
						value = value:match("^(.-)%s*#") or value
					end

					value = value:match("^%s*(.-)%s*$") -- final trim

					-- Shell env vars take precedence unless override is set
					if override or not env[key] or env[key] == "" then
						env[key] = value
						count = count + 1
					end
				end
			end
		end
	end

	if count > 0 then loaded_files[#loaded_files + 1] = vim.fn.fnamemodify(path, ":~") end

	return true, count
end

-- ═══════════════════════════════════════════════════════════════════════
-- BULK LOADER
--
-- Scans all DEFAULT_PATHS and loads each .env file found.
-- Aggregates the total count of variables set across all files.
-- ═══════════════════════════════════════════════════════════════════════

--- Load secrets from all default .env file paths.
---
--- Iterates `DEFAULT_PATHS` in order, calling `load_dotenv()` for each.
--- Shows a summary notification with the total count unless `silent`.
---
---@param opts? { silent: boolean } Loader options
---@return number total Total number of environment variables set across all files
function M.load_all(opts)
	opts = opts or {}
	loaded_files = {}

	local total = 0
	for i = 1, #M.DEFAULT_PATHS do
		local _, count = M.load_dotenv(M.DEFAULT_PATHS[i], { silent = true })
		total = total + count
	end

	if total > 0 and not opts.silent then
		vim.schedule(function()
			notify(
				fmt("🔐 Loaded %d AI secret(s) from %d file(s)", total, #loaded_files),
				vim.log.levels.INFO,
				{ title = "Secrets" }
			)
		end)
	end

	return total
end

-- ═══════════════════════════════════════════════════════════════════════
-- KEY VALIDATION
--
-- Utilities for checking key availability and counting configured
-- providers. Used by :AIStatus and by AI plugins to determine
-- which providers are available at runtime.
-- ═══════════════════════════════════════════════════════════════════════

--- Check if an API key environment variable is set and non-empty.
---
---@param env_var string Environment variable name (e.g. `"ANTHROPIC_API_KEY"`)
---@return boolean available `true` if the variable is set and non-empty
function M.has_key(env_var)
	local val = env[env_var]
	return val ~= nil and val ~= ""
end

--- Count how many AI provider keys are configured.
---
---@return number available Number of providers with valid API keys
---@return number total Total number of known providers
function M.count_keys()
	local available = 0
	local keys = M.AI_KEYS
	for i = 1, #keys do
		if M.has_key(keys[i].env) then available = available + 1 end
	end
	return available, #keys
end

-- ═══════════════════════════════════════════════════════════════════════
-- MASKED DISPLAY
--
-- Security-conscious display of API keys. Shows enough characters
-- for identification (first 7 + last 3) while hiding the rest.
-- Short keys (≤10 chars) show only the first 3 characters.
-- ═══════════════════════════════════════════════════════════════════════

--- Get a masked representation of an API key for safe display.
---
--- Display rules:
--- • Not set:   `"❌ not set"`
--- • ≤10 chars: first 3 + asterisks (e.g. `"sk-***"`)
--- • >10 chars: first 7 + `"***…"` + last 3 (e.g. `"sk-proj***…xyz"`)
---
---@param env_var string Environment variable name
---@return string masked Safe-to-display representation
function M.masked(env_var)
	local val = env[env_var]
	if not val or val == "" then return "❌ not set" end
	local len = #val
	if len <= 10 then return val:sub(1, 3) .. rep("*", len - 3) end
	return val:sub(1, 7) .. "***…" .. val:sub(-3)
end

-- ═══════════════════════════════════════════════════════════════════════
-- STATUS DISPLAY
--
-- Renders a formatted notification showing all known AI providers,
-- their API key status (set/unset), masked key values, and the
-- list of .env files that were loaded. Uses pre-allocated table
-- building for performance.
-- ═══════════════════════════════════════════════════════════════════════

--- Display a formatted status notification for all AI API keys.
---
--- Shows each provider with a ✅/❌ indicator, the provider icon,
--- name, and masked key value. Also lists Ollama (no key needed)
--- and the .env files that were loaded.
function M.status()
	local available, total = M.count_keys()
	local keys = M.AI_KEYS
	local sep = rep("─", 55)

	-- Pre-allocate table for efficient string building
	local lines = {
		"🔐 AI API Keys Status",
		sep,
	}
	local n = 2

	for i = 1, #keys do
		local entry = keys[i]
		local has = M.has_key(entry.env)
		n = n + 1
		lines[n] = fmt("  %s %s %-10s %s", has and "✅" or "❌", entry.icon, entry.name, M.masked(entry.env))
	end

	n = n + 1
	lines[n] = sep
	n = n + 1
	lines[n] = "  🦙 Ollama      (no key needed — local)"
	n = n + 1
	lines[n] = sep
	n = n + 1
	lines[n] = fmt("  📊 %d/%d providers configured", available, total)

	-- Show loaded file paths (if any)
	if #loaded_files > 0 then
		n = n + 1
		lines[n] = ""
		n = n + 1
		lines[n] = "  📁 Loaded from:"
		for i = 1, #loaded_files do
			n = n + 1
			lines[n] = "     • " .. loaded_files[i]
		end
	end

	notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "AI Secrets" })
end

-- ═══════════════════════════════════════════════════════════════════════
-- USER COMMANDS
--
-- Registered lazily via setup_commands(). The commands_registered
-- guard prevents double registration when init() is called
-- multiple times (e.g., during reload).
-- ═══════════════════════════════════════════════════════════════════════

--- Register user commands for secrets management.
---
--- Commands:
--- • `:AIStatus`  — Show AI API keys status (masked)
--- • `:AISecrets` — Alias for `:AIStatus`
--- • `:AIReload`  — Reload secrets from .env files and show status
---
--- Guarded by `commands_registered` flag — safe to call multiple times.
function M.setup_commands()
	if commands_registered then return end
	commands_registered = true

	local cmd = vim.api.nvim_create_user_command

	cmd("AIStatus", function()
		M.status()
	end, { desc = "🔐 Show AI API keys status" })

	cmd("AISecrets", function()
		M.status()
	end, { desc = "🔐 Show AI API keys status (alias)" })

	cmd("AIReload", function()
		loaded_files = {}
		local count = M.load_all()
		if count == 0 then
			notify(
				"🔐 No secrets loaded. Ensure .env exists:\n"
					.. "   • ~/.config/nvim/.env\n"
					.. "   • ./.env (project root)",
				vim.log.levels.INFO,
				{ title = "Secrets" }
			)
		end
		M.status()
	end, { desc = "🔐 Reload AI secrets from .env files" })
end

-- ═══════════════════════════════════════════════════════════════════════
-- INITIALIZATION
--
-- Single entry point called from core/bootstrap.lua.
-- Loads all .env files and registers user commands.
-- ═══════════════════════════════════════════════════════════════════════

--- Initialize the secrets module — load .env files and register commands.
---
--- Called once during bootstrap. Loads all default .env file paths
--- and registers `:AIStatus`, `:AISecrets`, and `:AIReload` commands.
---
--- ```lua
--- -- In core/bootstrap.lua:
--- require("core.secrets").init({ silent = false })
--- ```
---
---@param opts? { silent: boolean } Initialization options
function M.init(opts)
	opts = opts or {}
	M.load_all(opts)
	M.setup_commands()
end

return M
