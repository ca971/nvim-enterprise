---@file lua/plugins/code/lsp/handlers.lua
---@description Handlers — LSP diagnostic UI, floating window borders, signs and progress tracking
---@module "plugins.code.lsp.handlers"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings singleton (ui.float_border, lsp.diagnostic_*)
---@see core.icons Centralized icon definitions (diagnostics, misc.Lsp)
---@see plugins.code.lsp LSP subsystem entry point
---@see plugins.code.lsp.lspconfig LSP server configurations (on_attach, capabilities)
---@see plugins.ui.lualine Statusline (consumes _G.NvimConfig.lsp_progress)
---@see plugins.ui.tiny-inline-diagnostic Complementary inline diagnostic display
---
---@see https://github.com/neovim/nvim-lspconfig
---@see https://neovim.io/doc/user/diagnostic.html vim.diagnostic API reference
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/code/lsp/handlers.lua — Diagnostic UI & float borders           ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  This is a lazy.PluginSpec for nvim-lspconfig that configures    │    ║
--- ║  │  diagnostic display and LSP float behavior via init().           │    ║
--- ║  │  init() runs BEFORE the plugin loads, setting up:                │    ║
--- ║  │                                                                  │    ║
--- ║  │  1. Diagnostic signs                                             │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  Maps vim.diagnostic.severity → icons from core.icons      │  │    ║
--- ║  │  │  ERROR → , WARN → , HINT → , INFO →                        │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  2. Diagnostic config (vim.diagnostic.config)                    │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • virtual_text: spacing=4, source="if_many", icon prefix  │  │    ║
--- ║  │  │    Driven by lsp.diagnostic_virtual_text setting           │  │    ║
--- ║  │  │  • signs: text = severity → icon mapping                   │  │    ║
--- ║  │  │    Driven by lsp.diagnostic_signs setting                  │  │    ║
--- ║  │  │  • underline: driven by lsp.diagnostic_underline           │  │    ║
--- ║  │  │  • severity_sort: driven by lsp.diagnostic_severity_sort   │  │    ║
--- ║  │  │  • float: bordered, focusable, with icon+highlight prefix  │  │    ║
--- ║  │  │  • update_in_insert: always false (avoid flicker)          │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  3. LSP float borders                                            │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • vim.lsp.handlers["textDocument/hover"] with border      │  │    ║
--- ║  │  │  • vim.lsp.handlers["textDocument/signatureHelp"]          │  │    ║
--- ║  │  │  • Global override: vim.lsp.util.open_floating_preview     │  │    ║
--- ║  │  │    Injects border, max_width=80, max_height=30 defaults    │  │    ║
--- ║  │  │  • Border style from ui.float_border setting               │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  Note: vim.lsp.handlers still supported in 0.11.           │  │    ║
--- ║  │  │  Will migrate to per-call opts when handlers are removed.  │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  4. LSP progress tracker                                         │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • Listens to LspProgress autocmd                          │  │    ║
--- ║  │  │  • Tracks per-client progress in local table               │  │    ║
--- ║  │  │  • Exposes _G.NvimConfig.lsp_progress() for statusline     │  │    ║
--- ║  │  │  • Returns formatted string: "󰒓 title: message (42%)"      │  │    ║
--- ║  │  │  • Multiple clients separated by " | "                     │  │    ║
--- ║  │  │  • Clears entry on kind="end"                              │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  5. CursorHold diagnostic float                                  │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • Opens diagnostic float on CursorHold                    │  │    ║
--- ║  │  │  • Only when no other float is already visible             │  │    ║
--- ║  │  │  • Non-focusable, cursor-scoped, auto-closes on            │  │    ║
--- ║  │  │    BufLeave/CursorMoved/InsertEnter/FocusLost              │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Design decisions:                                                       ║
--- ║  ├─ Uses init() not config() — diagnostic UI must be set up before       ║
--- ║  │  any LSP server attaches to a buffer                                  ║
--- ║  ├─ All diagnostic settings driven by core.settings for per-user control ║
--- ║  ├─ virtual_text disabled entirely when setting is false (not just empty)║
--- ║  ├─ Float prefix uses a function for per-diagnostic icon+highlight       ║
--- ║  ├─ open_floating_preview monkey-patch ensures ALL LSP floats get        ║
--- ║  │  borders, not just hover and signatureHelp                            ║
--- ║  ├─ Progress tracker uses a local table (not global state) for data      ║
--- ║  │  but exposes a global function for statusline consumption             ║
--- ║  ├─ CursorHold float checks for existing floats to avoid stacking        ║
--- ║  └─ update_in_insert = false prevents diagnostic flicker during typing   ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • Diagnostic config set once in init() (not per-buffer)                 ║
--- ║  • CursorHold callback exits early if any float is already visible       ║
--- ║  • Progress data cleaned up on kind="end" (no memory leak)               ║
--- ║  • lsp_progress() builds string only when called (lazy evaluation)       ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
local icons = require("core.icons")

