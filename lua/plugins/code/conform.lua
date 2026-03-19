---@file lua/plugins/code/conform.lua
---@description Conform.nvim — formatter engine with per-language support
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/code/conform.lua — Format engine                                ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  conform.nvim                                                    │    ║
--- ║  │                                                                  │    ║
--- ║  │  • Central formatter engine (replaces null-ls formatting)        │    ║
--- ║  │  • Formatters declared by each langs/*.lua via opts_extend       │    ║
--- ║  │  • Only Lua (stylua) configured here — everything else           │    ║
--- ║  │    comes from the language packs                                 │    ║
--- ║  │  • format_on_save with LSP fallback                              │    ║
--- ║  │  • Large file guard (skips files > 1MB)                          │    ║
--- ║  │  • Formatter configs live in project root:                       │    ║
--- ║  │    .stylua.toml, .prettierrc, pyproject.toml, etc.               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Flow:                                                           │    ║
--- ║  │  ┌─────────┐   ┌───────────────┐   ┌─────────────────────┐       │    ║
--- ║  │  │ :w      │──▶│ format_on_save│──▶│ formatter found?    │       │    ║
--- ║  │  │ <C-cF>  │   │ or <leader>cF │   │ yes → run formatter │       │    ║
--- ║  │  └─────────┘   └───────────────┘   │ no  → LSP fallback  │       │    ║
--- ║  │                                    └─────────────────────┘       │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Formatter configs (NOT in this file — in project root):                 ║
--- ║  ┌────────────────────┬──────────────────────────────────────────┐       ║
--- ║  │  .stylua.toml      │  Lua (tabs, 120 cols, double quotes)     │       ║
--- ║  │  .prettierrc       │  JS/TS/CSS/HTML/JSON/YAML/MD             │       ║
--- ║  │  pyproject.toml    │  Python (ruff section)                   │       ║
--- ║  │  rustfmt.toml      │  Rust                                    │       ║
--- ║  │  .clang-format     │  C/C++                                   │       ║
--- ║  │  .editorconfig     │  Cross-formatter defaults                │       ║
--- ║  └────────────────────┴──────────────────────────────────────────┘       ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • BufWritePre + cmd + keys loading (zero startup cost)                  ║
--- ║  • opts_extend: langs/*.lua add formatters dynamically                   ║
--- ║  • Large file guard (>1MB → skip formatting, notify user)                ║
--- ║  • notify_on_error = true (visible feedback on failures)                 ║
--- ║  • format_on_save as function (dynamic, respects runtime toggles)        ║
--- ║  • No hardcoded formatter args — project configs take precedence         ║
--- ║                                                                          ║
--- ║  Keymaps:                                                                ║
--- ║    <leader>cF   Format buffer (async, LSP fallback)  (n, v)              ║
--- ║                                                                          ║
--- ║  Relationship with LazyVim <leader>cf:                                   ║
--- ║    cf = synchronous format (LazyVim default)                             ║
--- ║    cF = async format with explicit LSP fallback (this file)              ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
if not settings:is_plugin_enabled("conform") then return {} end

-- ═══════════════════════════════════════════════════════════════════════
-- PERFORMANCE THRESHOLDS
-- ═══════════════════════════════════════════════════════════════════════

local MAX_FORMAT_FILE_SIZE = 1024 * 1024 -- 1MB
local uv = vim.uv or vim.loop

-- ═══════════════════════════════════════════════════════════════════════
-- SETTINGS
-- ═══════════════════════════════════════════════════════════════════════

local format_timeout = settings:get("lsp.format_timeout", 3000)
local format_on_save_enabled = settings:get("lsp.format_on_save", true)

-- ═══════════════════════════════════════════════════════════════════════
-- LARGE FILE GUARD
-- ═══════════════════════════════════════════════════════════════════════

---@type table<number, boolean>
local notified_bufs = {}

---@param bufnr number
---@return boolean
local function is_large_file(bufnr)
	local fname = vim.api.nvim_buf_get_name(bufnr)
	if fname == "" then return false end
	local stat = uv.fs_stat(fname)
	if stat and stat.size > MAX_FORMAT_FILE_SIZE then
		if not notified_bufs[bufnr] then
			notified_bufs[bufnr] = true
			vim.schedule(function()
				vim.notify(
					string.format(
						"⚡ Formatting skipped: %s (%.0fKB, max %dKB)",
						fname:match("[^/\\]+$") or fname,
						stat.size / 1024,
						MAX_FORMAT_FILE_SIZE / 1024
					),
					vim.log.levels.INFO,
					{ title = "Conform" }
				)
			end)
		end
		return true
	end
	return false
end

vim.api.nvim_create_autocmd("BufDelete", {
	group = vim.api.nvim_create_augroup("NvimEnterprise_ConformCleanup", { clear = true }),
	callback = function(ev)
		notified_bufs[ev.buf] = nil
	end,
})

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════

return {
	"stevearc/conform.nvim",
	event = { "BufWritePre" },
	cmd = { "ConformInfo" },
	keys = {
		{
			"<leader>cF",
			function()
				local bufnr = vim.api.nvim_get_current_buf()
				if is_large_file(bufnr) then return end
				require("conform").format({
					async = true,
					lsp_format = "fallback",
					timeout_ms = format_timeout,
				})
			end,
			mode = { "n", "v" },
			desc = "Format buffer",
		},
	},

	-- ╔═══════════════════════════════════════════════════════════════╗
	-- ║  DO NOT use opts_extend for formatters_by_ft!                 ║
	-- ║                                                               ║
	-- ║  opts_extend treats the value as a LIST and concatenates.     ║
	-- ║  formatters_by_ft is a DICT — lazy.nvim deep-merges dicts     ║
	-- ║  automatically. opts_extend corrupts the merge.               ║
	-- ║                                                               ║
	-- ║  langs/*.lua specs with the same plugin name are deep-merged  ║
	-- ║  by lazy.nvim automatically:                                  ║
	-- ║                                                               ║
	-- ║  Base:    formatters_by_ft = { lua = {"stylua"} }             ║
	-- ║  Lang:    formatters_by_ft = { nu  = {"topiary_nu"} }         ║
	-- ║  Result:  formatters_by_ft = { lua = {"stylua"},              ║
	-- ║                                nu  = {"topiary_nu"} }         ║
	-- ╚═══════════════════════════════════════════════════════════════╝

	---@type conform.setupOpts
	opts = {
		formatters_by_ft = {
			lua = { "stylua" },
		},

		default_format_opts = {
			timeout_ms = format_timeout,
			async = false,
			quiet = false,
			lsp_format = "fallback",
		},

		---@param bufnr number
		---@return conform.FormatOpts|nil
		format_on_save = function(bufnr)
			if not format_on_save_enabled then return nil end
			if vim.b[bufnr].disable_autoformat then return nil end
			if is_large_file(bufnr) then return nil end
			return {
				timeout_ms = format_timeout,
				lsp_format = "fallback",
			}
		end,

		notify_on_error = true,

		formatters = {},
	},
}
