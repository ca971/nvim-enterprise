---@file lua/core/security.lua
---@description Security — path validation, namespace sanitization, safe loading, and settings validation
---@module "core.security"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.class Base OOP system (Security extends Class)
---@see core.utils Utility functions (file_exists, starts_with, tbl_get, safe_require)
---@see core.secrets Secrets module (complementary — API key management)
---@see core.settings Settings validation uses Security:validate_settings()
---@see users.user_manager UserManager uses Security:validate_namespace()
---@see users.namespace Namespace resolution uses Security:validate_path()
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/security.lua — Security utilities for safe file/module loading     ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Security (singleton, extends Class)                             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Security layers:                                                │    ║
--- ║  │  ├─ Path validation                                              │    ║
--- ║  │  │  • Resolves symlinks and normalizes to absolute path          │    ║
--- ║  │  │  • Rejects paths outside stdpath("config") (traversal guard)  │    ║
--- ║  │  │  • Prevents ../../etc/passwd style attacks                    │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Namespace validation                                         │    ║
--- ║  │  │  • Alphanumeric + hyphens + underscores only                  │    ║
--- ║  │  │  • Must start with a letter (no leading digits/symbols)       │    ║
--- ║  │  │  • Max 64 characters (prevents filesystem issues)             │    ║
--- ║  │  │  • Reserved names blocked: init, core, config, plugins, etc.  │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ Safe file loading                                            │    ║
--- ║  │  │  • safe_dofile(): path validation + pcall(dofile, ...)        │    ║
--- ║  │  │  • safe_require(): delegates to utils.safe_require()          │    ║
--- ║  │  │  • Both return nil + error string on failure (no throws)      │    ║
--- ║  │  │                                                               │    ║
--- ║  │  └─ Settings validation                                          │    ║
--- ║  │     • Type-checks critical settings keys after merge             │    ║
--- ║  │     • Returns list of validation errors (not assertions)         │    ║
--- ║  │     • Allows nil values (only checks type when present)          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ Singleton pattern — one Security instance for the lifetime   │    ║
--- ║  │  ├─ All methods return (value, error) tuples — never throw       │    ║
--- ║  │  │  Callers decide whether to log, notify, or abort              │    ║
--- ║  │  ├─ Path validation uses vim.fn.resolve() to follow symlinks     │    ║
--- ║  │  │  before comparison (symlink outside config → rejected)        │    ║
--- ║  │  ├─ Namespace blocked list excludes "default" intentionally —    │    ║
--- ║  │  │  it's a valid user profile name, not a system module          │    ║
--- ║  │  ├─ validate_settings() checks type-when-present (not required)  │    ║
--- ║  │  │  so partial settings tables (user overrides) are valid        │    ║
--- ║  │  └─ Extends Class for consistency with the OOP system, even      │    ║
--- ║  │     though Security has no mutable state                         │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Singleton: instantiated once, cached by require()                     ║
--- ║  • No file I/O in validation methods (only path string operations)       ║
--- ║  • Reserved name check uses sequential scan (6 entries - O(1) in practice║
--- ║  • validate_settings() collects all errors in one pass (no early exit)   ║
--- ║                                                                          ║
--- ║  Public API:                                                             ║
--- ║    security:validate_path(path)            Reject paths outside config   ║
--- ║    security:validate_namespace(name)        Sanitize user namespace names║
--- ║    security:safe_dofile(path)              Path-validated dofile()       ║
--- ║    security:safe_require(modname)           Error-safe require()         ║
--- ║    security:validate_settings(settings)     Type-check settings table    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local Class = require("core.class")
local utils = require("core.utils")

-- ═══════════════════════════════════════════════════════════════════════
-- CLASS DEFINITION
-- ═══════════════════════════════════════════════════════════════════════

---@class Security : Class
local Security = Class:extend("Security")

-- ═══════════════════════════════════════════════════════════════════════
-- PATH VALIDATION
--
-- Prevents directory traversal attacks by ensuring all loaded files
-- reside within the Neovim config directory. Symlinks are resolved
-- before comparison so a symlink pointing outside config is rejected.
-- ═══════════════════════════════════════════════════════════════════════

--- Validate that a path is within the Neovim config directory.
---
--- Resolves symlinks and normalizes to an absolute path before
--- checking containment. Prevents directory traversal attacks
--- (e.g., `../../etc/passwd`).
---
--- ```lua
--- local ok, err = security:validate_path("~/.config/nvim/lua/core/init.lua")
--- -- ok = true, err = nil
---
--- local ok, err = security:validate_path("/etc/passwd")
--- -- ok = false, err = "Path '/etc/passwd' is outside config directory '...'"
--- ```
---
---@param path string Path to validate (absolute, relative, or with `~`)
---@return boolean valid `true` if the path is inside the config directory
---@return string|nil error Error message if validation fails, `nil` on success
function Security:validate_path(path)
	local config_dir = vim.fn.stdpath("config") --[[@as string]]
	local resolved = vim.fn.resolve(vim.fn.expand(path))
	local canonical = vim.fn.fnamemodify(resolved, ":p")

	if not utils.starts_with(canonical, config_dir) then
		return false, string.format("Path '%s' is outside config directory '%s'", canonical, config_dir)
	end
	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════════
-- NAMESPACE VALIDATION
--
-- Sanitizes user profile names to prevent filesystem and Lua module
-- system issues. Rules:
-- • Must start with a letter (Lua module names can't start with digits)
-- • Only [a-zA-Z0-9_-] (filesystem-safe, no spaces or special chars)
-- • Max 64 characters (prevents long path issues on some OS)
-- • Reserved system module names are blocked
-- ═══════════════════════════════════════════════════════════════════════

--- Validate a user namespace name for safety and correctness.
---
--- Enforces naming rules that ensure the namespace works as both
--- a filesystem directory name and a Lua module path segment.
---
--- Rules:
--- 1. Must be a non-empty string
--- 2. Max 64 characters
--- 3. Must start with a letter
--- 4. Only `[a-zA-Z0-9_-]` characters allowed
--- 5. Must not be a reserved system module name
---
--- NOTE: `"default"` is intentionally NOT blocked — it's a valid
--- user profile name, distinct from system modules like `"core"`.
---
--- ```lua
--- security:validate_namespace("bly")       --> true, nil
--- security:validate_namespace("jane-doe")  --> true, nil
--- security:validate_namespace("default")   --> true, nil
--- security:validate_namespace("core")      --> false, "'core' is a reserved name"
--- security:validate_namespace("123bad")    --> false, "must start with a letter..."
--- ```
---
---@param name string Namespace name to validate
---@return boolean valid `true` if the name is safe to use
---@return string|nil error Error message if validation fails, `nil` on success
function Security:validate_namespace(name)
	if type(name) ~= "string" or #name == 0 then return false, "Namespace name must be a non-empty string" end
	if #name > 64 then return false, "Namespace name must be 64 characters or fewer" end
	if not name:match("^[a-zA-Z][a-zA-Z0-9_%-]*$") then
		return false, "Namespace name must start with a letter and contain only [a-zA-Z0-9_-]"
	end

	-- Reserved system module names that would conflict with the
	-- config directory structure (users/<name>/ would shadow these)
	local blocked = { "init", "core", "config", "plugins", "langs", "class" }
	for _, r in ipairs(blocked) do
		if name == r then return false, string.format("'%s' is a reserved name", name) end
	end

	return true, nil
end

-- ═══════════════════════════════════════════════════════════════════════
-- SAFE FILE LOADING
--
-- Wrappers around dofile() and require() that add path validation
-- and error handling. Both return (result, nil) on success or
-- (nil, error_string) on failure — never throw.
-- ═══════════════════════════════════════════════════════════════════════

--- Safely load a Lua file using `dofile()` with path validation.
---
--- Validates that the file is within the config directory and exists
--- before attempting to load it. Uses `pcall(dofile, ...)` to catch
--- syntax errors and runtime errors during file execution.
---
--- ```lua
--- local result, err = security:safe_dofile(vim.fn.stdpath("config") .. "/settings.lua")
--- if not result then
---   log:error("Failed: %s", err)
--- end
--- ```
---
---@param path string Absolute path to the Lua file
---@return any|nil result Return value of the loaded file, or `nil` on failure
---@return string|nil error Error message on failure, `nil` on success
function Security:safe_dofile(path)
	local valid, err = self:validate_path(path)
	if not valid then return nil, err end
	if not utils.file_exists(path) then return nil, "File does not exist: " .. path end
	local ok, result = pcall(dofile, path)
	if not ok then return nil, string.format("Error loading '%s': %s", path, tostring(result)) end
	return result, nil
end

--- Safely require a Lua module with error handling.
---
--- Delegates to `utils.safe_require()` which wraps `require()` in
--- `pcall()`. Unlike `safe_dofile()`, no path validation is performed
--- because `require()` uses Lua's module resolution system.
---
---@param modname string Module name (e.g. `"core.settings"`)
---@return any|nil module The loaded module, or `nil` on failure
---@return string|nil error Error message on failure, `nil` on success
function Security:safe_require(modname)
	return utils.safe_require(modname)
end

-- ═══════════════════════════════════════════════════════════════════════
-- SETTINGS VALIDATION
--
-- Type-checks critical keys in a settings table after merge.
-- Designed to catch configuration errors early (during bootstrap)
-- rather than at plugin load time. Checks type-when-present:
-- nil values are allowed (the key may be optional or provided
-- by defaults), but wrong types are flagged.
-- ═══════════════════════════════════════════════════════════════════════

--- Validate a settings table structure and types.
---
--- Checks that critical settings keys (when present) have the
--- expected Lua type. Collects all errors in a single pass rather
--- than aborting on the first mismatch, so the user sees all
--- problems at once.
---
--- NOTE: `nil` values are allowed — this method only checks type
--- when a key IS present. This supports partial settings tables
--- (e.g., user overrides that only define a subset of keys).
---
--- ```lua
--- local valid, errors = security:validate_settings(merged_settings)
--- if not valid then
---   for _, err in ipairs(errors) do
---     log:error(err)
---   end
--- end
--- ```
---
---@param settings table The settings table to validate (typically the merged result)
---@return boolean valid `true` if all present keys have correct types
---@return string[] errors List of validation error messages (empty if valid)
function Security:validate_settings(settings)
	local errors = {}

	--- Check that a settings key has the expected type (if present).
	---@param path string Dot-separated settings path
	---@param expected_type string Expected Lua type name
	local function check(path, expected_type)
		local val = utils.tbl_get(settings, path)
		if val ~= nil and type(val) ~= expected_type then
			table.insert(errors, string.format("settings.%s: expected %s, got %s", path, expected_type, type(val)))
		end
	end

	-- ── Top-level keys ───────────────────────────────────────────────
	check("active_user", "string")

	-- ── UI settings ──────────────────────────────────────────────────
	check("ui", "table")
	check("ui.colorscheme", "string")

	-- ── Editor settings ──────────────────────────────────────────────
	check("editor", "table")
	check("editor.tab_size", "number")

	-- ── Plugin settings ──────────────────────────────────────────────
	check("plugins", "table")
	check("plugins.disabled", "table")

	-- ── Language settings ────────────────────────────────────────────
	check("languages", "table")
	check("languages.enabled", "table")

	-- ── LSP settings ─────────────────────────────────────────────────
	check("lsp", "table")

	-- ── AI settings ──────────────────────────────────────────────────
	check("ai", "table")

	-- ── Performance settings ─────────────────────────────────────────
	check("performance", "table")

	return #errors == 0, errors
end

-- ═══════════════════════════════════════════════════════════════════════
-- SINGLETON
--
-- Security has no mutable state, but is instantiated as a singleton
-- for consistency with the OOP system and to enable instanceof checks.
-- ═══════════════════════════════════════════════════════════════════════

return Security:new() --[[@as Security]]
