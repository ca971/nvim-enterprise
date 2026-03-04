---@file lua/langs/sql.lua
---@description SQL — LSP, formatter, linter, treesitter, Dadbod & buffer-local keymaps
---@module "langs.sql"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.python             Python language support (same architecture)
---@see langs.prisma             Prisma language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/sql.lua — SQL language support                                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("sql") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "sql" / "mysql" / "plsql"):  │    ║
--- ║  │  ├─ LSP          sqls      (SQL Language Server)                 │    ║
--- ║  │  ├─ Formatter    sql-formatter (via conform.nvim)                │    ║
--- ║  │  ├─ Linter       sqlfluff  (via nvim-lint)                       │    ║
--- ║  │  ├─ Treesitter   sql parser (syntax + folding)                   │    ║
--- ║  │  └─ Extras       vim-dadbod-ui (database GUI)                    │    ║
--- ║  │                  vim-dadbod-completion (SQL completions)         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ CONNECT   c  Connect to database (sqlite3/psql/mysql)        │    ║
--- ║  │  ├─ EXECUTE   r  Execute file/selection                          │    ║
--- ║  │  ├─ EXPLAIN   e  Explain query/selection (EXPLAIN ANALYZE)       │    ║
--- ║  │  ├─ SCHEMA    t  Show tables            d  Describe table        │    ║
--- ║  │  │            i  Connection info                                 │    ║
--- ║  │  ├─ TOOLS     x  Fix with sqlfluff                               │    ║
--- ║  │  └─ DOCS      h  SQL reference (PostgreSQL docs)                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Database connection state:                                      │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Module-local `_db_conn` table stores active connection: │    │    ║
--- ║  │  │  • client: "sqlite3" | "psql" | "mysql"                  │    │    ║
--- ║  │  │  • db: database name or file path                        │    │    ║
--- ║  │  │  • cmd: full CLI command string for piping queries       │    │    ║
--- ║  │  │                                                          │    │    ║
--- ║  │  │  Set via <leader>lc (Connect keymap).                    │    │    ║
--- ║  │  │  Used by Execute, Explain, Schema keymaps.               │    │    ║
--- ║  │  │  Falls back to auto-detecting *.db files for sqlite3.    │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Client auto-detection (for <leader>lc):                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Scans PATH for available SQL clients:                   │    │    ║
--- ║  │  │  • sqlite3 → prompts for database file                   │    │    ║
--- ║  │  │  • psql    → prompts for connection string / dbname      │    │    ║
--- ║  │  │  • mysql   → prompts for database name                   │    │    ║
--- ║  │  │  Presents only available clients via vim.ui.select()     │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Schema introspection (client-specific):                         │    ║
--- ║  │  ┌─────────────┬────────────────────────────────────────────┐    │    ║
--- ║  │  │  Client     │  Tables           │  Describe              │    │    ║
--- ║  │  │  sqlite3    │  .tables          │  .schema <table>       │    │    ║
--- ║  │  │  psql       │  \dt              │  \d <table>            │    │    ║
--- ║  │  │  mysql      │  SHOW TABLES;     │  DESCRIBE <table>;     │    │    ║
--- ║  │  └─────────────┴────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType sql / mysql / plsql):               ║
--- ║  • tabstop=2, shiftwidth=2         (2-space indentation)                 ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • commentstring="-- %s"           (SQL uses -- comments)                ║
--- ║  • wrap=false                                                            ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if SQL support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("sql") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string SQL Nerd Font icon (trailing whitespace stripped)
local sql_icon = icons.lang.sql:gsub("%s+$", "")

