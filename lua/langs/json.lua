---@file lua/langs/json.lua
---@description JSON/JSONC — LSP (jsonls + SchemaStore), formatter, treesitter & buffer-local keymaps
---@module "langs.json"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.yaml               YAML language support (JSON ↔ YAML conversion)
---@see langs.python             Python language support (same architecture)
---@see langs.javascript         JavaScript language support (shared prettier)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/json.lua — JSON / JSONC language support                          ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("json") → {} if off         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "json" / "jsonc"):           │    ║
--- ║  │  ├─ LSP          jsonls  (Microsoft JSON Language Server)        │    ║
--- ║  │  │               + SchemaStore (4000+ JSON schemas)              │    ║
--- ║  │  ├─ Formatter    prettier (conform.nvim)                         │    ║
--- ║  │  ├─ Treesitter   json · json5 · jsonc parsers                    │    ║
--- ║  │  └─ CLI tools    jq (validate, query, format, sort, minify)      │    ║
--- ║  │                  yq (JSON → YAML conversion)                     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ VALIDATE  r  Validate (jq empty)                             │    ║
--- ║  │  ├─ FORMAT    p  Pretty-print (jq .)   m  Minify (jq -c)         │    ║
--- ║  │  ├─ QUERY     x  JQ expression → scratch buffer                  │    ║
--- ║  │  ├─ SORT      s  Sort keys recursively (jq -S)                   │    ║
--- ║  │  ├─ CONVERT   t  JSON → YAML (yq or python3 fallback)            │    ║
--- ║  │  ├─ PATH      c  Copy treesitter path to clipboard               │    ║
--- ║  │  ├─ ESCAPE    e  Escape string          E  Unescape string       │    ║
--- ║  │  ├─ FOLD      f  Toggle all folds                                │    ║
--- ║  │  ├─ DOCS      h  JSON/JQ reference picker                        │    ║
--- ║  │  └─ STATS     i  Document statistics                             │    ║
--- ║  │                                                                  │    ║
--- ║  │  jq integration flow:                                            │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. check_jq() verifies jq is in $PATH                   │    │    ║
--- ║  │  │  2. get_buf_content() reads buffer as single string      │    │    ║
--- ║  │  │  3. run_jq(flags, content) pipes through jq              │    │    ║
--- ║  │  │  4. Result either:                                       │    │    ║
--- ║  │  │     • Replaces buffer content (format/minify/sort)       │    │    ║
--- ║  │  │     • Opens in scratch buffer (query/convert)            │    │    ║
--- ║  │  │     • Displays as notification (validate/stats)          │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType json/jsonc):                        ║
--- ║  • conceallevel=0                (show all quotes and punctuation)       ║
--- ║  • colorcolumn=""                (no column guide for data files)        ║
--- ║  • tabstop=2, shiftwidth=2       (standard JSON indentation)             ║
--- ║  • expandtab=true                (spaces, never tabs)                    ║
--- ║  • Treesitter folding            (foldmethod=expr, foldlevel=99)         ║
--- ║                                                                          ║
--- ║  Schema integration:                                                     ║
--- ║  • SchemaStore.nvim provides 4000+ schemas from schemastore.org          ║
--- ║  • Schemas are auto-matched by filename (package.json, tsconfig, etc.)   ║
--- ║  • jsonls validates against matched schema in real-time                  ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .json                 → json                                          ║
--- ║  • .jsonc, .json5        → jsonc                                         ║
--- ║  • .babelrc, .eslintrc   → json                                          ║
--- ║  • tsconfig.json, etc.   → jsonc  (comments allowed)                     ║
--- ║  • Auto-detect JSONC     → scans first 5 lines for // or /* comments     ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if JSON support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("json") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string JSON Nerd Font icon (trailing whitespace stripped)
local json_icon = icons.lang.json:gsub("%s+$", "")

