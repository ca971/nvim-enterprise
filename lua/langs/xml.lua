---@file lua/langs/xml.lua
---@description XML — LSP, formatter, linter, treesitter & buffer-local keymaps
---@module "langs.xml"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.html               HTML language support (related markup)
---@see langs.json               JSON language support (conversion target)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/xml.lua — XML language support                                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("xml") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "xml"):                      │    ║
--- ║  │  ├─ LSP          lemminx      (Eclipse XML Language Server)      │    ║
--- ║  │  ├─ Formatter    xmllint      (libxml2 format / pretty-print)    │    ║
--- ║  │  ├─ Linter       lemminx      (via LSP diagnostics)              │    ║
--- ║  │  ├─ Treesitter   xml · dtd    parsers                            │    ║
--- ║  │  └─ DAP          —            (N/A for XML)                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ VALIDATE  r  Validate (xmllint)     s  Schema/DTD validate   │    ║
--- ║  │  ├─ FORMAT    p  Pretty-print            m  Minify               │    ║
--- ║  │  ├─ XPATH     x  XPath query                                     │    ║
--- ║  │  ├─ CONVERT   j  Convert to JSON (xq/yq)                         │    ║
--- ║  │  ├─ NAVIGATE  t  Jump to matching tag                            │    ║
--- ║  │  ├─ EDIT      w  Wrap in tag (n/v)       e  Encode entities(n/v) │    ║
--- ║  │  │            d  Decode entities (n/v)                           │    ║
--- ║  │  ├─ FOLD      f  Toggle fold level                               │    ║
--- ║  │  └─ DOCS      i  Document stats          h  XML reference        │    ║
--- ║  │                                                                  │    ║
--- ║  │  Schema validation flow:                                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. User selects validation mode via vim.ui.select()     │    │    ║
--- ║  │  │     • XSD Schema   → xmllint --schema <path>             │    │    ║
--- ║  │  │     • DTD           → xmllint --dtdvalid <path>          │    │    ║
--- ║  │  │     • RelaxNG       → xmllint --relaxng <path>           │    │    ║
--- ║  │  │     • Auto          → xmllint --valid (embedded DOCTYPE) │    │    ║
--- ║  │  │  2. Prompted for schema path (except Auto mode)          │    │    ║
--- ║  │  │  3. Results displayed in terminal split                  │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType xml):                               ║
--- ║  • colorcolumn=120, textwidth=120  (XML tends toward wider lines)        ║
--- ║  • tabstop=2, shiftwidth=2         (standard XML indentation)            ║
--- ║  • expandtab=true                  (spaces, never tabs)                  ║
--- ║  • conceallevel=0                  (show all characters verbatim)        ║
--- ║  • commentstring=<!-- %s -->        (XML comment format)                 ║
--- ║  • Treesitter folding              (foldmethod=expr, foldlevel=99)       ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .xsd, .xsl, .xslt, .wsdl, .pom → xml                                  ║
--- ║  • *.csproj, *.fsproj, *.props, *.targets, *.nuspec → xml                ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if XML support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("xml") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string XML Nerd Font icon (trailing whitespace stripped)
local xml_icon = icons.lang.xml:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for XML buffers.
-- The group is buffer-local and only visible when filetype == "xml".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("xml", "XML", xml_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Check that `xmllint` is available on the system.
---
--- Notifies the user with platform-specific install instructions if
--- the binary is not found. Used as a guard in all keymaps that
--- depend on `xmllint` (validate, format, minify, xpath).
---
--- ```lua
--- if not check_xmllint() then return end
--- vim.fn.system("xmllint --format " .. file)
--- ```
---
---@return boolean available `true` if `xmllint` is executable
---@private
local function check_xmllint()
	if vim.fn.executable("xmllint") == 1 then return true end
	vim.notify(
		"Install xmllint:\n  macOS: brew install libxml2\n  Debian/Ubuntu: apt install libxml2-utils",
		vim.log.levels.WARN,
		{ title = "XML" }
	)
	return false
end

--- Encode raw text into XML entities.
---
--- Replaces the five predefined XML entities. `&` **must** be encoded
--- first to prevent double-encoding of already-encoded entities.
---
--- ```lua
--- xml_encode('a < b & c > d')   -- → "a &lt; b &amp; c &gt; d"
--- xml_encode('"hello"')         -- → "&quot;hello&quot;"
--- ```
---
---@param text string Raw text to encode
---@return string encoded Text with XML entities escaped
---@private
local function xml_encode(text)
	return text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;")
end

--- Decode XML entities back into raw text.
---
--- Replaces the five predefined XML entities. `&amp;` **must** be
--- decoded last to prevent corruption of partially-decoded sequences.
---
--- ```lua
--- xml_decode("a &lt; b &amp; c")   -- → "a < b & c"
--- xml_decode("&quot;hello&quot;")   -- → '"hello"'
--- ```
---
---@param text string Text with XML entities
---@return string decoded Text with entities resolved to raw characters
---@private
local function xml_decode(text)
	return text:gsub("&apos;", "'"):gsub("&quot;", '"'):gsub("&gt;", ">"):gsub("&lt;", "<"):gsub("&amp;", "&")
end

--- Display `xmllint` output in a read-only scratch split.
---
--- Creates a new scratch buffer, populates it with the output lines,
--- and opens it in a horizontal split. Used by validation keymaps to
--- show error details.
---
--- ```lua
--- show_xmllint_output("line 3: parser error: ...")
--- ```
---
---@param output string Raw output from `xmllint`
---@return nil
---@private
local function show_xmllint_output(output)
	vim.cmd.split()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(output, "\n"))
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_win_set_buf(0, buf)
end

