---@file lua/plugins/code/neotest.lua
---@description Neotest — test runner framework (core configuration only)
---@module "plugins.code.neotest"
---@version 2.0.0
---@since 2026-03
---@see https://github.com/nvim-neotest/neotest
---@see langs.python     Python adapter registration (neotest-python)
---@see langs.javascript JavaScript adapter registration (neotest-vitest/jest)
---@see langs.typescript TypeScript adapter registration (neotest-vitest/jest)
---@see langs.go         Go adapter registration (neotest-go)
---@see langs.rust       Rust adapter registration (neotest-rust)
---@see langs.lua        Lua adapter registration (neotest-plenary)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/code/neotest.lua — Test runner (core)                           ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  neotest (this file — core only)                                 │    ║
--- ║  │  ├─ UI configuration       (summary, output, floating, icons)    │    ║
--- ║  │  ├─ Keymaps                (<Space>n namespace)                  │    ║
--- ║  │  ├─ Status                 (virtual text, signs, diagnostics)    │    ║
--- ║  │  └─ Adapters = {}          (empty — populated by langs/*.lua)    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Adapter registration (in each lua/langs/*.lua file):            │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  {                                                       │    │    ║
--- ║  │  │    "nvim-neotest/neotest",                               │    │    ║
--- ║  │  │    optional = true,                                      │    │    ║
--- ║  │  │    dependencies = { "adapter-plugin" },                  │    │    ║
--- ║  │  │    opts = function(_, opts)                              │    │    ║
--- ║  │  │      opts.adapters = opts.adapters or {}                 │    │    ║
--- ║  │  │      table.insert(opts.adapters, require("adapter")({})) │    │    ║
--- ║  │  │    end,                                                  │    │    ║
--- ║  │  │  }                                                       │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps (<Space>n namespace):                                   │    ║
--- ║  │  ┌────────────┬──────────────────────────────────────────┐       │    ║
--- ║  │  │ Key        │ Action                                   │       │    ║
--- ║  │  ├────────────┼──────────────────────────────────────────┤       │    ║
--- ║  │  │ <Space>nr  │ Run nearest test                         │       │    ║
--- ║  │  │ <Space>nR  │ Run current file                         │       │    ║
--- ║  │  │ <Space>ns  │ Run test suite                           │       │    ║
--- ║  │  │ <Space>nl  │ Run last test                            │       │    ║
--- ║  │  │ <Space>nd  │ Debug nearest test (DAP)                 │       │    ║
--- ║  │  │ <Space>no  │ Toggle output                            │       │    ║
--- ║  │  │ <Space>nO  │ Toggle output panel                      │       │    ║
--- ║  │  │ <Space>np  │ Toggle summary panel                     │       │    ║
--- ║  │  │ <Space>nS  │ Stop running tests                       │       │    ║
--- ║  │  │ <Space>nw  │ Toggle watch mode                        │       │    ║
--- ║  │  │ [n / ]n    │ Prev / Next failed test                  │       │    ║
--- ║  │  └────────────┴──────────────────────────────────────────┘       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ Zero adapters in core (all from langs/ — hot-loaded)         │    ║
--- ║  │  ├─ Adapters only loaded when their filetype is opened           │    ║
--- ║  │  ├─ DAP strategy for debug: reuses existing nvim-dap config      │    ║
--- ║  │  ├─ Summary panel opens on the right (consistent with neo-tree)  │    ║
--- ║  │  ├─ Output in floating window (not split) for focus              │    ║
--- ║  │  └─ Watch mode auto-runs tests on file save                      │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════════

local settings = require("core.settings")
if not settings:is_plugin_enabled("neotest") then return {} end

local icons = require("core.icons")
local float_border = settings:get("ui.float_border", "rounded")

-- ═══════════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════════

return {
	"nvim-neotest/neotest",
	-- event = "VeryLazy",
	cmd = { "Neotest" },
	dependencies = {
		"nvim-neotest/nvim-nio",
		"nvim-lua/plenary.nvim",
		"nvim-treesitter/nvim-treesitter",
		"antoinemadec/FixCursorHold.nvim",
	},

	-- ── Keymaps ──────────────────────────────────────────────────────
	keys = {
		{ "<leader>n", group = "neotest", icon = "󰙨" },

		-- Run
		{
			"<leader>nr",
			function()
				require("neotest").run.run()
			end,
			desc = "󰙨 Run nearest test",
		},
		{
			"<leader>nR",
			function()
				require("neotest").run.run(vim.fn.expand("%"))
			end,
			desc = "󰙨 Run current file",
		},
		{
			"<leader>ns",
			function()
				require("neotest").run.run({ suite = true })
			end,
			desc = "󰙨 Run test suite",
		},
		{
			"<leader>nl",
			function()
				require("neotest").run.run_last()
			end,
			desc = "󰑐 Run last test",
		},

		-- Debug
		{
			"<leader>nd",
			function()
				require("neotest").run.run({ strategy = "dap" })
			end,
			desc = "󰃤 Debug nearest test",
		},

		-- Output
		{
			"<leader>no",
			function()
				require("neotest").output.open({ enter = true, auto_close = true })
			end,
			desc = " Toggle output",
		},
		{
			"<leader>nO",
			function()
				require("neotest").output_panel.toggle()
			end,
			desc = " Toggle output panel",
		},

		-- Summary
		{
			"<leader>np",
			function()
				require("neotest").summary.toggle()
			end,
			desc = "󰙅 Toggle summary panel",
		},

		-- Control
		{
			"<leader>nS",
			function()
				require("neotest").run.stop()
			end,
			desc = "󰓛 Stop running tests",
		},
		{
			"<leader>nw",
			function()
				require("neotest").watch.toggle(vim.fn.expand("%"))
			end,
			desc = "󰈞 Toggle watch mode",
		},

		-- Navigation
		{
			"[n",
			function()
				require("neotest").jump.prev({ status = "failed" })
			end,
			desc = "Prev failed test",
		},
		{
			"]n",
			function()
				require("neotest").jump.next({ status = "failed" })
			end,
			desc = "Next failed test",
		},
	},

	---@type neotest.Config
	opts = {
		adapters = {},

		status = {
			enabled = true,
			virtual_text = true,
			signs = true,
		},

		output = {
			enabled = true,
			open_on_run = "short",
		},

		output_panel = {
			enabled = true,
			open = "botright split | resize 15",
		},

		summary = {
			enabled = true,
			animated = true,
			follow = true,
			expand_errors = true,
			open = "botright vsplit | vertical resize 50",
			mappings = {
				expand = { "<CR>", "<2-LeftMouse>" },
				expand_all = "e",
				output = "o",
				short = "O",
				attach = "a",
				jumpto = "i",
				stop = "u",
				run = "r",
				debug = "d",
				mark = "m",
				run_marked = "R",
				debug_marked = "D",
				clear_marked = "M",
				target = "t",
				clear_target = "T",
				next_failed = "J",
				prev_failed = "K",
				watch = "w",
			},
		},

		floating = {
			border = float_border,
			max_height = 0.6,
			max_width = 0.6,
			options = {},
		},

		icons = {
			passed = icons.test and icons.test.Passed or "✓",
			failed = icons.test and icons.test.Failed or "✗",
			running = icons.test and icons.test.Running or "⟳",
			skipped = icons.test and icons.test.Skipped or "○",
			unknown = icons.test and icons.test.Unknown or "?",
			running_animated = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
		},

		quickfix = {
			enabled = true,
			open = false,
		},

		discovery = {
			enabled = true,
			concurrent = 1,
		},

		diagnostic = {
			enabled = true,
			severity = vim.diagnostic.severity.ERROR,
		},
	},
}