---@type string[] Filetypes that this module applies to
local json_fts = { "json", "jsonc" }

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUPS
--
-- Registers the <leader>l group label for JSON buffers.
-- Both `json` and `jsonc` get the same group label since JSONC
-- is a superset of JSON (JSON with Comments).
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("json", "JSON", json_icon)
keys.lang_group("jsonc", "JSONC", json_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- jq availability check, buffer content extraction, and jq execution.
-- These three functions eliminate massive code duplication across the
-- six+ keymaps that pipe buffer content through jq.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that the `jq` command-line JSON processor is available.
---
--- Displays a warning notification with install instructions if
--- `jq` is not found in `$PATH`.
---
--- ```lua
--- if not check_jq() then return end
--- ```
---
---@return boolean available `true` if `jq` is executable, `false` otherwise
---@private
local function check_jq()
	if vim.fn.executable("jq") ~= 1 then
		vim.notify("Install jq: brew install jq", vim.log.levels.WARN, { title = "JSON" })
		return false
	end
	return true
end

--- Get the entire buffer content as a single string.
---
--- Reads all lines from the current buffer and joins them with
--- newline characters. Used as input for jq pipe operations.
---
--- ```lua
--- local content = get_buf_content()
--- local result = vim.fn.system("jq '.'", content)
--- ```
---
---@return string content Buffer content joined with newlines
---@private
local function get_buf_content()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	return table.concat(lines, "\n")
end

--- Run a jq command on the given content and return the result.
---
--- Pipes `content` through `jq <args>` via `vim.fn.system()`.
--- On success, returns the output lines (trailing empty line stripped).
--- On failure, displays an error notification and returns `nil`.
---
--- ```lua
--- local lines = run_jq("'.'", content)
--- if lines then
---     vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
--- end
--- ```
---
---@param args string jq arguments and expression (e.g. `"'.'", `"-S '.'"`, `"-c '.'"`)
---@param content string JSON content to pipe as stdin
---@return string[]|nil lines Output lines on success, `nil` on error
---@private
local function run_jq(args, content)
	local result = vim.fn.system("jq " .. args, content)
	if vim.v.shell_error ~= 0 then
		vim.notify("jq error:\n" .. result, vim.log.levels.ERROR, { title = "JSON" })
		return nil
	end

	local lines = vim.split(result, "\n")
	-- Strip trailing empty line (jq always appends newline)
	if lines[#lines] == "" then
		lines[#lines] = nil
	end
	return lines
end

--- Open content in a scratch buffer with the given filetype.
---
--- Creates a new unlisted scratch buffer, populates it with the
--- given lines, sets the filetype, and opens it in a vertical split.
--- The buffer is wiped when hidden (no save prompt).
---
--- ```lua
--- open_scratch(yaml_lines, "yaml")
--- ```
---
---@param lines string[] Content lines for the scratch buffer
---@param ft string Filetype to set on the scratch buffer
---@return nil
---@private
local function open_scratch(lines, ft)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("filetype", ft, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.cmd.vsplit()
	vim.api.nvim_win_set_buf(0, buf)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — VALIDATE / FORMAT
--
-- JSON validation and formatting via jq. Validation uses `jq empty`
-- which exits non-zero on malformed JSON. Formatting uses `jq '.'`
-- for pretty-printing and `jq -c '.'` for minification.
-- ═══════════════════════════════════════════════════════════════════════════

--- Validate the current buffer as JSON via `jq empty`.
---
--- `jq empty` parses the entire input without producing output.
--- If the JSON is valid, it exits 0 (success notification).
--- If malformed, it exits non-zero with the parse error (error notification).
keys.lang_map(json_fts, "n", "<leader>lr", function()
	if not check_jq() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("jq empty " .. vim.fn.shellescape(file) .. " 2>&1")
	if vim.v.shell_error == 0 then
		vim.notify("✓ Valid JSON", vim.log.levels.INFO, { title = "JSON" })
	else
		vim.notify("✗ Invalid:\n" .. result, vim.log.levels.ERROR, { title = "JSON" })
	end
end, { desc = icons.ui.Check .. " Validate (jq)" })

--- Pretty-print the buffer content via `jq '.'`.
---
--- Replaces the entire buffer with jq's formatted output (2-space
--- indent, sorted consistent with jq defaults). Notifies on success.
keys.lang_map(json_fts, "n", "<leader>lp", function()
	if not check_jq() then return end
	local lines = run_jq("'.'", get_buf_content())
	if lines then
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
		vim.notify("Pretty-printed", vim.log.levels.INFO, { title = "JSON" })
	end
end, { desc = json_icon .. " Pretty-print" })

--- Minify (compact) the buffer content via `jq -c '.'`.
---
--- Replaces the entire buffer with a single-line compact JSON
--- representation. Useful for API payloads or reducing file size.
keys.lang_map(json_fts, "n", "<leader>lm", function()
	if not check_jq() then return end
	local lines = run_jq("-c '.'", get_buf_content())
	if lines then
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
		vim.notify("Minified", vim.log.levels.INFO, { title = "JSON" })
	end
end, { desc = json_icon .. " Minify" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — JQ QUERY
--
-- Interactive jq expression evaluation. Prompts for a jq expression,
-- runs it against the current buffer, and opens the result in a
-- scratch buffer for inspection.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run a jq expression and show results in a scratch buffer.
---
--- Prompts for a jq expression via `vim.ui.input()` (default: `.`),
--- pipes the current buffer content through jq, and opens the result
--- in a vertical split scratch buffer with JSON highlighting.
---
--- The scratch buffer is set to `bufhidden=wipe` so it disappears
--- when closed (no save prompt, no buffer list clutter).
keys.lang_map(json_fts, "n", "<leader>lx", function()
	if not check_jq() then return end
	vim.ui.input({ prompt = "jq expression: ", default = "." }, function(expr)
		if not expr or expr == "" then return end
		local lines = run_jq(vim.fn.shellescape(expr), get_buf_content())
		if lines then
			open_scratch(lines, "json")
		end
	end)
end, { desc = icons.ui.Search .. " JQ query" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SORT / TRANSFORM
--
-- Key sorting and format conversion utilities.
-- Sort uses `jq -S` for recursive alphabetical key ordering.
-- Conversion supports JSON → YAML via yq or python3 fallback.
-- ═══════════════════════════════════════════════════════════════════════════

--- Sort object keys recursively via `jq -S '.'`.
---
--- Replaces the buffer with the same JSON but with all object keys
--- sorted alphabetically at every nesting level. Useful for
--- normalizing config files and reducing diff noise.
keys.lang_map(json_fts, "n", "<leader>ls", function()
	if not check_jq() then return end
	local lines = run_jq("-S '.'", get_buf_content())
	if lines then
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
		vim.notify("Keys sorted", vim.log.levels.INFO, { title = "JSON" })
	end
end, { desc = json_icon .. " Sort keys" })

--- Convert JSON to YAML and open in a scratch buffer.
---
--- Resolution order for converter:
--- 1. `yq` — fast, native Go binary (`yq -p=json -o=yaml`)
--- 2. `python3` + PyYAML — fallback via inline script
--- 3. Neither — notification with install instructions
---
--- The result opens in a vertical split scratch buffer with YAML
--- filetype highlighting. The original JSON buffer is not modified.
keys.lang_map(json_fts, "n", "<leader>lt", function()
	---@type string|nil
	local cmd
	if vim.fn.executable("yq") == 1 then
		cmd = "yq -p=json -o=yaml"
	elseif vim.fn.executable("python3") == 1 then
		cmd = "python3 -c 'import sys,json,yaml; yaml.dump(json.load(sys.stdin),sys.stdout,default_flow_style=False)'"
	else
		vim.notify("Install yq: brew install yq", vim.log.levels.WARN, { title = "JSON" })
		return
	end

	local content = get_buf_content()
	local result = vim.fn.system(cmd, content)
	if vim.v.shell_error ~= 0 then
		vim.notify("Conversion error:\n" .. result, vim.log.levels.ERROR, { title = "JSON" })
		return
	end

	open_scratch(vim.split(result, "\n"), "yaml")
end, { desc = icons.file.Yaml .. " Convert to YAML" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — JSON PATH / ESCAPE
--
-- Treesitter-based JSON path extraction and string escape/unescape
-- utilities for working with embedded strings in JSON values.
-- ═══════════════════════════════════════════════════════════════════════════

--- Copy the JSON path to the key under cursor using treesitter.
---
--- Walks up the treesitter AST from the cursor position, collecting
--- path segments:
--- - `pair` nodes → `.keyname` (dot-notation)
--- - `array` nodes → `[index]` (bracket-notation, 0-based)
---
--- The assembled path is copied to the system clipboard (`+` register)
--- and displayed in a notification.
---
--- ```
--- { "users": [{ "name": "Alice" }] }
---                        ^ cursor here → ".users[0].name"
--- ```
keys.lang_map(json_fts, "n", "<leader>lc", function()
	local node = vim.treesitter.get_node()
	if not node then
		vim.notify("No treesitter node", vim.log.levels.INFO, { title = "JSON" })
		return
	end

	---@type string[]
	local parts = {}
	---@type TSNode|nil
	local current = node

	while current do
		local parent = current:parent()
		if not parent then break end

		if parent:type() == "pair" then
			local key_node = parent:field("key")[1]
			if key_node then
				local key = vim.treesitter.get_node_text(key_node, 0):gsub('^"', ""):gsub('"$', "")
				table.insert(parts, 1, "." .. key)
			end
		elseif parent:type() == "array" then
			---@type integer
			local idx = 0
			for child in parent:iter_children() do
				if child:id() == current:id() then break end
				if child:named() then idx = idx + 1 end
			end
			table.insert(parts, 1, "[" .. idx .. "]")
		end

		current = parent
	end

	---@type string
	local path = table.concat(parts, "")
	if path == "" then path = "." end
	vim.fn.setreg("+", path)
	vim.notify("Copied: " .. path, vim.log.levels.INFO, { title = "JSON" })
end, { desc = json_icon .. " Copy path" })

--- Escape special characters in the JSON string on the current line.
---
--- Detects a quoted string on the current line, then escapes
--- backslashes, double quotes, newlines, and tabs within it.
--- Notifies if no quoted string is found.
---
--- NOTE: Operates on the first quoted string found on the line.
--- Does not handle multi-line strings or strings with existing escapes.
keys.lang_map(json_fts, "n", "<leader>le", function()
	local line = vim.api.nvim_get_current_line()
	local content = line:match('^%s*"(.-)"%s*$')
	if content then
		local escaped = content:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\t", "\\t")
		vim.api.nvim_set_current_line(line:gsub(vim.pesc(content), escaped))
	else
		vim.notify("No string found on current line", vim.log.levels.INFO, { title = "JSON" })
	end
end, { desc = json_icon .. " Escape string" })

--- Unescape a JSON string on the current line.
---
--- Resolves escape sequences (`\\n` → newline, `\\t` → tab,
--- `\\"` → `"`, `\\\\` → `\`) in the current line. Notifies
--- if no escape sequences were found.
keys.lang_map(json_fts, "n", "<leader>lE", function()
	local line = vim.api.nvim_get_current_line()
	local unescaped = line:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub('\\"', '"'):gsub("\\\\", "\\")
	if unescaped ~= line then
		vim.api.nvim_set_current_line(unescaped)
		vim.notify("Unescaped", vim.log.levels.INFO, { title = "JSON" })
	end
end, { desc = json_icon .. " Unescape string" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FOLD
--
-- Toggle between fully collapsed and fully expanded fold states.
-- Uses treesitter-based folding configured in the FileType autocmd.
-- ═══════════════════════════════════════════════════════════════════════════

--- Toggle all folds between collapsed and expanded.
---
--- If any folds are currently open (`foldlevel > 0`), collapses all
--- folds (`zM`). Otherwise, expands all folds (`zR`). Notifies the
--- user of the resulting state.
keys.lang_map(json_fts, "n", "<leader>lf", function()
	local current = vim.wo.foldlevel
	if current > 0 then
		vim.cmd("normal! zM")
		vim.notify("Folds: all collapsed", vim.log.levels.INFO, { title = "JSON" })
	else
		vim.cmd("normal! zR")
		vim.notify("Folds: all expanded", vim.log.levels.INFO, { title = "JSON" })
	end
end, { desc = json_icon .. " Toggle fold level" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — STATS
--
-- Document statistics computed via simple pattern matching.
-- Provides a quick overview of the JSON structure without
-- requiring full parsing.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show document statistics (lines, size, objects, arrays, keys).
---
--- Counts structural elements via simple pattern matching:
--- - Objects: count of `{` characters
--- - Arrays:  count of `[` characters
--- - Keys:    count of `"…":` patterns (quoted key followed by colon)
---
--- Also reports line count and file size in bytes.
---
--- NOTE: Pattern-based counting is approximate. Strings containing
--- `{`, `[`, or `"key":` patterns will inflate the counts.
--- For exact counts, use `jq '[paths | length] | length'`.
keys.lang_map(json_fts, "n", "<leader>li", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local content = table.concat(lines, "\n")

	---@type integer
	local objects = 0
	---@type integer
	local arrays = 0
	---@type integer
	local keys_count = 0

	for c in content:gmatch(".") do
		if c == "{" then objects = objects + 1 end
		if c == "[" then arrays = arrays + 1 end
	end
	for _ in content:gmatch('"[^"]*"%s*:') do
		keys_count = keys_count + 1
	end

	local stats = string.format(
		"%s JSON Stats:\n  Lines:    %d\n  Size:     %s bytes\n  Objects:  %d\n  Arrays:   %d\n  Keys:     %d",
		json_icon,
		#lines,
		vim.fn.getfsize(vim.fn.expand("%:p")),
		objects,
		arrays,
		keys_count
	)
	vim.notify(stats, vim.log.levels.INFO, { title = "JSON" })
end, { desc = icons.diagnostics.Info .. " Document stats" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to JSON specification, jq manual, JSON Schema, and
-- JSON Path documentation via a fuzzy-searchable picker.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open a JSON/JQ documentation reference in the browser.
---
--- Presents a list of curated references via `vim.ui.select()`:
--- 1. JSON Spec (RFC 8259) — the official JSON standard
--- 2. jq Manual — complete jq filter reference
--- 3. JSON Schema — schema validation specification
--- 4. JSON Path — XPath-like query syntax for JSON
---
--- Opens the selected URL in the system browser via `vim.ui.open()`.
keys.lang_map(json_fts, "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "JSON Spec (RFC 8259)", url = "https://datatracker.ietf.org/doc/html/rfc8259" },
		{ name = "jq Manual", url = "https://jqlang.github.io/jq/manual/" },
		{ name = "JSON Schema", url = "https://json-schema.org/" },
		{ name = "JSON Path", url = "https://goessner.net/articles/JsonPath/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r) return r.name end, refs),
		{ prompt = json_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " JSON / JQ reference" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers JSON-specific alignment presets for mini.align:
-- • json_pairs — align key-value pairs on ":"
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("json") then
		---@type string Alignment preset icon from icons.file
		local json_align_icon = icons.file.Json

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			json_pairs = {
				description = "Align JSON key-value pairs on ':'",
				icon = json_align_icon,
				split_pattern = ":",
				category = "data",
				lang = "json",
				filetypes = { "json", "jsonc" },
			},
		})

		-- ── Set default filetype mappings ────────────────────────────
		align_registry.set_ft_mapping("json", "json_pairs")
		align_registry.set_ft_mapping("jsonc", "json_pairs")
		align_registry.mark_language_loaded("json")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map(json_fts, { "n", "x" }, "<leader>aL", align_registry.make_align_fn("json_pairs"), {
			desc = json_align_icon .. "  Align JSON pairs",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the JSON-specific
-- parts (servers, formatters, parsers, schemas).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for JSON                   │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (jsonls server added on require)  │
-- │ SchemaStore.nvim   │ lazy = true (loaded when jsonls starts)      │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.json)           │
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: JSON has no DAP or linter configured — jsonls provides
-- built-in validation, and prettier handles all formatting.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for JSON
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- jsonls: Microsoft's JSON Language Server.
	-- Provides validation, completion, hover, and formatting.
	--
	-- SchemaStore integration:
	--   • on_new_config hook injects 4000+ schemas from schemastore.org
	--   • Schemas are matched by filename (package.json, tsconfig, etc.)
	--   • Enables auto-completion of known fields with documentation
	--   • Real-time validation against the matched schema
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			"b0o/SchemaStore.nvim",
		},
		opts = {
			servers = {
				jsonls = {
					on_new_config = function(new_config)
						new_config.settings = new_config.settings or {}
						new_config.settings.json = new_config.settings.json or {}
						new_config.settings.json.schemas = new_config.settings.json.schemas or {}
						vim.list_extend(new_config.settings.json.schemas, require("schemastore").json.schemas())
					end,
					settings = {
						json = {
							validate = { enable = true },
							format = { enable = true },
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					json = "json",
					jsonc = "jsonc",
					json5 = "jsonc",
				},
				filename = {
					[".babelrc"] = "json",
					[".eslintrc"] = "json",
					[".prettierrc"] = "json",
					[".stylelintrc"] = "json",
					["tsconfig.json"] = "jsonc",
					["jsconfig.json"] = "jsonc",
					["launch.json"] = "jsonc",
					["settings.json"] = "jsonc",
					[".vscode/settings.json"] = "jsonc",
				},
				pattern = {
					--- Auto-detect JSONC by scanning first 5 lines for comments.
					---
					--- JSON files with `//` or `/* ... */` comments are re-classified
					--- as `jsonc` to enable proper highlighting and suppress
					--- "unexpected token" diagnostics from jsonls.
					---
					---@param path string File path
					---@param bufnr integer Buffer number
					---@return string|nil filetype `"jsonc"` if comments detected, `nil` otherwise
					["%.json[c5]?$"] = function(path, bufnr)
						local content = vim.api.nvim_buf_get_lines(bufnr, 0, 5, false)
						for _, line in ipairs(content) do
							if line:match("^%s*//") or line:match("^%s*/%*") then
								return "jsonc"
							end
						end
					end,
				},
			})

			-- ── Buffer-local options for JSON files ──────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "json", "jsonc" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.conceallevel = 0
					opt.colorcolumn = ""
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true
					opt.number = true
					opt.relativenumber = true
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures JSON tooling is installed via Mason:
	--   • json-lsp   — Microsoft JSON Language Server
	--   • prettier   — opinionated code formatter (JSON, JSONC, JSON5)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"json-lsp",
				"prettier",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- prettier: handles JSON formatting with consistent indentation,
	-- trailing commas (where valid), and key ordering. Used for both
	-- json and jsonc filetypes.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				json = { "prettier" },
				jsonc = { "prettier" },
			},
		},
	},

	-- ── SCHEMASTORE ────────────────────────────────────────────────────────
	-- Provides 4000+ JSON schemas from schemastore.org.
	-- Loaded lazily — only required when jsonls starts and calls
	-- the on_new_config hook to inject schemas.
	--
	-- version = false: always use latest (schemas update frequently)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"b0o/SchemaStore.nvim",
		lazy = true,
		version = false,
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- json:   syntax highlighting, folding, text objects, path extraction
	-- json5:  JSON5 superset (trailing commas, comments, unquoted keys)
	-- jsonc:  JSON with Comments (tsconfig, VS Code settings, etc.)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"json",
				"json5",
				"jsonc",
			},
		},
	},
}
