---@file lua/plugins/code/lsp/mason.lua
---@description Mason — tool installer for LSP servers, DAP adapters, linters and formatters with mason-lspconfig bridge
---@module "plugins.code.lsp.mason"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see core.settings Settings singleton (ui.float_border, lsp.auto_install)
---@see core.icons Centralized icon definitions (UI, misc.Mason)
---@see plugins.code.lsp LSP subsystem entry point
---@see plugins.code.lsp.lspconfig LSP server configurations
---@see langs Language modules (each adds tools via opts_extend)
---
---@see https://github.com/williamboman/mason.nvim
---@see https://github.com/williamboman/mason-lspconfig.nvim
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/code/lsp/mason.lua — Package manager for LSP/DAP/linters        ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  mason.nvim                                                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Tool collection via opts_extend:                                │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  mason.lua (this file)                                     │  │    ║
--- ║  │  │  └─ ensure_installed = {} (empty base)                     │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  Each langs/*.lua adds tools via lazy.nvim opts_extend:    │  │    ║
--- ║  │  │  ├─ langs/python.lua → ensure_installed += {               │  │    ║
--- ║  │  │  │    "basedpyright", "ruff", "debugpy"                    │  │    ║
--- ║  │  │  │  }                                                      │  │    ║
--- ║  │  │  ├─ langs/go.lua → ensure_installed += {                   │  │    ║
--- ║  │  │  │    "gopls", "gofumpt", "delve"                          │  │    ║
--- ║  │  │  │  }                                                      │  │    ║
--- ║  │  │  ├─ langs/lua.lua → ensure_installed += {                  │  │    ║
--- ║  │  │  │    "lua-language-server", "stylua"                      │  │    ║
--- ║  │  │  │  }                                                      │  │    ║
--- ║  │  │  └─ ... (55+ language files contribute tools)              │  │    ║
--- ║  │  │                                                            │  │    ║
--- ║  │  │  Result: ensure_installed = deduplicated union of all      │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  Deferred auto-install pipeline:                                 │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  1. config() receives merged ensure_installed from lazy    │  │    ║
--- ║  │  │  2. vim.defer_fn(fn, 100) — waits for UI to render first   │  │    ║
--- ║  │  │  3. Deduplicate tools via hash set (O(n))                  │  │    ║
--- ║  │  │  4. mason-registry.refresh() — cached, network if stale    │  │    ║
--- ║  │  │  5. Install missing packages in parallel (up to 4)         │  │    ║
--- ║  │  │  6. Warn on unknown packages (vim.notify)                  │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  │                                                                  │    ║
--- ║  │  mason-lspconfig.nvim (bridge)                                   │    ║
--- ║  │  ┌────────────────────────────────────────────────────────────┐  │    ║
--- ║  │  │  • automatic_installation = false                          │  │    ║
--- ║  │  │  • Each langs/*.lua manages its own prerequisites:         │  │    ║
--- ║  │  │    ├─ python.lua: checks for venv, basedpyright            │  │    ║
--- ║  │  │    ├─ dotnet.lua: checks for dotnet SDK                    │  │    ║
--- ║  │  │    ├─ ocaml.lua: checks for opam                           │  │    ║
--- ║  │  │    └─ r.lua: checks for R runtime                          │  │    ║
--- ║  │  │  • Enabling automatic_installation would bypass those      │  │    ║
--- ║  │  │    checks and silently fail on missing system deps         │  │    ║
--- ║  │  └────────────────────────────────────────────────────────────┘  │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Design decisions:                                                       ║
--- ║  ├─ ensure_installed starts empty — tools come from langs/*.lua          ║
--- ║  ├─ opts_extend merges arrays across all specs referencing mason.nvim    ║
--- ║  ├─ Deferred install (defer_fn 100ms) avoids blocking UI on startup      ║
--- ║  ├─ Hash-set deduplication handles overlapping tool lists from langs     ║
--- ║  ├─ mason-registry.refresh() is cached — only hits network if stale      ║
--- ║  ├─ max_concurrent_installers = 4 balances speed vs GitHub rate limits   ║
--- ║  ├─ automatic_installation = false on bridge — langs handle prereqs      ║
--- ║  ├─ log_level = WARN for production (use :MasonLog for debugging)        ║
--- ║  └─ Icons from core/icons.lua (single source of truth)                   ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • cmd + keys loading (zero startup cost until first use)                ║
--- ║  • opts_extend: langs/*.lua add tools without touching this file         ║
--- ║  • Deferred registry refresh (not at startup)                            ║
--- ║  • Deferred auto-install (vim.defer_fn, not during startup)              ║
--- ║  • O(n) deduplication of ensure_installed from 55+ lang files            ║
--- ║  • max_concurrent_installers = 4 (parallel, not sequential)              ║
--- ║  • mason-lspconfig loaded lazily (lazy = true)                           ║
--- ║                                                                          ║
--- ║  Global keymaps:                                                         ║
--- ║    <leader>cm   Open Mason UI                          (n)               ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
local icons = require("core.icons")

---@type lazy.PluginSpec[]
return {
	-- ═══════════════════════════════════════════════════════════════════
	-- MASON CORE
	-- ═══════════════════════════════════════════════════════════════════
	{
		"williamboman/mason.nvim",
		cmd = { "Mason", "MasonInstall", "MasonUpdate", "MasonUninstall", "MasonLog" },
		build = ":MasonUpdate",
		keys = {
			{ "<leader>cm", "<Cmd>Mason<CR>", desc = icons.misc.Mason .. " Mason" },
		},

		opts_extend = { "ensure_installed" },

		opts = {
			-- ── UI ───────────────────────────────────────────────────
			ui = {
				border = settings:get("ui.float_border", "rounded"),
				width = 0.8,
				height = 0.8,
				icons = {
					package_installed = icons.ui.Check,
					package_pending = icons.ui.Circle,
					package_uninstalled = icons.ui.BoldClose,
				},
				keymaps = {
					toggle_help = "?",
					toggle_package_expand = "<CR>",
					install_package = "i",
					update_package = "u",
					uninstall_package = "X",
					cancel_installation = "<C-c>",
					check_package_version = "c",
					check_outdated_packages = "C",
					update_all_packages = "U",
					apply_language_filter = "<C-f>",
				},
			},

			-- ── Tools to install ─────────────────────────────────────
			-- Empty base. Each langs/*.lua adds tools via opts_extend:
			--   opts = { ensure_installed = { "gopls", "gofumpt" } }
			---@type string[]
			ensure_installed = {},

			-- ── Concurrency ──────────────────────────────────────────
			-- 4 parallel installs. Higher values may hit GitHub rate
			-- limits. Lower values slow down initial setup.
			max_concurrent_installers = 4,

			-- ── Logging ──────────────────────────────────────────────
			-- WARN in production. Change to INFO for debugging:
			--   :MasonLog
			log_level = vim.log.levels.WARN,
		},

		---@param _ table Plugin spec (unused)
		---@param opts table Resolved options (with merged ensure_installed)
		config = function(_, opts)
			require("mason").setup(opts)

			-- ── Deferred auto-install ────────────────────────────────
			-- Runs AFTER startup is complete (vim.defer_fn) to avoid
			-- blocking the UI during editor initialization.
			--
			-- Flow:
			-- 1. Deduplicate ensure_installed from 55+ lang files
			-- 2. Refresh registry (cached — only hits network if stale)
			-- 3. Install any missing packages in parallel
			--
			-- Using defer_fn(fn, 100) instead of vim.schedule because:
			-- • vim.schedule runs on the NEXT event loop tick (too early)
			-- • defer_fn with 100ms ensures UI has fully rendered first
			-- • User sees the editor immediately, installs run in bg

			local tools = opts.ensure_installed or {}
			if #tools == 0 then return end

			vim.defer_fn(function()
				local mr_ok, mr = pcall(require, "mason-registry")
				if not mr_ok then return end

				-- Deduplicate (O(n) with hash set)
				---@type table<string, boolean>
				local seen = {}
				---@type string[]
				local unique = {}
				for _, tool in ipairs(tools) do
					if not seen[tool] then
						seen[tool] = true
						unique[#unique + 1] = tool
					end
				end

				-- Refresh registry then install missing
				mr.refresh(function()
					for _, tool in ipairs(unique) do
						local ok, pkg = pcall(mr.get_package, tool)
						if ok and pkg then
							if not pkg:is_installed() and not pkg:is_installing() then pkg:install() end
						else
							vim.schedule(function()
								vim.notify(
									string.format("Package '%s' not found in registry", tool),
									vim.log.levels.WARN,
									{ title = "Mason" }
								)
							end)
						end
					end
				end)
			end, 100)
		end,
	},

	-- ═══════════════════════════════════════════════════════════════════
	-- MASON-LSPCONFIG BRIDGE
	--
	-- automatic_installation = false because each langs/*.lua manages
	-- its own installation with prerequisite checks:
	--   • python.lua: checks for venv, basedpyright
	--   • dotnet.lua: checks for dotnet SDK
	--   • ocaml.lua: checks for opam
	--   • r.lua: checks for R runtime
	--
	-- Enabling automatic_installation here would bypass those checks
	-- and silently fail on missing system dependencies.
	-- ═══════════════════════════════════════════════════════════════════
	{
		"williamboman/mason-lspconfig.nvim",
		lazy = true,
		dependencies = { "williamboman/mason.nvim" },
		opts = {
			automatic_installation = false,
		},
	},
}
