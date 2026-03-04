-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  langs/_template.lua — Template for new language support files           ║
-- ║                                                                          ║
-- ║  USAGE:                                                                  ║
-- ║  1. Copy this file to lua/langs/<language>.lua                           ║
-- ║  2. Replace all occurrences of LANG_NAME with your language name         ║
-- ║  3. Replace LANG_KEY with the filetype / settings key                    ║
-- ║  4. Replace LANG_ICON with the icon key from core/icons.lua              ║
-- ║  5. Adjust LSP server, formatter, linter, treesitter grammar             ║
-- ║  6. Add the language to settings.languages.enabled                       ║
-- ║  7. Add the icon to core/icons.lua if not present                        ║
-- ║                                                                          ║
-- ║  CONVENTIONS:                                                            ║
-- ║  • Guard clause: is_language_enabled() at the top                        ║
-- ║  • has_executable(): condition for mason/formatter/linter/LSP            ║
-- ║  • opts = function(_, opts): for conditional plugin configuration        ║
-- ║  • Keys under <leader>l (buffer-local, set via keys.lang_map)            ║
-- ║  • Files starting with _ are ignored by plugin_manager scanner           ║
-- ║                                                                          ║
-- ║  KEYMAPS (buffer-local, applied on FileType)                             ║
-- ║                                                                          ║
-- ║  NORMAL MODE — <leader>l                                                 ║
-- ║    r   Run file                    R   Run with arguments                ║
-- ║    b   Build                       t   Test                              ║
-- ║    c   REPL / console              s   Special (language-specific)       ║
-- ║    l   Lint                        p   Package management                ║
-- ║    d   Debug (DAP)                 i   Project info                      ║
-- ║    h   Documentation (browser)                                           ║
-- ║                                                                          ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- ── Guard clause ─────────────────────────────────────────────────────────
local settings = require("core.settings")
if not settings:is_language_enabled("LANG_KEY") then
	return {}
end

local keys = require("core.keymaps")
local icons = require("core.icons")
local has_executable = require("core.utils").has_executable

local lang_icon = icons.lang.LANG_ICON:gsub("%s+$", "")

-- ── Which-key group ──────────────────────────────────────────────────────
keys.lang_group("LANG_KEY", "LANG_NAME", lang_icon)

-- ── Helper: check runtime is available ───────────────────────────────────
local function check_runtime()
	if not has_executable("RUNTIME_CMD") then
		vim.notify("RUNTIME_CMD not found in PATH", vim.log.levels.ERROR, { title = "LANG_NAME" })
		return false
	end
	return true
end

-- ══════════════════════════════════════════════════════════════════════════
-- RUN
-- ══════════════════════════════════════════════════════════════════════════

--- Run the current file.
keys.lang_map("LANG_KEY", "n", "<leader>lr", function()
	if not check_runtime() then
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("RUNTIME_CMD " .. vim.fn.shellescape(file))
end, { desc = icons.ui.Play .. " Run file" })

--- Run with custom arguments.
keys.lang_map("LANG_KEY", "n", "<leader>lR", function()
	if not check_runtime() then
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.ui.input({ prompt = "Arguments: " }, function(args)
		if args == nil then
			return
		end
		vim.cmd.split()
		vim.cmd.terminal("RUNTIME_CMD " .. vim.fn.shellescape(file) .. " " .. args)
	end)
end, { desc = icons.ui.Play .. " Run with arguments" })

-- ══════════════════════════════════════════════════════════════════════════
-- BUILD / TEST
-- ══════════════════════════════════════════════════════════════════════════

--- Build project.
keys.lang_map("LANG_KEY", "n", "<leader>lb", function()
	if not check_runtime() then
		return
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("BUILD_CMD")
end, { desc = icons.dev.Build .. " Build" })

--- Run tests.
keys.lang_map("LANG_KEY", "n", "<leader>lt", function()
	if not check_runtime() then
		return
	end
	vim.cmd("silent! write")
	vim.cmd.split()
	vim.cmd.terminal("TEST_CMD")
end, { desc = icons.dev.Test .. " Test" })

-- ══════════════════════════════════════════════════════════════════════════
-- REPL / CONSOLE
-- ══════════════════════════════════════════════════════════════════════════

--- Open REPL / interactive console.
keys.lang_map("LANG_KEY", "n", "<leader>lc", function()
	if not check_runtime() then
		return
	end
	vim.cmd.split()
	vim.cmd.terminal("REPL_CMD")
end, { desc = icons.ui.Terminal .. " REPL" })

