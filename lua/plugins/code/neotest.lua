---@file lua/plugins/code/neotest.lua
---@description Neotest — test runner framework with per-language adapters
---@module "plugins.code.neotest"
---@version 1.0.0
---@since 2026-03
---@see https://github.com/nvim-neotest/neotest
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/code/neotest.lua — Test runner                                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  neotest                                                         │    ║
--- ║  │  ├─ Adapters (conditional on binary availability)                │    ║
--- ║  │  │  ├─ neotest-python     (pytest, unittest)                     │    ║
--- ║  │  │  ├─ neotest-vitest     (Vitest for JS/TS)                     │    ║
--- ║  │  │  ├─ neotest-jest       (Jest for JS/TS)                       │    ║
--- ║  │  │  ├─ neotest-go         (go test)                              │    ║
--- ║  │  │  ├─ neotest-rust       (cargo test via cargo-nextest)         │    ║
--- ║  │  │  └─ neotest-lua        (busted/plenary)                       │    ║
--- ║  │  │                                                               │    ║
--- ║  │  ├─ DAP integration       (debug nearest test)                   │    ║
--- ║  │  └─ Summary panel         (tree view of test results)            │    ║
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
--- ║  │  ├─ Adapters loaded only if runtime binary exists (has())        │    ║
--- ║  │  ├─ DAP strategy for debug: reuses existing nvim-dap config      │    ║
--- ║  │  ├─ Summary panel opens on the right (consistent with neo-tree)  │    ║
--- ║  │  ├─ Output in floating window (not split) for focus              │    ║
--- ║  │  └─ Watch mode auto-runs tests on file save                      │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
if not settings:is_plugin_enabled("neotest") then return {} end

local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════
-- ADAPTER BUILDER
--
-- Each adapter is conditionally loaded based on runtime availability.
-- This prevents errors when a language toolchain is not installed.
-- ═══════════════════════════════════════════════════════════════════════

---@alias AdapterSpec { plugin: string, binary: string, setup: fun(): table }

--- Adapter definitions — only loaded if the binary is found in PATH.
---@type AdapterSpec[]
---@private
local ADAPTER_SPECS = {
	{
		plugin = "nvim-neotest/neotest-python",
		binary = "python3",
		setup = function()
			return require("neotest-python")({
				dap = { justMyCode = false },
				runner = "pytest",
				args = { "--tb=short", "-q" },
			})
		end,
	},
	{
		plugin = "marilari88/neotest-vitest",
		binary = "npx",
		setup = function()
			return require("neotest-vitest")
		end,
	},
	{
		plugin = "nvim-neotest/neotest-jest",
		binary = "npx",
		setup = function()
			return require("neotest-jest")({
				jestCommand = "npx jest",
				cwd = function()
					return vim.fn.getcwd()
				end,
			})
		end,
	},
	{
		plugin = "nvim-neotest/neotest-go",
		binary = "go",
		setup = function()
			return require("neotest-go")({
				recursive_run = true,
				args = { "-count=1", "-race" },
			})
		end,
	},
	{
		plugin = "rouge8/neotest-rust",
		binary = "cargo",
		setup = function()
			return require("neotest-rust")({
				args = { "--no-capture" },
			})
		end,
	},
}

--- Build the list of available adapters based on installed binaries.
---
---@return table[] adapters Configured adapter instances
---@return string[] plugins Plugin specs for lazy.nvim dependencies
---@private
local function build_adapters()
	local adapters = {}
	local plugins = {}

	for _, spec in ipairs(ADAPTER_SPECS) do
		if vim.fn.executable(spec.binary) == 1 then
			table.insert(plugins, { spec.plugin, lazy = true })
			-- Adapter setup is deferred to config time
		end
	end

	return adapters, plugins
end

local _, adapter_plugins = build_adapters()

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════

local float_border = settings:get("ui.float_border", "rounded")

return {
	"nvim-neotest/neotest",
	event = "VeryLazy",
	dependencies = vim.list_extend({
		"nvim-neotest/nvim-nio",
		"nvim-lua/plenary.nvim",
		"nvim-treesitter/nvim-treesitter",
		"antoinemadec/FixCursorHold.nvim",
	}, adapter_plugins),

	-- ── Keymaps ──────────────────────────────────────────────────────
	keys = {
		-- Group registration for which-key
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

		-- Navigation (jump between failed tests)
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

	---@param _ table Plugin spec (unused)
	---@param opts neotest.Config Resolved options
	config = function(_, opts)
		-- ── Build adapters at config time (deferred require) ─────────
		local adapters = {}
		for _, spec in ipairs(ADAPTER_SPECS) do
			if vim.fn.executable(spec.binary) == 1 then table.insert(adapters, spec.setup()) end
		end
		opts.adapters = adapters

		require("neotest").setup(opts)
	end,
}
