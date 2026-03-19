---@file lua/langs/markdown.lua
---@description Markdown — LSP (marksman), formatter, linter, treesitter, preview & buffer-local keymaps
---@module "langs.markdown"
---@author ca971
---@license MIT
---@version 1.1.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see core.mini-align-registry Alignment preset registration system
---@see langs.json               JSON language support (shared prettier)
---@see langs.yaml               YAML language support (frontmatter)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/markdown.lua — Markdown language support                          ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("markdown") → {} if off     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = "markdown"):                 │    ║
--- ║  │  ├─ LSP          marksman (cross-reference, completion)          │    ║
--- ║  │  ├─ Formatter    prettier + markdownlint-cli2 + markdown-toc     │    ║
--- ║  │  ├─ Linter       markdownlint-cli2 (nvim-lint)                   │    ║
--- ║  │  ├─ Treesitter   markdown · markdown_inline · html · latex       │    ║
--- ║  │  │               yaml · toml · mermaid parsers                   │    ║
--- ║  │  └─ Extras       render-markdown · obsidian · markdown-preview   │    ║
--- ║  │                  mkdnflow · vim-table-mode · img-clip            │    ║
--- ║  │                  headlines · nvim-toc · follow-md-links          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ PREVIEW   P  Browser (grip)        W  Live browser preview   │    ║
--- ║  │  │            R  Toggle render-markdown                          │    ║
--- ║  │  ├─ TOC       t  Navigate TOC           T  Insert TOC            │    ║
--- ║  │  │            G  Generate TOC (plugin)                           │    ║
--- ║  │  ├─ HEADING   +  Increase level         -  Decrease level        │    ║
--- ║  │  ├─ LINK      l  Insert link            I  Insert image          │    ║
--- ║  │  │            v  Paste image (clipboard) o  Follow link          │    ║
--- ║  │  ├─ TABLE     b  Insert table           M  Toggle table mode     │    ║
--- ║  │  │            a  Realign table                                   │    ║
--- ║  │  ├─ EDIT      x  Toggle checkbox        c  Insert code block     │    ║
--- ║  │  ├─ EXPORT    e  Export (pandoc)                                 │    ║
--- ║  │  ├─ DOCS      i  Document stats         h  Markdown cheat sheet  │    ║
--- ║  │  ├─ OBSIDIAN  O  Obsidian actions picker                         │    ║
--- ║  │  └─ MKDNFLOW  m  → Mkdnflow sub-group                            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Visual mode keymaps (<leader>l prefix):                         │    ║
--- ║  │  ├─ FORMAT    b  Bold (**…**)           i  Italic (*…*)          │    ║
--- ║  │  │            c  Inline code (`…`)       s  Strikethrough (~~…~~)│    ║
--- ║  │  └─ TABLE     a  Tableize selection                              │    ║
--- ║  │                                                                  │    ║
--- ║  │  Plugin integration matrix:                                      │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  render-markdown.nvim  inline decoration (headings, etc) │    │    ║
--- ║  │  │  markdown-preview.nvim live browser preview (hot-reload) │    │    ║
--- ║  │  │  obsidian.nvim         vault management (cond: .obsidian │    │    ║
--- ║  │  │  mkdnflow.nvim         navigation, links, lists, tables  │    │    ║
--- ║  │  │  vim-table-mode        table creation and editing        │    │    ║
--- ║  │  │  img-clip.nvim         paste images from clipboard       │    │    ║
--- ║  │  │  headlines.nvim        heading backgrounds + hr rules    │    │    ║
--- ║  │  │  nvim-toc              auto-generate TOC                 │    │    ║
--- ║  │  │  follow-md-links.nvim  follow links with gf              │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType markdown + prose types):            ║
--- ║  • wrap=true, linebreak=true      (soft-wrap at word boundaries)         ║
--- ║  • conceallevel=2                 (hide markdown syntax)                 ║
--- ║  • textwidth=80, colorcolumn=80   (prose line length)                    ║
--- ║  • spell=true, spelllang=en_us    (spell checking enabled)               ║
--- ║  • formatoptions=tcroqnlj         (auto-format for prose)                ║
--- ║  • commentstring="<!-- %s -->"     (HTML comment syntax)                 ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • .md                → markdown                                         ║
--- ║  • .mdx               → markdown.mdx                                     ║
--- ║  • .rmd               → rmd                                              ║
--- ║  • README, CHANGELOG  → markdown (no extension)                          ║
--- ║  • .markdownlint.*    → json                                             ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Markdown support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("markdown") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Markdown Nerd Font icon (trailing whitespace stripped)
local md_icon = icons.lang.markdown:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
--
-- Registers the <leader>l group label for Markdown buffers.
-- The group is buffer-local and only visible when filetype == "markdown".
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("markdown", "Markdown", md_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Text insertion, selection wrapping, heading extraction, and TOC
-- generation utilities. All functions are module-local and not
-- exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Insert text at the cursor position on the current line.
---
--- Splices `text` into the current line at the cursor column,
--- preserving content before and after the cursor.
---
--- ```lua
--- insert_at_cursor("[example](https://example.com)")
--- ```
---
---@param text string Text to insert at cursor position
---@return nil
---@private
local function insert_at_cursor(text)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_get_current_line()
	local new_line = line:sub(1, col) .. text .. line:sub(col + 1)
	vim.api.nvim_buf_set_lines(0, row - 1, row, false, { new_line })
end

--- Wrap the visual selection with prefix and suffix strings.
---
--- Yanks the selection into register `z`, deletes it, inserts
--- `prefix .. suffix`, then pastes the yanked text between them.
---
--- ```lua
--- wrap_selection("**", "**")   -- Bold
--- wrap_selection("`", "`")     -- Inline code
--- ```
---
---@param prefix string Characters to insert before the selection
---@param suffix string Characters to insert after the selection
---@return nil
---@private
local function wrap_selection(prefix, suffix)
	vim.cmd('normal! "zdi' .. prefix .. suffix)
	vim.cmd("normal! " .. string.rep("h", #suffix - 1) .. '"zP')
end

--- Extract all headings from the current buffer.
---
--- Parses the buffer line by line, skipping fenced code blocks,
--- and extracts heading level, clean title text, and line number.
--- Strips inline formatting (bold, italic, code) and custom
--- anchors (`{#id}`) from heading text.
---
--- ```lua
--- local headings = extract_headings()
--- for _, h in ipairs(headings) do
---     print(h.level, h.title, h.lnum)
--- end
--- ```
---
---@return { level: integer, title: string, lnum: integer }[] headings List of heading entries
---@private
local function extract_headings()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	---@type { level: integer, title: string, lnum: integer }[]
	local headings = {}
	---@type boolean
	local in_code_block = false

	for i, line in ipairs(lines) do
		if line:match("^```") then in_code_block = not in_code_block end

		if not in_code_block then
			local level_str, title = line:match("^(#+)%s+(.+)$")
			if level_str and title then
				-- Strip inline formatting and trailing anchors
				local clean = title
					:gsub("%*%*(.-)%*%*", "%1") -- bold
					:gsub("__(.-)__", "%1") -- bold alt
					:gsub("%*(.-)%*", "%1") -- italic
					:gsub("_(.-)_", "%1") -- italic alt
					:gsub("`(.-)`", "%1") -- code
					:gsub("%s*{#.-}%s*$", "") -- custom anchors
					:gsub("%s+$", "") -- trailing whitespace

				headings[#headings + 1] = {
					level = #level_str,
					title = clean,
					lnum = i,
				}
			end
		end
	end

	return headings
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — PREVIEW
--
-- Multiple preview strategies for different workflows:
-- • grip: GitHub-flavored rendering in the browser (offline)
-- • markdown-preview.nvim: live browser preview with hot-reload
-- • render-markdown.nvim: inline decoration in the buffer
-- ═══════════════════════════════════════════════════════════════════════════

--- Preview in browser with grip (GitHub-flavored rendering).
---
--- Launches `grip` as a detached background process which serves
--- the markdown file on localhost and opens the system browser.
--- Requires `grip` to be installed (`pip install grip`).
keys.lang_map("markdown", "n", "<leader>lP", function()
	if vim.fn.executable("grip") ~= 1 then
		vim.notify("Install grip: pip install grip", vim.log.levels.WARN, { title = "Markdown" })
		return
	end
	local file = vim.fn.expand("%:p")
	vim.fn.jobstart({ "grip", file, "--browser" }, { detach = true })
	vim.notify("Opening in browser (grip)…", vim.log.levels.INFO, { title = "Markdown" })
end, { desc = icons.status.Remote .. " Preview (browser)" })

--- Toggle live browser preview with hot-reload.
---
--- Delegates to `markdown-preview.nvim` which starts a local
--- web server and opens the preview in the system browser.
--- Changes are reflected in real-time as you type.
keys.lang_map("markdown", "n", "<leader>lW", "<cmd>MarkdownPreviewToggle<cr>", {
	desc = icons.status.Remote .. " Browser preview (live)",
})

--- Toggle render-markdown inline decoration.
---
--- Enables/disables in-buffer rendering of headings, code blocks,
--- tables, checkboxes, links, and other markdown elements using
--- virtual text and extmarks.
keys.lang_map("markdown", "n", "<leader>lR", "<cmd>RenderMarkdown toggle<cr>", {
	desc = md_icon .. " Toggle render",
})

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TABLE OF CONTENTS
--
-- TOC generation and navigation using treesitter-parsed headings.
-- Supports both interactive navigation (vim.ui.select) and
-- inline insertion at cursor position.
-- ═══════════════════════════════════════════════════════════════════════════

--- Navigate the table of contents via `vim.ui.select`.
---
--- Extracts all headings from the buffer (skipping code blocks),
--- presents them in a hierarchical picker with indentation matching
--- heading depth, and jumps to the selected heading.
keys.lang_map("markdown", "n", "<leader>lt", function()
	local headings = extract_headings()

	if #headings == 0 then
		vim.notify("No headings found", vim.log.levels.INFO, { title = "Markdown" })
		return
	end

	---@type string[]
	local display = vim.tbl_map(function(h)
		local indent = string.rep("  ", h.level - 1)
		local prefix = string.rep("#", h.level)
		return string.format("%s%s %s (L%d)", indent, prefix, h.title, h.lnum)
	end, headings)

	vim.ui.select(display, { prompt = md_icon .. " Table of Contents:" }, function(_, idx)
		if idx then
			vim.api.nvim_win_set_cursor(0, { headings[idx].lnum, 0 })
			vim.cmd("normal! zz")
		end
	end)
end, { desc = icons.ui.List .. " Table of contents" })

--- Insert a table of contents at the cursor position.
---
--- Generates a markdown TOC with:
--- - `## Table of Contents` header
--- - Nested bullet list matching heading hierarchy (h2+ only, h1 skipped)
--- - GitHub-compatible anchor links (lowercase, hyphens, no special chars)
---
--- Inserts at the current cursor line and notifies with entry count.
keys.lang_map("markdown", "n", "<leader>lT", function()
	local headings = extract_headings()
	---@type string[]
	local toc_lines = { "## Table of Contents", "" }

	for _, h in ipairs(headings) do
		if h.level >= 2 then
			local anchor = h.title:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
			local indent = string.rep("  ", h.level - 2)
			toc_lines[#toc_lines + 1] = string.format("%s- [%s](#%s)", indent, h.title, anchor)
		end
	end

	toc_lines[#toc_lines + 1] = ""

	local row = vim.api.nvim_win_get_cursor(0)[1]
	vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, toc_lines)
	vim.notify(string.format("Inserted TOC (%d entries)", #toc_lines - 3), vim.log.levels.INFO, { title = "Markdown" })
end, { desc = icons.ui.List .. " Insert TOC" })

--- Generate or refresh table of contents via nvim-toc plugin.
---
--- Delegates to the `:TOC` command provided by `richardbizik/nvim-toc`.
keys.lang_map("markdown", "n", "<leader>lG", "<cmd>TOC<cr>", {
	desc = icons.ui.List .. " Generate TOC (plugin)",
})

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — HEADINGS
--
-- Increase and decrease heading levels (add/remove # prefix).
-- Respects the h1–h6 range and handles non-heading lines.
-- ═══════════════════════════════════════════════════════════════════════════

--- Increase heading level (add `#`).
---
--- Behavior:
--- - Heading lines: adds one `#` (up to h6 maximum)
--- - Non-heading lines: converts to h1 (`# <text>`)
keys.lang_map("markdown", "n", "<leader>l+", function()
	local line = vim.api.nvim_get_current_line()
	local level, rest = line:match("^(#+)(%s.+)$")
	if level and #level < 6 then
		vim.api.nvim_set_current_line("#" .. level .. rest)
	elseif not level then
		vim.api.nvim_set_current_line("# " .. line)
	end
end, { desc = md_icon .. " Increase heading level" })

--- Decrease heading level (remove `#`).
---
--- Behavior:
--- - h2–h6: removes one `#`
--- - h1: removes the `# ` prefix entirely (becomes plain text)
keys.lang_map("markdown", "n", "<leader>l-", function()
	local line = vim.api.nvim_get_current_line()
	local level, rest = line:match("^(#+)(%s.+)$")
	if level and #level > 1 then
		vim.api.nvim_set_current_line(level:sub(2) .. rest)
	elseif level and #level == 1 then
		vim.api.nvim_set_current_line(rest:sub(2))
	end
end, { desc = md_icon .. " Decrease heading level" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — LINKS / IMAGES
--
-- Markdown link and image insertion, clipboard image pasting,
-- and intelligent link following (URLs, anchors, relative files).
-- ═══════════════════════════════════════════════════════════════════════════

--- Insert a markdown link at cursor: `[text](url)`.
---
--- Prompts for link text and URL via `vim.ui.input()`, then
--- inserts the formatted link at the cursor position. Aborts
--- silently if either prompt is cancelled or empty.
keys.lang_map("markdown", "n", "<leader>ll", function()
	vim.ui.input({ prompt = "Link text: " }, function(text)
		if not text or text == "" then return end
		vim.ui.input({ prompt = "URL: " }, function(url)
			if not url or url == "" then return end
			insert_at_cursor(string.format("[%s](%s)", text, url))
		end)
	end)
end, { desc = icons.ui.ArrowRight .. " Insert link" })

--- Insert a markdown image at cursor: `![alt](path)`.
---
--- Prompts for alt text and image path/URL via `vim.ui.input()`.
--- The path prompt supports file completion. Aborts if path is empty.
keys.lang_map("markdown", "n", "<leader>lI", function()
	vim.ui.input({ prompt = "Alt text: " }, function(alt)
		if not alt then alt = "" end
		vim.ui.input({ prompt = "Image path/URL: ", completion = "file" }, function(path)
			if not path or path == "" then return end
			insert_at_cursor(string.format("![%s](%s)", alt, path))
		end)
	end)
end, { desc = icons.file.Image .. " Insert image" })

--- Paste image from system clipboard and insert markdown link.
---
--- Delegates to `img-clip.nvim` which saves the clipboard image
--- to `assets/images/` and inserts a markdown image reference.
keys.lang_map("markdown", "n", "<leader>lv", "<cmd>PasteImage<cr>", {
	desc = icons.file.Image .. " Paste image (clipboard)",
})

--- Follow link under cursor (URL, anchor, or relative file).
---
--- Detection strategy:
--- 1. **Markdown link** `[text](url)` — checks if cursor is within the link span
---    - `https://…` → opens in system browser
---    - `#anchor` → jumps to matching heading in current buffer
---    - Relative path → opens the file in the editor
--- 2. **Bare URL** `https://…` — opens in system browser
--- 3. **Nothing found** → notification
keys.lang_map("markdown", "n", "<leader>lo", function()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1

	-- ── Find markdown link: [text](url) ──────────────────────────
	for link_start, url, link_end in line:gmatch("()%[.-%]%((.-)%)()") do
		if col >= link_start and col <= link_end then
			if url:match("^https?://") then
				vim.ui.open(url)
				vim.notify("Opening: " .. url, vim.log.levels.INFO, { title = "Markdown" })
			elseif url:match("^#") then
				-- ── Internal anchor ──────────────────────────────
				local anchor = url:sub(2)
				local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
				for i, l in ipairs(lines) do
					local _, title = l:match("^(#+)%s+(.+)$")
					if title then
						local generated = title:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
						if generated == anchor then
							vim.api.nvim_win_set_cursor(0, { i, 0 })
							vim.cmd("normal! zz")
							return
						end
					end
				end
				vim.notify("Anchor not found: " .. url, vim.log.levels.WARN, { title = "Markdown" })
			else
				-- ── Relative file path ───────────────────────────
				local dir = vim.fn.expand("%:p:h")
				local target = vim.fn.fnamemodify(dir .. "/" .. url, ":p")
				if vim.fn.filereadable(target) == 1 then
					vim.cmd.edit(target)
				else
					vim.notify("File not found: " .. target, vim.log.levels.WARN, { title = "Markdown" })
				end
			end
			return
		end
	end

	-- ── Fallback: try bare URL ───────────────────────────────────
	local bare_url = line:match("https?://[%w%.%-_~:/?#%[%]@!$&'()*+,;=%%]+")
	if bare_url then
		vim.ui.open(bare_url)
	else
		vim.notify("No link found under cursor", vim.log.levels.INFO, { title = "Markdown" })
	end
end, { desc = icons.ui.ArrowRight .. " Follow link" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CHECKBOX / TASK
--
-- Toggle task list checkboxes between states:
-- - [ ] (unchecked) ↔ - [x] (checked)
-- Also converts plain list items and bare text to tasks.
-- ═══════════════════════════════════════════════════════════════════════════

--- Toggle checkbox on the current line.
---
--- State transitions:
--- 1. `- [x]` / `- [X]` → `- [ ]` (uncheck)
--- 2. `- [ ]`           → `- [x]` (check)
--- 3. `- text`          → `- [ ] text` (add unchecked box to list item)
--- 4. `text`            → `- [ ] text` (convert to task list item)
keys.lang_map("markdown", "n", "<leader>lx", function()
	local line = vim.api.nvim_get_current_line()
	---@type string|nil
	local new_line

	if line:match("%- %[x%]") or line:match("%- %[X%]") then
		new_line = line:gsub("%- %[[xX]%]", "- [ ]", 1)
	elseif line:match("%- %[ %]") then
		new_line = line:gsub("%- %[ %]", "- [x]", 1)
	elseif line:match("^%s*%-") then
		new_line = line:gsub("^(%s*%-) ", "%1 [ ] ", 1)
	else
		new_line = line:gsub("^(%s*)", "%1- [ ] ", 1)
	end

	if new_line and new_line ~= line then vim.api.nvim_set_current_line(new_line) end
end, { desc = icons.ui.Check .. " Toggle checkbox" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TABLE
--
-- Markdown table creation with configurable dimensions and
-- integration with vim-table-mode for live editing.
-- ═══════════════════════════════════════════════════════════════════════════

--- Create a markdown table with given dimensions.
---
--- Prompts for column count and row count (excluding header),
--- then inserts a properly formatted table at the current line.
--- Places the cursor on the first header cell for immediate editing.
---
--- ```markdown
--- | Header 1 | Header 2 | Header 3 |
--- | --- | --- | --- |
--- |  |  |  |
--- |  |  |  |
--- ```
keys.lang_map("markdown", "n", "<leader>lb", function()
	vim.ui.input({ prompt = "Columns: ", default = "3" }, function(cols_str)
		if not cols_str then return end
		---@type integer
		local cols = tonumber(cols_str) or 3

		vim.ui.input({ prompt = "Rows (excluding header): ", default = "2" }, function(rows_str)
			if not rows_str then return end
			---@type integer
			local rows = tonumber(rows_str) or 2

			---@type string[]
			local table_lines = {}

			-- ── Header + separator ───────────────────────────────
			local header = "|"
			local separator = "|"
			for c = 1, cols do
				header = header .. string.format(" Header %d |", c)
				separator = separator .. " --- |"
			end
			table_lines[#table_lines + 1] = header
			table_lines[#table_lines + 1] = separator

			-- ── Data rows ────────────────────────────────────────
			local empty_cell = "|"
			for _ = 1, cols do
				empty_cell = empty_cell .. "  |"
			end
			for _ = 1, rows do
				table_lines[#table_lines + 1] = empty_cell
			end
			table_lines[#table_lines + 1] = ""

			local row = vim.api.nvim_win_get_cursor(0)[1]
			vim.api.nvim_buf_set_lines(0, row, row, false, table_lines)
			vim.api.nvim_win_set_cursor(0, { row + 1, 2 })
		end)
	end)
end, { desc = icons.ui.Table .. " Insert table" })

--- Toggle automatic table formatting mode (vim-table-mode).
---
--- When enabled, tables are auto-aligned as you type. Column
--- widths adjust dynamically and separators are maintained.
keys.lang_map("markdown", "n", "<leader>lM", "<cmd>TableModeToggle<cr>", {
	desc = icons.ui.Table .. " Toggle table mode",
})

--- Realign the markdown table under cursor (vim-table-mode).
---
--- Re-formats all columns to consistent widths and fixes
--- misaligned separators. Non-destructive — only changes whitespace.
keys.lang_map("markdown", "n", "<leader>la", "<cmd>TableModeRealign<cr>", {
	desc = icons.ui.Table .. " Realign table",
})

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — CODE BLOCK
--
-- Fenced code block insertion with language selection from a
-- curated list of common programming languages.
-- ═══════════════════════════════════════════════════════════════════════════

--- Insert a fenced code block with language selector.
---
--- Presents a list of common languages via `vim.ui.select()`.
--- An empty string option is included for generic (untyped) blocks.
--- After insertion, places the cursor inside the block in insert mode.
---
--- ```markdown
--- ```python
---   ← cursor here
--- ```
--- ```
keys.lang_map("markdown", "n", "<leader>lc", function()
	---@type string[]
	local common_langs = {
		"bash",
		"c",
		"cpp",
		"css",
		"dart",
		"go",
		"html",
		"java",
		"javascript",
		"json",
		"kotlin",
		"lua",
		"python",
		"ruby",
		"rust",
		"sql",
		"typescript",
		"yaml",
		"zig",
		"",
	}

	vim.ui.select(common_langs, { prompt = "Language:" }, function(lang)
		if lang == nil then return end
		local row = vim.api.nvim_win_get_cursor(0)[1]
		local block = { "```" .. lang, "", "```", "" }
		vim.api.nvim_buf_set_lines(0, row, row, false, block)
		vim.api.nvim_win_set_cursor(0, { row + 2, 0 })
		vim.cmd("startinsert")
	end)
end, { desc = icons.ui.Code .. " Insert code block" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — EXPORT (PANDOC)
--
-- Document conversion via pandoc. Supports export to PDF, HTML,
-- DOCX, LaTeX, reStructuredText, Org, and EPUB formats.
-- ═══════════════════════════════════════════════════════════════════════════

--- Convert the current file to another format using pandoc.
---
--- Presents a list of output formats via `vim.ui.select()`, then
--- runs the appropriate `pandoc` command in a terminal split.
--- The output file has the same base name with the new extension.
---
--- Supported formats:
--- - PDF (via XeLaTeX engine)
--- - HTML (self-contained, standalone)
--- - DOCX (Microsoft Word)
--- - LaTeX (standalone .tex)
--- - reStructuredText
--- - Org (Emacs Org-mode)
--- - EPUB (e-book)
keys.lang_map("markdown", "n", "<leader>le", function()
	if vim.fn.executable("pandoc") ~= 1 then
		vim.notify("Install pandoc: brew install pandoc", vim.log.levels.WARN, { title = "Markdown" })
		return
	end

	---@type { ext: string, args: string }[]
	local formats = {
		{ ext = "pdf", args = "--pdf-engine=xelatex" },
		{ ext = "html", args = "-s --self-contained" },
		{ ext = "docx", args = "" },
		{ ext = "tex", args = "-s" },
		{ ext = "rst", args = "" },
		{ ext = "org", args = "" },
		{ ext = "epub", args = "" },
	}

	local format_names = vim.tbl_map(function(f)
		return f.ext
	end, formats)

	vim.ui.select(format_names, { prompt = "Export to:" }, function(_, idx)
		if not idx then return end
		local fmt = formats[idx]
		local file = vim.fn.expand("%:p")
		local output = vim.fn.expand("%:p:r") .. "." .. fmt.ext
		local cmd = string.format("pandoc %s -o %s %s", vim.fn.shellescape(file), vim.fn.shellescape(output), fmt.args)
		vim.cmd.split()
		vim.cmd.terminal(cmd)
	end)
end, { desc = icons.documents.File .. " Export (pandoc)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENT STATS
--
-- Comprehensive document statistics including word count, reading
-- time, and structural element counts. Word count strips code
-- blocks and HTML tags for accuracy.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show comprehensive document statistics.
---
--- Reports:
--- - **Content**: words, lines, characters, estimated reading time (~200 wpm)
--- - **Structure**: headings, links, images, code blocks, checkboxes
---
--- Word count is computed on a stripped version of the content
--- (code blocks, HTML tags, and link syntax removed) for accuracy.
keys.lang_map("markdown", "n", "<leader>li", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local content = table.concat(lines, "\n")

	-- ── Strip non-prose content for accurate word count ───────────
	local stripped = content
		:gsub("```.-```", "") -- fenced code blocks
		:gsub("<.->", "") -- HTML tags
		:gsub("%[(.-)%]%(.-%)", "%1") -- links → text only

	---@type integer
	local words = 0
	for _ in stripped:gmatch("%S+") do
		words = words + 1
	end

	---@type integer
	local chars = #content
	---@type integer
	local line_count = #lines
	---@type integer
	local reading_time = math.ceil(words / 200)

	-- ── Count structural elements ────────────────────────────────
	---@type integer, integer, integer, integer, integer, integer
	local headings, links, images, code_blocks, checkboxes, checked = 0, 0, 0, 0, 0, 0

	for _, line in ipairs(lines) do
		if line:match("^#+%s") then headings = headings + 1 end
		for _ in line:gmatch("%[.-%]%(.-%)") do
			links = links + 1
		end
		for _ in line:gmatch("!%[.-%]%(.-%)") do
			images = images + 1
		end
		if line:match("^```") then code_blocks = code_blocks + 1 end
		if line:match("%- %[ %]") then checkboxes = checkboxes + 1 end
		if line:match("%- %[[xX]%]") then
			checked = checked + 1
			checkboxes = checkboxes + 1
		end
	end
	code_blocks = math.floor(code_blocks / 2) -- pairs of ```

	local stats = string.format(
		"%s Document Stats:\n"
			.. "  Words:       %d\n"
			.. "  Lines:       %d\n"
			.. "  Characters:  %d\n"
			.. "  Reading:     ~%d min\n"
			.. "  ─────────────────\n"
			.. "  Headings:    %d\n"
			.. "  Links:       %d\n"
			.. "  Images:      %d\n"
			.. "  Code blocks: %d\n"
			.. "  Checkboxes:  %d/%d",
		md_icon,
		words,
		line_count,
		chars,
		reading_time,
		headings,
		links,
		images,
		code_blocks,
		checked,
		checkboxes
	)
	vim.notify(stats, vim.log.levels.INFO, { title = "Markdown" })
end, { desc = icons.diagnostics.Info .. " Document stats" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FORMATTING SHORTCUTS (VISUAL MODE)
--
-- Inline formatting wrappers for visual selections.
-- Each keymap wraps the selected text with the corresponding
-- markdown syntax characters.
-- ═══════════════════════════════════════════════════════════════════════════

--- Bold selection: wrap with `**`.
keys.lang_map("markdown", "v", "<leader>lb", function()
	wrap_selection("**", "**")
end, { desc = md_icon .. " Bold" })

--- Italic selection: wrap with `*`.
keys.lang_map("markdown", "v", "<leader>li", function()
	wrap_selection("*", "*")
end, { desc = md_icon .. " Italic" })

--- Code selection: wrap with `` ` ``.
keys.lang_map("markdown", "v", "<leader>lc", function()
	wrap_selection("`", "`")
end, { desc = icons.ui.Code .. " Inline code" })

--- Strikethrough selection: wrap with `~~`.
keys.lang_map("markdown", "v", "<leader>ls", function()
	wrap_selection("~~", "~~")
end, { desc = md_icon .. " Strikethrough" })

--- Convert delimiter-separated selection to a markdown table.
---
--- Delegates to vim-table-mode's `:Tableize` command which
--- converts CSV/TSV-like data into a properly formatted table.
keys.lang_map("markdown", "v", "<leader>la", ":Tableize<CR>", {
	desc = icons.ui.Table .. " Tableize selection",
})

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — OBSIDIAN
--
-- Obsidian vault operations via obsidian.nvim.
-- Degrades gracefully when outside a vault (no .obsidian directory).
-- ═══════════════════════════════════════════════════════════════════════════

--- Open an action picker for all Obsidian vault operations.
---
--- Presents common Obsidian operations via `vim.ui.select()`:
--- Quick Switch, Search, New Note, Daily Notes, Backlinks,
--- Templates, Tags, TOC, Rename, Paste Image, Workspace.
---
--- Degrades gracefully when obsidian.nvim is not loaded
--- (outside a vault or plugin not installed).
keys.lang_map("markdown", "n", "<leader>lO", function()
	if vim.fn.exists(":ObsidianQuickSwitch") ~= 2 then
		vim.notify("Obsidian not available (not in a vault?)", vim.log.levels.INFO, { title = "Markdown" })
		return
	end

	---@type { name: string, cmd: string }[]
	local actions = {
		{ name = "Quick Switch", cmd = "ObsidianQuickSwitch" },
		{ name = "Search Vault", cmd = "ObsidianSearch" },
		{ name = "New Note", cmd = "ObsidianNew" },
		{ name = "Today's Note", cmd = "ObsidianToday" },
		{ name = "Yesterday's Note", cmd = "ObsidianYesterday" },
		{ name = "Backlinks", cmd = "ObsidianBacklinks" },
		{ name = "Insert Template", cmd = "ObsidianTemplate" },
		{ name = "Tags", cmd = "ObsidianTags" },
		{ name = "Table of Contents", cmd = "ObsidianTOC" },
		{ name = "Rename Note", cmd = "ObsidianRename" },
		{ name = "Paste Image", cmd = "ObsidianPasteImg" },
		{ name = "Workspace", cmd = "ObsidianWorkspace" },
	}

	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = md_icon .. " Obsidian:" },
		function(_, idx)
			if idx then vim.cmd(actions[idx].cmd) end
		end
	)
end, { desc = md_icon .. " Obsidian actions" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
--
-- Quick access to the Markdown Guide cheat sheet.
-- ═══════════════════════════════════════════════════════════════════════════

--- Open Markdown syntax cheat sheet in the browser.
---
--- Opens the Markdown Guide cheat sheet page which covers all
--- common syntax: headings, emphasis, lists, links, images,
--- code blocks, tables, footnotes, and more.
keys.lang_map("markdown", "n", "<leader>lh", function()
	vim.ui.open("https://www.markdownguide.org/cheat-sheet/")
end, { desc = icons.ui.Note .. " Markdown cheat sheet" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — MKDNFLOW SUB-GROUP
--
-- Register <leader>lm as a visible sub-group in which-key.
-- The empty function acts as a group placeholder; which-key
-- intercepts the prefix and shows the sub-menu before the
-- timeout fires. Actual mappings are set by mkdnflow.nvim.
-- ═══════════════════════════════════════════════════════════════════════════

--- Mkdnflow sub-group placeholder for which-key.
keys.lang_map("markdown", "n", "<leader>lm", function() end, {
	desc = md_icon .. " Mkdnflow",
})

--- Insert row/col sub-group placeholder for which-key.
keys.lang_map("markdown", "n", "<leader>lmi", function() end, {
	desc = icons.ui.Plus .. " Insert row/col",
})

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
--
-- Registers Markdown-specific alignment presets for mini.align:
-- • markdown_table — align table columns on "|"
--
-- Uses a guard (`is_language_loaded`) to prevent duplicate registration
-- when the module is re-sourced.
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("markdown") then
		---@type string Alignment preset icon from icons.file
		local md_align_icon = icons.file.Markdown

		-- ── Register presets ─────────────────────────────────────────
		align_registry.register_many({
			markdown_table = {
				description = "Align Markdown table columns on '|'",
				icon = md_align_icon,
				split_pattern = "|",
				category = "data",
				lang = "markdown",
				filetypes = { "markdown" },
			},
		})

		-- ── Set default filetype mapping ─────────────────────────────
		align_registry.set_ft_mapping("markdown", "markdown_table")
		align_registry.mark_language_loaded("markdown")

		-- ── Alignment keymaps ────────────────────────────────────────
		keys.lang_map("markdown", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("markdown_table"), {
			desc = md_align_icon .. "  Align Markdown table",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RUNTIME SETUP — FILETYPE, BUFFER OPTIONS
--
-- Runs at MODULE IMPORT TIME. Decoupled from any plugin lifecycle.
-- Guarantees filetype detection and buffer options are active
-- regardless of which plugins are loaded or their load order.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Filetype detection ────────────────────────────────────────────────
vim.filetype.add({
	extension = {
		md = "markdown",
		mdx = "markdown.mdx",
		rmd = "rmd",
	},
	filename = {
		["README"] = "markdown",
		["CHANGELOG"] = "markdown",
		["LICENSE"] = "markdown",
	},
	pattern = {
		["%.marksman%.toml$"] = "toml",
		["%.markdownlint.*"] = "json",
	},
})

-- ── 2. Buffer-local options for prose filetypes ──────────────────────────
local prose_augroup = vim.api.nvim_create_augroup("MarkdownProseOpts", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
	group = prose_augroup,
	pattern = {
		"markdown",
		"markdown.mdx",
		"text",
		"plaintex",
		"rst",
		"org",
		"norg",
		"gitcommit",
		"mail",
	},
	callback = function()
		local opt = vim.opt_local
		opt.wrap = true
		opt.conceallevel = 2
		opt.linebreak = true
		opt.breakindent = true
		opt.breakindentopt = "shift:2"
		opt.textwidth = 80
		opt.colorcolumn = "80"
		opt.tabstop = 2
		opt.shiftwidth = 2
		opt.softtabstop = 2
		opt.expandtab = true
		opt.formatoptions = "tcroqnlj"
		opt.commentstring = "<!-- %s -->"
		opt.number = true
		opt.relativenumber = false
		opt.spell = true
		opt.spelllang = "en_us"
	end,
})

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations. Each spec adds only the Markdown-specific
-- parts (servers, formatters, linters, parsers, prose tools).
--
-- Loading strategy:
-- ┌────────────────────────────┬──────────────────────────────────────┐
-- │ Plugin                     │ How it lazy-loads for Markdown       │
-- ├────────────────────────────┼──────────────────────────────────────┤
-- │ nvim-lspconfig             │ opts merge (marksman server added)   │
-- │ mason.nvim                 │ opts merge (tools → ensure_installed)│
-- │ conform.nvim               │ opts merge (formatters_by_ft)        │
-- │ nvim-lint                  │ opts merge (linters_by_ft)           │
-- │ nvim-treesitter            │ opts merge (parsers → ensure_install)│
-- │ render-markdown.nvim       │ ft = "markdown" (true lazy load)    │
-- │ markdown-preview.nvim      │ ft + cmd (true lazy load)           │
-- │ obsidian.nvim              │ ft + cond (.obsidian dir check)     │
-- │ mkdnflow.nvim              │ ft = "markdown" (true lazy load)    │
-- │ vim-table-mode             │ ft = "markdown" (true lazy load)    │
-- │ img-clip.nvim              │ ft = "markdown" (true lazy load)    │
-- │ headlines.nvim             │ ft = "markdown" (true lazy load)    │
-- │ nvim-toc                   │ ft = "markdown" (true lazy load)    │
-- │ toggle-checkbox.nvim       │ ft = "markdown" (true lazy load)    │
-- │ follow-md-links.nvim       │ ft = "markdown" (true lazy load)    │
-- └────────────────────────────┴──────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[]
return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	-- marksman: cross-file references, wiki-links, heading completion.
	-- Filetype detection and buffer options are at module level above.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				marksman = {},
			},
		},
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"prettier",
				"markdownlint-cli2",
			},
		},
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	-- prettier:           prose-wrap at 80 chars, 2-space indent
	-- markdownlint-cli2:  auto-fixes lintable issues
	-- markdown-toc:       auto-generates/updates TOC markers
	--
	-- FIX: removed `optional = true` (can prevent merge)
	-- FIX: formatter config targets `prettier` (was `prettierd` — bug)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		opts = {
			formatters_by_ft = {
				["markdown"] = { "prettier", "markdownlint-cli2", "markdown-toc" },
				["markdown.mdx"] = { "prettier", "markdownlint-cli2", "markdown-toc" },
			},
			formatters = {
				prettier = {
					prepend_args = {
						"--prose-wrap",
						"always",
						"--print-width",
						"80",
						"--tab-width",
						"2",
					},
				},
			},
		},
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	-- FIX: removed `optional = true`
	-- ───────────────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		opts = {
			linters_by_ft = {
				markdown = { "markdownlint-cli2" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"markdown",
				"markdown_inline",
				"html",
				"latex",
				"yaml",
				"toml",
				"mermaid",
			},
		},
	},

	-- ── OBSIDIAN ───────────────────────────────────────────────────────────
	{
		"epwalsh/obsidian.nvim",
		version = "*",
		lazy = true,
		ft = { "markdown" },
		cond = function()
			local cwd = vim.fn.getcwd()
			return vim.fn.filereadable(cwd .. "/.obsidian/app.json") == 1 or vim.fn.isdirectory(cwd .. "/.obsidian") == 1
		end,
		dependencies = {
			"nvim-lua/plenary.nvim",
			"saghen/blink.cmp",
			"nvim-telescope/telescope.nvim",
		},
		opts = {
			workspaces = {
				{
					name = "auto",
					path = function()
						return vim.fn.getcwd()
					end,
				},
			},
			completion = {
				nvim_cmp = true,
				min_chars = 2,
			},
			new_notes_location = "current_dir",
			note_id_func = function(title)
				if title ~= nil then return title:gsub(" ", "-"):gsub("[^A-Za-z0-9-]", ""):lower() end
				return tostring(os.time())
			end,
			wiki_link_func = function(opts)
				if opts.id == opts.label then return string.format("[[%s]]", opts.id) end
				return string.format("[[%s|%s]]", opts.id, opts.label)
			end,
			mappings = {
				["gf"] = {
					action = function()
						return require("obsidian").util.gf_passthrough()
					end,
					opts = { noremap = false, expr = true, buffer = true },
				},
				["<leader>oc"] = {
					action = function()
						return require("obsidian").util.toggle_checkbox()
					end,
					opts = { buffer = true },
				},
			},
			ui = {
				enable = true,
				checkboxes = {
					[" "] = { char = "󰄱", hl_group = "ObsidianTodo" },
					["x"] = { char = "", hl_group = "ObsidianDone" },
					[">"] = { char = "", hl_group = "ObsidianRightArrow" },
					["~"] = { char = "󰰱", hl_group = "ObsidianTilde" },
				},
				bullets = { char = "•", hl_group = "ObsidianBullet" },
				external_link_icon = { char = "", hl_group = "ObsidianExtLinkIcon" },
				reference_text = { hl_group = "ObsidianRefText" },
				highlight_text = { hl_group = "ObsidianHighlightText" },
				tags = { hl_group = "ObsidianTag" },
			},
		},
	},

	-- ── RENDER MARKDOWN ────────────────────────────────────────────────────
	{
		"MeanderingProgrammer/render-markdown.nvim",
		ft = { "markdown", "norg", "rmd", "org", "codecompanion", "Avante" },
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"echasnovski/mini.icons",
		},
		opts = {
			file_types = { "markdown", "norg", "rmd", "org", "codecompanion", "Avante" },
			code = {
				sign = false,
				width = "block",
				right_pad = 1,
				language_pad = 1,
				language_name = true,
				border = "thin",
				highlight = "RenderMarkdownCode",
			},
			heading = {
				sign = false,
				icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
				backgrounds = {
					"RenderMarkdownH1Bg",
					"RenderMarkdownH2Bg",
					"RenderMarkdownH3Bg",
					"RenderMarkdownH4Bg",
					"RenderMarkdownH5Bg",
					"RenderMarkdownH6Bg",
				},
				foregrounds = {
					"RenderMarkdownH1",
					"RenderMarkdownH2",
					"RenderMarkdownH3",
					"RenderMarkdownH4",
					"RenderMarkdownH5",
					"RenderMarkdownH6",
				},
			},
			bullet = {
				icons = { "●", "○", "◆", "◇" },
			},
			checkbox = {
				unchecked = { icon = "󰄱 " },
				checked = { icon = "󰱒 " },
				custom = {
					partial = { raw = "[~]", rendered = "󰥔 ", highlight = "RenderMarkdownWarn" },
					forwarded = { raw = "[>]", rendered = "󰒊 ", highlight = "RenderMarkdownInfo" },
					important = { raw = "[!]", rendered = "󰀦 ", highlight = "RenderMarkdownError" },
					question = { raw = "[?]", rendered = "󰘥 ", highlight = "RenderMarkdownWarn" },
				},
			},
			dash = {
				icon = "─",
				width = "full",
			},
			link = {
				hyperlink = "󰌹 ",
				image = "󰥶 ",
				email = "󰇮 ",
			},
			pipe_table = {
				enabled = true,
				style = "full",
				cell = "padded",
			},
			quote = {
				repeat_linebreak = true,
			},
			win_options = {
				conceallevel = { rendered = 2 },
				concealcursor = { rendered = "nc" },
			},
			anti_conceal = {
				enabled = true,
				above = 0,
				below = 0,
			},
		},
	},

	-- ── MARKDOWN PREVIEW ───────────────────────────────────────────────────
	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		ft = { "markdown" },
		build = function()
			require("lazy").load({ plugins = { "markdown-preview.nvim" } })
			vim.fn["mkdp#util#install"]()
		end,
		init = function()
			vim.g.mkdp_auto_start = 0
			vim.g.mkdp_auto_close = 1
			vim.g.mkdp_refresh_slow = 0
			vim.g.mkdp_preview_options = {
				mkit = {},
				katex = {},
				uml = {},
				maid = {},
				disable_sync_scroll = 0,
				sync_scroll_type = "middle",
				hide_yaml_meta = 1,
				sequence_diagrams = {},
				flowchart_diagrams = {},
				content_editable = false,
				disable_filename = 0,
				toc = {},
			}
			vim.g.mkdp_theme = "dark"
			vim.g.mkdp_page_title = "${name} — Preview"
			vim.g.mkdp_filetypes = { "markdown" }
		end,
	},

	-- ── IMG-CLIP ───────────────────────────────────────────────────────────
	{
		"HakonHarnes/img-clip.nvim",
		ft = { "markdown", "norg", "org" },
		opts = {
			default = {
				dir_path = "assets/images",
				relative_to_current_file = true,
				prompt_for_file_name = true,
				file_name = "%Y%m%d-%H%M%S",
				extension = "png",
				template = "![$CURSOR]($FILE_PATH)",
			},
			filetypes = {
				markdown = {
					url_encode_path = true,
					template = "![$CURSOR]($FILE_PATH)",
				},
			},
		},
	},

	-- ── VIM-TABLE-MODE ─────────────────────────────────────────────────────
	{
		"dhruvasagar/vim-table-mode",
		ft = { "markdown" },
		init = function()
			vim.g.table_mode_corner = "|"
			vim.g.table_mode_header_fillchar = "-"
			vim.g.table_mode_auto_align = 1
		end,
	},

	-- ── HEADLINES ──────────────────────────────────────────────────────────
	{
		"lukas-reineke/headlines.nvim",
		ft = { "markdown", "norg", "rmd", "org" },
		dependencies = "nvim-treesitter/nvim-treesitter",
		opts = {
			markdown = {
				headline_highlights = {
					"Headline1",
					"Headline2",
					"Headline3",
					"Headline4",
					"Headline5",
					"Headline6",
				},
				bullet_highlights = {
					"@markup.heading.1.markdown",
					"@markup.heading.2.markdown",
					"@markup.heading.3.markdown",
					"@markup.heading.4.markdown",
					"@markup.heading.5.markdown",
					"@markup.heading.6.markdown",
				},
				fat_headlines = true,
				fat_headline_upper_string = "▄",
				fat_headline_lower_string = "▀",
				dash_highlight = "Dash",
				dash_string = "─",
				quote_highlight = "Quote",
				quote_string = "┃",
				codeblock_highlight = "CodeBlock",
			},
		},
		config = function(_, opts)
			vim.api.nvim_set_hl(0, "Headline1", { fg = "#f38ba8", bg = "#2a1f2e", bold = true })
			vim.api.nvim_set_hl(0, "Headline2", { fg = "#fab387", bg = "#2a2520", bold = true })
			vim.api.nvim_set_hl(0, "Headline3", { fg = "#f9e2af", bg = "#2a2820", bold = true })
			vim.api.nvim_set_hl(0, "Headline4", { fg = "#a6e3a1", bg = "#1e2a22", bold = true })
			vim.api.nvim_set_hl(0, "Headline5", { fg = "#89b4fa", bg = "#1e2230", bold = true })
			vim.api.nvim_set_hl(0, "Headline6", { fg = "#cba6f7", bg = "#251e30", bold = true })
			vim.api.nvim_set_hl(0, "Dash", { fg = "#3b4261" })
			vim.api.nvim_set_hl(0, "Quote", { fg = "#7aa2f7" })
			vim.api.nvim_set_hl(0, "CodeBlock", { bg = "#1e1e2e" })
			require("headlines").setup(opts)
		end,
	},

	-- ── MARKDOWN-TOC ───────────────────────────────────────────────────────
	{
		"richardbizik/nvim-toc",
		ft = { "markdown" },
		opts = {
			toc_header = "Table of Contents",
		},
	},

	-- ── TOGGLE CHECKBOX ────────────────────────────────────────────────────
	{
		"opdavies/toggle-checkbox.nvim",
		ft = { "markdown" },
	},

	-- ── FOLLOW-MD-LINKS ────────────────────────────────────────────────────
	{
		"jghauser/follow-md-links.nvim",
		ft = { "markdown" },
	},

	-- ── MKDNFLOW ───────────────────────────────────────────────────────────
	{
		"jakewvincent/mkdnflow.nvim",
		ft = { "markdown" },
		opts = {
			modules = {
				bib = false,
				buffers = true,
				conceal = false,
				cursor = true,
				folds = false,
				foldtext = false,
				links = true,
				lists = true,
				maps = true,
				paths = true,
				tables = true,
				yaml = false,
			},

			-- FIX: use Neovim filetype names (not extensions)
			-- OLD: { md = true, rmd = true, mdx = true }
			filetypes = { "markdown", "rmd", "markdown.mdx" },

			create_dirs = true,
			perspective = {
				priority = "current",
				fallback = "first",
				root_tell = ".git",
				nvim_wd_heel = false,
			},
			wrap = false,
			links = {
				style = "markdown",
				name_is_source = false,
				conceal = false,
				context = 0,
				implicit_extension = nil,
				transform_implicit = false,
				transform_explicit = function(text)
					return text:gsub(" ", "-"):lower()
				end,
			},

			-- FIX: flatten placeholders (remove before/after nesting)
			-- OLD: placeholders = { before = { title = ..., date = ... }, after = {} }
			new_file_template = {
				use_template = true,
				placeholders = {
					title = "link_title",
					date = "os_date",
				},
				template = "# {{ title }}\n\nDate: {{ date }}\n\n",
			},

			-- FIX: complete rewrite of to_do section
			-- OLD: symbols, not_started, in_progress, complete, update_parents
			-- NEW: statuses (dict), status_order, status_propagation
			to_do = {
				statuses = {
					[" "] = { name = "not_started" },
					["-"] = { name = "in_progress" },
					["x"] = { name = "complete" },
				},
				status_order = { " ", "-", "x" },
				status_propagation = {
					up = true,
				},
			},

			tables = {
				trim_whitespace = true,
				format_on_move = true,
				auto_extend_rows = false,
				auto_extend_cols = false,
			},
			mappings = {
				MkdnEnter = { { "n", "v" }, "<CR>" },
				MkdnTab = false,
				MkdnSTab = false,
				MkdnNextLink = { "n", "]l" },
				MkdnPrevLink = { "n", "[l" },
				MkdnNextHeading = { "n", "]]" },
				MkdnPrevHeading = { "n", "[[" },
				MkdnGoBack = { "n", "<BS>" },
				MkdnGoForward = false,
				MkdnCreateLink = false,
				MkdnCreateLinkFromClipboard = { { "n", "v" }, "<leader>lmL" },
				MkdnFollowLink = false,
				MkdnDestroyLink = { "n", "<leader>lmd" },
				MkdnTagSpan = { "v", "<M-CR>" },
				MkdnMoveSource = { "n", "<F2>" },
				MkdnYankAnchorLink = { "n", "yaa" },
				MkdnYankFileAnchorLink = { "n", "yfa" },
				MkdnIncreaseHeading = { "n", "+" },
				MkdnDecreaseHeading = { "n", "-" },
				MkdnToggleToDo = { { "n", "v" }, "<leader>lmc" },
				MkdnNewListItem = false,
				MkdnNewListItemBelowInsert = { "n", "o" },
				MkdnNewListItemAboveInsert = { "n", "O" },
				MkdnExtendList = false,
				MkdnUpdateNumbering = { "n", "<leader>lmn" },
				MkdnTableNextCell = { "i", "<Tab>" },
				MkdnTablePrevCell = { "i", "<S-Tab>" },
				MkdnTableNextRow = false,
				MkdnTablePrevRow = { "i", "<M-CR>" },
				MkdnTableNewRowBelow = { "n", "<leader>lmir" },
				MkdnTableNewRowAbove = { "n", "<leader>lmiR" },
				MkdnTableNewColAfter = { "n", "<leader>lmia" },
				MkdnTableNewColBefore = { "n", "<leader>lmiA" },
				MkdnFoldSection = { "n", "<leader>lmf" },
				MkdnUnfoldSection = { "n", "<leader>lmF" },
			},
		},
	},
}