-- ══════════════════════════════════════════════════════════════════════════
-- LINT
-- ══════════════════════════════════════════════════════════════════════════

--- Run linter manually.
keys.lang_map("LANG_KEY", "n", "<leader>ll", function()
	if not has_executable("LINTER_CMD") then
		vim.notify("Install LINTER_CMD", vim.log.levels.WARN, { title = "LANG_NAME" })
		return
	end
	vim.cmd("silent! write")
	local file = vim.fn.expand("%:p")
	vim.cmd.split()
	vim.cmd.terminal("LINTER_CMD " .. vim.fn.shellescape(file))
end, { desc = lang_icon .. " Lint" })

-- ══════════════════════════════════════════════════════════════════════════
-- PACKAGE MANAGEMENT
-- ══════════════════════════════════════════════════════════════════════════

--- Package / dependency management picker.
keys.lang_map("LANG_KEY", "n", "<leader>lp", function()
	local actions = {
		{ name = "Install…", cmd = "PKG_INSTALL_CMD", prompt = true },
		{ name = "Update", cmd = "PKG_UPDATE_CMD" },
		{ name = "List", cmd = "PKG_LIST_CMD" },
	}
	vim.ui.select(
		vim.tbl_map(function(a)
			return a.name
		end, actions),
		{ prompt = lang_icon .. " Packages:" },
		function(_, idx)
			if not idx then
				return
			end
			local action = actions[idx]
			if action.prompt then
				vim.ui.input({ prompt = "Package: " }, function(name)
					if not name or name == "" then
						return
					end
					vim.cmd.split()
					vim.cmd.terminal(action.cmd .. " " .. vim.fn.shellescape(name))
				end)
			else
				vim.cmd.split()
				vim.cmd.terminal(action.cmd)
			end
		end
	)
end, { desc = icons.ui.Package .. " Packages" })

-- ══════════════════════════════════════════════════════════════════════════
-- INFO / DOCS
-- ══════════════════════════════════════════════════════════════════════════

