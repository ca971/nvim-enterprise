---@file lua/plugins/editor/markview.lua
---@description Markview — rich inline preview for Markdown, LaTeX, HTML & Typst inside Neovim
---@module "plugins.editor.markview"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.icons               Central icon definitions (glyphs, borders, separators)
---@see plugins.ui.presenting    Presentation mode from markdown (complementary)
---@see plugins.ui.no-neck-pain  Centered layout for wide screens (complementary)
---@see langs.markdown            Markdown LSP, linter & treesitter (complementary)
---
---@see https://github.com/OXY2DEV/markview.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/markview.lua — Markdown rendering & preview              ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  markview.nvim                                                   │    ║
--- ║  │                                                                  │    ║
--- ║  │  Renders markdown elements inline using Neovim's conceal and     │    ║
--- ║  │  extmarks. The buffer content is NEVER modified — all rendering  │    ║
--- ║  │  is purely visual (virtual text + concealed text).               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Rendering examples:                                             │    ║
--- ║  │  ┌─────────────────────────────────────────────────────────┐     │    ║
--- ║  │  │  # Heading          →  ██ Heading ██  (highlighted)     │     │    ║
--- ║  │  │  - [ ] Task         →  ☐ Task         (checkbox icon)   │     │    ║
--- ║  │  │  - [x] Done         →  ✔ Done         (checked icon)    │     │    ║
--- ║  │  │  ```lua ... ```     →  ┃ lua  ...  ┃  (styled block)    │     │    ║
--- ║  │  │  [link](url)        →  link↗          (concealed URL)   │     │    ║
--- ║  │  │  ---                →  ────────────── (horizontal rule) │     │    ║
--- ║  │  │  $\sum_{i=0}^n$     →  Σᵢ₌₀ⁿ         (LaTeX rendered)   │     │    ║
--- ║  │  └─────────────────────────────────────────────────────────┘     │    ║
--- ║  │                                                                  │    ║
--- ║  │  Hybrid mode (automatic source ↔ preview):                       │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Normal mode  → rendered (pretty headings, icons, etc.)  │    │    ║
--- ║  │  │  Insert mode  → raw markdown (full editing control)      │    │    ║
--- ║  │  │  Visual mode  → raw markdown (accurate text selection)   │    │    ║
--- ║  │  │  conceallevel managed automatically via callbacks        │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Checkbox state machine (<leader>mt):                            │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  - [x] Task  →  - [ ] Task      (checked → unchecked)    │    │    ║
--- ║  │  │  - [ ] Task  →  - [x] Task      (unchecked → checked)    │    │    ║
--- ║  │  │  - List item →  - [ ] List item  (list → add checkbox)   │    │    ║
--- ║  │  │  Plain text  →  - [ ] Plain text (plain → full checkbox) │    │    ║
--- ║  │  │                                                          │    │    ║
--- ║  │  │  Obsidian custom states: [/] progress, [-] cancelled,    │    │    ║
--- ║  │  │  [*] starred, [?] question, [i] info                     │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Complements (does NOT replace):                                 │    ║
--- ║  │  ├─ <Space>uc     Toggle conceal level (core toggle)             │    ║
--- ║  │  ├─ <Space>uT     Toggle treesitter highlight (core toggle)      │    ║
--- ║  │  ├─ <leader>vp    presenting.nvim (slides from markdown)         │    ║
--- ║  │  └─ markdown-preview.nvim (browser-based preview, external)      │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • ft-only loading (zero startup cost for non-markdown workflows)        ║
--- ║  • Treesitter parsers as dependencies (markdown, markdown_inline)        ║
--- ║  • Hybrid mode: raw source auto-shown in insert (no manual toggle)       ║
--- ║  • No background processes (pure extmark rendering)                      ║
--- ║  • conceallevel managed automatically via on_enable/on_disable           ║
--- ║  • Icons from core/icons.lua (single source of truth)                    ║
--- ║                                                                          ║
--- ║  Global keymaps (markdown filetypes only):                               ║
--- ║  ┌─────────────────────────────────────────────────────────────────────┐ ║
--- ║  │  KEY          MODE   ACTION                     CONFLICT STATUS     │ ║
--- ║  │                                                                     │ ║
--- ║  │  Rendering:                                                         │ ║
--- ║  │  <leader>mm   n      Toggle markview rendering  ✓ safe (m* owned)   │ ║
--- ║  │  <leader>ms   n      Toggle splitview           ✓ safe              │ ║
--- ║  │  <leader>mp   n      Open preview               ✓ safe              │ ║
--- ║  │                                                                     │ ║
--- ║  │  Editing:                                                           │ ║
--- ║  │  <leader>mh   n      Increase heading level     ✓ safe              │ ║
--- ║  │  <leader>mH   n      Decrease heading level     ✓ safe              │ ║
--- ║  │  <leader>mt   n      Toggle checkbox             ✓ safe             │ ║
--- ║  │  <leader>mc   n      Insert code block           ✓ safe             │ ║
--- ║  │  <leader>ml   n      Insert link template        ✓ safe             │ ║
--- ║  │  <leader>mT   n      Generate TOC                ✓ safe             │ ║
--- ║  │                                                                     │ ║
--- ║  │  Navigation (]x / [x convention):                                   │ ║
--- ║  │  ]m           n      Next heading                ✓ safe             │ ║
--- ║  │  [m           n      Prev heading                ✓ safe             │ ║
--- ║  └─────────────────────────────────────────────────────────────────────┘ ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Markview plugin is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_plugin_enabled("markview") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

---@type Icons
local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS
--
-- Filetype lists used for both plugin loading and keymap scoping.
-- Separated to allow broader loading triggers while restricting
-- editing keymaps to true markdown files only.
-- ═══════════════════════════════════════════════════════════════════════════

--- Filetypes where markview rendering is active.
--- Used for keymap `ft` scoping on rendering controls.
---@type string[]
local supported_ft = { "markdown", "latex", "html", "typst" }

--- Extended filetypes including aliases and AI chat buffers.
--- Used for the `ft` lazy-loading trigger to cover all markdown variants.
--- - `md` is an alias for `markdown` in some plugins
--- - `tex` is an alias for `latex` in some configurations
--- - `Avante` is an AI chat plugin that uses markdown for its buffer
---@type string[]
local load_ft = { "markdown", "md", "latex", "tex", "html", "typst", "Avante" }

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
--
-- Utility functions used by keymaps throughout this module.
-- All functions are module-local and not exposed to consumers.
-- ═══════════════════════════════════════════════════════════════════════════

--- Increase the heading level of the current line by prepending `#`.
---
--- Behavior:
--- - `## Title` → `### Title` (level 2 → level 3)
--- - `###### Title` → unchanged (level 6 is the markdown maximum)
--- - `Plain text` → `# Plain text` (becomes a level 1 heading)
---
--- Note: "increase level" means deeper nesting (more `#` characters),
--- which is consistent with heading hierarchy (h1 > h2 > h3).
---
---@return nil
---@private
local function heading_increase()
	local line = vim.api.nvim_get_current_line()
	local level = line:match("^(#+)")
	if level and #level < 6 then
		vim.api.nvim_set_current_line("#" .. line)
	elseif not level then
		vim.api.nvim_set_current_line("# " .. line)
	end
end

--- Decrease the heading level of the current line by removing one `#`.
---
--- Behavior:
--- - `### Title` → `## Title` (level 3 → level 2)
--- - `# Title` → `Title` (heading removed entirely)
--- - `Plain text` → unchanged (not a heading)
---
---@return nil
---@private
local function heading_decrease()
	local line = vim.api.nvim_get_current_line()
	local hashes, rest = line:match("^(#+)%s?(.*)")
	if hashes and #hashes > 1 then
		vim.api.nvim_set_current_line(hashes:sub(2) .. " " .. rest)
	elseif hashes and #hashes == 1 then
		vim.api.nvim_set_current_line(rest)
	end
end

--- Cycle the checkbox state on the current line.
---
--- State machine:
--- ```
--- - [x] Task  →  - [ ] Task      (checked → unchecked)
--- - [ ] Task  →  - [x] Task      (unchecked → checked)
--- - List item →  - [ ] List item  (list → add checkbox)
--- Plain text  →  - [ ] Plain text (plain → full list + checkbox)
--- ```
---
--- Compatible with Obsidian-style checkboxes (`[/]`, `[-]`, `[*]`, etc.).
---
---@return nil
---@private
local function toggle_checkbox()
	local line = vim.api.nvim_get_current_line()
	if line:match("%- %[x%]") then
		vim.api.nvim_set_current_line((line:gsub("%- %[x%]", "- [ ]", 1)))
	elseif line:match("%- %[ %]") then
		vim.api.nvim_set_current_line((line:gsub("%- %[ %]", "- [x]", 1)))
	elseif line:match("^%s*%-") then
		vim.api.nvim_set_current_line((line:gsub("^(%s*%-)%s", "%1 [ ] ", 1)))
	else
		vim.api.nvim_set_current_line((line:gsub("^(%s*)", "%1- [ ] ", 1)))
	end
end

--- Insert a fenced code block below the current line.
---
--- The block is indented to match the current line's indentation.
--- Cursor is placed at the language identifier position (after the
--- opening ```) and insert mode is entered for immediate language typing.
---
--- Result:
--- ```
--- ```|
---
--- ```
--- ```
--- (where `|` is cursor position)
---
---@return nil
---@private
local function insert_code_block()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	---@type string
	local indent = vim.api.nvim_get_current_line():match("^(%s*)")
	vim.api.nvim_buf_set_lines(0, row, row, false, {
		indent .. "```",
		indent .. "",
		indent .. "```",
	})
	vim.api.nvim_win_set_cursor(0, { row + 1, #indent + 3 })
	vim.cmd("startinsert!")
end

--- Insert a markdown link template `[](url)` at the cursor position.
---
--- Cursor is placed inside the square brackets for immediate label
--- typing. The `url` placeholder can be tabbed to afterwards.
---
---@return nil
---@private
local function insert_link()
	local pos = vim.api.nvim_win_get_cursor(0)
	vim.api.nvim_put({ "[](url)" }, "c", true, false)
	vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] + 1 })
	vim.cmd("startinsert")