--- Replace the current buffer contents with `xmllint` output.
---
--- Splits the output into lines, strips the trailing empty line that
--- `xmllint` appends, and replaces all buffer lines atomically.
---
--- ```lua
--- local result = vim.fn.system("xmllint --format " .. file)
--- replace_buffer_with(result)
--- ```
---
---@param output string Formatted/minified XML output
---@return nil
---@private
local function replace_buffer_with(output)
	local lines = vim.split(output, "\n")
	-- Remove trailing empty line added by xmllint
	if lines[#lines] == "" then lines[#lines] = nil end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

--- Open text in a read-only scratch split with a given filetype.
---
--- Creates a new scratch buffer, sets the filetype for highlighting,
--- and opens it in the specified split direction.
---
--- ```lua
--- open_scratch_split(json_text, "json", "vsplit")
--- open_scratch_split(xml_text, "xml", "split")
--- ```
---
---@param content string Text content for the scratch buffer
---@param ft string Filetype to set on the buffer (for syntax highlighting)
---@param split_cmd? string Split command (`"split"` or `"vsplit"`, default `"split"`)
---@return nil
---@private
local function open_scratch_split(content, ft, split_cmd)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
	vim.api.nvim_set_option_value("filetype", ft, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.cmd(split_cmd or "split")
	vim.api.nvim_win_set_buf(0, buf)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — VALIDATE
--
-- XML well-formedness and schema validation via xmllint.
-- Supports XSD, DTD, RelaxNG, and auto-detection from embedded DOCTYPE.
-- ═══════════════════════════════════════════════════════════════════════════

--- Validate well-formedness with `xmllint --noout`.
---
--- Saves the buffer before validation. On success, shows a confirmation
--- notification. On failure, opens the error output in a read-only
--- scratch split for inspection.
keys.lang_map("xml", "n", "<leader>lr", function()
	if not check_xmllint() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("xmllint --noout " .. vim.fn.shellescape(file) .. " 2>&1")
	if vim.v.shell_error == 0 then
		vim.notify("✓ Well-formed XML", vim.log.levels.INFO, { title = "XML" })
	else
		show_xmllint_output(result)
	end
end, { desc = icons.ui.Check .. " Validate (xmllint)" })

--- Validate against a schema (XSD), DTD, or RelaxNG.
---
--- Presents a `vim.ui.select()` menu with four validation modes:
--- 1. **XSD Schema**  → `xmllint --schema <path>` (prompts for `.xsd` file)
--- 2. **DTD**         → `xmllint --dtdvalid <path>` (prompts for DTD file)
--- 3. **RelaxNG**     → `xmllint --relaxng <path>` (prompts for `.rng` file)
--- 4. **Auto**        → `xmllint --valid` (uses embedded DOCTYPE/xsi)
---
--- Modes 1–3 prompt for a file path with completion; mode 4 runs
--- immediately. Results are displayed in a terminal split.
keys.lang_map("xml", "n", "<leader>ls", function()
	if not check_xmllint() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")

	---@class XmlValidationMode
	---@field name string Display label for the validation mode
	---@field flag string xmllint CLI flag
	---@field prompt? string Input prompt for schema path (`nil` for auto mode)

	---@type XmlValidationMode[]
	local modes = {
		{ name = "XSD Schema", flag = "--schema", prompt = "Schema (.xsd) path: " },
		{ name = "DTD", flag = "--dtdvalid", prompt = "DTD path: " },
		{ name = "RelaxNG", flag = "--relaxng", prompt = "RelaxNG (.rng) path: " },
		{ name = "Auto (embedded DOCTYPE/xsi)", flag = "--valid", prompt = nil },
	}

	vim.ui.select(
		vim.tbl_map(function(m)
			return m.name
		end, modes),
		{ prompt = xml_icon .. " Validation mode:" },
		function(_, idx)
			if not idx then return end
			local mode = modes[idx]

			--- Run xmllint validation with the given flag arguments.
			---@param flag_args string CLI flags and schema path
			local function run_validation(flag_args)
				local cmd = "xmllint --noout " .. flag_args .. " " .. vim.fn.shellescape(file) .. " 2>&1"
				vim.cmd.split()
				vim.cmd.terminal(cmd)
			end

			if mode.prompt then
				vim.ui.input({ prompt = mode.prompt, completion = "file" }, function(schema)
					if not schema or schema == "" then return end
					run_validation(mode.flag .. " " .. vim.fn.shellescape(schema))
				end)
			else
				run_validation(mode.flag)
			end
		end
	)
end, { desc = icons.ui.Check .. " Schema validate" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FORMAT
--
-- XML pretty-printing and minification via xmllint.
-- Replaces the buffer content in-place.
-- ═══════════════════════════════════════════════════════════════════════════

--- Pretty-print (reindent) the current file with `xmllint --format`.
---
--- Saves the buffer before formatting. Replaces all buffer lines with
--- the formatted output. Notifies on success or displays the error
--- message on failure.
keys.lang_map("xml", "n", "<leader>lp", function()
	if not check_xmllint() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("xmllint --format " .. vim.fn.shellescape(file) .. " 2>&1")
	if vim.v.shell_error == 0 then
		replace_buffer_with(result)
		vim.notify("Pretty-printed", vim.log.levels.INFO, { title = "XML" })
	else
		vim.notify("xmllint error:\n" .. result, vim.log.levels.ERROR, { title = "XML" })
	end
end, { desc = xml_icon .. " Pretty-print" })

--- Minify: remove indentation and collapse whitespace.
---
--- Runs `xmllint --noblanks` to strip all insignificant whitespace,
--- producing a compact single-line (or near-single-line) output.
--- Saves the buffer before minifying.
keys.lang_map("xml", "n", "<leader>lm", function()
	if not check_xmllint() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local result = vim.fn.system("xmllint --noblanks " .. vim.fn.shellescape(file) .. " 2>&1")
	if vim.v.shell_error == 0 then
		replace_buffer_with(result)
		vim.notify("Minified", vim.log.levels.INFO, { title = "XML" })
	else
		vim.notify("xmllint error:\n" .. result, vim.log.levels.ERROR, { title = "XML" })
	end
end, { desc = xml_icon .. " Minify" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — XPATH
--
-- XPath query execution via xmllint. Results are displayed in a
-- read-only scratch split with XML syntax highlighting.
-- ═══════════════════════════════════════════════════════════════════════════

--- Run an XPath query on the current file and display results.
---
--- Prompts for an XPath expression (default `//`), executes it via
--- `xmllint --xpath`, and displays matching nodes in a read-only
--- scratch split. The scratch buffer uses `xml` filetype for
--- syntax highlighting.
keys.lang_map("xml", "n", "<leader>lx", function()
	if not check_xmllint() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.ui.input({ prompt = "XPath expression: ", default = "//" }, function(xpath)
		if not xpath or xpath == "" then return end
		local result =
			vim.fn.system("xmllint --xpath " .. vim.fn.shellescape(xpath) .. " " .. vim.fn.shellescape(file) .. " 2>&1")
		if vim.v.shell_error ~= 0 then
			vim.notify("XPath error:\n" .. result, vim.log.levels.ERROR, { title = "XML" })
			return
		end
		open_scratch_split(result, "xml", "split")
	end)
end, { desc = icons.ui.Search .. " XPath query" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CONVERSION
--
-- XML-to-JSON conversion using xq (Python yq) or yq (Go).
-- Output is displayed in a vertical scratch split with JSON highlighting.
-- ═══════════════════════════════════════════════════════════════════════════

--- Convert the current XML file to JSON.
---
--- Auto-detects the available converter:
--- - `xq` (Python yq package) → `xq . <file>`
--- - `yq` (Go version)        → `yq -p=xml -o=json <file>`
---
--- Opens the JSON output in a vertical scratch split with `json`
--- filetype for syntax highlighting.
keys.lang_map("xml", "n", "<leader>lj", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")

	---@type string|nil
	local cmd
	if vim.fn.executable("xq") == 1 then
		-- Python yq: xq reads XML from stdin / file
		cmd = "xq . " .. vim.fn.shellescape(file)
	elseif vim.fn.executable("yq") == 1 then
		-- Go yq with explicit XML input
		cmd = "yq -p=xml -o=json " .. vim.fn.shellescape(file)
	else
		vim.notify(
			"Install one of:\n  pip install yq   (provides xq)\n  brew install yq   (Go version)",
			vim.log.levels.WARN,
			{ title = "XML" }
		)
		return
	end

	local result = vim.fn.system(cmd .. " 2>&1")
	if vim.v.shell_error ~= 0 then
		vim.notify("Conversion error:\n" .. result, vim.log.levels.ERROR, { title = "XML" })
		return
	end

	open_scratch_split(result, "json", "vsplit")
end, { desc = icons.file.Json .. " Convert to JSON" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — NAVIGATION
--
-- Tag-aware navigation using searchpair() for correct handling of
-- nested XML elements.
-- ═══════════════════════════════════════════════════════════════════════════

--- Jump to the matching open / close tag on the current line.
---
--- Detection logic:
--- 1. If a **closing tag** (`</tag>`) is found → search backward for
---    the matching opening tag using `searchpair()`.
--- 2. If an **opening tag** (`<tag ...>`) is found → skip self-closing
---    tags (`<tag/>`), then search forward for the matching closing tag.
--- 3. If no tag is found → notify the user.
---
--- Uses `searchpair()` for correct handling of nested tags with the
--- same name.
keys.lang_map("xml", "n", "<leader>lt", function()
	local line = vim.api.nvim_get_current_line()

	-- ── Detect closing tag: </tagname> ───────────────────────────
	local close_tag = line:match("</([%w:%-%.]+)%s*>")
	if close_tag then
		local escaped = vim.fn.escape(close_tag, "\\")
		local found = vim.fn.searchpair("<" .. escaped .. "\\>", "", "</" .. escaped .. "\\s*>", "bW")
		if found == 0 then
			vim.notify("Opening tag not found: <" .. close_tag .. ">", vim.log.levels.WARN, { title = "XML" })
		end
		return
	end

	-- ── Detect opening tag: <tagname ...> (not self-closing) ─────
	local open_tag = line:match("<([%w:%-%.]+)[%s>]")
	if not open_tag then open_tag = line:match("<([%w:%-%.]+)$") end
	if open_tag then
		-- Skip self-closing tags
		if line:match("<" .. vim.pesc(open_tag) .. "[^>]*/>") then
			vim.notify("Self-closing tag: <" .. open_tag .. "/>", vim.log.levels.INFO, { title = "XML" })
			return
		end
		local escaped = vim.fn.escape(open_tag, "\\")
		local found = vim.fn.searchpair("<" .. escaped .. "\\>", "", "</" .. escaped .. "\\s*>", "W")
		if found == 0 then
			vim.notify("Closing tag not found: </" .. open_tag .. ">", vim.log.levels.WARN, { title = "XML" })
		end
		return
	end

	vim.notify("No tag found on current line", vim.log.levels.INFO, { title = "XML" })
end, { desc = icons.ui.ArrowRight .. " Jump to matching tag" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — EDITING (WRAP IN TAG)
--
-- Wrap current line or visual selection inside an XML element.
-- Prompts for a tag name and strips attributes for the closing tag.
-- ═══════════════════════════════════════════════════════════════════════════

--- Wrap the current line's content in an XML tag.
---
--- Prompts for a tag name (may include attributes, e.g. `div class="x"`).
--- The closing tag uses only the element name (attributes stripped).
--- Preserves the original line indentation.
keys.lang_map("xml", "n", "<leader>lw", function()
	vim.ui.input({ prompt = "Tag name: " }, function(tag)
		if not tag or tag == "" then return end
		local tag_name = tag:match("^([%w:%-%.]+)")
		local line = vim.api.nvim_get_current_line()
		local indent = line:match("^(%s*)")
		local content = line:gsub("^%s+", ""):gsub("%s+$", "")
		vim.api.nvim_set_current_line(string.format("%s<%s>%s</%s>", indent, tag, content, tag_name))
	end)
end, { desc = xml_icon .. " Wrap in tag" })

--- Wrap the visual selection in an XML tag.
---
--- Prompts for a tag name. The selected lines are indented by two
--- additional spaces inside the new element. The opening and closing
--- tags inherit the indentation of the first selected line.
keys.lang_map("xml", "v", "<leader>lw", function()
	vim.ui.input({ prompt = "Tag name: " }, function(tag)
		if not tag or tag == "" then return end
		local tag_name = tag:match("^([%w:%-%.]+)")

		-- Get visual selection range
		local start_row = vim.fn.line("'<") - 1
		local end_row = vim.fn.line("'>")
		local lines = vim.api.nvim_buf_get_lines(0, start_row, end_row, false)
		if #lines == 0 then return end

		-- Detect indentation from first selected line
		local indent = lines[1]:match("^(%s*)") or ""
		local inner_indent = indent .. "  "

		-- Build wrapped lines
		---@type string[]
		local result = { indent .. "<" .. tag .. ">" }
		for _, l in ipairs(lines) do
			result[#result + 1] = inner_indent .. l:gsub("^%s+", "")
		end
		result[#result + 1] = indent .. "</" .. tag_name .. ">"

		vim.api.nvim_buf_set_lines(0, start_row, end_row, false, result)
	end)
end, { desc = xml_icon .. " Wrap selection in tag" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — EDITING (ENTITIES)
--
-- XML entity encoding / decoding for both normal and visual mode.
-- Handles the five predefined XML entities: & < > " '
-- ═══════════════════════════════════════════════════════════════════════════

--- Encode XML entities on the current line.
---
--- Replaces `& < > " '` with their XML entity equivalents.
--- Notifies whether any replacements were made.
keys.lang_map("xml", "n", "<leader>le", function()
	local line = vim.api.nvim_get_current_line()
	local encoded = xml_encode(line)
	if encoded ~= line then
		vim.api.nvim_set_current_line(encoded)
		vim.notify("Entities encoded", vim.log.levels.INFO, { title = "XML" })
	else
		vim.notify("Nothing to encode", vim.log.levels.INFO, { title = "XML" })
	end
end, { desc = xml_icon .. " Encode entities" })

--- Decode XML entities on the current line.
---
--- Replaces `&amp; &lt; &gt; &quot; &apos;` with their raw character
--- equivalents. Notifies whether any replacements were made.
keys.lang_map("xml", "n", "<leader>ld", function()
	local line = vim.api.nvim_get_current_line()
	local decoded = xml_decode(line)
	if decoded ~= line then
		vim.api.nvim_set_current_line(decoded)
		vim.notify("Entities decoded", vim.log.levels.INFO, { title = "XML" })
	else
		vim.notify("Nothing to decode", vim.log.levels.INFO, { title = "XML" })
	end
end, { desc = xml_icon .. " Decode entities" })

--- Encode XML entities in the visual selection.
---
--- Yanks the selection into register `z`, encodes, and replaces
--- the selection in-place.
keys.lang_map("xml", "v", "<leader>le", function()
	vim.cmd('noautocmd normal! "zy')
	local text = vim.fn.getreg("z")
	local encoded = xml_encode(text)
	if encoded ~= text then
		vim.fn.setreg("z", encoded)
		vim.cmd('noautocmd normal! gv"zp')
		vim.notify("Entities encoded", vim.log.levels.INFO, { title = "XML" })
	end
end, { desc = xml_icon .. " Encode entities" })

--- Decode XML entities in the visual selection.
---
--- Yanks the selection into register `z`, decodes, and replaces
--- the selection in-place.
keys.lang_map("xml", "v", "<leader>ld", function()
	vim.cmd('noautocmd normal! "zy')
	local text = vim.fn.getreg("z")
	local decoded = xml_decode(text)
	if decoded ~= text then
		vim.fn.setreg("z", decoded)
		vim.cmd('noautocmd normal! gv"zp')
		vim.notify("Entities decoded", vim.log.levels.INFO, { title = "XML" })
	end
end, { desc = xml_icon .. " Decode entities" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FOLD
--
-- Quick fold level toggling for navigating deeply nested XML trees.
-- ═══════════════════════════════════════════════════════════════════════════

--- Cycle fold level: collapse all ↔ expand all.
---
--- If the current fold level is > 0 (some folds open) → collapse all
--- with `zM`. Otherwise → expand all with `zR`. Notifies the new
--- fold state.
keys.lang_map("xml", "n", "<leader>lf", function()
	local current = vim.wo.foldlevel
	if current > 0 then
		vim.cmd("normal! zM")
		vim.notify("Folds: all collapsed", vim.log.levels.INFO, { title = "XML" })
	else
		vim.cmd("normal! zR")
		vim.notify("Folds: all expanded", vim.log.levels.INFO, { title = "XML" })
	end
end, { desc = xml_icon .. " Toggle fold level" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Document statistics and external reference documentation.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show comprehensive document statistics.
---
--- Analyses the buffer content and reports:
--- - Line count and character count
--- - Element count (including self-closing)
--- - Attribute count
--- - Maximum nesting depth
--- - Comment, CDATA, and processing instruction counts
--- - Namespace count with prefix listing
---
--- The analysis is regex-based (not a full XML parser) and handles
--- multi-line comments correctly via an `in_comment` state tracker.
keys.lang_map("xml", "n", "<leader>li", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local content = table.concat(lines, "\n")

	---@type integer
	local elements = 0
	---@type integer
	local self_closing = 0
	---@type integer
	local attributes = 0
	---@type integer
	local comments = 0
	---@type integer
	local cdata = 0
	---@type integer
	local pis = 0
	---@type table<string, boolean>
	local namespaces = {}
	---@type integer
	local max_depth = 0
	---@type integer
	local depth = 0
	---@type boolean
	local in_comment = false

	for _, line in ipairs(lines) do
		-- ── Track multi-line comments ────────────────────────────
		if line:match("<!%-%-") then
			in_comment = true
			comments = comments + 1
		end
		if line:match("%-%->") then in_comment = false end
		if in_comment then goto continue end

		-- ── Self-closing tags: <tag/> ────────────────────────────
		for _ in line:gmatch("<[%w:%-%.]+[^>]*/>") do
			self_closing = self_closing + 1
			elements = elements + 1
		end

		-- ── Opening tags (exclude self-closing, PIs, declarations)
		for tag in line:gmatch("<([%w:%-%.]+)[%s>]") do
			if not line:match("<" .. vim.pesc(tag) .. "[^>]*/>") then
				elements = elements + 1
				depth = depth + 1
				if depth > max_depth then max_depth = depth end
			end
		end

		-- ── Closing tags ─────────────────────────────────────────
		for _ in line:gmatch("</[%w:%-%.]+%s*>") do
			depth = depth - 1
		end

		-- ── Attributes ───────────────────────────────────────────
		for _ in line:gmatch("[%w:%-%.]+%s*=") do
			attributes = attributes + 1
		end

		-- ── CDATA sections ───────────────────────────────────────
		for _ in line:gmatch("<!%[CDATA%[") do
			cdata = cdata + 1
		end

		-- ── Processing instructions ──────────────────────────────
		for _ in line:gmatch("<%?[%w]+") do
			pis = pis + 1
		end

		-- ── Namespaces ───────────────────────────────────────────
		for ns in line:gmatch("xmlns:([%w%-]+)%s*=") do
			namespaces[ns] = true
		end
		if line:match("xmlns%s*=") then namespaces["(default)"] = true end

		::continue::
	end

	-- ── Format namespace list ────────────────────────────────────
	local ns_count = vim.tbl_count(namespaces)
	---@type string
	local ns_list = ""
	if ns_count > 0 then
		local ns_names = vim.tbl_keys(namespaces)
		table.sort(ns_names)
		ns_list = "\n  Prefixes:      " .. table.concat(ns_names, ", ")
	end

	local stats = string.format(
		"%s Document Stats:\n"
			.. "  Lines:         %d\n"
			.. "  Characters:    %d\n"
			.. "  ─────────────────\n"
			.. "  Elements:      %d (self-closing: %d)\n"
			.. "  Attributes:    %d\n"
			.. "  Max depth:     %d\n"
			.. "  Comments:      %d\n"
			.. "  CDATA:         %d\n"
			.. "  PIs:           %d\n"
			.. "  Namespaces:    %d%s",
		xml_icon,
		#lines,
		#content,
		elements,
		self_closing,
		attributes,
		max_depth,
		comments,
		cdata,
		pis,
		ns_count,
		ns_list
	)
	vim.notify(stats, vim.log.levels.INFO, { title = "XML" })
end, { desc = icons.diagnostics.Info .. " Document stats" })

--- Open XML / XPath / XSLT reference documentation in the browser.
---
--- Presents a `vim.ui.select()` menu with links to:
--- - XML Introduction (MDN)
--- - XPath Reference (MDN)
--- - XSLT Reference (MDN)
--- - XML Schema (W3Schools)
--- - XML Specification (W3C)
keys.lang_map("xml", "n", "<leader>lh", function()
	---@class XmlDocRef
	---@field name string Display label for the documentation link
	---@field url string URL to open in the browser

	---@type XmlDocRef[]
	local refs = {
		{ name = "XML Reference (MDN)", url = "https://developer.mozilla.org/en-US/docs/Web/XML/XML_introduction" },
		{ name = "XPath Reference", url = "https://developer.mozilla.org/en-US/docs/Web/XPath" },
		{ name = "XSLT Reference", url = "https://developer.mozilla.org/en-US/docs/Web/XSLT" },
		{ name = "XML Schema (W3Schools)", url = "https://www.w3schools.com/xml/schema_intro.asp" },
		{ name = "XML Spec (W3C)", url = "https://www.w3.org/TR/xml/" },
	}
	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = xml_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " XML reference" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers XML-specific alignment presets for mini.align:
-- • xml_attributes — align XML attributes on "="
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("xml") then
		---@type string Alignment preset icon from icons.file
		local xml_align_icon = icons.file.Xml

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			xml_attributes = {
				description = "Align XML attributes on '='",
				icon = xml_align_icon,
				split_pattern = "=",
				category = "data",
				lang = "xml",
				filetypes = { "xml" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("xml", "xml_attributes")
		align_registry.mark_language_loaded("xml")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("xml", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("xml_attributes"), {
			desc = xml_align_icon .. "  Align XML attrs",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the XML-specific
-- parts (servers, formatters, parsers).
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin             │ How it lazy-loads for XML                     │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-lspconfig     │ opts merge (lemminx server added on require) │
-- │ mason.nvim         │ opts merge (tools added to ensure_installed) │
-- │ conform.nvim       │ opts merge (formatters_by_ft.xml/xsd/xsl/svg)│
-- │ nvim-treesitter    │ opts merge (parsers added to ensure_installed│
-- └────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: No separate linter spec — lemminx provides real-time
-- diagnostics via LSP (validation, schema errors, well-formedness).
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for XML
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- lemminx: Eclipse XML Language Server
	-- Provides completions, diagnostics, schema validation (XSD/DTD/RNG),
	-- code actions, hover, go-to-definition, and format capabilities.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				lemminx = {
					settings = {
						xml = {
							catalogs = {},
							validation = {
								enabled = true,
								noGrammar = "hint",
								schema = { enabled = "always" },
							},
							format = {
								enabled = true,
								splitAttributes = false,
								joinCDATALines = false,
								joinContentLines = false,
								joinCommentLines = false,
								spaceBeforeEmptyCloseTag = true,
							},
							completion = {
								autoCloseTags = true,
							},
							codeLens = {
								enabled = true,
							},
						},
					},
				},
			},
		},
		init = function()
			-- ── Filetype extensions ──────────────────────────────────
			vim.filetype.add({
				extension = {
					xsd = "xml",
					xsl = "xml",
					xslt = "xml",
					wsdl = "xml",
					pom = "xml",
				},
				pattern = {
					[".*%.csproj$"] = "xml",
					[".*%.fsproj$"] = "xml",
					[".*%.props$"] = "xml",
					[".*%.targets$"] = "xml",
					[".*%.nuspec$"] = "xml",
				},
			})

			-- ── Buffer-local options for XML files ───────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "xml" },
				callback = function()
					local opt = vim.opt_local
					opt.wrap = false
					opt.colorcolumn = "120"
					opt.textwidth = 120
					opt.conceallevel = 0
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true
					opt.number = true
					opt.relativenumber = true
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99
					opt.commentstring = "<!-- %s -->"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Ensures lemminx is installed via Mason. xmllint is expected to
	-- be available system-wide (libxml2-utils / libxml2).
	-- ───────────────────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"lemminx",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- xmllint: libxml2 format utility for XML, XSD, XSL, and SVG files.
	-- Used for both pretty-printing (--format) and minification
	-- (--noblanks). Also serves as the conform.nvim formatter.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = {
			formatters_by_ft = {
				xml = { "xmllint" },
				xsd = { "xmllint" },
				xsl = { "xmllint" },
				svg = { "xmllint" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- xml: syntax highlighting, folding, text objects
	-- dtd: Document Type Definition highlighting
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"xml",
				"dtd",
			},
		},
	},
}
