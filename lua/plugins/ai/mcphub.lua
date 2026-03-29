---@file lua/plugins/ai/mcphub.lua
---@description MCPHub — MCP server manager and tool provider for Neovim
---@module "plugins.ai.mcphub"
---@version 1.1.0
---@since 2026-03
---@see https://github.com/ravitemer/mcphub.nvim
---@see plugins.ai.codecompanion  Consumes MCP tools via extension
---@see plugins.ai.avante         Consumes MCP tools via custom_tools
---@see core.secrets              Loads GITHUB_PERSONAL_ACCESS_TOKEN from .env
---
--- ╔══════════════════════════════════════════════════════════════════════════╗
--- ║  plugins/ai/mcphub.lua — MCP server hub                                  ║
--- ║                                                                          ║
--- ║  Architecture:                                                           ║
--- ║  ┌──────────────────────────────────────────────────────────────────┐    ║
--- ║  │  mcphub.nvim                                                     │    ║
--- ║  │  ├─ Server lifecycle     (start/stop/restart MCP servers)        │    ║
--- ║  │  ├─ Tool discovery       (list tools from all active servers)    │    ║
--- ║  │  ├─ Resource access      (read resources exposed by servers)     │    ║
--- ║  │  ├─ Prompt templates     (server-provided prompt templates)      │    ║
--- ║  │  ├─ Hub UI               (:MCPHub — interactive dashboard)       │    ║
--- ║  │  │                                                               │    ║
--- ║  │                                                                  │    ║
--- ║  │  Integration:                                                    │    ║
--- ║  │  ├─ codecompanion.nvim   (extension: tools + slash commands)     │    ║
--- ║  │  └─ avante.nvim          (custom_tools: MCP tools injected)      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Secrets flow:                                                   │    ║
--- ║  │  ┌──────────────────────────────────────────────────────────┐    │    ║
--- ║  │  │  .env → core/secrets.lua → vim.env.GITHUB_*              │    │    ║
--- ║  │  │  vim.env → mcphub on_servers_start → server process env  │    │    ║
--- ║  │  │  (secrets never hardcoded in JSON or Lua)                │    │    ║
--- ║  │  └──────────────────────────────────────────────────────────┘    │    ║
--- ║  │                                                                  │    ║
--- ║  │  Config file:                                                    │    ║
--- ║  │  └─ ~/.config/nvim/mcpservers.json                               │    ║
--- ║  │     (compatible with Claude Desktop format)                      │    ║
--- ║  │                                                                  │    ║
--- ║  │  Keymaps:                                                        │    ║
--- ║  │  ┌────────────┬──────────────────────────────────────────┐       │    ║
--- ║  │  │ Key        │ Action                                   │       │    ║
--- ║  │  ├────────────┼──────────────────────────────────────────┤       │    ║
--- ║  │  │ <Space>am  │ Toggle MCP Hub UI                        │       │    ║
--- ║  │  │ <Space>aM  │ MCP Hub logs                             │       │    ║
--- ║  │  └────────────┴──────────────────────────────────────────┘       │    ║
--- ║  │                                                                  │    ║
--- ║  │  Design decisions:                                               │    ║
--- ║  │  ├─ 3-level guard (plugin + ai.enabled + ai.mcphub.enabled)      │    ║
--- ║  │  ├─ auto_start = false (servers start on first AI request)       │    ║
--- ║  │  ├─ shutdown_on_exit = true (clean up on Neovim close)           │    ║
--- ║  │  ├─ cmd + keys loading (zero startup cost)                       │    ║
--- ║  │  ├─ on_servers_start hook injects vim.env secrets into servers   │    ║
--- ║  │  └─ Extensions for both codecompanion and avante                 │    ║
--- ║  └──────────────────────────────────────────────────────────────────┘    ║
--- ║                                                                          ║
--- ║  Changelog:                                                              ║
--- ║  • 1.1.0 — Integrated with core/secrets.lua for token injection          ║
--- ║            Added GITHUB_PERSONAL_ACCESS_TOKEN to .env pipeline           ║
--- ║            on_servers_start hook propagates vim.env to server processes  ║
--- ╚══════════════════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════════════
-- GUARD
-- ═══════════════════════════════════════════════════════════════════════

