---@file lua/core/logger.lua
---@description Logger — structured logging system with file output, vim.notify, and contextual scoping
---@module "core.logger"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.class Base OOP system (Logger extends Class)
---@see core.settings Settings uses Logger for configuration load/save events
---@see core.bootstrap Bootstrap sequence logs startup phases
---@see core.health Health checks reference log file path for diagnostics
---@see config.plugin_manager PluginManager logs plugin enable/disable events
---@see users.user_manager UserManager logs user profile switching
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/logger.lua — Structured logging with file + notification output    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Logger (extends Class)                                          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Features:                                                       │    ║
--- ║  │  • Four log levels: DEBUG < INFO < WARN < ERROR                  │    ║
--- ║  │  • Configurable minimum level (messages below are discarded)     │    ║
--- ║  │  • File output: async append to stdpath("state")/nvimenterprise.log   ║
--- ║  │  • vim.notify integration: WARN+ shown as notifications          │    ║
--- ║  │  • Contextual scoping: each logger carries a module name tag     │    ║
--- ║  │  • string.format varargs: log:info("loaded %d plugins", count)   │    ║
--- ║  │  • Factory pattern: Logger:for_module("core.settings")           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Log format:                                                     │    ║
--- ║  │    [2026-02-15 14:32:01] [INFO ] [core.settings] Settings loaded │    ║
--- ║  │    [2026-02-15 14:32:01] [ERROR] [core.lsp] Server crashed       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Output routing:                                                 │    ║
--- ║  │  ├─ DEBUG → file only (never notifies)                           │    ║
--- ║  │  ├─ INFO  → file only (never notifies)                           │    ║
--- ║  │  ├─ WARN  → file + vim.notify (if _notify_enabled)               │    ║
--- ║  │  └─ ERROR → file + vim.notify (if _notify_enabled)               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ Extends Class (not standalone) for consistency with the      │    ║
--- ║  │  │  OOP system — enables instanceof checks and super_call        │    ║
--- ║  │  ├─ Async file writes via vim.schedule + vim.uv.fs_* to avoid    │    ║
--- ║  │  │  blocking the editor during high-frequency logging            │    ║
--- ║  │  ├─ Level check is the first operation in _log() — zero cost     │    ║
--- ║  │  │  for messages below the configured threshold                  │    ║
--- ║  │  ├─ Factory :for_module() returns a NEW instance per module,     │    ║
--- ║  │  │  not a singleton — each module gets its own name/config       │    ║
--- ║  │  ├─ File permissions 0o666 (438 decimal) for multi-user envs     │    ║
--- ║  │  └─ vim.notify only for WARN+ to avoid notification fatigue      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Usage:                                                          │    ║
--- ║  │    local log = require("core.logger"):for_module("core.settings")│    ║
--- ║  │    log:info("Settings loaded in %dms", elapsed)                  │    ║
--- ║  │    log:warn("Deprecated option: %s", key)                        │    ║
--- ║  │    log:error("Failed to load: %s", err)                          │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Level gate in _log(): sub-threshold messages cost one integer compare ║
--- ║  • Varargs formatting deferred: string.format only runs if level passes  ║
--- ║  • File I/O is fully async (vim.schedule + vim.uv non-blocking API)      ║
--- ║  • No external dependencies beyond core/class.lua                        ║
--- ║  • Module cached by require() — Logger class loaded once                 ║
--- ║                                                                          ║
--- ║  Public API:                                                             ║
--- ║    Logger:for_module(name, opts)   Factory: create a scoped logger       ║
--- ║    logger:debug(msg, ...)          Log at DEBUG level                    ║
--- ║    logger:info(msg, ...)           Log at INFO level                     ║
--- ║    logger:warn(msg, ...)           Log at WARN level                     ║
--- ║    logger:error(msg, ...)          Log at ERROR level                    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local Class = require("core.class")

-- ═══════════════════════════════════════════════════════════════════════
-- CLASS DEFINITION
-- ═══════════════════════════════════════════════════════════════════════

---@alias LogLevel "DEBUG"|"INFO"|"WARN"|"ERROR"

---@class Logger : Class
---@field _name string Logger name / scope tag (e.g. `"core.settings"`)
---@field _level integer Minimum numeric log level (messages below are discarded)
---@field _file_enabled boolean Whether to write log entries to the log file
---@field _notify_enabled boolean Whether to show WARN+ messages via vim.notify
local Logger = Class:extend("Logger")

