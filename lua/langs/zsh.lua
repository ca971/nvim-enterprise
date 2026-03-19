---@file lua/langs/zsh.lua
---@description Zsh — treesitter, buffer-local keymaps (no dedicated LSP)
---@module "langs.zsh"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see langs.sh   Bash/POSIX sh support (companion module)
---@see langs.lua  Lua language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/zsh.lua — Zsh language support                                    ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("zsh") → {} if off          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (lazy-loaded on ft = "zsh"):                          │    ║
--- ║  │  ├─ LSP          (none — no mature Zsh LSP exists)               │    ║
--- ║  │  ├─ Formatter    (none — shfmt does not support Zsh)             │    ║
--- ║  │  ├─ Linter       zsh -n (syntax check via built-in)              │    ║
--- ║  │  ├─ Treesitter   bash parser (partial Zsh compatibility)         │    ║
--- ║  │  └─ DAP          (none)                                          │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file (zsh)        R  Run with trace (-x)    │    ║
--- ║  │  │            e  Execute line/selection in terminal              │    ║
--- ║  │  ├─ CHECK     i  Syntax check (zsh -n)                           │    ║
--- ║  │  ├─ REPL      c  Interactive zsh                                 │    ║
--- ║  │  └─ DOCS      h  Man page for word      s  Zsh documentation     │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Note: shfmt does NOT support Zsh syntax. No reliable Zsh                ║
--- ║  formatter exists. Formatting is left to manual style or editor          ║
--- ║  indentation commands.                                                   ║
--- ╚══════════════════════════════════════════════════════════════════════════╝
---
-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("zsh") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string
local zsh_icon = (icons.lang.zsh or icons.lang.shell or icons.ui.Terminal or ""):gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("zsh", "Zsh", zsh_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

---@param filepath string
---@return boolean
---@private
local function has_shebang(filepath)
	local f = io.open(filepath, "r")
	if not f then return false end
	local first_line = f:read("*l") or ""
	f:close()
	return first_line:match("^#!") ~= nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("zsh", "n", "<leader>lr", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("zsh " .. vim.fn.shellescape(file))
end, { desc = icons.ui.Play .. " Run file" })

keys.lang_map("zsh", "n", "<leader>lR", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("zsh -x " .. vim.fn.shellescape(file))
end, { desc = zsh_icon .. " Run with trace (set -x)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — EXECUTE
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("zsh", "n", "<leader>le", function()
	local line = vim.api.nvim_get_current_line():gsub("^%s+", "")
	if line == "" or line:match("^#") then
		vim.notify("Empty or comment line", vim.log.levels.INFO, { title = "Zsh" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("zsh -c " .. vim.fn.shellescape(line))
end, { desc = zsh_icon .. " Execute current line" })

keys.lang_map("zsh", "v", "<leader>le", function()
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code ~= "" then
		vim.cmd.split()
		vim.cmd.terminal("zsh -c " .. vim.fn.shellescape(code))
	end
end, { desc = zsh_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("zsh", "n", "<leader>lc", function()
	vim.cmd.split()
	vim.cmd.terminal("zsh")
end, { desc = icons.ui.Terminal .. " REPL" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — SYNTAX CHECK
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("zsh", "n", "<leader>li", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local output = vim.fn.system({ "zsh", "-n", file })
	if vim.v.shell_error == 0 then
		vim.notify("Syntax OK", vim.log.levels.INFO, { title = "Zsh" })
	else
		vim.notify("Syntax errors:\n" .. vim.trim(output), vim.log.levels.ERROR, { title = "Zsh" })
	end
end, { desc = icons.diagnostics.Info .. " Syntax check (zsh -n)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FORMAT
--
-- Zsh has NO dedicated formatter (shfmt does not support Zsh).
-- We provide a basic keyword-aware reindent that handles common
-- shell constructs: if/fi, for/done, while/done, case/esac, {/}.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("zsh", { "n", "v" }, "<leader>lf", function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local indent = 0
	local sw = vim.bo.shiftwidth or 4
	local result = {}

	for _, line in ipairs(lines) do
		local trimmed = line:gsub("^%s+", "")

		-- Empty lines / comments: preserve as-is (just trim leading space)
		if trimmed == "" then
			result[#result + 1] = ""
			goto continue
		end

		-- Decrease indent BEFORE writing: fi, done, esac, }, ;;, else, elif
		if
			trimmed:match("^fi%s*$")
			or trimmed:match("^fi[;#%s]")
			or trimmed:match("^done%s*$")
			or trimmed:match("^done[;#%s]")
			or trimmed:match("^esac%s*$")
			or trimmed:match("^esac[;#%s]")
			or trimmed:match("^}%s*$")
			or trimmed:match("^}[;#%s]")
			or trimmed:match("^%;%;%s*$")
		then
			indent = math.max(0, indent - 1)
		end

		-- else/elif: decrease then increase (same level as if)
		if trimmed:match("^else%s*$") or trimmed:match("^else[;#%s]") or trimmed:match("^elif[%s]") then
			indent = math.max(0, indent - 1)
		end

		-- Write the line with current indent
		result[#result + 1] = string.rep(" ", indent * sw) .. trimmed

		-- Increase indent AFTER writing: then, do, else, elif, {, case..in
		if
			trimmed:match("^then%s*$")
			or trimmed:match("^then[;#%s]")
			or trimmed:match("^do%s*$")
			or trimmed:match("^do[;#%s]")
			or trimmed:match("^else%s*$")
			or trimmed:match("^else[;#%s]")
			or trimmed:match("^elif[%s]")
			or trimmed:match("{%s*$")
			or trimmed:match("{%s*#")
			or trimmed:match("in%s*$")
			or trimmed:match("in%s*#")
		then
			indent = indent + 1
		end

		-- One-line patterns: "if ...; then" / "for ...; do" / "while ...; do"
		-- These have the keyword on the SAME line
		if
			(trimmed:match(";%s*then%s*$") or trimmed:match(";%s*then[;#%s]"))
			or (trimmed:match(";%s*do%s*$") or trimmed:match(";%s*do[;#%s]"))
		then
			indent = indent + 1
		end

		-- Function definition: name() {
		if trimmed:match("^[%w_]+%s*%(%)%s*{%s*$") then
			-- Already handled by the { pattern above
		end

		-- case item: pattern)
		if trimmed:match("%)%s*$") and not trimmed:match("^#") and not trimmed:match("esac") then
			-- Check if this looks like a case pattern (not a subshell)
			local in_case = false
			for i = #result - 1, 1, -1 do
				local prev = result[i]:gsub("^%s+", "")
				if prev:match("^case%s") then
					in_case = true
					break
				end
				if prev:match("^esac") or prev:match("^fi") or prev:match("^done") then break end
			end
			if in_case then indent = indent + 1 end
		end

		::continue::
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, result)
	pcall(vim.api.nvim_win_set_cursor, 0, cursor)

	vim.notify("Reindented (keyword-aware)", vim.log.levels.INFO, { title = "Zsh" })
end, { desc = zsh_icon .. " Format (reindent)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("zsh", "n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then
		vim.notify("No word under cursor", vim.log.levels.INFO, { title = "Zsh" })
		return
	end

	---@type string[]
	local patterns = { word, "zsh" .. word, "zshbuiltins", "zshall" }

	for _, pattern in ipairs(patterns) do
		local ok = pcall(vim.cmd, "Man " .. pattern)
		if ok then return end
	end

	vim.notify("No man page for: " .. word, vim.log.levels.INFO, { title = "Zsh" })
end, { desc = icons.ui.Note .. " Man page for word" })

keys.lang_map("zsh", "n", "<leader>ls", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Zsh Manual", url = "https://zsh.sourceforge.io/Doc/Release/" },
		{ name = "Zsh User Guide", url = "https://zsh.sourceforge.io/Guide/" },
		{ name = "Zsh FAQ", url = "https://zsh.sourceforge.io/FAQ/" },
		{ name = "Zsh Wiki", url = "https://zsh-users.sourceforge.io/" },
		{ name = "Zsh Lovers (cheatsheet)", url = "https://grml.org/zsh/zsh-lovers.html" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = zsh_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Zsh docs" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("zsh") then
		align_registry.register_many({
			zsh_assignments = {
				description = "Align Zsh variable assignments on '='",
				icon = zsh_icon,
				split_pattern = "=",
				category = "scripting",
				lang = "zsh",
				filetypes = { "zsh" },
			},
		})

		align_registry.set_ft_mapping("zsh", "zsh_assignments")
		align_registry.mark_language_loaded("zsh")

		keys.lang_map("zsh", { "n", "x" }, "<leader>aZ", align_registry.make_align_fn("zsh_assignments"), {
			desc = zsh_icon .. " Align Zsh assignments",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RUNTIME SETUP — FILETYPE, TREESITTER, BUFFER OPTIONS, CHMOD
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Filetype detection ────────────────────────────────────────────────
-- Neovim detects most zsh files but misses some config files.
vim.filetype.add({
	extension = {
		zsh = "zsh",
	},
	filename = {
		[".zshrc"] = "zsh",
		[".zshenv"] = "zsh",
		[".zprofile"] = "zsh",
		[".zlogout"] = "zsh",
		[".zlogin"] = "zsh",
	},
	pattern = {
		-- oh-my-zsh and similar framework files
		["%.zsh$"] = "zsh",
	},
})

-- ── 2. Treesitter language registration ──────────────────────────────────
-- Zsh has no dedicated treesitter parser.
-- The "bash" parser provides reasonable highlighting for zsh files
-- (keywords, strings, comments, variables, command substitutions).
-- Without this registration, zsh files get NO treesitter highlighting.
pcall(vim.treesitter.language.register, "bash", "zsh")

-- ── 3. Buffer-local options ──────────────────────────────────────────────
local zsh_augroup = vim.api.nvim_create_augroup("ZshLang", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
	group = zsh_augroup,
	pattern = "zsh",
	callback = function()
		local opt = vim.opt_local
		opt.wrap = false
		opt.colorcolumn = "80"
		opt.textwidth = 80
		opt.tabstop = 2
		opt.shiftwidth = 2
		opt.softtabstop = 2
		opt.expandtab = true
		opt.number = true
		opt.relativenumber = true
		opt.commentstring = "# %s"
		opt.foldmethod = "expr"
		-- opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
		opt.foldmethod = "indent"
		opt.foldlevel = 99
	end,
})

-- ── 4. Auto chmod +x on save ────────────────────────────────────────────
-- Applies to *.zsh files
vim.api.nvim_create_autocmd("BufWritePost", {
	group = zsh_augroup,
	pattern = { "*.zsh" },
	callback = function()
		local file = vim.fn.expand("%:p")
		if file == "" then return end
		local perm = vim.fn.getfperm(file)
		if perm ~= "" and not perm:match("x") then
			local result = vim.fn.system({ "chmod", "+x", file })
			if vim.v.shell_error == 0 then
				vim.notify("chmod +x → " .. vim.fn.expand("%:t"), vim.log.levels.INFO, { title = "Zsh" })
			else
				vim.notify("chmod +x failed: " .. vim.trim(result), vim.log.levels.WARN, { title = "Zsh" })
			end
		end
	end,
})

-- Extensionless zsh scripts (with shebang)
vim.api.nvim_create_autocmd("BufWritePost", {
	group = zsh_augroup,
	callback = function()
		if vim.bo.filetype ~= "zsh" then return end

		local name = vim.fn.expand("%:t")
		if name:match("%.zsh$") then return end

		-- Skip zsh config files (not scripts)
		local config_files = { ".zshrc", ".zshenv", ".zprofile", ".zlogout", ".zlogin" }
		for _, cf in ipairs(config_files) do
			if name == cf then return end
		end

		local file = vim.fn.expand("%:p")
		if file == "" then return end
		if not has_shebang(file) then return end

		local perm = vim.fn.getfperm(file)
		if perm ~= "" and not perm:match("x") then
			local result = vim.fn.system({ "chmod", "+x", file })
			if vim.v.shell_error == 0 then
				vim.notify("chmod +x → " .. name, vim.log.levels.INFO, { title = "Zsh" })
			else
				vim.notify("chmod +x failed: " .. vim.trim(result), vim.log.levels.WARN, { title = "Zsh" })
			end
		end
	end,
})

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[]
return {
	-- ── TREESITTER ─────────────────────────────────────────────────────────
	-- bash parser provides partial zsh highlighting.
	-- The language.register() above maps zsh → bash parser.
	-- ───────────────────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"bash",
			},
		},
	},
}
