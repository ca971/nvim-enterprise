---@file lua/plugins/editor/neo-tree.lua
---@description Neo-tree — pro-grade file explorer with git awareness and rich integrations
---@module "plugins.editor.neo-tree"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.editor.oil       Lightweight file manager (complementary)
---@see plugins.editor.telescope  Telescope integration for find/grep in directory
---@see plugins.editor.diffview   Diffview integration for git log per file
---@see https://github.com/nvim-neo-tree/neo-tree.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════╗
--- ║  plugins/editor/neo-tree.lua — Pro-grade file explorer               ║
--- ║                                                                      ║
--- ║  Architecture:                                                       ║
--- ║  ┌─────────────────────────────────────────────────────────────┐     ║
--- ║  │  neo-tree.nvim (v3)                                         │     ║
--- ║  │                                                             │     ║
--- ║  │  Sources:                                                   │     ║
--- ║  │  ├─ filesystem       File tree with git status overlay      │     ║
--- ║  │  ├─ buffers          Open buffer list                       │     ║
--- ║  │  ├─ git_status       Staged/unstaged/untracked view         │     ║
--- ║  │  └─ document_symbols LSP symbol tree (outline)              │     ║
--- ║  │                                                             │     ║
--- ║  │  Custom actions:                                            │     ║
--- ║  │  ├─ Trash-safe delete (macOS/Linux, graceful fallback)      │     ║
--- ║  │  ├─ File info popup (size, perms, dates, line count)        │     ║
--- ║  │  ├─ Telescope find/grep scoped to directory                 │     ║
--- ║  │  ├─ Toggle executable permission (chmod ±x)                 │     ║
--- ║  │  ├─ Git log per file (diffview → telescope → terminal)      │     ║
--- ║  │  ├─ Copy file content / path variants to clipboard          │     ║
--- ║  │  ├─ System open (platform-adaptive)                         │     ║
--- ║  │  ├─ Diff file against current buffer                        │     ║
--- ║  │  ├─ Open terminal in directory context                      │     ║
--- ║  │  └─ Smart create with template detection                    │     ║
--- ║  │                                                             │     ║
--- ║  │  Integrations:                                              │     ║
--- ║  │  ├─ window-picker    Targeted splits                        │     ║
--- ║  │  ├─ image.nvim       Preview (kitty/wezterm/iTerm2)         │     ║
--- ║  │  ├─ mini.icons       File type icons                        │     ║
--- ║  │  └─ nui.nvim         UI components                          │     ║
--- ║  └─────────────────────────────────────────────────────────────┘     ║
--- ║                                                                      ║
--- ║  Optimizations:                                                      ║
--- ║  • Lazy-loaded via `Neotree` cmd + `<leader>e*` keymaps              ║
--- ║  • Directory hijack replaces netrw (BufEnter once)                   ║
--- ║  • Theme-adaptive highlights via ColorScheme autocmd                 ║
--- ║  • Platform detection imported once (not per-action)                 ║
--- ║  • O(1) close-key lookup in info popup                               ║
--- ║  • Auto-refresh on focus, git ops, and file writes                   ║
--- ║  • Comprehensive nesting rules (30+ file associations)               ║
--- ║                                                                      ║
--- ║  Global keymaps:                                                     ║
--- ║    <leader>ee   Toggle file explorer (left sidebar)        (n)       ║
--- ║    <leader>eE   Toggle float explorer                      (n)       ║
--- ║    <leader>ef   Reveal current file in explorer            (n)       ║
--- ║    <leader>eg   Git status explorer                        (n)       ║
--- ║    <leader>eb   Buffer explorer                            (n)       ║
--- ║    <leader>ed   Document symbols explorer                  (n)       ║
--- ╚══════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════
local settings = require("core.settings")
if not settings:is_plugin_enabled("neo_tree") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════
---@type Icons
local icons = require("core.icons")
---@type fun(name: string): integer
local augroup = require("core.utils").augroup
---@type PlatformInfo
local platform = require("core.platform")

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════════

--- Maximum file size (in bytes) for content operations (copy, line count).
--- Prevents accidental clipboard flooding or slow reads on large files.
---@type integer
---@private
local MAX_FILE_SIZE = 10 * 1024 * 1024 -- 10 MB

--- Filetypes and buftypes that should not be replaced when opening files.
---@type string[]
---@private
local NO_REPLACE_TYPES = {
	"terminal",
	"trouble",
	"qf",
	"Outline",
	"aerial",
	"edgy",
	"toggleterm",
	"TelescopePrompt",
	"noice",
}

--- Path format identifiers for `copy_path()`.
---@alias PathFormat "absolute"|"relative"|"filename"|"stem"|"directory"