-- ═══════════════════════════════════════════════════════════════════════
-- LEVEL CONSTANTS
--
-- Numeric levels for internal comparison and the VIM_LEVELS map
-- for translating to vim.log.levels.* when calling vim.notify().
-- ═══════════════════════════════════════════════════════════════════════

--- Numeric log level constants for threshold comparison.
---
--- Order: `DEBUG (0) < INFO (1) < WARN (2) < ERROR (3)`
--- Messages with a level below the logger's `_level` are discarded
--- before any formatting or I/O occurs.
---
---@enum LogLevelEnum
Logger.LEVELS = {
	DEBUG = 0,
	INFO = 1,
	WARN = 2,
	ERROR = 3,
}

--- Mapping from LogLevel strings to `vim.log.levels.*` constants.
---
--- Used when forwarding messages to `vim.notify()`, which expects
--- the Neovim-native level enum rather than our numeric constants.
---
---@type table<LogLevel, integer>
Logger.VIM_LEVELS = {
	DEBUG = vim.log.levels.DEBUG,
	INFO = vim.log.levels.INFO,
	WARN = vim.log.levels.WARN,
	ERROR = vim.log.levels.ERROR,
}

-- ═══════════════════════════════════════════════════════════════════════
-- CONSTRUCTOR
--
-- Each Logger instance is scoped to a module name and carries its
-- own level/output configuration. The factory :for_module() is the
-- preferred entry point for consumers.
-- ═══════════════════════════════════════════════════════════════════════

--- Initialize a new Logger instance.
---
--- ```lua
--- local log = Logger:new("core.settings", { level = "DEBUG", file = true, notify = false })
--- ```
---
---@param name string Logger scope name (e.g. `"core.settings"`, `"plugins.lsp"`)
---@param opts? { level?: LogLevel, file?: boolean, notify?: boolean } Configuration options
function Logger:init(name, opts)
	opts = opts or {}
	self._name = name or "NvimEnterprise"
	self._level = Logger.LEVELS[opts.level or "INFO"]
	self._file_enabled = opts.file ~= false
	self._notify_enabled = opts.notify ~= false
end

-- ═══════════════════════════════════════════════════════════════════════
-- INTERNAL METHODS
--
-- Private methods handle log file path resolution, message formatting,
-- async file writes, and the core routing logic. All prefixed with
-- underscore to signal internal use.
-- ═══════════════════════════════════════════════════════════════════════

--- Get the absolute path to the log file.
---
--- Logs are stored in Neovim's state directory to persist across
--- sessions without polluting the config or data directories.
---
---@return string path Absolute path to `nvimenterprise.log`
---@private
function Logger:_log_path()
	return vim.fn.stdpath("state") .. "/nvimenterprise.log"
end

--- Format a log message with timestamp, level, and scope tag.
---
--- Output format: `[2026-02-15 14:32:01] [INFO ] [core.settings] Message text`
---
--- The level is left-padded to 5 characters for visual alignment
--- in the log file (`DEBUG`, `INFO `, `WARN `, `ERROR`).
---
---@param level LogLevel Log level string
---@param msg string Pre-formatted message body
---@return string formatted Complete log line (without trailing newline)
---@private
function Logger:_format(level, msg)
	local ts = os.date("%Y-%m-%d %H:%M:%S")
	return string.format("[%s] [%-5s] [%s] %s", ts, level, self._name, msg)
end

--- Write a formatted log line to the log file asynchronously.
---
--- Uses `vim.schedule()` to defer the write to the next event loop
--- iteration, then `vim.uv.fs_open/write/close` for non-blocking I/O.
--- The file is opened in append mode (`"a"`) with permissions `0o666`
--- (438 decimal) to support multi-user environments.
---
--- Silently no-ops if `_file_enabled` is `false` or if the file
--- cannot be opened (e.g., permission denied, disk full).
---
---@param formatted string Complete log line to append
---@private
function Logger:_write_file(formatted)
	if not self._file_enabled then return end
	vim.schedule(function()
		local path = self:_log_path()
		local fd = vim.uv.fs_open(path, "a", 438) -- 0o666
		if fd then
			vim.uv.fs_write(fd, formatted .. "\n")
			vim.uv.fs_close(fd)
		end
	end)
end