--- Show project / environment info.
keys.lang_map("LANG_KEY", "n", "<leader>li", function()
	local info = { lang_icon .. " LANG_NAME Info:", "" }

	if has_executable("RUNTIME_CMD") then
		local version = vim.fn.system("RUNTIME_CMD --version 2>/dev/null"):gsub("%s+$", "")
		info[#info + 1] = "  Version: " .. version
	end

	local tools = { "RUNTIME_CMD", "LSP_CMD", "FORMATTER_CMD", "LINTER_CMD" }
	info[#info + 1] = ""
	info[#info + 1] = "  Tools:"
	for _, tool in ipairs(tools) do
		local status = has_executable(tool) and "✓" or "✗"
		info[#info + 1] = "    " .. status .. " " .. tool
	end

	info[#info + 1] = "  CWD:     " .. vim.fn.getcwd()
	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "LANG_NAME" })
end, { desc = icons.diagnostics.Info .. " Project info" })

--- Open documentation in browser.
keys.lang_map("LANG_KEY", "n", "<leader>lh", function()
	local refs = {
		{ name = "LANG_NAME Docs", url = "https://LANG_DOCS_URL/" },
		{ name = "LANG_NAME Reference", url = "https://LANG_REF_URL/" },
		{ name = "LANG_NAME GitHub", url = "https://github.com/LANG_REPO" },
	}
	vim.ui.select(
		vim.tbl_map(function(r)
			return r.name
		end, refs),
		{ prompt = lang_icon .. " Documentation:" },
		function(_, idx)
			if idx then
				vim.ui.open(refs[idx].url)
			end
		end
	)
end, { desc = icons.ui.Note .. " Documentation" })

-- ═══════════════════════════════════════════════════════════════════════════
-- LAZY.NVIM SPECS
-- ═══════════════════════════════════════════════════════════════════════════

return {
	-- ── LSP SERVER ─────────────────────────────────────────────────────────
	{
		"neovim/nvim-lspconfig",
		opts = function(_, opts)
			if has_executable("LSP_CMD") then
				opts.servers = opts.servers or {}
				opts.servers.LSP_SERVER_NAME = {
					-- settings = {},
				}
			end
		end,
		init = function()
			-- ── Filetype detection ──────────────────────────────────────
			vim.filetype.add({
				extension = {
					EXTENSION = "LANG_KEY",
				},
			})

			-- ── Buffer options ──────────────────────────────────────────
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "LANG_KEY" },
				callback = function()
					local opt = vim.opt_local

					-- Display
					opt.wrap = false
					opt.colorcolumn = "80"
					opt.textwidth = 80

					-- Indentation
					opt.tabstop = 2
					opt.shiftwidth = 2
					opt.softtabstop = 2
					opt.expandtab = true

					-- Line numbers
					opt.number = true
					opt.relativenumber = true

					-- Fold (treesitter-based)
					opt.foldmethod = "expr"
					opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
					opt.foldlevel = 99

					-- Comment string (adjust for your language)
					-- opt.commentstring = "// %s"
					-- opt.commentstring = "# %s"
					-- opt.commentstring = "-- %s"
					-- opt.commentstring = "(* %s *)"
				end,
			})
		end,
	},

	-- ── MASON TOOLS ────────────────────────────────────────────────────────
	-- Only install if the runtime is available
	{
		"williamboman/mason.nvim",
		opts = function(_, opts)
			if has_executable("RUNTIME_CMD") then
				opts.ensure_installed = opts.ensure_installed or {}
				vim.list_extend(opts.ensure_installed, {
					-- "LSP_MASON_NAME",
					-- "FORMATTER_MASON_NAME",
					-- "LINTER_MASON_NAME",
				})
			end
		end,
	},

	-- ── FORMATTER ──────────────────────────────────────────────────────────
	{
		"stevearc/conform.nvim",
		optional = true,
		opts = function(_, opts)
			if has_executable("FORMATTER_CMD") then
				opts.formatters_by_ft = opts.formatters_by_ft or {}
				opts.formatters_by_ft.LANG_KEY = { "FORMATTER_NAME" }
			end
		end,
	},

	-- ── LINTER ─────────────────────────────────────────────────────────────
	{
		"mfussenegger/nvim-lint",
		optional = true,
		opts = function(_, opts)
			if has_executable("LINTER_CMD") then
				opts.linters_by_ft = opts.linters_by_ft or {}
				opts.linters_by_ft.LANG_KEY = { "LINTER_NAME" }
			end
		end,
	},

	-- ── TREESITTER ──────────────────────────────────────────────────────────
	{
		"nvim-treesitter/nvim-treesitter",
		opts = {
			ensure_installed = {
				"TREESITTER_GRAMMAR",
			},
		},
	},

	-- ── ADDITIONAL PLUGINS (optional) ──────────────────────────────────────
	-- Add language-specific plugins here, e.g.:
	-- {
	--     "author/plugin-name.nvim",
	--     ft = { "LANG_KEY" },
	--     cond = function() return has_executable("RUNTIME_CMD") end,
	--     opts = {},
	-- },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PLACEHOLDERS — Replace before use:
--
--   LANG_NAME           → Display name (e.g. "Python", "Rust", "OCaml")
--   LANG_KEY            → Filetype / settings key (e.g. "python", "rust")
--   LANG_ICON           → Icon key in icons.lang (e.g. "python", "rust")
--   RUNTIME_CMD         → Language runtime (e.g. "python3", "cargo", "node")
--   BUILD_CMD           → Build command (e.g. "cargo build", "make")
--   TEST_CMD            → Test command (e.g. "cargo test", "pytest")
--   REPL_CMD            → REPL command (e.g. "python3", "irb", "ghci")
--   LSP_CMD             → LSP binary name (e.g. "pyright", "rust-analyzer")
--   LSP_SERVER_NAME     → lspconfig server name (e.g. "pyright", "rust_analyzer")
--   LSP_MASON_NAME      → Mason package name (e.g. "pyright", "rust-analyzer")
--   FORMATTER_CMD       → Formatter binary (e.g. "black", "rustfmt")
--   FORMATTER_NAME      → conform.nvim name (e.g. "black", "rustfmt")
--   FORMATTER_MASON_NAME → Mason package (e.g. "black", "rustfmt")
--   LINTER_CMD          → Linter binary (e.g. "ruff", "clippy")
--   LINTER_NAME         → nvim-lint name (e.g. "ruff", "clippy")
--   LINTER_MASON_NAME   → Mason package (e.g. "ruff")
--   TREESITTER_GRAMMAR  → Treesitter grammar (e.g. "python", "rust")
--   EXTENSION           → File extension (e.g. "py", "rs", "ml")
--   LANG_DOCS_URL       → Documentation URL
--   LANG_REF_URL        → API reference URL
--   LANG_REPO           → GitHub repo path
--   PKG_INSTALL_CMD     → Package install (e.g. "pip install", "cargo add")
--   PKG_UPDATE_CMD      → Package update (e.g. "pip install -U", "cargo update")
--   PKG_LIST_CMD        → Package list (e.g. "pip list", "cargo tree")
-- ═══════════════════════════════════════════════════════════════════════════
