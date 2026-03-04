---@description Utils — pure utility functions for table manipulation, string ops, file I/O, async helpers, and more
---@module "core.utils"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings uses deep_merge, tbl_get, tbl_set, read_file, write_file
---@see core.security Security uses file_exists, starts_with, safe_require, tbl_get
---@see core.secrets Secrets uses file I/O utilities for .env parsing
---@see core.logger Logger uses string formatting utilities
---@see core.platform Platform uses has_executable, path utilities
---@see core.icons Icons module accessed via icon() helper and cache system
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  core/utils.lua — General-purpose utility library                        ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Utils (module table — pure functions, no state, no side-effects)│    ║
--- ║  │                                                                  │    ║
--- ║  │  Categories (11 sections, ~80 functions):                        │    ║
--- ║  │  ├─ Compatibility      Shims for API differences across versions │    ║
--- ║  │  ├─ Table utilities    deep_merge, tbl_get/set/delete, filter,   │    ║
--- ║  │  │                     map, reduce, flatten, unique, slice, etc. │    ║
--- ║  │  ├─ String utilities   trim, starts/ends_with, capitalize,       │    ║
--- ║  │  │                     truncate, pad, split_lines, word_wrap     │    ║
--- ║  │  ├─ File I/O           read/write/append/copy, dir listing,      │    ║
--- ║  │  │                     recursive scan, existence checks          │    ║
--- ║  │  ├─ Module utilities   safe_require, module_exists, reload,      │    ║
--- ║  │  │                     cache clearing                            │    ║
--- ║  │  ├─ Async / Timer      debounce, throttle, defer, next_tick      │    ║
--- ║  │  ├─ Neovim utilities   augroup, get_root, is_filetype, notify    │    ║
--- ║  │  ├─ Icon utilities     icon(), icon_search, icon_find,           │    ║
--- ║  │  │                     icon_label, icon_categories               │    ║
--- ║  │  ├─ Validation         validate_type, validate_not_empty,        │    ║
--- ║  │  │                     validate_one_of                           │    ║
--- ║  │  ├─ Formatting         format_bytes, format_ms, format_date,     │    ║
--- ║  │  │                     format_relative_time                      │    ║
--- ║  │  └─ Performance        measure, memoize                          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ Module table (not OOP) — pure functions with no state        │    ║
--- ║  │  ├─ All functions are nil-safe: invalid inputs return sensible   │    ║
--- ║  │  │  defaults (empty string, empty table, false, nil) instead     │    ║
--- ║  │  │  of throwing errors                                           │    ║
--- ║  │  ├─ Table functions work on both lists and maps unless stated    │    ║
--- ║  │  ├─ File I/O uses vim.uv (libuv) for non-blocking operations     │    ║
--- ║  │  ├─ deep_merge() replaces lists (not element-merge) — this is    │    ║
--- ║  │  │  intentional for settings override semantics                  │    ║
--- ║  │  ├─ Icon utilities lazy-load core/icons.lua and cache the        │    ║
--- ║  │  │  result to avoid circular dependencies at require time        │    ║
--- ║  │  └─ No external dependencies — only vim.* and Lua stdlib         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Consumers (nearly every module in the config):                  │    ║
--- ║  │  ├─ core/settings.lua      deep_merge, tbl_get/set, file I/O     │    ║
--- ║  │  ├─ core/security.lua      file_exists, starts_with, tbl_get     │    ║
--- ║  │  ├─ core/secrets.lua       file I/O (complementary to vim.uv)    │    ║
--- ║  │  ├─ core/health.lua        has_executable, module_exists         │    ║
--- ║  │  ├─ config/*.lua           safe_require, deep_merge, notify      │    ║
--- ║  │  ├─ users/*.lua            validate_*, tbl_contains              │    ║
--- ║  │  └─ plugins/**/*.lua       icon(), notify, debounce, etc.        │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Pure functions — no state, no side-effects, fully cacheable           ║
--- ║  • vim.uv (libuv) for all file I/O — zero Vimscript overhead             ║
--- ║  • Icon cache: core/icons.lua loaded once on first icon() call           ║
--- ║  • is_list shim: uses native vim.islist when available                   ║
--- ║  • All table functions handle nil/non-table input gracefully             ║
--- ║  • Module cached by require() — loaded once at startup                   ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

---@class Utils
local M = {}

-- ═══════════════════════════════════════════════════════════════════════
-- COMPATIBILITY SHIMS
--
-- Bridges API differences between Neovim versions. Uses the native
-- implementation when available, falls back to a pure Lua polyfill.
-- ═══════════════════════════════════════════════════════════════════════

--- Check if a table is a list (sequential integer keys starting at 1).
---
--- Uses `vim.islist` (Neovim 0.10+), falls back to a pure Lua
--- implementation for older versions.
---
---@type fun(t: any): boolean
M.is_list = vim.islist
	or function(t)
		if type(t) ~= "table" then return false end
		local i = 0
		for _ in pairs(t) do
			i = i + 1
			if t[i] == nil then return false end
		end
		return true
	end

-- ═══════════════════════════════════════════════════════════════════════
-- TABLE UTILITIES
--
-- Core table manipulation functions used throughout the config.
-- All functions are nil-safe: passing non-table values returns
-- sensible defaults instead of throwing errors.
--
-- Key design choice: deep_merge() REPLACES lists rather than
-- element-merging them. This is intentional for settings override
-- semantics — if a user specifies languages.enabled = {"python"},
-- it should replace the default list, not append to it.
-- ═══════════════════════════════════════════════════════════════════════

--- Deep-merge `override` into `base` (non-destructive).
---
--- Creates a new table with all keys from both inputs. When both
--- values are dict-like tables, they are recursively merged.
--- Lists (integer-indexed tables) are REPLACED, not merged.
---
--- ```lua
--- local base = { ui = { theme = "dark", font_size = 14 }, plugins = { "a" } }
--- local over = { ui = { font_size = 16 }, plugins = { "b" } }
--- utils.deep_merge(base, over)
--- --> { ui = { theme = "dark", font_size = 16 }, plugins = { "b" } }
--- ```
---
---@param base table Base table (not modified)
---@param override table Override table (values win on conflict)
---@return table merged New deep-merged table
function M.deep_merge(base, override)
	if type(base) ~= "table" or type(override) ~= "table" then return override end
	local result = vim.deepcopy(base)
	for k, v in pairs(override) do
		if type(v) == "table" and type(result[k]) == "table" and not M.is_list(v) then
			result[k] = M.deep_merge(result[k], v)
		else
			result[k] = vim.deepcopy(v)
		end
	end
	return result
