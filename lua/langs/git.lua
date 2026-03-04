---@file lua/langs/git.lua
---@description Git filetypes — treesitter & buffer-local keymaps for commit, rebase, config
---@module "langs.git"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard (`is_language_enabled`)
---@see core.keymaps             Buffer-local keymap API (`lang_group`, `lang_map`)
---@see core.icons               Shared icon definitions for UI consistency
---@see langs.python             Python language support (same architecture)
---@see langs.docker             Docker language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/git.lua — Git filetypes support (commit, rebase, config)          ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("git") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded per filetype):                           │    ║
--- ║  │  ├─ LSP          — (none, handled by Neovim built-ins)           │    ║
--- ║  │  ├─ Formatter    — (none)                                        │    ║
--- ║  │  ├─ Linter       — (none)                                        │    ║
--- ║  │  ├─ Treesitter   git_config · git_rebase · gitcommit ·           │    ║
--- ║  │  │               gitignore · gitattributes · diff parsers        │    ║
--- ║  │  ├─ DAP          — (not applicable)                              │    ║
--- ║  │  └─ Extras       conventional commits, rebase helpers, config    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Three distinct filetype groups with separate keymaps:           │    ║
--- ║  │                                                                  │    ║
--- ║  │  ┌─ GITCOMMIT (COMMIT_EDITMSG, MERGE_MSG, TAG_EDITMSG) ──────┐   │    ║
--- ║  │  │  <leader>l keymaps:                                       │   │    ║
--- ║  │  │  ├─ CONVENTIONAL  c  Commit prefix (type/scope picker)    │   │    ║
--- ║  │  │  ├─ TRAILERS      a  Co-authored-by   s  Signed-off-by    │   │    ║
--- ║  │  │  │                t  Issue reference   b  Breaking change │   │    ║
--- ║  │  │  ├─ INSPECT       d  Staged diff       i  Commit stats    │   │    ║
--- ║  │  │  ├─ EDIT          e  Commit template   r  Reset message   │   │    ║
--- ║  │  │  └─ DOCS          h  Conventional commits reference       │   │    ║
--- ║  │  └───────────────────────────────────────────────────────────┘   │    ║
--- ║  │                                                                  │    ║
--- ║  │  ┌─ GITREBASE (git-rebase-todo) ─────────────────────────────┐   │    ║
--- ║  │  │  <leader>l keymaps:                                       │   │    ║
--- ║  │  │  ├─ ACTIONS  p  pick   r  reword   e  edit                │   │    ║
--- ║  │  │  │           s  squash  f  fixup   d  drop                │   │    ║
--- ║  │  │  └─ DOCS     h  Rebase actions help                       │   │    ║
--- ║  │  └───────────────────────────────────────────────────────────┘   │    ║
--- ║  │                                                                  │    ║
--- ║  │  ┌─ GITCONFIG (.gitconfig, .git/config) ─────────────────────┐   │    ║
--- ║  │  │  <leader>l keymaps:                                       │   │    ║
--- ║  │  │  ├─ VIEW     s  Show all config    l  List (scoped)       │   │    ║
--- ║  │  │  ├─ EDIT     e  Edit global        E  Edit system         │   │    ║
--- ║  │  │  ├─ ALIAS    a  Add alias (interactive)                   │   │    ║
--- ║  │  │  ├─ INFO     u  User info          r  Show remotes        │   │    ║
--- ║  │  │  │           i  Config stats                              │   │    ║
--- ║  │  │  └─ DOCS     h  Git config reference                      │   │    ║
--- ║  │  └───────────────────────────────────────────────────────────┘   │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options:                                                         ║
--- ║  ┌─────────────────┬────────────────────────────────────────────────┐    ║
--- ║  │ gitcommit       │ wrap=true, linebreak, textwidth=72,            │    ║
--- ║  │                 │ colorcolumn="50,72", spell=true, 2-space indent│    ║
--- ║  ├─────────────────┼────────────────────────────────────────────────┤    ║
--- ║  │ gitrebase       │ number=true, relativenumber=false              │    ║
--- ║  ├─────────────────┼────────────────────────────────────────────────┤    ║
--- ║  │ gitconfig       │ tabstop=4, noexpandtab (real tabs),            │    ║
--- ║  │                 │ commentstring="# %s"                           │    ║
--- ║  └─────────────────┴────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Filetype extensions:                                                    ║
--- ║  • COMMIT_EDITMSG, MERGE_MSG, TAG_EDITMSG → gitcommit                    ║
--- ║  • git-rebase-todo → gitrebase                                           ║
--- ║  • .gitconfig, .gitmodules, .git/config → gitconfig                      ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
--
-- Early return if Git filetype support is disabled in core/settings.lua.
-- Returns an empty table so lazy.nvim receives a valid (no-op) spec list.
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("git") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string Git Nerd Font icon (trailing whitespace stripped)
local git_icon = icons.lang.git:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUPS
--
-- Registers the <leader>l group label for each Git filetype.
-- Each group is buffer-local and only visible in its respective filetype.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("gitcommit", "Git Commit", git_icon)
keys.lang_group("gitrebase", "Git Rebase", git_icon)
keys.lang_group("gitconfig", "Git Config", git_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- FILETYPE DETECTION
--
-- Runs immediately on require to register Git-specific filetype mappings.
-- These supplement Neovim's built-in detection with additional patterns
-- for gitconfig files in non-standard locations.
-- ═══════════════════════════════════════════════════════════════════════════

vim.filetype.add({
	filename = {
		["gitconfig"] = "gitconfig",
		[".gitconfig"] = "gitconfig",
		[".gitmodules"] = "gitconfig",
		["COMMIT_EDITMSG"] = "gitcommit",
		["MERGE_MSG"] = "gitcommit",
		["TAG_EDITMSG"] = "gitcommit",
		["git-rebase-todo"] = "gitrebase",
	},
	pattern = {
		[".*/%.git/config"] = "gitconfig",
		[".*/git/config"] = "gitconfig",
		[".*gitconfig.*"] = "gitconfig",
		[".*/%.gitconfig%..*"] = "gitconfig",
	},
})

-- ═══════════════════════════════════════════════════════════════════════════
-- BUFFER OPTIONS
--
-- Applied immediately via FileType autocmds for each Git filetype.
-- Each filetype has distinct editing conventions.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── gitcommit: prose-oriented editing with spell checking ────────────────
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("GitBufferOptions", { clear = true }),
	pattern = { "gitcommit" },
	callback = function()
		local opt = vim.opt_local
		opt.wrap = true
		opt.linebreak = true
		opt.textwidth = 72
		opt.colorcolumn = "50,72"
		opt.tabstop = 2
		opt.shiftwidth = 2
		opt.expandtab = true
		opt.number = false
		opt.relativenumber = false
		opt.spell = true
		opt.spelllang = "en_us"
		opt.commentstring = "# %s"
	end,
})

