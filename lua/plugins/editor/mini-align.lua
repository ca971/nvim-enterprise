---@file lua/plugins/editor/mini-align.lua
---@description Mini.align — enterprise-grade text alignment with registry, presets & Telescope picker
---@module "plugins.editor.mini-align"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.mini-align-registry  Alignment preset registration system (central API)
---@see core.keymaps               Keymap API used for generic alignment mappings
---@see core.icons                 Shared icon definitions for UI consistency
---@see langs.*                    Each lang module registers its own presets via the registry
---
---@see https://github.com/echasnovski/mini.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/mini-align.lua — Enterprise-grade text alignment         ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  mini.align (from mini.nvim monorepo)                            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Preset system (2-tier):                                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  Generic presets (always loaded — 7 presets):            │    │    ║
--- ║  │  │    eq_sign (=)  colon (:)  comma (,)  pipe (|)           │    │    ║
--- ║  │  │    arrows (=>/->) inline_comments (--)                   │    │    ║
--- ║  │  │    inline_comments_slash (//)                            │    │    ║
--- ║  │  │                                                          │    │    ║
--- ║  │  │  Language presets (lazy-loaded per filetype):            │    │    ║
--- ║  │  │    Registered by each langs/<lang>.lua on FileType       │    │    ║
--- ║  │  │    via core/mini-align-registry API                      │    │    ║
--- ║  │  │    e.g. python_dict, lua_table, rust_struct, etc.        │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Smart auto-detection flow (<leader>az):                         │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  1. Check line content for special patterns:             │    │    ║
--- ║  │  │     |  → markdown_table    &  → tex_tabular              │    │    ║
--- ║  │  │     := → helm_assign       => / -> → arrows              │    │    ║
--- ║  │  │     -- / // → inline_comments                            │    │    ║
--- ║  │  │  2. Check filetype default (registry.get_ft_default)     │    │    ║
--- ║  │  │  3. If no match → notify user to use manual `ga`         │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Telescope preset picker (<leader>ap):                           │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  • Context-aware: shows generic + current filetype       │    │    ║
--- ║  │  │  • Sorted by category then name                          │    │    ║
--- ║  │  │  • Shows icon, name, category, description, lang tag     │    │    ║
--- ║  │  │  • <CR> applies selected preset immediately              │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Visual mode hints (automatic):                                  │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  • On entering visual mode → detect best preset          │    │    ║
--- ║  │  │  • Show virtual text hint at EOL:                        │    │    ║
--- ║  │  │    "✏  eq_sign detected — gA to align"                   │    │    ║
--- ║  │  │  • Cleared automatically when leaving visual mode        │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Modifier keys (after ga / gA):                                  │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  s  → change split pattern    j  → cycle justification   │    │    ║
--- ║  │  │  t  → trim whitespace         m  → merge parts           │    │    ║
--- ║  │  │  f  → filter lines (pattern)  i  → ignore split pattern  │    │    ║
--- ║  │  │  p  → pair parts              <BS> → remove last modifier│    │    ║
--- ║  │  │  <CR> → confirm               <Esc> → cancel             │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  User commands:                                                  │    ║
--- ║  │  ├─ :AlignPreset <name>   Apply a named preset                   │    ║
--- ║  │  ├─ :AlignListPresets     List all loaded presets by category    │    ║
--- ║  │  ├─ :AlignSmart           Smart auto-detect alignment            │    ║
--- ║  │  ├─ :AlignInfo            Show context info for current buffer   │    ║
--- ║  │  └─ :AlignLangs           Language loading status dashboard      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Lualine component:                                              │    ║
--- ║  │  ├─ Visible only in visual mode                                  │    ║
--- ║  │  ├─ Shows "✏ ALIGN [ft:N]" when filetype presets available       │    ║
--- ║  │  └─ Exported via vim.g.mini_align_lualine                        │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  IMPORTANT: This file contains NO language-specific presets.             ║
--- ║  Each langs/<lang>.lua registers its own presets via the                 ║
--- ║  core.mini-align-registry API when the filetype is loaded.               ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Event-based loading (BufReadPost + BufNewFile + VeryLazy)             ║
--- ║  • Theme-adaptive highlights (re-applied on ColorScheme change)          ║
--- ║  • Virtual text hints only in visual mode (zero cost in normal mode)     ║
--- ║  • Telescope picker is context-aware (filters by current filetype)       ║
--- ║  • Icons from core/icons.lua (single source of truth)                    ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║  ┌─────────────────────────────────────────────────────────────────────┐ ║
--- ║  │  KEY          MODE   ACTION                     CONFLICT STATUS     │ ║
--- ║  │  ga           n, x   Align (no preview)         ✓ safe (mini own)   │ ║
--- ║  │  gA           n, x   Align with live preview    ✓ safe              │ ║
--- ║  │  <leader>ap   n, x   Preset picker (Telescope)  ✓ safe (a* owned)   │ ║
--- ║  │  <leader>az   n, x   Smart auto-detect          ✓ safe              │ ║
--- ║  │  <leader>a?   n, x   Cheatsheet                 ✓ safe              │ ║
--- ║  │  <leader>a=   n, x   Align on '='               ✓ safe              │ ║
--- ║  │  <leader>a:   n, x   Align on ':'               ✓ safe              │ ║
--- ║  │  <leader>a,   n, x   Align on ','               ✓ safe              │ ║
--- ║  │  <leader>a|   n, x   Align on '|'               ✓ safe              │ ║
--- ║  │  <leader>aA   n, x   Align arrows (=> / ->)     ✓ safe              │ ║
--- ║  │  <leader>ai   n, x   Align comments (--)        ✓ safe              │ ║
--- ║  │  <leader>aI   n, x   Align comments (//)        ✓ safe              │ ║
--- ║  └─────────────────────────────────────────────────────────────────────┘ ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if mini.align is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_plugin_enabled("mini_align") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

---@type Icons
local icons = require("core.icons")

---@type table Registry API for alignment preset management
local registry = require("core.mini-align-registry")

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — COLOR EXTRACTION
--
-- Utility functions for extracting foreground/background colors from
-- existing highlight groups. Used to create theme-adaptive custom
-- highlight groups that follow the user's colorscheme.
-- ═══════════════════════════════════════════════════════════════════════════

--- Extract the foreground color from a highlight group as a hex string.
---
--- ```lua
--- fg_of("Function")        -- → "#7aa2f7"
--- fg_of("NonExistentGroup") -- → nil
--- ```
---
---@param name string Highlight group name
---@return string|nil hex Foreground color as `#RRGGBB`, or `nil` if not set
---@private
local function fg_of(name)
	local ok, group = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok and group.fg then return string.format("#%06x", group.fg) end
	return nil
end

--- Extract the background color from a highlight group as a hex string.
---
--- ```lua
--- bg_of("CursorLine")      -- → "#292e42"
--- bg_of("NonExistentGroup") -- → nil
--- ```
---
---@param name string Highlight group name
---@return string|nil hex Background color as `#RRGGBB`, or `nil` if not set
---@private
local function bg_of(name)
	local ok, group = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok and group.bg then return string.format("#%06x", group.bg) end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — NOTIFICATION
--
-- Centralized notification helper with consistent formatting.
-- All mini.align notifications use the pencil icon and "mini.align" title.
-- ═══════════════════════════════════════════════════════════════════════════

--- Send a notification with the "mini.align" title and icon.
---
--- ```lua
--- notify("Aligned 5 lines", vim.log.levels.INFO)
--- notify("No preset detected", vim.log.levels.WARN, icons.ui.Lightbulb)
--- ```
---
---@param msg string Notification message body
---@param level integer `vim.log.levels.*` constant
---@param icon? string Override icon (default: `icons.ui.Pencil`)
---@return nil
---@private
local function notify(msg, level, icon)
	level = level or vim.log.levels.INFO
	icon = icon or icons.ui.Pencil
	vim.notify(string.format("%s  %s", icon, msg), level, { title = icons.ui.Pencil .. "  mini.align" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — HIGHLIGHT MANAGEMENT
--
-- Theme-adaptive highlight groups for mini.align visual feedback.
-- Colors are extracted from the current colorscheme's existing groups
-- to ensure consistency. Re-applied on ColorScheme change via autocmd.
-- ═══════════════════════════════════════════════════════════════════════════

--- Apply all mini.align custom highlight groups.
---
--- Creates 7 highlight groups based on the current colorscheme:
--- - `MiniAlignPreview`   — live preview overlay (Function fg + CursorLine bg)
--- - `MiniAlignDelimiter` — split delimiter character (Error fg, bold+underline)
--- - `MiniAlignColumn`    — aligned column content (String fg + CursorLine bg)
--- - `MiniAlignActive`    — active mode indicator (Warn fg, bold+italic)
--- - `MiniAlignHint`      — virtual text hints (Comment fg, italic)
--- - `MiniAlignSuccess`   — success feedback (String fg, bold)
--- - `MiniAlignTarget`    — target highlight (Special fg + TabLineSel bg)
---
--- Each group has hardcoded fallback colors for themes that don't
--- define the expected source groups.
---
---@return nil
---@private
local function apply_highlights()
	local hl = vim.api.nvim_set_hl

	hl(0, "MiniAlignPreview", {
		fg = fg_of("Function") or "#7aa2f7",
		bg = bg_of("CursorLine") or "#292e42",
		bold = true,
	})
	hl(0, "MiniAlignDelimiter", {
		fg = fg_of("DiagnosticError") or "#f7768e",
		bold = true,
		underline = true,
	})
	hl(0, "MiniAlignColumn", {
		fg = fg_of("String") or "#9ece6a",
		bg = bg_of("CursorLine") or "#292e42",
	})
	hl(0, "MiniAlignActive", {
		fg = fg_of("DiagnosticWarn") or "#e0af68",
		bold = true,
		italic = true,
	})
	hl(0, "MiniAlignHint", {
		fg = fg_of("Comment") or "#565f89",
		italic = true,
	})
	hl(0, "MiniAlignSuccess", {
		fg = fg_of("String") or "#9ece6a",
		bold = true,
	})
	hl(0, "MiniAlignTarget", {
		fg = fg_of("Special") or "#7dcfff",
		bg = bg_of("TabLineSel") or "#3b4261",
		bold = true,
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS — MODULE ACCESS
--
-- Safe accessor for the mini.align module. Used by modifier callbacks
-- that need access to `gen_step.*` functions.
-- ═══════════════════════════════════════════════════════════════════════════

--- Safely require the mini.align module.
---
--- Returns `nil` if the module is not loaded (should never happen
--- inside modifier callbacks, but defensive coding is good practice).
---
---@return table|nil module The mini.align module, or `nil` if unavailable
---@private
local function get_mini_align()
	local ok, ma = pcall(require, "mini.align")
	if not ok then return nil end
	return ma
end

-- ═══════════════════════════════════════════════════════════════════════════
-- GENERIC PRESETS
--
-- Always-available presets that work across all filetypes.
-- Language-specific presets are registered by each langs/<lang>.lua
-- via core/mini-align-registry when the filetype is first opened.
--
-- Categories: "generic" (these), "systems", "jvm", "scripting",
-- "functional", "web", "data", "devops", "domain"
-- ═══════════════════════════════════════════════════════════════════════════

registry.register_many({
	eq_sign = {
		description = "Align on '=' (generic assignments)",
		icon = icons.ui.Pencil,
		split_pattern = "=",
		category = "generic",
	},
	colon = {
		description = "Align on ':' (generic key-value)",
		icon = icons.ui.Dot,
		split_pattern = ":",
		category = "generic",
	},
	comma = {
		description = "Align on ',' (arguments / array items)",
		icon = icons.ui.Dot,
		split_pattern = ",",
		category = "generic",
	},
	arrows = {
		description = "Align fat '=>' and thin '->' arrows",
		icon = icons.arrows.SmallArrowRight,
		split_pattern = "=>?",
		category = "generic",
	},
	pipe = {
		description = "Align '|' separators (tables / unions)",
		icon = icons.ui.Pencil,
		split_pattern = "|",
		category = "generic",
	},
	inline_comments = {
		description = "Align inline comments ('--' / '//')",
		icon = icons.ui.Comment,
		split_pattern = "%-%-",
		category = "generic",
	},
	inline_comments_slash = {
		description = "Align inline '//' comments",
		icon = icons.ui.Comment,
		split_pattern = "//",
		category = "generic",
	},
})

-- ═══════════════════════════════════════════════════════════════════════════
-- SMART AUTO-DETECTION
--
-- Analyses the current line content and filetype to determine the
-- best alignment preset. Used by <leader>az and the :AlignSmart command.
-- ═══════════════════════════════════════════════════════════════════════════

--- Auto-detect the best alignment preset for the current context.
---
--- Detection order (first match wins):
--- 1. Line contains `|` and `markdown_table` preset exists → markdown_table
--- 2. Line contains `&` and `tex_tabular` preset exists → tex_tabular
--- 3. Line contains `:=` and `helm_assign` preset exists → helm_assign
--- 4. Line contains `=>` or `->` → arrows
--- 5. Line contains `--` or `//` comments → inline_comments
--- 6. Filetype has a registered default preset → that preset
--- 7. No match → `nil`
---
---@return string|nil preset_name Name of the detected preset, or `nil`
---@private
local function auto_detect_preset()
	local line = vim.api.nvim_get_current_line()

	-- ── Content-based detection (highest priority) ───────────
	if line:match("|") and registry.is_registered("markdown_table") then return "markdown_table" end
	if line:match("&") and registry.is_registered("tex_tabular") then return "tex_tabular" end
	if line:match(":=") and registry.is_registered("helm_assign") then return "helm_assign" end
	if line:match("=>") or line:match("->") then return "arrows" end
	if line:match("%s+%-%-") or line:match("%s+//") then return "inline_comments" end

	-- ── Filetype default (lowest priority) ───────────────────
	local ft = vim.bo.filetype
	local ft_default = registry.get_ft_default(ft)
	if ft_default and registry.is_registered(ft_default) then return ft_default end

	return nil
end

--- Run smart alignment: auto-detect and apply the best preset.
---
--- If no preset is detected, notifies the user to use manual `ga`
--- alignment instead.
---
---@return nil
---@private
local function smart_align()
	local preset_name = auto_detect_preset()
	if not preset_name then
		notify("No preset detected — use 'ga' for manual alignment.", vim.log.levels.WARN, icons.ui.Lightbulb)
		return
	end
	registry.apply_preset(preset_name)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TELESCOPE PRESET PICKER
--
-- Context-aware Telescope picker that shows all available presets
-- filtered by the current filetype. Sorted by category then name.
-- Falls back to vim.ui.select if Telescope is not available.
-- ═══════════════════════════════════════════════════════════════════════════

--- Category labels for human-readable display in the picker.
---@type table<string, string>
---@private
local CATEGORY_LABELS = {
	generic = "Generic",
	systems = "Systems / Low-level",
	jvm = "JVM / Managed",
	scripting = "Scripting / Dynamic",
	functional = "Functional",
	web = "Web / Frontend",
	data = "Data / Config",
	devops = "DevOps / Infrastructure",
	domain = "Domain-specific",
}

--- Open the context-aware alignment preset picker.
---
--- Shows all presets relevant to the current filetype (generic +
--- filetype-specific). Each entry displays:
--- `<icon>  <name>  [<category>]  <description>  {<lang>}`
---
--- Selecting a preset applies it immediately to the current
--- selection or motion.
---
---@return nil
---@private
local function open_preset_picker()
	local ok_tel, pickers = pcall(require, "telescope.pickers")
	local ok_fin, finders = pcall(require, "telescope.finders")
	local ok_cfg, conf = pcall(require, "telescope.config")
	local ok_act, actions = pcall(require, "telescope.actions")
	local ok_ast, act_state = pcall(require, "telescope.actions.state")

	if not (ok_tel and ok_fin and ok_cfg and ok_act and ok_ast) then
		notify("Telescope not available.", vim.log.levels.WARN, icons.ui.Telescope)
		return
	end

	local ft = vim.bo.filetype
	local relevant_presets = registry.get_for_filetype(ft)

	---@type table[]
	local preset_list = {}
	for name, preset in pairs(relevant_presets) do
		preset_list[#preset_list + 1] = {
			name = name,
			description = preset.description,
			icon = preset.icon,
			pattern = preset.split_pattern,
			category = preset.category,
			lang = preset.lang,
		}
	end
	table.sort(preset_list, function(a, b)
		if a.category ~= b.category then return a.category < b.category end
		return a.name < b.name
	end)

	pickers
		.new({}, {
			prompt_title = string.format(
				"%s  Alignment Presets [%s] (%d available)",
				icons.ui.Pencil,
				ft ~= "" and ft or "any",
				#preset_list
			),
			finder = finders.new_table({
				results = preset_list,
				---@param entry table Preset entry data
				---@return table Telescope entry
				entry_maker = function(entry)
					local cat_label = CATEGORY_LABELS[entry.category] or entry.category
					local lang_tag = entry.lang and string.format(" {%s}", entry.lang) or ""
					return {
						value = entry,
						display = string.format(
							"%s  %-28s [%-20s]  %s%s",
							entry.icon,
							entry.name,
							cat_label,
							entry.description,
							lang_tag
						),
						ordinal = entry.category .. " " .. entry.name .. " " .. entry.description,
					}
				end,
			}),
			sorter = conf.values.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = act_state.get_selected_entry()
					if not selection then return end
					registry.apply_preset(selection.value.name)
				end)
				return true
			end,
		})
		:find()
end

-- ═══════════════════════════════════════════════════════════════════════════
-- VIRTUAL TEXT HINTS
--
-- Shows contextual alignment hints as virtual text at EOL when the
-- user enters visual mode. Hints are cleared automatically when
-- leaving visual mode. Uses a dedicated namespace to avoid conflicts.
-- ═══════════════════════════════════════════════════════════════════════════

---@type integer Extmark namespace for alignment hints
local ns_id = vim.api.nvim_create_namespace("mini_align_hints")

--- Show a virtual text hint at the end of a specific line.
---
--- Clears any existing hints before showing the new one to prevent
--- stale hints from accumulating.
---
---@param bufnr integer Buffer number
---@param line_nr integer 0-indexed line number
---@param hint string Hint text to display
---@return nil
---@private
local function show_virtual_hint(bufnr, line_nr, hint)
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
	vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_nr, 0, {
		virt_text = { { "  " .. icons.ui.Pencil .. "  " .. hint, "MiniAlignHint" } },
		virt_text_pos = "eol",
		hl_mode = "combine",
	})
end

--- Clear all virtual text hints from a buffer.
---
---@param bufnr integer Buffer number
---@return nil
---@private
local function clear_virtual_hints(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP REGISTRATION
-- ═══════════════════════════════════════════════════════════════════════════

--- Register the `<leader>a` which-key group with alignment icon.
---
--- Uses pcall to gracefully handle which-key not being loaded.
---
---@return nil
---@private
local function register_which_key_group()
	local ok, wk = pcall(require, "which-key")
	if not ok then return end
	wk.add({
		{
			"<leader>a",
			group = "Align",
			icon = { icon = icons.ui.Pencil, color = "orange" },
			mode = { "n", "x" },
		},
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAP SETUP
--
-- Registers all generic alignment keymaps under <leader>a.
-- Language-specific keymaps are registered by each langs/<lang>.lua.
-- ═══════════════════════════════════════════════════════════════════════════

--- Register all generic alignment keymaps.
---
--- Keymaps registered:
--- - `<leader>ap` — Telescope preset picker
--- - `<leader>az` — Smart auto-detect alignment
--- - `<leader>a?` — Cheatsheet (shows all modifiers and presets)
--- - `<leader>a=` — Align on `=`
--- - `<leader>a:` — Align on `:`
--- - `<leader>a,` — Align on `,`
--- - `<leader>a|` — Align on `|`
--- - `<leader>aA` — Align arrows (`=>` / `->`)
--- - `<leader>ai` — Align inline comments (`--`)
--- - `<leader>aI` — Align inline comments (`//`)
---
---@return nil
---@private
local function setup_keymaps()
	local core_keys = require("core.keymaps")

	--- Set a keymap via the core keymaps API.
	---@param modes string|string[] Vim mode(s)
	---@param lhs string Left-hand side
	---@param rhs function Right-hand side
	---@param desc string Keymap description
	local function map(modes, lhs, rhs, desc)
		core_keys.map(modes, lhs, rhs, { desc = desc }, "mini-align")
	end

	-- ── Picker & smart ───────────────────────────────────────────
	map({ "n", "x" }, "<leader>ap", open_preset_picker, icons.ui.Telescope .. " Alignment preset picker")
	map({ "n", "x" }, "<leader>az", smart_align, icons.misc.Robot .. " Smart auto-detect alignment")

	-- ── Cheatsheet ───────────────────────────────────────────────
	map({ "n", "x" }, "<leader>a?", function()
		local sep = string.rep("-", 58)
		local ft = vim.bo.filetype
		local ft_presets = registry.get_ft_presets_only(ft)
		local ft_count = vim.tbl_count(ft_presets)
		local ft_names = vim.tbl_keys(ft_presets)
		table.sort(ft_names)

		local loaded = registry.get_loaded_languages()
		local pending = registry.get_pending_languages()

		---@type string[]
		local lines = {
			icons.ui.Pencil .. "  mini.align Cheatsheet",
			sep,
			"  ga  " .. icons.arrows.SmallArrowRight .. "  Align (no preview)",
			"  gA  " .. icons.arrows.SmallArrowRight .. "  Align (live preview)",
			"",
			"  Modifiers after ga / gA:",
			"  s  Change split pattern      j  Cycle justification",
			"  t  Trim whitespace           m  Merge parts",
			"  f  Filter lines              i  Ignore split pattern",
			"  p  Pair parts                <BS>  Remove last modifier",
			"  <CR>  Confirm  |  <Esc>  Cancel",
			"",
			"  <leader>ap  Preset picker (Telescope)",
			"  <leader>az  Smart auto-detect",
			"  :AlignPreset <name>  Apply named preset",
			"  :AlignListPresets   List loaded presets",
			"  :AlignLangs        Language loading status",
		}

		if ft_count > 0 then
			lines[#lines + 1] = ""
			lines[#lines + 1] = string.format("  [%s] presets (%d):", ft, ft_count)
			for _, name in ipairs(ft_names) do
				local p = ft_presets[name]
				lines[#lines + 1] = string.format("    %s  %-24s  %s", p.icon, name, p.description)
			end
		end

		lines[#lines + 1] = ""
		lines[#lines + 1] = string.format(
			"  Loaded: %d generic + %d lang (%d langs active, %d pending)",
			registry.count_generic(),
			registry.count_lang(),
			#loaded,
			#pending
		)
		lines[#lines + 1] = sep
		notify(table.concat(lines, "\n"), vim.log.levels.INFO, icons.ui.Note)
	end, icons.ui.Note .. " mini.align cheatsheet")

	-- ── Quick-access presets ─────────────────────────────────────
	map({ "n", "x" }, "<leader>a=", registry.make_align_fn("eq_sign"), icons.ui.Pencil .. " Align on '='")
	map({ "n", "x" }, "<leader>a:", registry.make_align_fn("colon"), icons.ui.Dot .. " Align on ':'")
	map({ "n", "x" }, "<leader>a,", registry.make_align_fn("comma"), icons.ui.Dot .. " Align on ','")
	map({ "n", "x" }, "<leader>a|", registry.make_align_fn("pipe"), icons.ui.Pencil .. " Align on '|'")
	map({ "n", "x" }, "<leader>aA", registry.make_align_fn("arrows"), icons.arrows.SmallArrowRight .. " Align arrows")
	map(
		{ "n", "x" },
		"<leader>ai",
		registry.make_align_fn("inline_comments"),
		icons.ui.Comment .. " Inline comments (--)"
	)
	map(
		{ "n", "x" },
		"<leader>aI",
		registry.make_align_fn("inline_comments_slash"),
		icons.ui.Comment .. " Inline comments (//)"
	)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- USER COMMANDS
--
-- Ex commands for command-line access to alignment features.
-- All commands include tab-completion where applicable.
-- ═══════════════════════════════════════════════════════════════════════════

--- Register all `:Align*` user commands.
---
--- Commands:
--- - `:AlignPreset <name>` — Apply a named preset (tab-complete)
--- - `:AlignListPresets`   — List all presets grouped by category
--- - `:AlignSmart`         — Run smart auto-detect alignment
--- - `:AlignInfo`          — Show context info for current buffer
--- - `:AlignLangs`         — Show language loading status dashboard
---
---@return nil
---@private
local function setup_user_commands()
	-- ── :AlignPreset <name> ──────────────────────────────────────
	vim.api.nvim_create_user_command("AlignPreset", function(opts)
		local name = opts.args
		if not registry.is_registered(name) then
			local available = vim.tbl_keys(registry.get_all())
			table.sort(available)
			notify(
				string.format(
					"Unknown preset '%s'.\nCurrently loaded (%d):\n  %s",
					name,
					#available,
					table.concat(available, "\n  ")
				),
				vim.log.levels.ERROR,
				icons.diagnostics.Error
			)
			return
		end
		registry.apply_preset(name)
	end, {
		nargs = 1,
		desc = "Apply a named mini.align preset",
		complete = function()
			local names = vim.tbl_keys(registry.get_all())
			table.sort(names)
			return names
		end,
	})

	-- ── :AlignListPresets ────────────────────────────────────────
	vim.api.nvim_create_user_command("AlignListPresets", function()
		local all = registry.get_all()
		---@type table<string, table[]>
		local by_cat = {}
		for name, p in pairs(all) do
			local cat = p.category or "other"
			if not by_cat[cat] then by_cat[cat] = {} end
			by_cat[cat][#by_cat[cat] + 1] = {
				name = name,
				icon = p.icon,
				description = p.description,
				pattern = p.split_pattern,
				lang = p.lang,
			}
		end

		---@type string[]
		local lines = {
			icons.ui.Pencil .. "  mini.align — Loaded Presets",
			string.rep("-", 68),
			"",
		}
		local cats = vim.tbl_keys(by_cat)
		table.sort(cats)
		for _, cat in ipairs(cats) do
			local entries = by_cat[cat]
			table.sort(entries, function(a, b)
				return a.name < b.name
			end)
			lines[#lines + 1] = string.format("  [%s]  (%d)", cat:upper(), #entries)
			for _, p in ipairs(entries) do
				local lang_tag = p.lang and string.format(" {%s}", p.lang) or ""
				lines[#lines + 1] = string.format("    %s  %-28s  %s%s", p.icon, p.name, p.description, lang_tag)
			end
			lines[#lines + 1] = ""
		end
		lines[#lines + 1] = string.format(
			"  Total: %d presets (%d generic + %d language)",
			registry.count(),
			registry.count_generic(),
			registry.count_lang()
		)
		notify(table.concat(lines, "\n"), vim.log.levels.INFO, icons.ui.List)
	end, {
		nargs = 0,
		desc = "List all currently loaded mini.align presets",
	})

	-- ── :AlignSmart ──────────────────────────────────────────────
	vim.api.nvim_create_user_command("AlignSmart", function()
		smart_align()
	end, {
		nargs = 0,
		desc = "Smart auto-detect alignment",
	})

	-- ── :AlignInfo ───────────────────────────────────────────────
	vim.api.nvim_create_user_command("AlignInfo", function()
		local ft = vim.bo.filetype
		local preset_name = auto_detect_preset()
		local preset = preset_name and registry.get(preset_name)
		local ft_only = registry.get_ft_presets_only(ft)
		local ft_all = registry.get_for_filetype(ft)
		local loaded = registry.get_loaded_languages()
		local pending = registry.get_pending_languages()

		---@type string[]
		local lines = {
			icons.ui.Pencil .. "  mini.align Context",
			string.rep("-", 54),
			"  Filetype       : " .. (ft ~= "" and ft or "(none)"),
			"  Detected       : " .. (preset and (preset.icon .. "  " .. preset_name) or "none"),
			"  Category       : " .. (preset and preset.category or "N/A"),
			"  Pattern        : " .. (preset and preset.split_pattern or "N/A"),
			"  FT presets     : " .. vim.tbl_count(ft_only) .. " language-specific",
			"  Available      : " .. vim.tbl_count(ft_all) .. " (generic + filetype)",
			"  Total loaded   : " .. registry.count() .. " in registry",
			string.rep("-", 54),
			"  Langs loaded   : " .. (#loaded > 0 and table.concat(loaded, ", ") or "(none)"),
			"  Langs pending  : " .. (#pending > 0 and tostring(#pending) .. " languages" or "(none)"),
			"  Enabled total  : " .. #registry.get_enabled_languages(),
			string.rep("-", 54),
		}
		notify(table.concat(lines, "\n"), vim.log.levels.INFO, icons.ui.Note)
	end, {
		nargs = 0,
		desc = "Show mini.align context info",
	})

	-- ── :AlignLangs ──────────────────────────────────────────────
	vim.api.nvim_create_user_command("AlignLangs", function()
		local enabled = registry.get_enabled_languages()
		local loaded = registry.get_loaded_languages()
		---@type table<string, boolean>
		local loaded_set = {}
		for _, l in ipairs(loaded) do
			loaded_set[l] = true
		end

		---@type string[]
		local lines = {
			icons.ui.Pencil .. "  mini.align — Language Status",
			string.rep("-", 58),
			"",
		}

		-- ── Loaded languages ─────────────────────────────────
		if #loaded > 0 then
			lines[#lines + 1] = string.format("  %s  LOADED (%d):", icons.ui.Check, #loaded)
			for _, lang in ipairs(loaded) do
				---@type string[]
				local lang_presets = {}
				for name, p in pairs(registry.get_all()) do
					if p.lang == lang then lang_presets[#lang_presets + 1] = name end
				end
				table.sort(lang_presets)
				lines[#lines + 1] = string.format(
					"    %s  %-16s  %d preset(s): %s",
					icons.ui.Check,
					lang,
					#lang_presets,
					table.concat(lang_presets, ", ")
				)
			end
			lines[#lines + 1] = ""
		end

		-- ── Pending languages ────────────────────────────────
		---@type string[]
		local pending = {}
		for _, lang in ipairs(enabled) do
			if not loaded_set[lang] then pending[#pending + 1] = lang end
		end

		if #pending > 0 then
			lines[#lines + 1] = string.format("  %s  PENDING (%d — open a file to load):", icons.ui.Clock, #pending)
			for i = 1, #pending, 4 do
				---@type string[]
				local chunk = {}
				for j = i, math.min(i + 3, #pending) do
					chunk[#chunk + 1] = string.format("%-16s", pending[j])
				end
				lines[#lines + 1] = "    " .. table.concat(chunk, "  ")
			end
			lines[#lines + 1] = ""
		end

		lines[#lines + 1] = string.rep("-", 58)
		lines[#lines + 1] = string.format(
			"  Summary: %d enabled, %d loaded, %d pending, %d total presets",
			#enabled,
			#loaded,
			#pending,
			registry.count()
		)
		notify(table.concat(lines, "\n"), vim.log.levels.INFO, icons.ui.List)
	end, {
		nargs = 0,
		desc = "Show mini.align language loading status",
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- AUTOCOMMANDS
--
-- 1. ColorScheme: re-apply custom highlights when theme changes
-- 2. ModeChanged → visual: show alignment hint at EOL
-- 3. ModeChanged → non-visual: clear alignment hints
-- ═══════════════════════════════════════════════════════════════════════════

--- Register all mini.align autocommands.
---
---@return nil
---@private
local function setup_autocommands()
	local group = vim.api.nvim_create_augroup("MiniAlign_Autocmds", { clear = true })

	-- ── Re-apply highlights on colorscheme change ────────────────
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		pattern = "*",
		desc = "Re-apply mini.align highlights after colorscheme change",
		callback = apply_highlights,
	})

	-- ── Show hint when entering visual mode ──────────────────────
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		pattern = "*:[vV\x16]*",
		desc = "Show mini.align hint when entering visual mode",
		callback = function()
			local bufnr = vim.api.nvim_get_current_buf()
			local preset_name = auto_detect_preset()
			if not preset_name then return end
			local preset = registry.get(preset_name)
			if not preset then return end
			show_virtual_hint(bufnr, vim.fn.line(".") - 1, preset.icon .. "  " .. preset_name .. " detected — gA to align")
		end,
	})

	-- ── Clear hints when leaving visual mode ─────────────────────
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		pattern = "[vV\x16]*:*",
		desc = "Clear mini.align hints when leaving visual mode",
		callback = function()
			clear_virtual_hints(vim.api.nvim_get_current_buf())
		end,
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LUALINE COMPONENT
--
-- Provides a statusline component that shows alignment info in visual mode.
-- Exported via `vim.g.mini_align_lualine` for consumption by lualine config.
-- ═══════════════════════════════════════════════════════════════════════════

--- Create a lualine component table for alignment mode indicator.
---
--- The component:
--- - Is only visible in visual mode (v, V, <C-V>)
--- - Shows `"✏ ALIGN [ft:N]"` when filetype presets are available
--- - Shows `"✏ ALIGN"` otherwise
--- - Uses DiagnosticWarn foreground color for visibility
---
---@return table component Lualine component specification
---@private
local function make_lualine_component()
	return {
		function()
			local ft = vim.bo.filetype
			local ft_count = vim.tbl_count(registry.get_ft_presets_only(ft))
			if ft_count > 0 then return string.format("%s ALIGN [%s:%d]", icons.ui.Pencil, ft, ft_count) end
			return icons.ui.Pencil .. " ALIGN"
		end,
		color = { fg = fg_of("DiagnosticWarn") or "#e0af68", bold = true },
		cond = function()
			local m = vim.fn.mode()
			return m == "v" or m == "V" or m == "\22"
		end,
	}
end

--- Export the lualine component factory to a global variable.
---
--- This allows the lualine configuration to retrieve the component
--- without requiring this module directly:
--- ```lua
--- -- In lualine config:
--- local align_component = vim.g.mini_align_lualine()
--- ```
---
---@return nil
---@private
local function export_lualine_component()
	vim.g.mini_align_lualine = function()
		return make_lualine_component()
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPEC
--
-- Loading strategy:
-- ┌────────────────────┬──────────────────────────────────────────────┐
-- │ Trigger            │ Details                                      │
-- ├────────────────────┼──────────────────────────────────────────────┤
-- │ event              │ BufReadPost, BufNewFile, VeryLazy            │
-- │                    │ (loads early so `ga`/`gA` are always ready)  │
-- │ dependencies       │ telescope.nvim (optional, for preset picker) │
-- │                    │ which-key.nvim (optional, for group label)   │
-- └────────────────────┴──────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec[]
return {
	{
		"echasnovski/mini.nvim",
		name = "mini.align",
		version = false,

		-- ═══════════════════════════════════════════════════════════════
		-- LAZY LOADING STRATEGY
		--
		-- Event-based loading ensures `ga` / `gA` are available as
		-- soon as any buffer is opened. Cannot use keys-only because
		-- mini.align's `ga`/`gA` mappings are set during setup().
		-- ═══════════════════════════════════════════════════════════════
		event = { "BufReadPost", "BufNewFile", "VeryLazy" },

		dependencies = {
			{ "nvim-telescope/telescope.nvim", optional = true },
			{ "folke/which-key.nvim", optional = true },
		},

		-- ═══════════════════════════════════════════════════════════════
		-- CONFIG
		--
		-- Setup order:
		-- 1. Apply theme-adaptive highlights
		-- 2. Configure mini.align with modifiers and options
		-- 3. Register which-key group
		-- 4. Setup generic keymaps
		-- 5. Setup autocommands (colorscheme, visual hints)
		-- 6. Register user commands
		-- 7. Export lualine component
		-- ═══════════════════════════════════════════════════════════════
		config = function()
			-- ── 1. Highlights ────────────────────────────────────────
			apply_highlights()

			-- ── 2. Mini.align setup ──────────────────────────────────
			require("mini.align").setup({
				-- Core mappings (NOT remapped — these are standard mini.align)
				mappings = {
					start = "ga",
					start_with_preview = "gA",
				},

				-- ── Interactive modifiers ────────────────────────
				-- These keys are active AFTER pressing `ga` or `gA`,
				-- while the alignment operation is pending.
				modifiers = {
					-- Change split pattern interactively
					["s"] = function(_, opts)
						local input = MiniAlign.user_input(icons.ui.Search .. "  Split pattern: ")
						if input == nil then return end
						opts.split_pattern = input
					end,

					-- Cycle justification: left → right → center → none → left
					["j"] = function(_, opts)
						---@type table<string, string>
						local cycle = { left = "right", right = "center", center = "none", none = "left" }
						opts.justify_side = cycle[opts.justify_side] or "left"
						---@type table<string, string>
						local icon_map = {
							left = icons.ui.BoldArrowLeft,
							right = icons.ui.BoldArrowRight,
							center = "|",
							none = icons.ui.Close,
						}
						notify(
							string.format("Justification -> %s  %s", icon_map[opts.justify_side] or "?", opts.justify_side),
							vim.log.levels.INFO,
							icons.ui.Pencil
						)
					end,

					-- Add trim whitespace step
					["t"] = function(steps)
						local ma = get_mini_align()
						if not ma then return end
						table.insert(steps.pre_justify, ma.gen_step.trim())
						notify("Trim whitespace enabled", vim.log.levels.INFO, icons.ui.BoldClose)
					end,

					-- Add pair parts step
					["p"] = function(steps)
						local ma = get_mini_align()
						if not ma then return end
						table.insert(steps.pre_justify, ma.gen_step.pair())
						notify("Pair parts enabled", vim.log.levels.INFO, icons.ui.Code)
					end,

					-- Add filter lines step (Lua pattern)
					["f"] = function(steps)
						local input = MiniAlign.user_input(icons.ui.Search .. "  Filter (Lua pattern): ")
						if not input or input == "" then return end
						local ma = get_mini_align()
						if not ma then return end
						table.insert(steps.pre_justify, ma.gen_step.filter(input))
						notify(string.format("Filter: %s", input), vim.log.levels.INFO, icons.ui.Search)
					end,

					-- Add ignore split pattern step
					["i"] = function(steps)
						local input = MiniAlign.user_input(icons.ui.Search .. "  Ignore split pattern: ")
						if not input or input == "" then return end
						local ma = get_mini_align()
						if not ma then return end
						table.insert(steps.pre_justify, ma.gen_step.ignore_split({ input }))
						notify(string.format("Ignoring '%s' in split", input), vim.log.levels.INFO, icons.diagnostics.Info)
					end,

					-- Add merge delimiter step
					["m"] = function(steps)
						local input = MiniAlign.user_input(icons.ui.Pencil .. "  Merge delimiter: ")
						if input == nil then return end
						local ma = get_mini_align()
						if not ma then return end
						table.insert(steps.pre_justify, ma.gen_step.merge(input))
						notify(string.format("Merge delimiter: '%s'", input), vim.log.levels.INFO, icons.ui.Code)
					end,

					-- Remove last modifier (backspace)
					["\b"] = function(steps)
						if #steps.pre_justify > 0 then
							table.remove(steps.pre_justify)
							notify("Last modifier removed", vim.log.levels.WARN, icons.ui.BoldClose)
						end
					end,
				},

				-- ── Default options ──────────────────────────────
				options = {
					split_pattern = "",
					justify_side = "left",
					merge_delimiter = "",
				},

				-- ── Pipeline steps ──────────────────────────────
				steps = {
					pre_split = {},
					split = nil,
					pre_justify = {},
					justify = nil,
					pre_merge = {},
					merge = nil,
				},

				silent = false,
			})

			-- ── 3–7. Post-setup initialization ───────────────────────
			register_which_key_group()
			setup_keymaps()
			setup_autocommands()
			setup_user_commands()
			export_lualine_component()
		end,
	},
}