--- Path format functions keyed by `PathFormat`.
---@type table<PathFormat, fun(path: string): string>
---@private
local PATH_FORMATTERS = {
	absolute = function(p)
		return p
	end,
	relative = function(p)
		return vim.fn.fnamemodify(p, ":.")
	end,
	filename = function(p)
		return vim.fn.fnamemodify(p, ":t")
	end,
	stem = function(p)
		return vim.fn.fnamemodify(p, ":t:r")
	end,
	directory = function(p)
		return vim.fn.fnamemodify(p, ":h")
	end,
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS: Notifications
-- ═══════════════════════════════════════════════════════════════════════════

--- Send a notification with the "Neo-tree" title and icon.
---@param msg string Notification message body
---@param level? integer vim.log.levels.* constant (default: INFO)
---@private
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, {
		title = icons.tree.Explorer .. "  Neo-tree",
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS: Color Extraction
-- ═══════════════════════════════════════════════════════════════════════════

--- Extract a color component from an existing highlight group.
---@param name string Highlight group name (e.g. `"Function"`)
---@param component "fg"|"bg" Which color component to extract
---@return string|nil hex Hex color string (e.g. `"#7aa2f7"`) or `nil`
---@private
local function hl_color(name, component)
	local ok, group = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
	if ok and group[component] then return string.format("#%06x", group[component]) end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS: Formatting
-- ═══════════════════════════════════════════════════════════════════════════

--- Format a byte count into a human-readable size string.
---@param size number File size in bytes
---@return string formatted Formatted size (e.g. `"1.5K"`, `"3.2M"`)
---@private
local function format_size(size)
	local units = { "B", "K", "M", "G", "T" }
	local unit_index = 1
	local value = size

	while value >= 1024 and unit_index < #units do
		value = value / 1024
		unit_index = unit_index + 1
	end

	if unit_index == 1 then return string.format("%d%s", value, units[unit_index]) end
	return string.format("%.1f%s", value, units[unit_index])
end

--- Format a Unix file mode into a `rwxrwxrwx` permission string.
--- Uses bitwise operations for correctness.
---@param mode number Raw `stat.mode` value
---@return string perms Formatted permission string (e.g. `"rwxr-xr--"`)
---@private
local function format_permissions(mode)
	local bits = mode % 512 -- last 9 bits (owner/group/other rwx)
	local result = {}
	local chars = { "r", "w", "x" }

	for i = 8, 0, -1 do
		local char_idx = (8 - i) % 3 + 1
		result[#result + 1] = (bit.band(bits, bit.lshift(1, i)) ~= 0) and chars[char_idx] or "-"
	end

	return table.concat(result)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS: Neo-tree Utilities
-- ═══════════════════════════════════════════════════════════════════════════

--- Resolve the directory path for a given Neo-tree node.
--- If the node is a directory, returns its path directly.
--- If the node is a file, returns its parent directory.
---@param node table Neo-tree node object
---@return string dir Absolute directory path
---@private
local function get_node_dir(node)
	local path = node:get_id()
	if node.type == "directory" then return path end
	return vim.fn.fnamemodify(path, ":h")
end

--- Safely refresh a Neo-tree source.
--- Wraps `require("neo-tree.sources.manager").refresh` in `pcall`
--- to prevent errors when Neo-tree is not fully loaded.
---@param source? string Source name (e.g. `"filesystem"`, `"git_status"`). Omit for all.
---@private
local function refresh(source)
	pcall(require("neo-tree.sources.manager").refresh, source)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ACTIONS: Path Operations
-- ═══════════════════════════════════════════════════════════════════════════

--- Copy a variant of the node's path to the system clipboard.
---@param state table Neo-tree state object
---@param fmt PathFormat Path format identifier
---@private
local function copy_path(state, fmt)
	local node = state.tree:get_node()
	local path = node:get_id()
	local result = (PATH_FORMATTERS[fmt] or PATH_FORMATTERS.absolute)(path)

	vim.fn.setreg("+", result, "c")
	notify(string.format("%s  Copied: %s", icons.ui.Check, result))
end

--- Copy the entire content of a file to the system clipboard.
--- Only works on file nodes smaller than `MAX_FILE_SIZE`.
---@param state table Neo-tree state object
---@private
local function copy_file_content(state)
	local node = state.tree:get_node()
	if node.type ~= "file" then
		notify("Can only copy content of files", vim.log.levels.WARN)
		return
	end

	local path = node:get_id()
	local stat = vim.uv.fs_stat(path)

	if stat and stat.size > MAX_FILE_SIZE then
		notify("File too large to copy (>10 MB)", vim.log.levels.WARN)
		return
	end

	local ok, content = pcall(vim.fn.readfile, path)
	if ok and content then
		vim.fn.setreg("+", table.concat(content, "\n"), "c")
		notify(string.format("%s  Copied %d lines from %s", icons.ui.Copy, #content, node.name))
	else
		notify("Failed to read file", vim.log.levels.ERROR)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ACTIONS: System Integration
-- ═══════════════════════════════════════════════════════════════════════════

--- Open the node's file or directory with the system default application.
--- Uses platform-appropriate commands (macOS/Windows/WSL/Linux).
---@param state table Neo-tree state object
---@private
local function system_open(state)
	local node = state.tree:get_node()
	local path = node:get_id()

	---@type string[]
	local cmd
	if platform.is_mac then
		cmd = { "open", path }
	elseif platform.is_windows then
		cmd = { "cmd", "/c", "start", "", path }
	elseif platform.is_wsl then
		cmd = { "wslview", path }
	else
		cmd = { "xdg-open", path }
	end

	vim.fn.jobstart(cmd, { detach = true })
	notify(string.format("%s  Opened externally", icons.ui.Play))
end

--- Diff the selected file against the current buffer in a vertical split.
--- Closes Neo-tree before opening the diff to avoid layout issues.
---@param state table Neo-tree state object
---@private
local function diff_file(state)
	local node = state.tree:get_node()
	if node.type ~= "file" then
		notify("Can only diff files", vim.log.levels.WARN)
		return
	end
	local path = node:get_id()
	vim.cmd("Neotree close")
	vim.cmd("vert diffsplit " .. vim.fn.fnameescape(path))
end

--- Open a terminal in the directory of the selected node.
--- Closes Neo-tree first, then sets the local directory.
---@param state table Neo-tree state object
---@private
local function open_terminal_here(state)
	local node = state.tree:get_node()
	local dir = get_node_dir(node)
	vim.cmd("Neotree close")
	vim.cmd("lcd " .. vim.fn.fnameescape(dir))
	vim.cmd("terminal")
	vim.cmd("startinsert")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ACTIONS: File Operations
-- ═══════════════════════════════════════════════════════════════════════════

--- Move the selected node to system trash instead of permanent deletion.
--- Uses platform-appropriate trash commands with graceful fallback.
---@param state table Neo-tree state object
---@private
local function trash_delete(state)
	local node = state.tree:get_node()
	if node.type == "message" then return end

	local path = node:get_id()
	local name = node.name

	local confirm = vim.fn.confirm(string.format(" %s  Move '%s' to trash?", icons.ui.BoldClose, name), "&Yes\n&No", 2)
	if confirm ~= 1 then return end

	---@type string[]|nil
	local cmd

	if platform.is_mac then
		cmd = vim.fn.executable("trash") == 1 and { "trash", path } or { "mv", path, vim.fn.expand("~/.Trash/") }
	elseif platform.is_windows then
		notify("Trash not supported on Windows. Use 'd' to delete permanently.", vim.log.levels.WARN)
		return
	else
		if vim.fn.executable("gio") == 1 then
			cmd = { "gio", "trash", path }
		elseif vim.fn.executable("trash-put") == 1 then
			cmd = { "trash-put", path }
		else
			local trash_dir = vim.fn.expand("~/.local/share/Trash/files/")
			vim.fn.mkdir(trash_dir, "p")
			cmd = { "mv", path, trash_dir }
		end
	end

	vim.fn.system(cmd)
	if vim.v.shell_error == 0 then
		notify(string.format("%s  Trashed: %s", icons.ui.Check, name))
		refresh("filesystem")
	else
		notify(string.format("Failed to trash '%s'. Use 'd' to delete permanently.", name), vim.log.levels.ERROR)
	end
end

--- Toggle the executable permission bit on a file (Unix only).
--- Runs `chmod +x` or `chmod -x` depending on current state.
---@param state table Neo-tree state object
---@private
local function toggle_executable(state)
	if platform.is_windows then
		notify("Not supported on Windows", vim.log.levels.WARN)
		return
	end

	local node = state.tree:get_node()
	if node.type ~= "file" then
		notify("Can only toggle executable on files", vim.log.levels.WARN)
		return
	end

	local path = node:get_id()
	local stat = vim.uv.fs_stat(path)
	if not stat then return end

	-- Check if owner execute bit is set (0o100 = 64)
	local is_exec = bit.band(stat.mode, 64) ~= 0

	if is_exec then
		vim.fn.system({ "chmod", "-x", path })
		notify(string.format("%s  Removed execute: %s", icons.ui.Lock, node.name))
	else
		vim.fn.system({ "chmod", "+x", path })
		notify(string.format("%s  Made executable: %s", icons.ui.Unlock, node.name))
	end

	refresh("filesystem")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ACTIONS: Information Display
-- ═══════════════════════════════════════════════════════════════════════════

--- Display detailed file information in a floating popup window.
--- Shows: name, path, type, size, permissions, timestamps, line count.
---@param state table Neo-tree state object
---@private
local function file_info_popup(state)
	local node = state.tree:get_node()
	local path = node:get_id()
	local stat = vim.uv.fs_stat(path)

	if not stat then
		notify("Cannot stat: " .. path, vim.log.levels.WARN)
		return
	end

	---@type string[]
	local lines = {
		" " .. icons.documents.Default .. "  File Information",
		string.rep("─", 50),
		"",
		"  " .. icons.ui.File .. "  Name      " .. node.name,
		"  " .. icons.ui.Folder .. "  Path      " .. vim.fn.fnamemodify(path, ":."),
		"  " .. icons.ui.Settings .. "  Type      " .. stat.type,
		"  " .. icons.ui.Package .. "  Size      " .. format_size(stat.size) .. " (" .. stat.size .. " bytes)",
	}

	-- Permissions (Unix only)
	if not platform.is_windows then
		local perms = format_permissions(stat.mode)
		local octal = string.format("%o", stat.mode % 512)
		lines[#lines + 1] = "  " .. icons.ui.Lock .. "  Perms     " .. perms .. " (" .. octal .. ")"
	end

	-- Timestamps
	lines[#lines + 1] = ""
	lines[#lines + 1] = "  " .. icons.ui.Calendar .. "  Modified  " .. os.date("%Y-%m-%d %H:%M:%S", stat.mtime.sec)
	lines[#lines + 1] = "  " .. icons.ui.Calendar .. "  Accessed  " .. os.date("%Y-%m-%d %H:%M:%S", stat.atime.sec)
	if stat.birthtime and stat.birthtime.sec > 0 then
		lines[#lines + 1] = "  " .. icons.ui.Calendar .. "  Created   " .. os.date("%Y-%m-%d %H:%M:%S", stat.birthtime.sec)
	end

	-- Line count for text files
	if stat.type == "file" and stat.size < MAX_FILE_SIZE then
		local ok, content = pcall(vim.fn.readfile, path)
		if ok and content then
			lines[#lines + 1] = ""
			lines[#lines + 1] = "  " .. icons.ui.List .. "  Lines     " .. #content
		end
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = "  Press q or <Esc> to close"

	-- Calculate popup dimensions
	local width = 4
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line) + 4)
	end

	-- Create floating window
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "cursor",
		row = 1,
		col = 2,
		width = width,
		height = #lines,
		style = "minimal",
		border = settings:get("ui.float_border", "rounded"),
		title = " " .. icons.ui.File .. " Info ",
		title_pos = "center",
	})

	vim.api.nvim_set_option_value("winblend", 10, { win = win })
	vim.api.nvim_set_option_value("cursorline", false, { win = win })

	-- Close keymaps (single definition)
	for _, key in ipairs({ "q", "<Esc>", "<CR>" }) do
		vim.api.nvim_buf_set_keymap(buf, "n", key, "<cmd>close<cr>", { noremap = true, silent = true })
	end

	-- Auto-close on focus loss
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = buf,
		once = true,
		callback = function()
			pcall(vim.api.nvim_win_close, win, true)
		end,
	})
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ACTIONS: Telescope Integration
-- ═══════════════════════════════════════════════════════════════════════════

--- Launch Telescope `find_files` scoped to the selected directory.
---@param state table Neo-tree state object
---@private
local function telescope_find_in_dir(state)
	local node = state.tree:get_node()
	local dir = get_node_dir(node)
	local short = vim.fn.fnamemodify(dir, ":~:.")

	local ok, builtin = pcall(require, "telescope.builtin")
	if ok then
		builtin.find_files({
			cwd = dir,
			prompt_title = icons.documents.FileFind .. " Find in " .. short,
		})
	else
		notify("Telescope not available", vim.log.levels.WARN)
	end
end

--- Launch Telescope `live_grep` scoped to the selected directory.
---@param state table Neo-tree state object
---@private
local function telescope_grep_in_dir(state)
	local node = state.tree:get_node()
	local dir = get_node_dir(node)
	local short = vim.fn.fnamemodify(dir, ":~:.")

	local ok, builtin = pcall(require, "telescope.builtin")
	if ok then
		builtin.live_grep({
			cwd = dir,
			prompt_title = icons.ui.Search .. " Grep in " .. short,
		})
	else
		notify("Telescope not available", vim.log.levels.WARN)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ACTIONS: Git Integration
-- ═══════════════════════════════════════════════════════════════════════════

--- Show the git log/history for the selected file.
--- Tries integrations in order: diffview → telescope → terminal.
---@param state table Neo-tree state object
---@private
local function git_log_file(state)
	local node = state.tree:get_node()
	if node.type ~= "file" then
		notify("Can only show git log for files", vim.log.levels.WARN)
		return
	end

	local path = node:get_id()

	if pcall(require, "diffview") then
		vim.cmd("Neotree close")
		vim.cmd("DiffviewFileHistory " .. vim.fn.fnameescape(path))
	elseif pcall(require, "telescope.builtin") then
		require("telescope.builtin").git_bcommits({
			prompt_title = icons.git.Commit .. " Log: " .. node.name,
		})
	else
		vim.cmd("Neotree close")
		vim.cmd("terminal git log --oneline --follow " .. vim.fn.shellescape(path))
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HIGHLIGHTS
-- ═══════════════════════════════════════════════════════════════════════════

--- Apply theme-adaptive highlights for all Neo-tree UI elements.
--- Derives colors from the active colorscheme with curated fallbacks
--- (Tokyo Night palette). Called on setup and on every `ColorScheme` event.
---@private
local function apply_highlights()
	local hl = vim.api.nvim_set_hl
	local fg = function(name)
		return hl_color(name, "fg")
	end
	local bg = function(name)
		return hl_color(name, "bg")
	end

	local sidebar_bg = bg("NormalFloat") or bg("Normal")

	-- ── Sidebar panel ────────────────────────────────────────────────
	hl(0, "NeoTreeNormal", { bg = sidebar_bg })
	hl(0, "NeoTreeNormalNC", { bg = sidebar_bg })
	hl(0, "NeoTreeEndOfBuffer", { fg = sidebar_bg, bg = sidebar_bg })
	hl(0, "NeoTreeWinSeparator", { fg = sidebar_bg or fg("WinSeparator") or "#1d202f", bg = sidebar_bg })
	hl(0, "NeoTreeCursorLine", { bg = bg("CursorLine") })

	-- ── Names and icons ──────────────────────────────────────────────
	hl(0, "NeoTreeRootName", { fg = fg("Function") or "#7aa2f7", bold = true, italic = true })
	hl(0, "NeoTreeDirectoryName", { fg = fg("Directory") or "#7aa2f7", bold = true })
	hl(0, "NeoTreeDirectoryIcon", { fg = fg("Directory") or "#7aa2f7" })
	hl(0, "NeoTreeFileName", { fg = fg("Normal") or "#c0caf5" })
	hl(0, "NeoTreeFileNameOpened", { fg = fg("String") or "#9ece6a", bold = true })
	hl(0, "NeoTreeFileIcon", { link = "Normal" })
	hl(0, "NeoTreeSymbolicLinkTarget", { fg = fg("Special") or "#7dcfff", italic = true })

	-- ── Structural elements ──────────────────────────────────────────
	hl(0, "NeoTreeIndentMarker", { fg = fg("NonText") or "#3b4261" })
	hl(0, "NeoTreeExpander", { fg = fg("NonText") or "#3b4261" })
	hl(0, "NeoTreeModified", { fg = fg("DiagnosticWarn") or "#e0af68" })
	hl(0, "NeoTreeBufferNumber", { fg = fg("Comment") or "#565f89" })

	-- ── Dimmed elements ──────────────────────────────────────────────
	hl(0, "NeoTreeDotfile", { fg = fg("Comment") or "#565f89" })
	hl(0, "NeoTreeDimText", { fg = fg("Comment") or "#565f89" })
	hl(0, "NeoTreeFadeText1", { fg = fg("Comment") or "#565f89" })
	hl(0, "NeoTreeFadeText2", { fg = fg("NonText") or "#3b4261" })
	hl(0, "NeoTreeMessage", { fg = fg("Comment") or "#565f89", italic = true })

	-- ── Filter ───────────────────────────────────────────────────────
	hl(0, "NeoTreeFilterTerm", { fg = fg("String") or "#9ece6a", bold = true })

	-- ── Git status colors ────────────────────────────────────────────
	hl(0, "NeoTreeGitAdded", { fg = fg("DiffAdd") or "#449dab" })
	hl(0, "NeoTreeGitModified", { fg = fg("DiffChange") or "#6183bb" })
	hl(0, "NeoTreeGitDeleted", { fg = fg("DiffDelete") or "#914c54" })
	hl(0, "NeoTreeGitRenamed", { fg = fg("Special") or "#7dcfff" })
	hl(0, "NeoTreeGitUntracked", { fg = fg("DiagnosticHint") or "#73daca" })
	hl(0, "NeoTreeGitIgnored", { fg = fg("Comment") or "#565f89" })
	hl(0, "NeoTreeGitStaged", { fg = fg("String") or "#9ece6a" })
	hl(0, "NeoTreeGitUnstaged", { fg = fg("DiagnosticWarn") or "#e0af68" })
	hl(0, "NeoTreeGitConflict", { fg = fg("DiagnosticError") or "#f7768e", bold = true })

	-- ── Floating window ──────────────────────────────────────────────
	hl(0, "NeoTreeFloatBorder", { fg = fg("FloatBorder") or "#29a4bd", bg = sidebar_bg })
	hl(0, "NeoTreeFloatTitle", { fg = fg("FloatTitle") or "#7dcfff", bg = sidebar_bg, bold = true })
	hl(0, "NeoTreeFloatNormal", { bg = sidebar_bg })
	hl(0, "NeoTreeTitleBar", { fg = fg("Function") or "#7aa2f7", bg = sidebar_bg, bold = true })

	-- ── Source selector tabs ─────────────────────────────────────────
	local tab_sel_fg = fg("Normal") or "#c0caf5"
	local tab_sel_bg = bg("TabLineSel") or bg("CursorLine") or "#292e42"
	local tab_fg = fg("Comment") or "#565f89"
	local tab_bg = sidebar_bg

	hl(0, "NeoTreeTabActive", { fg = tab_sel_fg, bg = tab_sel_bg, bold = true })
	hl(0, "NeoTreeTabInactive", { fg = tab_fg, bg = tab_bg })
	hl(0, "NeoTreeTabSeparatorActive", { fg = tab_sel_bg, bg = tab_bg })
	hl(0, "NeoTreeTabSeparatorInactive", { fg = tab_bg, bg = tab_bg })

	-- ── Preview ──────────────────────────────────────────────────────
	hl(0, "NeoTreePreview", { link = "Search" })
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════════

---@type lazy.PluginSpec[]
return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		cmd = "Neotree",

		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-mini/mini.icons",
			"MunifTanjim/nui.nvim",

			-- Image preview support (optional, terminal-dependent)
			{
				"3rd/image.nvim",
				optional = true,
				cond = function()
					return vim.env.TERM_PROGRAM == "WezTerm"
						or vim.env.TERM == "xterm-kitty"
						or vim.env.TERM_PROGRAM == "iTerm.app"
				end,
			},

			-- Window picker for opening files in specific splits
			{
				"s1n7ax/nvim-window-picker",
				name = "window-picker",
				event = "VeryLazy",
				version = "2.*",
				opts = {
					hint = "floating-big-letter",
					show_prompt = false,
					filter_rules = {
						include_current_win = false,
						autoselect_one = true,
						bo = {
							filetype = {
								"neo-tree",
								"neo-tree-popup",
								"notify",
								"noice",
								"snacks_notif",
								"quickfix",
								"TelescopePrompt",
							},
							buftype = { "terminal", "quickfix" },
						},
					},
				},
			},
		},

		-- ── Keymaps (lazy.nvim triggers) ─────────────────────────────
		keys = {
			-- stylua: ignore start
			{ "<leader>ee", function() require("neo-tree.command").execute({ toggle = true, position = "left" }) end,                                        desc = icons.tree.Explorer    .. " File Explorer" },
			{ "<leader>eE", function() require("neo-tree.command").execute({ toggle = true, position = "float" }) end,                                       desc = icons.tree.Explorer    .. " Float Explorer" },
			{ "<leader>ef", function() require("neo-tree.command").execute({ reveal = true, position = "left", reveal_force_cwd = true }) end,               desc = icons.documents.FileFind .. " Reveal in Explorer" },
			{ "<leader>eg", function() require("neo-tree.command").execute({ source = "git_status", toggle = true, position = "left" }) end,                 desc = icons.git.Git          .. " Git Explorer" },
			{ "<leader>eb", function() require("neo-tree.command").execute({ source = "buffers", toggle = true, position = "left" }) end,                    desc = icons.ui.Tab           .. " Buffer Explorer" },
			{ "<leader>ed", function() require("neo-tree.command").execute({ source = "document_symbols", toggle = true, position = "right" }) end,          desc = icons.ui.Code          .. " Document Symbols" },
			-- stylua: ignore end
		},

		deactivate = function()
			vim.cmd([[Neotree close]])
		end,

		-- ── Init: directory argument detection ───────────────────────
		init = function()
			vim.api.nvim_create_autocmd("BufEnter", {
				group = augroup("NeoTreeStart"),
				once = true,
				callback = function()
					if package.loaded["neo-tree"] then return end
					local f = vim.fn.argv(0)
					if f and f ~= "" then
						local stat = vim.uv.fs_stat(f)
						if stat and stat.type == "directory" then require("neo-tree") end
					end
				end,
			})
		end,

		-- ══════════════════════════════════════════════════════════════
		-- OPTIONS
		-- ══════════════════════════════════════════════════════════════
		opts = {
			-- ── Sources ──────────────────────────────────────────────
			sources = {
				"filesystem",
				"buffers",
				"git_status",
				"document_symbols",
			},

			-- ── Global behavior ──────────────────────────────────────
			close_if_last_window = true,
			popup_border_style = settings:get("ui.float_border", "rounded"),
			enable_git_status = true,
			enable_diagnostics = true,
			enable_modified_markers = true,
			enable_opened_markers = true,
			enable_cursor_hijack = true,
			enable_refresh_on_write = true,
			sort_case_insensitive = true,
			use_popups_for_input = true,
			resize_timer_interval = 200,
			log_level = "info",
			log_to_file = false,
			open_files_do_not_replace_types = NO_REPLACE_TYPES,

			-- ── Source selector (top tab bar) ────────────────────────
			source_selector = {
				winbar = true,
				statusline = false,
				content_layout = "center",
				show_scrolled_off_parent_node = true,
				tabs_layout = "equal",
				show_separator_on_edge = true,
				separator = {
					left = icons.powerline.Round_left,
					right = icons.powerline.Round_right,
				},
				sources = {
					{ source = "filesystem", display_name = " " .. icons.ui.Folder .. " Files " },
					{ source = "buffers", display_name = " " .. icons.ui.Tab .. " Buffers " },
					{ source = "git_status", display_name = " " .. icons.git.Git .. " Git " },
					{ source = "document_symbols", display_name = " " .. icons.ui.Code .. " Symbols " },
				},
			},

			-- ── Event handlers ───────────────────────────────────────
			event_handlers = {
				{
					event = "file_open_requested",
					handler = function()
						require("neo-tree.command").execute({ action = "close" })
					end,
				},
				{
					event = "terminal_opened",
					handler = function()
						vim.schedule(function()
							refresh("git_status")
						end)
					end,
				},
				{
					event = "neo_tree_window_after_open",
					handler = function(args)
						if args.position == "left" or args.position == "right" then vim.cmd("wincmd =") end
					end,
				},
				{
					event = "neo_tree_window_after_close",
					handler = function(args)
						if args.position == "left" or args.position == "right" then vim.cmd("wincmd =") end
					end,
				},
				{
					event = "neo_tree_buffer_enter",
					handler = function()
						vim.schedule(function()
							refresh()
						end)
					end,
				},
			},

			-- ── Default component configs ────────────────────────────
			default_component_configs = {
				container = {
					enable_character_fade = true,
					width = "100%",
				},
				indent = {
					indent_size = 2,
					padding = 1,
					with_markers = true,
					with_expanders = true,
					indent_marker = icons.tree.Indent,
					last_indent_marker = icons.tree.LastIndent,
					highlight = "NeoTreeIndentMarker",
					expander_collapsed = icons.arrows.ArrowClosed,
					expander_expanded = icons.arrows.ArrowOpen,
					expander_highlight = "NeoTreeExpander",
				},
				icon = {
					folder_closed = icons.ui.FolderClosed,
					folder_open = icons.ui.FolderOpen,
					folder_empty = icons.ui.FolderEmpty,
					folder_empty_open = icons.ui.EmptyFolderOpen,
					default = icons.ui.File,
					highlight = "NeoTreeFileIcon",
				},
				symlink_target = { enabled = true },
				name = {
					trailing_slash = true,
					use_git_status_colors = true,
					highlight = "NeoTreeFileName",
					highlight_opened_files = "all",
				},
				modified = {
					symbol = icons.ui.Pencil .. " ",
					highlight = "NeoTreeModified",
				},
				diagnostics = {
					symbols = {
						error = icons.diagnostics.Error .. " ",
						warn = icons.diagnostics.Warn .. " ",
						hint = icons.diagnostics.Hint .. " ",
						info = icons.diagnostics.Info .. " ",
					},
					highlights = {
						error = "DiagnosticSignError",
						warn = "DiagnosticSignWarn",
						hint = "DiagnosticSignHint",
						info = "DiagnosticSignInfo",
					},
				},
				git_status = {
					symbols = {
						added = icons.git.Added,
						modified = icons.git.Modified,
						deleted = icons.git.Removed,
						renamed = icons.git.Renamed,
						untracked = icons.git.Untracked,
						ignored = icons.git.Ignored,
						unstaged = icons.git.Unstaged,
						staged = icons.git.Staged,
						conflict = icons.git.Conflict,
					},
					align = "right",
				},
				file_size = { enabled = true, required_width = 50 },
				last_modified = { enabled = true, required_width = 70 },
				type = { enabled = true, required_width = 90 },
				created = { enabled = false, required_width = 110 },
			},

			-- ══════════════════════════════════════════════════════════
			-- FILESYSTEM SOURCE
			-- ══════════════════════════════════════════════════════════
			filesystem = {
				bind_to_cwd = true,
				cwd_target = { sidebar = "tab", current = "window" },
				follow_current_file = { enabled = true, leave_dirs_open = true },
				use_libuv_file_watcher = true,
				hijack_netrw_behavior = "open_default",
				scan_mode = "shallow",
				group_empty_dirs = true,
				async_directory_scan = "auto",

				filtered_items = {
					visible = false,
					show_hidden_count = true,
					hide_dotfiles = false,
					hide_gitignored = true,
					hide_hidden = true,
					hide_by_name = {
						".git",
						".DS_Store",
						"thumbs.db",
						"node_modules",
						"__pycache__",
						".cache",
						".vscode",
						".idea",
						".mypy_cache",
						".pytest_cache",
						".ruff_cache",
						".tox",
						"dist",
						"build",
						".next",
						".nuxt",
						".svelte-kit",
						"target",
						"vendor",
					},
					hide_by_pattern = {
						"*.pyc",
						"*.pyo",
						"*.o",
						"*.obj",
						"*.class",
						"*.swp",
						"*.swo",
						"*.egg-info",
					},
					always_show = {
						".gitignore",
						".gitattributes",
						".env",
						".env.local",
						".editorconfig",
						".prettierrc",
						".eslintrc",
						".dockerignore",
						".luacheckrc",
						".stylua.toml",
						".selene.toml",
						"Makefile",
						"Dockerfile",
						"Justfile",
					},
					always_show_by_pattern = { ".env*" },
					never_show = {
						".DS_Store",
						"thumbs.db",
						"desktop.ini",
						".Spotlight-V100",
						".Trashes",
					},
					never_show_by_pattern = { "*.swp", "*~", "*.bak" },
				},

				find_command = "fd",
				find_args = {
					fd = {
						"--exclude",
						".git",
						"--exclude",
						"node_modules",
						"--exclude",
						"__pycache__",
						"--exclude",
						".mypy_cache",
						"--exclude",
						"target",
					},
				},

				commands = {
					--- Create file or folder with parent directory auto-creation.
					--- Paths ending with `/` create directories.
					---@param state table Neo-tree state object
					smart_create = function(state)
						local node = state.tree:get_node()
						local dir = get_node_dir(node)

						vim.ui.input({ prompt = "Create (end with / for folder): ", default = dir .. "/" }, function(input)
							if not input or input == "" then return end
							if input:match("/$") then
								vim.fn.mkdir(input, "p")
							else
								local parent = vim.fn.fnamemodify(input, ":h")
								if vim.fn.isdirectory(parent) == 0 then vim.fn.mkdir(parent, "p") end
								vim.fn.writefile({}, input)
							end
							refresh("filesystem")
						end)
					end,
				},

				window = {
					mappings = {
						["H"] = "toggle_hidden",
						["<bs>"] = "navigate_up",
						["."] = "set_root",
						["/"] = "fuzzy_finder",
						["#"] = "fuzzy_sorter",
						["f"] = "filter_on_submit",
						["<C-x>"] = "clear_filter",
						["[g"] = "prev_git_modified",
						["]g"] = "next_git_modified",
					},
				},
			},

			-- ══════════════════════════════════════════════════════════
			-- BUFFERS SOURCE
			-- ══════════════════════════════════════════════════════════
			buffers = {
				follow_current_file = { enabled = true, leave_dirs_open = true },
				group_empty_dirs = true,
				show_unloaded = true,
				terminals_first = false,
				window = {
					mappings = {
						["bd"] = "buffer_delete",
						["<bs>"] = "navigate_up",
						["."] = "set_root",
					},
				},
			},

			-- ══════════════════════════════════════════════════════════
			-- GIT STATUS SOURCE
			-- ══════════════════════════════════════════════════════════
			git_status = {
				window = {
					position = "left",
					mappings = {
						["A"] = "git_add_all",
						["gu"] = "git_unstage_file",
						["ga"] = "git_add_file",
						["gr"] = "git_revert_file",
						["gc"] = "git_commit",
						["gp"] = "git_push",
						["gg"] = "git_commit_and_push",
					},
				},
			},

			-- ══════════════════════════════════════════════════════════
			-- DOCUMENT SYMBOLS SOURCE
			-- ══════════════════════════════════════════════════════════
			document_symbols = {
				follow_cursor = true,
				client_filters = "first",
				renderers = {
					root = {
						{ "indent" },
						{ "icon", default = icons.ui.Code },
						{ "name", zindex = 10 },
					},
					symbol = {
						{ "indent", with_expanders = true },
						{ "kind_icon", default = icons.ui.Dot },
						{
							"container",
							content = {
								{ "name", zindex = 10 },
								{ "kind_name", zindex = 20, align = "right" },
							},
						},
					},
				},
				window = {
					mappings = {
						["<cr>"] = "jump_to_symbol",
						["o"] = "jump_to_symbol",
						["A"] = "noop",
						["d"] = "noop",
						["y"] = "noop",
						["x"] = "noop",
						["p"] = "noop",
						["c"] = "noop",
						["m"] = "noop",
						["a"] = "noop",
					},
				},
				-- stylua: ignore
				kinds = {
					File          = { icon = icons.kinds.File,          hl = "Tag" },
					Module        = { icon = icons.kinds.Module,        hl = "Exception" },
					Namespace     = { icon = icons.kinds.Namespace,     hl = "Include" },
					Package       = { icon = icons.kinds.Package,       hl = "Label" },
					Class         = { icon = icons.kinds.Class,         hl = "Type" },
					Method        = { icon = icons.kinds.Method,        hl = "Function" },
					Property      = { icon = icons.kinds.Property,      hl = "@property" },
					Field         = { icon = icons.kinds.Field,         hl = "@field" },
					Constructor   = { icon = icons.kinds.Constructor,   hl = "@constructor" },
					Enum          = { icon = icons.kinds.Enum,          hl = "Type" },
					Interface     = { icon = icons.kinds.Interface,     hl = "Type" },
					Function      = { icon = icons.kinds.Function,      hl = "Function" },
					Variable      = { icon = icons.kinds.Variable,      hl = "@variable" },
					Constant      = { icon = icons.kinds.Constant,      hl = "Constant" },
					String        = { icon = icons.kinds.String,        hl = "String" },
					Number        = { icon = icons.kinds.Number,        hl = "Number" },
					Boolean       = { icon = icons.kinds.Boolean,       hl = "Boolean" },
					Array         = { icon = icons.kinds.Array,         hl = "Type" },
					Object        = { icon = icons.kinds.Object,        hl = "Type" },
					Key           = { icon = icons.kinds.Key,           hl = "@field" },
					Null          = { icon = icons.kinds.Null,          hl = "Constant" },
					EnumMember    = { icon = icons.kinds.EnumMember,    hl = "Constant" },
					Struct        = { icon = icons.kinds.Struct,        hl = "Type" },
					Event         = { icon = icons.kinds.Event,         hl = "Type" },
					Operator      = { icon = icons.kinds.Operator,      hl = "Operator" },
					TypeParameter = { icon = icons.kinds.TypeParameter, hl = "Type" },
				},
			},

			-- ══════════════════════════════════════════════════════════
			-- WINDOW CONFIGURATION
			-- ══════════════════════════════════════════════════════════
			window = {
				position = "left",
				width = 38,
				auto_expand_width = false,
				mapping_options = { noremap = true, nowait = true },

				mappings = {
					-- ── Navigation ───────────────────────────────────
					["<space>"] = "none",
					["<cr>"] = "open",
					["o"] = "open",
					["<2-LeftMouse>"] = "open",
					["l"] = "open",
					["h"] = "close_node",
					["<esc>"] = "cancel",

					-- ── Open modes ───────────────────────────────────
					["s"] = "open_split",
					["v"] = "open_vsplit",
					["t"] = "open_tabnew",
					["w"] = "open_with_window_picker",

					-- ── Preview ──────────────────────────────────────
					["P"] = { "toggle_preview", config = { use_float = true, use_image_nvim = true } },
					["<tab>"] = function(state)
						local node = state.tree:get_node()
						if require("neo-tree.utils").is_expandable(node) then
							state.commands["toggle_node"](state)
						else
							state.commands["toggle_preview"](state)
							vim.cmd("Neotree reveal")
						end
					end,

					-- ── Window focus ─────────────────────────────────
					["<C-h>"] = function()
						vim.cmd("wincmd h")
					end,
					["<C-l>"] = function()
						vim.cmd("wincmd l")
					end,

					-- ── Tree manipulation ────────────────────────────
					["a"] = { "add", config = { show_path = "relative" } },
					["A"] = { "add_directory", config = { show_path = "relative" } },
					["d"] = "delete",
					["r"] = "rename",
					["c"] = { "copy", config = { show_path = "relative" } },
					["m"] = { "move", config = { show_path = "relative" } },
					["x"] = "cut_to_clipboard",
					["p"] = "paste_from_clipboard",

					-- ── Trash (safer delete) ─────────────────────────
					["T"] = trash_delete,

					-- ── Copy path variants ───────────────────────────
					["Y"] = function(state)
						copy_path(state, "absolute")
					end,
					["y"] = function(state)
						copy_path(state, "relative")
					end,
					["yn"] = function(state)
						copy_path(state, "filename")
					end,
					["ys"] = function(state)
						copy_path(state, "stem")
					end,
					["yd"] = function(state)
						copy_path(state, "directory")
					end,
					["yc"] = copy_file_content,

					-- ── System integration ───────────────────────────
					["O"] = system_open,
					["D"] = diff_file,

					-- ── File info & permissions ──────────────────────
					["I"] = file_info_popup,
					["X"] = toggle_executable,

					-- ── Terminal ──────────────────────────────────────
					["<C-t>"] = open_terminal_here,

					-- ── Telescope integration ────────────────────────
					["gf"] = telescope_find_in_dir,
					["gg"] = telescope_grep_in_dir,

					-- ── Git log ──────────────────────────────────────
					["gl"] = git_log_file,

					-- ── Source navigation ────────────────────────────
					["[d"] = "prev_source",
					["]d"] = "next_source",

					-- ── Sort operations ──────────────────────────────
					["oc"] = { "order_by_created", nowait = true },
					["od"] = { "order_by_diagnostics", nowait = true },
					["og"] = { "order_by_git_status", nowait = true },
					["om"] = { "order_by_modified", nowait = true },
					["on"] = { "order_by_name", nowait = true },
					["os"] = { "order_by_size", nowait = true },
					["ot"] = { "order_by_type", nowait = true },

					-- ── Expand / collapse ────────────────────────────
					["z"] = "close_all_nodes",
					["Z"] = "expand_all_nodes",

					-- ── Information ──────────────────────────────────
					["i"] = "show_file_details",
					["?"] = "show_help",

					-- ── Refresh ──────────────────────────────────────
					["R"] = "refresh",
				},
			},

			-- ── Renderers ────────────────────────────────────────────
			renderers = {
				directory = {
					{ "indent" },
					{ "icon" },
					{ "current_filter" },
					{
						"container",
						content = {
							{ "name", zindex = 10 },
							{ "clipboard", zindex = 10 },
							{ "diagnostics", errors_only = true, zindex = 20, align = "right", hide_when_expanded = true },
							{ "git_status", zindex = 10, align = "right", hide_when_expanded = true },
						},
					},
				},
				file = {
					{ "indent" },
					{ "icon" },
					{
						"container",
						content = {
							{ "name", zindex = 10 },
							{ "clipboard", zindex = 10 },
							{ "bufnr", zindex = 10 },
							{ "modified", zindex = 20, align = "right" },
							{ "diagnostics", zindex = 20, align = "right" },
							{ "git_status", zindex = 10, align = "right" },
							{ "file_size", zindex = 5, align = "right" },
							{ "last_modified", zindex = 5, align = "right" },
						},
					},
				},
			},

			-- ── Nesting rules ────────────────────────────────────────
			-- stylua: ignore
			nesting_rules = {
				-- JavaScript / TypeScript
				["js"]  = { "js.map", "d.ts" },
				["ts"]  = { "ts.map", "d.ts" },
				["tsx"] = { "tsx.map" },
				["jsx"] = { "jsx.map" },

				-- Styles
				["css"]  = { "css.map", "min.css" },
				["scss"] = { "scss.map", "min.css" },

				-- Package managers
				["package.json"]  = { "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", ".npmrc", ".yarnrc", ".yarnrc.yml" },
				["composer.json"] = { "composer.lock" },
				["Gemfile"]       = { "Gemfile.lock" },
				["mix.exs"]       = { "mix.lock" },
				["Pipfile"]       = { "Pipfile.lock" },

				-- Language build files
				["go.mod"]            = { "go.sum" },
				["Cargo.toml"]        = { "Cargo.lock" },
				["pyproject.toml"]    = { "poetry.lock", "uv.lock", "pdm.lock" },
				["flake.nix"]         = { "flake.lock" },
				["build.gradle"]      = { "gradle.lockfile" },
				["build.gradle.kts"]  = { "gradle.lockfile" },

				-- Config file groups
				["tsconfig.json"] = { "tsconfig.*.json" },
				[".eslintrc"]     = { ".eslintrc.js", ".eslintrc.cjs", ".eslintrc.json", ".eslintrc.yaml", ".eslintignore" },
				[".prettierrc"]   = { ".prettierrc.js", ".prettierrc.cjs", ".prettierrc.json", ".prettierrc.yaml", ".prettierignore" },
				["tailwind.config"] = { "tailwind.config.js", "tailwind.config.ts", "tailwind.config.cjs", "postcss.config.js", "postcss.config.cjs" },

				-- Framework configs
				["vite.config"]    = { "vite.config.ts", "vite.config.js", "vite.config.mjs" },
				["next.config"]    = { "next.config.js", "next.config.mjs", "next.config.ts" },
				["nuxt.config"]    = { "nuxt.config.ts", "nuxt.config.js" },
				["svelte.config"]  = { "svelte.config.js", "svelte.config.ts" },
				["webpack.config"] = { "webpack.config.js", "webpack.config.ts" },
				["jest.config"]    = { "jest.config.js", "jest.config.ts", "jest.setup.ts", "jest.setup.js" },
				["vitest.config"]  = { "vitest.config.ts", "vitest.config.js" },

				-- Docker
				["docker-compose.yml"] = { "docker-compose.*.yml", "docker-compose.*.yaml" },
				["Dockerfile"]         = { "Dockerfile.*", ".dockerignore" },

				-- Documentation
				["README.md"] = { "CHANGELOG.md", "CONTRIBUTING.md", "LICENSE", "LICENSE.md", "CODE_OF_CONDUCT.md" },

				-- Git
				[".gitignore"] = { ".gitattributes", ".gitmodules" },
			},
		},

		-- ══════════════════════════════════════════════════════════════
		-- POST-CONFIGURATION
		-- ══════════════════════════════════════════════════════════════
		config = function(_, opts)
			-- ── Diagnostic signs ─────────────────────────────────────
			for severity, icon in pairs(icons.diagnostics) do
				local name = "DiagnosticSign" .. severity
				vim.fn.sign_define(name, { text = icon, texthl = name, numhl = "" })
			end

			-- ── Apply highlights (initial + on colorscheme change) ───
			apply_highlights()

			vim.api.nvim_create_autocmd("ColorScheme", {
				group = augroup("NeoTreeHL"),
				desc = "Re-apply Neo-tree custom highlights after colorscheme change",
				callback = apply_highlights,
			})

			-- ── Setup ────────────────────────────────────────────────
			require("neo-tree").setup(opts)

			-- ── Auto-refresh on focus ────────────────────────────────
			vim.api.nvim_create_autocmd("FocusGained", {
				group = augroup("NeoTreeRefresh"),
				desc = "Auto-refresh Neo-tree on window focus",
				callback = function()
					if package.loaded["neo-tree"] then refresh() end
				end,
			})

			-- ── Auto-refresh on git operations ───────────────────────
			vim.api.nvim_create_autocmd("TermClose", {
				group = augroup("NeoTreeGitRefresh"),
				desc = "Refresh Neo-tree git status after terminal closes",
				callback = function()
					if package.loaded["neo-tree"] then vim.schedule(function()
						refresh("git_status")
					end) end
				end,
			})
		end,
	},
}
