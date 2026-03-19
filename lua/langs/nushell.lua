---@file lua/langs/nushell.lua
---@description Nushell — LSP (nu --lsp), formatter, treesitter & buffer-local keymaps
---@module "langs.nushell"
---@author ca971
---@license MIT
---@version 2.0.0
---@since 2026-01
---
---@see core.settings            Language enable/disable guard
---@see core.keymaps             Buffer-local keymap API
---@see core.icons               Shared icon definitions
---@see core.mini-align-registry Alignment preset registration
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  langs/nushell.lua — Nushell language support (v3)                       ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  MODULE LEVEL (runs at lazy.nvim import):                        │    ║
--- ║  │  ├─ vim.filetype.add()        *.nu → filetype "nu"               │    ║
--- ║  │  ├─ vim.treesitter.language   Register parser ↔ filetype         │    ║
--- ║  │  ├─ FileType autocmd          Buffer opts + LSP + TS highlight   │    ║
--- ║  │  └─ :NushellCheck command     Diagnostics for troubleshooting    │    ║
--- ║  │                                                                  │    ║
--- ║  │  RETURN SPECS (merged by lazy.nvim):                             │    ║
--- ║  │  └─ nvim-treesitter           ensure_installed = { "nu" }        │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_language_enabled("nushell") then return {} end

-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTS
-- ═══════════════════════════════════════════════════════════════════════════

local keys = require("core.keymaps")
local icons = require("core.icons")

---@type string
local nu_icon = icons.lang.nushell:gsub("%s+$", "")

-- ═══════════════════════════════════════════════════════════════════════════
-- WHICH-KEY GROUP
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_group("nu", "Nushell", nu_icon)

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

---@return boolean
---@private
local function check_nu()
	if vim.fn.executable("nu") ~= 1 then
		vim.notify("nu not found in PATH", vim.log.levels.ERROR, { title = "Nushell" })
		return false
	end
	return true
end

---@param cmd string
---@param save? boolean
---@return boolean
---@private
local function run_nu(cmd, save)
	if not check_nu() then return false end
	if save then vim.cmd("silent! write") end
	vim.cmd.split()
	vim.cmd.terminal(cmd)
	return true
end