--- Core log routing method — all public methods delegate here.
---
--- Execution flow:
--- 1. Level gate: discard if `level < self._level` (zero cost)
--- 2. Varargs format: `string.format(msg, ...)` only if args provided
--- 3. Format: prepend timestamp, level tag, and scope name
--- 4. File write: async append (if `_file_enabled`)
--- 5. Notify: `vim.notify()` for WARN+ (if `_notify_enabled`)
---
---@param level LogLevel Log level string (`"DEBUG"`, `"INFO"`, `"WARN"`, `"ERROR"`)
---@param msg string Message body (may contain `string.format` placeholders)
---@param ... any Format arguments passed to `string.format(msg, ...)`
---@private
function Logger:_log(level, msg, ...)
	-- Level gate: cheapest possible check before any work
	if Logger.LEVELS[level] < self._level then return end

	-- Defer string.format until we know the message will be used
	if select("#", ...) > 0 then msg = string.format(msg, ...) end

	local formatted = self:_format(level, msg)

	-- Write to log file (async)
	self:_write_file(formatted)

	-- Notify user for WARN and ERROR to surface actionable issues
	if self._notify_enabled and Logger.LEVELS[level] >= Logger.LEVELS.WARN then
		vim.schedule(function()
			vim.notify(string.format("[%s] %s", self._name, msg), Logger.VIM_LEVELS[level], { title = "NvimEnterprise" })
		end)
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- PUBLIC API — LOG METHODS
--
-- Convenience methods for each log level. All delegate to _log()
-- with the appropriate level string. Supports string.format varargs.
-- ═══════════════════════════════════════════════════════════════════════

--- Log a DEBUG message.
---
--- Only written to file (never triggers vim.notify). Use for verbose
--- tracing during development.
---
--- ```lua
--- log:debug("Resolving path: %s → %s", input, resolved)
--- ```
---
---@param msg string Message body (supports `string.format` placeholders)
---@param ... any Format arguments
function Logger:debug(msg, ...)
	self:_log("DEBUG", msg, ...)
end

--- Log an INFO message.
---
--- Written to file only. Use for significant lifecycle events
--- (module loaded, settings applied, session restored).
---
--- ```lua
--- log:info("Settings loaded in %dms", elapsed)
--- ```
---
---@param msg string Message body (supports `string.format` placeholders)
---@param ... any Format arguments
function Logger:info(msg, ...)
	self:_log("INFO", msg, ...)
end

--- Log a WARN message.
---
--- Written to file AND shown via `vim.notify()` (if `_notify_enabled`).
--- Use for recoverable issues that the user should be aware of.
---
--- ```lua
--- log:warn("Deprecated option '%s', use '%s' instead", old_key, new_key)
--- ```
---
---@param msg string Message body (supports `string.format` placeholders)
---@param ... any Format arguments
function Logger:warn(msg, ...)
	self:_log("WARN", msg, ...)
end

--- Log an ERROR message.
---
--- Written to file AND shown via `vim.notify()` (if `_notify_enabled`).
--- Use for failures that may affect functionality.
---
--- ```lua
--- log:error("Failed to load plugin '%s': %s", name, err)
--- ```
---
---@param msg string Message body (supports `string.format` placeholders)
---@param ... any Format arguments
function Logger:error(msg, ...)
	self:_log("ERROR", msg, ...)
end

-- ═══════════════════════════════════════════════════════════════════════
-- FACTORY
--
-- Preferred entry point for consumers. Creates a new Logger instance
-- scoped to a specific module name. Each module gets its own logger
-- with independent configuration (not a singleton — unlike Platform).
-- ═══════════════════════════════════════════════════════════════════════

--- Create a namespaced logger for a specific module.
---
--- Factory method — the recommended way to obtain a Logger instance.
--- Each call creates a new independent Logger scoped to the given
--- module name.
---
--- ```lua
--- -- In core/settings.lua:
--- local log = require("core.logger"):for_module("core.settings")
--- log:info("Settings loaded")
--- log:warn("Unknown key '%s' in user config", key)
---
--- -- In plugins/code/lsp/init.lua:
--- local log = require("core.logger"):for_module("plugins.code.lsp")
--- log:debug("Attaching LSP to buffer %d", bufnr)
--- ```
---
---@param name string Module or component name (e.g. `"core.settings"`)
---@param opts? { level?: LogLevel, file?: boolean, notify?: boolean } Logger configuration
---@return Logger logger New Logger instance scoped to `name`
function Logger:for_module(name, opts)
	return Logger:new(name, opts) --[[@as Logger]]
end

return Logger