---@type string[] Filetypes covered by this module
local sql_fts = { "sql", "mysql", "plsql" }

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUPS
--
-- Registers the <leader>l group label for all SQL-family filetypes.
-- All three filetypes share the same icon and keymap prefix.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("sql", "SQL", sql_icon)
keys.lang_group("mysql", "SQL", sql_icon)
keys.lang_group("plsql", "SQL", sql_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE
--
-- Module-local database connection state. Set by the Connect keymap
-- (<leader>lc) and consumed by Execute, Explain, and Schema keymaps.
-- Persists for the lifetime of the Neovim session (not saved to disk).
-- ═══════════════════════════════════════════════════════════════════════════

---@class SqlConnection
---@field client string SQL client name (`"sqlite3"`, `"psql"`, or `"mysql"`)
---@field db string Database identifier (file path or connection string)
---@field cmd string Full CLI command string for piping queries via stdin

---@type SqlConnection|nil Active database connection, or `nil` if not connected
local _db_conn = nil

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that an active database connection exists.
---
--- If no connection is active, notifies the user to connect first
--- via `<leader>lc`. Used as a guard in keymaps that require a
--- database connection.
---
--- ```lua
--- if not check_connection() then return end
--- vim.cmd.terminal(_db_conn.cmd .. " < query.sql")
--- ```
---
---@return boolean connected `true` if `_db_conn` is set
---@private
local function check_connection()
	if not _db_conn then
		vim.notify(
			"No database connection. Use <leader>lc first.",
			vim.log.levels.WARN,
			{ title = "SQL" }
		)
		return false
	end
	return true
end

--- Write a query string to a temporary `.sql` file.
---
--- Creates a temp file via `vim.fn.tempname()` with a `.sql` extension,
--- writes the query content, and returns the path. Used to pipe queries
--- to CLI clients via stdin redirection.
---
---@param query string The SQL query to write
---@return string path Absolute path to the temporary file
---@private
local function write_temp_query(query)
	local tmpfile = vim.fn.tempname() .. ".sql"
	vim.fn.writefile(vim.split(query, "\n"), tmpfile)
	return tmpfile
end

--- Execute a command string in a terminal split, piping a temp file.
---
--- Combines the active connection command with stdin redirection
--- from a temporary SQL file.
---
---@param query string The SQL query or command to execute
---@private
local function exec_query(query)
	local tmpfile = write_temp_query(query)
	vim.cmd.split()
	vim.cmd.terminal(_db_conn.cmd .. " < " .. vim.fn.shellescape(tmpfile))
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CONNECTION
--
-- Database connection management. Scans PATH for available SQL clients,
-- presents a selection menu, then prompts for database details.
-- The connection is stored in the module-local `_db_conn` table.
-- ═══════════════════════════════════════════════════════════════════════════

--- Connect to a database via an interactive picker.
---
--- Scans PATH for available SQL clients (sqlite3, psql, mysql),
--- presents only the available ones via `vim.ui.select()`, then
--- prompts for the database identifier (file path or connection
--- string depending on the client).
---
--- The resulting connection is stored in `_db_conn` and used by
--- all subsequent Execute, Explain, and Schema keymaps.
keys.lang_map(sql_fts, "n", "<leader>lc", function()
	---@type { name: string, prompt: string, builder: fun(db: string): string }[]
	local clients = {
		{
			name = "sqlite3",
			prompt = "Database file: ",
			builder = function(db) return "sqlite3 " .. vim.fn.shellescape(db) end,
		},
		{
			name = "psql",
			prompt = "Connection string (or dbname): ",
			builder = function(db) return "psql " .. vim.fn.shellescape(db) end,
		},
		{
			name = "mysql",
			prompt = "Database: ",
			builder = function(db) return "mysql " .. db end,
		},
	}

	local available = vim.tbl_filter(function(c)
		return vim.fn.executable(c.name) == 1
	end, clients)

	if #available == 0 then
		vim.notify(
			"No SQL client found (sqlite3, psql, mysql)",
			vim.log.levels.WARN,
			{ title = "SQL" }
		)
		return
	end

	vim.ui.select(
		vim.tbl_map(function(c) return c.name end, available),
		{ prompt = sql_icon .. " Database client:" },
		function(_, idx)
			if not idx then return end
			local client = available[idx]
			vim.ui.input({ prompt = client.prompt, completion = "file" }, function(db)
				if not db or db == "" then return end
				_db_conn = {
					client = client.name,
					db = db,
					cmd = client.builder(db),
				}
				vim.notify(
					"Connected: " .. client.name .. " → " .. db,
					vim.log.levels.INFO,
					{ title = "SQL" }
				)
			end)
		end
	)
end, { desc = icons.dev.Database .. " Connect" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — EXECUTE
--
-- Query execution against the active database connection.
-- Supports both full-file execution and visual selection.
-- Falls back to auto-detecting SQLite database files in CWD.
-- ═══════════════════════════════════════════════════════════════════════════

--- Execute the current SQL file against the active connection.
---
--- If a connection is active (`_db_conn`), pipes the file to the
--- client via stdin redirection.
---
--- Fallback (no connection): scans CWD for `*.db`, `*.sqlite3`,
--- `*.sqlite` files and auto-connects to the first one found
--- using `sqlite3`. This provides a zero-config experience for
--- simple SQLite workflows.
keys.lang_map(sql_fts, "n", "<leader>lr", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")

	if _db_conn then
		vim.cmd.split()
		vim.cmd.terminal(_db_conn.cmd .. " < " .. vim.fn.shellescape(file))
		return
	end

	-- ── Fallback: auto-detect SQLite databases in CWD ────────────
	---@type string[]
	local dbs = vim.fn.glob("*.db", false, true)
	vim.list_extend(dbs, vim.fn.glob("*.sqlite3", false, true))
	vim.list_extend(dbs, vim.fn.glob("*.sqlite", false, true))

	if #dbs > 0 and vim.fn.executable("sqlite3") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("sqlite3 " .. vim.fn.shellescape(dbs[1]) .. " < " .. vim.fn.shellescape(file))
	else
		vim.notify(
			"No database connection. Use <leader>lc first.",
			vim.log.levels.WARN,
			{ title = "SQL" }
		)
	end
end, { desc = icons.ui.Play .. " Execute file" })

--- Execute the visual selection as a SQL query.
---
--- Yanks the selection into register `z`, writes it to a temp file,
--- then pipes it to the active database connection. Requires an
--- active connection via `<leader>lc`.
keys.lang_map(sql_fts, "v", "<leader>lr", function()
	vim.cmd('noautocmd normal! "zy')
	local query = vim.fn.getreg("z")
	if query == "" then return end
	if not check_connection() then return end
	exec_query(query)
end, { desc = icons.ui.Play .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — EXPLAIN
--
-- Query plan analysis using EXPLAIN ANALYZE.
-- Wraps the query (or file content) with `EXPLAIN ANALYZE` prefix
-- and pipes it to the active connection.
-- ═══════════════════════════════════════════════════════════════════════════

--- Explain the query plan for the current file.
---
--- Reads the file content, strips trailing semicolons, wraps with
--- `EXPLAIN ANALYZE`, then pipes to the active connection.
--- Requires an active database connection.
keys.lang_map(sql_fts, "n", "<leader>le", function()
	vim.cmd("silent! write")
	if not check_connection() then return end

	local file = vim.fn.expand("%:p")
	local content = table.concat(vim.fn.readfile(file), " "):gsub(";%s*$", "")
	local explain = "EXPLAIN ANALYZE " .. content .. ";"
	exec_query(explain)
end, { desc = sql_icon .. " Explain query" })

--- Explain the query plan for the visual selection.
---
--- Yanks the selection, strips trailing semicolons, wraps with
--- `EXPLAIN ANALYZE`, then pipes to the active connection.
keys.lang_map(sql_fts, "v", "<leader>le", function()
	vim.cmd('noautocmd normal! "zy')
	local query = vim.fn.getreg("z"):gsub(";%s*$", "")
	if query == "" then return end
	if not check_connection() then return end

	local explain = "EXPLAIN ANALYZE " .. query .. ";"
	exec_query(explain)
end, { desc = sql_icon .. " Explain selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SCHEMA
--
-- Database schema introspection. Commands adapt to the active client
-- (sqlite3 / psql / mysql) using client-specific syntax.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show all tables in the connected database.
---
--- Adapts the command to the active client:
--- - **sqlite3** → `.tables`
--- - **psql** → `\dt`
--- - **mysql** → `SHOW TABLES;`
keys.lang_map(sql_fts, "n", "<leader>lt", function()
	if not check_connection() then return end

	---@type string
	local query
	if _db_conn.client == "sqlite3" then
		query = ".tables"
	elseif _db_conn.client == "psql" then
		query = "\\dt"
	else
		query = "SHOW TABLES;"
	end

	exec_query(query)
end, { desc = icons.ui.List .. " Show tables" })

--- Describe the structure of a specific table.
---
--- Prompts for a table name, then runs the client-specific
--- describe command:
--- - **sqlite3** → `.schema <table>`
--- - **psql** → `\d <table>`
--- - **mysql** → `DESCRIBE <table>;`
keys.lang_map(sql_fts, "n", "<leader>ld", function()
	if not check_connection() then return end

	vim.ui.input({ prompt = "Table name: " }, function(table_name)
		if not table_name or table_name == "" then return end

		---@type string
		local query
		if _db_conn.client == "sqlite3" then
			query = ".schema " .. table_name
		elseif _db_conn.client == "psql" then
			query = "\\d " .. table_name
		else
			query = "DESCRIBE " .. table_name .. ";"
		end

		exec_query(query)
	end)
end, { desc = icons.dev.Database .. " Describe table" })

--- Display active connection information.
---
--- Shows the current client name and database identifier in a
--- notification. Displays "No active connection" if `_db_conn`
--- is nil.
keys.lang_map(sql_fts, "n", "<leader>li", function()
	if _db_conn then
		vim.notify(
			string.format("Client: %s\nDatabase: %s", _db_conn.client, _db_conn.db),
			vim.log.levels.INFO,
			{ title = "SQL Connection" }
		)
	else
		vim.notify("No active connection", vim.log.levels.INFO, { title = "SQL" })
	end
end, { desc = icons.diagnostics.Info .. " Connection info" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TOOLS / DOCUMENTATION
--
-- SQL development utilities and external documentation access.
-- sqlfluff provides automated SQL fixing (style + best practices).
-- Documentation links to PostgreSQL command reference.
-- ═══════════════════════════════════════════════════════════════════════════

--- Auto-fix the current file with sqlfluff.
---
--- Runs `sqlfluff fix --dialect ansi` in-place on the current file,
--- then reloads the buffer. Requires `sqlfluff` to be installed
--- (notifies with install instructions if not found).
keys.lang_map(sql_fts, "n", "<leader>lx", function()
	if vim.fn.executable("sqlfluff") ~= 1 then
		vim.notify("Install: pip install sqlfluff", vim.log.levels.WARN, { title = "SQL" })
		return
	end
	vim.cmd("silent! write")
	vim.fn.system("sqlfluff fix --dialect ansi " .. vim.fn.shellescape(vim.fn.expand("%:p")))
	vim.cmd.edit()
	vim.notify("Fixed with sqlfluff", vim.log.levels.INFO, { title = "SQL" })
end, { desc = sql_icon .. " Fix (sqlfluff)" })

--- Open SQL reference documentation in the system browser.
---
--- If the cursor is on a word (SQL keyword), opens the PostgreSQL
--- documentation page for that specific command (e.g. `SELECT` →
--- `sql-select.html`). If the cursor is not on a word, opens the
--- general SQL commands index.
---
--- NOTE: Links target PostgreSQL docs. For MySQL or SQLite, consider
--- adjusting the base URL based on `_db_conn.client`.
keys.lang_map(sql_fts, "n", "<leader>lh", function()
	---@type string
	local word = vim.fn.expand("<cWORD>"):upper()
	if word ~= "" then
		vim.ui.open("https://www.postgresql.org/docs/current/sql-" .. word:lower() .. ".html")
	else
		vim.ui.open("https://www.postgresql.org/docs/current/sql-commands.html")
	end
end, { desc = icons.ui.Note .. " SQL reference" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers SQL-specific alignment presets for mini.align:
-- • sql_columns — align column definitions on whitespace
-- • sql_alias   — align AS aliases on the "AS" keyword
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("sql") then
		---@type string Alignment preset icon from icons.file
		local sql_align_icon = icons.file.Sql

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			sql_columns = {
				description = "Align SQL column definitions",
				icon = sql_align_icon,
				split_pattern = "%s+",
				category = "data",
				lang = "sql",
				filetypes = { "sql" },
			},
			sql_alias = {
				description = "Align SQL AS aliases",
				icon = sql_align_icon,
				split_pattern = "%sAS%s",
				category = "data",
				lang = "sql",
				filetypes = { "sql" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("sql", "sql_columns")
		align_registry.mark_language_loaded("sql")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("sql", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("sql_columns"), {
			desc = sql_align_icon .. "  Align SQL columns",
		})
		keys.lang_map("sql", { "n", "x" }, "<leader>aT", align_registry.make_align_fn("sql_alias"), {
			desc = sql_align_icon .. "  Align SQL aliases",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the SQL-specific
-- parts (servers, formatters, linters, parsers, Dadbod).
--
-- Loading strategy:
-- ┌──────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin               │ How it lazy-loads for SQL                    │
-- ├──────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig       │ opts merge (sqls server added)              │
-- │ mason.nvim           │ opts merge (sqls + formatter + linter)      │
-- │ conform.nvim         │ opts merge (sql_formatter for 3 filetypes) │
-- │ nvim-lint            │ opts merge (sqlfluff for sql)               │
-- │ nvim-treesitter      │ opts merge (sql parser ensured)            │
-- │ vim-dadbod-ui        │ cmd lazy load (DBUI commands)              │
-- │ vim-dadbod           │ dependency of dadbod-ui (lazy)             │
-- │ vim-dadbod-completion│ ft = sql/mysql/plsql (true lazy load)      │
-- └──────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for SQL
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- sqls: SQL Language Server (completions, diagnostics, formatting,
	-- hover, execute query). Supports multiple database backends.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				sqls = {},
			},
		},
		init = function()
			-- ── Buffer-local options for SQL files ───────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "sql", "mysql", "plsql" },
				callback = function()
					local opt = vim.opt_local

					opt.wrap = false

					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true

					opt.commentstring = "-- %s"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures sqls, sql-formatter, and sqlfluff are installed via Mason.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"sqls",
				"sql-formatter",
				"sqlfluff",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- sql-formatter for all three SQL filetypes (sql, mysql, plsql).
	-- Provides consistent formatting regardless of dialect.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				sql = { "sql_formatter" },
				mysql = { "sql_formatter" },
				plsql = { "sql_formatter" },
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- sqlfluff: SQL linter and auto-fixer (style, anti-patterns,
	-- best practices). Complements the LSP diagnostics.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = {
			linters_by_ft = {
				sql = { "sqlfluff" },
			},
		},
	},

	-- ── TREESITTER PARSER ──────────────────────────────────────────────────
	-- sql: syntax highlighting, folding, indentation
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"sql",
			},
		},
	},

	-- ── DADBOD (Database UI) ───────────────────────────────────────────────
	-- vim-dadbod-ui: interactive database GUI with query editor,
	-- result viewer, and saved queries. Lazy-loaded on `:DBUI` command.
	-- vim-dadbod: underlying database adapter (supports 15+ databases).
	-- vim-dadbod-completion: SQL completions from database schema.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"kristijanhusak/vim-dadbod-ui",
		lazy = true,
		cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
		dependencies = {
			{ "tpope/vim-dadbod", lazy = true },
			{ "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" }, lazy = true },
		},
		init = function()
			vim.g.db_ui_use_nerd_fonts = 1
		end,
	},
}