---@param lines string[]
---@private
local function open_scratch(lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.cmd.split()
	vim.api.nvim_win_set_buf(0, buf)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — RUN
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("nu", "n", "<leader>lr", function()
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	run_nu("nu " .. file, true)
end, { desc = icons.ui.Play .. " Run file" })

keys.lang_map("nu", "n", "<leader>lR", function()
	if not check_nu() then return end
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then return end
		vim.cmd.split()
		vim.cmd.terminal("nu " .. file .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

keys.lang_map("nu", "n", "<leader>le", function()
	if not check_nu() then return end
	local line = vim.api.nvim_get_current_line():gsub("^%s+", "")
	if line == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("nu -c " .. vim.fn.shellescape(line))
end, { desc = nu_icon .. " Execute line" })

keys.lang_map("nu", "v", "<leader>le", function()
	if not check_nu() then return end
	vim.cmd('noautocmd normal! "zy')
	local code = vim.fn.getreg("z")
	if code == "" then return end
	vim.cmd.split()
	vim.cmd.terminal("nu -c " .. vim.fn.shellescape(code))
end, { desc = nu_icon .. " Execute selection" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — REPL / SOURCE
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("nu", "n", "<leader>lc", function()
	run_nu("nu -i")
end, { desc = icons.ui.Terminal .. " Nu REPL" })

keys.lang_map("nu", "n", "<leader>ls", function()
	if not check_nu() then return end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("nu -c 'source " .. file .. "'")
end, { desc = nu_icon .. " Source file" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — TEST
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("nu", "n", "<leader>lt", function()
	if not check_nu() then return end
	vim.cmd("silent! write")
	local cwd = vim.fn.getcwd()
	if vim.fn.filereadable(cwd .. "/tests/mod.nu") == 1 then
		vim.cmd.split()
		vim.cmd.terminal("nu tests/mod.nu")
	else
		local file = vim.fn.shellescape(vim.fn.expand("%:p"))
		vim.cmd.split()
		vim.cmd.terminal("nu " .. file)
	end
end, { desc = icons.dev.Test .. " Run tests" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — LINT
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("nu", "n", "<leader>ll", function()
	if not check_nu() then return end
	vim.cmd("silent! write")
	local file = vim.fn.shellescape(vim.fn.expand("%:p"))
	local result = vim.fn.system("nu --ide-check 10 " .. file .. " 2>&1")
	if result == "" or result:match("^%s*$") then
		vim.notify("✓ No issues found", vim.log.levels.INFO, { title = "Nushell" })
	else
		open_scratch(vim.split(result, "\n"))
	end
end, { desc = nu_icon .. " Lint (--ide-check)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — FORMAT
--
-- Nushell has no stable formatter:
--   • nu --lsp does NOT support textDocument/formatting
--   • nufmt is not on crates.io (experimental)
--   • topiary doesn't support nushell
--
-- We provide basic indent-based formatting via Neovim's built-in
-- gg=G (treesitter indentation) as a pragmatic fallback.
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("nu", { "n", "v" }, "<leader>lf", function()
	-- 1. Try conform (in case user installs nufmt later)
	local conform_ok, conform = pcall(require, "conform")
	if conform_ok then
		local formatters = conform.list_formatters(0)
		if #formatters > 0 then
			conform.format({ bufnr = 0, timeout_ms = 5000 })
			return
		end
	end

	-- 2. Treesitter-based reindent (always available since we have the parser)
	local cursor = vim.api.nvim_win_get_cursor(0)
	vim.cmd("silent normal! gg=G")
	pcall(vim.api.nvim_win_set_cursor, 0, cursor)
	vim.notify(
		"Reindented with treesitter.\n\n"
			.. "No dedicated Nushell formatter available yet.\n"
			.. "nufmt: cargo install --git https://github.com/nushell/nufmt",
		vim.log.levels.INFO,
		{ title = "Nushell" }
	)
end, { desc = nu_icon .. " Format (reindent)" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — MODULE / OVERLAY
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("nu", "n", "<leader>lm", function()
	run_nu("nu -c 'help modules'")
end, { desc = nu_icon .. " Modules" })

keys.lang_map("nu", "n", "<leader>lp", function()
	run_nu("nu -c 'overlay list'")
end, { desc = nu_icon .. " Overlays" })

-- ═══════════════════════════════════════════════════════════════════════════
-- KEYMAPS — DOCUMENTATION
-- ═══════════════════════════════════════════════════════════════════════════

keys.lang_map("nu", "n", "<leader>li", function()
	if not check_nu() then return end
	local version = vim.fn.system("nu --version 2>/dev/null"):gsub("%s+$", "")
	---@type string[]
	local info = {
		nu_icon .. " Nushell Info:",
		"",
		"  Version: " .. version,
		"  CWD:     " .. vim.fn.getcwd(),
		"",
		"  Tools:",
	}
	for _, tool in ipairs({ "nu", "nufmt" }) do
		local status = vim.fn.executable(tool) == 1 and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end
	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Nushell" })
end, { desc = icons.diagnostics.Info .. " Nushell info" })

keys.lang_map("nu", "n", "<leader>lh", function()
	---@type { name: string, url: string }[]
	local refs = {
		{ name = "Nushell Book", url = "https://www.nushell.sh/book/" },
		{ name = "Nushell Commands", url = "https://www.nushell.sh/commands/" },
		{ name = "Nushell Cookbook", url = "https://www.nushell.sh/cookbook/" },
		{ name = "Nushell GitHub", url = "https://github.com/nushell/nushell" },
	}
	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = nu_icon .. " Documentation:" },
		function(_, idx)
			if idx then vim.ui.open(refs[idx].url) end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- MINI.ALIGN PRESETS
-- ═══════════════════════════════════════════════════════════════════════════

do
	local align_ok, align_registry = pcall(require, "core.mini-align-registry")
	if align_ok and not align_registry.is_language_loaded("nushell") then
		local nu_align_icon = icons.app.Nu
		align_registry.register_many({
			nushell_record = {
				description = "Align Nushell record fields on ':'",
				icon = nu_align_icon,
				split_pattern = ":",
				category = "devops",
				lang = "nushell",
				filetypes = { "nu" },
			},
		})
		align_registry.set_ft_mapping("nu", "nushell_record")
		align_registry.mark_language_loaded("nushell")
		keys.lang_map("nu", { "n", "x" }, "<leader>aL", align_registry.make_align_fn("nushell_record"), {
			desc = nu_align_icon .. "  Align Nushell record",
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RUNTIME SETUP — FILETYPE DETECTION
--
-- Runs at MODULE IMPORT TIME (lazy.nvim loads all spec files at startup).
-- Must execute BEFORE any FileType autocmd fires.
-- ═══════════════════════════════════════════════════════════════════════════

vim.filetype.add({
	extension = {
		nu = "nu",
	},
	filename = {
		["env.nu"] = "nu",
		["config.nu"] = "nu",
		["login.nu"] = "nu",
	},
})

-- ═══════════════════════════════════════════════════════════════════════════
-- RUNTIME SETUP — TREESITTER LANGUAGE REGISTRATION
--
-- Tells Neovim: filetype "nu" → parser "nu".
-- Without this, vim.treesitter.start() cannot resolve which parser
-- to use for custom filetypes.
-- ═══════════════════════════════════════════════════════════════════════════

pcall(vim.treesitter.language.register, "nu", "nu")

-- ═══════════════════════════════════════════════════════════════════════════
-- RUNTIME SETUP — TREESITTER HIGHLIGHT WITH INSTALL + RETRY
--
-- When a .nu file is opened:
--   1. Check if the "nu" parser .so is available
--   2. If yes → start highlighting immediately
--   3. If no  → trigger :TSInstall nu, then retry at intervals
--   4. After successful install → start highlighting + notify user
--
-- This handles first-time setup gracefully (parser not yet compiled).
-- ═══════════════════════════════════════════════════════════════════════════

--- Check if the treesitter parser for a language is fully usable.
--- Uses get_string_parser which is the definitive test (actually creates a parser).
---
---@param lang string Treesitter language name
---@return boolean installed true if a parser can be created
---@private
local function ts_parser_installed(lang)
	-- vim.treesitter.language.add() can return true even when the
	-- parser is unusable on some Neovim versions.
	-- get_string_parser actually tries to create a parser instance.
	local ok = pcall(vim.treesitter.get_string_parser, "", lang)
	return ok
end

--- Check if highlight queries exist for a language.
--- Without queries/lang/highlights.scm, treesitter has no coloring rules.
---
---@param lang string Treesitter language name
---@return boolean available true if highlights.scm is found and parseable
---@private
local function ts_queries_available(lang)
	local ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
	return ok and query ~= nil
end

--- Start treesitter highlighting on a buffer.
--- Checks both parser AND queries before attempting.
---
---@param buf number Buffer handle
---@param lang string Treesitter language name
---@return boolean started
---@private
local function ts_start(buf, lang)
	if not vim.api.nvim_buf_is_valid(buf) then return false end

	if not ts_parser_installed(lang) then
		vim.notify(lang .. " parser not installed.\nRun :TSInstall " .. lang, vim.log.levels.DEBUG, { title = "Nushell" })
		return false
	end

	if not ts_queries_available(lang) then
		vim.notify(
			lang
				.. " highlight queries not found.\n"
				.. "The nushell/tree-sitter-nu plugin may be missing.\n"
				.. "Run :Lazy install tree-sitter-nu",
			vim.log.levels.WARN,
			{ title = "Nushell" }
		)
		return false
	end

	local ok, err = pcall(vim.treesitter.start, buf, lang)
	if not ok then vim.notify("TS highlight failed: " .. tostring(err), vim.log.levels.DEBUG, { title = "Nushell" }) end
	return ok
end

--- Install the treesitter parser and retry highlighting.
--- Retries up to `max_retries` times at `interval_ms` intervals.
---
---@param buf number Buffer handle
---@param lang string Treesitter language name
---@private
local function ts_install_and_retry(buf, lang)
	local max_retries = 15
	local interval_ms = 2000

	vim.notify(
		"Installing " .. lang .. " treesitter parser…\nThis only happens once.",
		vim.log.levels.INFO,
		{ title = "Nushell" }
	)

	-- Trigger installation (non-blocking, runs in background)
	pcall(vim.cmd, "TSInstall " .. lang)

	-- Retry loop: check periodically if the parser became available
	local attempt = 0
	local function retry()
		attempt = attempt + 1
		if attempt > max_retries then
			vim.notify(
				lang .. " parser install timed out.\n" .. "Try manually:\n" .. "  :TSInstall nu\n" .. "  :edit",
				vim.log.levels.WARN,
				{ title = "Nushell" }
			)
			return
		end
		if not vim.api.nvim_buf_is_valid(buf) then return end

		if ts_parser_installed(lang) then
			if ts_start(buf, lang) then
				vim.notify(
					"✓ " .. lang .. " parser ready — highlighting active",
					vim.log.levels.INFO,
					{ title = "Nushell" }
				)
			end
		else
			vim.defer_fn(retry, interval_ms)
		end
	end

	vim.defer_fn(retry, interval_ms)
end

--- Ensure treesitter highlighting is active for a nu buffer.
--- Installs the parser if missing.
---
---@param buf number Buffer handle
---@private
local function ensure_nu_highlighting(buf)
	-- Defer slightly to let nvim-treesitter plugin finish loading
	-- (parsers list, :TSInstall command, etc.)
	vim.defer_fn(function()
		if not vim.api.nvim_buf_is_valid(buf) then return end
		if vim.bo[buf].filetype ~= "nu" then return end

		if ts_parser_installed("nu") then
			ts_start(buf, "nu")
		else
			ts_install_and_retry(buf, "nu")
		end
	end, 500)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- RUNTIME SETUP — FILETYPE AUTOCMD
--
-- Single autocmd handles everything for nu buffers:
--   • Buffer-local options
--   • LSP (nu --lsp via vim.lsp.start)
--   • Treesitter highlighting (with auto-install)
--
-- No dependency on lspconfig or any plugin lifecycle.
-- ═══════════════════════════════════════════════════════════════════════════

local nu_augroup = vim.api.nvim_create_augroup("NushellLang", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
	group = nu_augroup,
	pattern = "nu",
	callback = function(args)
		local buf = args.buf

		-- ── Buffer-local options ─────────────────────────────────
		local opt = vim.opt_local
		opt.wrap = false
		opt.colorcolumn = "100"
		opt.textwidth = 100
		opt.tabstop = 2
		opt.shiftwidth = 2
		opt.softtabstop = 2
		opt.expandtab = true
		opt.number = true
		opt.relativenumber = true
		opt.commentstring = "# %s"

		-- ── LSP: nu --lsp (manual start) ─────────────────────────
		if vim.fn.executable("nu") == 1 then
			vim.lsp.start({
				name = "nushell",
				cmd = { "nu", "--lsp" },
				root_dir = vim.fs.dirname(vim.fs.find({ "env.nu", "config.nu", ".git" }, {
					upward = true,
					path = vim.api.nvim_buf_get_name(buf),
				})[1]) or vim.fn.getcwd(),
				filetypes = { "nu" },
			})
		end

		-- ── Treesitter highlighting (with auto-install) ──────────
		ensure_nu_highlighting(buf)
	end,
})

-- ═══════════════════════════════════════════════════════════════════════════
-- DEBUG COMMAND — :NushellCheck
--
-- Displays a diagnostic summary for troubleshooting Nushell setup.
-- Run this command when highlighting or LSP doesn't work.
-- ═══════════════════════════════════════════════════════════════════════════

vim.api.nvim_create_user_command("NushellCheck", function()
	local lines = { nu_icon .. " Nushell Diagnostics", "" }

	-- Filetype
	local ft = vim.bo.filetype
	lines[#lines + 1] = "  Filetype:        " .. (ft ~= "" and ft or "(empty)")

	-- Treesitter language mapping
	local ts_lang = vim.treesitter.language.get_lang("nu")
	lines[#lines + 1] = "  TS get_lang(nu):  " .. tostring(ts_lang)

	-- Parser installed?
	local parser_ok = pcall(vim.treesitter.language.add, "nu")
	lines[#lines + 1] = "  Parser installed: " .. (parser_ok and "✓ yes" or "✗ NO")

	-- Parser .so location
	if parser_ok then
		local parser_path = vim.api.nvim_get_runtime_file("parser/nu.so", false)
		if #parser_path == 0 then parser_path = vim.api.nvim_get_runtime_file("parser/nu.dylib", false) end
		lines[#lines + 1] = "  Parser path:     " .. (#parser_path > 0 and parser_path[1] or "(not found in rtp)")
	end

	-- Highlight queries?
	local has_queries = ts_queries_available("nu")
	lines[#lines + 1] = "  HL queries:      " .. (has_queries and "✓ yes" or "✗ NO")

	-- Query file locations
	local query_files = vim.api.nvim_get_runtime_file("queries/nu/highlights.scm", true)
	lines[#lines + 1] = "  Query files:     " .. #query_files .. " found"
	for _, qf in ipairs(query_files) do
		lines[#lines + 1] = "    → " .. qf
	end

	-- tree-sitter-nu plugin present?
	local ts_nu_paths = vim.api.nvim_get_runtime_file("queries/nu/highlights.scm", true)
	local has_ts_nu_plugin = false
	for _, p in ipairs(ts_nu_paths) do
		if p:find("tree%-sitter%-nu") then
			has_ts_nu_plugin = true
			break
		end
	end
	lines[#lines + 1] = "  tree-sitter-nu:  " .. (has_ts_nu_plugin and "✓ plugin loaded" or "✗ NOT FOUND")

	-- TS highlighting active on current buffer?
	local ts_active = false
	pcall(function()
		-- vim.treesitter.get_parser throws if no parser is active
		local p = vim.treesitter.get_parser(0, "nu")
		ts_active = p ~= nil
	end)
	lines[#lines + 1] = "  TS active (buf):  " .. (ts_active and "✓ yes" or "✗ NO")

	-- LSP
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	local nu_lsp = vim.tbl_filter(function(c)
		return c.name == "nushell"
	end, clients)
	lines[#lines + 1] = "  LSP nushell:     " .. (#nu_lsp > 0 and "✓ active" or "✗ not running")

	-- Formatting capability
	lines[#lines + 1] = ""
	lines[#lines + 1] = "  Formatting:"

	local lsp_can_format = false
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
		if client.name == "nushell" and client.server_capabilities.documentFormattingProvider then lsp_can_format = true end
	end
	lines[#lines + 1] = "    LSP format:    " .. (lsp_can_format and "✓ supported" or "✗ not supported")

	local nufmt = vim.fn.executable("nufmt") == 1
	lines[#lines + 1] = "    nufmt:         " .. (nufmt and "✓ installed" or "✗ not available")
	lines[#lines + 1] = "    fallback:      ✓ treesitter reindent (gg=G)"

	if not nufmt and not lsp_can_format then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "    ℹ No dedicated formatter. <leader>lf uses treesitter reindent."
		lines[#lines + 1] = "      When available: cargo install --git https://github.com/nushell/nufmt"
	end

	-- Installation hint
	if vim.fn.executable("nufmt") ~= 1 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "  ℹ Format uses LSP (nu --lsp)."
		lines[#lines + 1] = "    Optional: cargo install --git https://github.com/nushell/nufmt"
	end

	-- nu binary
	local nu_path = vim.fn.exepath("nu")
	lines[#lines + 1] = "  nu binary:       " .. (nu_path ~= "" and nu_path or "✗ NOT IN PATH")

	-- Compiler (needed for parser compilation)
	local cc = vim.fn.exepath("cc")
	local gcc = vim.fn.exepath("gcc")
	local compiler = cc ~= "" and cc or gcc ~= "" and gcc or nil
	lines[#lines + 1] = "  C compiler:      " .. (compiler and ("✓ " .. compiler) or "✗ NOT FOUND")

	-- Suggestions
	lines[#lines + 1] = ""
	if not parser_ok then
		lines[#lines + 1] = "  ⚠ Parser not installed. Run :TSInstall nu"
		if not compiler then lines[#lines + 1] = "  ⚠ C compiler needed: xcode-select --install" end
	elseif not has_queries then
		lines[#lines + 1] = "  ⚠ No highlight queries found!"
		if not has_ts_nu_plugin then
			lines[#lines + 1] = "    Fix: add { 'nushell/tree-sitter-nu' } to your plugins"
		else
			lines[#lines + 1] = "    Try: :TSUpdate nu  then  :edit"
		end
	elseif not ts_active then
		lines[#lines + 1] = "  ⚠ Parser + queries OK but highlighting not active."
		lines[#lines + 1] = "    Try: :lua vim.treesitter.start(0, 'nu')"
	elseif not topiary and not nufmt then
		lines[#lines + 1] = "  ⚠ No formatter available."
		lines[#lines + 1] = "    brew install topiary       (recommended)"
		lines[#lines + 1] = "    cargo install --git https://github.com/nushell/nufmt"
	else
		lines[#lines + 1] = "  ✓ Everything looks good!"
	end

	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "NushellCheck" })
end, { desc = "Nushell: diagnostic check" })

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM PLUGIN SPECS
--
-- ┌──────────────────────────┬────────────────────────────────────────────┐
-- │ Plugin                   │ What it provides for Nushell               │
-- ├──────────────────────────┼────────────────────────────────────────────┤
-- │ nushell/tree-sitter-nu   │ queries/nu/highlights.scm (coloring rules) │
-- │ nvim-treesitter          │ Parser compilation + management            │
-- │ conform.nvim             │ Formatting (nufmt → LSP fallback)          │
-- └──────────────────────────┴────────────────────────────────────────────┘
-- ═══════════════════════════════════════════════════════════════════════════

---@return LazyPluginSpec[]
return {
	-- ── tree-sitter-nu: highlight queries ──────────────────────────────────
	{
		"nushell/tree-sitter-nu",
		lazy = false,
	},

	-- ── nvim-treesitter: parser compilation ────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = { "nu" },
		},
	},

	-- No conform spec: no stable formatter exists for Nushell.
	-- When nufmt becomes available on crates.io, add:
	--
	-- {
	--     "stevearc/conform.nvim",
	--     opts = {
	--         formatters_by_ft = {
	--             nu = { "nufmt" },
	--         },
	--     },
	-- },
}