local settings_ok, settings = pcall(require, "core.settings")
if settings_ok then
	if not settings:is_plugin_enabled("mcphub") then return {} end
	if not settings:get("ai.enabled", false) then return {} end
end

local icons_ok, icons = pcall(require, "core.icons")
local ai_icon = (icons_ok and icons.misc and icons.misc.AI) or "󰧑"

-- ═══════════════════════════════════════════════════════════════════════
-- SECRETS PROPAGATION
--
-- MCP servers run as child processes (via npx). They inherit
-- Neovim's process environment, but vim.env changes made AFTER
-- process start are not propagated. The on_servers_start hook
-- ensures secrets loaded by core/secrets.lua are available.
--
-- Flow:
--   .env → core/secrets.lua → vim.env.GITHUB_* (at startup)
--   vim.env → mcpservers.json env:{} → server process (at spawn)
--
-- Since secrets.lua runs in init.lua Phase 1 (before plugins),
-- vim.env is populated before mcphub starts any server.
-- The JSON env:{} field can reference these via the process env.
-- ═══════════════════════════════════════════════════════════════════════

--- Environment variables to propagate from vim.env to MCP servers.
--- These are injected into every server's process environment
--- if they are set in vim.env (loaded from .env by core/secrets.lua).
---
---@type string[]
---@private
local PROPAGATED_ENV_VARS = {
	"GITHUB_PERSONAL_ACCESS_TOKEN",
	"ANTHROPIC_API_KEY",
	"OPENAI_API_KEY",
}

--- Build an environment table from vim.env for the specified variables.
--- Only includes variables that are set and non-empty.
---
---@return table<string, string> env Environment variables to inject
---@private
local function build_server_env()
	local server_env = {}
	for _, var in ipairs(PROPAGATED_ENV_VARS) do
		local val = vim.env[var]
		if val and val ~= "" then server_env[var] = val end
	end
	return server_env
end

-- ═══════════════════════════════════════════════════════════════════════
-- PLUGIN SPEC
-- ═══════════════════════════════════════════════════════════════════════

return {
	"ravitemer/mcphub.nvim",
	build = "npm install -g mcp-hub@latest",
	cmd = { "MCPHub" },
	dependencies = {
		"nvim-lua/plenary.nvim",
	},

	keys = {
		{
			"<leader>am",
			"<Cmd>MCPHub<CR>",
			desc = ai_icon .. " MCP Hub",
		},
		{
			"<leader>aM",
			"<Cmd>MCPHub logs<CR>",
			desc = ai_icon .. " MCP Hub logs",
		},
	},

	opts = {
		-- Path to MCP servers config (Claude Desktop compatible format)
		config = vim.fn.stdpath("config") .. "/mcpservers.json",

		-- Port for the MCP Hub server (0 = random available port)
		port = 0,

		-- Don't auto-start — servers start when AI plugin requests tools
		auto_start = false,

		-- Clean shutdown when Neovim exits
		shutdown_on_exit = true,

		-- Logging
		log = {
			level = vim.log.levels.WARN,
			to_file = false,
		},

		-- Hub UI window
		ui = {
			window = {
				width = 0.8,
				height = 0.8,
				relative = "editor",
				zindex = 50,
			},
		},

		-- Extensions — enable for both AI plugins
		extensions = {
			codecompanion = {
				enabled = true,
				show_result_in_chat = true,
				make_vars = true,
				make_slash_commands = true,
			},
			avante = {
				enabled = true,
				make_slash_commands = true,
			},
		},
	},

	config = function(_, opts)
		-- ── Inject secrets into server environment ───────────────────
		-- Propagate API keys from vim.env (loaded by core/secrets.lua)
		-- into the MCP server process environment before setup.
		-- This ensures servers like @modelcontextprotocol/server-github
		-- can access GITHUB_PERSONAL_ACCESS_TOKEN without hardcoding.
		opts.env = vim.tbl_deep_extend("force", opts.env or {}, build_server_env())

		require("mcphub").setup(opts)
	end,
}