-- ── gitrebase: line-oriented editing with line numbers ───────────────────
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("GitRebaseBufferOptions", { clear = true }),
	pattern = { "gitrebase" },
	callback = function()
		local opt = vim.opt_local
		opt.number = true
		opt.relativenumber = false
		opt.colorcolumn = ""
	end,
})

-- ── gitconfig: INI-style with real tabs (git convention) ─────────────────
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("GitConfigBufferOptions", { clear = true }),
	pattern = { "gitconfig" },
	callback = function()
		local opt = vim.opt_local
		opt.tabstop = 4
		opt.shiftwidth = 4
		opt.expandtab = false
		opt.commentstring = "# %s"
		opt.number = true
		opt.relativenumber = true
	end,
})

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — GITCOMMIT: CONVENTIONAL COMMITS
--
-- Conventional commit message authoring tools: prefix insertion,
-- trailer management, staged diff inspection, and message statistics.
--
-- Follows the Conventional Commits v1.0.0 specification:
-- https://www.conventionalcommits.org/en/v1.0.0/
-- ═══════════════════════════════════════════════════════════════════════════

--- Insert a conventional commit prefix (type + optional scope).
---
--- Presents a picker with standard commit types:
--- • feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
---
--- After type selection, prompts for an optional scope.
--- The prefix is prepended to the existing subject line, replacing
--- any existing conventional prefix.
---
--- Example result: `feat(auth): add OAuth2 support`
keys.lang_map("gitcommit", "n", "<leader>lc", function()
	---@type { prefix: string, desc: string }[]
	local types = {
		{ prefix = "feat", desc = "A new feature" },
		{ prefix = "fix", desc = "A bug fix" },
		{ prefix = "docs", desc = "Documentation only" },
		{ prefix = "style", desc = "Code style (formatting, semicolons…)" },
		{ prefix = "refactor", desc = "Refactor (no feature/fix)" },
		{ prefix = "perf", desc = "Performance improvement" },
		{ prefix = "test", desc = "Add/fix tests" },
		{ prefix = "build", desc = "Build system / deps" },
		{ prefix = "ci", desc = "CI configuration" },
		{ prefix = "chore", desc = "Other changes" },
		{ prefix = "revert", desc = "Revert a commit" },
	}

	vim.ui.select(
		vim.tbl_map(function(t) return string.format("%-10s %s", t.prefix .. ":", t.desc) end, types),
		{ prompt = git_icon .. " Commit type:" },
		function(_, idx)
			if not idx then return end
			local chosen = types[idx]
			vim.ui.input({ prompt = "Scope (optional): " }, function(scope)
				---@type string
				local prefix
				if scope and scope ~= "" then
					prefix = chosen.prefix .. "(" .. scope .. "): "
				else
					prefix = chosen.prefix .. ": "
				end
				local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
				local cleaned = first_line:gsub("^%w+%(?[%w%-]*%)?:%s*", "")
				vim.api.nvim_buf_set_lines(0, 0, 1, false, { prefix .. cleaned })
				vim.api.nvim_win_set_cursor(0, { 1, #prefix + #cleaned })
				vim.cmd("startinsert!")
			end)
		end
	)
end, { desc = git_icon .. " Conventional prefix" })

--- Add a Co-authored-by trailer to the commit message.
---
--- Prompts for the co-author's name and email, then appends
--- the trailer at the end of the message (after a blank line
--- separator if needed).
---
--- Format: `Co-authored-by: Name <email>`
keys.lang_map("gitcommit", "n", "<leader>la", function()
	vim.ui.input({ prompt = "Co-author name: " }, function(name)
		if not name or name == "" then return end
		vim.ui.input({ prompt = "Email: " }, function(email)
			if not email or email == "" then return end
			local trailer = string.format("Co-authored-by: %s <%s>", name, email)
			local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			if lines[#lines] ~= "" and not lines[#lines]:match("^[%w%-]+:") then
				lines[#lines + 1] = ""
			end
			lines[#lines + 1] = trailer
			vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
			vim.notify("Added: " .. trailer, vim.log.levels.INFO, { title = "Git" })
		end)
	end)
end, { desc = git_icon .. " Co-authored-by" })

--- Add a Signed-off-by trailer from git config.
---
--- Reads `user.name` and `user.email` from git config and appends
--- the Signed-off-by trailer. Checks for duplicates to prevent
--- adding the same signature twice.
---
--- Format: `Signed-off-by: Name <email>`
keys.lang_map("gitcommit", "n", "<leader>ls", function()
	local name = vim.fn.system("git config user.name"):gsub("%s+$", "")
	local email = vim.fn.system("git config user.email"):gsub("%s+$", "")
	if name == "" or email == "" then
		vim.notify("Git user.name/email not configured", vim.log.levels.WARN, { title = "Git" })
		return
	end
	local trailer = string.format("Signed-off-by: %s <%s>", name, email)
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	-- ── Duplicate check ──────────────────────────────────────────────
	for _, line in ipairs(lines) do
		if line == trailer then
			vim.notify("Already signed off", vim.log.levels.INFO, { title = "Git" })
			return
		end
	end

	if lines[#lines] ~= "" and not lines[#lines]:match("^[%w%-]+:") then
		lines[#lines + 1] = ""
	end
	lines[#lines + 1] = trailer
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.notify("Added: " .. trailer, vim.log.levels.INFO, { title = "Git" })
end, { desc = git_icon .. " Signed-off-by" })

--- Insert a ticket/issue reference into the commit message.
---
--- Prompts for the issue identifier (e.g. `#123`, `JIRA-456`).
--- If the subject line can accommodate it (< 72 chars), appends
--- it in parentheses. Otherwise adds a `Refs:` trailer.
keys.lang_map("gitcommit", "n", "<leader>lt", function()
	vim.ui.input({ prompt = "Issue/ticket (e.g. #123, JIRA-456): " }, function(ref)
		if not ref or ref == "" then return end
		local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
		if #first_line + #ref + 3 < 72 then
			-- ── Inline in subject ────────────────────────────────────
			vim.api.nvim_buf_set_lines(0, 0, 1, false, { first_line .. " (" .. ref .. ")" })
		else
			-- ── Add as trailer ───────────────────────────────────────
			local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			if lines[#lines] ~= "" and not lines[#lines]:match("^[%w%-]+:") then
				lines[#lines + 1] = ""
			end
			lines[#lines + 1] = "Refs: " .. ref
			vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
		end
	end)
end, { desc = git_icon .. " Issue reference" })

--- Insert a BREAKING CHANGE trailer and add `!` to the subject.
---
--- Prompts for a breaking change description, then:
--- 1. Appends `BREAKING CHANGE: <desc>` as a trailer
--- 2. Modifies the subject line to include `!` after the type/scope
---    (e.g. `feat!: ` or `feat(api)!: `)
keys.lang_map("gitcommit", "n", "<leader>lb", function()
	vim.ui.input({ prompt = "Breaking change description: " }, function(desc)
		if not desc or desc == "" then return end
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

		-- ── Add trailer ──────────────────────────────────────────────
		if lines[#lines] ~= "" and not lines[#lines]:match("^[%w%-]+:") then
			lines[#lines + 1] = ""
		end
		lines[#lines + 1] = "BREAKING CHANGE: " .. desc

		-- ── Add ! to subject line ────────────────────────────────────
		local first = lines[1]
		local modified = first:gsub("^(%w+%(?[%w%-]*%)?)(:%s)", "%1!%2")
		lines[1] = modified

		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
		vim.notify("Breaking change added", vim.log.levels.WARN, { title = "Git" })
	end)
end, { desc = icons.diagnostics.Warn .. " Breaking change" })

--- Show the staged diff in a vertical split.
---
--- Creates a read-only scratch buffer with `git diff --cached` output
--- and sets its filetype to `diff` for syntax highlighting.
--- Notifies the user if there are no staged changes.
keys.lang_map("gitcommit", "n", "<leader>ld", function()
	local result = vim.fn.system("git diff --cached --stat 2>/dev/null")
	if result == "" then
		vim.notify("No staged changes", vim.log.levels.INFO, { title = "Git" })
		return
	end
	local buf = vim.api.nvim_create_buf(false, true)
	local full_diff = vim.fn.system("git diff --cached")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(full_diff, "\n"))
	vim.api.nvim_set_option_value("filetype", "diff", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.cmd.vsplit()
	vim.api.nvim_win_set_buf(0, buf)
end, { desc = icons.git.Diff .. " Staged diff" })

--- Show commit message statistics.
---
--- Displays:
--- • Subject line length (with quality indicator: ✓ ≤50, ⚠ ≤72, ✗ >72)
--- • Body line count (excluding comments)
--- • Trailer count
--- • Staged changes summary
keys.lang_map("gitcommit", "n", "<leader>li", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local first_line = lines[1] or ""

	---@type integer
	local body_lines = 0
	---@type integer
	local trailers = 0

	for i = 2, #lines do
		if lines[i]:match("^[%w%-]+:") then
			trailers = trailers + 1
		elseif lines[i] ~= "" and not lines[i]:match("^#") then
			body_lines = body_lines + 1
		end
	end

	local staged = vim.fn.system("git diff --cached --shortstat 2>/dev/null"):gsub("%s+$", "")
	local stats = string.format(
		"%s Commit Stats:\n  Subject:  %d chars (%s)\n  Body:     %d lines\n  Trailers: %d\n  ─────────────────\n  Staged:   %s",
		git_icon,
		#first_line,
		#first_line <= 50 and "✓ good" or (#first_line <= 72 and "⚠ long" or "✗ too long"),
		body_lines,
		trailers,
		staged ~= "" and staged or "none"
	)
	vim.notify(stats, vim.log.levels.INFO, { title = "Git" })
end, { desc = icons.diagnostics.Info .. " Commit stats" })

--- Open a commit message template.
---
--- Populates the buffer with a commented template showing the
--- conventional commit format, body guidelines, and available
--- trailer types. Only applies if the first line is empty.
keys.lang_map("gitcommit", "n", "<leader>le", function()
	---@type string[]
	local template = {
		"",
		"",
		"# --- Subject line (50 chars max) ---",
		"# type(scope): description",
		"#",
		"# --- Body (72 chars per line) ---",
		"# Explain WHAT and WHY, not HOW",
		"#",
		"# --- Trailers ---",
		"# Co-authored-by: Name <email>",
		"# Signed-off-by: Name <email>",
		"# Refs: #123",
		"# BREAKING CHANGE: description",
		"#",
		"# Types: feat fix docs style refactor perf test build ci chore revert",
	}

	local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
	if first_line == "" then
		vim.api.nvim_buf_set_lines(0, 0, -1, false, template)
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		vim.cmd("startinsert")
	end
end, { desc = git_icon .. " Commit template" })

--- Clear the commit message and start fresh.
---
--- Preserves all comment lines (starting with `#`) and removes
--- everything else, leaving a blank first line in insert mode.
keys.lang_map("gitcommit", "n", "<leader>lr", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	---@type string[]
	local comments = {}
	for _, line in ipairs(lines) do
		if line:match("^#") then comments[#comments + 1] = line end
	end

	---@type string[]
	local result = { "" }
	for _, c in ipairs(comments) do
		result[#result + 1] = c
	end

	vim.api.nvim_buf_set_lines(0, 0, -1, false, result)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.cmd("startinsert")
end, { desc = icons.ui.Refresh .. " Reset message" })

--- Open the Conventional Commits specification in the system browser.
keys.lang_map("gitcommit", "n", "<leader>lh", function()
	vim.ui.open("https://www.conventionalcommits.org/en/v1.0.0/")
end, { desc = icons.ui.Note .. " Conventional commits ref" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — GITREBASE: INTERACTIVE REBASE HELPERS
--
-- Quick action replacement for interactive rebase lines.
-- Each keymap replaces the first word of the current line with the
-- corresponding rebase action (pick, reword, edit, squash, fixup, drop).
-- ═══════════════════════════════════════════════════════════════════════════

--- Replace the rebase action on the current line.
---
--- Substitutes the first word (the rebase command) with the given action.
--- No-ops silently if the line format doesn't match.
---
--- ```lua
--- rebase_action("squash")  -- changes "pick abc123" → "squash abc123"
--- ```
---
---@param action string The rebase action to set ("pick", "reword", "edit", "squash", "fixup", "drop")
---@return function handler The keymap callback function
---@private
local function rebase_action(action)
	return function()
		local line = vim.api.nvim_get_current_line()
		local new_line = line:gsub("^%w+", action, 1)
		if new_line ~= line then
			vim.api.nvim_set_current_line(new_line)
		end
	end
end

--- Set rebase action to `pick` (use commit as-is).
keys.lang_map("gitrebase", "n", "<leader>lp", rebase_action("pick"), { desc = git_icon .. " Pick" })

--- Set rebase action to `reword` (use commit, edit message).
keys.lang_map("gitrebase", "n", "<leader>lr", rebase_action("reword"), { desc = git_icon .. " Reword" })

--- Set rebase action to `edit` (use commit, stop for amending).
keys.lang_map("gitrebase", "n", "<leader>le", rebase_action("edit"), { desc = git_icon .. " Edit" })

--- Set rebase action to `squash` (meld into previous commit).
keys.lang_map("gitrebase", "n", "<leader>ls", rebase_action("squash"), { desc = git_icon .. " Squash" })

--- Set rebase action to `fixup` (like squash, discard message).
keys.lang_map("gitrebase", "n", "<leader>lf", rebase_action("fixup"), { desc = git_icon .. " Fixup" })

--- Set rebase action to `drop` (remove commit entirely).
keys.lang_map("gitrebase", "n", "<leader>ld", rebase_action("drop"), { desc = git_icon .. " Drop" })

--- Show a quick reference for interactive rebase actions.
keys.lang_map("gitrebase", "n", "<leader>lh", function()
	vim.notify(
		git_icon
			.. " Rebase actions:\n"
			.. "  p  pick    = use commit\n"
			.. "  r  reword  = use commit, edit message\n"
			.. "  e  edit    = use commit, stop for amending\n"
			.. "  s  squash  = meld into previous commit\n"
			.. "  f  fixup   = like squash, discard message\n"
			.. "  d  drop    = remove commit",
		vim.log.levels.INFO,
		{ title = "Git Rebase" }
	)
end, { desc = icons.ui.Note .. " Rebase help" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — GITCONFIG: CONFIG FILE EDITING
--
-- Git configuration viewing, editing, and management tools.
-- Supports global, local, system, and worktree scopes.
-- ═══════════════════════════════════════════════════════════════════════════

--- Show all git config entries merged from all scopes.
---
--- Opens a read-only vertical split with `git config --list --show-origin
--- --show-scope` output, showing every config key with its source file
--- and scope.
keys.lang_map("gitconfig", "n", "<leader>ls", function()
	if vim.fn.executable("git") ~= 1 then
		vim.notify("git not found", vim.log.levels.ERROR, { title = "Git" })
		return
	end
	local buf = vim.api.nvim_create_buf(false, true)
	local result = vim.fn.system("git config --list --show-origin --show-scope 2>&1")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result, "\n"))
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.cmd.vsplit()
	vim.api.nvim_win_set_buf(0, buf)
end, { desc = git_icon .. " Show all config" })

--- List git config entries filtered by scope.
---
--- Presents a picker with available scopes:
--- • local    — repository-level (.git/config)
--- • global   — user-level (~/.gitconfig)
--- • system   — system-level (/etc/gitconfig)
--- • worktree — worktree-level (multi-worktree setups)
---
--- Opens the result in a read-only vertical split with gitconfig
--- syntax highlighting.
keys.lang_map("gitconfig", "n", "<leader>ll", function()
	if vim.fn.executable("git") ~= 1 then
		vim.notify("git not found", vim.log.levels.ERROR, { title = "Git" })
		return
	end

	---@type string[]
	local scopes = { "local", "global", "system", "worktree" }

	vim.ui.select(scopes, { prompt = git_icon .. " Config scope:" }, function(scope)
		if not scope then return end
		local result = vim.fn.system("git config --" .. scope .. " --list 2>&1")
		if result == "" or vim.v.shell_error ~= 0 then
			vim.notify("No " .. scope .. " config found", vim.log.levels.INFO, { title = "Git" })
			return
		end
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result, "\n"))
		vim.api.nvim_set_option_value("filetype", "gitconfig", { buf = buf })
		vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
		vim.cmd.vsplit()
		vim.api.nvim_win_set_buf(0, buf)
	end)
end, { desc = git_icon .. " List config (scoped)" })

--- Edit the global gitconfig file.
---
--- Resolution order:
--- 1. `~/.gitconfig` — traditional location
--- 2. `~/.config/git/config` — XDG-compliant location
keys.lang_map("gitconfig", "n", "<leader>le", function()
	local global_config = vim.fn.expand("~/.gitconfig")
	if vim.fn.filereadable(global_config) ~= 1 then
		global_config = vim.fn.expand("~/.config/git/config")
	end
	if vim.fn.filereadable(global_config) == 1 then
		vim.cmd.edit(global_config)
	else
		vim.notify("No global gitconfig found", vim.log.levels.WARN, { title = "Git" })
	end
end, { desc = git_icon .. " Edit global config" })

--- Edit the system gitconfig file.
---
--- Resolution order:
--- 1. Path from `git config --system --list --show-origin`
--- 2. Common fallback paths:
---    • `/etc/gitconfig`
---    • `/usr/local/etc/gitconfig`
---    • `/opt/homebrew/etc/gitconfig` (macOS Homebrew)
keys.lang_map("gitconfig", "n", "<leader>lE", function()
	local system_config = vim.fn.system("git config --system --list --show-origin 2>/dev/null"):match("file:(%S+)")
	if system_config and vim.fn.filereadable(system_config) == 1 then
		vim.cmd.edit(system_config)
		return
	end

	---@type string[]
	local candidates = { "/etc/gitconfig", "/usr/local/etc/gitconfig", "/opt/homebrew/etc/gitconfig" }
	for _, path in ipairs(candidates) do
		if vim.fn.filereadable(path) == 1 then
			vim.cmd.edit(path)
			return
		end
	end

	vim.notify("No system gitconfig found", vim.log.levels.WARN, { title = "Git" })
end, { desc = git_icon .. " Edit system config" })

--- Add a git alias interactively.
---
--- Prompts for:
--- 1. Alias name
--- 2. Git command
--- 3. Scope (global or local)
---
--- Runs `git config --<scope> alias.<name> <command>` and reloads
--- the buffer if editing the same config file.
keys.lang_map("gitconfig", "n", "<leader>la", function()
	if vim.fn.executable("git") ~= 1 then return end
	vim.ui.input({ prompt = "Alias name: " }, function(name)
		if not name or name == "" then return end
		vim.ui.input({ prompt = "Command: " }, function(cmd)
			if not cmd or cmd == "" then return end
			vim.ui.select({ "global", "local" }, { prompt = git_icon .. " Scope:" }, function(scope)
				if not scope then return end
				local result = vim.fn.system(
					"git config --" .. scope .. " alias." .. name .. " " .. vim.fn.shellescape(cmd) .. " 2>&1"
				)
				if vim.v.shell_error == 0 then
					vim.notify(
						string.format("Added %s alias: %s = %s", scope, name, cmd),
						vim.log.levels.INFO,
						{ title = "Git" }
					)
					vim.cmd.edit()
				else
					vim.notify("Error:\n" .. result, vim.log.levels.ERROR, { title = "Git" })
				end
			end)
		end)
	end)
end, { desc = git_icon .. " Add alias" })

--- Show git user identity and signing configuration.
---
--- Displays:
--- • Name and email from git config
--- • GPG signing key (if configured)
--- • commit.gpgsign setting
--- • gpg.format (openpgp, ssh, x509)
keys.lang_map("gitconfig", "n", "<leader>lu", function()
	if vim.fn.executable("git") ~= 1 then return end
	local name = vim.fn.system("git config user.name 2>/dev/null"):gsub("%s+$", "")
	local email = vim.fn.system("git config user.email 2>/dev/null"):gsub("%s+$", "")
	local signing = vim.fn.system("git config user.signingkey 2>/dev/null"):gsub("%s+$", "")
	local gpg_sign = vim.fn.system("git config commit.gpgsign 2>/dev/null"):gsub("%s+$", "")
	local gpg_format = vim.fn.system("git config gpg.format 2>/dev/null"):gsub("%s+$", "")

	---@type string[]
	local info = {
		git_icon .. " Git User:",
		"",
		"  Name:      " .. (name ~= "" and name or "not set"),
		"  Email:     " .. (email ~= "" and email or "not set"),
		"  Signing:   " .. (signing ~= "" and signing or "not set"),
		"  GPG sign:  " .. (gpg_sign ~= "" and gpg_sign or "false"),
		"  GPG format:" .. (gpg_format ~= "" and (" " .. gpg_format) or " openpgp"),
	}
	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Git" })
end, { desc = git_icon .. " User info" })

--- Show configured git remotes.
---
--- Displays `git remote -v` output in a notification.
--- Notifies if no remotes are configured or not in a repository.
keys.lang_map("gitconfig", "n", "<leader>lr", function()
	if vim.fn.executable("git") ~= 1 then return end
	local result = vim.fn.system("git remote -v 2>&1")
	if result == "" or vim.v.shell_error ~= 0 then
		vim.notify("No remotes configured (or not in a repo)", vim.log.levels.INFO, { title = "Git" })
		return
	end
	vim.notify(git_icon .. " Remotes:\n" .. result, vim.log.levels.INFO, { title = "Git" })
end, { desc = git_icon .. " Show remotes" })

--- Show gitconfig file statistics.
---
--- Analyzes the current buffer and displays:
--- • Total line count
--- • Number of `[section]` headers
--- • Number of key-value pairs
--- • Number of aliases (keys under `[alias]`)
--- • Number of comment lines
keys.lang_map("gitconfig", "n", "<leader>li", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	---@type integer
	local sections = 0
	---@type integer
	local keys_count = 0
	---@type integer
	local comments = 0
	---@type integer
	local aliases = 0
	---@type string
	local current_section = ""

	for _, line in ipairs(lines) do
		if line:match("^%s*#") or line:match("^%s*;") then
			comments = comments + 1
		elseif line:match("^%[(.-)%]") then
			sections = sections + 1
			current_section = line:match("^%[(.-)%]")
		elseif line:match("^%s+%w") then
			keys_count = keys_count + 1
			if current_section:match("^alias") then aliases = aliases + 1 end
		end
	end

	vim.notify(
		string.format(
			"%s Config Stats:\n  Lines:     %d\n  Sections:  %d\n  Keys:      %d\n  Aliases:   %d\n  Comments:  %d",
			git_icon,
			#lines,
			sections,
			keys_count,
			aliases,
			comments
		),
		vim.log.levels.INFO,
		{ title = "Git" }
	)
end, { desc = icons.diagnostics.Info .. " Config stats" })

--- Open git-config documentation in the system browser.
---
--- Presents a picker with key reference pages:
--- • git-config Reference — full configuration variable documentation
--- • Git Aliases          — alias creation guide
--- • Signing Commits      — GPG/SSH commit signing setup
--- • Git Credentials      — credential helper configuration
keys.lang_map("gitconfig", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "git-config Reference", url = "https://git-scm.com/docs/git-config" },
		{ name = "Git Aliases", url = "https://git-scm.com/book/en/v2/Git-Basics-Git-Aliases" },
		{ name = "Signing Commits", url = "https://git-scm.com/book/en/v2/Git-Tools-Signing-Your-Work" },
		{ name = "Git Credentials", url = "https://git-scm.com/docs/gitcredentials" },
	}

	vim.ui.select(
		vim.tbl_map(function(r) return r.name end, refs),
		{ prompt = git_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Git config reference" })

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- All specs are returned as a list and merged by lazy.nvim with the
-- base plugin configurations.
--
-- Loading strategy:
-- ┌────────────────────────────────────────┬──────────────────────────────────────────────┐
-- │ Plugin                                 │ How it lazy-loads for Git                    │
-- ├────────────────────────────────────────┼──────────────────────────────────────────────┤
-- │ nvim-treesitter                        │ opts merge (git parsers added)               │
-- └────────────────────────────────────────┴──────────────────────────────────────────────┘
--
-- NOTE: Git filetypes do not use LSP, formatter, linter, or DAP.
-- All intelligence is provided by Neovim built-ins, treesitter parsers,
-- and the buffer-local keymaps defined above.
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[] specs Lazy.nvim plugin specifications for Git filetypes
return {
	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	-- git_config:     syntax highlighting for gitconfig files
	-- git_rebase:     syntax highlighting for interactive rebase
	-- gitcommit:      syntax highlighting for commit messages
	-- gitignore:      syntax highlighting for .gitignore
	-- gitattributes:  syntax highlighting for .gitattributes
	-- diff:           syntax highlighting for diff/patch output
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"git_config",
				"git_rebase",
				"gitcommit",
				"gitignore",
				"gitattributes",
				"diff",
			},
		},
	},
}