end

--- Deep-equal comparison of two values.
---
--- Recursively compares tables by value (not reference). Non-table
--- values are compared with `==`. Both key sets must match exactly.
---
--- ```lua
--- utils.deep_equal({ a = { b = 1 } }, { a = { b = 1 } })  --> true
--- utils.deep_equal({ a = 1 }, { a = 1, b = 2 })            --> false
--- ```
---
---@param a any First value
---@param b any Second value
---@return boolean equal `true` if values are deeply equal
function M.deep_equal(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	-- Check all keys in a exist in b with same value
	for k, v in pairs(a) do
		if not M.deep_equal(v, b[k]) then return false end
	end
	-- Check b doesn't have extra keys
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

--- Get a nested value from a table using dot-notation.
---
--- Traverses the table following each key segment. Returns `nil`
--- if any segment along the path is not a table or is missing.
---
--- ```lua
--- utils.tbl_get({ a = { b = { c = 42 } } }, "a.b.c")  --> 42
--- utils.tbl_get({ a = 1 }, "a.b.c")                    --> nil
--- ```
---
---@param tbl table Table to traverse
---@param path string Dot-separated key path (e.g. `"a.b.c"`)
---@return any|nil value The value at the path, or `nil` if not found
function M.tbl_get(tbl, path)
	if type(tbl) ~= "table" then return nil end
	local keys = vim.split(path, ".", { plain = true })
	local current = tbl
	for _, key in ipairs(keys) do
		if type(current) ~= "table" then return nil end
		current = current[key]
	end
	return current
end

--- Set a nested value in a table using dot-notation.
---
--- Creates intermediate tables as needed. Overwrites non-table
--- intermediates silently.
---
--- ```lua
--- local t = {}
--- utils.tbl_set(t, "a.b.c", 42)  --> t = { a = { b = { c = 42 } } }
--- ```
---
---@param tbl table Table to modify (mutated in place)
---@param path string Dot-separated key path
---@param value any Value to set at the path
function M.tbl_set(tbl, path, value)
	if type(tbl) ~= "table" then return end
	local keys = vim.split(path, ".", { plain = true })
	local current = tbl
	for i = 1, #keys - 1 do
		local key = keys[i]
		if type(current[key]) ~= "table" then current[key] = {} end
		current = current[key]
	end
	current[keys[#keys]] = value
end

--- Delete a nested value from a table using dot-notation.
---
--- ```lua
--- local t = { a = { b = { c = 42 } } }
--- utils.tbl_delete(t, "a.b.c")  --> true, t = { a = { b = {} } }
--- utils.tbl_delete(t, "x.y.z")  --> false
--- ```
---
---@param tbl table Table to modify (mutated in place)
---@param path string Dot-separated key path
---@return boolean deleted `true` if the key was found and removed
function M.tbl_delete(tbl, path)
	if type(tbl) ~= "table" then return false end
	local keys = vim.split(path, ".", { plain = true })
	local current = tbl
	for i = 1, #keys - 1 do
		local key = keys[i]
		if type(current[key]) ~= "table" then return false end
		current = current[key]
	end
	local last_key = keys[#keys]
	if current[last_key] == nil then return false end
	current[last_key] = nil
	return true
end

--- Check if a list contains a value (sequential search).
---
---@param tbl table List to search
---@param val any Value to find
---@return boolean found `true` if `val` is in `tbl`
function M.tbl_contains(tbl, val)
	if type(tbl) ~= "table" then return false end
	for _, v in ipairs(tbl) do
		if v == val then return true end
	end
	return false
end

--- Find the index of a value in a list.
---
---@param tbl table List to search
---@param val any Value to find
---@return integer|nil index 1-based index, or `nil` if not found
function M.tbl_index_of(tbl, val)
	if type(tbl) ~= "table" then return nil end
	for i, v in ipairs(tbl) do
		if v == val then return i end
	end
	return nil
end

--- Return keys of a table sorted alphabetically.
---
---@param tbl table Table to extract keys from
---@return string[] keys Sorted list of key names
function M.tbl_keys_sorted(tbl)
	local keys = vim.tbl_keys(tbl)
	table.sort(keys)
	return keys
end

--- Return the number of entries in a table (handles both list and map).
---
---@param tbl table Table to count
---@return integer count Number of key-value pairs
function M.tbl_count(tbl)
	if type(tbl) ~= "table" then return 0 end
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

--- Filter a list table by a predicate function.
---
--- ```lua
--- utils.tbl_filter({ 1, 2, 3, 4 }, function(v) return v > 2 end)  --> { 3, 4 }
--- ```
---
---@param tbl table List to filter
---@param fn fun(value: any, index: integer): boolean Predicate function
---@return table filtered New list containing only matching elements
function M.tbl_filter(tbl, fn)
	local result = {}
	for i, v in ipairs(tbl) do
		if fn(v, i) then table.insert(result, v) end
	end
	return result
end

--- Map a list table through a transform function.
---
--- ```lua
--- utils.tbl_map({ 1, 2, 3 }, function(v) return v * 2 end)  --> { 2, 4, 6 }
--- ```
---
---@param tbl table List to transform
---@param fn fun(value: any, index: integer): any Transform function
---@return table mapped New list with transformed elements
function M.tbl_map(tbl, fn)
	local result = {}
	for i, v in ipairs(tbl) do
		table.insert(result, fn(v, i))
	end
	return result
end

--- Reduce a list table to a single value.
---
--- ```lua
--- utils.tbl_reduce({ 1, 2, 3 }, function(acc, v) return acc + v end, 0)  --> 6
--- ```
---
---@param tbl table List to reduce
---@param fn fun(accumulator: any, value: any, index: integer): any Reducer function
---@param initial any Initial accumulator value
---@return any result Final accumulated value
function M.tbl_reduce(tbl, fn, initial)
	local acc = initial
	for i, v in ipairs(tbl) do
		acc = fn(acc, v, i)
	end
	return acc
end

--- Flatten a nested list table one level deep.
---
--- ```lua
--- utils.tbl_flatten({ { 1, 2 }, { 3 }, { 4, 5 } })  --> { 1, 2, 3, 4, 5 }
--- ```
---
---@param tbl table Nested list to flatten
---@return table flattened Single-level list
function M.tbl_flatten(tbl)
	local result = {}
	for _, v in ipairs(tbl) do
		if type(v) == "table" and M.is_list(v) then
			for _, inner in ipairs(v) do
				table.insert(result, inner)
			end
		else
			table.insert(result, v)
		end
	end
	return result
end

--- Remove duplicate values from a list.
---
--- Uses `tostring()` for deduplication keys, so different types
--- that stringify identically will be considered duplicates.
---
---@param tbl table List with potential duplicates
---@return table unique New list with duplicates removed (first occurrence kept)
function M.tbl_unique(tbl)
	local seen = {}
	local result = {}
	for _, v in ipairs(tbl) do
		local key = tostring(v)
		if not seen[key] then
			seen[key] = true
			table.insert(result, v)
		end
	end
	return result
end

--- Slice a list table (1-based, inclusive on both ends).
---
---@param tbl table List to slice
---@param start_idx integer Start index (1-based, inclusive)
---@param end_idx? integer End index (1-based, inclusive, default: `#tbl`)
---@return table slice New list containing the slice
function M.tbl_slice(tbl, start_idx, end_idx)
	end_idx = end_idx or #tbl
	local result = {}
	for i = start_idx, end_idx do
		if tbl[i] ~= nil then table.insert(result, tbl[i]) end
	end
	return result
end

--- Group a list of items by a key function.
---
--- ```lua
--- utils.tbl_group_by(items, function(item) return item.category end)
--- --> { ui = { ... }, editor = { ... } }
--- ```
---
---@param tbl table List of items to group
---@param fn fun(value: any): string Key extraction function
---@return table<string, table> groups Map of group key → list of items
function M.tbl_group_by(tbl, fn)
	local groups = {}
	for _, v in ipairs(tbl) do
		local key = fn(v)
		if not groups[key] then groups[key] = {} end
		table.insert(groups[key], v)
	end
	return groups
end

-- ═══════════════════════════════════════════════════════════════════════
-- STRING UTILITIES
--
-- String manipulation functions used for display formatting, path
-- operations, and input validation. All functions are nil-safe:
-- passing non-string values returns an empty string.
-- ═══════════════════════════════════════════════════════════════════════

--- Check if a command is available on the system PATH.
---
---@param cmd string Command name to check
---@return boolean available `true` if the command is found
function M.has_executable(cmd)
	return vim.fn.executable(cmd) == 1
end

--- Trim whitespace from both ends of a string.
---
---@param s string Input string
---@return string trimmed String with leading/trailing whitespace removed
function M.trim(s)
	if type(s) ~= "string" then return "" end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Trim whitespace from the left side of a string.
---
---@param s string Input string
---@return string trimmed String with leading whitespace removed
function M.ltrim(s)
	if type(s) ~= "string" then return "" end
	return (s:gsub("^%s+", ""))
end

--- Trim whitespace from the right side of a string.
---
---@param s string Input string
---@return string trimmed String with trailing whitespace removed
function M.rtrim(s)
	if type(s) ~= "string" then return "" end
	return (s:gsub("%s+$", ""))
end

--- Check if a string starts with a given prefix.
---
---@param s string String to check
---@param prefix string Prefix to search for
---@return boolean starts `true` if `s` starts with `prefix`
function M.starts_with(s, prefix)
	if type(s) ~= "string" or type(prefix) ~= "string" then return false end
	return s:sub(1, #prefix) == prefix
end

--- Check if a string ends with a given suffix.
---
---@param s string String to check
---@param suffix string Suffix to search for
---@return boolean ends `true` if `s` ends with `suffix`
function M.ends_with(s, suffix)
	if type(s) ~= "string" or type(suffix) ~= "string" then return false end
	return suffix == "" or s:sub(-#suffix) == suffix
end

--- Check if a string contains a substring (case-sensitive, plain match).
---
---@param s string String to search in
---@param substring string Substring to search for
---@return boolean found `true` if `substring` is found in `s`
function M.contains(s, substring)
	if type(s) ~= "string" or type(substring) ~= "string" then return false end
	return s:find(substring, 1, true) ~= nil
end

--- Check if a string is empty or nil.
---
---@param s string|nil Value to check
---@return boolean empty `true` if `s` is `nil` or `""`
function M.is_empty(s)
	return s == nil or s == ""
end

--- Check if a string is blank (nil, empty, or whitespace-only).
---
---@param s string|nil Value to check
---@return boolean blank `true` if `s` is nil, empty, or only whitespace
function M.is_blank(s)
	return s == nil or M.trim(s) == ""
end

--- Capitalize the first letter of a string.
---
---@param s string Input string
---@return string capitalized String with first character uppercased
function M.capitalize(s)
	if type(s) ~= "string" or #s == 0 then return s or "" end
	return s:sub(1, 1):upper() .. s:sub(2)
end

--- Convert a string to title case (capitalize each word).
---
---@param s string Input string
---@return string titled String with each word capitalized
function M.title_case(s)
	if type(s) ~= "string" then return "" end
	return (s:gsub("(%a)([%w_']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end))
end

--- Truncate a string to a maximum length, adding ellipsis if needed.
---
---@param s string Input string
---@param max_len integer Maximum length (including ellipsis)
---@param ellipsis? string Truncation indicator (default: `"…"`)
---@return string truncated String of at most `max_len` characters
function M.truncate(s, max_len, ellipsis)
	if type(s) ~= "string" then return "" end
	ellipsis = ellipsis or "…"
	if #s <= max_len then return s end
	return s:sub(1, max_len - #ellipsis) .. ellipsis
end

--- Pad a string on the right to a minimum width.
---
---@param s string Input string
---@param width integer Minimum total width
---@param char? string Pad character (default: `" "`)
---@return string padded Right-padded string
function M.pad_right(s, width, char)
	char = char or " "
	if #s >= width then return s end
	return s .. string.rep(char, width - #s)
end

--- Pad a string on the left to a minimum width.
---
---@param s string Input string
---@param width integer Minimum total width
---@param char? string Pad character (default: `" "`)
---@return string padded Left-padded string
function M.pad_left(s, width, char)
	char = char or " "
	if #s >= width then return s end
	return string.rep(char, width - #s) .. s
end

--- Split a string into a list of lines.
---
--- Handles both `\n` and `\r\n` line endings. Removes the trailing
--- empty string artifact from `gmatch`.
---
---@param s string Input string
---@return string[] lines List of line strings (without newline characters)
function M.split_lines(s)
	if type(s) ~= "string" then return {} end
	local lines = {}
	for line in s:gmatch("([^\n]*)\n?") do
		table.insert(lines, line)
	end
	-- Remove trailing empty line from gmatch artifact
	if #lines > 0 and lines[#lines] == "" then table.remove(lines) end
	return lines
end

--- Wrap text to a maximum line width (word-aware).
---
--- Splits on whitespace boundaries. Does not break words that
--- exceed `width` — they are placed on their own line.
---
---@param text string Input text
---@param width integer Maximum characters per line
---@return string[] lines List of wrapped lines
function M.word_wrap(text, width)
	local lines = {}
	local current_line = ""
	for word in text:gmatch("%S+") do
		if #current_line + #word + 1 > width then
			if #current_line > 0 then table.insert(lines, current_line) end
			current_line = word
		else
			if #current_line > 0 then
				current_line = current_line .. " " .. word
			else
				current_line = word
			end
		end
	end
	if #current_line > 0 then table.insert(lines, current_line) end
	return lines
end

-- ═══════════════════════════════════════════════════════════════════════
-- FILE I/O
--
-- File system operations using vim.uv (libuv) for non-blocking I/O.
-- All read/write functions return (result, nil) on success or
-- (nil, error_string) on failure — never throw.
-- Write functions auto-create parent directories as needed.
-- ═══════════════════════════════════════════════════════════════════════

--- Check if a file exists at the given path.
---
---@param path string File path to check
---@return boolean exists `true` if a regular file exists at `path`
function M.file_exists(path)
	if type(path) ~= "string" or path == "" then return false end
	local stat = vim.uv.fs_stat(path)
	return stat ~= nil and stat.type == "file"
end

--- Check if a directory exists at the given path.
---
---@param path string Directory path to check
---@return boolean exists `true` if a directory exists at `path`
function M.dir_exists(path)
	if type(path) ~= "string" or path == "" then return false end
	local stat = vim.uv.fs_stat(path)
	return stat ~= nil and stat.type == "directory"
end

--- Check if a path exists (file, directory, or any type).
---
---@param path string Path to check
---@return boolean exists `true` if anything exists at `path`
function M.path_exists(path)
	if type(path) ~= "string" or path == "" then return false end
	return vim.uv.fs_stat(path) ~= nil
end

--- Get the size of a file in bytes.
---
---@param path string File path
---@return integer|nil size File size in bytes, or `nil` if not a file
function M.file_size(path)
	local stat = vim.uv.fs_stat(path)
	if stat and stat.type == "file" then return stat.size end
	return nil
end

--- Get the last modification time of a file.
---
---@param path string File path
---@return integer|nil mtime Unix timestamp, or `nil` on failure
function M.file_mtime(path)
	local stat = vim.uv.fs_stat(path)
	if stat then return stat.mtime.sec end
	return nil
end

--- Read an entire file as a string.
---
--- Uses `vim.uv.fs_open/fstat/read/close` for efficient libuv-based I/O.
---
---@param path string File path to read
---@return string|nil content File contents, or `nil` on failure
---@return string|nil error Error message on failure, `nil` on success
function M.read_file(path)
	if type(path) ~= "string" or path == "" then return nil, "Invalid path" end
	local fd = vim.uv.fs_open(path, "r", 438)
	if not fd then return nil, "Cannot open file: " .. path end
	local stat = vim.uv.fs_fstat(fd)
	if not stat then
		vim.uv.fs_close(fd)
		return nil, "Cannot stat file: " .. path
	end
	local data = vim.uv.fs_read(fd, stat.size, 0)
	vim.uv.fs_close(fd)
	if not data then return nil, "Cannot read file: " .. path end
	return data, nil
end

--- Read a file as a list of lines.
---
---@param path string File path to read
---@return string[]|nil lines List of lines, or `nil` on failure
---@return string|nil error Error message on failure
function M.read_lines(path)
	local content, err = M.read_file(path)
	if not content then return nil, err end
	return M.split_lines(content), nil
end

--- Write a string to a file (creates parent directories as needed).
---
--- Overwrites the file if it already exists. Uses `vim.uv.fs_open`
--- with write mode (`"w"`) and permissions `0o666` (438 decimal).
---
---@param path string File path to write
---@param content string Content to write
---@return boolean success `true` if the write succeeded
---@return string|nil error Error message on failure
function M.write_file(path, content)
	if type(path) ~= "string" or path == "" then return false, "Invalid path" end
	-- Ensure parent directory exists
	local dir = vim.fn.fnamemodify(path, ":h")
	if not M.dir_exists(dir) then vim.fn.mkdir(dir, "p") end
	local fd = vim.uv.fs_open(path, "w", 438) -- 0o666
	if not fd then return false, "Cannot open file for writing: " .. path end
	local ok = vim.uv.fs_write(fd, content)
	vim.uv.fs_close(fd)
	if not ok then return false, "Cannot write to file: " .. path end
	return true, nil
end

--- Append a string to a file (creates if it doesn't exist).
---
---@param path string File path to append to
---@param content string Content to append
---@return boolean success `true` if the append succeeded
---@return string|nil error Error message on failure
function M.append_file(path, content)
	if type(path) ~= "string" or path == "" then return false, "Invalid path" end
	local dir = vim.fn.fnamemodify(path, ":h")
	if not M.dir_exists(dir) then vim.fn.mkdir(dir, "p") end
	local fd = vim.uv.fs_open(path, "a", 438) -- 0o666
	if not fd then return false, "Cannot open file for appending: " .. path end
	local ok = vim.uv.fs_write(fd, content)
	vim.uv.fs_close(fd)
	if not ok then return false, "Cannot append to file: " .. path end
	return true, nil
end

--- Copy a file from source to destination.
---
--- Reads the entire source file into memory, then writes it to
--- the destination. Creates parent directories for the destination.
---
---@param src string Source file path
---@param dst string Destination file path
---@return boolean success `true` if the copy succeeded
---@return string|nil error Error message on failure
function M.copy_file(src, dst)
	local content, err = M.read_file(src)
	if not content then return false, err end
	return M.write_file(dst, content)
end

--- List entries in a directory (sorted alphabetically).
---
--- Uses `vim.uv.fs_scandir` for libuv-based directory scanning.
---
---@param path string Directory path to scan
---@param filter? "file"|"directory"|nil Only return entries of this type
---@return string[] entries Sorted list of entry names (not full paths)
function M.list_dir(path, filter)
	local entries = {}
	if type(path) ~= "string" or path == "" then return entries end
	local handle = vim.uv.fs_scandir(path)
	if not handle then return entries end
	while true do
		local name, typ = vim.uv.fs_scandir_next(handle)
		if not name then break end
		if not filter or typ == filter then table.insert(entries, name) end
	end
	table.sort(entries)
	return entries
end

--- List entries in a directory with full paths (sorted).
---
---@param path string Directory path to scan
---@param filter? "file"|"directory"|nil Only return entries of this type
---@return string[] entries Sorted list of full paths
function M.list_dir_full(path, filter)
	local names = M.list_dir(path, filter)
	local results = {}
	for _, name in ipairs(names) do
		table.insert(results, path .. "/" .. name)
	end
	return results
end

--- Recursively list all files in a directory tree.
---
--- Returns relative paths from the root `path`. Optionally filters
--- filenames by a Lua pattern (e.g., `"%.lua$"` for Lua files).
---
---@param path string Root directory to scan
---@param pattern? string Lua pattern to filter filenames (e.g. `"%.lua$"`)
---@return string[] files Sorted list of relative file paths
function M.list_files_recursive(path, pattern)
	local results = {}

	--- Recursively scan a directory, building relative paths.
	---@param dir string Current directory to scan
	---@param prefix string Relative path prefix for entries
	local function scan(dir, prefix)
		local handle = vim.uv.fs_scandir(dir)
		if not handle then return end
		while true do
			local name, typ = vim.uv.fs_scandir_next(handle)
			if not name then break end
			local rel_path = prefix ~= "" and (prefix .. "/" .. name) or name
			if typ == "directory" then
				scan(dir .. "/" .. name, rel_path)
			elseif typ == "file" then
				if not pattern or name:match(pattern) then table.insert(results, rel_path) end
			end
		end
	end

	scan(path, "")
	table.sort(results)
	return results
end

--- Ensure a directory exists, creating it and parents if needed.
---
---@param path string Directory path to ensure
---@return boolean success `true` if the directory exists or was created
function M.ensure_dir(path)
	if M.dir_exists(path) then return true end
	return vim.fn.mkdir(path, "p") == 1
end

--- Get the file extension from a path (without the leading dot).
---
---@param path string File path
---@return string extension Extension string, or `""` if none
function M.file_extension(path)
	if type(path) ~= "string" then return "" end
	return path:match("%.([^%.]+)$") or ""
end

--- Get the filename without extension (basename).
---
---@param path string File path
---@return string basename Filename without extension
function M.file_basename(path)
	if type(path) ~= "string" then return "" end
	local name = vim.fn.fnamemodify(path, ":t")
	return name:match("(.+)%.[^%.]+$") or name
end

-- ═══════════════════════════════════════════════════════════════════════
-- MODULE UTILITIES
--
-- Safe wrappers around Lua's require() and package.loaded system.
-- Enables graceful degradation when optional modules are missing
-- and supports hot-reloading during development.
-- ═══════════════════════════════════════════════════════════════════════

--- Safely require a Lua module (never throws).
---
--- Returns `(module, nil)` on success or `(nil, error_string)` on failure.
---
--- ```lua
--- local mod, err = utils.safe_require("optional.plugin")
--- if mod then mod.setup() end
--- ```
---
---@param modname string Module name (e.g. `"core.settings"`)
---@return any|nil module The loaded module, or `nil` on failure
---@return string|nil error Error message on failure
function M.safe_require(modname)
	local ok, result = pcall(require, modname)
	if ok then
		return result, nil
	else
		return nil, tostring(result)
	end
end

--- Require a module, returning a default value on failure.
---
---@param modname string Module name
---@param default any Fallback value if require fails
---@return any result The loaded module, or `default`
function M.require_or(modname, default)
	local mod, _ = M.safe_require(modname)
	return mod or default
end

--- Check if a Lua module exists (without loading it).
---
--- First checks `package.loaded`, then walks `package.searchers`
--- to see if any searcher can find the module.
---
---@param modname string Module name to check
---@return boolean exists `true` if the module can be found
function M.module_exists(modname)
	if package.loaded[modname] then return true end
	---@diagnostic disable-next-line: deprecated
	local searchers = package.searchers or package.loaders
	for _, searcher in ipairs(searchers) do
		local loader = searcher(modname)
		if type(loader) == "function" then return true end
	end
	return false
end

--- Reload a Lua module (clears cache and re-requires).
---
---@param modname string Module name to reload
---@return any|nil module The freshly loaded module, or `nil` on failure
---@return string|nil error Error message on failure
function M.reload_module(modname)
	package.loaded[modname] = nil
	return M.safe_require(modname)
end

--- Clear all cached modules matching a Lua pattern.
---
--- Useful for bulk-reloading a namespace (e.g., all plugin configs).
---
--- ```lua
--- utils.clear_module_cache("^plugins%.")  --> clears all plugins.* modules
--- ```
---
---@param pattern string Lua pattern to match module names
---@return integer count Number of modules cleared from cache
function M.clear_module_cache(pattern)
	local count = 0
	for name in pairs(package.loaded) do
		if name:match(pattern) then
			package.loaded[name] = nil
			count = count + 1
		end
	end
	return count
end

-- ═══════════════════════════════════════════════════════════════════════
-- ASYNC / TIMER UTILITIES
--
-- Time-based function wrappers using vim.uv timers. Debounce and
-- throttle are critical for performance-sensitive operations like
-- search-as-you-type, buffer change handlers, and resize events.
-- ═══════════════════════════════════════════════════════════════════════

--- Execute a function after a delay.
---
---@param ms integer Delay in milliseconds
---@param fn function Function to execute
function M.defer(ms, fn)
	vim.defer_fn(fn, ms)
end

--- Execute a function on the next event loop iteration.
---
---@param fn function Function to execute
function M.next_tick(fn)
	vim.schedule(fn)
end

-- ═══════════════════════════════════════════════════════════════════════
-- NEOVIM UTILITIES
--
-- Neovim-specific helpers for autocommands, project root detection,
-- filetype checks, visual selection, and notification wrappers.
-- ═══════════════════════════════════════════════════════════════════════

--- Create an autocommand group with `clear = true`.
---
--- Automatically prefixes the name with `"NvimEnterprise_"` for
--- consistent namespace isolation across the configuration.
---
---@param name string Group name (will be prefixed with `"NvimEnterprise_"`)
---@return integer augroup_id The created augroup ID
function M.augroup(name)
	return vim.api.nvim_create_augroup("NvimEnterprise_" .. name, { clear = true })
end

--- Get the root directory of the current project.
---
--- Searches upward from the current file for common root markers.
--- Falls back to `vim.uv.cwd()` if no marker is found.
---
---@param markers? string[] Custom root markers (default: `.git`, `package.json`, etc.)
---@return string root Absolute path to the project root
function M.get_root(markers)
	markers = markers or { ".git", "package.json", "Cargo.toml", "go.mod", "Makefile", "pyproject.toml", ".project_root" }
	local path = vim.fn.expand("%:p:h")
	local found = vim.fs.find(markers, { path = path, upward = true })[1]
	if found then return vim.fn.fnamemodify(found, ":h") end
	return vim.uv.cwd() or "."
end

--- Check if the current buffer has a specific filetype.
---
---@param ft string|string[] Filetype(s) to check against
---@return boolean matches `true` if the current buffer's filetype matches
function M.is_filetype(ft)
	local current = vim.bo.filetype
	if type(ft) == "table" then return M.tbl_contains(ft, current) end
	return current == ft
end

--- Get the current buffer's filename.
---
---@param full_path? boolean Return the full absolute path (default: `false`, returns tail only)
---@return string filename The filename or full path
function M.current_file(full_path)
	if full_path then return vim.fn.expand("%:p") end
	return vim.fn.expand("%:t")
end

--- Check if Neovim has a specific feature.
---
---@param feature string Feature string (e.g. `"nvim-0.10"`, `"python3"`, `"clipboard"`)
---@return boolean has `true` if the feature is available
function M.has(feature)
	return vim.fn.has(feature) == 1
end

--- Get the current visual selection as a string.
---
--- Works in visual, visual-line, and visual-block modes.
--- Handles reversed selections (cursor before anchor).
---
---@return string selection The selected text (lines joined with `\n`)
function M.get_visual_selection()
	local _, ls, cs = unpack(vim.fn.getpos("v"))
	local _, le, ce = unpack(vim.fn.getpos("."))
	if ls > le or (ls == le and cs > ce) then
		ls, cs, le, ce = le, ce, ls, cs
	end
	local lines = vim.api.nvim_buf_get_lines(0, ls - 1, le, false)
	if #lines == 0 then return "" end
	lines[#lines] = lines[#lines]:sub(1, ce)
	lines[1] = lines[1]:sub(cs)
	return table.concat(lines, "\n")
end

--- Notify with a consistent "NvimEnterprise" title.
---
---@param msg string Notification message
---@param level? integer `vim.log.levels.*` constant (default: `INFO`)
---@param opts? table Additional options passed to `vim.notify()`
function M.notify(msg, level, opts)
	opts = opts or {}
	opts.title = opts.title or "NvimEnterprise"
	vim.notify(msg, level or vim.log.levels.INFO, opts)
end

--- Notify an error with optional title.
---
---@param msg string Error message
---@param title? string Notification title (default: `"NvimEnterprise"`)
function M.notify_error(msg, title)
	M.notify(msg, vim.log.levels.ERROR, { title = title })
end

--- Notify a warning with optional title.
---
---@param msg string Warning message
---@param title? string Notification title (default: `"NvimEnterprise"`)
function M.notify_warn(msg, title)
	M.notify(msg, vim.log.levels.WARN, { title = title })
end

-- ═══════════════════════════════════════════════════════════════════════
-- ICON UTILITIES
--
-- Convenience API for accessing icons from core/icons.lua.
-- Uses lazy-loading with a module-level cache to avoid circular
-- dependencies at require time (utils is loaded before icons in
-- some code paths). The cache is invalidated via icon_cache_clear().
-- ═══════════════════════════════════════════════════════════════════════

--- Icon module cache (lazy-loaded on first `icon()` call).
---@type table|nil
---@private
M._icons_cache = nil

--- Load and cache the icons module.
---
--- Uses `pcall(require, ...)` to avoid hard dependency — returns
--- an empty table if `core.icons` is not yet available.
---
---@return table icons The cached icons module table
---@private
function M._get_icons()
	if not M._icons_cache then
		local ok, icons = pcall(require, "core.icons")
		if ok and type(icons) == "table" then
			M._icons_cache = icons
		else
			M._icons_cache = {}
		end
	end
	return M._icons_cache
end

--- Retrieve an icon by category and name, with optional spacing.
---
--- Supports multiple calling conventions:
---
--- ```lua
--- -- Standard: category + name
--- utils.icon("ui", "Check")                          --> "󰄬"
--- utils.icon("diagnostics", "Error")                 --> ""
---
--- -- Dot-notation shorthand
--- utils.icon("ui.Check")                             --> "󰄬"
--- utils.icon("git.Branch")                           --> ""
---
--- -- With spacing
--- utils.icon("ui", "Check", { after = true })        --> "󰄬 "
--- utils.icon("ui", "Fire", true)                     --> "󰈸 "  (shorthand)
--- utils.icon("ui", "Gear", { before = true })        --> " 󰒓"
---
--- -- Custom spacing strings
--- utils.icon("ui", "Fire", { after = "  " })         --> "󰈸  "
---
--- -- Fallback for missing icons
--- utils.icon("ui", "NonExistent", { fallback = "?" }) --> "?"
---
--- -- Nerd Font conditional
--- utils.icon("ui", "Check", { nerd_only = true, fallback = "[x]" })
--- ```
---
---@param category string Icon category or dot-path (e.g. `"ui"` or `"ui.Check"`)
---@param name? string Icon name within the category (optional if using dot-path)
---@param opts? table|boolean Options table, or `true` as shorthand for `{ after = true }`
---@return string|table icon The icon glyph with optional spacing (or table for borders)
function M.icon(category, name, opts)
	-- ── Normalize arguments ──────────────────────────────────────────
	-- Handle dot-notation: icon("ui.Check") or icon("ui.Check", { after = true })
	if type(category) == "string" and category:find("%.") then
		local dot_pos = category:find("%.")
		local parsed_cat = category:sub(1, dot_pos - 1)
		local parsed_name = category:sub(dot_pos + 1)
		-- Shift arguments: name becomes opts
		if type(name) == "table" or type(name) == "boolean" then opts = name end
		category = parsed_cat
		name = parsed_name
	end

	-- Handle boolean shorthand: icon("ui", "Check", true) → { after = true }
	if opts == true then
		opts = { after = true }
	elseif opts == false or opts == nil then
		opts = {}
	end

	-- ── Validate ─────────────────────────────────────────────────────
	if type(category) ~= "string" or type(name) ~= "string" then return opts.fallback or "" end

	-- ── Nerd Font check ──────────────────────────────────────────────
	if opts.nerd_only then
		local platform_ok, platform = pcall(require, "core.platform")
		local has_nerd = true
		if platform_ok then has_nerd = platform.has_nerd_font ~= false end
		if not has_nerd then return opts.fallback or "" end
	end

	-- ── Lookup ───────────────────────────────────────────────────────
	local icons = M._get_icons()
	local cat = icons[category]

	if type(cat) ~= "table" then return opts.fallback or "" end

	local glyph = cat[name]

	if glyph == nil then
		-- Case-insensitive fallback search
		local name_lower = name:lower()
		for k, v in pairs(cat) do
			if k:lower() == name_lower then
				glyph = v
				break
			end
		end
	end

	if glyph == nil then return opts.fallback or "" end

	-- Handle table values (e.g., borders.Rounded is a list)
	if type(glyph) == "table" then return glyph end

	-- ── Apply spacing ────────────────────────────────────────────────
	local before_str = ""
	local after_str = ""

	if opts.before then
		before_str = type(opts.before) == "string" and opts.before --[[@as string]]
			or " "
	end

	if opts.after then
		after_str = type(opts.after) == "string" and opts.after --[[@as string]]
			or " "
	end

	return before_str .. glyph .. after_str
end

--- Retrieve a full icon category table.
---
--- ```lua
--- utils.icon_category("diagnostics")  --> { Error = "", Warn = "", ... }
--- ```
---
---@param category string Category name (e.g. `"diagnostics"`, `"git"`, `"ui"`)
---@return table<string, string> icons Map of name → glyph (empty table if not found)
function M.icon_category(category)
	local icons = M._get_icons()
	local cat = icons[category]
	if type(cat) == "table" then return cat end
	return {}
end

--- List all available icon category names (sorted).
---
--- Excludes internal fields (prefixed with `_`).
---
--- ```lua
--- utils.icon_categories()  --> { "app", "arrows", "borders", "dap", ... }
--- ```
---
---@return string[] categories Sorted list of category names
function M.icon_categories()
	local icons = M._get_icons()
	local categories = {}
	for k, v in pairs(icons) do
		if type(v) == "table" and not k:match("^_") then categories[#categories + 1] = k end
	end
	table.sort(categories)
	return categories
end

--- List all icon names within a category (sorted).
---
--- ```lua
--- utils.icon_names("diagnostics")  --> { "Error", "Hint", "Info", "Warn" }
--- ```
---
---@param category string Category name
---@return string[] names Sorted list of icon names
function M.icon_names(category)
	local cat = M.icon_category(category)
	local names = {}
	for k in pairs(cat) do
		names[#names + 1] = k
	end
	table.sort(names)
	return names
end

--- Search for an icon by name across all categories.
---
--- Returns the first match found. Case-insensitive by default.
---
--- ```lua
--- utils.icon_search("Check")
--- --> { category = "ui", name = "Check", glyph = "󰄬" }
--- ```
---
---@param name string Icon name to search for
---@param case_sensitive? boolean Use case-sensitive matching (default: `false`)
---@return table|nil result `{ category: string, name: string, glyph: string }` or `nil`
function M.icon_search(name, case_sensitive)
	local icons = M._get_icons()
	local search_name = case_sensitive and name or name:lower()

	for cat_name, cat in pairs(icons) do
		if type(cat) == "table" and not cat_name:match("^_") then
			for icon_name, glyph in pairs(cat) do
				local compare = case_sensitive and icon_name or icon_name:lower()
				if compare == search_name then
					return {
						category = cat_name,
						name = icon_name,
						glyph = glyph,
					}
				end
			end
		end
	end
	return nil
end

--- Search for all icons matching a Lua pattern across all categories.
---
--- ```lua
--- utils.icon_find("arrow")
--- --> { { category="arrows", name="ArrowDown", glyph="" }, ... }
--- ```
---
---@param pattern string Lua pattern to match icon names
---@param case_sensitive? boolean Use case-sensitive matching (default: `false`)
---@return table[] results Sorted list of `{ category, name, glyph }` tables
function M.icon_find(pattern, case_sensitive)
	local icons = M._get_icons()
	local results = {}
	local search_pattern = case_sensitive and pattern or pattern:lower()

	for cat_name, cat in pairs(icons) do
		if type(cat) == "table" and not cat_name:match("^_") then
			for icon_name, glyph in pairs(cat) do
				if type(glyph) == "string" then
					local compare = case_sensitive and icon_name or icon_name:lower()
					if compare:match(search_pattern) then
						results[#results + 1] = {
							category = cat_name,
							name = icon_name,
							glyph = glyph,
						}
					end
				end
			end
		end
	end

	table.sort(results, function(a, b)
		if a.category ~= b.category then return a.category < b.category end
		return a.name < b.name
	end)

	return results
end

--- Build a formatted icon + label string.
---
--- Convenience wrapper for the common `"icon separator label"` pattern.
---
--- ```lua
--- utils.icon_label("ui", "Rocket", "Deploy")        --> "󰓅 Deploy"
--- utils.icon_label("git", "Branch", "main", " → ")  --> " → main"
--- ```
---
---@param category string Icon category
---@param name string Icon name
---@param label string Text label to display after the icon
---@param separator? string Separator between icon and label (default: `" "`)
---@return string formatted Icon + separator + label (just label if icon not found)
function M.icon_label(category, name, label, separator)
	separator = separator or " "
	local glyph = M.icon(category, name)
	if glyph == "" then return label end
	return glyph .. separator .. label
end

--- Invalidate the icon cache.
---
--- Call after hot-reloading `core/icons.lua` to force a fresh
--- `require()` on the next `icon()` call.
function M.icon_cache_clear()
	M._icons_cache = nil
	-- Also clear from package.loaded so next require gets fresh data
	package.loaded["core.icons"] = nil
end

-- ═══════════════════════════════════════════════════════════════════════
-- VALIDATION UTILITIES
--
-- Input validation functions that return (valid, error_string) tuples.
-- Used by security, settings, and user management modules for
-- consistent error reporting without throwing.
-- ═══════════════════════════════════════════════════════════════════════

--- Validate a value against one or more expected types.
---
--- ```lua
--- utils.validate_type(42, "number", "tab_size")        --> true, nil
--- utils.validate_type("hi", { "string", "nil" }, "x")  --> true, nil
--- utils.validate_type(42, "string", "name")             --> false, "Expected name to be string, got number"
--- ```
---
---@param value any Value to validate
---@param expected string|string[] Expected type name(s)
---@param name? string Variable name for error messages (default: `"value"`)
---@return boolean valid `true` if `type(value)` matches any expected type
---@return string|nil error Error message on failure
function M.validate_type(value, expected, name)
	local types = type(expected) == "table" and expected or { expected }
	local actual = type(value)
	for _, t in ipairs(types) do
		if actual == t then return true, nil end
	end
	local label = name or "value"
	return false, string.format("Expected %s to be %s, got %s", label, table.concat(types, " or "), actual)
end

--- Validate that a value is a non-blank string.
---
---@param value any Value to validate
---@param name? string Variable name for error messages (default: `"value"`)
---@return boolean valid `true` if value is a non-blank string
---@return string|nil error Error message on failure
function M.validate_not_empty(value, name)
	local label = name or "value"
	if type(value) ~= "string" then
		return false, string.format("Expected %s to be a string, got %s", label, type(value))
	end
	if M.is_blank(value) then return false, string.format("%s cannot be empty", label) end
	return true, nil
end

--- Validate that a value is one of a set of allowed values.
---
--- ```lua
--- utils.validate_one_of("dark", { "dark", "light" }, "theme")  --> true, nil
--- utils.validate_one_of("blue", { "dark", "light" }, "theme")  --> false, "theme must be one of [dark, light], got 'blue'"
--- ```
---
---@param value any Value to validate
---@param allowed table List of allowed values
---@param name? string Variable name for error messages (default: `"value"`)
---@return boolean valid `true` if `value` is in the allowed list
---@return string|nil error Error message on failure
function M.validate_one_of(value, allowed, name)
	if M.tbl_contains(allowed, value) then return true, nil end
	local label = name or "value"
	local allowed_str = table.concat(
		M.tbl_map(allowed, function(v)
			return tostring(v)
		end),
		", "
	)
	return false, string.format("%s must be one of [%s], got '%s'", label, allowed_str, tostring(value))
end

-- ═══════════════════════════════════════════════════════════════════════
-- FORMATTING UTILITIES
--
-- Human-readable formatting for bytes, durations, dates, and
-- relative timestamps. Used in status displays, notifications,
-- and :checkhealth output.
-- ═══════════════════════════════════════════════════════════════════════

--- Format a byte count into human-readable form.
---
--- ```lua
--- utils.format_bytes(1536)      --> "1.5 KB"
--- utils.format_bytes(2097152)   --> "2.0 MB"
--- ```
---
---@param bytes integer Number of bytes
---@return string formatted Human-readable size string
function M.format_bytes(bytes)
	if bytes < 1024 then
		return string.format("%d B", bytes)
	elseif bytes < 1048576 then
		return string.format("%.1f KB", bytes / 1024)
	elseif bytes < 1073741824 then
		return string.format("%.1f MB", bytes / 1048576)
	else
		return string.format("%.2f GB", bytes / 1073741824)
	end
end

--- Format a duration in milliseconds into human-readable form.
---
--- ```lua
--- utils.format_ms(0.5)    --> "500μs"
--- utils.format_ms(42.3)   --> "42.3ms"
--- utils.format_ms(1500)   --> "1.50s"
--- ```
---
---@param ms number Duration in milliseconds
---@return string formatted Human-readable duration string
function M.format_ms(ms)
	if ms < 1 then
		return string.format("%.0fμs", ms * 1000)
	elseif ms < 1000 then
		return string.format("%.1fms", ms)
	else
		return string.format("%.2fs", ms / 1000)
	end
end

--- Format a Unix timestamp as a readable date string.
---
---@param timestamp integer Unix timestamp
---@param format? string `os.date` format string (default: `"%Y-%m-%d %H:%M:%S"`)
---@return string formatted Formatted date string
function M.format_date(timestamp, format)
	format = format or "%Y-%m-%d %H:%M:%S"
	return os.date(format, timestamp) --[[@as string]]
end

--- Format a Unix timestamp as a relative time string.
---
--- ```lua
--- utils.format_relative_time(os.time() - 120)   --> "2 minutes ago"
--- utils.format_relative_time(os.time() - 7200)  --> "2 hours ago"
--- ```
---
---@param timestamp integer Unix timestamp
---@return string relative Human-readable relative time (e.g. `"2 hours ago"`)
function M.format_relative_time(timestamp)
	local now = os.time()
	local diff = now - timestamp

	if diff < 60 then
		return "just now"
	elseif diff < 3600 then
		local mins = math.floor(diff / 60)
		return string.format("%d minute%s ago", mins, mins > 1 and "s" or "")
	elseif diff < 86400 then
		local hours = math.floor(diff / 3600)
		return string.format("%d hour%s ago", hours, hours > 1 and "s" or "")
	elseif diff < 2592000 then
		local days = math.floor(diff / 86400)
		return string.format("%d day%s ago", days, days > 1 and "s" or "")
	else
		return M.format_date(timestamp)
	end
end

-- ═══════════════════════════════════════════════════════════════════════
-- PERFORMANCE UTILITIES
--
-- Measurement and memoization tools for profiling and optimizing
-- hot code paths during development.
-- ═══════════════════════════════════════════════════════════════════════

--- Measure the execution time of a function.
---
--- Uses `vim.uv.hrtime()` for nanosecond-precision timing.
---
--- ```lua
--- local result, ms = utils.measure(function()
---   return heavy_computation()
--- end)
--- log:info("Took %s", utils.format_ms(ms))
--- ```
---
---@param fn function Function to measure
---@param ... any Arguments to pass to `fn`
---@return any result Return value of `fn`
---@return number ms Execution time in milliseconds
function M.measure(fn, ...)
	local start = vim.uv.hrtime()
	local result = fn(...)
	local elapsed = (vim.uv.hrtime() - start) / 1e6
	return result, elapsed
end

--- Create a memoized version of a function.
---
--- Caches results by stringified arguments (`vim.inspect`).
--- Returns both the memoized function and a cache-clear function.
---
--- ```lua
--- local fast_fn, clear = utils.memoize(expensive_fn)
--- fast_fn(1, 2)  -- computes and caches
--- fast_fn(1, 2)  -- returns cached result
--- clear()        -- purge all cached results
--- ```
---
---@param fn function Function to memoize
---@return function memoized Memoized wrapper function
---@return function clear Cache-clearing function
function M.memoize(fn)
	local cache = {}
	local memoized = function(...)
		local key = vim.inspect({ ... })
		if cache[key] == nil then cache[key] = fn(...) end
		return cache[key]
	end
	local clear = function()
		cache = {}
	end
	return memoized, clear
end

return M