end

--- Generate a table of contents from all headings in the buffer.
---
--- Scans the entire buffer for lines matching `^#+\s+(.*)`, builds a
--- nested markdown list with anchor links, and inserts it at the
--- current cursor position.
---
--- Anchor generation follows GitHub's algorithm:
--- 1. Lowercase the heading text
--- 2. Replace spaces with hyphens
--- 3. Strip all non-alphanumeric, non-hyphen characters
---
--- ### Example output
--- ```markdown
--- ## Table of Contents
---
--- - [Getting Started](#getting-started)
---   - [Installation](#installation)
---   - [Configuration](#configuration)
--- - [API Reference](#api-reference)
--- ```
---
---@return nil
---@private
local function generate_toc()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	---@type string[]
	local toc = { "## Table of Contents", "" }
	---@type integer
	local heading_count = 0

	for _, line in ipairs(lines) do
		local hashes, title = line:match("^(#+)%s+(.*)")
		if hashes and title then
			local level = #hashes
			local indent = string.rep("  ", level - 1)
			-- GitHub-compatible anchor: lowercase, spaces→hyphens, strip specials
			local anchor = title:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
			toc[#toc + 1] = indent .. "- [" .. title .. "](#" .. anchor .. ")"
			heading_count = heading_count + 1
		end
	end

	toc[#toc + 1] = ""
	local row = vim.api.nvim_win_get_cursor(0)[1]
	vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, toc)
	vim.notify(
		string.format("TOC generated (%d headings)", heading_count),
		vim.log.levels.INFO,
		{ title = "Markview" }
	)
end

--- Jump to the next markdown heading below the cursor.
---
--- Searches from the line after the cursor to the end of the buffer.
--- Notifies the user if no heading is found below.
---
---@return nil
---@private
local function jump_next_heading()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(0, row, -1, false)
	for i, line in ipairs(lines) do
		if line:match("^#+%s") then
			vim.api.nvim_win_set_cursor(0, { row + i, 0 })
			return
		end
	end
	vim.notify("No next heading", vim.log.levels.WARN, { title = "Markview" })
end

--- Jump to the previous markdown heading above the cursor.
---
--- Searches from the line before the cursor to the top of the buffer.
--- Iterates in reverse for efficiency (finds the closest match first).
--- Notifies the user if no heading is found above.
---
---@return nil
---@private
local function jump_prev_heading()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local lines = vim.api.nvim_buf_get_lines(0, 0, row - 1, false)
	for i = #lines, 1, -1 do
		if lines[i]:match("^#+%s") then
			vim.api.nvim_win_set_cursor(0, { i, 0 })
			return
		end
	end
	vim.notify("No previous heading", vim.log.levels.WARN, { title = "Markview" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPEC
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Trigger            │ Details                                      │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ ft                 │ markdown, md, latex, tex, html, typst,       │
-- │                    │ Avante (loads on first matching buffer)       │
-- │ keys               │ <leader>m{m,s,p,h,H,t,c,l,T}, ]m, [m       │
-- │ dependencies       │ nvim-treesitter, nvim-web-devicons           │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec
return {
	"OXY2DEV/markview.nvim",

	-- ═══════════════════════════════════════════════════════════════════
	-- LAZY LOADING STRATEGY
	--
	-- ft-only loading: markview is a rendering plugin that only makes
	-- sense for markup filetypes. Loading on ft keeps startup at zero
	-- cost for non-markdown workflows. The plugin self-attaches to
	-- buffers matching these filetypes once loaded.
	--
	-- "Avante" is included for AI chat buffers that use markdown.
	-- ═══════════════════════════════════════════════════════════════════
	ft = load_ft,

	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"nvim-tree/nvim-web-devicons",
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- GLOBAL KEYMAPS
	--
	-- All keymaps under <leader>m prefix (Markdown group).
	-- Only active in markdown-related filetypes via `ft` scoping.
	--
	-- Navigation keys ]m / [m follow the ]x / [x convention:
	--   ]d/[d  diagnostics      ]h/[h  git hunks
	--   ]H/[H  harpoon marks    ]b/[b  buffers
	--   ]t/[t  TODOs            ]q/[q  quickfix
	--   ]m/[m  markdown headings
	-- ═══════════════════════════════════════════════════════════════════
	keys = {
		-- ── Rendering controls ───────────────────────────────────────
		{
			"<leader>mm",
			"<Cmd>Markview toggle<CR>",
			ft = supported_ft,
			desc = icons.file.Markdown .. " Toggle Markview",
		},
		{
			"<leader>ms",
			"<Cmd>Markview splitToggle<CR>",
			ft = supported_ft,
			desc = icons.ui.Window .. " Splitview toggle",
		},
		{
			"<leader>mp",
			"<Cmd>Markview splitOpen<CR>",
			ft = supported_ft,
			desc = icons.ui.Play .. " Open preview",
		},

		-- ── Heading manipulation ─────────────────────────────────────
		{
			"<leader>mh",
			heading_increase,
			ft = { "markdown" },
			desc = icons.ui.BoldArrowDown .. " Heading increase (add #)",
		},
		{
			"<leader>mH",
			heading_decrease,
			ft = { "markdown" },
			desc = icons.ui.BoldArrowUp .. " Heading decrease (remove #)",
		},

		-- ── Checkbox toggle ──────────────────────────────────────────
		{
			"<leader>mt",
			toggle_checkbox,
			ft = { "markdown" },
			desc = icons.ui.Check .. " Toggle checkbox",
		},

		-- ── Insert helpers ───────────────────────────────────────────
		{
			"<leader>mc",
			insert_code_block,
			ft = { "markdown" },
			desc = icons.ui.Code .. " Insert code block",
		},
		{
			"<leader>ml",
			insert_link,
			ft = { "markdown" },
			desc = icons.ui.ArrowRight .. " Insert link",
		},

		-- ── Table of contents ────────────────────────────────────────
		{
			"<leader>mT",
			generate_toc,
			ft = { "markdown" },
			desc = icons.ui.List .. " Table of contents",
		},

		-- ── Heading navigation ───────────────────────────────────────
		{
			"]m",
			jump_next_heading,
			ft = { "markdown" },
			desc = icons.file.Markdown .. " Next heading",
		},
		{
			"[m",
			jump_prev_heading,
			ft = { "markdown" },
			desc = icons.file.Markdown .. " Prev heading",
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- OPTIONS
	--
	-- Organized into logical sections:
	-- ├─ Preview        Hybrid mode and conceal management
	-- ├─ Markdown       Block-level rendering (headings, code, hr, lists)
	-- ├─ Markdown inline Inline rendering (checkboxes, emphasis)
	-- ├─ LaTeX          Math expression rendering
	-- └─ HTML           Entity and tag rendering
	-- ═══════════════════════════════════════════════════════════════════
	opts = {
		-- ═══════════════════════════════════════════════════════════════
		-- PREVIEW MODE
		--
		-- Hybrid mode provides the best editing experience:
		-- • Normal mode: markdown is rendered (pretty headings, icons)
		-- • Insert mode: raw markdown is shown (full editing control)
		-- • Visual mode: raw markdown is shown (accurate selection)
		--
		-- This eliminates the need to manually toggle rendering.
		-- The conceallevel is managed automatically via callbacks.
		-- ═══════════════════════════════════════════════════════════════
		preview = {
			---@type string[] Modes where rendering is active
			modes = { "n", "no", "c" },

			---@type string[] Modes where hybrid (auto-reveal) is active
			hybrid_modes = { "n", "no" },

			callbacks = {
				--- Called when markview enables on a window.
				--- Sets conceallevel to 2 so concealed text is replaced
				--- with the configured substitute character (icon).
				---@param _ any Unused buffer reference
				---@param win integer Window ID to configure
				on_enable = function(_, win)
					vim.wo[win].conceallevel = 2
					vim.wo[win].concealcursor = "nc"
				end,

				--- Called when markview disables on a window.
				--- Resets conceallevel to 0 to show raw markdown.
				---@param _ any Unused buffer reference
				---@param win integer Window ID to configure
				on_disable = function(_, win)
					vim.wo[win].conceallevel = 0
					vim.wo[win].concealcursor = ""
				end,
			},
		},

		-- ═══════════════════════════════════════════════════════════════
		-- MARKDOWN RENDERING — BLOCK ELEMENTS
		--
		-- Each section controls how a specific markdown element is
		-- rendered inline. All icons come from core/icons.lua.
		-- Highlight groups (MarkviewHeading1, etc.) are defined
		-- by the markview plugin itself and adapt to the colorscheme.
		-- ═══════════════════════════════════════════════════════════════
		markdown = {
			-- ── Headings ─────────────────────────────────────────────
			-- Rendered as labeled badges with background highlights.
			-- shift_width controls left padding for hierarchy indent.
			headings = {
				---@type boolean
				enable = true,
				---@type integer Left padding per heading level
				shift_width = 1,
				heading_1 = { style = "label", padding_left = " ", padding_right = " ", hl = "MarkviewHeading1" },
				heading_2 = { style = "label", padding_left = " ", padding_right = " ", hl = "MarkviewHeading2" },
				heading_3 = { style = "label", padding_left = " ", padding_right = " ", hl = "MarkviewHeading3" },
				heading_4 = { style = "label", padding_left = " ", padding_right = " ", hl = "MarkviewHeading4" },
				heading_5 = { style = "label", padding_left = " ", padding_right = " ", hl = "MarkviewHeading5" },
				heading_6 = { style = "label", padding_left = " ", padding_right = " ", hl = "MarkviewHeading6" },
			},

			-- ── Code blocks ──────────────────────────────────────────
			-- Rendered with a background highlight and language label.
			-- min_width prevents narrow code blocks from looking odd.
			-- pad_amount adds internal padding for readability.
			code_blocks = {
				---@type boolean
				enable = true,
				---@type string Rendering style ("language" shows the lang label)
				style = "language",
				---@type string Highlight group for code block background
				hl = "MarkviewCode",
				---@type integer Minimum width in columns
				min_width = 60,
				---@type integer Internal padding (spaces)
				pad_amount = 2,
				---@type string Character used for padding
				pad_char = " ",
			},

			-- ── Horizontal rules ─────────────────────────────────────
			-- Rendered as a full-width line using the separator icon.
			-- Width adapts to terminal columns dynamically.
			horizontal_rules = {
				---@type boolean
				enable = true,
				parts = {
					{
						type = "repeating",
						--- Calculate repeat count based on terminal width.
						--- Subtracts 4 for margins and divides by 2 for
						--- the character width of the separator glyph.
						---@return integer count Number of repetitions
						repeat_amount = function()
							return math.floor((vim.o.columns - 4) / 2)
						end,
						text = icons.separator.Horizontal,
						hl = "Comment",
					},
				},
			},

			-- ── List items ───────────────────────────────────────────
			-- Each list marker type gets its own icon and highlight.
			-- indent_size controls nesting alignment.
			list_items = {
				---@type boolean
				enable = true,
				---@type integer Pixels per indent level
				indent_size = 2,
				---@type integer Shift width for nested items
				shift_width = 2,
				marker_minus = { add_padding = true, text = icons.ui.Circle, hl = "MarkviewListItemMinus" },
				marker_plus = { add_padding = true, text = icons.ui.Square, hl = "MarkviewListItemPlus" },
				marker_star = { add_padding = true, text = icons.ui.Dot, hl = "MarkviewListItemStar" },
			},
		},

		-- ═══════════════════════════════════════════════════════════════
		-- MARKDOWN RENDERING — INLINE ELEMENTS
		--
		-- Checkbox rendering with standard and Obsidian-compatible
		-- custom states. Each state maps a single character inside
		-- `- [X]` brackets to an icon and highlight group.
		-- ═══════════════════════════════════════════════════════════════
		markdown_inline = {
			---@type boolean
			enable = true,

			checkboxes = {
				---@type boolean
				enable = true,

				-- ── Standard states ──────────────────────────────
				--- Checked checkbox: `- [x] Task`
				checked = { text = icons.ui.Check, hl = "MarkviewCheckboxChecked" },
				--- Unchecked checkbox: `- [ ] Task`
				unchecked = { text = icons.ui.Square, hl = "MarkviewCheckboxUnchecked" },

				-- ── Custom states (Obsidian-compatible) ──────────
				---@type table[]
				custom = {
					--- In-progress: `- [/] Task`
					{ match_string = "/", text = icons.ui.Indicator, hl = "MarkviewCheckboxProgress" },
					--- Cancelled: `- [-] Task`
					{ match_string = "-", text = icons.ui.BoldClose, hl = "MarkviewCheckboxCancelled" },
					--- Starred/important: `- [*] Task`
					{ match_string = "*", text = icons.ui.Star, hl = "MarkviewCheckboxStar" },
					--- Question/needs-review: `- [?] Task`
					{ match_string = "?", text = icons.diagnostics.Hint, hl = "MarkviewCheckboxQuestion" },
					--- Informational: `- [i] Task`
					{ match_string = "i", text = icons.diagnostics.Info, hl = "MarkviewCheckboxInfo" },
				},
			},
		},

		-- ═══════════════════════════════════════════════════════════════
		-- LATEX RENDERING
		--
		-- Renders LaTeX math expressions inline:
		-- `$\sum_{i=0}^{n}$` → rendered as mathematical symbols.
		-- Requires the latex treesitter parser.
		-- ═══════════════════════════════════════════════════════════════
		latex = {
			---@type boolean
			enable = true,
		},

		-- ═══════════════════════════════════════════════════════════════
		-- HTML RENDERING
		--
		-- Renders common HTML entities and tags inline:
		-- `&amp;` → &, `<br>` → line break indicator, etc.
		-- ═══════════════════════════════════════════════════════════════
		html = {
			---@type boolean
			enable = true,
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- CONFIG
	--
	-- Post-setup hook: registers the <leader>m which-key group
	-- with a markdown icon so which-key shows a meaningful label
	-- when the user presses <leader>m and waits.
	-- ═══════════════════════════════════════════════════════════════════

	---@param _ table Plugin spec (unused)
	---@param opts table Resolved options from opts above
	config = function(_, opts)
		require("markview").setup(opts)

		-- ── Which-key group ──────────────────────────────────────────
		local wk_ok, wk = pcall(require, "which-key")
		if wk_ok then
			wk.add({
				{
					"<leader>m",
					group = icons.file.Markdown .. " Markdown",
					icon = { icon = icons.file.Markdown, color = "blue" },
				},
			})
		end
	end,
}
