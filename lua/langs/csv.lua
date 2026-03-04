---@file lua/langs/csv.lua
---@description CSV / TSV / PSV — Tabular data viewing, alignment, sorting, conversion
---@module "langs.csv"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings              Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps               Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons                 Icon provider (`lang.csv`, `file.Csv`, `ui`, `diagnostics`)
---@see core.mini-align-registry   Alignment preset registration for CSV columns
---@see langs.json                 JSON support (conversion target from CSV)
---@see langs.markdown             Markdown support (table conversion target)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/csv.lua — CSV / TSV / PSV file support                            ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("csv") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Data file module (not a programming language):                  │    ║
--- ║  │  ├─ No LSP server (structural data, not code)                    │    ║
--- ║  │  ├─ No formatter (alignment is handled manually)                 │    ║
--- ║  │  ├─ No linter (no syntax rules beyond RFC 4180)                  │    ║
--- ║  │  └─ No DAP (not executable code)                                 │    ║
--- ║  │                                                                  │    ║
--- ║  │  Detection layers:                                               │    ║
--- ║  │  ├─ Filetype    .csv .tsv .psv → csv                             │    ║
--- ║  │  └─ Delimiter   auto-detected from first line:                   │    ║
--- ║  │     tab > semicolon > pipe > comma (by frequency)                │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded on ft = "csv"):                          │    ║
--- ║  │  ├─ Plugin      rainbow_csv (syntax highlighting + RBQL)         │    ║
--- ║  │  └─ Treesitter  csv parser                                       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (buffer-local, <leader>l group, 14 bindings):           │    ║
--- ║  │  ├─ ALIGN       a  Align columns          A  Unalign             │    ║
--- ║  │  ├─ SORT        s  Sort by column          r  Reverse sort       │    ║
--- ║  │  ├─ QUERY       q  RBQL query (rainbow_csv)                      │    ║
--- ║  │  │              f  Filter rows by pattern                        │    ║
--- ║  │  ├─ CONVERT     t  To markdown table       j  To JSON            │    ║
--- ║  │  ├─ COLUMN      c  Column info + stats     d  Set delimiter      │    ║
--- ║  │  │              H  Toggle header highlight  n  Column count      │    ║
--- ║  │  ├─ STATS       i  File stats                                    │    ║
--- ║  │  └─ DOCS        h  CSV reference (RFC 4180)                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Delimiter auto-detection algorithm:                             │    ║
--- ║  │  ├─ Parse first line of file                                     │    ║
--- ║  │  ├─ Count occurrences of: TAB, comma, semicolon, pipe            │    ║
--- ║  │  ├─ Highest count wins (stable: TAB > ; > | > , on ties)         │    ║
--- ║  │  └─ Default: comma (if no delimiters found)                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  CSV line parser (RFC 4180 compliant):                           │    ║
--- ║  │  ├─ Handles quoted fields ("hello, world")                       │    ║
--- ║  │  ├─ Handles escaped quotes ("say ""hello""")                     │    ║
--- ║  │  └─ Handles empty fields                                         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Column statistics (computed on <leader>lc):                     │    ║
--- ║  │  ├─ Row count, non-empty count                                   │    ║
--- ║  │  ├─ Numeric detection and count                                  │    ║
--- ║  │  └─ Sum and average (for numeric columns)                        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Conversion outputs:                                             │    ║
--- ║  │  ├─ Markdown table → vsplit scratch buffer (filetype: markdown)  │    ║
--- ║  │  └─ JSON array     → vsplit scratch buffer (filetype: json)      │    ║
--- ║  │     ├─ Numbers preserved as JSON numbers                         │    ║
--- ║  │     ├─ Booleans preserved as JSON booleans                       │    ║
--- ║  │     └─ Strings properly JSON-encoded                             │    ║
--- ║  │                                                                  │    ║
--- ║  │  Mini.align integration:                                         │    ║
--- ║  │  ├─ Preset: csv_columns (align on ',')                           │    ║
--- ║  │  └─ <leader>aL  Align CSV columns                                │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (set on FileType csv):                                   ║
--- ║  • wrap=false                  (horizontal scrolling for wide data)      ║
--- ║  • relativenumber=false        (absolute line numbers for row reference) ║
--- ║  • cursorline=true             (highlight current row for readability)   ║
--- ║  • sidescroll=5, sidescrolloff=10 (smooth horizontal scrolling)          ║
--- ║  • expandtab=false             (preserve TAB delimiters in TSV files)    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if CSV support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("csv") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string CSV Nerd Font icon (trailing whitespace stripped)
local csv_icon = icons.lang.csv:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group as " CSV" in which-key for csv buffers.
-- All lang_map() calls below bind into this group.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("csv", "CSV", csv_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — DELIMITER DETECTION & CSV PARSING
--
-- CSV files use different delimiters depending on locale and tool:
-- ├─ Comma (,)     — RFC 4180 standard, most common internationally
-- ├─ Tab (\t)      — TSV files, common in bioinformatics and spreadsheets
-- ├─ Semicolon (;) — common in European locales (where , is decimal sep)
-- └─ Pipe (|)      — PSV files, common in legacy systems and databases
--
-- The detect function counts delimiter occurrences in the first line
-- and returns the most frequent one. On ties, the priority order is:
-- TAB > semicolon > pipe > comma.
-- ═══════════════════════════════════════════════════════════════════════════

--- Auto-detect the delimiter from the first line of the buffer.
---
--- Counts occurrences of four candidate delimiters (tab, comma,
--- semicolon, pipe) and returns the one with the highest frequency.
--- Falls back to comma if no delimiters are found (single-column data).
---
--- ```lua
--- local delim = detect_delimiter()
--- -- Returns "\t" for TSV, "," for CSV, ";" for European CSV, "|" for PSV
--- ```
---
---@return string delimiter Single-character delimiter string
---@private
local function detect_delimiter()
	local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""

	---@type integer
	local tab_count = select(2, first_line:gsub("\t", ""))
	---@type integer
	local comma_count = select(2, first_line:gsub(",", ""))
	---@type integer
	local semi_count = select(2, first_line:gsub(";", ""))
	---@type integer
	local pipe_count = select(2, first_line:gsub("|", ""))

	local max = math.max(tab_count, comma_count, semi_count, pipe_count)
	if max == 0 then return "," end
	-- Priority order on ties: TAB > semicolon > pipe > comma
	if max == tab_count then return "\t" end
	if max == semi_count then return ";" end
	if max == pipe_count then return "|" end
	return ","
end

--- Split a CSV line into fields, respecting RFC 4180 quoting rules.
---
--- Handles:
--- - Quoted fields containing the delimiter: `"hello, world"`
--- - Escaped quotes (doubled): `"say ""hello"""`  → `say "hello"`
--- - Empty fields: `a,,c` → `{"a", "", "c"}`
--- - Mixed quoted and unquoted fields
---
--- Does NOT handle:
--- - Multi-line quoted fields (each line is parsed independently)
--- - BOM characters (should be stripped before parsing)
---
--- ```lua
--- local fields = split_csv_line('name,"age, years",city', ",")
--- -- Returns: {"name", "age, years", "city"}
--- ```
---
---@param line string Raw CSV line to parse
---@param delim string Single-character delimiter
---@return string[] fields List of field values (quotes stripped)
---@private
local function split_csv_line(line, delim)
	---@type string[]
	local fields = {}
	---@type string
	local field = ""
	---@type boolean
	local in_quote = false
	---@type integer
	local i = 1

	while i <= #line do
		local c = line:sub(i, i)
		if c == '"' then
			if in_quote and line:sub(i + 1, i + 1) == '"' then
				-- Escaped quote: "" → "
				field = field .. '"'
				i = i + 1
			else
				in_quote = not in_quote
			end
		elseif c == delim and not in_quote then
			fields[#fields + 1] = field
			field = ""
		else
			field = field .. c
		end
		i = i + 1
	end
	fields[#fields + 1] = field
	return fields
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — ALIGN / UNALIGN
--
-- Column alignment pads each field to the maximum width in its column,
-- making tabular data visually inspectable without a spreadsheet.
-- Unalign strips the padding to restore minimal file size.
-- ═══════════════════════════════════════════════════════════════════════════

--- Align all columns to fixed width for visual inspection.
---
--- Algorithm:
--- 1. Parse all rows using the auto-detected delimiter
--- 2. Compute the maximum display width for each column
---    (using `vim.fn.strdisplaywidth` for Unicode correctness)
--- 3. Pad each field with trailing spaces to the column max width
--- 4. Rejoin fields with `delimiter + space` for readability
--- 5. Replace all buffer lines in-place
keys.lang_map("csv", "n", "<leader>la", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local delim = detect_delimiter()

	-- ── Parse all rows and compute column widths ──────────────────────
	---@type string[][]
	local rows = {}
	---@type table<integer, integer>
	local max_widths = {}
	for _, line in ipairs(lines) do
		local fields = split_csv_line(line, delim)
		rows[#rows + 1] = fields
		for c, f in ipairs(fields) do
			max_widths[c] = math.max(max_widths[c] or 0, vim.fn.strdisplaywidth(f))
		end
	end

	-- ── Rebuild lines with padding ────────────────────────────────────
	---@type string[]
	local aligned = {}
	for _, fields in ipairs(rows) do
		---@type string[]
		local parts = {}
		for c, f in ipairs(fields) do
			local pad = (max_widths[c] or 0) - vim.fn.strdisplaywidth(f)
			parts[#parts + 1] = f .. string.rep(" ", pad)
		end
		aligned[#aligned + 1] = table.concat(parts, delim .. " ")
	end

	vim.api.nvim_buf_set_lines(0, 0, -1, false, aligned)
	vim.notify("Columns aligned", vim.log.levels.INFO, { title = "CSV" })
end, { desc = csv_icon .. " Align columns" })

--- Remove alignment padding (strip trailing whitespace from fields).
---
--- Trims leading and trailing whitespace from each field, then
--- rejoins with the bare delimiter (no space). Restores the file
--- to its minimal size for storage or processing.
keys.lang_map("csv", "n", "<leader>lA", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local delim = detect_delimiter()

	---@type string[]
	local trimmed = {}
	for _, line in ipairs(lines) do
		local fields = split_csv_line(line, delim)
		for i, f in ipairs(fields) do
			fields[i] = f:match("^%s*(.-)%s*$")
		end
		trimmed[#trimmed + 1] = table.concat(fields, delim)
	end

	vim.api.nvim_buf_set_lines(0, 0, -1, false, trimmed)
	vim.notify("Alignment removed", vim.log.levels.INFO, { title = "CSV" })
end, { desc = csv_icon .. " Unalign" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SORT
--
-- Column-based sorting with automatic type detection.
-- Numeric values are sorted numerically, strings are sorted
-- case-insensitively. The header row (first line) is always preserved.
-- ═══════════════════════════════════════════════════════════════════════════

--- Sort rows by a selected column (ascending).
---
--- Flow:
--- 1. Parse header row to extract column names
--- 2. Present column selection via `vim.ui.select()` with `N: name` format
--- 3. Sort data rows (excluding header) by the selected column
--- 4. Auto-detect numeric vs string sort per comparison pair
--- 5. Replace buffer with header + sorted data
keys.lang_map("csv", "n", "<leader>ls", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	if #lines < 2 then return end
	local delim = detect_delimiter()
	local header = lines[1]
	local header_fields = split_csv_line(header, delim)

	---@type string[]
	local col_names = {}
	for i, f in ipairs(header_fields) do
		col_names[#col_names + 1] = string.format("%d: %s", i, f:match("^%s*(.-)%s*$"))
	end

	vim.ui.select(col_names, { prompt = csv_icon .. " Sort by column:" }, function(_, idx)
		if not idx then return end

		---@type string[]
		local data = {}
		for i = 2, #lines do
			data[#data + 1] = lines[i]
		end

		table.sort(data, function(a, b)
			local fa = split_csv_line(a, delim)[idx] or ""
			local fb = split_csv_line(b, delim)[idx] or ""
			-- Numeric sort if both values are numbers
			local na, nb = tonumber(fa), tonumber(fb)
			if na and nb then return na < nb end
			return fa:lower() < fb:lower()
		end)

		---@type string[]
		local result = { header }
		for _, line in ipairs(data) do
			result[#result + 1] = line
		end
		vim.api.nvim_buf_set_lines(0, 0, -1, false, result)
		vim.notify("Sorted by column " .. idx, vim.log.levels.INFO, { title = "CSV" })
	end)
end, { desc = csv_icon .. " Sort by column" })

--- Sort rows by a selected column (descending).
---
--- Same flow as ascending sort but with reversed comparison.
keys.lang_map("csv", "n", "<leader>lr", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	if #lines < 2 then return end
	local delim = detect_delimiter()
	local header = lines[1]
	local header_fields = split_csv_line(header, delim)

	---@type string[]
	local col_names = {}
	for i, f in ipairs(header_fields) do
		col_names[#col_names + 1] = string.format("%d: %s", i, f:match("^%s*(.-)%s*$"))
	end

	vim.ui.select(col_names, { prompt = csv_icon .. " Reverse sort by:" }, function(_, idx)
		if not idx then return end

		---@type string[]
		local data = {}
		for i = 2, #lines do
			data[#data + 1] = lines[i]
		end

		table.sort(data, function(a, b)
			local fa = split_csv_line(a, delim)[idx] or ""
			local fb = split_csv_line(b, delim)[idx] or ""
			local na, nb = tonumber(fa), tonumber(fb)
			if na and nb then return na > nb end
			return fa:lower() > fb:lower()
		end)

		---@type string[]
		local result = { header }
		for _, line in ipairs(data) do
			result[#result + 1] = line
		end
		vim.api.nvim_buf_set_lines(0, 0, -1, false, result)
		vim.notify("Reverse sorted by column " .. idx, vim.log.levels.INFO, { title = "CSV" })
	end)
end, { desc = csv_icon .. " Reverse sort" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — QUERY / FILTER
--
-- Data querying via RBQL (rainbow_csv's SQL-like query language) and
-- Lua pattern-based row filtering.
--
-- RBQL supports:
-- SELECT, WHERE, ORDER BY, GROUP BY, DISTINCT, JOIN, UPDATE
-- with Python or JavaScript expressions.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the RBQL query console (rainbow_csv).
---
--- RBQL (Rainbow Query Language) provides SQL-like queries:
--- ```
--- SELECT a1, a3 WHERE a2 > 100 ORDER BY a1
--- ```
--- Column references use `a1`, `a2`, etc. (1-indexed).
--- Requires rainbow_csv to be loaded.
keys.lang_map("csv", "n", "<leader>lq", function()
	if vim.fn.exists(":RainbowQuery") == 2 then
		vim.cmd("RainbowQuery")
	else
		vim.notify("rainbow_csv not loaded", vim.log.levels.INFO, { title = "CSV" })
	end
end, { desc = icons.ui.Search .. " RBQL query" })

--- Filter rows by a Lua pattern on a selected column.
---
--- Flow:
--- 1. Prompt for column number (1-indexed)
--- 2. Prompt for Lua pattern (e.g. `^A`, `%d+`, `foo`)
--- 3. Filter data rows (header is always kept)
--- 4. Display results in a new scratch buffer (split)
---
--- The scratch buffer has `bufhidden=wipe` so it's automatically
--- cleaned up when closed. Filetype is set to "csv" for syntax.
keys.lang_map("csv", "n", "<leader>lf", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	if #lines < 2 then return end
	local delim = detect_delimiter()

	vim.ui.input({ prompt = "Column number: ", default = "1" }, function(col_str)
		if not col_str then return end
		---@type integer|nil
		local col = tonumber(col_str)
		if not col then return end

		vim.ui.input({ prompt = "Pattern (Lua): " }, function(pattern)
			if not pattern or pattern == "" then return end

			---@type string[]
			local result = { lines[1] }
			for i = 2, #lines do
				local fields = split_csv_line(lines[i], delim)
				local val = fields[col] or ""
				if val:match(pattern) then result[#result + 1] = lines[i] end
			end

			-- ── Display in scratch buffer ─────────────────────────────
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, result)
			vim.api.nvim_set_option_value("filetype", "csv", { buf = buf })
			vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
			vim.cmd.split()
			vim.api.nvim_win_set_buf(0, buf)
			vim.notify(string.format("Filtered: %d/%d rows", #result - 1, #lines - 1), vim.log.levels.INFO, { title = "CSV" })
		end)
	end)
end, { desc = icons.ui.Search .. " Filter rows" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CONVERSION
--
-- Format conversion to Markdown tables and JSON arrays.
-- Both outputs are displayed in new scratch buffers (vsplit)
-- with the appropriate filetype for syntax highlighting.
-- ═══════════════════════════════════════════════════════════════════════════

--- Convert CSV to a Markdown table in a scratch buffer (vsplit).
---
--- Output format:
--- ```markdown
--- | name  | age | city     |
--- | ----- | --- | -------- |
--- | Alice | 30  | New York |
--- ```
---
--- Columns are padded to the maximum field width for alignment.
--- The header separator uses dashes matching each column width.
keys.lang_map("csv", "n", "<leader>lt", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	if #lines == 0 then return end
	local delim = detect_delimiter()

	-- ── Parse rows and compute column widths ──────────────────────────
	---@type string[][]
	local rows = {}
	---@type table<integer, integer>
	local max_widths = {}
	for _, line in ipairs(lines) do
		if line ~= "" then
			local fields = split_csv_line(line, delim)
			for i, f in ipairs(fields) do
				fields[i] = f:match("^%s*(.-)%s*$")
				max_widths[i] = math.max(max_widths[i] or 0, #fields[i])
			end
			rows[#rows + 1] = fields
		end
	end

	-- ── Build Markdown table lines ────────────────────────────────────
	---@type string[]
	local md_lines = {}
	for r, fields in ipairs(rows) do
		---@type string[]
		local parts = {}
		for c, f in ipairs(fields) do
			local w = max_widths[c] or #f
			parts[#parts + 1] = " " .. f .. string.rep(" ", w - #f) .. " "
		end
		md_lines[#md_lines + 1] = "|" .. table.concat(parts, "|") .. "|"

		-- ── Header separator (after first row) ────────────────────────
		if r == 1 then
			---@type string[]
			local sep_parts = {}
			for c = 1, #fields do
				sep_parts[#sep_parts + 1] = " " .. string.rep("-", max_widths[c] or 3) .. " "
			end
			md_lines[#md_lines + 1] = "|" .. table.concat(sep_parts, "|") .. "|"
		end
	end

	-- ── Display in scratch buffer ─────────────────────────────────────
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, md_lines)
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.cmd.vsplit()
	vim.api.nvim_win_set_buf(0, buf)
end, { desc = icons.ui.Table .. " To markdown table" })

--- Convert CSV to a JSON array of objects in a scratch buffer (vsplit).
---
--- Uses the header row as object keys. Performs type coercion:
--- - Numeric strings → JSON numbers (preserves precision)
--- - `"true"` / `"false"` → JSON booleans
--- - Everything else → JSON strings (properly escaped)
---
--- Output format:
--- ```json
--- [
---   { "name": "Alice", "age": 30, "active": true }
--- ]
--- ```
keys.lang_map("csv", "n", "<leader>lj", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	if #lines < 2 then return end
	local delim = detect_delimiter()

	-- ── Parse header ──────────────────────────────────────────────────
	local header = split_csv_line(lines[1], delim)
	for i, h in ipairs(header) do
		header[i] = h:match("^%s*(.-)%s*$")
	end

	-- ── Build JSON objects ────────────────────────────────────────────
	---@type string[]
	local objects = {}
	for r = 2, #lines do
		if lines[r] ~= "" then
			local fields = split_csv_line(lines[r], delim)
			---@type string[]
			local obj = {}
			for c, key in ipairs(header) do
				local val = (fields[c] or ""):match("^%s*(.-)%s*$")
				local num = tonumber(val)
				if num then
					obj[#obj + 1] = string.format("    %s: %s", vim.fn.json_encode(key), val)
				elseif val == "true" or val == "false" then
					obj[#obj + 1] = string.format("    %s: %s", vim.fn.json_encode(key), val)
				else
					obj[#obj + 1] = string.format("    %s: %s", vim.fn.json_encode(key), vim.fn.json_encode(val))
				end
			end
			objects[#objects + 1] = "  {\n" .. table.concat(obj, ",\n") .. "\n  }"
		end
	end

	local json = "[\n" .. table.concat(objects, ",\n") .. "\n]"

	-- ── Display in scratch buffer ─────────────────────────────────────
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(json, "\n"))
	vim.api.nvim_set_option_value("filetype", "json", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.cmd.vsplit()
	vim.api.nvim_win_set_buf(0, buf)
end, { desc = icons.file.Json .. " To JSON" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — COLUMN INFO / DELIMITER
--
-- Column introspection and delimiter management.
-- Column info includes header name, row counts, and numeric statistics
-- (sum, average) when the column contains numeric data.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show detailed information about the column under the cursor.
---
--- Determines which column the cursor is in by walking the line
--- character-by-character, tracking delimiters and quote state.
---
--- Displays:
--- - Column index and header name
--- - Total rows and non-empty count
--- - Detected delimiter
--- - For numeric columns: value count, sum, and average
keys.lang_map("csv", "n", "<leader>lc", function()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1
	local delim = detect_delimiter()

	-- ── Determine which field the cursor is in ────────────────────────
	---@type integer
	local field_idx = 1
	---@type boolean
	local in_quote = false
	for i = 1, #line do
		local c = line:sub(i, i)
		if c == '"' then
			in_quote = not in_quote
		elseif c == delim and not in_quote then
			if i >= col then break end
			field_idx = field_idx + 1
		end
	end

	-- ── Get header name ───────────────────────────────────────────────
	local header_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
	local headers = split_csv_line(header_line, delim)
	---@type string
	local header_name = headers[field_idx] and headers[field_idx]:match("^%s*(.-)%s*$") or "?"

	-- ── Compute column statistics ─────────────────────────────────────
	local data_lines = vim.api.nvim_buf_get_lines(0, 1, -1, false)
	---@type string[]
	local values = {}
	---@type integer
	local non_empty = 0
	---@type integer
	local numeric_count = 0
	---@type number
	local sum = 0

	for _, l in ipairs(data_lines) do
		if l ~= "" then
			local fields = split_csv_line(l, delim)
			local val = (fields[field_idx] or ""):match("^%s*(.-)%s*$")
			values[#values + 1] = val
			if val ~= "" then
				non_empty = non_empty + 1
				local num = tonumber(val)
				if num then
					numeric_count = numeric_count + 1
					sum = sum + num
				end
			end
		end
	end

	-- ── Format output ─────────────────────────────────────────────────
	---@type string
	local info = string.format(
		"%s Column Info:\n" .. "  Column:    %d — %s\n" .. "  Rows:      %d (%d non-empty)\n" .. "  Delimiter: %s",
		csv_icon,
		field_idx,
		header_name,
		#values,
		non_empty,
		delim == "\t" and "TAB" or delim
	)

	if numeric_count > 0 then
		local avg = sum / numeric_count
		info = info
			.. string.format(
				"\n  ─────────────────\n  Numeric:   %d values\n  Sum:       %.2f\n  Average:   %.2f",
				numeric_count,
				sum,
				avg
			)
	end

	vim.notify(info, vim.log.levels.INFO, { title = "CSV" })
end, { desc = icons.diagnostics.Info .. " Column info" })

--- Set the delimiter manually (overrides auto-detection).
---
--- Stores the selected delimiter in `vim.b.csv_delimiter` (buffer-local
--- variable) for use by other CSV functions. Presents the 4 standard
--- delimiters via `vim.ui.select()`.
---
--- NOTE: This does not yet propagate to helper functions. A future
--- enhancement could make `detect_delimiter()` check `vim.b.csv_delimiter`
--- before auto-detecting.
keys.lang_map("csv", "n", "<leader>ld", function()
	---@type { name: string, delim: string }[]
	local choices = {
		{ name = "Comma (,)", delim = "," },
		{ name = "Tab (\\t)", delim = "\t" },
		{ name = "Semicolon (;)", delim = ";" },
		{ name = "Pipe (|)", delim = "|" },
	}

	vim.ui.select(
		vim.tbl_map(function(c)
			return c.name
		end, choices),
		{ prompt = csv_icon .. " Delimiter:" },
		function(_, idx)
			if not idx then return end
			vim.b.csv_delimiter = choices[idx].delim
			vim.notify("Delimiter set to: " .. choices[idx].name, vim.log.levels.INFO, { title = "CSV" })
		end
	)
end, { desc = csv_icon .. " Set delimiter" })

--- Toggle visual header highlighting on the first line.
---
--- Uses a buffer-local namespace to add/remove `CursorLine` highlight
--- on line 0. The namespace handle is stored in `vim.w.csv_header_ns`
--- (window-local) to track toggle state.
keys.lang_map("csv", "n", "<leader>lH", function()
	if vim.w.csv_header_ns then
		vim.api.nvim_buf_clear_namespace(0, vim.w.csv_header_ns, 0, -1)
		vim.w.csv_header_ns = nil
		vim.notify("Header highlight off", vim.log.levels.INFO, { title = "CSV" })
	else
		local ns = vim.api.nvim_create_namespace("csv_header")
		vim.api.nvim_buf_add_highlight(0, ns, "CursorLine", 0, 0, -1)
		vim.w.csv_header_ns = ns
		vim.notify("Header highlight on", vim.log.levels.INFO, { title = "CSV" })
	end
end, { desc = csv_icon .. " Toggle header" })

--- Show the number of columns detected from the first line.
keys.lang_map("csv", "n", "<leader>ln", function()
	local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
	local delim = detect_delimiter()
	local fields = split_csv_line(first_line, delim)
	vim.notify(
		string.format("Columns: %d (delimiter: %s)", #fields, delim == "\t" and "TAB" or delim),
		vim.log.levels.INFO,
		{ title = "CSV" }
	)
end, { desc = csv_icon .. " Column count" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — STATS / HELP
--
-- File-level statistics and RFC 4180 documentation access.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show comprehensive file statistics.
---
--- Displays:
--- - Number of columns (from header row)
--- - Data row count (excluding header and empty lines)
--- - Empty row count
--- - Total line count
--- - Detected delimiter
--- - File size in bytes
keys.lang_map("csv", "n", "<leader>li", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local delim = detect_delimiter()
	local first = split_csv_line(lines[1] or "", delim)

	---@type integer
	local data_rows = 0
	---@type integer
	local empty_rows = 0
	for i = 2, #lines do
		if lines[i] == "" then
			empty_rows = empty_rows + 1
		else
			data_rows = data_rows + 1
		end
	end

	---@type string
	local stats = string.format(
		"%s CSV Stats:\n"
			.. "  Columns:     %d\n"
			.. "  Data rows:   %d\n"
			.. "  Empty rows:  %d\n"
			.. "  Total lines: %d\n"
			.. "  Delimiter:   %s\n"
			.. "  File size:   %s",
		csv_icon,
		#first,
		data_rows,
		empty_rows,
		#lines,
		delim == "\t" and "TAB" or delim,
		vim.fn.getfsize(vim.fn.expand("%:p")) .. " bytes"
	)
	vim.notify(stats, vim.log.levels.INFO, { title = "CSV" })
end, { desc = icons.diagnostics.Info .. " File stats" })

--- Open the CSV RFC 4180 specification in the default browser.
---
--- RFC 4180 defines the standard format for CSV files including
--- quoting rules, line endings, and header conventions.
keys.lang_map("csv", "n", "<leader>lh", function()
	vim.ui.open("https://datatracker.ietf.org/doc/html/rfc4180")
end, { desc = icons.ui.Note .. " CSV reference (RFC 4180)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers CSV-specific alignment presets when mini.align is available.
-- Loaded once per session (guarded by is_language_loaded).
--
-- Preset: csv_columns — align CSV fields on the comma delimiter.
-- For more advanced alignment, use the built-in <leader>la keymap
-- which respects quoted fields and multi-character delimiters.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("csv") then
		---@type string Alignment preset icon from icons.file
		local align_icon = icons.file.Csv

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			csv_columns = {
				description = "Align CSV column data on ','",
				icon = align_icon,
				split_pattern = ",",
				category = "data",
				lang = "csv",
				filetypes = { "csv" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("csv", "csv_columns")
		align_registry.mark_language_loaded("csv")

		-- ── Alignment keymap ─────────────────────────────────────────
		keys.lang_map("csv", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("csv_columns"), {
			desc = align_icon .. "  Align CSV columns",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations.
--
-- NOTE: This module does not configure an LSP server, formatter, or
-- linter — CSV is a data format, not a programming language. The
-- nvim-lspconfig entry is used solely for filetype detection and
-- buffer option registration.
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for CSV                    │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ init only (filetype + buffer opts, no LSP)  │
-- │ rainbow_csv        │ ft = "csv" (true lazy load)                  │
-- │ nvim-treesitter    │ opts merge (csv parser to ensure_installed)  │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for CSV
return {
	-- ── FILETYPE DETECTION & BUFFER OPTIONS ────────────────────────────
	-- No LSP server is configured — this entry is used solely for
	-- filetype registration and buffer option setup.
	--
	-- Filetype mapping:
	-- • .csv → csv (Comma-Separated Values)
	-- • .tsv → csv (Tab-Separated Values, same parsing logic)
	-- • .psv → csv (Pipe-Separated Values)
	--
	-- Buffer options are optimized for tabular data viewing:
	-- • wrap=false + sidescroll/sidescrolloff for horizontal navigation
	-- • relativenumber=false for absolute row references
	-- • cursorline=true for row tracking
	-- • expandtab=false to preserve TAB delimiters in TSV files
	-- ────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		init = function()
			-- ── Filetype detection ──────────────────────────────────
			vim.filetype.add({
				extension = {
					csv = "csv",
					tsv = "csv",
					psv = "csv",
				},
			})

			-- ── Buffer-local options for CSV files ────────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "csv" },
				callback = function()
					local opt = vim.opt_local

					-- ── Layout (horizontal scrolling) ─────────────────
					opt.wrap = false
					opt.sidescroll = 5
					opt.sidescrolloff = 10

					-- ── Line numbers (absolute for row reference) ─────
					opt.number = true
					opt.relativenumber = false
					opt.cursorline = true

					-- ── Tabs (preserve TSV delimiters) ────────────────
					opt.tabstop = 4
					opt.shiftwidth = 4
					opt.expandtab = false
				end,
				desc = "NvimEnterprise: CSV buffer options",
			})
		end,
	},

	-- ── RAINBOW CSV ────────────────────────────────────────────────────
	-- rainbow_csv: per-column syntax highlighting and RBQL query engine.
	-- Each column gets a distinct color for visual identification.
	--
	-- Configuration (via vim.g global variables):
	-- • rbql_with_headers = 1 — treat first row as column headers
	-- • rainbow_csv_autodetect = 1 — auto-detect delimiter on file open
	--
	-- RBQL commands: :RainbowQuery, :RainbowDelim, :NoRainbowDelim
	-- ────────────────────────────────────────────────────────────────────
	{
		"mechatroner/rainbow_csv",
		ft = { "csv" },
		init = function()
			-- Must be set before the plugin loads (hence init, not config)
			vim.g.rbql_with_headers = 1
			vim.g.rainbow_csv_autodetect = 1
		end,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────
	-- csv: basic syntax highlighting and folding for CSV files.
	-- Complements rainbow_csv's column-based coloring.
	-- ────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"csv",
			},
		},
	},
}
