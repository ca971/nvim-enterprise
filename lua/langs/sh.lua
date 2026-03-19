---@file lua/langs/sh.lua
---@description Shell (Bash/POSIX sh) — LSP (bashls), formatter (shfmt), linter (shellcheck), DAP, treesitter & keymaps
---@module "langs.sh"
---@author ca971
---@license MIT
---@version 1.1.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard
---@see core.keymaps             Buffer-local keymap API
---@see core.icons               Shared icon definitions
---@see core.mini-align-registry Alignment preset registration
---@see langs.lua                Lua language support (same architecture)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/sh.lua — Shell (Bash / POSIX sh) language support                 ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Guard: settings:is_language_enabled("sh") → {} if off           │    ║
--- ║  │                                                                  │    ║
--- ║  │  Toolchain (all lazy-loaded on ft = {"sh","bash"}):              │    ║
--- ║  │  ├─ LSP          bashls  (bash-language-server)                  │    ║
--- ║  │  ├─ Formatter    shfmt   (conform.nvim)                          │    ║
--- ║  │  ├─ Linter       shellcheck (nvim-lint)                          │    ║
--- ║  │  ├─ Treesitter   bash parser                                     │    ║
--- ║  │  ├─ DAP          bash-debug-adapter                              │    ║
--- ║  │  └─ Extras       auto chmod +x on save for *.sh files            │    ║
--- ║  │                                                                  │    ║
--- ║  │  Buffer-local keymaps (<leader>l prefix):                        │    ║
--- ║  │  ├─ RUN       r  Run file (bash/sh)    R  Run with trace (-x)    │    ║
--- ║  │  │            e  Execute line/selection in terminal              │    ║
--- ║  │  ├─ TEST      t  Run tests (bats)                                │    ║
--- ║  │  ├─ DEBUG     d  Debug (bash-debug-adapter / DAP)                │    ║
--- ║  │  ├─ REPL      c  Interactive shell                               │    ║
--- ║  │  ├─ INSPECT   i  ShellCheck wiki lookup                          │    ║
--- ║  │  └─ DOCS      h  Man page for word      s  Shell documentation   │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Buffer options (applied on FileType sh/bash):                           ║
--- ║  • colorcolumn=80, textwidth=80   (Google Shell Style Guide)             ║
--- ║  • tabstop=4, shiftwidth=4        (common shell convention)              ║
--- ║  • expandtab=true                 (spaces, matching shfmt defaults)      ║
--- ║  • Treesitter folding             (foldmethod=expr, foldlevel=99)        ║
--- ║                                                                          ║
--- ║  Auto chmod +x:                                                          ║
--- ║  • Files with *.sh extension are made executable after each save         ║
--- ║  • Only triggers if the file lacks execute permission                    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("sh") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string
local sh_icon = (icons.lang.sh or icons.lang.bash or icons.lang.shell or icons.ui.Terminal or ""):gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("sh", "Shell", sh_icon)
keys.lang_group("bash", "Shell", sh_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- DUAL-FILETYPE HELPER
-- ═══════════════════════════════════════════════════════════════════════════

---@param mode string|string[]
---@param lhs string
---@param rhs function|string
---@param opts table
---@private
local function shell_map(mode, lhs, rhs, opts)
	keys.lang_map("sh", mode, lhs, rhs, opts)
	keys.lang_map("bash", mode, lhs, rhs, opts)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

---@return string interpreter
---@private
local function get_interpreter()
	local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
	if first_line:match("^#!.-bash") then return "bash" end
	if first_line:match("^#!.-sh") then return "sh" end
	if vim.bo.filetype == "bash" then return "bash" end
	return "bash"
end

--- Check if a file has a shell shebang (first line starts with #!).
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

shell_map("n", "<leader>lr", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local interp = get_interpreter()
	vim.cmd.split()
	vim.cmd.terminal(interp .. " " .. vim.fn.shellescape(file))
end, { desc = icons.ui.Play .. " Run file" })

shell_map("n", "<leader>lR", function()
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local interp = get_interpreter()
	vim.cmd.split()
	vim.cmd.terminal(interp .. " -x " .. vim.fn.shellescape(file))
end, { desc = sh_icon .. " Run with trace (set -x)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — EXECUTE
-- ═══════════════════════════════════════════════════════════════════════════

shell_map("n", "<leader>le", function()
	local line = vim.api.nvim_get_current_line():gsub("^%s+", "")
	if line == "" or line:match("^#") then
		vim.notify("Empty or comment line", vim.log.levels.INFO, { title = "Shell" })
		return
	end
	vim.cmd.split()
	vim.cmd.terminal(line)
end, { desc = sh_icon .. " Execute current line" })

shell_map("v", "<leader>le", function()
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code ~= "" then
		vim.cmd.split()
		vim.cmd.terminal(code)
	end
end, { desc = sh_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL
-- ═══════════════════════════════════════════════════════════════════════════

shell_map("n", "<leader>lc", function()
	local interp = get_interpreter()
	vim.cmd.split()
	vim.cmd.terminal(interp)
end, { desc = icons.ui.Terminal .. " REPL" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TESTING
-- ═══════════════════════════════════════════════════════════════════════════

shell_map("n", "<leader>lt", function()
	if vim.fn.executable("bats") == 0 then
		vim.notify(
			"bats not found.\nInstall: https://github.com/bats-core/bats-core",
			vim.log.levels.WARN,
			{ title = "Shell" }
		)
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	local test_file = file

	if not file:match("%.bats$") then
		local bats_file = file:gsub("%.sh$", ".bats")
		if vim.fn.filereadable(bats_file) == 1 then test_file = bats_file end
	end

	vim.cmd.split()
	vim.cmd.terminal("bats " .. vim.fn.shellescape(test_file))
end, { desc = icons.dev.Test .. " Run tests (bats)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DEBUG
-- ═══════════════════════════════════════════════════════════════════════════

shell_map("n", "<leader>ld", function()
	vim.cmd("silent! write")
	local ok, dap = pcall(require, "dap")
	if not ok then
		vim.notify("nvim-dap not available", vim.log.levels.WARN, { title = "Shell" })
		return
	end
	dap.continue()
end, { desc = icons.dev.Debug .. " Debug (DAP)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
-- ═══════════════════════════════════════════════════════════════════════════

shell_map("n", "<leader>lh", function()
	local word = vim.fn.expand("<cword>")
	if word == "" then
		vim.notify("No word under cursor", vim.log.levels.INFO, { title = "Shell" })
		return
	end
	local ok = pcall(vim.cmd, "Man " .. word)
	if not ok then
		ok = pcall(vim.cmd.help, word)
		if not ok then vim.notify("No man page for: " .. word, vim.log.levels.INFO, { title = "Shell" }) end
	end
end, { desc = icons.ui.Note .. " Man page for word" })

shell_map("n", "<leader>ls", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Bash Reference Manual", url = "https://www.gnu.org/software/bash/manual/bash.html" },
		{
			name = "POSIX Shell Specification",
			url = "https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html",
		},
		{ name = "ShellCheck Wiki", url = "https://www.shellcheck.net/wiki/" },
		{ name = "Google Shell Style Guide", url = "https://google.github.io/styleguide/shellguide.html" },
		{ name = "Advanced Bash-Scripting Guide", url = "https://tldp.org/LDP/abs/html/" },
	}

	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = sh_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Shell docs" })

shell_map("n", "<leader>li", function()
	local line = vim.api.nvim_get_current_line()
	local sc_code = line:match("SC%d+")

	if not sc_code then
		local diagnostics = vim.diagnostic.get(0, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 })
		for _, d in ipairs(diagnostics) do
			sc_code = (d.message or ""):match("SC%d+")
			if not sc_code and d.code then
				local code_str = tostring(d.code)
				if code_str:match("^%d+$") then sc_code = "SC" .. code_str end
			end
			if sc_code then break end
		end
	end

	if sc_code then
		vim.ui.open("https://www.shellcheck.net/wiki/" .. sc_code)
	else
		vim.notify("No ShellCheck code found on current line", vim.log.levels.INFO, { title = "Shell" })
	end
end, { desc = icons.diagnostics.Info .. " ShellCheck explain" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")

	if align_ok and not align_registry.is_language_loaded("sh") then
		align_registry.register_many({
			sh_assignments = {
				description = "Align shell variable assignments on '='",
				icon = sh_icon,
				split_pattern = "=",
				category = "scripting",
				lang = "sh",
				filetypes = { "sh", "bash" },
			},
		})

		align_registry.set_ft_mapping("sh", "sh_assignments")
		align_registry.set_ft_mapping("bash", "sh_assignments")
		align_registry.mark_language_loaded("sh")

		shell_map({ "n", "x" }, "<leader>aS", align_registry.make_align_fn("sh_assignments"), {
			desc = sh_icon .. " Align shell assignments",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RUNTIME SETUP — FILETYPE, BUFFER OPTIONS, CHMOD, DAP
--
-- Runs at MODULE IMPORT TIME. Decoupled from any plugin lifecycle.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Buffer-local options ──────────────────────────────────────────────
local sh_augroup = vim.api.nvim_create_augroup("ShellLang", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
	group = sh_augroup,
	pattern = { "sh", "bash" },
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
		opt.foldmethod = "expr"
		opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
		opt.foldlevel = 99
	end,
})

-- ── 2. Auto chmod +x on save ────────────────────────────────────────────
-- Applies to:
--   • *.sh, *.bash files (by pattern)
--   • Any file with sh/bash filetype (catches extensionless scripts)
-- Only sets +x if:
--   • File has a shebang (#!/...)  → prevents false positives
--   • File lacks execute permission → avoids redundant chmod calls
--   • chmod succeeds               → notifies on failure

vim.api.nvim_create_autocmd("BufWritePost", {
	group = sh_augroup,
	pattern = { "*.sh", "*.bash" },
	callback = function()
		local file = vim.fn.expand("%:p")
		if file == "" then return end
		local perm = vim.fn.getfperm(file)
		if perm ~= "" and not perm:match("x") then
			local result = vim.fn.system({ "chmod", "+x", file })
			if vim.v.shell_error == 0 then
				vim.notify("chmod +x → " .. vim.fn.expand("%:t"), vim.log.levels.INFO, { title = "Shell" })
			else
				vim.notify("chmod +x failed: " .. vim.trim(result), vim.log.levels.WARN, { title = "Shell" })
			end
		end
	end,
})

-- Also handle extensionless scripts (e.g. install, setup, bootstrap)
-- These are detected by filetype but don't match *.sh pattern
vim.api.nvim_create_autocmd("BufWritePost", {
	group = sh_augroup,
	callback = function()
		local ft = vim.bo.filetype
		if ft ~= "sh" and ft ~= "bash" then return end

		-- Skip files already handled by the *.sh/*.bash pattern above
		local name = vim.fn.expand("%:t")
		if name:match("%.sh$") or name:match("%.bash$") then return end

		local file = vim.fn.expand("%:p")
		if file == "" then return end

		-- Only chmod if the file has a shebang
		if not has_shebang(file) then return end

		local perm = vim.fn.getfperm(file)
		if perm ~= "" and not perm:match("x") then
			local result = vim.fn.system({ "chmod", "+x", file })
			if vim.v.shell_error == 0 then
				vim.notify("chmod +x → " .. name, vim.log.levels.INFO, { title = "Shell" })
			else
				vim.notify("chmod +x failed: " .. vim.trim(result), vim.log.levels.WARN, { title = "Shell" })
			end
		end
	end,
})

-- ── 3. DAP setup (one-time) ─────────────────────────────────────────────
vim.api.nvim_create_autocmd("FileType", {
	group = sh_augroup,
	pattern = { "sh", "bash" },
	once = true,
	callback = function()
		local ok, dap = pcall(require, "dap")
		if not ok then return end

		local mason_path = vim.fn.stdpath("data") .. "/mason/packages/bash-debug-adapter"
		local bashdb_dir = mason_path .. "/extension/bashdb_dir"

		dap.adapters.bashdb = {
			type = "executable",
			command = mason_path .. "/bash-debug-adapter",
			name = "bashdb",
		}

		dap.configurations.sh = {
			{
				type = "bashdb",
				request = "launch",
				name = "Launch Bash script",
				showDebugOutput = true,
				pathBashdb = bashdb_dir .. "/bashdb",
				pathBashdbLib = bashdb_dir,
				trace = true,
				file = "${file}",
				program = "${file}",
				cwd = "${workspaceFolder}",
				pathCat = "cat",
				pathBash = vim.fn.exepath("bash") or "/bin/bash",
				pathMkfifo = "mkfifo",
				pathPkill = "pkill",
				args = {},
				env = {},
				terminalKind = "integrated",
			},
		}
	end,
})

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[]
return {
	-- ── LSP SERVER (bashls) ────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				bashls = {
					filetypes = { "sh", "bash" },
					settings = {
						bashIde = {
							globPattern = "*@(.sh|.inc|.bash|.command)",
						},
					},
				},
			},
		},
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"bash-language-server",
				"shfmt",
				"shellcheck",
				"bash-debug-adapter",
			},
		},
	},

	-- ── FORMATTER (shfmt) ──────────────────────────────────────────────────
	-- shfmt defaults use TABS. Our buffer options use 4 SPACES.
	-- Without explicit args, shfmt runs but produces no visible change
	-- (or converts spaces → tabs, breaking the indentation style).
	--
	-- Args:
	--   -i 4   → indent with 4 spaces (matches shiftwidth=4)
	--   -ci    → indent switch case bodies
	--   -bn    → allow binary ops to start a line
	--   -sr    → space after redirect operators (> file → > file)
	--   -ln bash → language dialect (bash, not posix)
	-- ───────────────────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		opts = {
			formatters_by_ft = {
				sh = { "shfmt" },
				bash = { "shfmt" },
			},
			formatters = {
				shfmt = {
					prepend_args = { "-i", "4", "-ci", "-bn", "-sr" },
				},
			},
		},
	},

	-- ── LINTER (shellcheck) ────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		opts = {
			linters_by_ft = {
				sh = { "shellcheck" },
				bash = { "shellcheck" },
			},
		},
	},

	-- ── TREESITTER PARSERS ─────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"bash",
			},
		},
	},
}