---@type lazy.PluginSpec
return {
	"neovim/nvim-lspconfig",

	--- Configure diagnostic UI, float borders, progress tracking and
	--- CursorHold float. Runs in init() (before plugin load) so
	--- diagnostic display is ready before any LSP server attaches.
	init = function()
		local border = settings:get("ui.float_border", "rounded")

		-- ── Diagnostic Signs ──────────────────────────────────────────
		---@type table<integer, string>
		local diagnostic_signs = {
			[vim.diagnostic.severity.ERROR] = icons.diagnostics.Error,
			[vim.diagnostic.severity.WARN] = icons.diagnostics.Warn,
			[vim.diagnostic.severity.HINT] = icons.diagnostics.Hint,
			[vim.diagnostic.severity.INFO] = icons.diagnostics.Info,
		}

		-- ── Diagnostic Config ─────────────────────────────────────────
		vim.diagnostic.config({
			virtual_text = settings:get("lsp.diagnostic_virtual_text", true) and {
				spacing = 4,
				source = "if_many",
				prefix = function(diagnostic)
					return diagnostic_signs[diagnostic.severity] or icons.diagnostics.Info
				end,
			} or false,

			signs = settings:get("lsp.diagnostic_signs", true) and {
				text = diagnostic_signs,
			} or false,

			underline = settings:get("lsp.diagnostic_underline", true),
			update_in_insert = false,
			severity_sort = settings:get("lsp.diagnostic_severity_sort", true),

			float = {
				focusable = true,
				style = "minimal",
				border = border,
				source = "if_many",
				header = "",
				prefix = function(diagnostic)
					local diag_icon = (diagnostic_signs[diagnostic.severity] or icons.diagnostics.Info) .. " "
					local hl = ({
						[vim.diagnostic.severity.ERROR] = "DiagnosticError",
						[vim.diagnostic.severity.WARN] = "DiagnosticWarn",
						[vim.diagnostic.severity.HINT] = "DiagnosticHint",
						[vim.diagnostic.severity.INFO] = "DiagnosticInfo",
					})[diagnostic.severity] or "DiagnosticInfo"
					return diag_icon, hl
				end,
			},
		})

		-- ── LSP Float Borders ─────────────────────────────────────────
		-- Still supported in Neovim 0.11. Will migrate to per-call opts
		-- when vim.lsp.handlers is fully removed in a future release.
		vim.lsp.handlers["textDocument/hover"] =
			vim.lsp.with(vim.lsp.handlers.hover, { border = border, max_width = 80, max_height = 30 })
		vim.lsp.handlers["textDocument/signatureHelp"] =
			vim.lsp.with(vim.lsp.handlers.signature_help, { border = border, max_width = 80, max_height = 15 })

		-- ── Global float override ─────────────────────────────────────
		-- Monkey-patches open_floating_preview to inject border and
		-- max dimensions into ALL LSP floats, not just hover/signature.
		local orig_open_float = vim.lsp.util.open_floating_preview
		---@diagnostic disable-next-line: duplicate-set-field
		vim.lsp.util.open_floating_preview = function(contents, syntax, float_opts, ...)
			float_opts = float_opts or {}
			float_opts.border = float_opts.border or border
			float_opts.max_width = float_opts.max_width or 80
			float_opts.max_height = float_opts.max_height or 30
			return orig_open_float(contents, syntax, float_opts, ...)
		end

		-- ── LSP Progress (for statusline) ─────────────────────────────
		-- Tracks per-client progress data and exposes a global function
		-- that lualine and other statusline plugins can call to display
		-- LSP activity (e.g., "indexing: src/ (42%)").
		---@type table<integer, { client: string, title: string, message: string, percentage: number }>
		local progress_data = {}

		vim.api.nvim_create_autocmd("LspProgress", {
			group = vim.api.nvim_create_augroup("NvimEnterprise_LspProgress", { clear = true }),
			desc = "Track LSP progress for statusline",
			callback = function(ev)
				local client_id = ev.data and ev.data.client_id
				local value = ev.data and ev.data.params and ev.data.params.value
				if not client_id or not value then return end
				local client = vim.lsp.get_client_by_id(client_id)
				if not client then return end
				if value.kind == "end" then
					progress_data[client_id] = nil
				else
					progress_data[client_id] = {
						client = client.name,
						title = value.title or "",
						message = value.message or "",
						percentage = value.percentage or 0,
					}
				end
			end,
		})

		-- Expose progress function globally for statusline consumption
		_G.NvimConfig = _G.NvimConfig or {}

		--- Get formatted LSP progress string for statusline display.
		--- Returns an empty string when no LSP operations are in progress.
		--- Multiple concurrent operations are separated by " | ".
		---
		--- ```lua
		--- _G.NvimConfig.lsp_progress()
		--- --> "󰒓 Indexing: src/ (42%)"
		--- --> "󰒓 Loading: workspace | 󰒓 Checking: types (89%)"
		--- --> ""  (no active operations)
		--- ```
		---
		---@return string progress Formatted progress string
		_G.NvimConfig.lsp_progress = function()
			local result = {}
			for _, data in pairs(progress_data) do
				local msg = data.title
				if data.message ~= "" then msg = msg .. ": " .. data.message end
				if data.percentage > 0 then msg = msg .. string.format(" (%d%%%%)", data.percentage) end
				result[#result + 1] = icons.misc.Lsp .. " " .. msg
			end
			return table.concat(result, " | ")
		end

		-- ── Diagnostic float on CursorHold ────────────────────────────
		-- Automatically shows diagnostic float when cursor rests on a
		-- line with diagnostics. Skips if any floating window is already
		-- visible to avoid stacking floats.
		vim.api.nvim_create_autocmd("CursorHold", {
			group = vim.api.nvim_create_augroup("NvimEnterprise_DiagFloatOnHold", { clear = true }),
			desc = "Show diagnostics on CursorHold when no float is open",
			callback = function()
				-- Skip if any floating window is already visible
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_get_config(win).relative ~= "" then return end
				end
				vim.diagnostic.open_float(nil, {
					focusable = false,
					close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
					border = border,
					source = "if_many",
					prefix = " ",
					scope = "cursor",
				})
			end,
		})
	end,
}
