---@file lua/plugins/code/dap.lua
---@description DAP (Debug Adapter Protocol) — full debugging environment
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/code/dap.lua — Debug Adapter Protocol                           ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  nvim-dap (core engine)                                          │    ║
--- ║  │  ├─ nvim-dap-ui         → visual debug interface (panels)        │    ║
--- ║  │  ├─ nvim-dap-virtual-text → inline variable values               │    ║
--- ║  │  └─ mason-nvim-dap      → automatic adapter installation         │    ║
--- ║  │                                                                  │    ║
--- ║  │  Adapters are NOT configured here.                               │    ║
--- ║  │  Each langs/*.lua file configures its own DAP adapter:           │    ║
--- ║  │  ├─ langs/python.lua    → debugpy                                │    ║
--- ║  │  ├─ langs/javascript.lua → js-debug-adapter                      │    ║
--- ║  │  ├─ langs/go.lua        → delve                                  │    ║
--- ║  │  ├─ langs/rust.lua      → codelldb / lldb-vscode                 │    ║
--- ║  │  └─ langs/*.lua         → (adapter per language)                 │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • keys-only loading (zero startup cost)                                 ║
--- ║  • DAP UI opens/closes automatically on debug session events             ║
--- ║  • Virtual text disabled in insert mode (no noise while editing)         ║
--- ║  • mason-nvim-dap deferred (VeryLazy + vim.schedule)                     ║
--- ║  • Signs defined once with core/icons.lua glyphs                         ║
--- ║  • Borders from core/icons.lua (single source of truth)                  ║
--- ║  • F-key bindings for IDE-familiar users (F5/F9/F10/F11)                 ║
--- ║  • <leader>d* bindings for Vim-native users                              ║
--- ║  • Profiler keymaps (<leader>dp*) are NOT touched (separate plugin)      ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    <leader>db   Toggle breakpoint                      (n)               ║
--- ║    <leader>dB   Conditional breakpoint                 (n)               ║
--- ║    <leader>dE   Edit breakpoint (condition/hitcount)   (n)               ║
--- ║    <leader>dc   Continue                               (n)               ║
--- ║    <leader>dC   Run to cursor                          (n)               ║
--- ║    <leader>di   Step into                              (n)               ║
--- ║    <leader>do   Step over                              (n)               ║
--- ║    <leader>dO   Step out                               (n)               ║
--- ║    <leader>dl   Run last debug config                  (n)               ║
--- ║    <leader>dr   Toggle REPL                            (n)               ║
--- ║    <leader>ds   Start / continue session               (n)               ║
--- ║    <leader>dt   Terminate session                      (n)               ║
--- ║    <leader>du   Toggle DAP UI                          (n)               ║
--- ║    <leader>de   Eval expression                        (n, v)            ║
--- ║    <leader>dw   Widgets (hover)                        (n)               ║
--- ║    <F5>         Continue                               (n)               ║
--- ║    <F9>         Toggle breakpoint                      (n)               ║
--- ║    <F10>        Step over                              (n)               ║
--- ║    <F11>        Step into                              (n)               ║
--- ║    <S-F11>      Step out                               (n)               ║
--- ║                                                                          ║
--- ║  Reserved (NOT managed here):                                            ║
--- ║    <leader>dph  Toggle Profiler Highlights  (snacks)                     ║
--- ║    <leader>dpp  Toggle Profiler             (snacks)                     ║
--- ║    <leader>dps  Profiler scratch            (snacks)                     ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
if not settings:is_plugin_enabled("dap") then
	return {}
end

local icons = require("core.icons")

-- ═══════════════════════════════════════════════════════════════════════════
-- SHARED HELPER — conditional require with pcall
-- ═══════════════════════════════════════════════════════════════════════════

---@param mod string
---@return any|nil
local function safe_require(mod)
	local ok, m = pcall(require, mod)
	return ok and m or nil
end

return {
	-- ═══════════════════════════════════════════════════════════════════
	-- CORE DAP ENGINE
	-- ═══════════════════════════════════════════════════════════════════
	{
		"mfussenegger/nvim-dap",
		version = false,

		dependencies = {
			"rcarriga/nvim-dap-ui",
			"nvim-neotest/nvim-nio",
			"theHamsta/nvim-dap-virtual-text",
		},

		-- ═══════════════════════════════════════════════════════════════
		-- KEYS — sole loading mechanism
		--
		-- DAP has no background processes, no autocmds, no watchers.
		-- It only needs to load when the user explicitly starts
		-- debugging. Pure on-demand architecture = zero startup cost.
		-- ═══════════════════════════════════════════════════════════════
		keys = {
			-- ── Breakpoints ──────────────────────────────────────────
			{
				"<leader>db",
				function()
					require("dap").toggle_breakpoint()
				end,
				desc = icons.dap.Breakpoint .. " Toggle breakpoint",
			},
			{
				"<leader>dB",
				function()
					require("dap").set_breakpoint(vim.fn.input("Condition: "))
				end,
				desc = icons.dap.BreakpointCondition .. " Conditional breakpoint",
			},
			{
				"<leader>dE",
				function()
					require("dap").set_breakpoint(nil, vim.fn.input("Hit count: "), vim.fn.input("Log message: "))
				end,
				desc = icons.dap.LogPoint .. " Edit breakpoint",
			},

			-- ── Session control ──────────────────────────────────────
			{
				"<leader>ds",
				function()
					require("dap").continue()
				end,
				desc = icons.dap.Play .. " Start / continue",
			},
			{
				"<leader>dc",
				function()
					require("dap").continue()
				end,
				desc = icons.dap.Play .. " Continue",
			},
			{
				"<leader>dl",
				function()
					require("dap").run_last()
				end,
				desc = icons.dap.RunLast .. " Run last",
			},
			{
				"<leader>dt",
				function()
					require("dap").terminate()
				end,
				desc = icons.dap.Terminate .. " Terminate",
			},
			{
				"<leader>dC",
				function()
					require("dap").run_to_cursor()
				end,
				desc = icons.ui.Target .. " Run to cursor",
			},

			-- ── Stepping ─────────────────────────────────────────────
			{
				"<leader>di",
				function()
					require("dap").step_into()
				end,
				desc = icons.dap.StepInto .. " Step into",
			},
			{
				"<leader>do",
				function()
					require("dap").step_over()
				end,
				desc = icons.dap.StepOver .. " Step over",
			},
			{
				"<leader>dO",
				function()
					require("dap").step_out()
				end,
				desc = icons.dap.StepOut .. " Step out",
			},

			-- ── Inspection ───────────────────────────────────────────
			{
				"<leader>dr",
				function()
					require("dap").repl.toggle()
				end,
				desc = icons.ui.Terminal .. " Toggle REPL",
			},
			{
				"<leader>dw",
				function()
					require("dap.ui.widgets").hover()
				end,
				desc = icons.ui.Search .. " Widgets (hover)",
			},
			{
				"<leader>de",
				function()
					require("dapui").eval()
				end,
				mode = { "n", "v" },
				desc = icons.ui.Code .. " Eval expression",
			},

			-- ── UI toggle ────────────────────────────────────────────
			{
				"<leader>du",
				function()
					require("dapui").toggle()
				end,
				desc = icons.ui.Window .. " Toggle DAP UI",
			},

			-- ── F-keys (IDE-familiar) ────────────────────────────────
			-- These mirror VS Code / IntelliJ defaults for users
			-- transitioning from traditional IDEs.
			{
				"<F5>",
				function()
					require("dap").continue()
				end,
				desc = icons.dap.Play .. " Continue (F5)",
			},
			{
				"<F9>",
				function()
					require("dap").toggle_breakpoint()
				end,
				desc = icons.dap.Breakpoint .. " Toggle breakpoint (F9)",
			},
			{
				"<F10>",
				function()
					require("dap").step_over()
				end,
				desc = icons.dap.StepOver .. " Step over (F10)",
			},
			{
				"<F11>",
				function()
					require("dap").step_into()
				end,
				desc = icons.dap.StepInto .. " Step into (F11)",
			},
			{
				"<S-F11>",
				function()
					require("dap").step_out()
				end,
				desc = icons.dap.StepOut .. " Step out (S-F11)",
			},
		},

		config = function()
			local dap = require("dap")

			-- ── Sign definitions ─────────────────────────────────────
			-- Uses core/icons.lua DAP glyphs. Defined once at setup,
			-- not on every breakpoint toggle.
			vim.fn.sign_define("DapBreakpoint", {
				text = icons.dap.Breakpoint,
				texthl = "DiagnosticError",
				linehl = "",
				numhl = "",
			})
			vim.fn.sign_define("DapBreakpointCondition", {
				text = icons.dap.BreakpointCondition,
				texthl = "DiagnosticWarn",
				linehl = "",
				numhl = "",
			})
			vim.fn.sign_define("DapBreakpointRejected", {
				text = icons.dap.BreakpointRejected,
				texthl = "DiagnosticError",
				linehl = "",
				numhl = "",
			})
			vim.fn.sign_define("DapLogPoint", {
				text = icons.dap.LogPoint,
				texthl = "DiagnosticInfo",
				linehl = "",
				numhl = "",
			})
			vim.fn.sign_define("DapStopped", {
				text = icons.dap.Stopped,
				texthl = "DiagnosticOk",
				linehl = "DapStoppedLine",
				numhl = "DapStoppedLine",
			})

			-- ── Stopped line highlight ───────────────────────────────
			-- Subtle background highlight on the current execution line.
			-- Link-based → survives :colorscheme switches.
			vim.api.nvim_set_hl(0, "DapStoppedLine", { link = "Visual" })
		end,
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- DAP UI — visual debug interface
	--
	-- Provides:
	-- • Scopes panel (local/global variables)
	-- • Stacks panel (call stack frames)
	-- • Breakpoints panel (list all breakpoints)
	-- • Watches panel (user-defined watch expressions)
	-- • Console (DAP output / REPL)
	--
	-- Auto-opens when a debug session starts (dap event_initialized)
	-- Auto-closes when a debug session ends (dap event_terminated)
	-- ═══════════════════════════════════════════════════════════════════
	{
		"rcarriga/nvim-dap-ui",
		lazy = true,
		dependencies = { "nvim-neotest/nvim-nio" },

		opts = function()
			local borders = icons.borders

			return {
				-- ── Panel icons ──────────────────────────────────────
				icons = {
					expanded = icons.arrows.ArrowOpen,
					collapsed = icons.arrows.ArrowClosed,
					current_frame = icons.dap.Stopped,
				},

				-- ── Controls (top bar) ───────────────────────────────
				controls = {
					enabled = true,
					element = "repl",
					icons = {
						pause = icons.dap.Pause,
						play = icons.dap.Play,
						step_into = icons.dap.StepInto,
						step_over = icons.dap.StepOver,
						step_out = icons.dap.StepOut,
						step_back = icons.dap.StepBack,
						run_last = icons.dap.RunLast,
						terminate = icons.dap.Terminate,
						disconnect = icons.dap.Disconnect,
					},
				},

				-- ── Floating window defaults ─────────────────────────
				floating = {
					border = borders.Rounded,
					max_height = 0.8,
					max_width = 0.8,
					mappings = {
						close = { "q", "<Esc>" },
					},
				},

				-- ── Element sizing ───────────────────────────────────
				-- Render settings for inline variable values
				render = {
					indent = 1,
					max_type_length = 40,
					max_value_lines = 100,
				},

				-- ── Layout ───────────────────────────────────────────
				-- Left: debug info (scopes, stacks, breakpoints, watches)
				-- Bottom: console / REPL output
				layouts = {
					{
						elements = {
							{ id = "scopes", size = 0.35 },
							{ id = "stacks", size = 0.25 },
							{ id = "breakpoints", size = 0.15 },
							{ id = "watches", size = 0.25 },
						},
						position = "left",
						size = 50,
					},
					{
						elements = {
							{ id = "repl", size = 0.5 },
							{ id = "console", size = 0.5 },
						},
						position = "bottom",
						size = 12,
					},
				},
			}
		end,

		config = function(_, opts)
			local dap = require("dap")
			local dapui = require("dapui")

			dapui.setup(opts)

			-- ── Auto open/close UI on debug events ───────────────────
			-- event_initialized: debug session started → open UI
			-- event_terminated:  debug session ended   → close UI
			-- event_exited:      debuggee process ended → close UI
			--
			-- reset = true: forces layout reset on open (prevents
			-- stale panel states from previous sessions)
			dap.listeners.after.event_initialized["dapui_config"] = function()
				dapui.open({ reset = true })
			end
			dap.listeners.before.event_terminated["dapui_config"] = function()
				dapui.close()
			end
			dap.listeners.before.event_exited["dapui_config"] = function()
				dapui.close()
			end
		end,
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- DAP VIRTUAL TEXT — inline variable values
	--
	-- Shows variable values as virtual text next to the source code
	-- while debugging. E.g.:
	--   local x = 42  -- x = 42
	--
	-- Disabled in insert mode to avoid visual noise while editing
	-- breakpoint conditions or code during a debug session.
	-- ═══════════════════════════════════════════════════════════════════
	{
		"theHamsta/nvim-dap-virtual-text",
		lazy = true,
		opts = {
			enabled = true,
			enabled_commands = true,
			all_frames = false,
			all_references = false,
			display_callback = function(variable, buf, stackframe, node, options)
				if #variable.value > 80 then
					return " "
						.. icons.ui.Ellipsis
						.. " "
						.. variable.name
						.. " = "
						.. variable.value:sub(1, 77)
						.. "…"
				end
				return " " .. icons.arrows.SmallArrowRight .. " " .. variable.name .. " = " .. variable.value
			end,
			highlight_changed_variables = true,
			highlight_new_as_changed = false,
			show_stop_reason = true,
			commented = false,
			only_first_definition = true,
			virt_text_pos = "eol",
			virt_text_win_col = nil,
		},
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- MASON-NVIM-DAP — automatic adapter installation
	--
	-- Bridges mason.nvim and nvim-dap. Automatically installs and
	-- configures debug adapters declared in langs/*.lua files.
	--
	-- Deferred via VeryLazy + vim.schedule to avoid adding to startup.
	-- ═══════════════════════════════════════════════════════════════════
	{
		"jay-babu/mason-nvim-dap.nvim",
		dependencies = { "williamboman/mason.nvim" },
		cmd = { "DapInstall", "DapUninstall" },
		opts_extend = { "ensure_installed" },
		opts = {
			automatic_installation = settings:get("lsp.auto_install", true),
			ensure_installed = {},
			handlers = {},
		},
	},
}
