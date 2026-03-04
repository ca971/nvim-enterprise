---@file lua/plugins/code/lsp/lspconfig.lua
---@description LSPConfig — LSP server configuration using Neovim 0.11+ native API
---@module "plugins.code.lsp.lspconfig"
---@author ca971
---@license MIT
---@version 1.0.0
---@since 2026-01
---
---@see plugins.code.lsp.mason Mason package manager (installs server binaries)
---@see plugins.code.lsp.mason-lspconfig Bridge between Mason and lspconfig
---@see plugins.code.completion.blink Completion engine (provides LSP capabilities)
---@see plugins.code.formatting.conform Formatting engine (LSP fallback)
---@see core.settings Settings provider (lsp.inlay_hints, lsp.auto_install)
---@see core.icons Icon provider (keymaps descriptions)
---@see core.utils Utility helpers (augroup factory)
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/code/lsp/lspconfig.lua — LSP server configuration               ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  Neovim 0.11+ Native LSP API                                     │    ║
--- ║  │                                                                  │    ║
--- ║  │  vim.lsp.config("*", defaults)                                   │    ║
--- ║  │  │  Global capabilities for ALL servers:                         │    ║
--- ║  │  │  • blink.cmp capabilities (if available)                      │    ║
--- ║  │  │  • Completion: snippets, preselect, insert-replace, tags      │    ║
--- ║  │  │  • Folding: line-folding-only for nvim-ufo compatibility      │    ║
--- ║  │  │  • NO server-specific settings here (delegated to langs/*)    │    ║
--- ║  │  │                                                               │    ║
--- ║  │  vim.lsp.config(name, opts)                                      │    ║
--- ║  │  │  Per-server config from enabled langs/*.lua:                  │    ║
--- ║  │  │  • Only servers from settings.languages.enabled               │    ║
--- ║  │  │  • Disabled languages never reach opts.servers                │    ║
--- ║  │  │  • Each lang file contributes its server(s) via opts merge    │    ║
--- ║  │  │                                                               │    ║
--- ║  │  vim.lsp.enable(name)                                            │    ║
--- ║  │  │  Lazy per-filetype activation:                                │    ║
--- ║  │  │  • Does NOT start any server immediately                      │    ║
--- ║  │  │  • Registers server for auto-start on matching FileType       │    ║
--- ║  │  │  • Example: enable("lua_ls") → starts only on .lua files      │    ║
--- ║  │  │  • If you never open .lua, lua_ls never runs                  │    ║
--- ║  │  │                                                               │    ║
--- ║  │  mason-lspconfig                                                 │    ║
--- ║  │  │  • automatic_installation = false                             │    ║
--- ║  │  │  • Each langs/*.lua manages its own Mason installation        │    ║
--- ║  │  │  • Prevents installation without prerequisites                │    ║
--- ║  │  │                                                               │    ║
--- ║  │  LspAttach (universal)                                           │    ║
--- ║  │  │  Applied to ALL servers on attach:                            │    ║
--- ║  │  │  ├─ Navigation: gd, gD, gi, gr, gy, gK, K                     │    ║
--- ║  │  │  ├─ Code actions: <leader>ca, <leader>cA, <leader>cr          │    ║
--- ║  │  │  ├─ Format: <leader>cf (conform fallback to LSP)              │    ║
--- ║  │  │  ├─ Diagnostics: <leader>cd, [d, ]d, [e, ]e, [w, ]w           │    ║
--- ║  │  │  ├─ Workspace: <leader>cw, <leader>cW                         │    ║
--- ║  │  │  ├─ Inlay hints: auto-enable + <leader>uh toggle              │    ║
--- ║  │  │  ├─ Code lens: auto-refresh + <leader>cl run                  │    ║
--- ║  │  │  ├─ Document highlight: CursorHold highlight/clear            │    ║
--- ║  │  │  └─ Semantic tokens: disabled for tailwindcss, cssls          │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Capability resolution order:                                            ║
--- ║  1. vim.lsp.protocol.make_client_capabilities() (Neovim defaults)        ║
--- ║  2. blink.cmp.get_lsp_capabilities() (if blink loaded)                   ║
--- ║  3. Manual completion fallback (if blink not available)                  ║
--- ║  4. Folding range (always added for nvim-ufo)                            ║
--- ║                                                                          ║
--- ║  Important design decision:                                              ║
--- ║  • vim.lsp.config("*") contains ONLY capabilities, no server settings    ║
--- ║  • Server-specific settings (Lua, Rust, Go, etc.) live in langs/*.lua    ║
--- ║  • This prevents global settings from conflicting with per-server ones   ║
--- ║                                                                          ║
--- ║  Optimizations:                                                          ║
--- ║  • BufReadPost/BufNewFile/BufWritePre loading (not VeryLazy)             ║
--- ║  • vim.lsp.enable() is inherently lazy per filetype                      ║
--- ║  • No server runs until its filetype is opened                           ║
--- ║  • mason-lspconfig defers to langs/*.lua for installation control        ║
--- ║  • Semantic tokens selectively disabled (perf for CSS servers)           ║
--- ║  • Document highlight uses per-buffer augroups (clean detach)            ║
--- ║                                                                          ║
--- ║  Global keymaps (buffer-local, set on LspAttach):                        ║
--- ║    gd            Goto Definition                             (n)         ║
--- ║    gD            Goto Declaration                            (n)         ║
--- ║    gi            Goto Implementation                         (n)         ║
--- ║    gr            References                                  (n)         ║
--- ║    gy            Goto Type Definition                        (n)         ║
--- ║    gK            Signature Help                              (n)         ║
--- ║    K             Hover                                       (n)         ║
--- ║    <C-k>         Signature Help                              (i)         ║
--- ║    <leader>ca    Code Action                                 (n,v)       ║
--- ║    <leader>cA    Source Action                                (n)        ║
--- ║    <leader>cr    Rename                                      (n)         ║
--- ║    <leader>cf    Format                                      (n,v)       ║
--- ║    <leader>cd    Line Diagnostics                            (n)         ║
--- ║    [d / ]d       Prev/Next Diagnostic                        (n)         ║
--- ║    [e / ]e       Prev/Next Error                             (n)         ║
--- ║    [w / ]w       Prev/Next Warning                           (n)         ║
--- ║    <leader>cw    Workspace Folders                           (n)         ║
--- ║    <leader>cW    Add Workspace Folder                        (n)         ║
--- ║    <leader>uh    Toggle Inlay Hints                          (n)         ║
--- ║    <leader>cl    Run Code Lens                               (n)         ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

local settings = require("core.settings")
local icons = require("core.icons")
local augroup = require("core.utils").augroup

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════════

--- Servers for which semantic tokens are disabled.
--- These servers produce noisy or conflicting semantic highlights
--- that interfere with treesitter-based highlighting.
---@type string[]
local semantic_tokens_disabled = { "tailwindcss", "cssls" }

return {
	"neovim/nvim-lspconfig",

	-- ═══════════════════════════════════════════════════════════════════
	-- LAZY LOADING STRATEGY
	--
	-- BufReadPost + BufNewFile: LSP must be ready before the user
	-- starts editing. BufWritePre: ensures format-on-save works
	-- even if the buffer was opened in an unusual way.
	-- ═══════════════════════════════════════════════════════════════════
	event = { "BufReadPost", "BufNewFile", "BufWritePre" },

	dependencies = {
		"williamboman/mason.nvim",
		"williamboman/mason-lspconfig.nvim",
		{ "saghen/blink.cmp", optional = true },
	},

	---@class PluginLspOpts
	opts = {
		--- Server configs, deep-merged from enabled langs/*.lua.
		--- Keys are server names (e.g. "lua_ls"), values are server options.
		--- Only servers from enabled languages reach this table.
		---@type table<string, table>
		servers = {},
	},

	---@param _ table Plugin spec (unused)
	---@param opts PluginLspOpts Resolved options (servers from enabled langs)
	config = function(_, opts)
		local servers = opts.servers or {}
		local server_names = vim.tbl_keys(servers)

		-- ═══════════════════════════════════════════════════════════════
		-- CAPABILITIES (global defaults for ALL servers)
		--
		-- Resolution order:
		-- 1. Neovim defaults (make_client_capabilities)
		-- 2. blink.cmp enhanced capabilities (if loaded)
		-- 3. Manual completion fallback (if blink unavailable)
		-- 4. Folding range (always, for nvim-ufo compatibility)
		--
		-- IMPORTANT: No server-specific settings here.
		-- Server settings live in their respective langs/*.lua files.
		-- This prevents global settings from conflicting with
		-- per-server configurations (e.g., Lua.runtime.version).
		-- ═══════════════════════════════════════════════════════════════
		local capabilities = vim.lsp.protocol.make_client_capabilities()

		-- ── blink.cmp integration ────────────────────────────────────
		local blink_ok, blink = pcall(require, "blink.cmp")
		if blink_ok and blink.get_lsp_capabilities then
			capabilities = blink.get_lsp_capabilities(capabilities)
		else
			-- Manual fallback: ensure rich completion support
			-- even when blink.cmp is not installed or loaded yet
			capabilities.textDocument.completion = {
				completionItem = {
					documentationFormat = { "markdown", "plaintext" },
					snippetSupport = true,
					preselectSupport = true,
					insertReplaceSupport = true,
					labelDetailsSupport = true,
					deprecatedSupport = true,
					commitCharactersSupport = true,
					tagSupport = { valueSet = { 1 } },
					resolveSupport = {
						properties = {
							"documentation",
							"detail",
							"additionalTextEdits",
						},
					},
				},
			}
		end

		-- ── Folding range (nvim-ufo) ─────────────────────────────────
		capabilities.textDocument.foldingRange = {
			dynamicRegistration = false,
			lineFoldingOnly = true,
		}

		-- ── Apply global capabilities (NO server-specific settings) ──
		vim.lsp.config("*", {
			capabilities = capabilities,
		})

		-- ═══════════════════════════════════════════════════════════════
		-- PER-SERVER CONFIGURATION (only enabled languages)
		--
		-- opts.servers only contains servers from enabled languages
		-- because plugin_manager filters langs/*.lua by
		-- settings.languages.enabled before their specs reach lazy.nvim.
		--
		-- Each vim.lsp.config() call deep-merges with the global "*"
		-- config above, so per-server settings override globals.
		-- ═══════════════════════════════════════════════════════════════
		for name, server_opts in pairs(servers) do
			vim.lsp.config(name, server_opts)
		end

		-- ═══════════════════════════════════════════════════════════════
		-- MASON-LSPCONFIG — Server binary installation
		--
		-- automatic_installation is disabled because each langs/*.lua
		-- manages its own Mason installation with proper prerequisites
		-- (e.g., cargo for rust-analyzer, npm for tsserver).
		-- ═══════════════════════════════════════════════════════════════
		local mason_ok, mason_lspconfig = pcall(require, "mason-lspconfig")
		if mason_ok and #server_names > 0 then mason_lspconfig.setup({
			automatic_installation = false,
		}) end

		-- ═══════════════════════════════════════════════════════════════
		-- VIM.LSP.ENABLE — Register servers for lazy activation
		--
		-- This does NOT start any server immediately. Each server
		-- auto-starts when a buffer with a matching filetype is opened.
		-- Filetypes come from nvim-lspconfig's lsp/<name>.lua files.
		--
		-- Example: vim.lsp.enable("lua_ls")
		--   → lua_ls starts only when you open a .lua file
		--   → if you never open .lua, lua_ls never runs
		-- ═══════════════════════════════════════════════════════════════
		if #server_names > 0 then vim.lsp.enable(server_names) end

		-- ═══════════════════════════════════════════════════════════════
		-- LSPATTACH — Universal keymaps & behavior
		--
		-- Applied to ALL servers when they attach to a buffer.
		-- Buffer-local keymaps ensure they only work in LSP-enabled
		-- buffers. Capability checks gate features like inlay hints,
		-- code lens, and document highlight.
		-- ═══════════════════════════════════════════════════════════════
		vim.api.nvim_create_autocmd("LspAttach", {
			group = augroup("LspGlobalAttach"),
			desc = "LSP: keymaps, inlay hints, code lens, document highlight",
			callback = function(args)
				local client = vim.lsp.get_client_by_id(args.data.client_id)
				if not client then return end
				local bufnr = args.buf

				--- Set a buffer-local keymap with LSP context.
				---@param mode string|string[] Mode(s) for the keymap
				---@param lhs string Left-hand side (key sequence)
				---@param rhs string|function Right-hand side (command or function)
				---@param desc string Human-readable description (shown in which-key)
				local function map(mode, lhs, rhs, desc)
					vim.keymap.set(mode, lhs, rhs, {
						buffer = bufnr,
						desc = desc,
						silent = true,
					})
				end

				-- ── Navigation ───────────────────────────────────────
				map("n", "gd", vim.lsp.buf.definition, icons.ui.ArrowRight .. " Goto Definition")
				map("n", "gD", vim.lsp.buf.declaration, icons.ui.ArrowRight .. " Goto Declaration")
				map("n", "gi", vim.lsp.buf.implementation, icons.ui.ArrowRight .. " Goto Implementation")
				map("n", "gr", vim.lsp.buf.references, icons.ui.ArrowRight .. " References")
				map("n", "gy", vim.lsp.buf.type_definition, icons.ui.ArrowRight .. " Goto Type Definition")
				map("n", "gK", vim.lsp.buf.signature_help, icons.ui.Lightbulb .. " Signature Help")
				map("i", "<C-k>", vim.lsp.buf.signature_help, "Signature Help")
				map("n", "K", vim.lsp.buf.hover, icons.ui.Lightbulb .. " Hover")

				-- ── Code actions ─────────────────────────────────────
				map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, icons.ui.Lightbulb .. " Code Action")
				map("n", "<leader>cA", function()
					vim.lsp.buf.code_action({
						context = { only = { "source" }, diagnostics = {} },
					})
				end, icons.ui.Gear .. " Source Action")
				map("n", "<leader>cr", vim.lsp.buf.rename, icons.ui.Pencil .. " Rename")

				-- ── Format ───────────────────────────────────────────
				map({ "n", "v" }, "<leader>cf", function()
					local conform_ok, conform = pcall(require, "conform")
					if conform_ok then
						conform.format({ bufnr = bufnr, lsp_format = "fallback" })
					else
						vim.lsp.buf.format({ bufnr = bufnr })
					end
				end, icons.ui.Check .. " Format")

				-- ── Diagnostics ──────────────────────────────────────
				map("n", "<leader>cd", vim.diagnostic.open_float, icons.diagnostics.Info .. " Line Diagnostics")
				map("n", "[d", function()
					vim.diagnostic.jump({ count = -1, float = true })
				end, "Prev Diagnostic")
				map("n", "]d", function()
					vim.diagnostic.jump({ count = 1, float = true })
				end, "Next Diagnostic")
				map("n", "[e", function()
					vim.diagnostic.jump({
						count = -1,
						severity = vim.diagnostic.severity.ERROR,
						float = true,
					})
				end, "Prev Error")
				map("n", "]e", function()
					vim.diagnostic.jump({
						count = 1,
						severity = vim.diagnostic.severity.ERROR,
						float = true,
					})
				end, "Next Error")
				map("n", "[w", function()
					vim.diagnostic.jump({
						count = -1,
						severity = vim.diagnostic.severity.WARN,
						float = true,
					})
				end, "Prev Warning")
				map("n", "]w", function()
					vim.diagnostic.jump({
						count = 1,
						severity = vim.diagnostic.severity.WARN,
						float = true,
					})
				end, "Next Warning")

				-- ── Workspace ────────────────────────────────────────
				map("n", "<leader>cw", function()
					local folders = vim.lsp.buf.list_workspace_folders()
					if #folders > 0 then
						vim.notify(table.concat(folders, "\n"), vim.log.levels.INFO, { title = "LSP Workspace Folders" })
					else
						vim.notify("No workspace folders", vim.log.levels.WARN, { title = "LSP" })
					end
				end, icons.ui.Folder .. " Workspace Folders")
				map("n", "<leader>cW", vim.lsp.buf.add_workspace_folder, icons.ui.Plus .. " Add Workspace Folder")

				-- ── Inlay Hints ──────────────────────────────────────
				if client:supports_method("textDocument/inlayHint") then
					if settings:get("lsp.inlay_hints", true) and vim.api.nvim_buf_is_valid(bufnr) then
						vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
					end
					map("n", "<leader>uh", function()
						local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr })
						vim.lsp.inlay_hint.enable(not enabled, { bufnr = bufnr })
						vim.notify(
							string.format("%s Inlay hints %s", icons.ui.Lightbulb, enabled and "disabled" or "enabled"),
							vim.log.levels.INFO,
							{ title = "LSP" }
						)
					end, icons.ui.Lightbulb .. " Toggle Inlay Hints")
				end

				-- ── Code Lens ────────────────────────────────────────
				if client:supports_method("textDocument/codeLens") then
					vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "InsertLeave" }, {
						buffer = bufnr,
						callback = function()
							pcall(vim.lsp.codelens.refresh, { bufnr = bufnr })
						end,
					})
					map("n", "<leader>cl", vim.lsp.codelens.run, icons.ui.Play .. " Run Code Lens")
				end

				-- ── Document Highlight ───────────────────────────────
				if client:supports_method("textDocument/documentHighlight") then
					local hl_group = augroup("LspDocHighlight_" .. bufnr)
					vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
						group = hl_group,
						buffer = bufnr,
						callback = vim.lsp.buf.document_highlight,
					})
					vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
						group = hl_group,
						buffer = bufnr,
						callback = vim.lsp.buf.clear_references,
					})
				end

				-- ── Semantic Tokens (selective disable) ──────────────
				for _, disabled_server in ipairs(semantic_tokens_disabled) do
					if client.name == disabled_server then client.server_capabilities.semanticTokensProvider = nil end
				end
			end,
		})
	end,
}
